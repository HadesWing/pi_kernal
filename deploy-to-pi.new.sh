#!/usr/bin/env bash
# 从 WSL 内直接部署内核到树莓派（借用 Windows OpenSSH，复用 pi-lab 别名和密钥）
# 用法：bash scripts/deploy-to-pi.sh
# 前置：VSCode 任务「4. 导出产物到 D 盘」已跑过
set -uo pipefail

# 找到 Windows OpenSSH（interop 下直接调用，用它自带 ~/.ssh/config 的 pi-lab 别名）
SSH_EXE=""
for c in "/mnt/c/Windows/System32/OpenSSH/ssh.exe" "ssh.exe"; do
  if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then SSH_EXE="$c"; break; fi
done
SCP_EXE="${SSH_EXE/ssh.exe/scp.exe}"
[ -n "$SSH_EXE" ] || { echo "[中止] 找不到 Windows OpenSSH"; exit 1; }

OUT=/mnt/d/rpi/linux/out
IMG=$OUT/kernel.img
MODS=$OUT/modules/lib/modules

[ -f "$IMG" ] || { echo "[中止] 缺少 $IMG —— 先跑任务 4"; exit 1; }
echo "==> 本地内核: $(ls -lh "$IMG" | awk '{print $5}')"

# 版本号自检：导出的内核和本仓库的版本号必须一致，否则会装错模块
LOCAL_VER=$(cat include/config/kernel.release 2>/dev/null | tr -d '\r\n')
if [ -n "$LOCAL_VER" ]; then
  echo "==> 本仓库版本: $LOCAL_VER（导出目录里有: $(ls -1 "$MODS" 2>/dev/null | tr '\n' ' ')）"
fi

# 上传内核（Windows scp 需要 Windows 路径）
IMG_W=$(wslpath -w "$IMG")
"$SCP_EXE" "$IMG_W" pi-lab:/tmp/kernel.img || { echo "[中止] 上传失败"; exit 1; }

# 上传模块（有才传；只改内核没动模块时可跳过）
# 版本号以本仓库 include/config/kernel.release 为准。
# 绝对不能 ls 整个目录——新旧两个版本目录并存时会取到两行，tar 直接失败。
MODS_TGZ=""
if [ -d "$MODS" ]; then
  VER=${LOCAL_VER:-$(ls -1 "$MODS" | tail -1)}
  if [ -z "$VER" ] || [ ! -d "$MODS/$VER" ]; then
    echo "[中止] 找不到 $MODS/$VER 对应的模块目录。"
    echo "        目录里现有：$(ls -1 "$MODS" | tr '\n' ' ')"
    echo "        多半是导出的还是旧版本号，先跑任务 4 重新导出。"
    exit 1
  fi
  echo "==> 打包模块 ($VER)"
  tar -C "$OUT/modules" -czf /tmp/pi-modules.tgz "lib/modules/$VER" || { echo "[中止] 打包失败"; exit 1; }
  MODS_TGZ=$(wslpath -w /tmp/pi-modules.tgz)
  "$SCP_EXE" "$MODS_TGZ" pi-lab:/tmp/pi-modules.tgz || echo "[警告] 模块上传失败，继续（内核仍可启动）"
fi

# 板上：备份旧内核 → 安装新内核和模块 → 重启
echo "==> 板上安装并重启"
"$SSH_EXE" pi-lab 'set -e
  sudo cp /boot/firmware/kernel.img /boot/firmware/kernel.img.bak
  sudo cp /tmp/kernel.img /boot/firmware/kernel.img
  if [ -f /tmp/pi-modules.tgz ]; then
    sudo tar xzf /tmp/pi-modules.tgz -C /
  fi
  sync
  ls -lh /boot/firmware/kernel.img /boot/firmware/kernel.img.bak
  echo "--- rebooting ---"
  sudo reboot' 2>&1 | grep -v "Connection to" || true

# 等待上线
echo "==> 等待重启上线（最多 5 分钟）"
START=$(date +%s)
for i in $(seq 1 60); do
  sleep 5
  if "$SSH_EXE" -o ConnectTimeout=3 pi-lab true 2>/dev/null; then
    echo "==> 上线，等待耗时 $(( $(date +%s) - START )) 秒"
    "$SSH_EXE" pi-lab "uname -a && free -m | head -2 && ls /sys/class/drm 2>&1 | head -3"
    exit 0
  fi
done

echo "==> [失败] 5 分钟未上线。救砖：拔卡→PC 上把 bootfs 的 kernel.img.bak 改回 kernel.img"
exit 2
