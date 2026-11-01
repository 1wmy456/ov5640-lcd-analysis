"""Compile actual bare-metal C sources against a freshly generated Vitis BSP."""
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
compiled_sources = []
for source in sorted((out / "src").rglob("*.c")):
    obj = out / (source.relative_to(out / "src").as_posix().replace("/", "_") + ".o")
    source_flags = [*flags, "-O2"] if source.name in {"cap_components.c", "cap_runtime.c", "appearance_tracker.c", "appearance_runtime.c"} else flags
    subprocess.run([gcc, *source_flags, "-c", str(source), "-I" + str(bsp / "include"),
                    "-I" + str(out / "src"), "-o", str(obj)], check=True)
    objects.append(str(obj))
    compiled_sources.append(source.relative_to(out / "src").as_posix())
elf = out / "ov5640_lcd.elf"
subprocess.run([gcc, *flags, "-T", str(out / "src/lscript.ld"),
                "-specs=" + str(out / "src/Xilinx.spec"), "-L" + str(bsp / "lib"),
                "-Wl,-Map=" + str(out / "ov5640_lcd.map"), *objects,
                "-Wl,--start-group", "-lxil", "-lgcc", "-lc", "-lm", "-Wl,--end-group", "-o", str(elf)], check=True)
symbols = subprocess.check_output([str(args.tools / "arm-none-eabi-nm.exe"), "-n", str(elf)]).decode()
(out / "symbols.txt").write_text(symbols)
end_address = int(next(line.split()[0] for line in symbols.splitlines()
                       if len(line.split()) == 3 and line.split()[2] == "_end"), 16)
if end_address >= 0x01100000:
    raise RuntimeError("Linked program/heap/stacks invade the VDMA framebuffer")
if (out / "src/pan_tilt/pan_tilt_app.c").exists():
    required = {"pan_tilt/pan_tilt_app.c", "pan_tilt/pan_tilt_driver.c", "pan_tilt/tracking_control.c",
                "pan_tilt/cap_components.c", "pan_tilt/cap_runtime.c"}
    if not required.issubset(compiled_sources):
        raise RuntimeError("Missing pan-tilt source in actual compilation")
subprocess.run([str(args.tools / "arm-none-eabi-size.exe"), str(elf)], check=True)
manifest = {"bsp": str(bsp), "elf_sha256": hashlib.sha256(elf.read_bytes()).hexdigest(),
            "compiled_sources": compiled_sources, "end_address": hex(end_address),
            "source_sha256": {p.relative_to(out / "src").as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                              for p in (out / "src").rglob("*") if p.is_file()}}
(out / "build_manifest.json").write_text(json.dumps(manifest, indent=2))
print("BOARD_APP: PASS application and linker script compiled:", elf)
print("BOARD_APP: compiled", len(compiled_sources), "C sources; _end=", hex(end_address), "below framebuffer 0x01100000")
