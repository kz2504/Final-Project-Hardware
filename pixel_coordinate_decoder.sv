module pixel_coordinate_decoder #(
   parameter int FRAME_WIDTH  = 640,
   parameter int FRAME_HEIGHT = 480
) (
   input  logic       pclk,
   input  logic       reset,
   input  logic       clear,
   input  logic       href,
   input  logic       vsync,
   input  logic [7:0] data,

   output logic       pixel_valid,
   output logic [7:0] pixel_data,
   output logic [9:0] u_coord,
   output logic [8:0] v_coord,
   output logic       frame_done,
   output logic       active
);

   localparam int FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
   localparam int FRAME_PIXEL_BITS = $clog2(FRAME_PIXELS);
   localparam logic [FRAME_PIXEL_BITS-1:0] LAST_FRAME_PIXEL =
      FRAME_PIXEL_BITS'(FRAME_PIXELS - 1);
   localparam logic [9:0] LAST_U_COORD = 10'(FRAME_WIDTH - 1);
   localparam logic [8:0] LAST_V_COORD = 9'(FRAME_HEIGHT - 1);

   typedef enum logic [1:0] {
      STATE_WAIT_FRAME,
      STATE_CAPTURE,
      STATE_DONE
   } capture_state_t;

   capture_state_t capture_state;
   logic       vsync_d;
   logic [1:0] yuv_byte_phase;
   logic [9:0] u_count;
   logic [8:0] v_count;
   logic [FRAME_PIXEL_BITS-1:0] pixel_count;
   logic       current_is_y;

   assign current_is_y = capture_state == STATE_CAPTURE && href && !yuv_byte_phase[0];

   always_ff @(posedge pclk or posedge reset) begin
      if (reset) begin
         capture_state  <= STATE_WAIT_FRAME;
         vsync_d        <= 1'b0;
         yuv_byte_phase <= 2'd0;
         u_count        <= 10'd0;
         v_count        <= 9'd0;
         pixel_count    <= '0;
         pixel_valid    <= 1'b0;
         pixel_data     <= 8'd0;
         u_coord        <= 10'd0;
         v_coord        <= 9'd0;
         frame_done     <= 1'b0;
      end else begin
         vsync_d     <= vsync;
         pixel_valid <= current_is_y;
         pixel_data  <= data;
         u_coord     <= u_count;
         v_coord     <= v_count;
         frame_done  <= 1'b0;

         if (clear) begin
            capture_state  <= STATE_WAIT_FRAME;
            yuv_byte_phase <= 2'd0;
            u_count        <= 10'd0;
            v_count        <= 9'd0;
            pixel_count    <= '0;
            pixel_valid    <= 1'b0;
         end else begin
            case (capture_state)
               STATE_WAIT_FRAME: begin
                  yuv_byte_phase <= 2'd0;
                  u_count        <= 10'd0;
                  v_count        <= 9'd0;
                  pixel_count    <= '0;
                  pixel_valid    <= 1'b0;

                  if (vsync_d && !vsync) begin
                     capture_state <= STATE_CAPTURE;
                  end
               end

               STATE_CAPTURE: begin
                  if (vsync) begin
                     capture_state  <= STATE_WAIT_FRAME;
                     yuv_byte_phase <= 2'd0;
                     u_count        <= 10'd0;
                     v_count        <= 9'd0;
                     pixel_count    <= '0;
                     pixel_valid    <= 1'b0;
                  end else if (href) begin
                     yuv_byte_phase <= yuv_byte_phase + 2'd1;

                     if (current_is_y) begin
                        if (pixel_count == LAST_FRAME_PIXEL) begin
                           frame_done    <= 1'b1;
                           capture_state <= STATE_DONE;
                        end else begin
                           pixel_count <= pixel_count + 1'b1;
                        end

                        if (u_count == LAST_U_COORD) begin
                           u_count <= 10'd0;
                           if (v_count != LAST_V_COORD) begin
                              v_count <= v_count + 1'b1;
                           end
                        end else begin
                           u_count <= u_count + 1'b1;
                        end
                     end
                  end else begin
                     yuv_byte_phase <= 2'd0;
                  end
               end

               STATE_DONE: begin
                  pixel_valid <= 1'b0;
               end

               default: begin
                  capture_state <= STATE_WAIT_FRAME;
               end
            endcase
         end
      end
   end

   assign active = capture_state == STATE_CAPTURE;

endmodule
