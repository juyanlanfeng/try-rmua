#!/bin/bash
# 在 Noetic 容器里跑 ROS CLI(rosservice/rostopic/rosbag/...),连宿主 localhost:11311。
# 必要性:宿主机装的是 ROS Humble,与本模拟器的 Noetic 接口冲突(直接 rosservice 会
#   ImportError: cannot import name 'Log' from 'rosgraph_msgs.msg')。故 ROS 命令一律在容器里跑。
# 用法:
#   ./scripts/ros.sh rosservice call /airsim_node/drone_1/takeoff "{waitOnLastTask: true}"
#   ./scripts/ros.sh rostopic echo -n1 /airsim_node/drone_1/debug/pose_gt
#   ./scripts/ros.sh rostopic hz /airsim_node/drone_1/imu/imu
#   ./scripts/ros.sh rosbag record -O /tmp/run.bag /airsim_node/drone_1/imu/imu
# 环境变量:IMAGE(默认 simulator01)、WS(默认 ~/IntelligentUAVChampionshipBase/basic_dev)
IMAGE="${IMAGE:-simulator01}"
WS="${WS:-$HOME/IntelligentUAVChampionshipBase/basic_dev}"
[ $# -eq 0 ] && { echo "用法: $0 <ros 命令...>  (例: $0 rostopic list)"; exit 1; }
[ -d "$WS" ] || WS=""   # 没有工作区就不挂(只跑 rosservice/rostopic 标准类型也够)
MNT=""; [ -n "$WS" ] && MNT="-v $WS:/ws"
exec docker run --rm -i --net host $MNT \
  --entrypoint bash "$IMAGE" -c \
  'source /opt/ros/noetic/setup.bash; [ -f /ws/devel/setup.bash ] && source /ws/devel/setup.bash; exec "$@"' \
  _ "$@"
