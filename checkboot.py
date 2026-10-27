import mmap, struct

IMG = r"D:/rpi/os.img"
targets = [b"kernel.img", b"kernel7.img", b"kernel7l.img", b"kernel_2712.img",
           b"bcm2708-rpi-b-plus.dtb", b"bcm2708-rpi-b.dtb", b"bcm2711-rpi-4-b.dtb",
           b"bcm2835-rpi-b-plus.dtb", b"start.elf", b"bootcode.bin", b"config.txt", b"cmdline.txt"]
found = {}
with open(IMG, "rb") as f:
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    # FAT32 启动分区位于 LBA 16384 起、512MB
    start = 16384 * 512
    end = start + (1048576 * 512)
    blob = m[start:end]
    for t in targets:
        found[t.decode()] = blob.count(t)
    m.close()

print("启动分区(FAT32, 512MB) 中的关键文件引用计数：")
for k, v in found.items():
    mark = "✔" if v > 0 else "✘"
    print(f"  {mark} {k:<28} {v}")
print()
if found["kernel.img"] > 0:
    print("结论：存在 kernel.img（ARMv6），Pi 1 B+ 可以引导。")
else:
    print("结论：没有 kernel.img —— 这代镜像已丢弃 ARMv6，Pi 1 B+ 无法启动，需退回 Bookworm/Bullseye。")
if found["bcm2708-rpi-b-plus.dtb"] > 0 or found["bcm2835-rpi-b-plus.dtb"] > 0:
    print("结论：存在 B+ 的设备树，型号匹配。")
