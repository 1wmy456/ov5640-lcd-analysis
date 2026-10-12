"""Compile preserved bare-metal C with a generated Vitis BSP (no GUI app needed)."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--bsp", required=True, type=Path)
parser.add_argument("--out", required=True, type=Path)
parser.add_argument("--tools", type=Path, default=Path("C:/Xilinxx/Vitis/2020.2/gnu/aarch32/nt/gcc-arm-none-eabi/bin"))
args = parser.parse_args()
out, bsp = args.out.resolve(), args.bsp.resolve()
assert out.is_relative_to((root / "build").resolve()) and not out.exists()
assert (bsp / "lib/libxil.a").is_file()
out.mkdir(parents=True)
shutil.copytree(root / "vitis/ov5640_lcd/src", out / "src")
gcc = str(args.tools / "arm-none-eabi-gcc.exe")
flags = ["-mcpu=cortex-a9", "-mfpu=vfpv3", "-mfloat-abi=hard", "-O0", "-g3", "-Wall"]
objects = []
for source in sorted((out / "src").rglob("*.c")):
    obj = out / (source.relative_to(out / "src").as_posix().replace("/", "_") + ".o")
    subprocess.run([gcc, *flags, "-c", str(source), "-I" + str(bsp / "include"),
                    "-I" + str(out / "src"), "-o", str(obj)], check=True)
    objects.append(str(obj))
elf = out / "ov5640_lcd.elf"
subprocess.run([gcc, *flags, "-T", str(out / "src/lscript.ld"),
                "-specs=" + str(out / "src/Xilinx.spec"), "-L" + str(bsp / "lib"),
                "-Wl,-Map=" + str(out / "ov5640_lcd.map"), *objects,
                "-Wl,--start-group", "-lxil", "-lgcc", "-lc", "-Wl,--end-group", "-o", str(elf)], check=True)
symbols = subprocess.check_output([str(args.tools / "arm-none-eabi-nm.exe"), "-n", str(elf)]).decode()
(out / "symbols.txt").write_text(symbols)
subprocess.run([str(args.tools / "arm-none-eabi-size.exe"), str(elf)], check=True)
manifest = {"bsp": str(bsp), "elf_sha256": hashlib.sha256(elf.read_bytes()).hexdigest(),
            "source_sha256": {p.relative_to(out / "src").as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in (out / "src").rglob("*") if p.is_file()}}
(out / "build_manifest.json").write_text(json.dumps(manifest, indent=2))
print("BOARD_APP: PASS original C and linker script compiled:", elf)
