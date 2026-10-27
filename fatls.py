"""最小 FAT32 解析器：列出树莓派启动分区根目录"""
import struct, sys

IMG = r"D:/rpi/os.img"
PART_LBA = 16384
SECT = 512

f = open(IMG, "rb")
def rd(lba, n=1):
    f.seek(lba * SECT)
    return f.read(n * SECT)

bs = rd(PART_LBA)
bps       = struct.unpack("<H", bs[0x0B:0x0D])[0]
spc       = bs[0x0D]
reserved  = struct.unpack("<H", bs[0x0E:0x10])[0]
nfats     = bs[0x10]
fatsz     = struct.unpack("<I", bs[0x24:0x28])[0]
rootclus  = struct.unpack("<I", bs[0x2C:0x30])[0]
print(f"FAT32: bps={bps} spc={spc} reserved={reserved} nfats={nfats} fatsz={fatsz} rootclus={rootclus}")

part_base = PART_LBA
fat_start = part_base + reserved
data_start = part_base + reserved + nfats * fatsz
cluster_bytes = bps * spc

def cluster_off(c):
    return (data_start + (c - 2) * spc) * SECT

def read_chain(start):
    out = b""
    c = start
    guard = 0
    while 2 <= c < 0x0FFFFFF8 and guard < 10000:
        out += rd((data_start + (c - 2) * spc), spc)
        f.seek((fat_start * SECT) + c * 4)
        c = struct.unpack("<I", f.read(4))[0] & 0x0FFFFFFF
        guard += 1
    return out

data = read_chain(rootclus)
entries = []
lfn = []
for i in range(0, len(data), 32):
    e = data[i:i+32]
    if len(e) < 32 or e[0] == 0x00:
        break
    if e[0] == 0xE5:
        lfn = []
        continue
    attr = e[11]
    if attr == 0x0F:  # LFN
        chunk = e[1:11] + e[14:26] + e[28:32]
        try:
            lfn.insert(0, chunk.decode("utf-16-le", "ignore"))
        except Exception:
            pass
        continue
    name = e[0:8].decode("ascii", "ignore").strip()
    ext = e[8:11].decode("ascii", "ignore").strip()
    sfn = name + ("." + ext if ext else "")
    long = "".join(lfn).split("\x00")[0] if lfn else ""
    lfn = []
    size = struct.unpack("<I", e[28:32])[0]
    if sfn in (".", "..") or e[0] == 0x2E:
        continue
    entries.append((long or sfn, sfn, size, attr))

print(f"根目录共 {len(entries)} 项：\n")
for long, sfn, size, attr in sorted(entries, key=lambda x: -x[2]):
    kind = "DIR " if attr & 0x10 else "FILE"
    print(f"  {kind} {size/1024/1024:9.2f} MB  {long or sfn}")

names = [e[0] for e in entries]
print()
for want in ("kernel.img", "kernel7.img", "bcm2708-rpi-b-plus.dtb", "cmdline.txt", "config.txt"):
    print(f"  {'✔ 存在' if want in names else '✘ 缺失'}  {want}")
f.close()
