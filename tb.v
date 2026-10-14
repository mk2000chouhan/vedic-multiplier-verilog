`timescale 1ns / 1ps
module tb_simple;

    // Clock / reset
    reg clk = 0;
    always #5 clk = ~clk; // 100 MHz

    reg rst;

    // -----------------------
    // Unsigned DUT signals (N = 16)
    // -----------------------
    reg  [15:0] a_u;
    reg  [15:0] b_u;
    wire [31:0] p_u; // 2*N bits

    // -----------------------
    // Signed DUT signals (N = 16)
    // -----------------------
    reg  [15:0] a_s;
    reg  [15:0] b_s;
    wire [31:0] p_s;

    // -----------------------
    // Floating-point DUT signals (N = 32)
    // -----------------------
    reg  [31:0] a_f;
    reg  [31:0] b_f;
    wire [63:0] p_f; // full 2*N bits (lower 32 bits contain FP32 result)

    // Instantiate unsigned multiplier (MODE = 0)
    vedic_mult_p #(.N(16), .BASE(4), .MODE(0)) dut_u (
        .clk(clk), .rst(rst), .a(a_u), .b(b_u), .p(p_u)
    );

    // Instantiate signed multiplier (MODE = 1)
    vedic_mult_p #(.N(16), .BASE(4), .MODE(1)) dut_s (
        .clk(clk), .rst(rst), .a(a_s), .b(b_s), .p(p_s)
    );

    // Instantiate FP multiplier (MODE = 2) -- N=32 so lower 32 bits used for FP
    vedic_mult_p #(.N(32), .BASE(8), .MODE(2)) dut_f (
        .clk(clk), .rst(rst), .a(a_f), .b(b_f), .p(p_f)
    );

    // Helper: print time and values when results are expected
    task wait_and_print;
        input integer delay_time;
        begin
            #delay_time;
            $display("\n--- Time %0t ---", $time);

            // unsigned
            $display("UNSIGNED:  a = %0d, b = %0d -> p = %0d (hex %h)", a_u, b_u, p_u, p_u);

            // signed (print as signed)
            $display("SIGNED:    a = %0d, b = %0d -> p = %0d (hex %h)", $signed(a_s), $signed(b_s), $signed(p_s), p_s);

            // FP (show raw bits and interpreted float)
            $display("FP32:      a = 0x%h, b = 0x%h -> p_bits = 0x%h (lower32 = 0x%h)  as float ~= %f",
                     a_f, b_f, p_f, p_f[31:0], $bitstoreal({32'h0, p_f[31:0]}));
        end
    endtask

    // Test sequence
    initial begin
        // initialize
        rst = 1;
        a_u = 0; b_u = 0;
        a_s = 0; b_s = 0;
        a_f = 0; b_f = 0;

        #20 rst = 0; // release reset after 20 ns
        #10;

        $display("Starting tests...");

        // -------------------
        // Test vector set 1 (interleaved)
        // -------------------
        // unsigned: 25 * 4
        a_u = 16'd25; b_u = 16'd4;

        // signed: -25 * 4
        a_s = -16'sd25; b_s = 16'sd40;

        // fp : 2.5 * 3.0
        a_f = 32'h40200000; // 2.5
        b_f = 32'h40400000; // 3.0

        // Wait enough cycles for pipelines to finish and print results
        // Increase this delay if your pipeline has more latency (N larger -> deeper recursion)
        wait_and_print(200);

        // -------------------
        // Test vector set 2 (interleaved)
        // -------------------
        a_u = 16'd255; b_u = 16'd10;
        a_s = -16'sd12;  b_s = -16'sd4;
        a_f = 32'h3F000000; // 0.5
        b_f = 32'h3F000000; // 0.5

        wait_and_print(200);

        // -------------------
        // Test vector set 3 (extra)
        // -------------------
        a_u = 16'd1000; b_u = 16'd2000;
        a_s = 16'sd7;     b_s = -16'sd5;
        a_f = 32'hBFE00000; // -1.75
        b_f = 32'h40800000; // 4.0

        wait_and_print(300);

        $display("All tests done. Finishing simulation.");
        #20 $finish;
    end

endmodule
