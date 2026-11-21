// =============================================================================
// tb_uart.v — тестбенч для функціональної верифікації uart_tx та uart_rx
// Лабораторна робота №3, варіант 10: UART / Verilog
// Студент: Манько Д. І., КІ-406
//
// Тестбенч імітує зовнішнє середовище:
//   * генерує тактовий сигнал 12 МГц (CLK) та скидання (RESET);
//   * тест 1 (Tx): подає байти на вхід передавача і незалежним монітором
//     перевіряє на лінії TxD старт-біт, 8 біт даних (LSB першим) і стоп-біт;
//   * тест 2 (Rx): сам формує кадри UART на лінії RxD (імітація іншого
//     пристрою з «справжньою» швидкістю 115200 бод) і перевіряє прийняті байти;
//   * тест 3 (петля): вихід Tx з'єднано з входом Rx;
//   * тест 4: кадр з неправильним стоп-бітом -> очікується rx_error.
// Результат: лічильник помилок; у кінці «ALL TESTS PASSED» або «FAILED».
// =============================================================================
`timescale 1ns / 1ps

module tb_uart;

    // ---- Параметри ----
    localparam integer CLK_FREQ     = 12_000_000;
    localparam integer BAUD_RATE    = 115_200;
    localparam real    CLK_PERIOD   = 1.0e9 / CLK_FREQ;          // 83.333 нс
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;      // 104
    localparam real    TX_BIT_TIME  = CLKS_PER_BIT * CLK_PERIOD; // тривалість біта передавача
    localparam real    EXT_BIT_TIME = 1.0e9 / BAUD_RATE;         // 8680.6 нс — «чужий» пристрій

    // ---- Сигнали ----
    reg        clk = 1'b0;
    reg        rst = 1'b1;

    reg  [7:0] tx_data  = 8'd0;
    reg        tx_start = 1'b0;
    wire       tx_line, tx_busy, tx_done;

    reg        loopback = 1'b0;  // 1 — Rx підключено до виходу Tx
    reg        ext_rx   = 1'b1;  // лінія, яку формує тестбенч
    wire       rx_line  = loopback ? tx_line : ext_rx;

    wire [7:0] rx_data;
    wire       rx_valid, rx_error;

    integer errors = 0;
    integer checks = 0;

    // ---- Генерація тактового сигналу ----
    always #(CLK_PERIOD / 2.0) clk = ~clk;

    // ---- Пристрої, що перевіряються (DUT) ----
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) dut_tx (
        .clk(clk), .rst(rst), .tx_data(tx_data), .tx_start(tx_start),
        .tx(tx_line), .tx_busy(tx_busy), .tx_done(tx_done)
    );

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) dut_rx (
        .clk(clk), .rst(rst), .rx(rx_line),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_error(rx_error)
    );

    // ---- Допоміжна процедура перевірки ----
    task check(input cond, input [8*48-1:0] msg);
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("  [FAIL] %0s  (t=%0t)", msg, $time);
            end
        end
    endtask

    // ---- Запуск передачі одного байта через uart_tx ----
    task tx_send(input [7:0] data);
        begin
            wait (!tx_busy);                    // чекаємо завершення попереднього кадру
            @(negedge clk);
            tx_data  = data;
            tx_start = 1'b1;
            @(negedge clk);
            tx_start = 1'b0;
        end
    endtask

    // ---- Монітор лінії TxD: читає кадр у серединах бітів ----
    task tx_monitor(input [7:0] expected);
        integer i;
        reg [7:0] got;
        begin
            @(negedge tx_line);                 // початок старт-біта
            #(TX_BIT_TIME / 2.0);
            check(tx_line == 1'b0, "Tx: start bit != 0");
            for (i = 0; i < 8; i = i + 1) begin
                #(TX_BIT_TIME);
                got[i] = tx_line;
            end
            #(TX_BIT_TIME);
            check(tx_line == 1'b1, "Tx: stop bit != 1");
            check(got == expected, "Tx: wrong data on TxD line");
            $display("  Tx: sent 0x%02h, line shows 0x%02h  %0s",
                     expected, got, (got == expected) ? "OK" : "ERROR");
        end
    endtask

    // ---- Імітація зовнішнього передавача на лінії RxD ----
    task ext_send(input [7:0] data, input stop_bit);
        integer i;
        begin
            ext_rx = 1'b0;                      // старт-біт
            #(EXT_BIT_TIME);
            for (i = 0; i < 8; i = i + 1) begin
                ext_rx = data[i];               // LSB першим
                #(EXT_BIT_TIME);
            end
            ext_rx = stop_bit;                  // стоп-біт (1 — коректний)
            #(EXT_BIT_TIME);
            ext_rx = 1'b1;                      // лінія у стан спокою
            #(EXT_BIT_TIME);
        end
    endtask

    // ---- Очікування результату приймача ----
    task rx_expect(input [7:0] expected);
        integer t;
        reg     seen;
        begin
            seen = 1'b0;
            for (t = 0; t < 12 * CLKS_PER_BIT && !seen; t = t + 1) begin
                @(posedge clk);
                if (rx_valid) begin
                    seen = 1'b1;
                    check(rx_data == expected, "Rx: wrong byte received");
                    $display("  Rx: expected 0x%02h, received 0x%02h  %0s",
                             expected, rx_data, (rx_data == expected) ? "OK" : "ERROR");
                end
                if (rx_error) check(1'b0, "Rx: unexpected framing error");
            end
            if (!seen) check(1'b0, "Rx: byte not received (timeout)");
        end
    endtask

    task rx_expect_error;
        integer t;
        reg     seen_err, seen_valid;
        begin
            seen_err = 1'b0; seen_valid = 1'b0;
            for (t = 0; t < 12 * CLKS_PER_BIT && !seen_err; t = t + 1) begin
                @(posedge clk);
                if (rx_error) seen_err   = 1'b1;
                if (rx_valid) seen_valid = 1'b1;
            end
            check(seen_err,    "Rx: framing error not detected");
            check(!seen_valid, "Rx: bad frame accepted as valid");
            $display("  Rx: frame with stop bit = 0 -> rx_error = %0d  %0s",
                     seen_err, (seen_err && !seen_valid) ? "OK" : "ERROR");
        end
    endtask

    // ---- Тестові дані ----
    reg [7:0] test_bytes [0:4];
    integer k;

    initial begin
        test_bytes[0] = 8'h55;  // 0101_0101 — чергування бітів
        test_bytes[1] = 8'hA3;
        test_bytes[2] = 8'h00;  // усі нулі
        test_bytes[3] = 8'hFF;  // усі одиниці
        test_bytes[4] = 8'h4D;  // ASCII 'M'

        $dumpfile("build/tb_uart.vcd");
        $dumpvars(0, tb_uart);

        // ---- Скидання ----
        rst = 1'b1;
        repeat (10) @(posedge clk);
        rst = 1'b0;
        repeat (10) @(posedge clk);

        // ---- Тест 1: передавач ----
        $display("TEST 1: transmitter (Tx -> TxD line monitor)");
        for (k = 0; k < 5; k = k + 1)
            fork
                tx_send(test_bytes[k]);
                tx_monitor(test_bytes[k]);
            join
        wait (!tx_busy);
        repeat (CLKS_PER_BIT) @(posedge clk);

        // ---- Тест 2: приймач (дані від «зовнішнього» пристрою) ----
        $display("TEST 2: receiver (external device -> RxD)");
        for (k = 0; k < 5; k = k + 1)
            fork
                ext_send(~test_bytes[k] ^ 8'h0F, 1'b1);
                rx_expect(~test_bytes[k] ^ 8'h0F);
            join

        // ---- Тест 3: петля Tx -> Rx ----
        $display("TEST 3: loopback (Tx output -> Rx input)");
        loopback = 1'b1;
        repeat (CLKS_PER_BIT) @(posedge clk);
        for (k = 0; k < 5; k = k + 1)
            fork
                tx_send(test_bytes[k]);
                rx_expect(test_bytes[k]);
            join
        wait (!tx_busy);
        loopback = 1'b0;
        repeat (2 * CLKS_PER_BIT) @(posedge clk);

        // ---- Тест 4: помилка кадру ----
        $display("TEST 4: framing error (stop bit = 0)");
        fork
            ext_send(8'hC3, 1'b0);
            rx_expect_error;
        join
        repeat (2 * CLKS_PER_BIT) @(posedge clk);

        // ---- Підсумок ----
        $display("--------------------------------------------");
        if (errors == 0)
            $display("ALL TESTS PASSED (%0d checks)", checks);
        else
            $display("TESTS FAILED: %0d errors of %0d checks", errors, checks);
        $display("--------------------------------------------");
        $finish;
    end

    // ---- Сторожовий таймер: захист від зависання симуляції ----
    initial begin
        #20_000_000;
        $display("TIMEOUT: simulation stopped");
        $finish;
    end

endmodule
