`timescale 1ns/1ps
`include "lte_hw_params.vh"

module lte_phy_sync #(
    parameter int K_LANES        = 2,
    parameter int FMA_PIPE_SIZE  = 1,
    parameter int FMA_ACC_SIZE   = 48,
    parameter int LTE_PSS_TD_LEN = 128,
    parameter int SUBFRAME_SPS   = 9600,
    parameter int BUF_CAP        = SUBFRAME_SPS,
    parameter bit ONECLOCK       = 1'b0
)(
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

    localparam int ADC_W       = `HW_ADC_WIDTH;
    localparam int PACKED_W    = 2 * ADC_W;
    localparam int FRAME_CNT_W = (SUBFRAME_SPS <= 1) ? 1 : $clog2(SUBFRAME_SPS + 1);
    localparam int MAX_QUEUED_FRAMES = (BUF_CAP / SUBFRAME_SPS) + 1;
    localparam int QFRAME_W = (MAX_QUEUED_FRAMES <= 1) ? 1 : $clog2(MAX_QUEUED_FRAMES + 1);

    initial begin
        if (BUF_CAP < SUBFRAME_SPS)
            $fatal(1, "lte_phy_sync: BUF_CAP must be >= SUBFRAME_SPS");
    end

    reg                   fifo_rd_ready_r;
    reg                   feed_active;
    reg [FRAME_CNT_W-1:0] feed_count;
    reg [FRAME_CNT_W-1:0] feed_reads_issued;
    reg [FRAME_CNT_W-1:0] frame_fill_count;
    reg [QFRAME_W-1:0]    queued_frames;
    reg                   overflow_sticky;

    wire                  fifo_full;
    wire                  fifo_empty;
    wire [PACKED_W-1:0]   fifo_rd_data;
    wire                  fifo_rd_valid;
    wire                  fifo_wd_fire;
    wire                  fifo_rd_fire;
    wire [PACKED_W-1:0]   fifo_wr_data = {i_data_q1, i_data_i1};
    wire [$clog2(BUF_CAP + 1)-1:0] fifo_level;

    wire                               core_sample_ready;
    wire [$clog2(`LTE_PSS_COUNT)-1:0]  core_pss_idx;
    wire                               core_pss_valid;
    wire [31:0]                        core_shift;
    wire                               core_busy;
    wire [33:0]                        core_mag_pss0;
    wire [33:0]                        core_mag_pss1;
    wire [33:0]                        core_mag_pss2;

    // ONECLOCK is a debug mode: stop accepting new ADC data while one full
    // captured frame is being pushed through the correlator.
    wire writes_blocked = ONECLOCK && (feed_active || core_busy);
    wire fifo_do_read   = fifo_rd_ready_r && !fifo_empty;
    wire fifo_do_write  = i_valid && !writes_blocked && (!fifo_full || fifo_do_read);
    // A frame becomes eligible either from already queued complete frames or
    // from the write that closes the currently filling subframe.
    wire frame_ready    = (queued_frames != 0) ||
                          (fifo_do_write && (frame_fill_count == (SUBFRAME_SPS - 1)));
    wire start_feed     = !feed_active &&
                          core_sample_ready &&
                          frame_ready;

    mem_ring_buffer #(
        .CAP(BUF_CAP),
        .WIDTH(PACKED_W)
    ) u_input_fifo (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_wd_data(fifo_wr_data),
        .i_wd_ready(i_valid && !writes_blocked),
        .i_rd_ready(fifo_rd_ready_r),
        .o_rd_data(fifo_rd_data),
        .o_rd_valid(fifo_rd_valid),
        .o_full(fifo_full),
        .o_empty(fifo_empty),
        .o_wd_fire(fifo_wd_fire),
        .o_rd_fire(fifo_rd_fire),
        .o_wd_idx(),
        .o_rd_idx(),
        .o_level(fifo_level)
    );

    lte_phy_pss_corr #(
        .K_LANES(K_LANES),
        .FMA_PIPE_SIZE(FMA_PIPE_SIZE),
        .FMA_ACC_SIZE(FMA_ACC_SIZE),
        .LTE_PSS_TD_LEN(LTE_PSS_TD_LEN),
        .SUBFRAME_SPS(SUBFRAME_SPS)
    ) u_lte_phy_pss_corr (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data_i1($signed(fifo_rd_data[ADC_W-1:0])),
        .i_data_q1($signed(fifo_rd_data[PACKED_W-1:ADC_W])),
        .i_valid(fifo_rd_valid),
        .o_sample_ready(core_sample_ready),
        .o_pss_idx(core_pss_idx),
        .o_pss_valid(core_pss_valid),
        .o_shift(core_shift),
        .o_busy(core_busy),
        .o_dbg_mag_pss0(core_mag_pss0),
        .o_dbg_mag_pss1(core_mag_pss1),
        .o_dbg_mag_pss2(core_mag_pss2)
    );

    always @(posedge i_clk) begin
        if (i_rst) begin
            fifo_rd_ready_r <= 1'b0;
            feed_active     <= 1'b0;
            feed_count      <= '0;
            feed_reads_issued <= '0;
            frame_fill_count<= '0;
            queued_frames   <= '0;
            overflow_sticky <= 1'b0;
        end else begin
            reg [FRAME_CNT_W-1:0] frame_fill_count_n;
            reg [FRAME_CNT_W-1:0] feed_reads_issued_n;
            reg [QFRAME_W-1:0]    queued_frames_n;

            fifo_rd_ready_r <= 1'b0;
            frame_fill_count_n = frame_fill_count;
            feed_reads_issued_n = feed_reads_issued;
            queued_frames_n    = queued_frames;

            if (i_valid && !fifo_do_write)
                overflow_sticky <= 1'b1;

            if (fifo_do_write) begin
                if (frame_fill_count_n == (SUBFRAME_SPS - 1)) begin
                    frame_fill_count_n = '0;
                    if (queued_frames_n < MAX_QUEUED_FRAMES[QFRAME_W-1:0])
                        queued_frames_n = queued_frames_n + 1'b1;
                end else begin
                    frame_fill_count_n = frame_fill_count_n + 1'b1;
                end
            end

            if (!feed_active && start_feed) begin
                feed_active <= 1'b1;
                feed_count  <= '0;
                feed_reads_issued_n = '0;
                if (!fifo_empty && (feed_reads_issued_n < SUBFRAME_SPS)) begin
                    fifo_rd_ready_r <= 1'b1;
                    feed_reads_issued_n = feed_reads_issued_n + 1'b1;
                end
            end

            // Limit read requests by the number of issued frame samples, not by
            // returned valids. This avoids a hidden extra read on the frame
            // boundary while fifo_rd_valid is still in flight.
            if (feed_active && core_sample_ready && !fifo_empty && (feed_reads_issued_n < SUBFRAME_SPS)) begin
                fifo_rd_ready_r <= 1'b1;
                feed_reads_issued_n = feed_reads_issued_n + 1'b1;
            end

            if (fifo_rd_valid) begin
                if (feed_count == (SUBFRAME_SPS - 1)) begin
                    feed_active <= 1'b0;
                    feed_count  <= '0;
                    feed_reads_issued_n = '0;
                    if (queued_frames_n != 0)
                        queued_frames_n = queued_frames_n - 1'b1;
                end else begin
                    feed_count <= feed_count + 1'b1;
                end
            end

            frame_fill_count <= frame_fill_count_n;
            feed_reads_issued <= feed_reads_issued_n;
            queued_frames    <= queued_frames_n;
        end
    end

    assign o_pss_idx      = core_pss_idx;
    assign o_pss_valid    = core_pss_valid;
    assign o_shift        = core_shift;
    assign o_dbg_mag_pss0 = core_mag_pss0;
    assign o_dbg_mag_pss1 = core_mag_pss1;
    assign o_dbg_mag_pss2 = core_mag_pss2;
    assign o_busy         = feed_active || core_busy;

endmodule
