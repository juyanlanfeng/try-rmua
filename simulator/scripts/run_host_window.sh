#!/bin/bash
# run_host_window.sh —— 在宿主机【原生】启动 UE 渲染大窗口。
#
# 为什么要在宿主机原生跑 UE(而不是放容器里):
#   本机是 Intel+NVIDIA 混合显卡(Optimus)。容器内 Vulkan 无法把渲染结果 present
#   到宿主桌面(在 swapchain 阶段 vkGetPhysicalDeviceSurfacePresentModesKHR 返回
#   VkResult=-13 → SIGSEGV 崩溃)。所以想要"UE 大窗口"只能让 UE 进程直接跑在宿主,
#   由宿主 X server 负责呈现。
#
# 宿主没装 ROS Noetic(Ubuntu22.04 自带的是 Humble,与 Noetic 冲突),而 UE 二进制
# 链接了 libroscpp 等 ROS1 库。解法:用 scripts/extract_roslibs.sh 从 simulator01
# 镜像里把 ROS1 运行库抽到 ~/RMUA/rmua_roslibs,本脚本用 LD_LIBRARY_PATH 指过去即可。
#
# 前置(按顺序):
#   ① scripts/run_roscore.sh     —— 已在容器里起了 roscore(监听宿主 localhost:11311)
#   ② scripts/extract_roslibs.sh —— 已把 ROS 库抽到 ~/RMUA/rmua_roslibs(一次性,需重跑则库被重建)
#   ③ settings.json 由本脚本自动拷到 ~/Documents/AirSim/(UE 原生模式从这读配置)
#
# 用法: ./scripts/run_host_window.sh [seed(默认 123)]
# 注意:同一时刻只能跑一个 UE 实例!两个会抢 GPU 触发 VK_ERROR_DEVICE_LOST。

set -e # 任一命令失败立刻退出,不在坏状态下启动 UE

SEED="${1:-123}" # 第一个参数=随机种子(选赛道);未传则默认 123
ROSLIBS="${ROSLIBS:-$HOME/RMUA/rmua_roslibs}" # ROS1 库目录;可用环境变量 ROSLIBS 覆盖
# 定位"本脚本所在目录的上一级"=仓库根;这样从任意 cwd 运行都能找到 Build/
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$REPO_DIR/Build/LinuxNoEditor" # UE 二进制所在目录(RMUA.sh 也在这)

# —— 单实例保护 ——
# pgrep -f 按完整命令行匹配正在跑的 UE 进程;若已有实例,再起一个会抢 GPU 崩溃
if pgrep -f "RMUA-Linux-Shipping RMUA seed" >/dev/null; then
  echo "❌ 已有 UE 实例在运行。先关闭:"
  echo "     pkill -f 'RMUA-Linux-Shipping RMUA seed'"
  exit 1
fi

# —— 依赖检查 ——
# ① ROS 库目录必须存在,否则 UE 因找不到 libroscpp 等起不来
[ -d "$ROSLIBS" ] || { echo "❌ 缺 $ROSLIBS,先跑 scripts/extract_roslibs.sh"; exit 1; }
# ② roscore 必须在监听 11311(ss -tlnp 列本地监听端口,grep :11311);否则 UE 的 ROS 节点连不上 master
ss -tlnp 2>/dev/null | grep -q ':11311' || { echo "❌ roscore 未在 11311,先跑 scripts/run_roscore.sh"; exit 1; }

# —— 放置 AirSim 配置 ——
# UE 原生模式从 ~/Documents/AirSim/settings.json 读车辆/传感器/相机配置
mkdir -p "$HOME/Documents/AirSim"
cp -f "$REPO_DIR/settings.json" "$HOME/Documents/AirSim/"   # 每次用仓库里的最新版覆盖,保证配置一致

cd "$BIN_DIR"                                    # 切到 UE 二进制目录(下面用相对路径 ./RMUA/... 调它)
echo "启动 UE 窗口:seed=$SEED (Ctrl+C 关闭)"
# exec env ... :用 env 注入环境变量后,把当前 shell 进程【替换】成 UE(不留多余 shell 进程;Ctrl+C 直达 UE)
exec env \
  LD_LIBRARY_PATH="$ROSLIBS" \                   # 让动态链接器能找到 ROS1 库(libroscpp/librospy 等)
  DISPLAY="${DISPLAY:-:0}" \                     # 渲染输出到宿主 X 显示(默认 :0)
  ROS_MASTER_URI=http://localhost:11311 \        # 告诉 UE 内的 ROS 节点:master 在宿主 11311
  ./RMUA/Binaries/Linux/RMUA-Linux-Shipping RMUA seed "$SEED"
  # ↑ 直调 UE 二进制。参数含义:
  #   第一个 "RMUA"        = UE 项目名(打包二进制需用它定位项目)
  #   "seed" "$SEED"       = 项目自定义子命令,设随机种子选赛道配置
  #   (RMUA.sh 只是对这一行的 wrapper:readlink 定位 + chmod + 转发 "$@")
