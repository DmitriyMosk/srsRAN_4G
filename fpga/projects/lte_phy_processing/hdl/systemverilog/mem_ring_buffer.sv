`timescale 1ns/1ps

module mem_ring_buffer #(
    parameter int CAP   = 5,
    parameter int WIDTH = 32,

    localparam int ADDR_W  = (CAP <= 2) ? 1 : $clog2(CAP),
    localparam int COUNT_W = (CAP <= 1) ? 1 : $clog2(CAP + 1)
)(
    input  wire                 i_clk,
    input  wire                 i_rst,

    input  wire [WIDTH-1:0]     i_wd_data,
    input  wire                 i_wd_ready,
    input  wire                 i_rd_ready,

    output reg  [WIDTH-1:0]     o_rd_data,
    output reg                  o_rd_valid,
    output wire                 o_full,
    output wire                 o_empty,
    output reg                  o_wd_fire,
    output reg                  o_rd_fire,
    output wire [ADDR_W-1:0]    o_wd_idx,
    output wire [ADDR_W-1:0]    o_rd_idx,
    output wire [COUNT_W-1:0]   o_level
);

    (* ram_style = "auto" *) reg [WIDTH-1:0] mem [0:CAP-1];

    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;
    reg [COUNT_W-1:0] level;

    function automatic [ADDR_W-1:0] next_idx(input [ADDR_W-1:0] idx);
        begin
            if (idx == (CAP - 1))
                next_idx = '0;
            else
                next_idx = idx + 1'b1;
        end
    endfunction

    wire full_i    = (level == CAP);
    wire empty_i   = (level == 0);
    wire rd_fire_i = i_rd_ready && !empty_i;
    wire wd_fire_i = i_wd_ready && (!full_i || rd_fire_i);

    assign o_full  = full_i;
    assign o_empty = empty_i;

    assign o_wd_idx = wr_ptr;
    assign o_rd_idx = rd_ptr;
    assign o_level  = level;

    always @(posedge i_clk) begin
        if (i_rst) begin
            wr_ptr     <= '0;
            rd_ptr     <= '0;
            level      <= '0;
            o_rd_data  <= '0;
            o_rd_valid <= 1'b0;
            o_wd_fire  <= 1'b0;
            o_rd_fire  <= 1'b0;
        end else begin
            if (wd_fire_i)
                mem[wr_ptr] <= i_wd_data;

            if (rd_fire_i)
                o_rd_data <= mem[rd_ptr];

            o_wd_fire  <= wd_fire_i;
            o_rd_fire  <= rd_fire_i;
            o_rd_valid <= rd_fire_i;

            case ({wd_fire_i, rd_fire_i})
                2'b10: level <= level + 1'b1;
                2'b01: level <= level - 1'b1;
                default: level <= level;
            endcase

            if (wd_fire_i)
                wr_ptr <= next_idx(wr_ptr);

            if (rd_fire_i)
                rd_ptr <= next_idx(rd_ptr);
        end
    end

    initial begin
        if (CAP < 2)
            $fatal(1, "mem_ring_buffer: CAP must be >= 2");
    end
endmodule
