// =============================================================================
// uart_tx.v — передавач UART (Transmitter, Tx)
// Лабораторна робота №3, варіант 10: UART / Verilog
// Студент: Манько Д. І., КІ-406
//
// Формат кадру 8N1: 1 старт-біт (0), 8 біт даних (молодший біт першим),
// без біта парності, 1 стоп-біт (1). У стані спокою лінія TX = 1.
//
// Бодова швидкість формується дільником тактової частоти:
//   CLKS_PER_BIT = CLK_FREQ / BAUD_RATE (12 МГц / 115200 = 104 такти на біт).
// =============================================================================
`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ  = 12_000_000,  // тактова частота, Гц
    parameter integer BAUD_RATE = 115_200      // бодова швидкість, біт/с
)(
    input  wire       clk,       // системний тактовий сигнал
    input  wire       rst,       // синхронне скидання, активний рівень 1
    input  wire [7:0] tx_data,   // байт для передачі
    input  wire       tx_start,  // імпульс запуску передачі (1 такт)
    output reg        tx,        // послідовний вихід (лінія TxD)
    output wire       tx_busy,   // 1 — триває передача кадру
    output reg        tx_done    // імпульс на 1 такт після стоп-біта
);

    // ---- Дільник частоти: кількість тактів clk на один біт UART ----
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam integer CNT_W        = $clog2(CLKS_PER_BIT);

    // ---- Стани скінченного автомата (FSM) ----
    localparam [1:0] S_IDLE  = 2'd0,  // очікування tx_start, лінія = 1
                     S_START = 2'd1,  // передача старт-біта (0)
                     S_DATA  = 2'd2,  // передача 8 біт даних
                     S_STOP  = 2'd3;  // передача стоп-біта (1)

    reg [1:0]       state;      // поточний стан FSM
    reg [CNT_W-1:0] baud_cnt;   // лічильник тактів усередині одного біта
    reg [2:0]       bit_idx;    // номер поточного біта даних (0..7)
    reg [7:0]       shift_reg;  // зсувний регістр з даними для передачі

    // Кінець тривалості поточного біта (тік бодового генератора)
    wire baud_tick = (baud_cnt == CLKS_PER_BIT - 1);

    assign tx_busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            tx        <= 1'b1;          // лінія у стані спокою
            baud_cnt  <= 0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            tx_done   <= 1'b0;
        end else begin
            tx_done <= 1'b0;            // за замовчуванням імпульс знятий

            case (state)
                // Очікування команди: фіксуємо байт і починаємо старт-біт
                S_IDLE: begin
                    tx       <= 1'b1;
                    baud_cnt <= 0;
                    bit_idx  <= 3'd0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx        <= 1'b0;      // старт-біт
                        state     <= S_START;
                    end
                end

                // Старт-біт триває CLKS_PER_BIT тактів, потім біт даних 0
                S_START: begin
                    if (baud_tick) begin
                        baud_cnt <= 0;
                        tx       <= shift_reg[0];  // молодший біт першим
                        state    <= S_DATA;
                    end else
                        baud_cnt <= baud_cnt + 1'b1;
                end

                // Біти даних: після кожного біта зсуваємо регістр праворуч
                S_DATA: begin
                    if (baud_tick) begin
                        baud_cnt <= 0;
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;         // стоп-біт
                            state <= S_STOP;
                        end else begin
                            bit_idx   <= bit_idx + 1'b1;
                            shift_reg <= {1'b0, shift_reg[7:1]};
                            tx        <= shift_reg[1];  // наступний біт
                        end
                    end else
                        baud_cnt <= baud_cnt + 1'b1;
                end

                // Стоп-біт, після нього — сигнал завершення і повернення в IDLE
                S_STOP: begin
                    if (baud_tick) begin
                        baud_cnt <= 0;
                        tx_done  <= 1'b1;
                        state    <= S_IDLE;
                    end else
                        baud_cnt <= baud_cnt + 1'b1;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
