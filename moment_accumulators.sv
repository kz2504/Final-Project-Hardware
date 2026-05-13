module moment_accumulators(
   input logic pclk,
   input logic reset,
   input logic clear,
   input logic pixel_valid,
   input logic foreground,
   input logic [9:0] u_coord,
   input logic [8:0] v_coord,
   input logic frame_start,
   input logic frame_done,

   output logic [31:0] area_result_pclk,
   output logic [31:0] u_result_pclk,
   output logic [31:0] v_result_pclk,
   output logic done_pclk
);

   logic [31:0] area_accum;
   logic [31:0] u_accum;
   logic [31:0] v_accum;
   logic [31:0] area_next;
   logic [31:0] u_next;
   logic [31:0] v_next;
   logic publish_this_frame;

   assign area_next = area_accum + ((pixel_valid && foreground) ? 32'd1 : 32'd0);
   assign u_next = u_accum + ((pixel_valid && foreground) ? { 22'd0, u_coord } : 32'd0);
   assign v_next = v_accum + ((pixel_valid && foreground) ? { 23'd0, v_coord } : 32'd0);

   always_ff @(posedge pclk or posedge reset) begin
      if (reset) begin
         area_accum <= 32'd0;
         u_accum <= 32'd0;
         v_accum <= 32'd0;
         area_result_pclk <= 32'd0;
         u_result_pclk <= 32'd0;
         v_result_pclk <= 32'd0;
         done_pclk <= 1'b0;
         publish_this_frame <= 1'b0;
      end else begin
         if (clear) begin
            done_pclk <= 1'b0;
         end

         if (frame_start) begin
            area_accum <= 32'd0;
            u_accum <= 32'd0;
            v_accum <= 32'd0;
            publish_this_frame <= !done_pclk || clear;
         end else begin
            area_accum <= area_next;
            u_accum <= u_next;
            v_accum <= v_next;

            if (frame_done) begin
               if (publish_this_frame) begin
                  area_result_pclk <= area_next;
                  u_result_pclk <= u_next;
                  v_result_pclk <= v_next;
                  done_pclk <= 1'b1;
               end
            end
         end
      end
   end

endmodule
