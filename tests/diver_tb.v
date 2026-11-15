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
initial begin
 repeat(3) @(negedge clk); rst_n=1;
 check(dut.player_x==624 && dut.player_y==224,"reset position");
 buttons=2; step; check(dut.player_x==626 && dut.camera_x==322,"right and camera follow");
 buttons=1; step; check(dut.player_x==624 && dut.facing_left,"left and facing");
 buttons=8; step; check(dut.player_y==226,"down");
 buttons=4; step; check(dut.player_y==224,"up");
 buttons=3; step; check(dut.player_x==624,"opposites cancel");
 buttons=26; step; check(dut.player_x==628 && dut.player_y==228,"diagonal boost");
 ena=0; step; check(dut.player_x==628,"enable gates movement"); ena=1;
 buttons=26; for(i=0;i<400;i=i+1) step;
 check(dut.player_x==1248 && dut.player_y==928,"maximum world boundary");
 check(dut.camera_x==640 && dut.camera_y==480,"maximum camera boundary");
 buttons=21; for(i=0;i<400;i=i+1) step;
 check(dut.player_x==0 && dut.player_y==0,"minimum world boundary");
 check(dut.camera_x==0 && dut.camera_y==0,"minimum camera boundary");
 // Transparent border and visible mask pixel.
 force dut.sprite.sx=0; force dut.sprite.sy=0; #1;
 check(!dut.sprite_opaque,"transparent sprite border");
 force dut.sprite.sx=13; force dut.sprite.sy=6; #1;
 check(dut.sprite_opaque && dut.sprite_color==6'b101111,"mask pixel");
 release dut.sprite.sx; release dut.sprite.sy;
 $display("PASS: diver movement, boost, opposing inputs, enable, world bounds, camera and sprite"); $finish;
end
endmodule
