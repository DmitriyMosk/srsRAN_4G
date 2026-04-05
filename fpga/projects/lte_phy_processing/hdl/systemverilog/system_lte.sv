`include "lte_hw_params.vh"

module system_lte #(
    // размерность данных верхнего уровня
    parameter int DATA_W            = 16,
    // целевая частота дискретизации для PSS
    parameter int LTE_CORR_FS       = 1920000,
    // количество корреляторов на PSS
    parameter int LTE_CORR_LANES    = 4,
    // длительность PSS в семплах
    parameter int LTE_PSS_TD_LEN    = 128,

    parameter int LTE_TARGET_FS     = 1_920_000,
    parameter int LTE_SUBFRAME_SPS  = (LTE_TARGET_FS / 200),
    parameter int LTE_BUF_CAP       = LTE_SUBFRAME_SPS
)(
    input  wire                           i_clk,
    input  wire                           i_rst,

    input  wire signed [DATA_W-1:0]       i_data_i1,
    input  wire signed [DATA_W-1:0]       i_data_q1,
    input  wire                           i_data_valid_i1,
    input  wire                           i_data_valid_q1,

    output wire signed [DATA_W-1:0]       o_data_i1,
    output wire signed [DATA_W-1:0]       o_data_q1,
    output wire                           o_data_valid_1,
    output wire                           o_pss_valid,

    output wire [$clog2(`LTE_PSS_COUNT)-1:0] o_dbg_pss_idx,
    output wire [31:0]                   o_dbg_shift,

    output wire [33:0]                    o_dbg_mag_pss0,
    output wire [33:0]                    o_dbg_mag_pss1,
    output wire [33:0]                    o_dbg_mag_pss2
);
    
    wire i_data_valid_1 = i_data_valid_i1 && i_data_valid_q1;
    wire pss_valid;
    
    lte_phy_sync #(
        .LTE_PSS_TD_LEN(LTE_PSS_TD_LEN),
        .K_LANES(LTE_CORR_LANES),
        .SUBFRAME_SPS(LTE_SUBFRAME_SPS),
        .BUF_CAP(LTE_BUF_CAP)
    ) u_lte_pss_detector (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data_i1(i_data_i1),
        .i_data_q1(i_data_q1),
        .i_valid(i_data_valid_1),
        .o_pss_idx(o_dbg_pss_idx),
        .o_pss_valid(pss_valid),
        .o_shift(o_dbg_shift),
        .o_dbg_mag_pss0(o_dbg_mag_pss0),
        .o_dbg_mag_pss1(o_dbg_mag_pss1),
        .o_dbg_mag_pss2(o_dbg_mag_pss2),
        .o_busy()
    );

    assign o_data_i1 = i_data_i1;
    assign o_data_q1 = i_data_q1;
    assign o_data_valid_1 = i_data_valid_1;
    assign o_pss_valid    = pss_valid;
endmodule
