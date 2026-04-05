`timescale 1ns/1ps
`include "lte_hw_params.vh"

module lte_phy_sync_k8_top (
    input  wire                               i_clk,
    input  wire                               i_rst,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_i1,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_q1,
    input  wire                               i_valid,

    output wire [$clog2(`LTE_PSS_COUNT)-1:0]  o_pss_idx,
    output wire                               o_pss_valid,
    output wire [31:0]                        o_shift,
    output wire                               o_busy,
    output wire [33:0]                        o_dbg_mag_pss0,
    output wire [33:0]                        o_dbg_mag_pss1,
    output wire [33:0]                        o_dbg_mag_pss2
);

    lte_phy_sync #(
        .K_LANES(8),
        .SUBFRAME_SPS(9600),
        .BUF_CAP(9600),
        .ONECLOCK(1'b0)
    ) u_lte_phy_sync (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data_i1(i_data_i1),
        .i_data_q1(i_data_q1),
        .i_valid(i_valid),
        .o_pss_idx(o_pss_idx),
        .o_pss_valid(o_pss_valid),
        .o_shift(o_shift),
        .o_busy(o_busy),
        .o_dbg_mag_pss0(o_dbg_mag_pss0),
        .o_dbg_mag_pss1(o_dbg_mag_pss1),
        .o_dbg_mag_pss2(o_dbg_mag_pss2)
    );

endmodule
