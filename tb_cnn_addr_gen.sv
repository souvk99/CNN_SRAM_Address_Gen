`timescale 1ns / 1ps

module tb_cnn_addr_gen;

    // Use smaller image height in testbench (e.g. 8 rows) to quickly sweep through
    // multiple column boundaries while verifying the full address generation logic!
    localparam TEST_IMG_H = 8;
    localparam TEST_IMG_W = 16;
    localparam WIN_SIZE   = 3;

    logic clk;
    logic reset_n;
    logic start;

    // SRAM Write / Init interface
    logic        wr_en;
    logic [1:0]  wr_bank_sel;
    logic [7:0]  wr_row;
    logic [5:0]  wr_col;
    logic [7:0]  wr_data;

    // Wires between cnn_addr_gen and sram_4bank_cnn
    wire [1:0]  bank_sel   [0:2];
    wire [7:0]  bank_addr  [0:2];
    wire [5:0]  bank_col   [0:2];

    wire        sram_rd_en  [0:3];
    wire [7:0]  sram_rd_row [0:3];
    wire [5:0]  sram_rd_col [0:3];
    wire [7:0]  bank_dout   [0:3];

    wire [23:0] pixel_out;
    wire        out_valid;
    wire        busy;
    wire        done;

    // Instantiate 4-Bank SRAM (Full 256x64 per bank = 64 KB)
    sram_4bank_cnn #(
        .ROWS_PER_BANK(256),
        .COLS_PER_BANK(64)
    ) sram_inst (
        .clk(clk),
        .wr_en(wr_en),
        .wr_bank_sel(wr_bank_sel),
        .wr_row(wr_row),
        .wr_col(wr_col),
        .wr_data(wr_data),
        .rd_en(sram_rd_en),
        .rd_row(sram_rd_row),
        .rd_col(sram_rd_col),
        .bank_dout(bank_dout)
    );

    // Instantiate CNN Address Generator configured for test sweep
    cnn_addr_gen #(
        .IMG_H(TEST_IMG_H),
        .IMG_W(TEST_IMG_W),
        .WIN_SIZE(WIN_SIZE)
    ) addr_gen_inst (
        .clk(clk),
        .reset_n(reset_n),
        .start(start),
        .bank_sel(bank_sel),
        .bank_addr(bank_addr),
        .bank_col(bank_col),
        .sram_rd_en(sram_rd_en),
        .sram_rd_row(sram_rd_row),
        .sram_rd_col(sram_rd_col),
        .bank_dout(bank_dout),
        .pixel_out(pixel_out),
        .out_valid(out_valid),
        .busy(busy),
        .done(done)
    );

    // Clock: 100 MHz (10 ns)
    initial clk = 0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer verified_samples = 0;
    integer boundary_rotations_seen = 0;

    // Conflict assertion monitor: Ensure no two bank_sel values ever collide
    always @(posedge clk) begin
        if (busy) begin
            if (bank_sel[0] === bank_sel[1] ||
                bank_sel[1] === bank_sel[2] ||
                bank_sel[0] === bank_sel[2]) begin
                $display("CRITICAL ERROR at time %0t: Bank conflict detected! bank_sel = {%0d, %0d, %0d}",
                         $time, bank_sel[0], bank_sel[1], bank_sel[2]);
                errors = errors + 1;
            end
        end
    end

    // Reference function for expected pixel value
    function [7:0] get_pixel(input integer r, input integer c);
        integer b_idx, l_col;
        begin
            b_idx = c % 4;
            l_col = c / 4;
            case (b_idx)
                0: get_pixel = 8'h10 + (r[3:0] * 8'd4) + l_col[5:0];
                1: get_pixel = 8'h40 + (r[3:0] * 8'd4) + l_col[5:0];
                2: get_pixel = 8'h70 + (r[3:0] * 8'd4) + l_col[5:0];
                3: get_pixel = 8'hA0 + (r[3:0] * 8'd4) + l_col[5:0];
            endcase
        end
    endfunction

    // Verification monitor
    integer exp_col_start = 0;
    integer exp_row = 0;
    logic [23:0] expected_pixels;

    always @(posedge clk) begin
        #1;
        if (out_valid) begin
            expected_pixels = {get_pixel(exp_row, exp_col_start),
                               get_pixel(exp_row, exp_col_start + 1),
                               get_pixel(exp_row, exp_col_start + 2)};

            if (pixel_out === expected_pixels) begin
                if (exp_row == 0) begin
                    $display("  PASS: Col Window %0d..%0d (Banks {%0d, %0d, %0d}) | Row %0d: pixel_out = 0x%06h (P0=0x%02h, P1=0x%02h, P2=0x%02h)",
                             exp_col_start, exp_col_start + 2,
                             addr_gen_inst.pipe_bank_sel[0],
                             addr_gen_inst.pipe_bank_sel[1],
                             addr_gen_inst.pipe_bank_sel[2],
                             exp_row, pixel_out,
                             pixel_out[23:16], pixel_out[15:8], pixel_out[7:0]);
                end
                verified_samples = verified_samples + 1;
            end else begin
                $display("  FAIL: Col %0d, Row %0d: pixel_out = 0x%06h, Expected = 0x%06h",
                         exp_col_start, exp_row, pixel_out, expected_pixels);
                errors = errors + 1;
            end

            // Check if this window was a rotation boundary
            if ((exp_col_start % 4) == 3) begin
                boundary_rotations_seen = boundary_rotations_seen + 1;
            end

            // Advance expected model state
            if (exp_row == TEST_IMG_H - 1) begin
                exp_row = 0;
                exp_col_start = exp_col_start + 1;
            end else begin
                exp_row = exp_row + 1;
            end
        end
    end

    initial begin
        $dumpfile("cnn_addr_gen.vcd");
        $dumpvars(0, tb_cnn_addr_gen);

        clk     = 0;
        reset_n = 0;
        start   = 0;
        wr_en   = 0;
        wr_bank_sel = 0;
        wr_row      = 0;
        wr_col      = 0;
        wr_data     = 0;

        $display("============================================================================");
        $display(" RUNNING VERIFICATION FOR ASSIGNMENT 3: CNN ADDRESS GENERATION & 4-BANK SRAM");
        $display("============================================================================");

        // Reset DUT
        #25;
        reset_n = 1;
        repeat (2) @(posedge clk);

        // ---------------------------------------------------------------------
        // Step 1: Start CNN Address Generator Scan
        // ---------------------------------------------------------------------
        $display("\n[Step 1] Triggering CNN Address Generation & Scanning image...");
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;

        // Wait until complete scan is finished
        wait (done == 1'b1);
        @(posedge clk);
        #10;

        // ---------------------------------------------------------------------
        // Step 2: Final Verification Summary
        // ---------------------------------------------------------------------
        $display("\n============================================================================");
        if (errors == 0 && verified_samples > 0) begin
            $display(" [RESULT] ALL ASSIGNMENT 3 CHECKS PASSED WITH 100%%%% ACCURACY! (0 errors)");
            $display("  - 0 Bank collisions detected (Disjoint bank invariant maintained)");
            $display("  - Bank-rotation boundaries (e.g. Banks 3 -> 0 -> 1) verified: %0d times", boundary_rotations_seen);
            $display("  - Total sliding-window samples verified: %0d", verified_samples);
            $display("  - 24-bit output bus reassembled correctly in spatial column order");
        end else begin
            $display(" [RESULT] TOTAL ERRORS: %0d", errors);
        end
        $display("============================================================================\n");

        #50;
        $finish;
    end

endmodule
