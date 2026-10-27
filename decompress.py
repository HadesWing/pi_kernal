#!/usr/bin/env python3
"""校验 .xz 的 sha256 → 流式解压成 os.img → 报告大小与关键特征"""
import hashlib
import lzma
import os
import sys
import time

DL = os.path.join(os.path.expanduser("~"), "Downloads", "rpi")
SRC = os.path.join(DL, "mirror.img.xz")
SHA_FILE = os.path.join(DL, "2026-10-06-raspios-trixie-armhf-lite.img.xz.sha256")
DST = os.path.join(os.environ.get("RPI_DIR", r"D:\rpi"), "os.img")


def sha256_of(path, chunk=8 << 20):
    h = hashlib.sha256()
    n = 0
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
            n += len(b)
    return h.hexdigest(), n


def main():
    t0 = time.time()
    print("[1/3] 校验压缩包 sha256 ...", flush=True)
    expect = open(SHA_FILE).read().split()[0].strip()
    got, size = sha256_of(SRC)
    print(f"      期望 {expect}")
    print(f"      实际 {got}")
    if expect != got:
        print("      ✘ 校验失败，镜像损坏，必须重新下载", flush=True)
        return 2
    print(f"      ✔ 一致（{size/1024/1024:.0f} MB）", flush=True)

    print("[2/3] 解压 ...", flush=True)
    total_out = 0
    last = -1
    with lzma.open(SRC, "rb") as fin, open(DST, "wb") as fout:
        while True:
            b = fin.read(8 << 20)
            if not b:
                break
            fout.write(b)
            total_out += len(b)
            pct = int(total_out / (4.0 * 1024**3) * 100)
            step = pct // 10 * 10
            if step != last:
                print(f"      ~{min(step,100)}%  {total_out/1024**3:.2f} GB", flush=True)
                last = step
    print(f"      ✔ 输出 {DST}  {total_out/1024**3:.2f} GB  用时 {time.time()-t0:.0f}s", flush=True)

    print("[3/3] 结构检查 ...", flush=True)
    with open(DST, "rb") as f:
        mbr = f.read(512)
    if mbr[510:512] != b"\x55\xaa":
        print("      ✘ 没有 MBR 签名，这不是标准树莓派镜像", flush=True)
        return 3
    # 解析前两个主分区
    import struct
    for i in range(4):
        e = mbr[446 + i * 16: 446 + (i + 1) * 16]
        if e[4] == 0:
            continue
        boot_flag = e[0]
        ptype = e[4]
        lba = struct.unpack("<I", e[8:12])[0]
        cnt = struct.unpack("<I", e[12:16])[0]
        print(f"      分区{i+1}: type=0x{ptype:02x} 起始LBA={lba} 扇区数={cnt} ({cnt*512/1024/1024:.0f} MB) boot={boot_flag}")

    # 校验 8GB 卡是否够
    need = total_out
    card = 7.34 * 1024**3
    print(f"      镜像 {need/1024**3:.2f} GB / 卡 {card/1024**3:.2f} GB → {'够' if need < card else '不够'}", flush=True)
    print("完成", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
