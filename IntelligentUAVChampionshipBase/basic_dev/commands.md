# ROS1 常用指令速查

## 编译与运行

```bash
# 编译工作空间（首次或全量编译）
catkin_make

# 只编译指定包（更快）
catkin_make --only-pkg-with-deps basic_dev

# Source 环境
source devel/setup.bash

# 启动 ROS Master（一切通信的前提）
roscore

# 运行节点
rosrun <包名> <可执行文件名>
rosrun basic_dev basic_dev

# 启动 launch 文件
roslaunch <包名> <xxx.launch>
roslaunch controller controller_test.launch
```

## 话题相关

```bash
# 列出所有话题
rostopic list
rostopic list -v          # 详细模式，显示类型

# 查看话题数据类型
rostopic type /话题名

# 查看话题详细信息（类型、发布者、订阅者）
rostopic info /话题名

# 监听话题数据
rostopic echo /话题名
rostopic echo /话题名 -n 1   # 只接收一条

# 查看话题发布频率
rostopic hz /话题名

# 向话题发送消息
rostopic pub /话题名 消息类型 "消息内容"
rostopic pub /airsim_node/drone_1/vel_body_cmd airsim_ros/VelCmd "..."
# 按 Tab 键两次自动生成消息模板
# -1: 只发一次
# -r 10: 以10Hz频率持续发送
```

## 消息相关

```bash
# 查看消息类型结构
rosmsg show <消息类型>
rosmsg show airsim_ros/VelCmd
rosmsg show geometry_msgs/PoseStamped

# 列出包内所有消息
rosmsg package <包名>
```

## 服务相关

```bash
# 列出所有服务
rosservice list

# 查看服务类型
rosservice type /服务名

# 调用服务
rosservice call /服务名 "参数"
rosservice call /airsim_node/drone_1/takeoff "waitOnLastTask: 1"
```

## 节点相关

```bash
# 列出所有节点
rosnode list

# 查看节点信息
rosnode info /节点名
```

## 文件系统相关

```bash
# 查找包路径
rospack find <包名>

# 列出包内所有可执行文件
rosrun --list <包名>
```

## rqt 可视化工具

```bash
# 话题/节点关系图
rqt_graph

# 消息可视化
rqt_plot /话题名/字段

# 控制台
rqt_console
```

## bag 数据录制与回放

```bash
# 录制
rosbag record -a                    # 录制所有话题
rosbag record /话题1 /话题2         # 录制指定话题

# 回放
rosbag play xxx.bag
```

## 本项目常用话题

| 话题 | 类型 | 用途 |
|------|------|------|
| `/airsim_node/drone_1/debug/pose_gt` | PoseStamped | 地面真值（赛道一） |
| `/airsim_node/drone_1/gps` | PoseStamped | GPS数据（赛道一） |
| `/airsim_node/drone_1/imu/imu` | Imu | IMU数据 |
| `/airsim_node/drone_1/lidar` | PointCloud2 | 激光雷达 |
| `/airsim_node/drone_1/front_left/Scene` | Image | 前左相机 |
| `/airsim_node/drone_1/front_right/Scene` | Image | 前右相机 |
| `/airsim_node/drone_1/vel_body_cmd` | VelCmd | 速度控制指令 |
| `/airsim_node/drone_1/rotor_pwm_cmd` | RotorPWM | 电机PWM指令 |
| `/airsim_node/initial_pose` | PoseStamped | 起始位姿 |
| `/airsim_node/end_goal` | PoseStamped | 终点位置 |
| `/airsim_node/drone_1/takeoff` | Takeoff(服务) | 起飞 |
| `/airsim_node/drone_1/land` | Takeoff(服务) | 降落 |
| `/airsim_node/reset` | Reset(服务) | 重置 |
