`timescale 1ns/1ps
module diver_tb;
reg clk=0, rst_n=0, ena=1;
reg [7:0] buttons=0;
wire [7:0] out;
always #5 clk=~clk;
tt_um_vga_example dut(.clk(clk),.rst_n(rst_n),.ena(ena),.ui_in(buttons),.uo_out(out),.uio_in(8'd0),.uio_out(),.uio_oe());
task step;
begin
 @(negedge clk); force dut.x=0; force dut.y=480;
 @(negedge clk); release dut.x; release dut.y;
end
endtask
task check;
input condition;
input [255:0] label;
begin if (!condition) begin $display("FAIL: %s",label); $fatal(1); end end
endtask
integer i;
reg [7:0] tile;
initial begin
 repeat(3) @(negedge clk); rst_n=1;
 check(dut.player_x==640 && dut.player_y==224,"reset position");
 check(!dut.blocked(640,224),"spawn is clear");
 for(i=0;i<4800;i=i+1) begin
   tile=dut.map.mem[i];
   check(dut.terrain_map[i] == tile,"collision matches source map");
   dut.terrain_map[i]=0;
 end
 @(negedge clk); dut.player_x=624;
 buttons=2; step; check(dut.player_x==626 && dut.camera_x==322,"right and camera follow");
 buttons=1; step; check(dut.player_x==624 && dut.facing_left,"left and facing");
 buttons=8; step; check(dut.player_y==226,"down");
 buttons=4; step; check(dut.player_y==224,"up");
 buttons=3; step; check(dut.player_x==624,"opposites cancel");
 buttons=10; step; check(dut.player_x==626 && dut.player_y==226,"diagonal movement");
 buttons=26; step; check(dut.player_x==628 && dut.player_y==228,"input 4 does not change speed");
 ena=0; step; check(dut.player_x==628,"enable gates movement"); ena=1;
 buttons=10; for(i=0;i<800;i=i+1) step;
 check(dut.player_x==1248 && dut.player_y==928,"maximum world boundary");
 check(dut.camera_x==640 && dut.camera_y==480,"maximum camera boundary");
 buttons=5; for(i=0;i<800;i=i+1) step;
 check(dut.player_x==0 && dut.player_y==0,"minimum world boundary");
 check(dut.camera_x==0 && dut.camera_y==0,"minimum camera boundary");
 // Every original rock variant blocks; decorations remain swimmable.
 for(i=0;i<256;i=i+1)
   check(dut.solid_tile(i) == (i==128 || (i>=192 && i<=207)),"exact original asset tile IDs");
 // Controlled fixtures isolate collision behavior from map layout.
 @(negedge clk); dut.player_x=128; dut.player_y=128;
 // Right wall begins at x=160, spanning the diver's vertical bounds.
 dut.terrain_map[8*80+10]=192;
 dut.terrain_map[9*80+10]=192;
 dut.terrain_map[10*80+10]=192;
 buttons=10; step;
 check(dut.player_x==128 && dut.player_y==130,"wall blocks X, Y slides");
 // Floor begins at y=160; reset to exactly touching it.
 @(negedge clk); dut.player_x=128; dut.player_y=128;
 dut.terrain_map[8*80+10]=0;
 dut.terrain_map[9*80+10]=0;
 dut.terrain_map[10*80+8]=128;
 dut.terrain_map[10*80+9]=128;
 buttons=8; step;
 check(dut.player_y==128,"swim stops at sand floor");
 buttons=4; step;
 check(dut.player_y==126,"can swim away from floor");
 // Diagonal-only obstacle: neither axis alone overlaps initially.
 for(i=0;i<4800;i=i+1) dut.terrain_map[i]=0;
 @(negedge clk); dut.player_x=128; dut.player_y=128;
 dut.terrain_map[10*80+10]=192;
 buttons=10; step;
 check(dut.player_x==130 && dut.player_y==128,"diagonal corner cannot clip");
 // Middle tile of a 3-tile span must be checked, not only corners.
 for(i=0;i<4800;i=i+1) dut.terrain_map[i]=0;
 @(negedge clk); dut.player_x=130; dut.player_y=128;
 dut.terrain_map[10*80+9]=128;
 buttons=8; step;
 check(dut.player_y==128,"middle tile blocks wide overlap");
 // Blocking walls from the left and above.
 for(i=0;i<4800;i=i+1) dut.terrain_map[i]=0;
 @(negedge clk); dut.player_x=128; dut.player_y=128;
 dut.terrain_map[8*80+7]=192;
 buttons=1; step;
 check(dut.player_x==128,"left rock collision");
 dut.terrain_map[7*80+8]=192;
 buttons=4; step;
 check(dut.player_y==128,"ceiling rock collision");
 // Transparent border and visible mask pixel.
 force dut.sprite.sx=0; force dut.sprite.sy=0; #1;
 check(!dut.sprite_opaque,"transparent sprite border");
 force dut.sprite.sx=13; force dut.sprite.sy=6; #1;
 check(dut.sprite_opaque && dut.sprite_color==6'b101111,"mask pixel");
 release dut.sprite.sx; release dut.sprite.sy;
 $display("PASS: diver movement, fixed speed, opposing inputs, enable, world bounds, camera, sprite and terrain collision"); $finish;
end
endmodule
