#!/bin/bash
# 从 simulator01 镜像抽取「宿主机原生跑 RMUA-Linux-Shipping 所需的 ROS 运行库」到目标目录。
# 原理:UE 二进制链接了 ROS1(libroscpp 等),但宿主是 Ubuntu 22.04 没装 Noetic;
#       glibc 向后兼容(宿主 2.35 > 容器 focal 2.31),故从容器抽出来的库能在宿主直接用。
# 用法: ./scripts/extract_roslibs.sh [目标目录(默认 ~/RMUA/rmua_roslibs)]
set -e
DEST="${1:-$HOME/RMUA/rmua_roslibs}"
IMAGE="${IMAGE:-simulator01}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_DIR/Build/LinuxNoEditor/RMUA/Binaries/Linux/RMUA-Linux-Shipping"

mkdir -p "$DEST"

echo "[1/3] 抽取 ROS 主体库 (/opt/ros/noetic/lib) ..."
CID=$(docker create "$IMAGE")
docker cp "$CID":/opt/ros/noetic/lib/. "$DEST"/ >/dev/null

echo "[2/3] 抽取 boost 1.71 / console_bridge ..."
for f in libboost_chrono.so.1.71.0 libboost_filesystem.so.1.71.0 libboost_regex.so.1.71.0 \
         libboost_thread.so.1.71.0 libboost_system.so.1.71.0 libboost_date_time.so.1.71.0 \
         libconsole_bridge.so.0.4; do
  docker cp "$CID":/usr/lib/x86_64-linux-gnu/$f "$DEST"/ >/dev/null 2>&1 || echo "    跳过(找不到): $f"
done
docker rm -f "$CID" >/dev/null

echo "[3/3] 抽取带符号链接的库 (log4cxx / ICU66 / apr) —— tar -ch 解引用符号链接 ..."
docker run --rm --entrypoint bash "$IMAGE" -c \
  'cd /usr/lib/x86_64-linux-gnu && tar -chf - liblog4cxx.so* libicui18n.so.66* libicuuc.so.66* \
       libicudata.so.66* libapr-1.so.0* libaprutil-1.so.0*' \
  | tar -xf - -C "$DEST"

echo "完成,共 $(ls "$DEST" | wc -l) 项 → $DEST"

# 依赖闭合校验
if [ -x "$BIN" ]; then
  miss=$(LD_LIBRARY_PATH="$DEST" ldd "$BIN" 2>/dev/null | grep "not found" || true)
  if [ -z "$miss" ]; then echo "✅ ldd 校验通过:0 not found"; else echo "❌ 仍缺失:"; echo "$miss"; exit 1; fi
else
  echo "(未找到二进制 $BIN,跳过 ldd 校验)"
fi
