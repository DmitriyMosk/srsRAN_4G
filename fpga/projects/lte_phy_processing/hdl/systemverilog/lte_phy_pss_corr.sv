`timescale 1ns/1ps
`include "lte_hw_params.vh"

module lte_phy_pss_corr #(
    parameter int K_LANES        = 2,
    parameter int FMA_PIPE_SIZE  = 1,
    parameter int FMA_ACC_SIZE   = 48,
    parameter int LTE_PSS_TD_LEN = 128,
    parameter int LTE_TARGET_FS  = 1_920_000,
    parameter int RING_CAP       = 256
)(
    input  wire                               i_clk,
    input  wire                               i_rst,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_i1,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_q1,
    input  wire                               i_valid,

    output reg  [$clog2(`LTE_PSS_COUNT)-1:0]  o_pss_idx,
    output reg                                o_pss_valid,
    output reg  [31:0]                        o_shift,
    output wire                               o_busy,

    output reg  [33:0]                        o_dbg_mag_pss0,
    output reg  [33:0]                        o_dbg_mag_pss1,
    output reg  [33:0]                        o_dbg_mag_pss2,
    output reg  [31:0]                        o_dbg_abs_sample
);

    localparam int PSS_COUNT      = `LTE_PSS_COUNT;
    localparam int ADC_W          = `HW_ADC_WIDTH;
    localparam int PSS_LEN        = LTE_PSS_TD_LEN;
    localparam int PSS_ADDR_W     = (PSS_LEN <= 2) ? 1 : $clog2(PSS_LEN);
    localparam int PACKED_W       = 2 * ADC_W;
    localparam int CORR_W         = 16;
    localparam int COEF_W         = 32;
    localparam int MAG_W          = FMA_ACC_SIZE + 2;
    localparam int SCAN_STEPS     = PSS_LEN + K_LANES - 1;
    localparam int STEP_W         = (SCAN_STEPS <= 2) ? 1 : $clog2(SCAN_STEPS);
    localparam int WINCNT_W       = (SCAN_STEPS <= 1) ? 1 : $clog2(SCAN_STEPS + 1);
    localparam int WINDOW_ADDR_W  = (SCAN_STEPS <= 2) ? 1 : $clog2(SCAN_STEPS);
    localparam int PERIOD_SPS     = LTE_TARGET_FS / 200;

    localparam [1:0] ST_FILL   = 2'd0;
    localparam [1:0] ST_PRIME  = 2'd1;
    localparam [1:0] ST_STREAM = 2'd2;
    localparam [1:0] ST_WAIT   = 2'd3;

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

    function automatic [WINDOW_ADDR_W-1:0] win_next_idx(
        input [WINDOW_ADDR_W-1:0] idx
    );
        begin
            if (idx == (SCAN_STEPS - 1))
                win_next_idx = '0;
            else
                win_next_idx = idx + 1'b1;
        end
    endfunction

    function automatic [WINDOW_ADDR_W-1:0] win_advance(
        input [WINDOW_ADDR_W-1:0] idx,
        input integer delta
    );
        integer tmp;
        begin
            tmp = idx + delta;
            if (tmp >= SCAN_STEPS)
                tmp = tmp - SCAN_STEPS;
            win_advance = tmp[WINDOW_ADDR_W-1:0];
        end
    endfunction

    function automatic [$clog2(PSS_COUNT)-1:0] best_pss_idx(
        input [MAG_W-1:0] mag0,
        input [MAG_W-1:0] mag1,
        input [MAG_W-1:0] mag2
    );
        begin
            if ((mag2 >= mag1) && (mag2 >= mag0))
                best_pss_idx = 2;
            else if (mag1 >= mag0)
                best_pss_idx = 1;
            else
                best_pss_idx = 0;
        end
    endfunction

    function automatic [MAG_W-1:0] best_pss_mag(
        input [MAG_W-1:0] mag0,
        input [MAG_W-1:0] mag1,
        input [MAG_W-1:0] mag2
    );
        begin
            if ((mag2 >= mag1) && (mag2 >= mag0))
                best_pss_mag = mag2;
            else if (mag1 >= mag0)
                best_pss_mag = mag1;
            else
                best_pss_mag = mag0;
        end
    endfunction

    initial begin
        if (K_LANES < 1)
            $fatal(1, "lte_phy_pss_corr: K_LANES must be >= 1");
        if (PSS_LEN != 128 && PSS_LEN != 256)
            $fatal(1, "lte_phy_pss_corr: only PSS_LEN=128/256 are supported");
        if (PERIOD_SPS < 1)
            $fatal(1, "lte_phy_pss_corr: PERIOD_SPS must be >= 1");
        if (RING_CAP < SCAN_STEPS)
            $fatal(1, "lte_phy_pss_corr: RING_CAP must be >= SCAN_STEPS");
    end

    // -------------------------------------------------------------------------
    // Input ring buffer
    // -------------------------------------------------------------------------
    reg  [31:0]           abs_in_count;
    reg  [31:0]           rd_abs_count;
    reg                   overflow_sticky;
    reg                   ring_rd_ready_r;
    reg                   fill_pending;
    reg  [31:0]           fill_abs_pending;

    wire                  ring_full;
    wire                  ring_empty;
    wire                  ring_wd_fire;
    wire                  ring_rd_fire;
    wire [PACKED_W-1:0]   ring_rd_data;
    wire                  ring_rd_valid;
    wire [PACKED_W-1:0]   ring_wr_data = {i_data_q1, i_data_i1};
    wire                  ring_do_read = ring_rd_ready_r && !ring_empty;

    mem_ring_buffer #(
        .CAP(RING_CAP),
        .WIDTH(PACKED_W)
    ) u_ring (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_wd_data(ring_wr_data),
        .i_wd_ready(i_valid),
        .i_rd_ready(ring_rd_ready_r),
        .o_rd_data(ring_rd_data),
        .o_rd_valid(ring_rd_valid),
        .o_full(ring_full),
        .o_empty(ring_empty),
        .o_wd_fire(ring_wd_fire),
        .o_rd_fire(ring_rd_fire),
        .o_wd_idx(),
        .o_rd_idx(),
        .o_level()
    );

    // -------------------------------------------------------------------------
    // Sliding batch buffer:
    // keeps SCAN_STEPS samples and advances by K_LANES without physically shifting
    // -------------------------------------------------------------------------
    reg [PACKED_W-1:0] window_mem [0:SCAN_STEPS-1];
    reg [WINCNT_W-1:0]      window_count;
    reg [WINDOW_ADDR_W-1:0] window_head_ptr;
    reg [WINDOW_ADDR_W-1:0] window_wr_ptr;
    reg [WINDOW_ADDR_W-1:0] window_rd_ptr;
    reg [31:0]              window_base_abs;

    // -------------------------------------------------------------------------
    // Batch scheduler and shared sample stream
    // -------------------------------------------------------------------------
    reg [1:0]         state;
    reg [STEP_W-1:0]  feed_step;
    reg [31:0]        batch_base_abs;
    reg [K_LANES-1:0] lane_done;

    reg signed [CORR_W-1:0] sample_i_r;
    reg signed [CORR_W-1:0] sample_q_r;
    reg [STEP_W-1:0]        sample_step_r;
    reg                     sample_valid_r;

    wire lane_valid [0:K_LANES-1];

    genvar g_lane;
    generate
        for (g_lane = 0; g_lane < K_LANES; g_lane = g_lane + 1) begin : gen_lane_valid
            assign lane_valid[g_lane] = sample_valid_r &&
                                        (sample_step_r >= g_lane) &&
                                        (sample_step_r < (PSS_LEN + g_lane));
        end
    endgenerate

    // -------------------------------------------------------------------------
    // PSS coefficient stream:
    // one ROM tap per PSS is read every cycle, then delayed across lanes
    // -------------------------------------------------------------------------
    reg                  rom_ena;
    reg [PSS_ADDR_W-1:0] rom_addr_cnt;
    wire [31:0]          pss_rom_dout [0:PSS_COUNT-1];

    // coef_pipe[pss][lane]:
    // lane 0 sees the newest tap, lane N sees the same tap delayed by N cycles
    reg [COEF_W-1:0] coef_pipe [0:PSS_COUNT-1][0:K_LANES-1];

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

    // -------------------------------------------------------------------------
    // 3 x K_LANES correlators
    // -------------------------------------------------------------------------
    wire signed [FMA_ACC_SIZE-1:0] corr_re [0:PSS_COUNT-1][0:K_LANES-1];
    wire signed [FMA_ACC_SIZE-1:0] corr_im [0:PSS_COUNT-1][0:K_LANES-1];
    wire                           corr_v  [0:PSS_COUNT-1][0:K_LANES-1];

    genvar g_pss;
    generate
        for (g_lane = 0; g_lane < K_LANES; g_lane = g_lane + 1) begin : gen_corr_lane
            for (g_pss = 0; g_pss < PSS_COUNT; g_pss = g_pss + 1) begin : gen_corr_pss
                math_complex_corr #(
                    .WIDTH(CORR_W),
                    .CORR_SEQ_SIZE(PSS_LEN),
                    .fma_pipe_size(FMA_PIPE_SIZE),
                    .fma_acc_size(FMA_ACC_SIZE)
                ) u_corr (
                    .i_rst(i_rst),
                    .i_clk(i_clk),
                    .i_data_i1(sample_i_r),
                    .i_data_q1(sample_q_r),
                    .i_data1_valid(lane_valid[g_lane]),
                    .i_data_i2($signed(coef_pipe[g_pss][g_lane][15:0])),
                    .i_data_q2($signed(coef_pipe[g_pss][g_lane][31:16])),
                    .i_data2_valid(lane_valid[g_lane]),
                    .o_valid(corr_v[g_pss][g_lane]),
                    .o_im(corr_im[g_pss][g_lane]),
                    .o_re(corr_re[g_pss][g_lane])
                );
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Peak detector over one LTE PSS period
    // -------------------------------------------------------------------------
    reg                                period_best_valid;
    reg [31:0]                         period_base;
    reg [31:0]                         period_best_shift;
    reg [$clog2(PSS_COUNT)-1:0]        period_best_pss;
    reg [MAG_W-1:0]                    period_best_mag;
    reg [MAG_W-1:0]                    period_best_mag0;
    reg [MAG_W-1:0]                    period_best_mag1;
    reg [MAG_W-1:0]                    period_best_mag2;

    assign o_busy = overflow_sticky;

    integer li;
    integer pi;
    always @(posedge i_clk) begin
        if (i_rst) begin
            abs_in_count      <= 32'd0;
            rd_abs_count      <= 32'd0;
            overflow_sticky   <= 1'b0;
            ring_rd_ready_r   <= 1'b0;
            fill_pending      <= 1'b0;
            fill_abs_pending  <= 32'd0;

            window_count      <= '0;
            window_head_ptr   <= '0;
            window_wr_ptr     <= '0;
            window_rd_ptr     <= '0;
            window_base_abs   <= 32'd0;

            state             <= ST_FILL;
            feed_step         <= '0;
            batch_base_abs    <= 32'd0;
            lane_done         <= '0;

            sample_i_r        <= '0;
            sample_q_r        <= '0;
            sample_step_r     <= '0;
            sample_valid_r    <= 1'b0;

            rom_ena           <= 1'b0;
            rom_addr_cnt      <= '0;

            o_pss_idx         <= '0;
            o_pss_valid       <= 1'b0;
            o_shift           <= 32'd0;
            o_dbg_mag_pss0    <= 34'd0;
            o_dbg_mag_pss1    <= 34'd0;
            o_dbg_mag_pss2    <= 34'd0;
            o_dbg_abs_sample  <= 32'd0;

            period_best_valid <= 1'b0;
            period_base       <= 32'd0;
            period_best_shift <= 32'd0;
            period_best_pss   <= '0;
            period_best_mag   <= '0;
            period_best_mag0  <= '0;
            period_best_mag1  <= '0;
            period_best_mag2  <= '0;

            for (pi = 0; pi < PSS_COUNT; pi = pi + 1) begin
                for (li = 0; li < K_LANES; li = li + 1)
                    coef_pipe[pi][li] <= '0;
            end
        end else begin
            o_pss_valid      <= 1'b0;
            ring_rd_ready_r  <= 1'b0;
            o_dbg_abs_sample <= abs_in_count;

            if (i_valid && ring_full && !ring_do_read)
                overflow_sticky <= 1'b1;

            if (i_valid)
                abs_in_count <= abs_in_count + 1'b1;

            if (ring_do_read) begin
                fill_pending     <= 1'b1;
                fill_abs_pending <= rd_abs_count;
                rd_abs_count     <= rd_abs_count + 1'b1;
            end

            if (ring_rd_valid) begin
                window_mem[window_wr_ptr] <= ring_rd_data;
                if (window_count == 0)
                    window_base_abs <= fill_abs_pending;
                window_wr_ptr <= win_next_idx(window_wr_ptr);
                window_count  <= window_count + 1'b1;
                fill_pending  <= 1'b0;
            end

            // One candidate result per lane per batch.
            for (li = 0; li < K_LANES; li = li + 1) begin
                if (!lane_done[li] &&
                    corr_v[0][li] &&
                    corr_v[1][li] &&
                    corr_v[2][li]) begin
                    reg [MAG_W-1:0] mag0;
                    reg [MAG_W-1:0] mag1;
                    reg [MAG_W-1:0] mag2;
                    reg [MAG_W-1:0] cand_mag;
                    reg [$clog2(PSS_COUNT)-1:0] cand_pss;
                    reg [31:0] cand_shift;
                    reg flush_old_period;

                    mag0 = l1mag(corr_re[0][li], corr_im[0][li]);
                    mag1 = l1mag(corr_re[1][li], corr_im[1][li]);
                    mag2 = l1mag(corr_re[2][li], corr_im[2][li]);

                    cand_pss   = best_pss_idx(mag0, mag1, mag2);
                    cand_mag   = best_pss_mag(mag0, mag1, mag2);
                    cand_shift = batch_base_abs + li;

                    flush_old_period = (cand_shift >= (period_base + PERIOD_SPS));

                    if (flush_old_period) begin
                        if (period_best_valid) begin
                            o_pss_valid    <= 1'b1;
                            o_pss_idx      <= period_best_pss;
                            o_shift        <= period_best_shift;
                            o_dbg_mag_pss0 <= period_best_mag0[33:0];
                            o_dbg_mag_pss1 <= period_best_mag1[33:0];
                            o_dbg_mag_pss2 <= period_best_mag2[33:0];
                        end
                        period_base       <= period_base + PERIOD_SPS;
                        period_best_valid <= 1'b0;
                    end

                    if (flush_old_period || !period_best_valid ||
                        (cand_mag > period_best_mag) ||
                        ((cand_mag == period_best_mag) && (cand_shift < period_best_shift))) begin
                        period_best_valid <= 1'b1;
                        period_best_shift <= cand_shift;
                        period_best_pss   <= cand_pss;
                        period_best_mag   <= cand_mag;
                        period_best_mag0  <= mag0;
                        period_best_mag1  <= mag1;
                        period_best_mag2  <= mag2;
                    end

                    lane_done[li] <= 1'b1;
                end
            end

            case (state)
                ST_FILL: begin
                    sample_valid_r <= 1'b0;
                    rom_ena        <= 1'b0;

                    if ((window_count < SCAN_STEPS) && !fill_pending && !ring_empty)
                        ring_rd_ready_r <= 1'b1;

                    if (window_count == SCAN_STEPS) begin
                        batch_base_abs <= window_base_abs;
                        window_rd_ptr  <= window_head_ptr;
                        feed_step      <= '0;
                        lane_done      <= '0;
                        for (pi = 0; pi < PSS_COUNT; pi = pi + 1) begin
                            for (li = 0; li < K_LANES; li = li + 1)
                                coef_pipe[pi][li] <= '0;
                        end
                        rom_ena      <= 1'b1;
                        rom_addr_cnt <= '0;
                        state        <= ST_PRIME;
                    end
                end

                ST_PRIME: begin
                    sample_valid_r <= 1'b0;

                    if (PSS_LEN > 1) begin
                        rom_ena      <= 1'b1;
                        rom_addr_cnt <= 1;
                    end else begin
                        rom_ena <= 1'b0;
                    end

                    state <= ST_STREAM;
                end

                ST_STREAM: begin
                    sample_i_r     <= sx_adc($signed(window_mem[window_rd_ptr][ADC_W-1:0]));
                    sample_q_r     <= sx_adc($signed(window_mem[window_rd_ptr][PACKED_W-1:ADC_W]));
                    sample_step_r  <= feed_step;
                    sample_valid_r <= 1'b1;
                    window_rd_ptr  <= win_next_idx(window_rd_ptr);

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

                    if (feed_step == (SCAN_STEPS - 1)) begin
                        sample_valid_r <= 1'b1;
                        feed_step      <= '0;
                        state          <= ST_WAIT;
                    end else begin
                        feed_step <= feed_step + 1'b1;
                    end
                end

                ST_WAIT: begin
                    sample_valid_r <= 1'b0;
                    rom_ena        <= 1'b0;

                    if (&lane_done) begin
                        window_wr_ptr   <= window_head_ptr;
                        window_head_ptr <= win_advance(window_head_ptr, K_LANES);
                        window_count    <= PSS_LEN - 1;
                        window_base_abs <= batch_base_abs + K_LANES;
                        state           <= ST_FILL;
                    end
                end

                default: begin
                    state          <= ST_FILL;
                    sample_valid_r <= 1'b0;
                    rom_ena        <= 1'b0;
                end
            endcase
        end
    end
endmodule
