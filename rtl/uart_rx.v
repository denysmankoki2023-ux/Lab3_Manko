// =============================================================================
// uart_rx.v — приймач UART (Receiver, Rx)
// Лабораторна робота №3, варіант 10: UART / Verilog
// Студент: Манько Д. І., КІ-406
//
// Приймає кадр 8N1. Алгоритм:
//   1) вхід rx синхронізується двома тригерами (захист від метастабільності);
//   2) спадний фронт 1 -> 0 у стані спокою — початок старт-біта;
//   3) через половину біта перевіряємо, що лінія все ще 0 (відсіювання завад);
//   4) далі кожні CLKS_PER_BIT тактів читаємо біт у середині його інтервалу;
//   5) у середині стоп-біта: 1 — байт прийнято (rx_valid), 0 — помилка кадру.
// =============================================================================
`timescale 1ns / 1ps

module uart_rx #(
    parameter integer CLK_FREQ  = 12_000_000,  // тактова частота, Гц
    parameter integer BAUD_RATE = 115_200      // бодова швидкість, біт/с
)(
    input  wire       clk,       // системний тактовий сигнал
    input  wire       rst,       // синхронне скидання, активний рівень 1
    input  wire       rx,        // послідовний вхід (лінія RxD)
    output reg  [7:0] rx_data,   // прийнятий байт
    output reg        rx_valid,  // імпульс на 1 такт: rx_data дійсний
    output reg        rx_error   // імпульс на 1 такт: помилка кадру (стоп-біт = 0)
);

    // ---- Дільник частоти ----
    localparam integer CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
    localparam integer HALF_BIT      = CLKS_PER_BIT / 2;
    localparam integer CNT_W         = $clog2(CLKS_PER_BIT);

    // ---- Стани FSM ----
    localparam [1:0] S_IDLE  = 2'd0,  // очікування старт-біта
                     S_START = 2'd1,  // перевірка середини старт-біта
                     S_DATA  = 2'd2,  // прийом 8 біт даних
                     S_STOP  = 2'd3;  // перевірка стоп-біта

    // ---- Синхронізатор входу та детектор фронту ----
    reg rx_meta, rx_sync, rx_prev;
    always @(posedge clk) begin
        if (rst) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
            rx_prev <= 1'b1;
        end else begin
            rx_meta <= rx;       // 1-й тригер синхронізатора
            rx_sync <= rx_meta;  // 2-й тригер — стабільний сигнал
            rx_prev <= rx_sync;  // попереднє значення для виявлення фронту
        end
    end
    wire start_edge = rx_prev & ~rx_sync;  // перехід 1 -> 0

    reg [1:0]       state;      // поточний стан FSM
    reg [CNT_W-1:0] baud_cnt;   // лічильник тактів усередині біта
    reg [2:0]       bit_idx;    // номер біта даних (0..7)
    reg [7:0]       shift_reg;  // зсувний регістр прийому

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            baud_cnt  <= 0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
            rx_error  <= 1'b0;
        end else begin
            rx_valid <= 1'b0;   // імпульсні виходи за замовчуванням 0
            rx_error <= 1'b0;

            case (state)
                // Чекаємо спадного фронту — початку старт-біта
                S_IDLE: begin
                    baud_cnt <= 0;
                    bit_idx  <= 3'd0;
                    if (start_edge)
                        state <= S_START;
                end

                // Середина старт-біта: якщо лінія знову 1 — це була завада
                S_START: begin
                    if (baud_cnt == HALF_BIT - 1) begin
                        baud_cnt <= 0;
                        state    <= (rx_sync == 1'b0) ? S_DATA : S_IDLE;
                    end else
                        baud_cnt <= baud_cnt + 1'b1;
                end

                // Читання біта в середині кожного бітового інтервалу
                S_DATA: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt  <= 0;
                        shift_reg <= {rx_sync, shift_reg[7:1]};  // LSB першим
                        if (bit_idx == 3'd7)
                            state <= S_STOP;
                        else
                            bit_idx <= bit_idx + 1'b1;
                    end else
                        baud_cnt <= baud_cnt + 1'b1;
                end

                // Середина стоп-біта: перевірка коректності кадру
                S_STOP: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        state    <= S_IDLE;
                        if (rx_sync) begin
                            rx_data  <= shift_reg;
                            rx_valid <= 1'b1;
                        end else
                            rx_error <= 1'b1;   // framing error
                    end else
                        baud_cnt <= baud_cnt + 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
