`timescale 1ns / 1ps

//==============================================================================
// Assignment 3: CNN Address Generation & Read-Control Block
// Verilog-2001 Standard (IEEE 1364-2001)
//
// Specification:
//   - Input SRAM: 4 banks, each 256x64 Bytes, 8-bit read/write port per bank.
//   - Image dimensions: 256 x 256 pixels, 8-bit per pixel.
//   - Storage layout: Column-staggered across 4 banks:
//       Bank index = Col % 4  (Bank 0, 1, 2, 3)
//       Local col  = Col / 4  (0 to 63)
//       Local row  = Row      (0 to 255)
//   - Traversal: Row-wise scan for each selection of column address
//       (Column-major vertical sweep: for each column window [C, C+1, C+2],
//        sweep rows 0 to 255).
//   - 24-bit output bus: Reassembles 3 consecutive pixels in correct spatial order:
//       [23:16] = Left pixel (Col C)
//       [15:8]  = Center pixel (Col C+1)
//       [7:0]   = Right pixel (Col C+2)
//       Handles bank-rotation boundaries seamlessly with 0 conflicts.
//==============================================================================

module cnn_addr_gen #(
    parameter IMG_H    = 256,
    parameter IMG_W    = 256,
    parameter WIN_SIZE = 3
)(
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,

    // Interface to SRAM banks (3 simultaneous accesses per cycle)
    output wire [1:0]  bank_sel_0,  // bank for col C
    output wire [1:0]  bank_sel_1,  // bank for col C+1
    output wire [1:0]  bank_sel_2,  // bank for col C+2

    output wire [7:0]  bank_addr_0, // row address for col C
    output wire [7:0]  bank_addr_1, // row address for col C+1
    output wire [7:0]  bank_addr_2, // row address for col C+2

    output wire [5:0]  bank_col_0,  // col address within bank for col C
    output wire [5:0]  bank_col_1,  // col address within bank for col C+1
    output wire [5:0]  bank_col_2,  // col address within bank for col C+2

    // Direct per-bank control for 4-bank SRAM
    output wire [3:0]  sram_rd_en,
    output wire [7:0]  sram_rd_row_0,
    output wire [7:0]  sram_rd_row_1,
    output wire [7:0]  sram_rd_row_2,
    output wire [7:0]  sram_rd_row_3,
    output wire [5:0]  sram_rd_col_0,
    output wire [5:0]  sram_rd_col_1,
    output wire [5:0]  sram_rd_col_2,
    output wire [5:0]  sram_rd_col_3,

    // Read data from 4 banks
    input  wire [7:0]  bank_dout_0,
    input  wire [7:0]  bank_dout_1,
    input  wire [7:0]  bank_dout_2,
    input  wire [7:0]  bank_dout_3,

    // Output bus & control
    output wire [23:0] pixel_out,   // reassembled 3-pixel, 24-bit output
    output wire        out_valid,
    output reg         busy,
    output reg         done
);

    // State machine
    localparam IDLE = 2'd0,
               SCAN = 2'd1,
               DONE = 2'd2;

    reg [1:0] state;

    // Traversal counters
    reg [7:0] col_start;
    reg [7:0] row_cnt;

    // Window column indices
    wire [7:0] col0 = col_start;
    wire [7:0] col1 = col_start + 8'd1;
    wire [7:0] col2 = col_start + 8'd2;

    // Modulo-4 Bank Mapping & Local Addresses
    assign bank_sel_0  = col0[1:0];      // col0 % 4
    assign bank_col_0  = col0[7:2];      // col0 / 4
    assign bank_addr_0 = row_cnt;        // local row

    assign bank_sel_1  = col1[1:0];      // col1 % 4
    assign bank_col_1  = col1[7:2];      // col1 / 4
    assign bank_addr_1 = row_cnt;        // local row

    assign bank_sel_2  = col2[1:0];      // col2 % 4
    assign bank_col_2  = col2[7:2];      // col2 / 4
    assign bank_addr_2 = row_cnt;        // local row

    // SRAM per-bank control lines
    assign sram_rd_en[0] = (state == SCAN) && ((bank_sel_0 == 2'd0) || (bank_sel_1 == 2'd0) || (bank_sel_2 == 2'd0));
    assign sram_rd_en[1] = (state == SCAN) && ((bank_sel_0 == 2'd1) || (bank_sel_1 == 2'd1) || (bank_sel_2 == 2'd1));
    assign sram_rd_en[2] = (state == SCAN) && ((bank_sel_0 == 2'd2) || (bank_sel_1 == 2'd2) || (bank_sel_2 == 2'd2));
    assign sram_rd_en[3] = (state == SCAN) && ((bank_sel_0 == 2'd3) || (bank_sel_1 == 2'd3) || (bank_sel_2 == 2'd3));

    assign sram_rd_row_0 = row_cnt;
    assign sram_rd_row_1 = row_cnt;
    assign sram_rd_row_2 = row_cnt;
    assign sram_rd_row_3 = row_cnt;

    assign sram_rd_col_0 = (bank_sel_0 == 2'd0) ? bank_col_0 :
                           (bank_sel_1 == 2'd0) ? bank_col_1 :
                           (bank_sel_2 == 2'd0) ? bank_col_2 : 6'd0;

    assign sram_rd_col_1 = (bank_sel_0 == 2'd1) ? bank_col_0 :
                           (bank_sel_1 == 2'd1) ? bank_col_1 :
                           (bank_sel_2 == 2'd1) ? bank_col_2 : 6'd0;

    assign sram_rd_col_2 = (bank_sel_0 == 2'd2) ? bank_col_0 :
                           (bank_sel_1 == 2'd2) ? bank_col_1 :
                           (bank_sel_2 == 2'd2) ? bank_col_2 : 6'd0;

    assign sram_rd_col_3 = (bank_sel_0 == 2'd3) ? bank_col_0 :
                           (bank_sel_1 == 2'd3) ? bank_col_1 :
                           (bank_sel_2 == 2'd3) ? bank_col_2 : 6'd0;

    // Pipeline registers for bank selection (to match 1-cycle SRAM read latency)
    reg [1:0] pipe_bank_sel_0, pipe_bank_sel_1, pipe_bank_sel_2;
    reg       pipe_valid;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state           <= IDLE;
            col_start       <= 8'd0;
            row_cnt         <= 8'd0;
            busy            <= 1'b0;
            done            <= 1'b0;
            pipe_valid      <= 1'b0;
            pipe_bank_sel_0 <= 2'd0;
            pipe_bank_sel_1 <= 2'd0;
            pipe_bank_sel_2 <= 2'd0;
        end
        else begin
            // Pipeline tracking
            pipe_bank_sel_0 <= bank_sel_0;
            pipe_bank_sel_1 <= bank_sel_1;
            pipe_bank_sel_2 <= bank_sel_2;
            pipe_valid      <= (state == SCAN);

            case (state)
                IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        busy      <= 1'b1;
                        col_start <= 8'd0;
                        row_cnt   <= 8'd0;
                        state     <= SCAN;
                    end else begin
                        busy <= 1'b0;
                    end
                end

                SCAN: begin
                    if (row_cnt == IMG_H - 1) begin
                        row_cnt <= 8'd0;
                        if (col_start == IMG_W - WIN_SIZE) begin
                            state <= DONE;
                            busy  <= 1'b0;
                            done  <= 1'b1;
                        end else begin
                            col_start <= col_start + 8'd1;
                        end
                    end else begin
                        row_cnt <= row_cnt + 8'd1;
                    end
                end

                DONE: begin
                    done  <= 1'b0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Rotation-Aware Output Spatial Reassembly
    // Direct multiplexers ensuring dynamic sensitivity to bank_dout changes
    wire [7:0] pix_0 = (pipe_bank_sel_0 == 2'd0) ? bank_dout_0 :
                       (pipe_bank_sel_0 == 2'd1) ? bank_dout_1 :
                       (pipe_bank_sel_0 == 2'd2) ? bank_dout_2 : bank_dout_3;

    wire [7:0] pix_1 = (pipe_bank_sel_1 == 2'd0) ? bank_dout_0 :
                       (pipe_bank_sel_1 == 2'd1) ? bank_dout_1 :
                       (pipe_bank_sel_1 == 2'd2) ? bank_dout_2 : bank_dout_3;

    wire [7:0] pix_2 = (pipe_bank_sel_2 == 2'd0) ? bank_dout_0 :
                       (pipe_bank_sel_2 == 2'd1) ? bank_dout_1 :
                       (pipe_bank_sel_2 == 2'd2) ? bank_dout_2 : bank_dout_3;

    assign pixel_out = {pix_0, pix_1, pix_2};
    assign out_valid = pipe_valid;

endmodule
