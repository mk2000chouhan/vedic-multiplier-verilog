`timescale 1ns / 1ps

module top_arty (
    input  wire sys_clk,          // 100 MHz system clock from board
    input  wire btn_reset_n,      // Active-low reset from button

    // Inputs from VIO
    input  wire [63:0] vio_a,     // Input operand A
    input  wire [63:0] vio_b,     // Input operand B

    // Outputs to ILA (for observing results)
    output wire [127:0] ila_p_unsigned,
    output wire [127:0] ila_p_signed,
    output wire [127:0] ila_p_fp64
);

    // -------------------------------------------------------------
    // Internal Reset (active-high)
    // -------------------------------------------------------------
    wire rst = ~btn_reset_n;

    // -------------------------------------------------------------
    // UNSIGNED MULTIPLIER (MODE = 0)
    // -------------------------------------------------------------
    vedic_mult_p #(
        .N(64),
        .BASE(8),
        .MODE(0)
    ) u_unsigned (
        .clk(sys_clk),
        .rst(rst),
        .a(vio_a),
        .b(vio_b),
        .p(ila_p_unsigned)
    );

    // -------------------------------------------------------------
    // SIGNED MULTIPLIER (MODE = 1)
    // -------------------------------------------------------------
    vedic_mult_p #(
        .N(64),
        .BASE(8),
        .MODE(1)
    ) u_signed (
        .clk(sys_clk),
        .rst(rst),
        .a(vio_a),
        .b(vio_b),
        .p(ila_p_signed)
    );

    // -------------------------------------------------------------
    // FLOATING POINT MULTIPLIER (MODE = 2)
    // -------------------------------------------------------------
    vedic_mult_p #(
        .N(64),
        .BASE(8),
        .MODE(2)
    ) u_fp64 (
        .clk(sys_clk),
        .rst(rst),
        .a(vio_a),
        .b(vio_b),
        .p(ila_p_fp64)
    );

endmodule
