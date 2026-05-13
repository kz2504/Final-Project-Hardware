/*
 * Top-level image processing peripheral.
 *
 * Register map, word addressed:
 *
 * Address  Register  Access  Meaning
 *   0      AREA_A    R       Camera A foreground area
 *   1      U_A       R       Camera A foreground u/x moment sum
 *   2      V_A       R       Camera A foreground v/y moment sum
 *   3      AREA_B    R       Camera B foreground area
 *   4      U_B       R       Camera B foreground u/x moment sum
 *   5      V_B       R       Camera B foreground v/y moment sum
 *   6      DONE      R/W     bit 0: A, bit 1: B, bit 2: frame buffer
 *   7      CONTROL   R/W     [1:0] frame source: 0 none, 1 A, 2 B
 *                            [15:8] threshold A, [23:16] threshold B
 *   8      FB_INDEX  R/W     Frame buffer word index, 0 .. 76799
 *   9      FB_DATA   R       Four pixels packed as {p3, p2, p1, p0}
 */

module imgproc(
   input logic clk,
   input logic reset,

   input logic [31:0] writedata,
   input logic write,
   input logic chipselect,
   input logic [3:0] address,

   output logic [31:0] readdata,

   input logic a_pclk,
   input logic a_href,
   input logic a_vsync,
   input logic [7:0] a_data,
   output logic a_xclk,

   input logic b_pclk,
   input logic b_href,
   input logic b_vsync,
   input logic [7:0] b_data,
   output logic b_xclk,

   output logic [9:0] leds
);

   localparam int FRAME_WIDTH = 640;
   localparam int FRAME_HEIGHT = 480;

   typedef enum logic [3:0] {
      REG_AREA_A = 4'd0,
      REG_U_A = 4'd1,
      REG_V_A = 4'd2,
      REG_AREA_B = 4'd3,
      REG_U_B = 4'd4,
      REG_V_B = 4'd5,
      REG_DONE = 4'd6,
      REG_CONTROL = 4'd7,
      REG_FB_INDEX = 4'd8,
      REG_FB_DATA = 4'd9
   } register_address_t; 

   typedef enum logic [1:0] {
      STORE_NONE = 2'd0,
      STORE_A = 2'd1,
      STORE_B = 2'd2
   } frame_store_select_t;

   logic clk25;
   logic [31:0] control;
   logic [31:0] frame_index;
   frame_store_select_t frame_store_select;

   logic a_clear_toggle;
   logic b_clear_toggle;
   logic frame_clear_toggle;

   logic [31:0] a_area;
   logic [31:0] a_u_sum;
   logic [31:0] a_v_sum;
   logic a_done;
   logic a_active;

   logic [31:0] b_area;
   logic [31:0] b_u_sum;
   logic [31:0] b_v_sum;
   logic b_done;
   logic b_active;

   logic frame_index_write;
   logic [31:0] frame_data;
   logic frame_done;
   logic frame_active;

   logic selected_pclk;
   logic selected_href;
   logic selected_vsync;
   logic [7:0] selected_data;
   logic frame_store_enable;
   register_address_t register_address;

   assign register_address = register_address_t'(address);
   assign frame_index_write = chipselect && write && (register_address == REG_FB_INDEX); //Combinational RAM read index update flag to avoid one-cycle delay
   assign frame_store_enable = frame_store_select != STORE_NONE;

   function automatic frame_store_select_t decode_frame_store(input logic [1:0] value);
      case (value)
         STORE_A: decode_frame_store = STORE_A;
         STORE_B: decode_frame_store = STORE_B;
         default: decode_frame_store = STORE_NONE;
      endcase
   endfunction

   always_comb begin
      case (frame_store_select)
         STORE_A: begin
            selected_pclk = a_pclk;
            selected_href = a_href;
            selected_vsync = a_vsync;
            selected_data = a_data;
         end

         STORE_B: begin
            selected_pclk = b_pclk;
            selected_href = b_href;
            selected_vsync = b_vsync;
            selected_data = b_data;
         end

         default: begin
            selected_pclk = a_pclk;
            selected_href = a_href;
            selected_vsync = a_vsync;
            selected_data = a_data;
         end
      endcase
   end

   always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
         clk25 <= 1'b0;
         control <= 32'd0;
         frame_index <= 32'd0;
         frame_store_select <= STORE_NONE;
         a_clear_toggle <= 1'b0;
         b_clear_toggle <= 1'b0;
         frame_clear_toggle <= 1'b0;
      end else begin
         clk25 <= ~clk25;

         if (chipselect && write) begin
            case (register_address)
               REG_CONTROL: begin
                  control <= writedata;
               end

               REG_DONE: begin
                  if (!writedata[0]) begin
                     a_clear_toggle <= ~a_clear_toggle; //Generate toggle flags for done clear
                  end
                  if (!writedata[1]) begin
                     b_clear_toggle <= ~b_clear_toggle;
                  end
                  if (!writedata[2]) begin
                     frame_store_select <= decode_frame_store(control[1:0]);
                     frame_clear_toggle <= ~frame_clear_toggle;
                  end
               end

               REG_FB_INDEX: begin
                  frame_index <= writedata;
               end

               default: begin
               end
            endcase
         end
      end
   end

   camera_moment_pipeline #(
      .FRAME_WIDTH ( FRAME_WIDTH ),
      .FRAME_HEIGHT ( FRAME_HEIGHT )
   ) camera_a_moments (
      .clk ( clk ),
      .reset ( reset ),
      .clear_req_toggle ( a_clear_toggle ),
      .threshold_cfg ( control[15:8] ),
      .pclk ( a_pclk ),
      .href ( a_href ),
      .vsync ( a_vsync ),
      .data ( a_data ),
      .area_result ( a_area ),
      .u_result ( a_u_sum ),
      .v_result ( a_v_sum ),
      .done ( a_done ),
      .active ( a_active )
   );

   camera_moment_pipeline #(
      .FRAME_WIDTH ( FRAME_WIDTH ),
      .FRAME_HEIGHT ( FRAME_HEIGHT )
   ) camera_b_moments (
      .clk ( clk ),
      .reset ( reset ),
      .clear_req_toggle ( b_clear_toggle ),
      .threshold_cfg ( control[23:16] ),
      .pclk ( b_pclk ),
      .href ( b_href ),
      .vsync ( b_vsync ),
      .data ( b_data ),
      .area_result ( b_area ),
      .u_result ( b_u_sum ),
      .v_result ( b_v_sum ),
      .done ( b_done ),
      .active ( b_active )
   );

   frame_buffer #(
      .FRAME_WIDTH ( FRAME_WIDTH ),
      .FRAME_HEIGHT ( FRAME_HEIGHT )
   ) debug_frame_buffer (
      .clk ( clk ),
      .reset ( reset ),
      .clear_req_toggle ( frame_clear_toggle ),
      .enable ( frame_store_enable ),
      .pclk ( selected_pclk ),
      .href ( selected_href ),
      .vsync ( selected_vsync ),
      .data ( selected_data ),
      .index_write ( frame_index_write ),
      .index_writedata ( writedata ),
      .frame_index ( frame_index ),
      .frame_data ( frame_data ),
      .done ( frame_done ),
      .active ( frame_active )
   );

   always_comb begin
      case (register_address)
         REG_AREA_A: readdata = a_area;
         REG_U_A: readdata = a_u_sum;
         REG_V_A: readdata = a_v_sum;
         REG_AREA_B: readdata = b_area;
         REG_U_B: readdata = b_u_sum;
         REG_V_B: readdata = b_v_sum;
         REG_DONE: readdata = { 29'd0, frame_done, b_done, a_done };
         REG_CONTROL: readdata = control;
         REG_FB_INDEX: readdata = frame_index;
         REG_FB_DATA: readdata = frame_data;
         default: readdata = 32'd0;
      endcase
   end

   assign a_xclk = clk25;
   assign b_xclk = clk25;
   assign leds = {
      1'b0,
      !reset,
      frame_store_select,
      frame_active,
      b_active,
      a_active,
      frame_done,
      b_done,
      a_done
   };

endmodule
