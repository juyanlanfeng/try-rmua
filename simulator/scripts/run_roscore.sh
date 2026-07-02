#!/bin/bash
# 启动一个容器内的 roscore,借助 --net host 监听在宿主的 localhost:11311。
# 宿主原生跑的 UE 二进制、以及可视化容器,都连这个 master。
# 这样宿主就不必原生安装 ROS1 Noetic。
set -e
IMAGE="${IMAGE:-simulator01}"

docker rm -f roscore_host >/dev/null 2>&1 || true
docker run -d --rm --net host --name roscore_host --entrypoint bash "$IMAGE" \
  -lc "source /opt/ros/noetic/setup.bash && roscore" >/dev/null

echo "等待 roscore 监听 11311 ..."
for i in $(seq 1 15); do
  if ss -tlnp 2>/dev/null | grep -q ':11311'; then
    echo "✅ roscore 已就绪:localhost:11311"; exit 0
  fi
  sleep 1
done
echo "❌ roscore 未起来。排查:docker logs roscore_host"; exit 1
