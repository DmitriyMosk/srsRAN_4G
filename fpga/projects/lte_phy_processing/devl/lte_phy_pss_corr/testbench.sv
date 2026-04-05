`timescale 1ns/1ps
`include "lte_hw_params.vh"

module tb_lte_phy_pss_corr;
    parameter longint CLK_HZ   = 200_000_000;
    parameter longint FS_HZ    = 1_920_000;
    parameter int     SPEEDUP  = 1;
    parameter int     K_LANES  = 2;
    parameter int     EXPECT_DETECTIONS = 8;

    localparam longint FS_EFF_HZ = FS_HZ * SPEEDUP;
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
    logic [31:0]                        o_dbg_abs_sample;

    lte_phy_pss_corr #(
        .K_LANES(K_LANES)
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
        .o_dbg_mag_pss2(o_dbg_mag_pss2),
        .o_dbg_abs_sample(o_dbg_abs_sample)
    );

    int     fd;
    string  line;
    int     addr;
    int     val;
    int     r;
    int     sample_count;
    int     detect_count;
    bit     use_int_div;
    int     ce_div;
    longint acc;
    int     ce_cnt;
    int     expected_shift;
    int     last_shift;
    bit     done;

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

        $display("TB: CLK_HZ=%0d FS_HZ=%0d SPEEDUP=%0d FS_EFF_HZ=%0d K_LANES=%0d",
                 CLK_HZ, FS_HZ, SPEEDUP, FS_EFF_HZ, K_LANES);
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
                    i_valid      <= 1'b1;
                    i_data_i1    <= $signed(val_i);
                    i_data_q1    <= $signed(val_q);
                    sample_count <= sample_count + 1;
                end
            end
        end else begin
            i_valid <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (o_pss_valid) begin
            detect_count <= detect_count + 1;
            $display("[%0t] DETECT #%0d: PSS%0d start0=%0d abs=%0d mags={%0d,%0d,%0d}",
                     $time, detect_count, o_pss_idx, o_shift, o_dbg_abs_sample,
                     o_dbg_mag_pss0, o_dbg_mag_pss1, o_dbg_mag_pss2);

            expected_shift = EXPECT_FIRST_SHIFT + (EXPECT_PERIOD * detect_count);

            if (o_pss_idx !== 1)
                $fatal(1, "Expected PSS1 on detect #%0d, got PSS%0d", detect_count, o_pss_idx);

            if (o_shift !== expected_shift[31:0])
                $fatal(1, "Expected detect #%0d at start0=%0d, got start0=%0d",
                       detect_count, expected_shift, o_shift);

            if ((detect_count > 0) && (o_shift !== (last_shift + EXPECT_PERIOD)))
                $fatal(1, "Expected period step %0d, previous start0=%0d current start0=%0d",
                       EXPECT_PERIOD, last_shift, o_shift);

            if (!(o_dbg_mag_pss1 >= o_dbg_mag_pss0 && o_dbg_mag_pss1 >= o_dbg_mag_pss2))
                $fatal(1, "Peak detector chose PSS1 but debug mags disagree: {%0d,%0d,%0d}",
                       o_dbg_mag_pss0, o_dbg_mag_pss1, o_dbg_mag_pss2);

            last_shift = o_shift;

            if (detect_count == (EXPECT_DETECTIONS - 1)) begin
                $display("TB PASSED: %0d detections match MATLAB-derived start0 sequence and peak rules",
                         EXPECT_DETECTIONS);
                $finish;
            end
        end
    end

    initial begin
        rst          = 1'b1;
        i_valid      = 1'b0;
        i_data_i1    = '0;
        i_data_q1    = '0;
        sample_count = 0;
        detect_count = 0;
        expected_shift = 0;
        last_shift     = 0;
        done         = 1'b0;

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
        #2s;
        $fatal(1, "Simulation timeout");
    end
endmodule
