`timescale 1ns / 1ps

// ---------------------------------------------------
// Simple Carry-Save Adder (CSA) - parameterized width
// ---------------------------------------------------
module csa #(parameter integer WIDTH = 128) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    input  wire [WIDTH-1:0] c,
    output wire [WIDTH-1:0] sum,
    output wire [WIDTH-1:0] carry
);
    // sum: bitwise XOR of three inputs
    assign sum   = a ^ b ^ c;
    // carry: bits that will be shifted by 1 when converted to normal addition
    assign carry = (a & b) | (b & c) | (c & a);
endmodule


// ---------------------------------------------------
// Kogge-Stone Parallel Prefix Adder (supports WIDTH up to parameter)
// NOTE: Returns simple WIDTH-bit sum of a + b
//       This is a pure combinational adder.
// ---------------------------------------------------
module kogge_stone_adder #(parameter integer WIDTH = 128) (
    input  wire [WIDTH-1:0] a,
    input  wire [WIDTH-1:0] b,
    output wire [WIDTH-1:0] sum
);
    // Generate / Propagate
    wire [WIDTH-1:0] g0, p0;
    wire [WIDTH:0]   carry;

    assign g0 = a & b;
    assign p0 = a ^ b;
    assign carry[0] = 1'b0;

    // prefix arrays
    localparam integer LEVELS = $clog2(WIDTH);
    genvar i, j;

    // Using 2D arrays implemented as vectors of vectors
    // g[level][bit] and p[level][bit]
    // We'll implement as packed arrays with level loop.
    // Create wires for each level.
    // Level 0 is g0/p0; higher levels computed iteratively.
    // We'll flatten into arrays of [LEVELS:0][WIDTH-1:0] using generate loops.

    // level 0 wires
    wire [WIDTH-1:0] g_level0 = g0;
    wire [WIDTH-1:0] p_level0 = p0;

    // Create intermediate nets per level
    // Use generate loops to compute g[i] and p[i]
    // We'll keep previous level in reg-like wires and compute next.
    // Start by assigning level 0 to arrays.
    // For synthesis-friendly style we unroll loops via generate.

    // We'll store all levels in arrays of wires
    // Note: SystemVerilog would be easier, but this Verilog-2001 style works.
    // Generate level wires:
    // g_levels[i] and p_levels[i]
    // g_levels[0] = g_level0, etc.
    // Implement using generate for each level.

    // Helper arrays
    wire [WIDTH-1:0] g_levels [0:LEVELS];
    wire [WIDTH-1:0] p_levels [0:LEVELS];

    assign g_levels[0] = g_level0;
    assign p_levels[0] = p_level0;

    generate
        for (i = 1; i <= LEVELS; i = i + 1) begin : gen_levels
            for (j = 0; j < WIDTH; j = j + 1) begin : gen_bits
                // distance for this level
                localparam integer DIST = 1 << (i-1);
                if (j < DIST) begin
                    assign g_levels[i][j] = g_levels[i-1][j];
                    assign p_levels[i][j] = p_levels[i-1][j];
                end else begin
                    assign g_levels[i][j] = g_levels[i-1][j] | (p_levels[i-1][j] & g_levels[i-1][j-DIST]);
                    assign p_levels[i][j] = p_levels[i-1][j] & p_levels[i-1][j-DIST];
                end
            end
        end
    endgenerate

    // Now compute carries: carry[j+1] = g_levels[LEVELS][j]
    generate
        for (j = 0; j < WIDTH; j = j + 1) begin : carry_calc
            assign carry[j+1] = g_levels[LEVELS][j];
        end
    endgenerate

    // sum[j] = p0[j] ^ carry[j]
    generate
        for (j = 0; j < WIDTH; j = j + 1) begin : sum_calc
            assign sum[j] = p0[j] ^ carry[j];
        end
    endgenerate
endmodule


// ---------------------------------------------------
// Recursive pipelined Vedic multiplier (unsigned core)
// - This is the unsigned-only recursive, pipelined multiplier
// - Used as the arithmetic core for signed/int and FP paths.
// - Behavior matches original design but refactored for reuse.
// ---------------------------------------------------
module vedic_mult_unsigned_p #(
    parameter integer N    = 16,
    parameter integer BASE = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire [N-1:0] a,
    input  wire [N-1:0] b,
    output reg  [(2*N)-1:0] p
);
    generate
        if (N <= BASE) begin : base_case
            // Base: combinational multiply then registered pipeline (2-cycle)
            wire [(2*N)-1:0] mul_w = a * b;
            reg  [(2*N)-1:0] mul_r;
            always @(posedge clk) begin
                if (rst) begin
                    mul_r <= 0;
                    p <= 0;
                end else begin
                    mul_r <= mul_w;
                    p <= mul_r;
                end
            end
        end else begin : recur
            localparam integer HALF = N/2;

            // Child multipliers (unsigned) - recursive
            wire [(2*HALF)-1:0] q0, q1, q2, q3;
            vedic_mult_unsigned_p #(.N(HALF), .BASE(BASE)) m0 (.clk(clk), .rst(rst), .a(a[HALF-1:0]),      .b(b[HALF-1:0]),      .p(q0));
            vedic_mult_unsigned_p #(.N(HALF), .BASE(BASE)) m1 (.clk(clk), .rst(rst), .a(a[N-1:HALF]),      .b(b[HALF-1:0]),      .p(q1));
            vedic_mult_unsigned_p #(.N(HALF), .BASE(BASE)) m2 (.clk(clk), .rst(rst), .a(a[HALF-1:0]),      .b(b[N-1:HALF]),      .p(q2));
            vedic_mult_unsigned_p #(.N(HALF), .BASE(BASE)) m3 (.clk(clk), .rst(rst), .a(a[N-1:HALF]),      .b(b[N-1:HALF]),      .p(q3));

            // Register child outputs (pipeline boundary)
            reg [(2*HALF)-1:0] q0_r, q1_r, q2_r, q3_r;
            always @(posedge clk) begin
                if (rst) begin
                    q0_r <= 0; q1_r <= 0; q2_r <= 0; q3_r <= 0;
                end else begin
                    q0_r <= q0;
                    q1_r <= q1;
                    q2_r <= q2;
                    q3_r <= q3;
                end
            end

            // Align/extend to full width
            wire [(2*N)-1:0] q0_ext = {{(2*N - 2*HALF){1'b0}}, q0_r};
            wire [(2*N)-1:0] q1_ext = ({{(2*N - 2*HALF){1'b0}}, q1_r} << HALF);
            wire [(2*N)-1:0] q2_ext = ({{(2*N - 2*HALF){1'b0}}, q2_r} << HALF);
            wire [(2*N)-1:0] q3_ext = ({{(2*N - 2*HALF){1'b0}}, q3_r} << N);

            // CSA tree (pipelined)
            wire [(2*N)-1:0] sum1, carry1;
            csa #(.WIDTH(2*N)) csa1 (.a(q0_ext), .b(q1_ext), .c(q2_ext), .sum(sum1), .carry(carry1));

            wire [(2*N)-1:0] sum2, carry2;
            csa #(.WIDTH(2*N)) csa2 (.a(sum1), .b(carry1 << 1), .c(q3_ext), .sum(sum2), .carry(carry2));

            // Register CSA outputs (pipeline boundary)
            reg [(2*N)-1:0] sum2_r, carry2_r;
            always @(posedge clk) begin
                if (rst) begin
                    sum2_r   <= 0;
                    carry2_r <= 0;
                end else begin
                    sum2_r   <= sum2;
                    carry2_r <= carry2;
                end
            end

            // Final stage: Kogge-Stone adder: sum2_r + (carry2_r << 1)
            wire [(2*N)-1:0] final_sum;
            kogge_stone_adder #(.WIDTH(2*N)) ksa_inst (
                    .a(sum2_r),
                    .b(carry2_r << 1),
                    .sum(final_sum)
                    );
            // Output register (pipeline boundary)
            always @(posedge clk) begin
                if (rst)
                    p <= 0;
                else
                    p <= final_sum;
            end
        end
    endgenerate
endmodule


// ---------------------------------------------------
// IEEE-754 single-precision (FP32) multiplier wrapper
// - Uses the unsigned vedic core to multiply the mantissas (24-bit each, incl. hidden 1)
// - Adds exponents (with bias adjustment), normalizes result, sets sign.
// - Produces 32-bit IEEE-754 result. Basic handling for zero/inf/nan.
// - Pipelined at mantissa multiply and final stage.
// ---------------------------------------------------
module fp32_mul_p (
    input  wire clk,
    input  wire rst,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] p
);
    // Fields
    wire sign_a = a[31];
    wire sign_b = b[31];
    wire [7:0] exp_a = a[30:23];
    wire [7:0] exp_b = b[30:23];
    wire [22:0] frac_a = a[22:0];
    wire [22:0] frac_b = b[22:0];

    // Detect special cases
    wire is_zero_a = (exp_a == 8'b0) && (frac_a == 23'b0);
    wire is_zero_b = (exp_b == 8'b0) && (frac_b == 23'b0);
    wire is_inf_a  = (exp_a == 8'hFF) && (frac_a == 23'b0);
    wire is_inf_b  = (exp_b == 8'hFF) && (frac_b == 23'b0);
    wire is_nan_a  = (exp_a == 8'hFF) && (frac_a != 23'b0);
    wire is_nan_b  = (exp_b == 8'hFF) && (frac_b != 23'b0);

    // Effective mantissas (with implicit 1 for normals; for denormals implicit 0)
    wire [23:0] mant_a = (exp_a == 8'b0) ? {1'b0, frac_a} : {1'b1, frac_a};
    wire [23:0] mant_b = (exp_b == 8'b0) ? {1'b0, frac_b} : {1'b1, frac_b};

    // Sign of output
    wire sign_out = sign_a ^ sign_b;

    // Exponent add (intermediate wider to avoid overflow) and bias adjust
    // Bias for single precision = 127
    wire [9:0] exp_sum_raw = (exp_a == 8'b0 ? 10'd0 : {2'b00,exp_a}) + (exp_b == 8'b0 ? 10'd0 : {2'b00,exp_b});
    // If inputs are denormals (exp==0) we treated exponent as 0; IEEE special handling for denormals is approximate here.

    // Mantissa multiply using vedic unsigned core: 24x24 -> 48 bits
    wire [47:0] mant_prod;
    // instantiate vedic unsigned multiplier for mantissas
    // Use N = 24, small base to keep recursion shallow
    vedic_mult_unsigned_p #(.N(24), .BASE(6)) mant_mul (
        .clk(clk),
        .rst(rst),
        .a(mant_a),
        .b(mant_b),
        .p(mant_prod)
    );

    // Pipeline register to sync mantissa product and exponent sums / special-case flags
    reg [47:0] mant_prod_r;
    reg [9:0]  exp_sum_raw_r;
    reg        sign_out_r;
    reg        is_zero_r, is_inf_r, is_nan_r;
    always @(posedge clk) begin
        if (rst) begin
            mant_prod_r <= 0;
            exp_sum_raw_r <= 0;
            sign_out_r <= 0;
            is_zero_r <= 0;
            is_inf_r <= 0;
            is_nan_r <= 0;
        end else begin
            mant_prod_r <= mant_prod;
            exp_sum_raw_r <= exp_sum_raw;
            sign_out_r <= sign_out;
            // propagate special cases: if either NaN -> NaN, if either Inf -> Inf, if either zero -> zero
            is_nan_r  <= is_nan_a | is_nan_b;
            is_inf_r  <= is_inf_a | is_inf_b;
            is_zero_r <= is_zero_a | is_zero_b;
        end
    end

    // Normalize mantissa product: mant_prod_r is up to 48 bits.
    // If MSB (47) == 1 => product in [2,4) (because each mantissa in [1,2) for normal numbers),
    // so we need to shift right by 1 and add 1 to exponent.
    // Else if MSB(46) == 1 => product in [1,2) already aligned.
    wire msb47 = mant_prod_r[47];
    wire msb46 = mant_prod_r[46];

    // Normalize shift and round (simple rounding: take bit 23 as round bit)
    // We'll form normalized mantissa of 24 bits (including implicit 1).
    wire [47:0] mant_shifted = msb47 ? (mant_prod_r >> 1) : mant_prod_r;
    // normalized mantissa: take bits [46:23] (24 bits -> implicit + 23 frac)
    wire [23:0] mant_norm = mant_shifted[46:23]; // 24 bits
    // sticky/round bits (for rudimentary round-to-nearest)
    wire round_bit = mant_shifted[22];
    wire sticky = |mant_shifted[21:0];

    // Compute exponent: exp_sum_raw_r - bias(127) + (msb47 ? 1 : 0)
    // exp_sum_raw_r currently is exp_a + exp_b (with denormals treated as 0). For IEEE we need:
    // exp_out = exp_a + exp_b - bias + (msb47 ? 1 : 0)
    // We stored exp_sum_raw_r as raw sum (0..510)
    wire [9:0] exp_adjust = exp_sum_raw_r - 10'd127 + (msb47 ? 10'd1 : 10'd0);

    // Handle overflow/underflow roughly
    // Exponent field final (8 bits):
    reg [8:0] exp_field; // one extra bit to detect overflow to Inf
    always @(*) begin
        if (is_nan_r) begin
            exp_field = 9'h1FF; // mark as NaN (we'll set mantissa nonzero)
        end else if (is_inf_r) begin
            exp_field = 9'h1FE; // mark as Inf
        end else if (is_zero_r) begin
            exp_field = 9'h000;
        end else begin
            // clamp/fit exp_adjust into 8-bit field with overflow detection
            if ($signed(exp_adjust) < -126) begin
                // underflow to zero/denormal (we do simple zero)
                exp_field = 9'h000;
            end else if (exp_adjust > 10'd255) begin
                // overflow -> Inf
                exp_field = 9'h1FE;
            end else begin
                exp_field = {1'b0, exp_adjust[7:0]}; // no overflow flag
            end
        end
    end

    // Rounding: simple round-to-nearest (tie -> round up)
    // Add round if round_bit && (sticky || LSB==1)
    wire round_add = round_bit && (sticky || mant_norm[0]);
    wire [23:0] mant_rounded = mant_norm + (round_add ? 24'd1 : 24'd0);

    // Handle mantissa overflow after rounding (e.g., 1.111.. + rounding -> 10.000)
    wire mant_overflow = mant_rounded[23] == 1'b1 && mant_norm[23] == 1'b1 && (msb47==0); // conservative check
    // Actually if mant_rounded becomes 24'b1_000... (i.e., bit23 1 but was 0?) we need to bump exponent.
    // We'll recompute final exponent and mantissa more simply:
    reg [7:0] final_exp;
    reg [22:0] final_frac;
    integer tmp_exp;  // Declare it outside procedural block

always @(*) begin
    if (is_nan_r) begin
        final_exp = 8'hFF;
        final_frac = 23'h400000; // quiet NaN
    end else if (is_inf_r) begin
        final_exp = 8'hFF;
        final_frac = 23'b0;
    end else if (is_zero_r) begin
        final_exp = 8'h00;
        final_frac = 23'b0;
    end else begin
        tmp_exp = exp_adjust;  // ✅ use it here, no error now
        // rest of code as before
        if (mant_rounded[23] == 1'b1 && mant_norm[23] == 1'b0) begin
            tmp_exp = tmp_exp + 1;
            final_frac = mant_rounded[23:1];
        end else begin
            final_frac = mant_rounded[22:0];
        end
        if (tmp_exp >= 255) begin
            final_exp = 8'hFF; final_frac = 0;
        end else if (tmp_exp <= 0) begin
            final_exp = 8'h00; final_frac = 0;
        end else begin
            final_exp = tmp_exp[7:0];
        end
    end
end


    // Output register (pipeline boundary)
    always @(posedge clk) begin
        if (rst) begin
            p <= 32'h0;
        end else begin
            if (is_nan_r) begin
                p <= {1'b0, 8'hFF, 23'h400000}; // quiet NaN
            end else if (is_inf_r) begin
                p <= {sign_out_r, 8'hFF, 23'b0};
            end else if (is_zero_r) begin
                p <= {sign_out_r, 8'h00, 23'b0};
            end else begin
                p <= {sign_out_r, final_exp, final_frac};
            end
        end
    end

endmodule


// ---------------------------------------------------
// Top-level parameterizable multiplier supporting:
// MODE = 0 -> unsigned integer (width N)
// MODE = 1 -> signed integer (two's complement, width N)
// MODE = 2 -> floating-point single precision (FP32, ignore N parameter for FP mode)
// ---------------------------------------------------
module vedic_mult_p #(
    parameter integer N    = 16,
    parameter integer BASE = 8,
    // Mode: 0 = unsigned, 1 = signed integer, 2 = IEEE-754 single-precision FP
    parameter integer MODE = 0
)(
    input  wire clk,
    input  wire rst,
    input  wire [N-1:0] a,
    input  wire [N-1:0] b,
    output reg  [(2*N)-1:0] p // Note: for MODE==2 (FP), only lower 32 bits are valid.
);
    // MODE 0: unsigned -> directly use vedic_mult_unsigned_p
    // MODE 1: signed -> compute signs, abs, call unsigned core, reapply sign
    // MODE 2: FP32 -> interpret inputs as 32-bit IEEE floats (so a and b must be 32-bit)
   generate
    if (MODE == 0) begin : gen_unsigned
        // Declare an intermediate wire
        wire [(2*N)-1:0] p_unsigned_wire;

        // Instantiate unsigned core
        vedic_mult_unsigned_p #(.N(N), .BASE(BASE)) ucore (
            .clk(clk),
            .rst(rst),
            .a(a),
            .b(b),
            .p(p_unsigned_wire)
        );

        // Register the result into output p (which is reg)
        always @(posedge clk) begin
            if (rst)
                p <= 0;
            else
                p <= p_unsigned_wire;
        end
    end

       // inside vedic_mult_p (replace existing MODE == 1 block)
else if (MODE == 1) begin : gen_signed
    // Signed integer multiply (two's complement -> abs -> unsigned core -> reapply sign)
    wire sign_a = a[N-1];
    wire sign_b = b[N-1];
    wire sign_out = sign_a ^ sign_b;

    wire [N-1:0] abs_a = sign_a ? (~a + 1'b1) : a;
    wire [N-1:0] abs_b = sign_b ? (~b + 1'b1) : b;

    // unsigned product (2N bits)
    wire [(2*N)-1:0] prod_abs;
    vedic_mult_unsigned_p #(.N(N), .BASE(BASE)) ucore_s (
        .clk(clk),
        .rst(rst),
        .a(abs_a),
        .b(abs_b),
        .p(prod_abs)
    );

    // Compute correct pipeline depth for the unsigned core:
    // Base latency = 2, recursion overhead per level = 3
    localparam integer LEVELS = $clog2(N/BASE); // N/BASE should be power of two
    localparam integer PIPE_DEPTH = 2 + 3 * LEVELS;

    // Shift registers to delay sign and product to align with final output
    integer ii;
    reg sign_pipe [0:PIPE_DEPTH-1];
    reg [(2*N)-1:0] prod_pipe [0:PIPE_DEPTH-1];

    always @(posedge clk) begin
        if (rst) begin
            for (ii = 0; ii < PIPE_DEPTH; ii = ii + 1) begin
                sign_pipe[ii] <= 1'b0;
                prod_pipe[ii] <= {(2*N){1'b0}};
            end
            p <= {(2*N){1'b0}};
        end else begin
            // stage 0 captures current prod/sign
            sign_pipe[0] <= sign_out;
            prod_pipe[0] <= prod_abs;
            // shift the pipeline
            for (ii = 1; ii < PIPE_DEPTH; ii = ii + 1) begin
                sign_pipe[ii] <= sign_pipe[ii-1];
                prod_pipe[ii] <= prod_pipe[ii-1];
            end
            // final output: apply sign from last stage
            if (sign_pipe[PIPE_DEPTH-1])
                p <= (~prod_pipe[PIPE_DEPTH-1]) + 1'b1;
            else
                p <= prod_pipe[PIPE_DEPTH-1];
        end
    end
end



        else begin : gen_fp
            // MODE == 2 : floating point (FP32)
            // For FP mode we interpret the lower 32 bits of a and b as IEEE-754 floats.
            // Output uses lower 32 bits of p. Upper bits of p are zeroed.
            // The FP path is internally pipelined and uses vedic unsigned core for mantissa multiply.
            wire [31:0] a32 = a;
            wire [31:0] b32 = b;
            wire [31:0] fp_out;
            fp32_mul_p fp_mul_inst (
                .clk(clk),
                .rst(rst),
                .a(a32),
                .b(b32),
                .p(fp_out)
            );

            always @(posedge clk) begin
                if (rst) begin
                    p <= 0;
                end else begin
                    // place 32-bit FP result in lower bits of p for compatibility
                    p <= {{(2*N-32){1'b0}}, fp_out};
                end
            end
        end
    endgenerate
endmodule
