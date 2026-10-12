"""Nonblocking firmware commands via UART, plus bounded serial log capture."""
import argparse
import codecs
from pathlib import Path
import time
import serial
import sys

# Camera initialization includes GB18030 text; byte fragments must not crash
# a GBK PowerShell console. Firmware tracking logs are ASCII.
sys.stdout.reconfigure(errors="backslashreplace")

parser = argparse.ArgumentParser()
parser.add_argument("--port", default="COM6")
parser.add_argument("--command", action="append", default=[])
parser.add_argument("--listen", type=float, default=2)
parser.add_argument("--log", type=Path)
args = parser.parse_args()
if args.listen < 0 or args.listen > 3600:
    parser.error("listen must be between 0 and 3600 seconds")
for command in args.command:
    if len(command) >= 128 or any(c in command for c in "\r\n"):
        parser.error("one command per --command, under 128 characters")
log = args.log.open("a", encoding="utf-8") if args.log else None
try:
    with serial.Serial(args.port, 115200, timeout=0.1, write_timeout=1,
                       rtscts=False, dsrdtr=False) as uart:
        for command in args.command:
            uart.write((command + "\r\n").encode("ascii"))
            time.sleep(0.05)
        deadline = time.monotonic() + args.listen
        decoder = codecs.getincrementaldecoder("gb18030")(errors="replace")
        while time.monotonic() < deadline:
            raw = uart.read(max(1, min(uart.in_waiting, 4096)))
            if raw:
                text = decoder.decode(raw)
                print(text, end="", flush=True)
                if log:
                    log.write(text)
                    log.flush()
except serial.SerialException as exc:
    raise SystemExit(f"Serial {args.port}: {exc}. Close any other serial terminal first.")
finally:
    if log:
        log.close()
