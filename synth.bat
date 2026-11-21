@echo off
rem Synthesis for Lattice iCE40UP5K-SG48 (iCEBreaker): Yosys + nextpnr + icepack
if not exist build mkdir build
yosys -p "synth_ice40 -top uart_top -json build/uart_top.json" -l build\yosys.log rtl\uart_tx.v rtl\uart_rx.v rtl\uart_top.v
if errorlevel 1 exit /b 1
nextpnr-ice40 --up5k --package sg48 --json build\uart_top.json --pcf constr\icebreaker.pcf --asc build\uart_top.asc --freq 12 -l build\nextpnr.log
if errorlevel 1 exit /b 1
icepack build\uart_top.asc build\uart_top.bin
echo.
echo ===== Resource utilisation =====
findstr /C:"ICESTORM_LC" /C:"SB_IO" /C:"SB_GB" build\nextpnr.log
echo ===== Timing =====
findstr /C:"Max frequency" build\nextpnr.log
