/*
 * Register map, word addressed:
 *
 * Address  Register  Access  Meaning
 *   0      CONTROL   R/W     bit 0: DONE. Hardware sets; write 0 to clear.
 *   1      INDEX     R/W     Frame word index, 0 .. 19199.
 *   2      DATA      R       Four pixels packed as {p3, p2, p1, p0}.
 */

module thresholding(
   input  logic        clk,
   input  logic        reset,

   input  logic [31:0] writedata,
   input  logic        write,
   input  logic        chipselect,
   input  logic [1:0]  address,

   output logic [31:0] readdata,

   input  logic        camera_pclk,
   input  logic        camera_href,
   input  logic        camera_vsync,
   input  logic [7:0]  camera_data,

   output logic [9:0]  LEDR,
   output logic        GPIO1_CLK
);

   localparam int FRAME_WIDTH      = 320;
   localparam int FRAME_HEIGHT     = 240;
   localparam int FRAME_PIXELS     = FRAME_WIDTH * FRAME_HEIGHT;
   localparam int FRAME_WORDS      = FRAME_PIXELS / 4;
   localparam int FRAME_WORD_BITS  = $clog2(FRAME_WORDS);
   localparam int FRAME_PIXEL_BITS = $clog2(FRAME_PIXELS);
   localparam logic [FRAME_PIXEL_BITS-1:0] LAST_FRAME_PIXEL =
      FRAME_PIXEL_BITS'(FRAME_PIXELS - 1);

   localparam logic [1:0] REG_CONTROL = 2'd0;
   localparam logic [1:0] REG_INDEX   = 2'd1;
   localparam logic [1:0] REG_DATA    = 2'd2;

   typedef enum logic [1:0] {
      STATE_WAIT_FRAME,
      STATE_CAPTURE,
      STATE_DONE
   } capture_state_t;

   logic [31:0] frame_ram [0:FRAME_WORDS-1];

   logic [31:0] frame_index;
   logic [31:0] frame_rd_data;
   logic        frame_index_valid;
   logic        write_index_valid;
   logic [FRAME_WORD_BITS-1:0] frame_rd_addr;
   logic [FRAME_WORD_BITS-1:0] write_index_addr;

   logic        clk25;
   logic        done_meta;
   logic        done_clk;
   logic        clear_req_toggle;

   logic [2:0]  clear_req_sync;
   logic        clear_req_seen;
   logic        done_pclk;
   capture_state_t capture_state;
   logic        vsync_d;
   logic [1:0]  yuv_byte_phase;
   logic [1:0]  pixel_pack_phase;
   logic [23:0] pixel_pack_word;
   logic [FRAME_WORD_BITS-1:0]  frame_wr_addr;
   logic [FRAME_PIXEL_BITS-1:0] captured_pixels;

   assign frame_index_valid = frame_index < FRAME_WORDS;
   assign frame_rd_addr = frame_index_valid ? frame_index[FRAME_WORD_BITS-1:0] : '0;
   assign write_index_valid = writedata < FRAME_WORDS;
   assign write_index_addr = write_index_valid ? writedata[FRAME_WORD_BITS-1:0] : '0;

   always_ff @(posedge clk or posedge reset) begin
      if (reset) begin
         clk25            <= 1'b0;
         frame_index      <= 32'd0;
         frame_rd_data    <= 32'd0;
         done_meta        <= 1'b0;
         done_clk         <= 1'b0;
         clear_req_toggle <= 1'b0;
      end else begin
         clk25         <= ~clk25;
         done_meta     <= done_pclk;
         done_clk      <= done_meta;
         frame_rd_data <= frame_ram[frame_rd_addr];

         if (chipselect && write) begin
            unique case (address)
               REG_CONTROL: begin
                  if (!writedata[0]) begin
                     clear_req_toggle <= ~clear_req_toggle;
                  end
               end

               REG_INDEX: begin
                  frame_index   <= writedata;
                  frame_rd_data <= frame_ram[write_index_addr];
               end

               default: begin
               end
            endcase
         end
      end
   end

   always_ff @(posedge camera_pclk or posedge reset) begin
      if (reset) begin
         clear_req_sync   <= 3'b000;
         capture_state    <= STATE_WAIT_FRAME;
         vsync_d          <= 1'b0;
         yuv_byte_phase   <= 2'd0;
         pixel_pack_phase <= 2'd0;
         pixel_pack_word  <= 24'd0;
         frame_wr_addr    <= '0;
         captured_pixels  <= '0;
      end else begin
         clear_req_sync <= { clear_req_sync[1:0], clear_req_toggle };
         vsync_d        <= camera_vsync;

         if (clear_req_seen) begin
            capture_state    <= STATE_WAIT_FRAME;
            yuv_byte_phase   <= 2'd0;
            pixel_pack_phase <= 2'd0;
            pixel_pack_word  <= 24'd0;
            frame_wr_addr    <= '0;
            captured_pixels  <= '0;
         end else begin
            unique case (capture_state)
               STATE_WAIT_FRAME: begin
                  yuv_byte_phase <= 2'd0;

                  if (vsync_d && !camera_vsync) begin
                     capture_state    <= STATE_CAPTURE;
                     pixel_pack_phase <= 2'd0;
                     pixel_pack_word  <= 24'd0;
                     frame_wr_addr    <= '0;
                     captured_pixels  <= '0;
                  end
               end

               STATE_CAPTURE: begin
                  if (camera_vsync) begin
                     capture_state  <= STATE_WAIT_FRAME;
                     yuv_byte_phase <= 2'd0;
                  end else if (camera_href) begin
                     yuv_byte_phase <= yuv_byte_phase + 2'd1;

                     if (!yuv_byte_phase[0]) begin
                        unique case (pixel_pack_phase)
                           2'd0: pixel_pack_word[7:0]   <= camera_data;
                           2'd1: pixel_pack_word[15:8]  <= camera_data;
                           2'd2: pixel_pack_word[23:16] <= camera_data;
                           default: begin
                              frame_ram[frame_wr_addr] <= { camera_data, pixel_pack_word };
                              frame_wr_addr <= frame_wr_addr + 1'b1;
                           end
                        endcase

                        pixel_pack_phase <= pixel_pack_phase + 2'd1;

                        if (captured_pixels == LAST_FRAME_PIXEL) begin
                           capture_state <= STATE_DONE;
                        end else begin
                           captured_pixels <= captured_pixels + 1'b1;
                        end
                     end
                  end else begin
                     yuv_byte_phase <= 2'd0;
                  end
               end

               STATE_DONE: begin
               end

               default: begin
                  capture_state <= STATE_WAIT_FRAME;
               end
            endcase
         end
      end
   end

   assign clear_req_seen = clear_req_sync[2] ^ clear_req_sync[1];
   assign done_pclk = capture_state == STATE_DONE;

   always_comb begin
      unique case (address)
         REG_CONTROL: readdata = { 31'd0, done_clk };
         REG_INDEX:   readdata = frame_index;
         REG_DATA:    readdata = frame_index_valid ? frame_rd_data : 32'd0;
         default:     readdata = 32'd0;
      endcase
   end

   assign LEDR      = { 8'd0, capture_state == STATE_CAPTURE, done_clk };
   assign GPIO1_CLK = clk25;

endmodule
