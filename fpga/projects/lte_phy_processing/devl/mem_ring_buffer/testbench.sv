`timescale 1ns/1ps

module tb_mem_ring_buffer;
    localparam int WIDTH = 8;

    reg clk = 1'b0;
    reg rst = 1'b1;

    reg [WIDTH-1:0] wd_data_5 = '0;
    reg             wd_ready_5 = 1'b0;
    reg             rd_ready_5 = 1'b0;
    logic [WIDTH-1:0] rd_data_5;
    logic             rd_valid_5;
    logic             full_5;
    logic             empty_5;
    logic             wd_fire_5;
    logic             rd_fire_5;
    logic [2:0]       wd_idx_5;
    logic [2:0]       rd_idx_5;
    logic [2:0]       level_5;

    reg [WIDTH-1:0] wd_data_6 = '0;
    reg             wd_ready_6 = 1'b0;
    reg             rd_ready_6 = 1'b0;
    logic [WIDTH-1:0] rd_data_6;
    logic             rd_valid_6;
    logic             full_6;
    logic             empty_6;
    logic             wd_fire_6;
    logic             rd_fire_6;
    logic [2:0]       wd_idx_6;
    logic [2:0]       rd_idx_6;
    logic [2:0]       level_6;

    mem_ring_buffer #(
        .CAP(5),
        .WIDTH(WIDTH)
    ) dut_cap5 (
        .i_clk(clk),
        .i_rst(rst),
        .i_wd_data(wd_data_5),
        .i_wd_ready(wd_ready_5),
        .i_rd_ready(rd_ready_5),
        .o_rd_data(rd_data_5),
        .o_rd_valid(rd_valid_5),
        .o_full(full_5),
        .o_empty(empty_5),
        .o_wd_fire(wd_fire_5),
        .o_rd_fire(rd_fire_5),
        .o_wd_idx(wd_idx_5),
        .o_rd_idx(rd_idx_5),
        .o_level(level_5)
    );

    mem_ring_buffer #(
        .CAP(6),
        .WIDTH(WIDTH)
    ) dut_cap6 (
        .i_clk(clk),
        .i_rst(rst),
        .i_wd_data(wd_data_6),
        .i_wd_ready(wd_ready_6),
        .i_rd_ready(rd_ready_6),
        .o_rd_data(rd_data_6),
        .o_rd_valid(rd_valid_6),
        .o_full(full_6),
        .o_empty(empty_6),
        .o_wd_fire(wd_fire_6),
        .o_rd_fire(rd_fire_6),
        .o_wd_idx(wd_idx_6),
        .o_rd_idx(rd_idx_6),
        .o_level(level_6)
    );

    always #5 clk = ~clk;

    task automatic check_state(
        input string tag,
        input logic full,
        input logic empty,
        input logic [2:0] level,
        input logic [2:0] wd_idx,
        input logic [2:0] rd_idx,
        input logic exp_full,
        input logic exp_empty,
        input logic [2:0] exp_level
    );
        begin
            if (full !== exp_full)
                $fatal(1, "%s: full mismatch exp=%0b got=%0b", tag, exp_full, full);
            if (empty !== exp_empty)
                $fatal(1, "%s: empty mismatch exp=%0b got=%0b", tag, exp_empty, empty);
            if (level !== exp_level)
                $fatal(1, "%s: level mismatch exp=%0d got=%0d", tag, exp_level, level);

            $display("[%0t] %s state: level=%0d full=%0b empty=%0b wr_idx=%0d rd_idx=%0d",
                     $time, tag, level, full, empty, wd_idx, rd_idx);
        end
    endtask

    task automatic push5(input string tag, input logic [WIDTH-1:0] value, input logic exp_wd_fire);
        begin
            @(negedge clk);
            wd_data_5  = value;
            wd_ready_5 = 1'b1;
            rd_ready_5 = 1'b0;

            @(posedge clk);
            #1;
            if (wd_fire_5 !== exp_wd_fire)
                $fatal(1, "%s: write fire mismatch exp=%0b got=%0b", tag, exp_wd_fire, wd_fire_5);

            @(negedge clk);
            wd_ready_5 = 1'b0;
            wd_data_5  = '0;
        end
    endtask

    task automatic pop5(input string tag, input logic exp_rd_fire, input logic [WIDTH-1:0] exp_data);
        begin
            @(negedge clk);
            wd_ready_5 = 1'b0;
            rd_ready_5 = 1'b1;

            @(posedge clk);
            #1;
            if (rd_fire_5 !== exp_rd_fire)
                $fatal(1, "%s: read fire mismatch exp=%0b got=%0b", tag, exp_rd_fire, rd_fire_5);

            if (exp_rd_fire) begin
                if (rd_valid_5 !== 1'b1)
                    $fatal(1, "%s: rd_valid must be 1", tag);
                if (rd_data_5 !== exp_data)
                    $fatal(1, "%s: rd_data mismatch exp=%0d got=%0d", tag, exp_data, rd_data_5);
            end else if (rd_valid_5 !== 1'b0) begin
                $fatal(1, "%s: rd_valid must be 0", tag);
            end

            @(negedge clk);
            rd_ready_5 = 1'b0;
        end
    endtask

    task automatic pushpop5(
        input string tag,
        input logic [WIDTH-1:0] push_value,
        input logic exp_wd_fire,
        input logic exp_rd_fire,
        input logic [WIDTH-1:0] exp_data
    );
        begin
            @(negedge clk);
            wd_data_5  = push_value;
            wd_ready_5 = 1'b1;
            rd_ready_5 = 1'b1;

            @(posedge clk);
            #1;
            if (wd_fire_5 !== exp_wd_fire)
                $fatal(1, "%s: write fire mismatch exp=%0b got=%0b", tag, exp_wd_fire, wd_fire_5);
            if (rd_fire_5 !== exp_rd_fire)
                $fatal(1, "%s: read fire mismatch exp=%0b got=%0b", tag, exp_rd_fire, rd_fire_5);
            if (exp_rd_fire) begin
                if (rd_valid_5 !== 1'b1)
                    $fatal(1, "%s: rd_valid must be 1", tag);
                if (rd_data_5 !== exp_data)
                    $fatal(1, "%s: rd_data mismatch exp=%0d got=%0d", tag, exp_data, rd_data_5);
            end

            @(negedge clk);
            wd_ready_5 = 1'b0;
            rd_ready_5 = 1'b0;
            wd_data_5  = '0;
        end
    endtask

    task automatic push6(input string tag, input logic [WIDTH-1:0] value, input logic exp_wd_fire);
        begin
            @(negedge clk);
            wd_data_6  = value;
            wd_ready_6 = 1'b1;
            rd_ready_6 = 1'b0;

            @(posedge clk);
            #1;
            if (wd_fire_6 !== exp_wd_fire)
                $fatal(1, "%s: write fire mismatch exp=%0b got=%0b", tag, exp_wd_fire, wd_fire_6);

            @(negedge clk);
            wd_ready_6 = 1'b0;
            wd_data_6  = '0;
        end
    endtask

    task automatic pop6(input string tag, input logic exp_rd_fire, input logic [WIDTH-1:0] exp_data);
        begin
            @(negedge clk);
            wd_ready_6 = 1'b0;
            rd_ready_6 = 1'b1;

            @(posedge clk);
            #1;
            if (rd_fire_6 !== exp_rd_fire)
                $fatal(1, "%s: read fire mismatch exp=%0b got=%0b", tag, exp_rd_fire, rd_fire_6);

            if (exp_rd_fire) begin
                if (rd_valid_6 !== 1'b1)
                    $fatal(1, "%s: rd_valid must be 1", tag);
                if (rd_data_6 !== exp_data)
                    $fatal(1, "%s: rd_data mismatch exp=%0d got=%0d", tag, exp_data, rd_data_6);
            end else if (rd_valid_6 !== 1'b0) begin
                $fatal(1, "%s: rd_valid must be 0", tag);
            end

            @(negedge clk);
            rd_ready_6 = 1'b0;
        end
    endtask

    task automatic pushpop6(
        input string tag,
        input logic [WIDTH-1:0] push_value,
        input logic exp_wd_fire,
        input logic exp_rd_fire,
        input logic [WIDTH-1:0] exp_data
    );
        begin
            @(negedge clk);
            wd_data_6  = push_value;
            wd_ready_6 = 1'b1;
            rd_ready_6 = 1'b1;

            @(posedge clk);
            #1;
            if (wd_fire_6 !== exp_wd_fire)
                $fatal(1, "%s: write fire mismatch exp=%0b got=%0b", tag, exp_wd_fire, wd_fire_6);
            if (rd_fire_6 !== exp_rd_fire)
                $fatal(1, "%s: read fire mismatch exp=%0b got=%0b", tag, exp_rd_fire, rd_fire_6);
            if (exp_rd_fire) begin
                if (rd_valid_6 !== 1'b1)
                    $fatal(1, "%s: rd_valid must be 1", tag);
                if (rd_data_6 !== exp_data)
                    $fatal(1, "%s: rd_data mismatch exp=%0d got=%0d", tag, exp_data, rd_data_6);
            end

            @(negedge clk);
            wd_ready_6 = 1'b0;
            rd_ready_6 = 1'b0;
            wd_data_6  = '0;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        rst = 1'b0;

        check_state("cap5 reset", full_5, empty_5, level_5, wd_idx_5, rd_idx_5, 1'b0, 1'b1, 3'd0);
        check_state("cap6 reset", full_6, empty_6, level_6, wd_idx_6, rd_idx_6, 1'b0, 1'b1, 3'd0);

        push5("cap5 push 11", 8'd11, 1'b1);
        push5("cap5 push 12", 8'd12, 1'b1);
        push5("cap5 push 13", 8'd13, 1'b1);
        push5("cap5 push 14", 8'd14, 1'b1);
        push5("cap5 push 15", 8'd15, 1'b1);
        check_state("cap5 full", full_5, empty_5, level_5, wd_idx_5, rd_idx_5, 1'b1, 1'b0, 3'd5);

        push5("cap5 blocked push", 8'd16, 1'b0);
        check_state("cap5 after blocked push", full_5, empty_5, level_5, wd_idx_5, rd_idx_5, 1'b1, 1'b0, 3'd5);

        pop5("cap5 pop 11", 1'b1, 8'd11);
        pop5("cap5 pop 12", 1'b1, 8'd12);
        check_state("cap5 after 2 pops", full_5, empty_5, level_5, wd_idx_5, rd_idx_5, 1'b0, 1'b0, 3'd3);

        push5("cap5 push 16", 8'd16, 1'b1);
        push5("cap5 push 17", 8'd17, 1'b1);
        check_state("cap5 wrapped full", full_5, empty_5, level_5, wd_idx_5, rd_idx_5, 1'b1, 1'b0, 3'd5);

        pop5("cap5 pop 13", 1'b1, 8'd13);
        pop5("cap5 pop 14", 1'b1, 8'd14);
        pop5("cap5 pop 15", 1'b1, 8'd15);
        pop5("cap5 pop 16", 1'b1, 8'd16);
        pop5("cap5 pop 17", 1'b1, 8'd17);
        check_state("cap5 empty", full_5, empty_5, level_5, wd_idx_5, rd_idx_5, 1'b0, 1'b1, 3'd0);

        pop5("cap5 blocked pop", 1'b0, 8'd0);

        push5("cap5 refill 21", 8'd21, 1'b1);
        push5("cap5 refill 22", 8'd22, 1'b1);
        push5("cap5 refill 23", 8'd23, 1'b1);
        push5("cap5 refill 24", 8'd24, 1'b1);
        push5("cap5 refill 25", 8'd25, 1'b1);
        pushpop5("cap5 full read+write", 8'd26, 1'b1, 1'b1, 8'd21);
        check_state("cap5 still full", full_5, empty_5, level_5, wd_idx_5, rd_idx_5, 1'b1, 1'b0, 3'd5);

        pop5("cap5 pop 22", 1'b1, 8'd22);
        pop5("cap5 pop 23", 1'b1, 8'd23);
        pop5("cap5 pop 24", 1'b1, 8'd24);
        pop5("cap5 pop 25", 1'b1, 8'd25);
        pop5("cap5 pop 26", 1'b1, 8'd26);
        check_state("cap5 final empty", full_5, empty_5, level_5, wd_idx_5, rd_idx_5, 1'b0, 1'b1, 3'd0);

        push6("cap6 push 31", 8'd31, 1'b1);
        push6("cap6 push 32", 8'd32, 1'b1);
        push6("cap6 push 33", 8'd33, 1'b1);
        push6("cap6 push 34", 8'd34, 1'b1);
        push6("cap6 push 35", 8'd35, 1'b1);
        push6("cap6 push 36", 8'd36, 1'b1);
        check_state("cap6 full", full_6, empty_6, level_6, wd_idx_6, rd_idx_6, 1'b1, 1'b0, 3'd6);

        pop6("cap6 pop 31", 1'b1, 8'd31);
        pop6("cap6 pop 32", 1'b1, 8'd32);
        push6("cap6 push 37", 8'd37, 1'b1);
        push6("cap6 push 38", 8'd38, 1'b1);
        check_state("cap6 wrapped full", full_6, empty_6, level_6, wd_idx_6, rd_idx_6, 1'b1, 1'b0, 3'd6);

        pushpop6("cap6 full read+write", 8'd39, 1'b1, 1'b1, 8'd33);
        check_state("cap6 still full", full_6, empty_6, level_6, wd_idx_6, rd_idx_6, 1'b1, 1'b0, 3'd6);

        pop6("cap6 pop 34", 1'b1, 8'd34);
        pop6("cap6 pop 35", 1'b1, 8'd35);
        pop6("cap6 pop 36", 1'b1, 8'd36);
        pop6("cap6 pop 37", 1'b1, 8'd37);
        pop6("cap6 pop 38", 1'b1, 8'd38);
        pop6("cap6 pop 39", 1'b1, 8'd39);
        check_state("cap6 final empty", full_6, empty_6, level_6, wd_idx_6, rd_idx_6, 1'b0, 1'b1, 3'd0);

        $display("mem_ring_buffer TB PASSED");
        $finish;
    end
endmodule
