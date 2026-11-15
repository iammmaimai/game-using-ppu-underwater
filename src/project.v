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
    wire [10:0] speed = ui_in[4] ? 11'd4 : 11'd2;
    wire moving = (ui_in[0] ^ ui_in[1]) | (ui_in[2] ^ ui_in[3]);
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
        end else if (frame_tick && ena) begin
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
    wire [5:0] color = display_d[1] ?
        (sprite_valid_d[1] ? sprite_color_d1 : bg_color) : 6'b000000;
    wire [1:0] red   = color[5:4];
    wire [1:0] green = color[3:2];
    wire [1:0] blue  = color[1:0];

    assign uo_out = {
        hsync_d[1], blue[0], green[0], red[0],
        vsync_d[1], blue[1], green[1], red[1]
    };
    assign uio_out = 8'b0;
    assign uio_oe = 8'b0;
    wire _unused_ok = &{ena, ui_in[7:5], uio_in};
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

`default_nettype wire
