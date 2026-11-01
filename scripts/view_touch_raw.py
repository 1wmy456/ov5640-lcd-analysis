"""Convert a captured DMA RGBx binary to PNG using only the Python standard library."""
import argparse,struct,zlib
from array import array
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('input',type=Path);p.add_argument('output',type=Path);a=p.parse_args()
data=array('I');data.frombytes(a.input.read_bytes());assert len(data)==800*480
rgb=bytes(v for pixel in data for v in ((pixel>>16)&255,(pixel>>8)&255,pixel&255))
def chunk(kind,payload):return struct.pack('>I',len(payload))+kind+payload+struct.pack('>I',zlib.crc32(kind+payload)&0xffffffff)
rows=b''.join(b'\x00'+rgb[y*2400:(y+1)*2400] for y in range(480))
a.output.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',800,480,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows))+chunk(b'IEND',b''))
print('source_frame',sum((data[i]>>24)<<(8*i) for i in range(4)),'tail_meta',hex(data[-1]>>24))
