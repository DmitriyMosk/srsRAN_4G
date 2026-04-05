`timescale 1ns/1ps
`include "lte_hw_params.vh"

module testbench;

    parameter longint CLK_HZ      = 1_920_000; //200_000_000;
    parameter longint TARGET_FS   = 1_920_000;
    parameter int     PSS_TD_LEN  = 128;
    parameter int     SPEEDUP     = 1;      // 1 = real FS, >1 = accelerated source
    parameter bit     RESPECT_BUSY= 1'b0;   // 0 = continuous stream, 1 = stall source on o_busy
    parameter int     K_TAPS      = 2;

    localparam longint FS_EFF_HZ = TARGET_FS * SPEEDUP;

    real CLK_PERIOD_NS = 1e9 / CLK_HZ;

    // ============================================================
    // Clock / Reset
    // ============================================================
    logic clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    logic rst;

    // ============================================================
    // DUT I/O
    // ============================================================
    logic signed [`HW_ADC_WIDTH-1:0] i_data_i;
    logic signed [`HW_ADC_WIDTH-1:0] i_data_q;
    logic                            i_sample_ce;

    logic [$clog2(`LTE_PSS_COUNT)-1:0]  o_pss_idx;
    logic                               o_pss_valid;
    logic [31:0]                        o_shift;
    logic                               o_busy;
    logic [33:0]                        o_dbg_mag_pss0;
    logic [33:0]                        o_dbg_mag_pss1;
    logic [33:0]                        o_dbg_mag_pss2;

    // peak reducer
    logic                            pss_valid;
    logic [$clog2(`LTE_PSS_COUNT)-1:0] pss_idx;
    logic [31:0]                     pss_shift;
    logic [33:0]                     dbg_mag_pss0;
    logic [33:0]                     dbg_mag_pss1;
    logic [33:0]                     dbg_mag_pss2;

    lte_pss_corr_engine #(
        .PSS_TD_LEN (PSS_TD_LEN),
        .TARGET_FS  (TARGET_FS),
        .K_TAPS     (K_TAPS)
    ) u_corr (
        .i_clk       (clk),
        .i_rst       (rst),
        .i_data_i1   (i_data_i1),
        .i_data_q1   (i_data_q1),
        .i_valid     (i_valid),
        .o_pss_idx   (o_pss_idx),
        .o_pss_valid (o_pss_valid),
        .o_shift     (o_shift),
        .o_busy      (o_busy),
        .o_dbg_mag_pss0(o_dbg_mag_pss0),
        .o_dbg_mag_pss1(o_dbg_mag_pss1),
        .o_dbg_mag_pss2(o_dbg_mag_pss2)
    );

    lte_pss_period_peak_reducer #(
        .TARGET_FS(TARGET_FS)
    ) u_reduce (
        .i_clk        (clk),
        .i_rst        (rst),
        .i_corr_valid (corr_valid),
        .i_corr_shift (corr_shift),
        .i_mag_pss0   (mag_pss0),
        .i_mag_pss1   (mag_pss1),
        .i_mag_pss2   (mag_pss2),
        .o_pss_valid  (pss_valid),
        .o_pss_idx    (pss_idx),
        .o_shift      (pss_shift),
        .o_dbg_mag_pss0(dbg_mag_pss0),
        .o_dbg_mag_pss1(dbg_mag_pss1),
        .o_dbg_mag_pss2(dbg_mag_pss2)
    );

    // ============================================================
    // File reader
    // input_signal.hex format:
    //   @00000000 123
    //   @00000001 -45
    //   ...
    // Interleaving: I,Q,I,Q,...
    // ============================================================
    int    fd;
    string line;
    int    addr, val;
    int    r;

    int sample_count;
    bit done;

    task automatic read_next_word(output int addr_out, output int val_out, output bit ok);
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
    endtask

    // ============================================================
    // Sample-ce generator
    // ============================================================
    bit     use_int_div;
    int     ce_div;
    int     ce_cnt;
    longint acc;
    longint stall_due_busy_count;

    initial begin
        if (FS_EFF_HZ > CLK_HZ)
            $fatal(1, "ERROR: FS_EFF_HZ (%0d) must be <= CLK_HZ (%0d)", FS_EFF_HZ, CLK_HZ);

        if ((CLK_HZ % FS_EFF_HZ) == 0) begin
            use_int_div = 1'b1;
            ce_div      = CLK_HZ / FS_EFF_HZ;
        end else begin
            use_int_div = 1'b0;
            ce_div      = 0;
        end

        $display("TB configuration:");
        $display("  CLK_HZ       = %0d", CLK_HZ);
        $display("  TARGET_FS    = %0d", TARGET_FS);
        $display("  SPEEDUP      = %0d", SPEEDUP);
        $display("  FS_EFF_HZ    = %0d", FS_EFF_HZ);
        $display("  PSS_TD_LEN   = %0d", PSS_TD_LEN);
        $display("  K_TAPS       = %0d", K_TAPS);
        $display("  RESPECT_BUSY = %0d", RESPECT_BUSY);

        if (use_int_div)
            $display("  CE mode      = integer divider, %0d cycles/sample", ce_div);
        else
            $display("  CE mode      = fractional DDS divider (+/-1 cycle jitter)");
    end

    // Drive source on negedge so DUT samples stable values on posedge
    always @(negedge clk) begin
        bit fire;
        bit ok_i, ok_q;
        int addr_i, addr_q;
        int val_i,  val_q;
        longint acc_next;

        fire = 1'b0;

        if (rst) begin
            i_sample_ce          <= 1'b0;
            i_data_i             <= '0;
            i_data_q             <= '0;
            ce_cnt               <= 0;
            acc                  <= 0;
            done                 <= 1'b0;
            sample_count         <= 0;
            stall_due_busy_count <= 0;
        end
        else if (!done) begin
            i_sample_ce <= 1'b0;

            // generate 1-cycle strobe request
            if (use_int_div) begin
                if (ce_cnt == (ce_div - 1)) begin
                    ce_cnt <= 0;
                    fire   = 1'b1;
                end else begin
                    ce_cnt <= ce_cnt + 1;
                end
            end else begin
                acc_next = acc + FS_EFF_HZ;
                if (acc_next >= CLK_HZ) begin
                    acc  <= acc_next - CLK_HZ;
                    fire = 1'b1;
                end else begin
                    acc <= acc_next;
                end
            end

            if (fire) begin
                if (RESPECT_BUSY && corr_busy) begin
                    stall_due_busy_count <= stall_due_busy_count + 1;
                end else begin
                    read_next_word(addr_i, val_i, ok_i);
                    read_next_word(addr_q, val_q, ok_q);

                    if (!ok_i || !ok_q) begin
                        done        <= 1'b1;
                        i_sample_ce <= 1'b0;
                    end else begin
                        i_sample_ce <= 1'b1;
                        i_data_i    <= $signed(val_i);
                        i_data_q    <= $signed(val_q);
                        sample_count <= sample_count + 1;
                    end
                end
            end
        end
        else begin
            i_sample_ce <= 1'b0;
        end
    end

    // ============================================================
    // Logs
    // ============================================================
    integer corr_log;
    integer pss_log;

    initial begin
        corr_log = $fopen("corr_log.txt", "w");
        pss_log  = $fopen("pss_log.txt",  "w");
        if (corr_log == 0) $fatal(1, "ERROR: Can't open corr_log.txt");
        if (pss_log  == 0) $fatal(1, "ERROR: Can't open pss_log.txt");
    end

    always @(posedge clk) begin
        if (corr_valid) begin
            $fdisplay(corr_log, "%0d;%0d;%0d;%0d",
                      corr_shift, mag_pss0, mag_pss1, mag_pss2);
        end

        if (pss_valid) begin
            $display("[%0t] PSS%0d detected at sample position %0d  mags={%0d,%0d,%0d} busy=%0b overrun=%0b",
                     $time, pss_idx, pss_shift,
                     dbg_mag_pss0, dbg_mag_pss1, dbg_mag_pss2,
                     corr_busy, corr_overrun);

            $fdisplay(pss_log, "%0d;%0d;%0d;%0d;%0d",
                      pss_idx, pss_shift,
                      dbg_mag_pss0, dbg_mag_pss1, dbg_mag_pss2);
        end
    end

    // ============================================================
    // BUSY / throughput monitor
    // counts how many source strobes happened while corr engine was busy
    // ============================================================
    logic   corr_busy_d;
    longint busy_cycles_cur;
    longint busy_cycles_max;
    longint busy_cycles_total;
    longint busy_samples_cur;
    longint busy_samples_max;
    longint busy_samples_total;
    int     busy_event_count;

    initial begin
        file = $fopen("pss_log.txt", "w");
    end

    always @(posedge clk) begin
        if (o_pss_valid) begin
            $display("[%0t] PSS%0d detected at start0 %0d (busy=%0b) mags={%0d,%0d,%0d}",
                     $time, o_pss_idx, o_shift, o_busy,
                     o_dbg_mag_pss0, o_dbg_mag_pss1, o_dbg_mag_pss2);

            $fdisplay(file, "%0d;%0d", o_pss_idx, o_shift);
        end
    end

    // BUSY monitor:
    // ������� �������� "��������/�� ��������" = ������� i_valid ������ �� ����� o_busy=1
    always @(posedge clk) begin
        if (rst) begin
            corr_busy_d        <= 1'b0;
            busy_cycles_cur    <= 0;
            busy_cycles_max    <= 0;
            busy_cycles_total  <= 0;
            busy_samples_cur   <= 0;
            busy_samples_max   <= 0;
            busy_samples_total <= 0;
            busy_event_count   <= 0;
        end else begin
            if (!corr_busy_d && corr_busy) begin
                busy_event_count <= busy_event_count + 1;
                busy_cycles_cur  <= 1;
                busy_samples_cur <= i_sample_ce ? 1 : 0;
            end
            else if (corr_busy_d && corr_busy) begin
                busy_cycles_cur <= busy_cycles_cur + 1;
                if (i_sample_ce)
                    busy_samples_cur <= busy_samples_cur + 1;
            end
            else if (corr_busy_d && !corr_busy) begin
                busy_cycles_total  <= busy_cycles_total + busy_cycles_cur;
                busy_samples_total <= busy_samples_total + busy_samples_cur;

                if (busy_cycles_cur  > busy_cycles_max)  busy_cycles_max  <= busy_cycles_cur;
                if (busy_samples_cur > busy_samples_max) busy_samples_max <= busy_samples_cur;

                busy_cycles_cur  <= 0;
                busy_samples_cur <= 0;
            end

            corr_busy_d <= corr_busy;
        end
    end

    final begin
        $fclose(corr_log);
        $fclose(pss_log);
    end

    // ============================================================
    // Main
    // ============================================================
    initial begin
        rst         = 1'b1;
        i_sample_ce = 1'b0;
        i_data_i    = '0;
        i_data_q    = '0;
        sample_count= 0;
        done        = 1'b0;

        fd = $fopen("input_signal.hex", "r");
        if (fd == 0)
            $fatal(1, "ERROR: Can't open input_signal.hex");

        repeat (20) @(posedge clk);
        rst <= 1'b0;

        wait(done);

        $fclose(fd);
        $display("\n[%0t] All samples loaded (%0d IQ samples)", $time, sample_count);
        $display("[%0t] Waiting extra cycles...\n", $time);

        repeat (200000) @(posedge clk);

        $display("\nTB SUMMARY:");
        $display("  busy events                = %0d", busy_event_count);
        $display("  total busy cycles          = %0d", busy_cycles_total);
        $display("  max busy cycles            = %0d", busy_cycles_max);
        $display("  total source strobes in busy = %0d", busy_samples_total);
        $display("  max source strobes per busy  = %0d", busy_samples_max);
        $display("  source stalls due busy     = %0d", stall_due_busy_count);
        $display("  corr_overrun               = %0b", corr_overrun);

        if (!RESPECT_BUSY) begin
            if ((busy_samples_total == 0) && !corr_overrun)
                $display("  RESULT: corr engine keeps up with continuous stream");
            else
                $display("  RESULT: corr engine does NOT keep up with continuous stream");
        end else begin
            $display("  RESULT: functional mode with backpressure enabled");
        end

        $finish;
    end

    // timeout
    initial begin
        #2s;
        $display("\n[%0t] ERROR: Simulation timeout!", $time);
        $finish;
    end

endmodule
