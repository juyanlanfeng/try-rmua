#!/bin/bash
# 渲染模式(UE 大窗口)+ X11 转发,通过 Docker 运行 simulator01
# 用法: ./run_docker_simulator_render.sh [seed]    (默认 seed=123)
# 前提: 原生 X11 桌面(本机 DISPLAY=:0)、已装 NVIDIA 驱动 + nvidia-container-toolkit
#
# ⚠️ 已知限制(本机 RTX 5070 Laptop = Intel+NVIDIA 混合显卡):
#   容器内 Vulkan 无法向宿主桌面 present,UE 会在 swapchain 阶段崩溃
#   (vkGetPhysicalDeviceSurfacePresentModesKHR -> VkResult=-13 -> SIGSEGV)。
#   已证实与 UE 无关(vkcube 同样崩),且 --device /dev/dri / 组权限 / Optimus
#   offload 环境变量均无效。此脚本仅在「桌面由 NVIDIA 独显单独驱动、非混合」的
#   机器上可用。本机请改用离屏: ./run_docker_simulator.sh <seed> + rviz/rqt。
SEED="${1:-123}"

# 放行本地容器访问 X 显示
xhost +local: >/dev/null 2>&1

docker run -it --rm --name sim01_render \
  --net host \
  --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all \
  -e DISPLAY="${DISPLAY:-:0}" \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  --entrypoint /bin/bash \
  simulator01 -c "source /opt/ros/noetic/setup.bash && (roscore &) && sleep 3 && exec /usr/local/LinuxNoEditor/RMUA.sh seed ${SEED}"
