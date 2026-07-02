#!/bin/bash
# 打开 rviz 看传感器:激光雷达点云 + 4 路相机(Image 显示)。
# 走 --net host 连宿主 localhost:11311;软件渲染(LIBGL_ALWAYS_SOFTWARE=1)不与 UE 抢独显。
# 前置:simulator01-viz 镜像已构建;roscore 已起;有图形桌面(DISPLAY)。
set -e
IMAGE="${IMAGE:-simulator01-viz}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISP="${DISPLAY:-:0}"

# 放开本地 X11 访问(容器作为本地客户端连宿主 X)
DISPLAY="$DISP" xhost +local: >/dev/null 2>&1 || true

docker rm -f viz_all >/dev/null 2>&1 || true
docker run -d --rm --net host \
  -e DISPLAY="$DISP" -e ROS_MASTER_URI=http://localhost:11311 \
  -e LIBGL_ALWAYS_SOFTWARE=1 -e QT_X11_NO_MITSHM=1 \
  -v /tmp/.X11-unix:/tmp/.X11-unix \
  -v "$REPO_DIR/rmua_full.rviz":/tmp/rmua_full.rviz \
  --name viz_all --entrypoint bash "$IMAGE" \
  -c "source /opt/ros/noetic/setup.bash && exec rviz -d /tmp/rmua_full.rviz" >/dev/null

echo "✅ rviz 已启动(容器 viz_all)。窗口内含:雷达点云 + 4 路相机面板。"
echo "   相机面板若堆叠,拖开标签即可;关闭:docker rm -f viz_all"
