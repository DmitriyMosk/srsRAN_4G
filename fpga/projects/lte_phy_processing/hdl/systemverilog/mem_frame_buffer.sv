`timescale 1ns/1ps

module mem_frame_buffer #(
    parameter int CAP   = 9600,
    parameter int WIDTH = 32,

    localparam int ADDR_W = (CAP <= 2) ? 1 : $clog2(CAP)
)(
    input  wire                i_clk,
    input  wire                i_wr_en,
    input  wire [ADDR_W-1:0]   i_wr_addr,
    input  wire [WIDTH-1:0]    i_wr_data,
    input  wire                i_rd_en,
    input  wire [ADDR_W-1:0]   i_rd_addr,
    output reg  [WIDTH-1:0]    o_rd_data
);

    // One write port + one read port, common clock. Capture and scan phases
    // are separated in lte_phy_pss_corr, so this maps naturally to BRAM.
    (* ram_style = "block" *) reg [WIDTH-1:0] mem [0:CAP-1];

    always @(posedge i_clk) begin
        if (i_wr_en)
            mem[i_wr_addr] <= i_wr_data;
    end

    always @(posedge i_clk) begin
        if (i_rd_en)
            o_rd_data <= mem[i_rd_addr];
    end

endmodule
