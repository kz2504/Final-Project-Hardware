module frame_buffer #(
   parameter int FRAME_WIDTH  = 640,
   parameter int FRAME_HEIGHT = 480
) (
   input  logic        clk,
   input  logic        reset,
   input  logic        clear_req_toggle,
   input  logic        enable,

   input  logic        pclk,
   input  logic        href,
   input  logic        vsync,
   input  logic [7:0]  data,

   input  logic        index_write,
   input  logic [31:0] index_writedata,
   input  logic [31:0] frame_index,
   output logic [31:0] frame_data,
   output logic        done,
   output logic        active
);

   localparam int FRAME_PIXELS     = FRAME_WIDTH * FRAME_HEIGHT;
   localparam int FRAME_WORDS      = FRAME_PIXELS / 4;
   localparam int FRAME_WORD_BITS  = $clog2(FRAME_WORDS);
   localparam int FRAME_PIXEL_BITS = $clog2(FRAME_PIXELS);
   localparam logic [FRAME_PIXEL_BITS-1:0] LAST_FRAME_PIXEL =
      FRAME_PIXEL_BITS'(FRAME_PIXELS - 1);

   typedef enum logic [1:0] {
      STATE_WAIT_FRAME,
      STATE_CAPTURE
   } capture_state_t;

   logic        frame_index_valid;
   logic        write_index_valid;
   logic [FRAME_WORD_BITS-1:0] frame_rd_addr;
   logic [FRAME_WORD_BITS-1:0] write_index_addr;
   logic [FRAME_WORD_BITS-1:0] frame_ram_rd_addr;
   logic [31:0] frame_ram_wr_data;
   logic        frame_ram_wren;

   (* ramstyle = "M10K" *) logic [31:0] frame_ram [0:FRAME_WORDS-1];

   logic [2:0]  clear_req_sync;
   logic        clear_req_seen;
   logic        done_pclk;
   logic        done_sync;
   logic        enable_sync;
   logic        capture_enable_current;
   logic        capture_open_current;
   capture_state_t capture_state;
   logic        vsync_d;
   logic [1:0]  yuv_byte_phase;
   logic [1:0]  pixel_pack_phase;
   logic [23:0] pixel_pack_word;
   logic [FRAME_WORD_BITS-1:0]  frame_wr_addr;
   logic [FRAME_PIXEL_BITS-1:0] captured_pixels;

   assign frame_index_valid = frame_index < FRAME_WORDS;
   assign frame_rd_addr = frame_index_valid ? frame_index[FRAME_WORD_BITS-1:0] : '0;
   assign write_index_valid = index_writedata < FRAME_WORDS;
   assign write_index_addr = write_index_valid ? index_writedata[FRAME_WORD_BITS-1:0] : '0;
   assign frame_ram_rd_addr = index_write ? write_index_addr : frame_rd_addr;
   assign frame_ram_wr_data = { data, pixel_pack_word };
   assign frame_ram_wren =
      enable_sync && capture_state == STATE_CAPTURE && !vsync && href &&
      !yuv_byte_phase[0] && pixel_pack_phase == 2'd3;
   assign capture_enable_current = clear_req_seen ? enable : enable_sync;
   assign capture_open_current = !done_pclk || clear_req_seen;

   always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
         done        <= 1'b0;
         done_sync   <= 1'b0;
      end else begin
         done_sync   <= done_pclk;
         done        <= done_sync;
      end
   end

   always_ff @(posedge clk) begin
      frame_data <= frame_ram[frame_ram_rd_addr];
   end

   always_ff @(posedge pclk or posedge reset) begin
      if (reset) begin
         clear_req_sync   <= 3'b000;
         done_pclk        <= 1'b0;
         enable_sync      <= 1'b0;
         capture_state    <= STATE_WAIT_FRAME;
         vsync_d          <= 1'b0;
         yuv_byte_phase   <= 2'd0;
         pixel_pack_phase <= 2'd0;
         pixel_pack_word  <= 24'd0;
         frame_wr_addr    <= '0;
         captured_pixels  <= '0;
      end else begin
         clear_req_sync <= { clear_req_sync[1:0], clear_req_toggle };
         vsync_d        <= vsync;

         if (clear_req_seen) begin
            done_pclk <= 1'b0;
            if (capture_state != STATE_CAPTURE) begin
               enable_sync <= enable;
            end
         end

         case (capture_state)
            STATE_WAIT_FRAME: begin
               yuv_byte_phase <= 2'd0;

               if (capture_enable_current && capture_open_current && vsync_d && !vsync) begin
                  capture_state    <= STATE_CAPTURE;
                  pixel_pack_phase <= 2'd0;
                  pixel_pack_word  <= 24'd0;
                  frame_wr_addr    <= '0;
                  captured_pixels  <= '0;
               end
            end

            STATE_CAPTURE: begin
               if (vsync) begin
                  capture_state  <= STATE_WAIT_FRAME;
                  yuv_byte_phase <= 2'd0;
               end else if (href) begin
                  yuv_byte_phase <= yuv_byte_phase + 2'd1;

                  if (!yuv_byte_phase[0]) begin
                     case (pixel_pack_phase)
                        2'd0: pixel_pack_word[7:0]   <= data;
                        2'd1: pixel_pack_word[15:8]  <= data;
                        2'd2: pixel_pack_word[23:16] <= data;
                        default: begin
                           frame_wr_addr <= frame_wr_addr + 1'b1;
                        end
                     endcase

                     pixel_pack_phase <= pixel_pack_phase + 2'd1;

                     if (captured_pixels == LAST_FRAME_PIXEL) begin
                        done_pclk     <= 1'b1;
                        capture_state <= STATE_WAIT_FRAME;
                     end else begin
                        captured_pixels <= captured_pixels + 1'b1;
                     end
                  end
               end else begin
                  yuv_byte_phase <= 2'd0;
               end
            end

            default: begin
               capture_state <= STATE_WAIT_FRAME;
            end
         endcase
      end
   end

   always_ff @(posedge pclk) begin
      if (frame_ram_wren) begin
         frame_ram[frame_wr_addr] <= frame_ram_wr_data;
      end
   end

   assign clear_req_seen = clear_req_sync[2] ^ clear_req_sync[1];
   assign active = capture_state == STATE_CAPTURE;

endmodule
