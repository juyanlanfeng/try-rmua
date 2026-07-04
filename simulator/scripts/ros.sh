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

# 默认使用 simulator01 镜像;可用 IMAGE=xxx 覆盖
IMAGE="${IMAGE:-simulator01}"

# 默认挂载的算法工作区路径;可用 WS=xxx 覆盖(用于让容器看到 airsim_ros 自定义 msg)
WS="${WS:-$HOME/IntelligentUAVChampionshipBase/basic_dev}"

# 没传任何 ROS 命令就提示用法并退出
[ $# -eq 0 ] && { echo "用法: $0 <ros 命令...>  (例: $0 rostopic list)"; exit 1; }

# 若 WS 目录不存在则置空,避免 docker -v 挂载报错(只跑标准类型 rosservice/rostopic 也够)
[ -d "$WS" ] || WS=""

# 组装挂载参数:有 WS 就 -v 挂载到 /ws,没有就空串
MNT=""; [ -n "$WS" ] && MNT="-v $WS:/ws"

# 执行一次性容器:
#   --rm            跑完即删,不留垃圾容器
#   -i              保持 stdin 开(交互式命令如 rostopic echo 需要)
#   --net host      共享宿主网络,直连 localhost:11311 的 roscore
#   $MNT            可选挂载算法工作区(让容器能 source airsim_ros 的自定义 msg)
#   --entrypoint bash 覆盖镜像默认 entrypoint,改用 bash 跑内联脚本
#   -c '...'        内联脚本:先 source noetic,再尝试 source 工作区 devel,最后 exec 用户命令
#   _ "$@"          _ 占位让 "$@" 从 1 开始正确展开为用户的 ROS 命令及参数
exec docker run --rm -i --net host $MNT \
  --entrypoint bash "$IMAGE" -c \
  'source /opt/ros/noetic/setup.bash; [ -f /ws/devel/setup.bash ] && source /ws/devel/setup.bash; exec "$@"' \
  _ "$@"
