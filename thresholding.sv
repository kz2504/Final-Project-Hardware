/*
 * Dummy Avalon memory-mapped peripheral for the thresholding block.
 *
 * Register map:
 *
 * Byte Offset  7 ... 0   Meaning
 *        0    |CONTROL|  Dummy control register
 */

module thresholding(
   input  logic       clk,
   input  logic       reset,
   input  logic [7:0] writedata,
   input  logic       write,
   input  logic       chipselect,
   input  logic [2:0] address,

   output logic [7:0] readdata,
   output logic [9:0] LEDR,
   output logic       GPIO1_31
);

   logic [7:0] control;
   logic       clk25;

   always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
         control <= 8'h00;
      end else if (chipselect && write && address == 3'h0) begin
         control <= writedata;
      end
   end

   always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
         clk25 <= 1'b0;
      end else begin
         clk25 <= ~clk25;
      end
   end

   assign readdata = (address == 3'h0) ? control : 8'h00;
   assign LEDR = 10'h3ff;
   assign GPIO1_31 = clk25;

endmodule
