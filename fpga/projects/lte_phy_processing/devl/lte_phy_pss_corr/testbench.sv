`timescale 1ns/1ps
`include "lte_hw_params.vh"

`define TB_ONECLOCK

module tb_lte_phy_pss_corr;
`ifdef TB_ONECLOCK
    localparam bit      TB_ONECLOCK_MODE     = 1'b1;
    localparam longint  TB_CLK_HZ            = 1_920_000;
`ifdef TB_K2
    localparam int      TB_K_LANES           = 2;
`else
    localparam int      TB_K_LANES           = 8;
`endif
`ifdef TB_EXPECT_FOUR
    localparam int      TB_EXPECT_DETECTIONS = 4;
`elsif TB_EXPECT_TWO
    localparam int      TB_EXPECT_DETECTIONS = 2;
`else
    localparam int      TB_EXPECT_DETECTIONS = 1;
`endif
`else
    localparam bit      TB_ONECLOCK_MODE     = 1'b0;
    localparam longint  TB_CLK_HZ            = 200_000_000;
`ifdef TB_K2
    localparam int      TB_K_LANES           = 2;
`else
    localparam int      TB_K_LANES           = 2;
`endif
`ifdef TB_EXPECT_FOUR
    localparam int      TB_EXPECT_DETECTIONS = 4;
`else
    localparam int      TB_EXPECT_DETECTIONS = 8;
`endif
`endif

    parameter longint CLK_HZ            = TB_CLK_HZ;
    parameter longint FS_HZ             = 1_920_000;
    parameter int     SPEEDUP           = 1;
    parameter int     K_LANES           = TB_K_LANES;
    parameter int     EXPECT_DETECTIONS = TB_EXPECT_DETECTIONS;
    parameter bit     ONECLOCK          = TB_ONECLOCK_MODE;
    parameter int     SUBFRAME_SPS      = FS_HZ / 200;
    parameter int     BUF_CAP           = SUBFRAME_SPS;

    localparam longint FS_EFF_HZ          = FS_HZ * SPEEDUP;
    localparam int     EXPECT_FIRST_SHIFT = 2193;
    localparam int     EXPECT_PERIOD      = 9600;

    real CLK_PERIOD_NS = 1e9 / CLK_HZ;

    logic clk = 1'b0;
    logic rst;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    logic signed [`HW_ADC_WIDTH-1:0]    i_data_i1;
    logic signed [`HW_ADC_WIDTH-1:0]    i_data_q1;
    logic                               i_valid;

    logic [$clog2(`LTE_PSS_COUNT)-1:0]  o_pss_idx;
    logic                               o_pss_valid;
    logic [31:0]                        o_shift;
    logic                               o_busy;
    logic [33:0]                        o_dbg_mag_pss0;
    logic [33:0]                        o_dbg_mag_pss1;
    logic [33:0]                        o_dbg_mag_pss2;

    lte_phy_sync #(
        .K_LANES(K_LANES),
        .SUBFRAME_SPS(SUBFRAME_SPS),
        .BUF_CAP(BUF_CAP),
        .ONECLOCK(ONECLOCK)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
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

    int     fd;
    string  line;
    int     addr;
    int     val;
    int     r;
    int     sample_count;
    int     accepted_count;
    int     detect_count;
    bit     use_int_div;
    int     ce_div;
    longint acc;
    int     ce_cnt;
    int     expected_shift;
    int     issued_sample_abs;
    int     current_frame_base_abs;
    int     frame_fill_count;
    int     frame_q_wr;
    int     frame_base_queue [0:255];
    int     detect_frame_base_abs;
    int     abs_detect_shift;
    bit     done;
    int     abs_expected_shift;

    task automatic read_next_word(output int addr_out, output int val_out, output bit ok);
        begin
            ok = 1'b0;
            while (!$feof(fd)) begin
                r = $fgets(line, fd);
                if (r == 0)
                    continue;
                r = $sscanf(line, "@%x %d", addr_out, val_out);
                if (r == 2) begin
                    ok = 1'b1;
                    return;
                end
            end
        end
    endtask

    initial begin
        if (FS_EFF_HZ > CLK_HZ)
            $fatal(1, "TB: FS_EFF_HZ (%0d) must be <= CLK_HZ (%0d)", FS_EFF_HZ, CLK_HZ);

        if ((CLK_HZ % FS_EFF_HZ) == 0) begin
            use_int_div = 1'b1;
            ce_div = CLK_HZ / FS_EFF_HZ;
        end else begin
            use_int_div = 1'b0;
            ce_div = 0;
        end

        $display("TB: CLK_HZ=%0d FS_HZ=%0d SPEEDUP=%0d FS_EFF_HZ=%0d K_LANES=%0d ONECLOCK=%0d BUF_CAP=%0d",
                 CLK_HZ, FS_HZ, SPEEDUP, FS_EFF_HZ, K_LANES, ONECLOCK, BUF_CAP);
    end

    always @(negedge clk) begin
        bit fire;
        bit ok_i;
        bit ok_q;
        int addr_i;
        int addr_q;
        int val_i;
        int val_q;

        fire = 1'b0;

        if (rst) begin
            i_valid   <= 1'b0;
            i_data_i1 <= '0;
            i_data_q1 <= '0;
            ce_cnt    <= 0;
            acc       <= 0;
            done      <= 1'b0;
        end else if (!done) begin
            i_valid <= 1'b0;

            if (use_int_div) begin
                if (ce_cnt == (ce_div-1)) begin
                    ce_cnt <= 0;
                    fire   = 1'b1;
                end else begin
                    ce_cnt <= ce_cnt + 1;
                end
            end else begin
                longint acc_next;
                acc_next = acc + FS_EFF_HZ;
                if (acc_next >= CLK_HZ) begin
                    acc  <= acc_next - CLK_HZ;
                    fire = 1'b1;
                end else begin
                    acc <= acc_next;
                end
            end

            if (fire) begin
                read_next_word(addr_i, val_i, ok_i);
                read_next_word(addr_q, val_q, ok_q);

                if (!ok_i || !ok_q) begin
                    done    <= 1'b1;
                    i_valid <= 1'b0;
                end else begin
                    i_valid            <= 1'b1;
                    i_data_i1          <= $signed(val_i);
                    i_data_q1          <= $signed(val_q);
                    issued_sample_abs  <= sample_count;
                    sample_count       <= sample_count + 1;
                end
            end
        end else begin
            i_valid <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            accepted_count         <= 0;
            current_frame_base_abs <= 0;
            frame_fill_count       <= 0;
            frame_q_wr             <= 0;
        end else if (dut.fifo_do_write) begin
            accepted_count <= accepted_count + 1;

            if (frame_fill_count == 0)
                current_frame_base_abs <= issued_sample_abs;

            if (frame_fill_count == (SUBFRAME_SPS - 1)) begin
                frame_base_queue[frame_q_wr] <= current_frame_base_abs;
                frame_q_wr    <= frame_q_wr + 1;
                frame_fill_count <= 0;
            end else begin
                frame_fill_count <= frame_fill_count + 1;
            end
        end
    end

    always @(posedge clk) begin
        if (o_pss_valid) begin
            if (detect_count >= frame_q_wr)
                $fatal(1, "TB bookkeeping error: no queued frame base for detect #%0d", detect_count);

            detect_frame_base_abs = frame_base_queue[detect_count];
            abs_detect_shift      = detect_frame_base_abs + o_shift;
            detect_count <= detect_count + 1;
            abs_expected_shift = EXPECT_FIRST_SHIFT + (EXPECT_PERIOD * detect_count);
            $display("[%0t] DETECT #%0d: PSS%0d rel_start0=%0d frame_base_abs=%0d abs_start0=%0d src_emitted=%0d accepted=%0d busy=%0d mags={%0d,%0d,%0d}",
                     $time, detect_count, o_pss_idx, o_shift, detect_frame_base_abs, abs_detect_shift,
                     sample_count, accepted_count, o_busy,
                     o_dbg_mag_pss0, o_dbg_mag_pss1, o_dbg_mag_pss2);

            if (!ONECLOCK) begin
                if (o_pss_idx !== 1)
                    $fatal(1, "Expected PSS1 on detect #%0d, got PSS%0d", detect_count, o_pss_idx);

                if (abs_detect_shift !== abs_expected_shift)
                    $fatal(1, "Expected absolute start0=%0d on detect #%0d, got abs_start0=%0d (frame_base_abs=%0d rel_start0=%0d)",
                           abs_expected_shift, detect_count, abs_detect_shift, detect_frame_base_abs, o_shift);

                if (!(o_dbg_mag_pss1 >= o_dbg_mag_pss0 && o_dbg_mag_pss1 >= o_dbg_mag_pss2))
                    $fatal(1, "Peak detector chose PSS1 but debug mags disagree: {%0d,%0d,%0d}",
                           o_dbg_mag_pss0, o_dbg_mag_pss1, o_dbg_mag_pss2);
            end else begin
                if (o_pss_idx !== 1)
                    $fatal(1, "ONECLOCK: expected PSS1 on detect #%0d, got PSS%0d", detect_count, o_pss_idx);

                if (detect_count == 0) begin
                    if (abs_detect_shift !== EXPECT_FIRST_SHIFT)
                        $fatal(1, "ONECLOCK: expected first absolute detection at start0=%0d, got abs_start0=%0d",
                               EXPECT_FIRST_SHIFT, abs_detect_shift);
                end

                if (!(o_dbg_mag_pss1 >= o_dbg_mag_pss0 && o_dbg_mag_pss1 >= o_dbg_mag_pss2))
                    $fatal(1, "ONECLOCK: peak detector chose PSS1 but debug mags disagree: {%0d,%0d,%0d}",
                           o_dbg_mag_pss0, o_dbg_mag_pss1, o_dbg_mag_pss2);
            end

            if ((detect_count + 1) == EXPECT_DETECTIONS) begin
                $display("TB PASSED: %0d detections validated", EXPECT_DETECTIONS);
                $finish;
            end
        end
    end

    initial begin
        rst            = 1'b1;
        i_valid        = 1'b0;
        i_data_i1      = '0;
        i_data_q1      = '0;
        sample_count   = 0;
        accepted_count = 0;
        detect_count   = 0;
        expected_shift = 0;
        issued_sample_abs = 0;
        current_frame_base_abs = 0;
        frame_fill_count = 0;
        frame_q_wr = 0;
        detect_frame_base_abs = 0;
        abs_detect_shift = 0;
        done           = 1'b0;

        fd = $fopen("input_signal.hex", "r");
        if (fd == 0)
            fd = $fopen("projects/lte_phy_processing/devl/lte_phy_sync/input_signal.hex", "r");
        if (fd == 0)
            $fatal(1, "Can't open input_signal.hex");

        repeat (20) @(posedge clk);
        rst <= 1'b0;

        wait(done);
        $fclose(fd);

        repeat (1200000) @(posedge clk);
        $fatal(1, "Input finished before %0d detections were observed", EXPECT_DETECTIONS);
    end

    initial begin
        #10s;
        $fatal(1, "Simulation timeout");
    end
endmodule
