/**
    @author Dmitry Moskovskikh
    @name mathematics multiply accumulate

    @brief A * B + C = C operation macro (MAC with loopback C)

    ВАЖНО:
      - Последний MAC выполняется в такт, когда i_clr=1 и s_pipe_end=1
      - Результат o_c / o_valid появляется на СЛЕДУЮЩИЙ такт
      - Это сделано специально, чтобы упростить упаковку в 1 DSP48E1
*/

`timescale 1ns/1ps
`include "lte_phy_math.vh"

module math_mac_macro #(
    parameter int A_WIDTH   = 16,
    parameter int B_WIDTH   = 16,
    parameter int ACC_WIDTH = 48,
    parameter int PIPE      = 1
)(
    input  wire                        i_clk,
    input  wire                        i_rst,
    input  wire                        i_clr,

    input  wire signed [A_WIDTH-1:0]   i_a,
    input  wire signed [B_WIDTH-1:0]   i_b,
    input  wire                        i_valid,

    output wire signed [ACC_WIDTH-1:0] o_c,
    output wire                        o_valid,

    output wire                        o_valid_mul
);

    localparam int MUL_WIDTH = A_WIDTH + B_WIDTH;

    initial begin
        if (PIPE < 1)
            $fatal(1, "math_mac_macro: PIPE must be >= 1");

        if (ACC_WIDTH < MUL_WIDTH)
            $fatal(1, "math_mac_macro: ACC_WIDTH (%0d) must be >= MUL_WIDTH (%0d)",
                   ACC_WIDTH, MUL_WIDTH);
    end

    // =========================================================================
    // Input pipeline
    // =========================================================================
    reg signed [A_WIDTH-1:0] pipe_a [0:PIPE-1];
    reg signed [B_WIDTH-1:0] pipe_b [0:PIPE-1];
    reg        [PIPE-1:0]    pipe_i_valid;

    integer i;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pipe_i_valid <= '0;
            for (i = 0; i < PIPE; i++) begin
                pipe_a[i] <= '0;
                pipe_b[i] <= '0;
            end
        end else begin
            pipe_a[0] <= i_a;
            pipe_b[0] <= i_b;

            pipe_i_valid[0] <= i_valid;
            for (i = 1; i < PIPE; i++) begin
                pipe_a[i]       <= pipe_a[i-1];
                pipe_b[i]       <= pipe_b[i-1];
                pipe_i_valid[i] <= pipe_i_valid[i-1];
            end
        end
    end

    reg signed [ACC_WIDTH-1:0] op_acc_r;
    reg signed [ACC_WIDTH-1:0] op_acc_snap_r;
    reg                        op_acc_valid;
    (* use_dsp = "yes" *) reg signed [MUL_WIDTH-1:0] mul_r;
    reg                        mul_valid_r;
    reg                        mul_clr_r;

    // pending snapshot after last MAC
    reg                        clr_pending;

    wire s_pipe_end = pipe_i_valid[PIPE-1];

    wire signed [MUL_WIDTH-1:0] mul_w =
        $signed(pipe_a[PIPE-1]) * $signed(pipe_b[PIPE-1]);

    // Keep a local register on the raw multiplier output so Vivado can map it
    // to the DSP MREG stage instead of spilling the product into fabric.
    always @(posedge i_clk) begin
        if (i_rst) begin
            mul_r       <= '0;
            mul_valid_r <= 1'b0;
            mul_clr_r   <= 1'b0;
        end else begin
            mul_r       <= mul_w;
            mul_valid_r <= s_pipe_end;
            mul_clr_r   <= (s_pipe_end ? i_clr : 1'b0);
        end
    end

    wire signed [ACC_WIDTH-1:0] mul_ext_r =
        {{(ACC_WIDTH-MUL_WIDTH){mul_r[MUL_WIDTH-1]}}, mul_r};

    // Ключевая форма для DSP inference
    wire signed [ACC_WIDTH-1:0] mac_next_w =
        $signed(op_acc_r) + $signed(mul_ext_r);

    always @(posedge i_clk) begin
        if (i_rst) begin
            op_acc_r      <= '0;
            op_acc_snap_r <= '0;
            op_acc_valid  <= 1'b0;
            clr_pending   <= 1'b0;
        end else begin
            op_acc_valid <= 1'b0;

            // Такт после последнего MAC:
            // отдать накопленное значение и сразу,
            // при наличии нового valid, начать новое накопление
            if (clr_pending) begin
                op_acc_snap_r <= op_acc_r;
                op_acc_valid  <= 1'b1;

                if (mul_valid_r) begin
                    // первый элемент следующего окна не теряем
                    op_acc_r <= mul_ext_r;

                    // на случай back-to-back окон длиной 1
                    clr_pending <= mul_clr_r;
                end else begin
                    op_acc_r    <= '0;
                    clr_pending <= 1'b0;
                end
            end
            // Обычный MAC-такт
            else if (mul_valid_r) begin
                op_acc_r <= mac_next_w;
                clr_pending <= mul_clr_r;
            end
        end
    end

    assign o_valid     = op_acc_valid;
    assign o_c         = op_acc_snap_r;

    assign o_valid_mul = s_pipe_end;
endmodule
