`timescale 1ns/1ps
`include "lte_hw_params.vh"

module lte_pss_corr_engine #(
    parameter int PSS_TD_LEN     = 128,
    parameter int TARGET_FS      = 1_920_000, // stub for now
    parameter int CORR_W         = 16,
    parameter int ACC_W          = 48,
    parameter int K_TAPS         = 2
)(
    input  wire                               i_clk,
    input  wire                               i_rst,

    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_i1,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_q1,
    input  wire                               i_valid,

    output reg                                o_pss_valid,
    output reg  [$clog2(`LTE_PSS_COUNT)-1:0]  o_pss_idx,
    output reg  [31:0]                        o_shift,
    output wire                               o_busy,
    output reg                                o_overrun,

    output reg                                o_corr_valid,
    output reg  [31:0]                        o_corr_shift,    // absolute END sample index
    output reg  [33:0]                        o_mag_pss0,
    output reg  [33:0]                        o_mag_pss1,
    output reg  [33:0]                        o_mag_pss2
);

    localparam int PSS_LEN         = LTE_PSS_TD_LEN;
    localparam int PSS_ADDR_WIDTH  = `LTE_PSS_ADDR_WIDTH;
    localparam int PSS_PERIOD_SPS  = LTE_TARGET_FS / 200;

    localparam int ADC_W           = `HW_ADC_WIDTH;
    localparam int CORR_W          = 16;
    localparam int ACC_W           = FMA_ACC_SIZE;
    localparam int MAG_W           = ACC_W + 2;
    localparam int PROD_W          = CORR_W + CORR_W;
    localparam int SUM_W           = CORR_W + 1;
    localparam int MIX_W           = SUM_W + SUM_W;
    localparam int PIPE_STAGES     = (K_LANES > 1) ? (K_LANES - 1) : 1;
    localparam int SCAN_STEPS      = PSS_LEN + K_LANES - 1;
    localparam int STEP_W          = (SCAN_STEPS <= 1) ? 1 : $clog2(SCAN_STEPS);
    localparam int LANE_W          = (K_LANES <= 1) ? 1 : $clog2(K_LANES);
    localparam int PERIOD_W        = (PSS_PERIOD_SPS <= 1) ? 1 : $clog2(PSS_PERIOD_SPS);
    localparam int RING_LEN        = PSS_LEN * 4;
    localparam int RING_AW         = (RING_LEN <= 1) ? 1 : $clog2(RING_LEN);

    initial begin
        if ((PSS_LEN != 128) && (PSS_LEN != 256))
            $fatal(1, "lte_phy_pss_detector: only PSS_LEN=128/256 are supported");

        if (K_LANES < 1)
            $fatal(1, "lte_phy_pss_detector: K_LANES must be >= 1");

        if ((LTE_TARGET_FS % 200) != 0)
            $fatal(1, "lte_phy_pss_detector: LTE_TARGET_FS must be divisible by 200");

        if ((RING_LEN & (RING_LEN - 1)) != 0)
            $fatal(1, "lte_phy_pss_detector: RING_LEN must be power of two");

        if (FMA_PIPE_SIZE < 1)
            $fatal(1, "lte_phy_pss_detector: FMA_PIPE_SIZE must be >= 1");
    end

    // -------------------------------------------------------------------------
    // helpers
    // -------------------------------------------------------------------------
    function automatic signed [CORR_W-1:0] sx_adc(input signed [ADC_W-1:0] v);
        if (CORR_W == ADC_W) sx_adc = v;
        else                 sx_adc = {{(CORR_W-ADC_W){v[ADC_W-1]}}, v};
    endfunction

    function automatic signed [ACC_W-1:0] sx_prod(input signed [PROD_W-1:0] v);
        if (ACC_W == PROD_W) sx_prod = v;
        else                 sx_prod = {{(ACC_W-PROD_W){v[PROD_W-1]}}, v};
    endfunction

    function automatic signed [ACC_W-1:0] sx_mix(input signed [MIX_W-1:0] v);
        if (ACC_W == MIX_W) sx_mix = v;
        else                sx_mix = {{(ACC_W-MIX_W){v[MIX_W-1]}}, v};
    endfunction

    function automatic [MAG_W-1:0] abs_s(input signed [ACC_W-1:0] v);
        abs_s = v[ACC_W-1] ? $unsigned(-v) : $unsigned(v);
    endfunction

    function automatic [MAG_W-1:0] l1mag(
        input signed [ACC_W-1:0] re,
        input signed [ACC_W-1:0] im
    );
        l1mag = abs_s(re) + abs_s(im);
    endfunction

    function automatic [PERIOD_W-1:0] period_mod_init(input [31:0] v);
        period_mod_init = v % PSS_PERIOD_SPS;
    endfunction

    reg                      rom_ena;
    reg [PSS_ADDR_WIDTH-1:0] rom_addr_cnt;
    wire [31:0]              douta_pss0, douta_pss1, douta_pss2;

    generate
        if (L == 128) begin : gen_pss0_128
            pss_0_rom_td_128sps u_pss0 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(douta_pss0));
        end else begin : gen_pss0_256
            pss_0_rom_td_256sps u_pss0 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(douta_pss0));
        end
    endgenerate

    generate
        if (L == 128) begin : gen_pss1_128
            pss_1_rom_td_128sps u_pss1 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(douta_pss1));
        end else begin : gen_pss1_256
            pss_1_rom_td_256sps u_pss1 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(douta_pss1));
        end
    endgenerate

    generate
        if (L == 128) begin : gen_pss2_128
            pss_2_rom_td_128sps u_pss2 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(douta_pss2));
        end else begin : gen_pss2_256
            pss_2_rom_td_256sps u_pss2 (.clka(i_clk), .ena(rom_ena), .addra(rom_addr_cnt), .douta(douta_pss2));
        end
    endgenerate

    (* ram_style = "distributed" *) reg signed [15:0] pss0_i_mem [0:PSS_LEN-1];
    (* ram_style = "distributed" *) reg signed [15:0] pss0_q_mem [0:PSS_LEN-1];
    (* ram_style = "distributed" *) reg signed [15:0] pss1_i_mem [0:PSS_LEN-1];
    (* ram_style = "distributed" *) reg signed [15:0] pss1_q_mem [0:PSS_LEN-1];
    (* ram_style = "distributed" *) reg signed [15:0] pss2_i_mem [0:PSS_LEN-1];
    (* ram_style = "distributed" *) reg signed [15:0] pss2_q_mem [0:PSS_LEN-1];

    reg                      pss_loaded;
    reg [PSS_ADDR_WIDTH-1:0] load_wr;
    localparam [1:0] L_IDLE = 2'd0, L_PRIME = 2'd1, L_RUN = 2'd2, L_DONE = 2'd3;
    reg [1:0] lstate;

    always @(posedge i_clk) begin
        if (i_rst) begin
            load_state   <= L_IDLE;
            rom_ena      <= 1'b0;
            rom_addr_cnt <= '0;
            load_wr      <= '0;
            pss_loaded   <= 1'b0;
        end else begin
            case (lstate)
                L_IDLE: begin
                    pss_loaded   <= 1'b0;
                    rom_ena      <= 1'b1;
                    rom_addr_cnt <= '0;
                    load_wr      <= '0;
                    load_state   <= L_PRIME;
                end

                L_PRIME: begin
                    rom_addr_cnt <= 1;
                    load_state   <= L_RUN;
                end

                L_RUN: begin
                    pss0_i_mem[load_wr] <= $signed(douta_pss0[15:0]);
                    pss0_q_mem[load_wr] <= $signed(douta_pss0[31:16]);
                    pss1_i_mem[load_wr] <= $signed(douta_pss1[15:0]);
                    pss1_q_mem[load_wr] <= $signed(douta_pss1[31:16]);
                    pss2_i_mem[load_wr] <= $signed(douta_pss2[15:0]);
                    pss2_q_mem[load_wr] <= $signed(douta_pss2[31:16]);

                    if (load_wr == (L-1)) begin
                        rom_ena    <= 1'b0;
                        pss_loaded <= 1'b1;
                        load_state <= L_DONE;
                    end else begin
                        load_wr      <= load_wr + 1'b1;
                        rom_addr_cnt <= load_wr + 2;
                    end
                end

                default: begin
                    rom_ena <= 1'b0;
                end
            endcase
        end
    end

    (* ram_style = "distributed" *) reg signed [ADC_W-1:0] ring_i_mem [0:RING_LEN-1];
    (* ram_style = "distributed" *) reg signed [ADC_W-1:0] ring_q_mem [0:RING_LEN-1];

    localparam [1:0] S_IDLE = 2'd0, S_SCAN = 2'd1, S_EVAL = 2'd2;

    reg [1:0]         sst;
    reg [STEP_W-1:0]  scan_step;
    reg [LANE_W-1:0]  eval_lane;
    reg [31:0]        abs_sample;
    reg [31:0]        last_written_abs;
    reg               stream_started;
    reg               overflow_sticky;
    reg [31:0]        batch_base_abs;
    reg [PERIOD_W-1:0] result_period_pos;

    reg signed [ACC_W-1:0] acc0_re [0:K_LANES-1];
    reg signed [ACC_W-1:0] acc0_im [0:K_LANES-1];
    reg signed [ACC_W-1:0] acc1_re [0:K_LANES-1];
    reg signed [ACC_W-1:0] acc1_im [0:K_LANES-1];
    reg signed [ACC_W-1:0] acc2_re [0:K_LANES-1];
    reg signed [ACC_W-1:0] acc2_im [0:K_LANES-1];

    reg signed [CORR_W-1:0] pss0_i_pipe [0:PIPE_STAGES-1];
    reg signed [CORR_W-1:0] pss0_q_pipe [0:PIPE_STAGES-1];
    reg signed [CORR_W-1:0] pss1_i_pipe [0:PIPE_STAGES-1];
    reg signed [CORR_W-1:0] pss1_q_pipe [0:PIPE_STAGES-1];
    reg signed [CORR_W-1:0] pss2_i_pipe [0:PIPE_STAGES-1];
    reg signed [CORR_W-1:0] pss2_q_pipe [0:PIPE_STAGES-1];
    reg                     coef_pipe_valid [0:PIPE_STAGES-1];

    reg                               period_best_valid;
    reg [MAG_W-1:0]                   period_best_mag;
    reg [$clog2(`LTE_PSS_COUNT)-1:0]  period_best_idx;
    reg [31:0]                        period_best_shift;
    reg [33:0]                        period_best_mag0;
    reg [33:0]                        period_best_mag1;
    reg [33:0]                        period_best_mag2;

    wire batch_ready = stream_started && (last_written_abs >= (batch_base_abs + SCAN_STEPS - 1));
    assign o_busy = (!pss_loaded) || overflow_sticky;

    wire [31:0] scan_abs_w = batch_base_abs + scan_step;
    wire signed [CORR_W-1:0] scan_i = sx_adc(ring_i_mem[scan_abs_w[RING_AW-1:0]]);
    wire signed [CORR_W-1:0] scan_q = sx_adc(ring_q_mem[scan_abs_w[RING_AW-1:0]]);
    wire signed [SUM_W-1:0]  scan_sum = scan_i + scan_q;

    wire coef_cur_valid = (scan_step < PSS_LEN);
    wire [PSS_ADDR_WIDTH-1:0] coef_cur_addr = scan_step[PSS_ADDR_WIDTH-1:0];

    wire signed [CORR_W-1:0] coef0_cur_i = coef_cur_valid ? pss0_i_mem[coef_cur_addr] : '0;
    wire signed [CORR_W-1:0] coef0_cur_q = coef_cur_valid ? pss0_q_mem[coef_cur_addr] : '0;
    wire signed [CORR_W-1:0] coef1_cur_i = coef_cur_valid ? pss1_i_mem[coef_cur_addr] : '0;
    wire signed [CORR_W-1:0] coef1_cur_q = coef_cur_valid ? pss1_q_mem[coef_cur_addr] : '0;
    wire signed [CORR_W-1:0] coef2_cur_i = coef_cur_valid ? pss2_i_mem[coef_cur_addr] : '0;
    wire signed [CORR_W-1:0] coef2_cur_q = coef_cur_valid ? pss2_q_mem[coef_cur_addr] : '0;

    wire lane_valid [0:K_LANES-1];
    wire signed [CORR_W-1:0] lane0_i [0:K_LANES-1];
    wire signed [CORR_W-1:0] lane0_q [0:K_LANES-1];
    wire signed [CORR_W-1:0] lane1_i [0:K_LANES-1];
    wire signed [CORR_W-1:0] lane1_q [0:K_LANES-1];
    wire signed [CORR_W-1:0] lane2_i [0:K_LANES-1];
    wire signed [CORR_W-1:0] lane2_q [0:K_LANES-1];

    wire signed [SUM_W-1:0] lane0_d [0:K_LANES-1];
    wire signed [SUM_W-1:0] lane1_d [0:K_LANES-1];
    wire signed [SUM_W-1:0] lane2_d [0:K_LANES-1];

    wire signed [PROD_W-1:0] lane0_ac [0:K_LANES-1];
    wire signed [PROD_W-1:0] lane0_bd [0:K_LANES-1];
    wire signed [MIX_W-1:0]  lane0_mix [0:K_LANES-1];
    wire signed [PROD_W-1:0] lane1_ac [0:K_LANES-1];
    wire signed [PROD_W-1:0] lane1_bd [0:K_LANES-1];
    wire signed [MIX_W-1:0]  lane1_mix [0:K_LANES-1];
    wire signed [PROD_W-1:0] lane2_ac [0:K_LANES-1];
    wire signed [PROD_W-1:0] lane2_bd [0:K_LANES-1];
    wire signed [MIX_W-1:0]  lane2_mix [0:K_LANES-1];

    genvar gv;
    generate
        for (gv = 0; gv < K_LANES; gv = gv + 1) begin : gen_lane_data
            assign lane_valid[gv] = (scan_step >= gv) && (scan_step < (PSS_LEN + gv));

            if (gv == 0) begin : gen_lane_cur
                assign lane0_i[gv] = coef0_cur_i;
                assign lane0_q[gv] = coef0_cur_q;
                assign lane1_i[gv] = coef1_cur_i;
                assign lane1_q[gv] = coef1_cur_q;
                assign lane2_i[gv] = coef2_cur_i;
                assign lane2_q[gv] = coef2_cur_q;
            end else begin : gen_lane_pipe
                assign lane0_i[gv] = pss0_i_pipe[gv-1];
                assign lane0_q[gv] = pss0_q_pipe[gv-1];
                assign lane1_i[gv] = pss1_i_pipe[gv-1];
                assign lane1_q[gv] = pss1_q_pipe[gv-1];
                assign lane2_i[gv] = pss2_i_pipe[gv-1];
                assign lane2_q[gv] = pss2_q_pipe[gv-1];
            end

            assign lane0_d[gv]   = lane0_i[gv] - lane0_q[gv];
            assign lane1_d[gv]   = lane1_i[gv] - lane1_q[gv];
            assign lane2_d[gv]   = lane2_i[gv] - lane2_q[gv];

            (* use_dsp = "yes" *) assign lane0_ac[gv] = scan_i * lane0_i[gv];
            (* use_dsp = "yes" *) assign lane0_bd[gv] = scan_q * lane0_q[gv];
            (* use_dsp = "yes" *) assign lane0_mix[gv] = scan_sum * lane0_d[gv];

            (* use_dsp = "yes" *) assign lane1_ac[gv] = scan_i * lane1_i[gv];
            (* use_dsp = "yes" *) assign lane1_bd[gv] = scan_q * lane1_q[gv];
            (* use_dsp = "yes" *) assign lane1_mix[gv] = scan_sum * lane1_d[gv];

            (* use_dsp = "yes" *) assign lane2_ac[gv] = scan_i * lane2_i[gv];
            (* use_dsp = "yes" *) assign lane2_bd[gv] = scan_q * lane2_q[gv];
            (* use_dsp = "yes" *) assign lane2_mix[gv] = scan_sum * lane2_d[gv];
        end
    endgenerate

    integer li;
    always @(posedge i_clk) begin
        if (i_rst) begin
            wr_ptr      <= '0;
            fill_count  <= '0;
            abs_sample  <= 32'd0;
            sst         <= S_IDLE;
            tap_base    <= '0;
            job_shift   <= 32'd0;
            job_base_ptr<= '0;

            sst            <= S_IDLE;
            scan_step      <= '0;
            eval_lane      <= '0;
            abs_sample     <= 32'd0;
            last_written_abs <= 32'd0;
            stream_started <= 1'b0;
            overflow_sticky <= 1'b0;
            batch_base_abs <= 32'd0;
            result_period_pos <= '0;

            period_best_valid <= 1'b0;
            period_best_mag   <= '0;
            period_best_idx   <= '0;
            period_best_shift <= 32'd0;
            period_best_mag0  <= 34'd0;
            period_best_mag1  <= 34'd0;
            period_best_mag2  <= 34'd0;

            for (li = 0; li < K_LANES; li = li + 1) begin
                acc0_re[li] <= '0; acc0_im[li] <= '0;
                acc1_re[li] <= '0; acc1_im[li] <= '0;
                acc2_re[li] <= '0; acc2_im[li] <= '0;
            end

            for (li = 0; li < PIPE_STAGES; li = li + 1) begin
                pss0_i_pipe[li] <= '0;
                pss0_q_pipe[li] <= '0;
                pss1_i_pipe[li] <= '0;
                pss1_q_pipe[li] <= '0;
                pss2_i_pipe[li] <= '0;
                pss2_q_pipe[li] <= '0;
                coef_pipe_valid[li] <= 1'b0;
            end
        end else begin
            reg [MAG_W-1:0] lane_mag0;
            reg [MAG_W-1:0] lane_mag1;
            reg [MAG_W-1:0] lane_mag2;
            reg [MAG_W-1:0] lane_best_mag;
            reg [$clog2(`LTE_PSS_COUNT)-1:0] lane_best_idx;
            reg [31:0] lane_start_abs;
            reg lane_period_last;
            reg use_cur;

            o_pss_valid <= 1'b0;

            if (i_valid) begin
                if (pss_loaded) begin
                    ring_i_mem[abs_sample[RING_AW-1:0]] <= i_data_i1;
                    ring_q_mem[abs_sample[RING_AW-1:0]] <= i_data_q1;
                    last_written_abs <= abs_sample;

                    if (!stream_started) begin
                        stream_started    <= 1'b1;
                        batch_base_abs    <= abs_sample;
                        result_period_pos <= period_mod_init(abs_sample);
                    end
                end

                abs_sample <= abs_sample + 1'b1;
            end

            if (stream_started && (last_written_abs >= (batch_base_abs + RING_LEN - 1)))
                overflow_sticky <= 1'b1;

            case (sst)
                S_IDLE: begin
                    if (batch_ready) begin
                        for (li = 0; li < K_LANES; li = li + 1) begin
                            acc0_re[li] <= '0; acc0_im[li] <= '0;
                            acc1_re[li] <= '0; acc1_im[li] <= '0;
                            acc2_re[li] <= '0; acc2_im[li] <= '0;
                        end

                        for (li = 0; li < PIPE_STAGES; li = li + 1) begin
                            pss0_i_pipe[li] <= '0;
                            pss0_q_pipe[li] <= '0;
                            pss1_i_pipe[li] <= '0;
                            pss1_q_pipe[li] <= '0;
                            pss2_i_pipe[li] <= '0;
                            pss2_q_pipe[li] <= '0;
                            coef_pipe_valid[li] <= 1'b0;
                        end

                        scan_step <= '0;
                        eval_lane <= '0;
                        sst       <= S_SCAN;
                    end
                end

                S_SCAN: begin
                    for (li = 0; li < K_LANES; li = li + 1) begin
                        if (lane_valid[li] && ((li == 0) ? coef_cur_valid : coef_pipe_valid[li-1])) begin
                            acc0_re[li] <= acc0_re[li] + sx_prod(lane0_ac[li]) + sx_prod(lane0_bd[li]);
                            acc0_im[li] <= acc0_im[li] + sx_mix(lane0_mix[li]) - sx_prod(lane0_ac[li]) + sx_prod(lane0_bd[li]);

                            acc1_re[li] <= acc1_re[li] + sx_prod(lane1_ac[li]) + sx_prod(lane1_bd[li]);
                            acc1_im[li] <= acc1_im[li] + sx_mix(lane1_mix[li]) - sx_prod(lane1_ac[li]) + sx_prod(lane1_bd[li]);

                            acc2_re[li] <= acc2_re[li] + sx_prod(lane2_ac[li]) + sx_prod(lane2_bd[li]);
                            acc2_im[li] <= acc2_im[li] + sx_mix(lane2_mix[li]) - sx_prod(lane2_ac[li]) + sx_prod(lane2_bd[li]);
                        end
                    end

                    for (li = PIPE_STAGES-1; li > 0; li = li - 1) begin
                        pss0_i_pipe[li] <= pss0_i_pipe[li-1];
                        pss0_q_pipe[li] <= pss0_q_pipe[li-1];
                        pss1_i_pipe[li] <= pss1_i_pipe[li-1];
                        pss1_q_pipe[li] <= pss1_q_pipe[li-1];
                        pss2_i_pipe[li] <= pss2_i_pipe[li-1];
                        pss2_q_pipe[li] <= pss2_q_pipe[li-1];
                        coef_pipe_valid[li] <= coef_pipe_valid[li-1];
                    end

                    pss0_i_pipe[0] <= coef0_cur_i;
                    pss0_q_pipe[0] <= coef0_cur_q;
                    pss1_i_pipe[0] <= coef1_cur_i;
                    pss1_q_pipe[0] <= coef1_cur_q;
                    pss2_i_pipe[0] <= coef2_cur_i;
                    pss2_q_pipe[0] <= coef2_cur_q;
                    coef_pipe_valid[0] <= coef_cur_valid;

                    if (scan_step == (SCAN_STEPS-1)) begin
                        eval_lane <= '0;
                        sst       <= S_EVAL;
                    end else begin
                        scan_step <= scan_step + 1'b1;
                    end
                end

                S_EVAL: begin
                    lane_mag0 = l1mag(acc0_re[eval_lane], acc0_im[eval_lane]);
                    lane_mag1 = l1mag(acc1_re[eval_lane], acc1_im[eval_lane]);
                    lane_mag2 = l1mag(acc2_re[eval_lane], acc2_im[eval_lane]);
                    lane_start_abs = batch_base_abs + eval_lane;
                    lane_period_last = (result_period_pos == (PSS_PERIOD_SPS - 1));

                    if ((lane_mag2 >= lane_mag1) && (lane_mag2 >= lane_mag0)) begin
                        lane_best_mag = lane_mag2;
                        lane_best_idx = 2;
                    end else if (lane_mag1 >= lane_mag0) begin
                        lane_best_mag = lane_mag1;
                        lane_best_idx = 1;
                    end else begin
                        lane_best_mag = lane_mag0;
                        lane_best_idx = 0;
                    end

                    use_cur = (!period_best_valid) || (lane_best_mag > period_best_mag);

                    if (!lane_period_last) begin
                        if (use_cur) begin
                            period_best_valid <= 1'b1;
                            period_best_mag   <= lane_best_mag;
                            period_best_idx   <= lane_best_idx;
                            period_best_shift <= lane_start_abs;
                            period_best_mag0  <= lane_mag0[33:0];
                            period_best_mag1  <= lane_mag1[33:0];
                            period_best_mag2  <= lane_mag2[33:0];
                        end
                    end else begin
                        if (use_cur) begin
                            o_pss_valid    <= 1'b1;
                            o_pss_idx      <= lane_best_idx;
                            o_shift        <= lane_start_abs;
                            o_dbg_mag_pss0 <= lane_mag0[33:0];
                            o_dbg_mag_pss1 <= lane_mag1[33:0];
                            o_dbg_mag_pss2 <= lane_mag2[33:0];
                        end else if (period_best_valid) begin
                            o_pss_valid    <= 1'b1;
                            o_pss_idx      <= period_best_idx;
                            o_shift        <= period_best_shift;
                            o_dbg_mag_pss0 <= period_best_mag0;
                            o_dbg_mag_pss1 <= period_best_mag1;
                            o_dbg_mag_pss2 <= period_best_mag2;
                        end

                        period_best_valid <= 1'b0;
                        period_best_mag   <= '0;
                        period_best_idx   <= '0;
                        period_best_shift <= 32'd0;
                        period_best_mag0  <= 34'd0;
                        period_best_mag1  <= 34'd0;
                        period_best_mag2  <= 34'd0;
                    end

                    if (lane_period_last)
                        result_period_pos <= '0;
                    else
                        result_period_pos <= result_period_pos + 1'b1;

                    if (eval_lane == (K_LANES-1)) begin
                        batch_base_abs <= batch_base_abs + K_LANES;
                        sst            <= S_IDLE;
                    end else begin
                        eval_lane <= eval_lane + 1'b1;
                    end
                end

                default: begin
                    sst <= S_IDLE;
                end
            endcase
        end
    end

endmodule

module lte_phy_sync #(
    parameter int K_LANES        = 2,
    parameter int FMA_PIPE_SIZE  = 1,
    parameter int FMA_ACC_SIZE   = 48,
    parameter int LTE_PSS_TD_LEN = 128,
    parameter int LTE_TARGET_FS  = 1_920_000
)(
    input  wire                               i_clk,
    input  wire                               i_rst,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_i1,
    input  wire signed [`HW_ADC_WIDTH-1:0]    i_data_q1,
    input  wire                               i_valid,

    output wire [$clog2(`LTE_PSS_COUNT)-1:0]  o_pss_idx,
    output wire                               o_pss_valid,
    output wire [31:0]                        o_shift,

    output wire [33:0]                        o_dbg_mag_pss0,
    output wire [33:0]                        o_dbg_mag_pss1,
    output wire [33:0]                        o_dbg_mag_pss2
);
    lte_phy_pss_detector #(
        .K_LANES(K_LANES),
        .FMA_PIPE_SIZE(FMA_PIPE_SIZE),
        .FMA_ACC_SIZE(FMA_ACC_SIZE),
        .LTE_PSS_TD_LEN(LTE_PSS_TD_LEN),
        .LTE_TARGET_FS(LTE_TARGET_FS)
    ) u_lte_phy_pss_detector (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data_i1(i_data_i1),
        .i_data_q1(i_data_q1),
        .i_valid(i_valid),
        .o_pss_idx(o_pss_idx),
        .o_pss_valid(o_pss_valid),
        .o_shift(o_shift),
        .o_busy(),
        .o_dbg_mag_pss0(o_dbg_mag_pss0),
        .o_dbg_mag_pss1(o_dbg_mag_pss1),
        .o_dbg_mag_pss2(o_dbg_mag_pss2)
    );
endmodule
