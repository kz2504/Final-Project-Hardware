module camera_moment_pipeline #(
   parameter int FRAME_WIDTH = 640,
   parameter int FRAME_HEIGHT = 480
) (
   input logic clk,
   input logic reset,
   input logic clear_req_toggle,
   input logic [7:0] threshold_cfg,

   input logic pclk,
   input logic href,
   input logic vsync,
   input logic [7:0] data,

   output logic [31:0] area_result,
   output logic [31:0] u_result,
   output logic [31:0] v_result,
   output logic done,
   output logic active
);

   logic [2:0] clear_req_sync; //3-bit synchronizer
   logic clear_seen; //Edge detection on clear toggle from 3-bit synchronizer (pclk)
   logic clear_req_toggle_d; //Delayed clear_req_toggle for edge detection (clk)
   logic [7:0] threshold_pending; //Threshold value pending for next frame (CDC)
   logic threshold_update_sync;
   logic [7:0] threshold_active; //Active threshold, latched at frame start (pclk)

   logic pixel_valid;
   logic [7:0] pixel_data;
   logic [9:0] u_coord;
   logic [8:0] v_coord;
   logic frame_start_pulse;
   logic frame_done_pulse;
   logic foreground;

   logic [31:0] area_result_pclk;
   logic [31:0] u_result_pclk;
   logic [31:0] v_result_pclk;
   logic done_pclk;
   logic done_sync;
   logic done_sync_d;

   assign clear_seen = clear_req_sync[2] ^ clear_req_sync[1]; //One-cycle pulse on edge

   always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
         clear_req_toggle_d <= 1'b0;
         threshold_pending <= 8'd0;
      end else begin
         clear_req_toggle_d <= clear_req_toggle;
         if (clear_req_toggle_d != clear_req_toggle) begin
            threshold_pending <= threshold_cfg; //Update pending threshold in clk domain on done clear toggle
         end
      end
   end

   always_ff @(posedge pclk or posedge reset) begin
      if (reset) begin
         clear_req_sync <= 3'b000;
         threshold_update_sync <= 1'b0;
         threshold_active <= 8'd0;
      end else begin
         clear_req_sync <= { clear_req_sync[1:0], clear_req_toggle }; //Update 3-bit sync
         if (clear_seen) begin //Update active pclk threshold register on frame start if done cleared
            threshold_update_sync <= 1'b1; //Arm
         end
         if (frame_start_pulse) begin
            if (threshold_update_sync || clear_seen) begin //Set active threshold if armed or incoming clear_seen (latter is scary)
               threshold_active <= threshold_pending;
               threshold_update_sync <= 1'b0;
            end
         end
      end
   end

   pixel_coordinate_decoder #(
      .FRAME_WIDTH ( FRAME_WIDTH ),
      .FRAME_HEIGHT ( FRAME_HEIGHT )
   ) coordinate_decoder (
      .pclk ( pclk ),
      .reset ( reset ),
      .href ( href ),
      .vsync ( vsync ),
      .data ( data ),
      .pixel_valid ( pixel_valid ),
      .pixel_data ( pixel_data ),
      .u_coord ( u_coord ),
      .v_coord ( v_coord ),
      .frame_start ( frame_start_pulse ),
      .frame_done ( frame_done_pulse ),
      .active ( active )
   );

   assign foreground = pixel_valid && pixel_data >= threshold_active;

   moment_accumulators accumulator_bank (
      .pclk ( pclk ),
      .reset ( reset ),
      .clear ( clear_seen ),
      .pixel_valid ( pixel_valid ),
      .foreground ( foreground ),
      .u_coord ( u_coord ),
      .v_coord ( v_coord ),
      .frame_start ( frame_start_pulse ),
      .frame_done ( frame_done_pulse ),
      .area_result_pclk ( area_result_pclk ),
      .u_result_pclk ( u_result_pclk ),
      .v_result_pclk ( v_result_pclk ),
      .done_pclk ( done_pclk )
   );

   always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
         done <= 1'b0;
         done_sync <= 1'b0;
         done_sync_d <= 1'b0;
         area_result <= 32'd0;
         u_result <= 32'd0;
         v_result <= 32'd0;
      end else begin
         done_sync <= done_pclk;
         done <= done_sync;
         done_sync_d <= done_sync;

         if (done_sync && !done_sync_d) begin
            area_result <= area_result_pclk;
            u_result <= u_result_pclk;
            v_result <= v_result_pclk;
         end
      end
   end

endmodule
