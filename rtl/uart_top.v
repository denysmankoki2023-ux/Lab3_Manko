// =============================================================================
// uart_top.v — верхній модуль для синтезу (ПЛІС Lattice iCE40UP5K, плата iCEBreaker)
// Лабораторна робота №3, варіант 10: UART / Verilog
// Студент: Манько Д. І., КІ-406
//
// Луна-пристрій (echo): кожен байт, прийнятий на RX, передається назад на TX.
// Так у схемі задіяні обидва модулі — і приймач, і передавач.
// =============================================================================
`timescale 1ns / 1ps

module uart_top #(
    parameter integer CLK_FREQ  = 12_000_000,  // генератор плати iCEBreaker 12 МГц
    parameter integer BAUD_RATE = 115_200
)(
    input  wire clk,        // тактовий сигнал 12 МГц
    input  wire rx,         // вхід UART (від USB-UART перетворювача)
    output wire tx,         // вихід UART
    output wire led_err_n   // червоний світлодіод (активний 0): була помилка кадру
);

    // ---- Скидання при увімкненні живлення (power-on reset), 15 тактів ----
    reg [3:0] por_cnt = 4'd0;
    wire      rst     = ~&por_cnt;
    always @(posedge clk)
        if (rst) por_cnt <= por_cnt + 1'b1;

    // ---- Приймач ----
    wire [7:0] rx_data;
    wire       rx_valid, rx_error;
    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst(rst), .rx(rx),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_error(rx_error)
    );

    // ---- Буфер на 1 байт: якщо передавач зайнятий, байт чекає ----
    reg  [7:0] hold_data;
    reg        pending;
    wire       tx_busy, tx_done;
    wire       tx_start = pending & ~tx_busy;

    always @(posedge clk) begin
        if (rst)
            pending <= 1'b0;
        else if (rx_valid) begin
            hold_data <= rx_data;
            pending   <= 1'b1;
        end else if (tx_start)
            pending <= 1'b0;
    end

    // ---- Передавач ----
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_tx (
        .clk(clk), .rst(rst), .tx_data(hold_data), .tx_start(tx_start),
        .tx(tx), .tx_busy(tx_busy), .tx_done(tx_done)
    );

    // ---- Індикація помилки кадру (запам'ятовується до скидання) ----
    reg err_latch;
    always @(posedge clk)
        if (rst)           err_latch <= 1'b0;
        else if (rx_error) err_latch <= 1'b1;

    assign led_err_n = ~err_latch;

endmodule
