import struct
IMG = r"D:/rpi/os.img"; PART_LBA = 16384; SECT = 512
f = open(IMG, "rb")
def rd(lba, n=1):
    f.seek(lba*SECT); return f.read(n*SECT)
bs = rd(PART_LBA)
bps = struct.unpack("<H", bs[0x0B:0x0D])[0]; spc = bs[0x0D]
reserved = struct.unpack("<H", bs[0x0E:0x10])[0]; nfats = bs[0x10]
fatsz = struct.unpack("<I", bs[0x24:0x28])[0]; rootclus = struct.unpack("<I", bs[0x2C:0x30])[0]
fat_start = PART_LBA + reserved
data_start = PART_LBA + reserved + nfats*fatsz
def read_chain(start, limit=64):
    out=b""; c=start; g=0
    while 2 <= c < 0x0FFFFFF8 and g < limit:
        out += rd(data_start + (c-2)*spc, spc)
        f.seek(fat_start*SECT + c*4); c = struct.unpack("<I", f.read(4))[0] & 0x0FFFFFFF; g+=1
    return out
data = read_chain(rootclus)
ents=[]; lfn=[]
for i in range(0,len(data),32):
    e=data[i:i+32]
    if len(e)<32 or e[0]==0: break
    if e[0]==0xE5: lfn=[]; continue
    attr=e[11]
    if attr==0x0F:
        c=e[1:11]+e[14:26]+e[28:32]; lfn.insert(0,c.decode("utf-16-le","ignore")); continue
    long="".join(lfn).split("\x00")[0] if lfn else ""; lfn=[]
    if e[0]==0x2E: continue
    clus=struct.unpack("<H", e[26:28])[0] | (struct.unpack("<H", e[20:22])[0]<<16)
    size=struct.unpack("<I", e[28:32])[0]
    ents.append((long or (e[0:8].decode('ascii','ignore').strip()+"."+e[8:11].decode('ascii','ignore').strip()), clus, size))
d={n:(c,s) for n,c,s in ents}
for name in ("cmdline.txt","config.txt","user-data","meta-data","network-config","issue.txt"):
    if name in d:
        c,s = d[name]
        raw = read_chain(c)[:s].decode("utf-8","replace")
        print(f"===== {name} ({s} 字节) =====")
        print(raw if raw.strip() else "（空文件）")
        print()
    else:
        print(f"===== {name} 不存在 =====")
f.close()
