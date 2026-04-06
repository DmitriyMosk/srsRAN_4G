`timescale 1ns/1ps
`include "lte_hw_params.vh"

module lte_phy_pss_corr #(
    parameter int K_LANES        = 2,
    parameter int FMA_PIPE_SIZE  = 1,
    parameter int FMA_ACC_SIZE   = 48,
    parameter int LTE_PSS_TD_LEN = 128,
    parameter int SUBFRAME_SPS   = 9600
)(
    input  wire                               i_clk,
    input  wire                               i_rst,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_i1,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_q1,
    input  wire                               i_valid,

    output wire                               o_sample_ready,
    output reg  [$clog2(`LTE_PSS_COUNT)-1:0]  o_pss_idx,
    output reg                                o_pss_valid,
    output reg  [31:0]                        o_shift,
    output wire                               o_busy,

    output reg  [33:0]                        o_dbg_mag_pss0,
    output reg  [33:0]                        o_dbg_mag_pss1,
    output reg  [33:0]                        o_dbg_mag_pss2
);

    localparam int PSS_COUNT      = `LTE_PSS_COUNT;
    localparam int ADC_W          = `HW_ADC_WIDTH;
    localparam int PSS_LEN        = LTE_PSS_TD_LEN;
    localparam int PACKED_W       = 2 * ADC_W;
    localparam int CORR_W         = 16;
    localparam int COEF_W         = 32;
    localparam int MAG_W          = FMA_ACC_SIZE + 2;
    localparam int PSS_ADDR_W     = (PSS_LEN <= 2) ? 1 : $clog2(PSS_LEN);
    localparam int FRAME_ADDR_W   = (SUBFRAME_SPS <= 2) ? 1 : $clog2(SUBFRAME_SPS);
    localparam int FRAME_CNT_W    = (SUBFRAME_SPS <= 1) ? 1 : $clog2(SUBFRAME_SPS + 1);
    localparam int STARTS_PER_FRAME = SUBFRAME_SPS - PSS_LEN + 1;
    localparam int START_W        = (STARTS_PER_FRAME <= 1) ? 1 : $clog2(STARTS_PER_FRAME);
    localparam int LANE_W         = (K_LANES <= 1) ? 1 : $clog2(K_LANES + 1);
    localparam int MAX_SCAN_STEPS = PSS_LEN + K_LANES - 1;
    localparam int STEP_W         = (MAX_SCAN_STEPS <= 2) ? 1 : $clog2(MAX_SCAN_STEPS);

    // CAPTURE: collect one full subframe into frame_mem.
    // PRIME:   give the synchronous PSS ROM one cycle to produce tap 0.
    // STREAM:  walk a shared sample stream across K adjacent correlation lanes.
    // WAIT:    wait until every active lane returns its correlation result.
    // MERGE:   register the best result of the finished batch into frame_best.
    // OUTPUT:  copy the frame winner into the visible debug/output bus.
    localparam [2:0] ST_CAPTURE = 3'd0;
    localparam [2:0] ST_PRIME   = 3'd1;
    localparam [2:0] ST_STREAM  = 3'd2;
    localparam [2:0] ST_WAIT    = 3'd3;
    localparam [2:0] ST_MERGE   = 3'd4;
    localparam [2:0] ST_OUTPUT  = 3'd5;

    function automatic signed [CORR_W-1:0] sx_adc(input signed [ADC_W-1:0] v);
        begin
            if (CORR_W == ADC_W)
                sx_adc = v;
            else
                sx_adc = {{(CORR_W-ADC_W){v[ADC_W-1]}}, v};
        end
    endfunction

    function automatic [MAG_W-1:0] abs_s(input signed [FMA_ACC_SIZE-1:0] v);
        begin
            abs_s = v[FMA_ACC_SIZE-1] ? $unsigned(-v) : $unsigned(v);
        end
    endfunction

    function automatic [MAG_W-1:0] l1mag(
        input signed [FMA_ACC_SIZE-1:0] re,
        input signed [FMA_ACC_SIZE-1:0] im
    );
        begin
            l1mag = abs_s(re) + abs_s(im);
        end
    endfunction

    function automatic int active_lanes_from(input int start_idx);
        int remaining;
        begin
            remaining = STARTS_PER_FRAME - start_idx;
            if (remaining <= 0)
                active_lanes_from = 0;
            else if (remaining >= K_LANES)
                active_lanes_from = K_LANES;
            else
                active_lanes_from = remaining;
        end
    endfunction

    function automatic int scan_steps_from_lanes(input int lane_count);
        begin
            if (lane_count <= 0)
                scan_steps_from_lanes = 1;
            else
                scan_steps_from_lanes = PSS_LEN + lane_count - 1;
        end
    endfunction

    initial begin
        if (K_LANES < 1)
            $fatal(1, "lte_phy_pss_corr: K_LANES must be >= 1");
        if (PSS_LEN != 128 && PSS_LEN != 256)
            $fatal(1, "lte_phy_pss_corr: only PSS_LEN=128/256 are supported");
        if (SUBFRAME_SPS < PSS_LEN)
            $fatal(1, "lte_phy_pss_corr: SUBFRAME_SPS must be >= PSS_LEN");
    end

    reg [2:0]                   state;
    reg [FRAME_CNT_W-1:0]       capture_count;
    reg [START_W-1:0]           batch_base_idx;
    reg [LANE_W-1:0]            batch_active_lanes;
    reg [STEP_W-1:0]            batch_scan_steps;
    reg [STEP_W-1:0]            feed_step;
    reg [K_LANES-1:0]           lane_done;

    reg signed [CORR_W-1:0]     sample_i_r;
    reg signed [CORR_W-1:0]     sample_q_r;
    reg [STEP_W-1:0]            sample_step_r;
    reg                         sample_valid_r;

    reg                         rom_ena;
    reg [PSS_ADDR_W-1:0]        rom_addr_cnt;
    wire [31:0]                 pss_rom_dout [0:PSS_COUNT-1];
    reg [COEF_W-1:0]            coef_pipe [0:PSS_COUNT-1][0:K_LANES-1];

    reg                         frame_best_valid;
    reg [MAG_W-1:0]             frame_best_mag;
    reg [$clog2(PSS_COUNT)-1:0] frame_best_pss;
    reg [31:0]                  frame_best_shift;
    reg [MAG_W-1:0]             frame_best_mag0;
    reg [MAG_W-1:0]             frame_best_mag1;
    reg [MAG_W-1:0]             frame_best_mag2;
    reg                         batch_best_valid;
    reg [MAG_W-1:0]             batch_best_mag;
    reg [$clog2(PSS_COUNT)-1:0] batch_best_pss;
    reg [31:0]                  batch_best_shift;
    reg [MAG_W-1:0]             batch_best_mag0;
    reg [MAG_W-1:0]             batch_best_mag1;
    reg [MAG_W-1:0]             batch_best_mag2;
    reg                         lane_result_valid [0:K_LANES-1];
    reg [MAG_W-1:0]             lane_result_mag   [0:K_LANES-1];
    reg [$clog2(PSS_COUNT)-1:0] lane_result_pss   [0:K_LANES-1];
    reg [31:0]                  lane_result_shift [0:K_LANES-1];
    reg [MAG_W-1:0]             lane_result_mag0  [0:K_LANES-1];
    reg [MAG_W-1:0]             lane_result_mag1  [0:K_LANES-1];
    reg [MAG_W-1:0]             lane_result_mag2  [0:K_LANES-1];

    wire [PACKED_W-1:0]         frame_wr_data = {i_data_q1, i_data_i1};
    wire                        frame_wr_en   = (state == ST_CAPTURE) && i_valid;
    reg                         frame_rd_en;
    reg [FRAME_ADDR_W-1:0]      frame_rd_addr;
    wire [PACKED_W-1:0]         frame_rd_data;

    mem_frame_buffer #(
        .CAP(SUBFRAME_SPS),
        .WIDTH(PACKED_W)
    ) u_frame_mem (
        .i_clk(i_clk),
        .i_wr_en(frame_wr_en),
        .i_wr_addr(capture_count[FRAME_ADDR_W-1:0]),
        .i_wr_data(frame_wr_data),
        .i_rd_en(frame_rd_en),
        .i_rd_addr(frame_rd_addr),
        .o_rd_data(frame_rd_data)
    );

    wire lane_valid [0:K_LANES-1];
    wire corr_rst = i_rst || (state == ST_CAPTURE) || (state == ST_PRIME);

    genvar g_lane;
    generate
        for (g_lane = 0; g_lane < K_LANES; g_lane = g_lane + 1) begin : gen_lane_valid
            assign lane_valid[g_lane] = sample_valid_r &&
                                        (g_lane < batch_active_lanes) &&
                                        (sample_step_r >= g_lane) &&
                                        (sample_step_r < (PSS_LEN + g_lane));
        end
    endgenerate

    generate
        if (PSS_LEN == 128) begin : gen_pss_128
            pss_0_rom_td_128sps u_pss0 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(pss_rom_dout[0]));
            pss_1_rom_td_128sps u_pss1 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(pss_rom_dout[1]));
            pss_2_rom_td_128sps u_pss2 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(pss_rom_dout[2]));
        end else begin : gen_pss_256
            pss_0_rom_td_256sps u_pss0 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(pss_rom_dout[0]));
            pss_1_rom_td_256sps u_pss1 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(pss_rom_dout[1]));
            pss_2_rom_td_256sps u_pss2 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(pss_rom_dout[2]));
        end
    endgenerate

    reg signed [FMA_ACC_SIZE-1:0]  corr_re [0:PSS_COUNT-1][0:K_LANES-1];
    reg signed [FMA_ACC_SIZE-1:0]  corr_im [0:PSS_COUNT-1][0:K_LANES-1];
    reg                            corr_v  [0:PSS_COUNT-1][0:K_LANES-1];

    genvar g_pss;
    generate
        for (g_lane = 0; g_lane < K_LANES; g_lane = g_lane + 1) begin : gen_corr_lane
            for (g_pss = 0; g_pss < PSS_COUNT; g_pss = g_pss + 1) begin : gen_corr_pss
                wire signed [FMA_ACC_SIZE-1:0] corr_re_w;
                wire signed [FMA_ACC_SIZE-1:0] corr_im_w;
                wire                           corr_v_w;

                math_complex_corr #(
                    .WIDTH(CORR_W),
                    .CORR_SEQ_SIZE(PSS_LEN),
                    .fma_pipe_size(FMA_PIPE_SIZE),
                    .fma_acc_size(FMA_ACC_SIZE)
                ) u_corr (
                    .i_rst(corr_rst),
                    .i_clk(i_clk),
                    .i_data_i1(sample_i_r),
                    .i_data_q1(sample_q_r),
                    .i_data1_valid(lane_valid[g_lane]),
                    .i_data_i2($signed(coef_pipe[g_pss][g_lane][15:0])),
                    .i_data_q2($signed(coef_pipe[g_pss][g_lane][31:16])),
                    .i_data2_valid(lane_valid[g_lane]),
                    .o_valid(corr_v_w),
                    .o_im(corr_im_w),
                    .o_re(corr_re_w)
                );

                // Register the correlator outputs locally so the long routes
                // from DSP results into peak-selection logic are cut by one
                // extra pipeline stage per lane/PSS branch.
                always @(posedge i_clk) begin
                    if (corr_rst) begin
                        corr_v[g_pss][g_lane]  <= 1'b0;
                        corr_re[g_pss][g_lane] <= '0;
                        corr_im[g_pss][g_lane] <= '0;
                    end else begin
                        corr_v[g_pss][g_lane]  <= corr_v_w;
                        corr_re[g_pss][g_lane] <= corr_re_w;
                        corr_im[g_pss][g_lane] <= corr_im_w;
                    end
                end
            end
        end
    endgenerate

    generate
        for (g_lane = 0; g_lane < K_LANES; g_lane = g_lane + 1) begin : gen_lane_result
            wire                         lane_corr_valid_w;
            wire [MAG_W-1:0]             lane_mag0_w;
            wire [MAG_W-1:0]             lane_mag1_w;
            wire [MAG_W-1:0]             lane_mag2_w;
            wire [MAG_W-1:0]             lane_best_mag_w;
            wire [$clog2(PSS_COUNT)-1:0] lane_best_pss_w;

            assign lane_corr_valid_w = corr_v[0][g_lane] && corr_v[1][g_lane] && corr_v[2][g_lane];
            assign lane_mag0_w = l1mag(corr_re[0][g_lane], corr_im[0][g_lane]);
            assign lane_mag1_w = l1mag(corr_re[1][g_lane], corr_im[1][g_lane]);
            assign lane_mag2_w = l1mag(corr_re[2][g_lane], corr_im[2][g_lane]);

            assign lane_best_mag_w = ((lane_mag2_w >= lane_mag1_w) && (lane_mag2_w >= lane_mag0_w)) ? lane_mag2_w :
                                     ((lane_mag1_w >= lane_mag0_w) ? lane_mag1_w : lane_mag0_w);
            assign lane_best_pss_w = ((lane_mag2_w >= lane_mag1_w) && (lane_mag2_w >= lane_mag0_w)) ? 2 :
                                     ((lane_mag1_w >= lane_mag0_w) ? 1 : 0);

            // Cut the long DSP-to-reducer path: first register the complex
            // correlation result, then register the per-lane winner, and only
            // after that update the frame-global maximum in the control FSM.
            always @(posedge i_clk) begin
                if (corr_rst) begin
                    lane_result_valid[g_lane] <= 1'b0;
                    lane_result_mag[g_lane]   <= '0;
                    lane_result_pss[g_lane]   <= '0;
                    lane_result_shift[g_lane] <= '0;
                    lane_result_mag0[g_lane]  <= '0;
                    lane_result_mag1[g_lane]  <= '0;
                    lane_result_mag2[g_lane]  <= '0;
                end else if ((g_lane < batch_active_lanes) &&
                             !lane_result_valid[g_lane] &&
                             lane_corr_valid_w) begin
                    lane_result_valid[g_lane] <= 1'b1;
                    lane_result_mag[g_lane]   <= lane_best_mag_w;
                    lane_result_pss[g_lane]   <= lane_best_pss_w;
                    lane_result_shift[g_lane] <= batch_base_idx + g_lane;
                    lane_result_mag0[g_lane]  <= lane_mag0_w;
                    lane_result_mag1[g_lane]  <= lane_mag1_w;
                    lane_result_mag2[g_lane]  <= lane_mag2_w;
                end
            end
        end
    endgenerate

    assign o_sample_ready = (state == ST_CAPTURE);
    assign o_busy = (state != ST_CAPTURE);

    integer li;
    integer pi;
    always @(posedge i_clk) begin
        reg [K_LANES-1:0]           active_mask;
        reg [K_LANES-1:0]           lane_done_n;
        reg                         batch_best_valid_n;
        reg [MAG_W-1:0]             batch_best_mag_n;
        reg [$clog2(PSS_COUNT)-1:0] batch_best_pss_n;
        reg [31:0]                  batch_best_shift_n;
        reg [MAG_W-1:0]             batch_best_mag0_n;
        reg [MAG_W-1:0]             batch_best_mag1_n;
        reg [MAG_W-1:0]             batch_best_mag2_n;
        reg                         batch_all_done;
        integer                     next_base_int;
        integer                     next_lanes_int;
        integer                     next_steps_int;
        integer                     init_lanes_int;
        integer                     init_steps_int;

        if (i_rst) begin
            state             <= ST_CAPTURE;
            capture_count     <= '0;
            batch_base_idx    <= '0;
            batch_active_lanes<= '0;
            batch_scan_steps  <= '0;
            feed_step         <= '0;
            lane_done         <= '0;

            sample_i_r        <= '0;
            sample_q_r        <= '0;
            sample_step_r     <= '0;
            sample_valid_r    <= 1'b0;
            frame_rd_en       <= 1'b0;
            frame_rd_addr     <= '0;

            rom_ena           <= 1'b0;
            rom_addr_cnt      <= '0;

            o_pss_idx         <= '0;
            o_pss_valid       <= 1'b0;
            o_shift           <= 32'd0;
            o_dbg_mag_pss0    <= 34'd0;
            o_dbg_mag_pss1    <= 34'd0;
            o_dbg_mag_pss2    <= 34'd0;

            frame_best_valid  <= 1'b0;
            frame_best_mag    <= '0;
            frame_best_pss    <= '0;
            frame_best_shift  <= 32'd0;
            frame_best_mag0   <= '0;
            frame_best_mag1   <= '0;
            frame_best_mag2   <= '0;
            batch_best_valid  <= 1'b0;
            batch_best_mag    <= '0;
            batch_best_pss    <= '0;
            batch_best_shift  <= 32'd0;
            batch_best_mag0   <= '0;
            batch_best_mag1   <= '0;
            batch_best_mag2   <= '0;

            for (pi = 0; pi < PSS_COUNT; pi = pi + 1) begin
                for (li = 0; li < K_LANES; li = li + 1)
                    coef_pipe[pi][li] <= '0;
            end
        end else begin
            o_pss_valid <= 1'b0;
            frame_rd_en <= 1'b0;

            active_mask = '0;
            for (li = 0; li < K_LANES; li = li + 1) begin
                if (li < batch_active_lanes)
                    active_mask[li] = 1'b1;
            end

            lane_done_n        = lane_done;

            for (li = 0; li < K_LANES; li = li + 1) begin
                if ((li < batch_active_lanes) &&
                    !lane_done_n[li] &&
                    lane_result_valid[li]) begin
                    lane_done_n[li] = 1'b1;
                end
            end

            batch_all_done = ((lane_done_n & active_mask) == active_mask) && (batch_active_lanes != 0);

            lane_done        <= lane_done_n;

            case (state)
                ST_CAPTURE: begin
                    sample_valid_r <= 1'b0;
                    rom_ena        <= 1'b0;

                    if (i_valid) begin
                        if (capture_count == (SUBFRAME_SPS - 1)) begin
                            init_lanes_int = active_lanes_from(0);
                            init_steps_int = scan_steps_from_lanes(init_lanes_int);

                            capture_count      <= '0;
                            batch_base_idx     <= '0;
                            batch_active_lanes <= init_lanes_int[LANE_W-1:0];
                            batch_scan_steps   <= init_steps_int[STEP_W-1:0];
                            feed_step          <= '0;
                            lane_done          <= '0;
                            frame_best_valid   <= 1'b0;
                            frame_best_mag     <= '0;
                            frame_best_pss     <= '0;
                            frame_best_shift   <= 32'd0;
                            frame_best_mag0    <= '0;
                            frame_best_mag1    <= '0;
                            frame_best_mag2    <= '0;
                            batch_best_valid   <= 1'b0;
                            batch_best_mag     <= '0;
                            batch_best_pss     <= '0;
                            batch_best_shift   <= 32'd0;
                            batch_best_mag0    <= '0;
                            batch_best_mag1    <= '0;
                            batch_best_mag2    <= '0;

                            for (pi = 0; pi < PSS_COUNT; pi = pi + 1) begin
                                for (li = 0; li < K_LANES; li = li + 1)
                                    coef_pipe[pi][li] <= '0;
                            end

                            frame_rd_en   <= 1'b1;
                            frame_rd_addr <= '0;
                            rom_ena      <= 1'b1;
                            rom_addr_cnt <= '0;
                            state        <= ST_PRIME;
                        end else begin
                            capture_count <= capture_count + 1'b1;
                        end
                    end
                end

                ST_PRIME: begin
                    sample_valid_r <= 1'b0;

                    if (batch_scan_steps > 1) begin
                        frame_rd_en   <= 1'b1;
                        frame_rd_addr <= batch_base_idx + 1'b1;
                    end

                    if (PSS_LEN > 1) begin
                        rom_ena      <= 1'b1;
                        rom_addr_cnt <= 1;
                    end else begin
                        rom_ena <= 1'b0;
                    end

                    state <= ST_STREAM;
                end

                ST_STREAM: begin
                    // One shared sample stream fans out into all active lanes.
                    // Each lane sees the same sample with a different delayed
                    // coefficient so that window starts are staggered by +1.
                    sample_i_r     <= sx_adc($signed(frame_rd_data[ADC_W-1:0]));
                    sample_q_r     <= sx_adc($signed(frame_rd_data[PACKED_W-1:ADC_W]));
                    sample_step_r  <= feed_step;
                    sample_valid_r <= 1'b1;

                    for (pi = 0; pi < PSS_COUNT; pi = pi + 1) begin
                        coef_pipe[pi][0] <= (feed_step < PSS_LEN) ? pss_rom_dout[pi] : '0;
                        for (li = 1; li < K_LANES; li = li + 1)
                            coef_pipe[pi][li] <= coef_pipe[pi][li-1];
                    end

                    if ((feed_step + 2) < PSS_LEN) begin
                        rom_ena      <= 1'b1;
                        rom_addr_cnt <= feed_step + 2;
                    end else begin
                        rom_ena <= 1'b0;
                    end

                    if ((feed_step + 2) < batch_scan_steps) begin
                        frame_rd_en   <= 1'b1;
                        frame_rd_addr <= batch_base_idx + feed_step + 2'd2;
                    end

                    if (feed_step == (batch_scan_steps - 1)) begin
                        feed_step <= '0;
                        state     <= ST_WAIT;
                    end else begin
                        feed_step <= feed_step + 1'b1;
                    end
                end

                ST_WAIT: begin
                    sample_valid_r <= 1'b0;
                    rom_ena        <= 1'b0;

                    if (batch_all_done) begin
                        batch_best_valid_n = 1'b0;
                        batch_best_mag_n   = '0;
                        batch_best_pss_n   = '0;
                        batch_best_shift_n = '0;
                        batch_best_mag0_n  = '0;
                        batch_best_mag1_n  = '0;
                        batch_best_mag2_n  = '0;

                        for (li = 0; li < K_LANES; li = li + 1) begin
                            if ((li < batch_active_lanes) && lane_result_valid[li]) begin
                                if (!batch_best_valid_n ||
                                    (lane_result_mag[li] > batch_best_mag_n) ||
                                    ((lane_result_mag[li] == batch_best_mag_n) && (lane_result_shift[li] < batch_best_shift_n))) begin
                                    batch_best_valid_n = 1'b1;
                                    batch_best_mag_n   = lane_result_mag[li];
                                    batch_best_pss_n   = lane_result_pss[li];
                                    batch_best_shift_n = lane_result_shift[li];
                                    batch_best_mag0_n  = lane_result_mag0[li];
                                    batch_best_mag1_n  = lane_result_mag1[li];
                                    batch_best_mag2_n  = lane_result_mag2[li];
                                end
                            end
                        end

                        batch_best_valid <= batch_best_valid_n;
                        batch_best_mag   <= batch_best_mag_n;
                        batch_best_pss   <= batch_best_pss_n;
                        batch_best_shift <= batch_best_shift_n;
                        batch_best_mag0  <= batch_best_mag0_n;
                        batch_best_mag1  <= batch_best_mag1_n;
                        batch_best_mag2  <= batch_best_mag2_n;
                        state            <= ST_MERGE;
                    end
                end

                ST_MERGE: begin
                    sample_valid_r <= 1'b0;
                    rom_ena        <= 1'b0;

                    if (batch_best_valid &&
                        (!frame_best_valid ||
                         (batch_best_mag > frame_best_mag) ||
                         ((batch_best_mag == frame_best_mag) && (batch_best_shift < frame_best_shift)))) begin
                        frame_best_valid <= 1'b1;
                        frame_best_mag   <= batch_best_mag;
                        frame_best_pss   <= batch_best_pss;
                        frame_best_shift <= batch_best_shift;
                        frame_best_mag0  <= batch_best_mag0;
                        frame_best_mag1  <= batch_best_mag1;
                        frame_best_mag2  <= batch_best_mag2;
                    end

                    next_base_int = batch_base_idx + batch_active_lanes;
                    if (next_base_int >= STARTS_PER_FRAME) begin
                        state <= ST_OUTPUT;
                    end else begin
                        next_lanes_int = active_lanes_from(next_base_int);
                        next_steps_int = scan_steps_from_lanes(next_lanes_int);

                        batch_base_idx     <= next_base_int[START_W-1:0];
                        batch_active_lanes <= next_lanes_int[LANE_W-1:0];
                        batch_scan_steps   <= next_steps_int[STEP_W-1:0];
                        feed_step          <= '0;
                        lane_done          <= '0;
                        batch_best_valid   <= 1'b0;
                        batch_best_mag     <= '0;
                        batch_best_pss     <= '0;
                        batch_best_shift   <= '0;
                        batch_best_mag0    <= '0;
                        batch_best_mag1    <= '0;
                        batch_best_mag2    <= '0;

                        for (pi = 0; pi < PSS_COUNT; pi = pi + 1) begin
                            for (li = 0; li < K_LANES; li = li + 1)
                                coef_pipe[pi][li] <= '0;
                        end

                        frame_rd_en   <= 1'b1;
                        frame_rd_addr <= next_base_int[FRAME_ADDR_W-1:0];
                        rom_ena       <= 1'b1;
                        rom_addr_cnt  <= '0;
                        state         <= ST_PRIME;
                    end
                end

                ST_OUTPUT: begin
                    sample_valid_r <= 1'b0;
                    rom_ena        <= 1'b0;

                    if (frame_best_valid) begin
                        o_pss_valid    <= 1'b1;
                        o_pss_idx      <= frame_best_pss;
                        o_shift        <= frame_best_shift;
                        o_dbg_mag_pss0 <= frame_best_mag0[33:0];
                        o_dbg_mag_pss1 <= frame_best_mag1[33:0];
                        o_dbg_mag_pss2 <= frame_best_mag2[33:0];
                    end

                    state <= ST_CAPTURE;
                end

                default: begin
                    state          <= ST_CAPTURE;
                    sample_valid_r <= 1'b0;
                    rom_ena        <= 1'b0;
                end
            endcase
        end
    end
endmodule
