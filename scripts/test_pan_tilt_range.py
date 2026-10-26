"""Observed, manual 5us steps; never mark a mechanical range verified automatically."""
import argparse
from pathlib import Path
import re
import time
import serial

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--port', required=True)
parser.add_argument('--axis', choices=('yaw', 'pitch'), required=True)
parser.add_argument('--start', type=int, required=True)
parser.add_argument('--end', type=int, required=True)
parser.add_argument('--minimum', type=int, required=True)
parser.add_argument('--maximum', type=int, required=True)
parser.add_argument('--interval', type=float, default=0.8)
parser.add_argument('--log', type=Path, required=True)
args = parser.parse_args()
if not (500 <= args.minimum <= min(args.start,args.end) <=
        max(args.start,args.end) <= args.maximum <= 2500):
    parser.error('Endpoints must be within the explicitly supplied temporary limits')
if not (0 < abs(args.end-args.start) <= 50) or (args.end-args.start)%5:
    parser.error('One observed segment is at most 50us, in exact 5us steps')
if not 0.5 <= args.interval <= 3:
    parser.error('Step interval must be 0.5..3 seconds')

with args.log.open('a',encoding='utf-8') as log:
    def record(text):
        print(text,flush=True);log.write(text+'\n');log.flush()
    with serial.Serial(args.port,115200,timeout=0.1,write_timeout=1) as uart:
        pending = bytearray()
        def exchange(command, expected):
            record('TX '+command)
            uart.write((command+'\r\n').encode('ascii'))
            deadline=time.monotonic()+2
            while time.monotonic()<deadline:
                pending.extend(uart.read(max(1,min(uart.in_waiting,4096))))
                while b'\n' in pending:
                    raw,_,remaining=pending.partition(b'\n');pending[:]=remaining
                    line=raw.decode('ascii',errors='replace').strip()
                    if not line:continue
                    record(line)
                    if line.startswith('invalid command'):raise RuntimeError(line)
                    if expected in line:return line
            raise RuntimeError('No firmware acknowledgement: '+command)
        try:
            exchange('manual','manual/hold:')
            status=exchange('status','mode=manual ')
            pulse=int(re.search(r'\b'+args.axis+r'=(\d+)',status)[1])
            enabled=int(re.search(r'\ben=(\d+)',status)[1])
            if pulse!=args.start:
                raise RuntimeError(f'Actual {args.axis}={pulse}, expected starting position {args.start}; no jump issued')
            axis_bit=1 if args.axis=='yaw' else 2
            if not enabled&axis_bit:raise RuntimeError('Test axis must already be enabled by operator')
            exchange(f'limits {args.axis} {args.minimum} {args.maximum}',args.axis+' limits=')
            step=5 if args.end>args.start else -5
            for position in range(args.start+step,args.end+step,step):
                exchange(f'step {args.axis} {step}',f'{args.axis} step={step} us requested={position}')
                time.sleep(args.interval)
            status=exchange('status','mode=manual ')
            if int(re.search(r'\b'+args.axis+r'=(\d+)',status)[1])!=args.end:
                raise RuntimeError('Endpoint did not take effect')
            exchange('pwm','PWM_NET ')
            record('SEGMENT_COMPLETE: manual hold; mechanical clearance REQUIRES operator observation; no verify/auto command sent')
        except BaseException:
            uart.write(b'disable\r\n');uart.flush()
            record('ABORT: disable sent; inspect mechanics before re-enabling')
            raise
