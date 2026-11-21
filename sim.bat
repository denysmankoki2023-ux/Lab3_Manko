@echo off
rem Simulation: compile with Icarus Verilog, run, open waveforms in GTKWave
if not exist build mkdir build
iverilog -g2012 -Wall -o build\sim.vvp rtl\uart_tx.v rtl\uart_rx.v tb\tb_uart.v
if errorlevel 1 exit /b 1
vvp -n build\sim.vvp
if errorlevel 1 exit /b 1
start "" gtkwave build\tb_uart.vcd tb\tb_uart.gtkw
