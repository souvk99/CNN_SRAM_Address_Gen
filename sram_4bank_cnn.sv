`timescale 1ns / 1ps

//==============================================================================
// Assignment 3: 4-Bank CNN Image SRAM Module
//
// Organization:
//   - 4 independent banks (Bank 0, 1, 2, 3)
//   - Each bank: 256 rows x 64 columns = 16,384 Bytes (16 KB)
//   - Total storage: 4 x 16 KB = 64 KB = 65,536 Bytes (stores 256x256 image)
//   - Pixel format: 8-bit unsigned
//   - Column-staggered layout:
//       Image column C is stored in Bank (C % 4), at local column (C / 4).
//   - Parallel Read: 4 independent 8-bit read ports (one per bank), allowing
//     up to 4 banks to be read simultaneously in the same clock cycle.
//==============================================================================

module sram_4bank_cnn #(
    parameter ROWS_PER_BANK = 256,
    parameter COLS_PER_BANK = 64
)(
    input  logic        clk,

    // Write interface (for runtime writes / testing)
    input  logic        wr_en,
    input  logic [1:0]  wr_bank_sel,
    input  logic [7:0]  wr_row,
    input  logic [5:0]  wr_col,
    input  logic [7:0]  wr_data,

    // Read interface: 4 independent bank addresses & outputs
    input  logic        rd_en [0:3],
    input  logic [7:0]  rd_row [0:3],
    input  logic [5:0]  rd_col [0:3],
    output logic [7:0]  bank_dout [0:3]
);

    // 4 memory arrays: 256 rows x 64 bytes
    logic [7:0] mem_bank0 [0:ROWS_PER_BANK-1][0:COLS_PER_BANK-1];
    logic [7:0] mem_bank1 [0:ROWS_PER_BANK-1][0:COLS_PER_BANK-1];
    logic [7:0] mem_bank2 [0:ROWS_PER_BANK-1][0:COLS_PER_BANK-1];
    logic [7:0] mem_bank3 [0:ROWS_PER_BANK-1][0:COLS_PER_BANK-1];

    // Initialization with recognizable staggered test patterns
    integer init_r, init_c;
    initial begin
        for (init_r = 0; init_r < ROWS_PER_BANK; init_r = init_r + 1) begin
            for (init_c = 0; init_c < COLS_PER_BANK; init_c = init_c + 1) begin
                mem_bank0[init_r][init_c] = 8'h10 + (init_r[3:0] * 8'd4) + init_c[5:0];
                mem_bank1[init_r][init_c] = 8'h40 + (init_r[3:0] * 8'd4) + init_c[5:0];
                mem_bank2[init_r][init_c] = 8'h70 + (init_r[3:0] * 8'd4) + init_c[5:0];
                mem_bank3[init_r][init_c] = 8'hA0 + (init_r[3:0] * 8'd4) + init_c[5:0];
            end
        end
    end

    always_ff @(posedge clk) begin
        // Write port
        if (wr_en) begin
            case (wr_bank_sel)
                2'd0: mem_bank0[wr_row][wr_col] <= wr_data;
                2'd1: mem_bank1[wr_row][wr_col] <= wr_data;
                2'd2: mem_bank2[wr_row][wr_col] <= wr_data;
                2'd3: mem_bank3[wr_row][wr_col] <= wr_data;
            endcase
        end

        // Synchronous Read ports (1 cycle latency for all 4 banks)
        if (rd_en[0]) bank_dout[0] <= mem_bank0[rd_row[0]][rd_col[0]];
        if (rd_en[1]) bank_dout[1] <= mem_bank1[rd_row[1]][rd_col[1]];
        if (rd_en[2]) bank_dout[2] <= mem_bank2[rd_row[2]][rd_col[2]];
        if (rd_en[3]) bank_dout[3] <= mem_bank3[rd_row[3]][rd_col[3]];
    end

endmodule
