import mmap
IMG = r"D:/rpi/os.img"
names = ["kernel.img", "kernel7.img", "bcm2708-rpi-b-plus.dtb", "bcm2835-rpi-b-plus.dtb",
         "bcm2709-rpi-2-b.dtb", "bcm2711-rpi-4-b.dtb", "overlays"]
with open(IMG, "rb") as f:
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    blob = m[16384*512: (16384+1048576)*512]
    print("按 UTF-16LE（FAT 长文件名真实存储形式）检索：")
    for n in names:
        cnt = blob.count(n.encode("utf-16-le"))
        print(f"  {'✔' if cnt else '✘'} {n:<26} {cnt}")
    m.close()
