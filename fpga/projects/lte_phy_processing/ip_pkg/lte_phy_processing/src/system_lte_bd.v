// block design wrapper

module system_lte_bd #(
    // размерность данных
    parameter DATA_W            = 16,
    // целевая частота дискретизации для PSS
    parameter LTE_CORR_FS       = 1920000,
    // количество корреляторов на PSS
    parameter LTE_CORR_LANES    = 4,
    // длительность PSS в семплах
    parameter LTE_PSS_TD_LEN    = 128
) (
    input wire i_clk,
    input wire i_rst,

    input wire signed [DATA_W - 1: 0]    i_data_i1,
    input wire signed [DATA_W - 1: 0]    i_data_q1,
    input wire                           i_data_valid_i1,
    input wire                           i_data_valid_q1,

    output wire signed [DATA_W - 1: 0]   o_data_i1,
    output wire signed [DATA_W - 1: 0]   o_data_q1,
    output wire                          o_data_valid_1,
    output wire                          o_pss_valid,

    output wire [3:0]                    o_dbg_pss_idx,
    output wire [31:0]                   o_dbg_shift,

    output wire  [33:0]                  o_dbg_mag_pss0,
    output wire  [33:0]                  o_dbg_mag_pss1,
    output wire  [33:0]                  o_dbg_mag_pss2
);
    system_lte #(
        .DATA_W(DATA_W), 
        .LTE_CORR_FS(LTE_CORR_FS), 
        .LTE_CORR_LANES(LTE_CORR_LANES),
        .LTE_PSS_TD_LEN(LTE_PSS_TD_LEN)
    ) u_system_lte_bd (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data_i1(i_data_i1),
        .i_data_q1(i_data_q1),
        .i_data_valid_i1(i_data_valid_i1),
        .i_data_valid_q1(i_data_valid_q1),
        .o_data_i1(o_data_i1),
        .o_data_q1(o_data_q1),
        .o_data_valid_1(o_data_valid_1),
        .o_pss_valid(o_pss_valid),
        .o_dbg_pss_idx(o_dbg_pss_idx),
        .o_dbg_shift(o_dbg_shift),
        .o_dbg_mag_pss0(o_dbg_mag_pss0),
        .o_dbg_mag_pss1(o_dbg_mag_pss1),
        .o_dbg_mag_pss2(o_dbg_mag_pss2)
    );
endmodule
