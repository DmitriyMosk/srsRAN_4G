/**
    @author Dmitry Moskovskikh
    @name mathematics complex cross correlation
    
    @description
        Как и было написано, в основе лежит FMA, 
        преобразованный в MAC (это FMA с обратной связью)
        где F = A * B + C, стало C = A * B + C

    Про размер аккумулятора, почему он так рассчитывается
    допустим, что WIDTH = 16
    
    A, B - 16-ти разрядные операнды,
    внутри этого модуля мы сделали так:
    для A * B, чтобы учитывать WIDTH этих операндов
    мы создаём регистр размером WIDTH*2

    в целом, можно было бы просчитать для последовательностей, длинной CORR_SEQ
    но мне лень...
*/ 

`timescale 1ns/1ps
`include "lte_phy_math.vh"

module math_complex_corr #(
    parameter int WIDTH         = 16,
    parameter int CORR_SEQ_SIZE = 5,

    parameter int fma_pipe_size = 1,
    parameter int fma_acc_size  = 48
)(
    input wire                      i_rst, i_clk,

    // signal
    input wire signed [WIDTH - 1:0] i_data_i1, i_data_q1,
    input wire                      i_data1_valid, 

    // signal2
    input wire signed [WIDTH - 1:0] i_data_i2, i_data_q2,
    input wire                      i_data2_valid,

    // фактически будет 1, если corr_seq_idx == CORR_SEQ_SIZE
    // сигнал для того, что значение mag можно использовать
    output reg                      o_valid,

    // мнимая и реальная часть корреляции
    output reg signed [fma_acc_size - 1:0] o_im,
    output reg signed [fma_acc_size - 1:0] o_re
);  
    // размер счётчика окна
    localparam int IDX_W = (CORR_SEQ_SIZE <= 1) ? 1 : $clog2(CORR_SEQ_SIZE);
    // последний индекс значения из корреляционного окна
    localparam int LAST_IDX = CORR_SEQ_SIZE - 1;

    //
    //
    // signals defenitions
    //
    //

    // сигнал валидности data1 и data2
    wire op_valid_data = (i_data1_valid & i_data2_valid);
    // счётчик внутри корреляционного окна
    // указывает на сколько мы сместились относительно 0
    reg [IDX_W - 1:0] op_corr_w_idx;
    // сумма i1 * i2 и - q1 * q2
    wire signed [fma_acc_size - 1:0]  op_re;
    // сумма i1 * q2 и + q1 * i2
    wire signed [fma_acc_size - 1:0]  op_im;
    // говорит о том, что все 4 mac завершили итерацию
    wire                              op_valid_it;
    // указывает на то, какая это итерация в текущий момент
    // 1 - если последняя
    wire                              op_last_it;
    // сигнал для сброса аккумуляторов
    wire                              op_clr_mac;
    // аккумулятор i1,i2 и q1,q2
    wire signed [fma_acc_size - 1:0]  op_acc_ii, op_acc_qq, op_acc_iq, op_acc_qi;
    // валид с mac для i1,i2 и q1,q2 и i1,q2 и q1,i2
    wire                              op_val_ii, op_val_qq, op_val_iq, op_val_qi;
    // валид с mac для i1,i2 и q1,q2 и i1,q2 и q1,i2
    // (просто внутреннее умножение mac)
    wire                              op_val_mul_ii, op_val_mul_qq, op_val_mul_iq, op_val_mul_qi;
    
    //
    //
    // logic implementation
    //
    //

    assign op_valid_it = (
        (op_val_mul_ii & op_val_mul_qq) & 
        (op_val_mul_iq & op_val_mul_qi)
    );

    assign op_last_it    = (op_valid_it & (op_corr_w_idx == LAST_IDX));

    // corr control block
    always @(posedge i_clk) begin
        if (i_rst) begin 
            op_corr_w_idx <= 0;
        end else begin 
            if (op_valid_it) begin
                op_corr_w_idx <= (
                    op_last_it ? 0 : op_corr_w_idx + 1);
            end
        end 
    end

    assign op_clr_mac   = op_last_it;
    wire o_valid_w      = (
        (op_val_ii & op_val_qq) & 
        (op_val_iq & op_val_qi)
    );

    // I1 * I2
    math_mac_macro #(
        .A_WIDTH   	(WIDTH          ),
        .B_WIDTH   	(WIDTH          ),
        .ACC_WIDTH 	(fma_acc_size   ),
        .PIPE      	(fma_pipe_size  ))
    u_math_mac_macro_i1_i2(
        .i_clk       	(i_clk               ),
        .i_rst       	(i_rst               ),
        .i_clr       	(op_clr_mac          ),
        .i_a         	(i_data_i1           ),
        .i_b         	(i_data_i2           ),
        .i_valid     	(op_valid_data       ),
        .o_c         	(op_acc_ii           ),
        .o_valid     	(op_val_ii           ),
        .o_valid_mul    (op_val_mul_ii       )
    );

    // Q1 * Q2
    math_mac_macro #(
        .A_WIDTH   	(WIDTH          ),
        .B_WIDTH   	(WIDTH          ),
        .ACC_WIDTH 	(fma_acc_size   ),
        .PIPE      	(fma_pipe_size  ))
    u_math_mac_macro_q1_q2(
        .i_clk       	(i_clk                  ),
        .i_rst       	(i_rst                  ),
        .i_clr       	(op_clr_mac             ),
        .i_a         	(i_data_q1              ),
        .i_b         	(i_data_q2              ),
        .i_valid     	(op_valid_data          ),
        .o_c         	(op_acc_qq              ),
        .o_valid     	(op_val_qq              ),
        .o_valid_mul    (op_val_mul_qq          )
    );

    assign op_re = (
        o_valid_w
        ? ($signed(op_acc_ii) + $signed(op_acc_qq)) 
        : 0);

    // I1 * Q2
    math_mac_macro #(
        .A_WIDTH   	(WIDTH          ),
        .B_WIDTH   	(WIDTH          ),
        .ACC_WIDTH 	(fma_acc_size   ),
        .PIPE      	(fma_pipe_size  ))
    u_math_mac_macro_i1_q2(
        .i_clk       	(i_clk                  ),
        .i_rst       	(i_rst                  ),
        .i_clr       	(op_clr_mac             ),
        .i_a         	(i_data_i1              ),
        .i_b         	(i_data_q2              ),
        .i_valid     	(op_valid_data          ),
        .o_c         	(op_acc_iq              ),
        .o_valid     	(op_val_iq              ),
        .o_valid_mul    (op_val_mul_iq          )
    );

    // Q1 * I2
    math_mac_macro #(
        .A_WIDTH   	(WIDTH          ),
        .B_WIDTH   	(WIDTH          ),
        .ACC_WIDTH 	(fma_acc_size   ),
        .PIPE      	(fma_pipe_size  ))
    u_math_mac_macro_q1_i2(
        .i_clk       	(i_clk                  ),
        .i_rst       	(i_rst                  ),
        .i_clr       	(op_clr_mac             ),
        .i_a         	(i_data_q1              ),
        .i_b         	(i_data_i2              ),
        .i_valid     	(op_valid_data          ),
        .o_c         	(op_acc_qi              ),
        .o_valid     	(op_val_qi              ),
        .o_valid_mul    (op_val_mul_qi          )
    );

    assign op_im = (
        o_valid_w
        ? ($signed(op_acc_qi) - $signed(op_acc_iq))
        : 0);

    always @(posedge i_clk) begin
        if (i_rst) begin
            o_valid <= 1'b0;
            o_re    <= '0;
            o_im    <= '0;
        end else begin
            o_valid <= o_valid_w;
            if (o_valid_w) begin
                o_re <= op_re;
                o_im <= op_im;
            end
        end
    end
endmodule
