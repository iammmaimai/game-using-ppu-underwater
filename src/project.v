/*
 * Controller-driven diver and scrolling underwater background for Tiny Tapeout VGA Playground.
 * Architecture follows the course slides:
 *   VGA (x + camera_x,y + camera_y) -> Map ROM -> BG tile ROM -> RGB222
 * The diver swims through the world and the camera follows.
 */
`default_nettype none

module tt_um_vga_example (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire hsync;
    wire vsync;
    wire display_on;
    wire [9:0] x;
    wire [9:0] y;

    hvsync_generator sync (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(display_on),
        .hpos(x),
        .vpos(y)
    );

    // Active-high directional controller; opposite inputs cancel.
    // Update in vertical blank so sprite/camera changes cannot tear a frame.
    wire frame_tick = (x == 10'd0 && y == 10'd480);
    reg [10:0] player_x, player_y;
    reg facing_left;
    reg [3:0] swim_phase;
    wire [10:0] speed = 11'd2;
    wire moving = (ui_in[0] ^ ui_in[1]) | (ui_in[2] ^ ui_in[3]);
    // Two-state game: collect all three coins, then reset to play again.
    localparam PLAYING = 1'b0, WON = 1'b1;
    reg game_state;
    reg [2:0] collected;
    reg [2:0] collected_next;
    wire [1:0] coin_count = {1'b0, collected[0]} +
                            {1'b0, collected[1]} + {1'b0, collected[2]};
    function [10:0] coin_x;
        input integer index;
        begin
            case (index)
                0: coin_x = 11'd320;
                1: coin_x = 11'd960;
                default: coin_x = 11'd352;
            endcase
        end
    endfunction
    function [10:0] coin_y;
        input integer index;
        begin
            case (index)
                0: coin_y = 11'd128;
                1: coin_y = 11'd448;
                default: coin_y = 11'd832;
            endcase
        end
    endfunction
    integer ci;
    always @* begin
        collected_next = collected;
        for (ci = 0; ci < 3; ci = ci + 1)
            if (next_x < coin_x(ci) + 11'd16 && next_x + 11'd32 > coin_x(ci) &&
                next_y < coin_y(ci) + 11'd16 && next_y + 11'd32 > coin_y(ci))
                collected_next[ci] = 1'b1;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            game_state <= PLAYING;
            collected <= 3'b000;
        end else if (frame_tick && ena && game_state == PLAYING) begin
            collected <= collected_next;
            if (&collected_next) game_state <= WON;
        end
    end
    // Full 32x32 diver bounds against the ORIGINAL Seabed Sand and
    // Rocky Seabed tiles in the same map.mem used by the renderer.
    // A non-aligned 32px box can overlap three tiles on each axis.
    reg [7:0] terrain_map [0:4799];
    initial $readmemh("../data/map.mem", terrain_map);
    function solid_tile;
        input [7:0] tile;
        begin
            // 128: assets/seabed-sand.png
            // 192..207: transformed quadrants of assets/rocky-seabed.png
            solid_tile = tile == 8'd128 ||
                         (tile >= 8'd192 && tile <= 8'd207);
        end
    endfunction
    function blocked;
        input [10:0] px, py;
        integer tx, ty, ix, iy;
        begin
            blocked = 1'b0;
            for (iy = 0; iy < 3; iy = iy + 1)
                for (ix = 0; ix < 3; ix = ix + 1) begin
                    tx = (px >> 4) + ix;
                    ty = (py >> 4) + iy;
                    if (tx <= ((px + 11'd31) >> 4) &&
                        ty <= ((py + 11'd31) >> 4)) begin
                        if (tx >= 80 || ty >= 60) blocked = 1'b1;
                        else if (solid_tile(terrain_map[ty * 80 + tx])) blocked = 1'b1;
                    end
                end
        end
    endfunction
    reg [10:0] candidate_x, candidate_y, next_x, next_y;
    always @* begin
        candidate_x = player_x;
        candidate_y = player_y;
        if (ui_in[1] && !ui_in[0])
            candidate_x = (player_x + speed > 11'd1248) ? 11'd1248 : player_x + speed;
        else if (ui_in[0] && !ui_in[1])
            candidate_x = (player_x < speed) ? 11'd0 : player_x - speed;
        if (ui_in[3] && !ui_in[2])
            candidate_y = (player_y + speed > 11'd928) ? 11'd928 : player_y + speed;
        else if (ui_in[2] && !ui_in[3])
            candidate_y = (player_y < speed) ? 11'd0 : player_y - speed;
        // Resolve X first, then Y at the accepted X position. This prevents
        // diagonal corner clipping and allows sliding along a blocked wall.
        next_x = blocked(candidate_x, player_y) ? player_x : candidate_x;
        next_y = blocked(next_x, candidate_y) ? player_y : candidate_y;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            player_x <= 11'd640;
            player_y <= 11'd224;
            facing_left <= 1'b0;
            swim_phase <= 4'd0;
        end else if (frame_tick && ena && game_state == PLAYING) begin
            if (moving) swim_phase <= swim_phase + 1'b1;
            player_x <= next_x;
            player_y <= next_y;
            if (ui_in[1] && !ui_in[0]) facing_left <= 1'b0;
            else if (ui_in[0] && !ui_in[1]) facing_left <= 1'b1;
        end
    end
    // Keep the diver centered until the viewport reaches a world edge.
    wire [9:0] camera_x = player_x < 11'd304 ? 10'd0 :
                             player_x > 11'd944 ? 10'd640 : player_x - 11'd304;
    wire [10:0] camera_y = player_y < 11'd224 ? 11'd0 :
                              player_y > 11'd704 ? 11'd480 : player_y - 11'd224;

    // Fixed 1280x960 world (2x2 screens); camera selects a 640x480 viewport.
    wire [10:0] world_x = {1'b0, x} + {1'b0, camera_x};
    wire [10:0] world_y = {1'b0, y} + camera_y;
    wire [6:0] map_x = world_x[10:4];
    wire [6:0] map_y = world_y[10:4];
    wire [3:0] tile_x = world_x[3:0];
    wire [3:0] tile_y = world_y[3:0];

    wire [7:0] tile_index;
    map_rom map (
        .clk(clk),
        .map_x(map_x),
        .map_y(map_y),
        .tile(tile_index)
    );

    // Preserve the pixel-within-tile coordinates while Map ROM is reading.
    reg [3:0] tile_x_d;
    reg [3:0] tile_y_d;
    always @(posedge clk) begin
        tile_x_d <= tile_x;
        tile_y_d <= tile_y;
    end

    wire [5:0] bg_color;
    bg_rom tiles (
        .clk(clk),
        .tile(tile_index),
        .offset_x(tile_x_d),
        .offset_y(tile_y_d),
        .color(bg_color)
    );

    // Match VGA control signals to the two registered ROM stages.
    reg [1:0] hsync_d;
    reg [1:0] vsync_d;
    reg [1:0] display_d;
    always @(posedge clk) begin
        if (!rst_n) begin
            hsync_d <= 2'b11;
            vsync_d <= 2'b11;
            display_d <= 2'b00;
        end else begin
            hsync_d <= {hsync_d[0], hsync};
            vsync_d <= {vsync_d[0], vsync};
            display_d <= {display_d[0], display_on};
        end
    end

    // Original 16x16 sprite scaled 2x; index zero is transparent.
    wire sprite_inside = world_x >= player_x && world_x < player_x + 11'd32 &&
                         world_y >= player_y && world_y < player_y + 11'd32;
    wire [10:0] sprite_dx = world_x - player_x;
    wire [10:0] sprite_dy = world_y - player_y;
    wire [3:0] sprite_sx = facing_left ? 4'd15 - sprite_dx[4:1] : sprite_dx[4:1];
    wire [5:0] sprite_color;
    wire sprite_opaque;
    diver_sprite sprite (.sx(sprite_sx), .sy(sprite_dy[4:1]),
        .kick(swim_phase[3]), .color(sprite_color), .opaque(sprite_opaque));
    reg [5:0] sprite_color_d0, sprite_color_d1;
    reg [1:0] sprite_valid_d;
    always @(posedge clk) begin
        if (!rst_n) begin
            sprite_color_d0 <= 0;
            sprite_color_d1 <= 0;
            sprite_valid_d <= 0;
        end else begin
            sprite_color_d0 <= sprite_color;
            sprite_color_d1 <= sprite_color_d0;
            sprite_valid_d <= {sprite_valid_d[0], sprite_inside && sprite_opaque};
        end
    end
    // Coins use world coordinates; HUD uses screen coordinates.
    reg coin_visible;
    reg [5:0] coin_color;
    integer draw_coin, dx, dy;
    always @* begin
        coin_visible = 1'b0;
        coin_color = 6'b111100;
        dx = 0;
        dy = 0;
        for (draw_coin = 0; draw_coin < 3; draw_coin = draw_coin + 1) begin
            if (!collected[draw_coin] && world_x >= coin_x(draw_coin) &&
                world_x < coin_x(draw_coin) + 11'd16 &&
                world_y >= coin_y(draw_coin) && world_y < coin_y(draw_coin) + 11'd16) begin
                dx = world_x - coin_x(draw_coin);
                dy = world_y - coin_y(draw_coin);
                // Stepped circular silhouette and a bright central glint.
                if ((dy >= 4 && dy < 12) || (dx >= 4 && dx < 12 && dy >= 1 && dy < 15)) begin
                    coin_visible = 1'b1;
                    coin_color = (dx >= 6 && dx <= 8 && dy >= 4 && dy <= 10)
                                 ? 6'b111110 : 6'b111000;
                end
            end
        end
    end
    wire hud_visible;
    wire [5:0] hud_color;
    game_hud hud (.x(x), .y(y), .count(coin_count), .won(game_state == WON),
                  .visible(hud_visible), .color(hud_color));
    // Delay overlays by the same two clocks as the background and diver.
    reg [1:0] coin_valid_d, hud_valid_d;
    reg [5:0] coin_color_d0, coin_color_d1, hud_color_d0, hud_color_d1;
    always @(posedge clk) begin
        if (!rst_n) begin
            coin_valid_d <= 0;
            hud_valid_d <= 0;
            coin_color_d0 <= 0;
            coin_color_d1 <= 0;
            hud_color_d0 <= 0;
            hud_color_d1 <= 0;
        end else begin
            coin_valid_d <= {coin_valid_d[0], coin_visible};
            hud_valid_d <= {hud_valid_d[0], hud_visible};
            coin_color_d0 <= coin_color;
            coin_color_d1 <= coin_color_d0;
            hud_color_d0 <= hud_color;
            hud_color_d1 <= hud_color_d0;
        end
    end
    wire [5:0] color = !display_d[1] ? 6'b000000 :
        hud_valid_d[1] ? hud_color_d1 :
        sprite_valid_d[1] ? sprite_color_d1 :
        coin_valid_d[1] ? coin_color_d1 : bg_color;
    wire [1:0] red   = color[5:4];
    wire [1:0] green = color[3:2];
    wire [1:0] blue  = color[1:0];

    assign uo_out = {
        hsync_d[1], blue[0], green[0], red[0],
        vsync_d[1], blue[1], green[1], red[1]
    };
    assign uio_out = 8'b0;
    assign uio_oe = 8'b0;
    wire _unused_ok = &{ena, ui_in[7:4], uio_in};
endmodule

// Fixed 80x60 tile map: exactly four screens arranged as a 2x2 world.
// This is a synchronous ROM exactly like the Map ROM in the course slides.
module map_rom (
    input  wire       clk,
    input  wire [6:0] map_x,
    input  wire [6:0] map_y,
    output reg  [7:0] tile
);
    (* rom_style = "block" *) reg [7:0] mem [0:4799];
    wire [12:0] address = map_y * 13'd80 + map_x;

    initial begin
        $readmemh("../data/map.mem", mem);
    end

    always @(posedge clk)
        tile <= (map_x < 7'd80 && map_y < 7'd60) ? mem[address] : 8'd0;
endmodule

// One unified 256-tile BG ROM: 256 tiles x 16 x 16 pixels.
// Tile indices 0..59: dithered ocean depth.
// Tile indices 64..123: dithered light-shaft variants.
// Tile 128: Seabed Sand, 129: Kelp Forest, 130: Coral Reef,
// Tile 131: Shipwreck, 132..191: Bubble Trail over each ocean depth.
// Tile indices 192..207: 16 Rocky Seabed wall variants made from four
// quadrants with horizontal, vertical, and 180-degree transformations.
module bg_rom (
    input  wire       clk,
    input  wire [7:0] tile,
    input  wire [3:0] offset_x,
    input  wire [3:0] offset_y,
    output reg  [5:0] color
);
    (* rom_style = "block" *) reg [5:0] mem [0:65535];
    wire [15:0] address = {tile, offset_y, offset_x};

    initial begin
        $readmemh("../data/bg-rom.mem", mem);
    end

    always @(posedge clk)
        color <= mem[address];
endmodule


module diver_sprite (
    input wire [3:0] sx, sy,
    input wire kick,
    output reg [5:0] color,
    output wire opaque
);
    reg [63:0] row;
    reg [3:0] pixel;
    always @* begin
        case (sy)
            4'd0: row = 64'h0000000000000000;
            4'd1: row = 64'h0000000000000000;
            4'd2: row = 64'h0000000333000000;
            4'd3: row = 64'h0000003111300000;
            4'd4: row = 64'h0000003111301110;
            4'd5: row = 64'h0000003111134451;
            4'd6: row = 64'h0001100122155541;
            4'd7: row = 64'h0013311222216611;
            4'd8: row = 64'h0133112222221110;
            4'd9: row = 64'h0011112222221100;
            4'd10: row = 64'h0000011222211000;
            4'd11: row = 64'h0003331111110000;
            4'd12: row = 64'h0033310001133000;
            4'd13: row = 64'h0001100000133300;
            4'd14: row = 64'h0000000000011000;
            4'd15: row = 64'h0000000000000000;
            default: row = 64'd0;
        endcase
        // Alternate the fins to give movement a small swimming kick.
        if (kick && sy == 4'd12) row = 64'h0001100001333000;
        if (kick && sy == 4'd13) row = 64'h0033300000110000;
        pixel = (row >> ((4'd15 - sx) * 4)) & 4'hf;
        case (pixel)
            1: color = 6'b000001;
            2: color = 6'b000110;
            3: color = 6'b111100;
            4: color = 6'b001011;
            5: color = 6'b101111;
            6: color = 6'b111001;
            default: color = 6'b000000;
        endcase
    end
    assign opaque = pixel != 0;
endmodule

// Small 5x7 font scaled 4x. Always show N/3; show YOU WIN after collection.
module game_hud (
    input wire [9:0] x, y,
    input wire [1:0] count,
    input wire won,
    output reg visible,
    output reg [5:0] color
);
    function [34:0] glyph;
        input [7:0] ch;
        begin
            case (ch)
                "0": glyph = 35'b01110_10001_10011_10101_11001_10001_01110;
                "1": glyph = 35'b00100_01100_00100_00100_00100_00100_01110;
                "2": glyph = 35'b01110_10001_00001_00010_00100_01000_11111;
                "3": glyph = 35'b11110_00001_00001_01110_00001_00001_11110;
                "/": glyph = 35'b00001_00001_00010_00100_01000_10000_10000;
                "Y": glyph = 35'b10001_10001_01010_00100_00100_00100_00100;
                "O": glyph = 35'b01110_10001_10001_10001_10001_10001_01110;
                "U": glyph = 35'b10001_10001_10001_10001_10001_10001_01110;
                "W": glyph = 35'b10001_10001_10001_10101_10101_10101_01010;
                "I": glyph = 35'b01110_00100_00100_00100_00100_00100_01110;
                "N": glyph = 35'b10001_11001_11001_10101_10011_10011_10001;
                default: glyph = 35'd0;
            endcase
        end
    endfunction
    integer gx, gy, column, letter;
    reg [7:0] character;
    reg [34:0] bits;
    always @* begin
        visible = 1'b0;
        color = 6'b000001;
        gx = 0; gy = 0; column = 0; letter = 0;
        character = " "; bits = 0;
        if (x >= 8 && x < 88 && y >= 8 && y < 44) begin
            visible = 1'b1;
            if (x >= 12 && x < 84 && y >= 12 && y < 40) begin
                gx = (x - 12) >> 2;
                gy = (y - 12) >> 2;
                case (gx / 6)
                    0: character = "0" + {6'b0, count};
                    1: character = "/";
                    2: character = "3";
                    default: character = " ";
                endcase
            end
        end else if (won && x >= 232 && x < 408 && y >= 218 && y < 262) begin
            visible = 1'b1;
            if (x >= 236 && x < 404 && y >= 226 && y < 254) begin
                gx = (x - 236) >> 2;
                gy = (y - 226) >> 2;
                case (gx / 6)
                    0: character = "Y";
                    1: character = "O";
                    2: character = "U";
                    4: character = "W";
                    5: character = "I";
                    6: character = "N";
                    default: character = " ";
                endcase
            end
        end
        column = gx % 6;
        bits = glyph(character);
        if (visible && column < 5 && bits[34 - gy * 5 - column]) color = 6'b111100;
    end
endmodule

`default_nettype wire
