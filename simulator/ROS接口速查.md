# ROS 接口速查（RMUA 2026 模拟器）

模拟器以 **ROS1 Noetic** 对外交互，所有话题/服务都在 `/airsim_node/` 下。

> ⚠️ **宿主机装的是 ROS Humble，与本模拟器的 Noetic 冲突**——直接在宿主跑 `rosservice`/`rostopic` 会报 `ImportError: cannot import name 'Log' from 'rosgraph_msgs.msg'`。**所有 ROS 命令一律在 Noetic 容器里跑**，用本仓库的包装脚本：
> ```bash
> ./scripts/ros.sh <ros 命令...>      # 连宿主 localhost:11311,自动 source Noetic + airsim_ros
> ```
> 例：`./scripts/ros.sh rostopic list`、`./scripts/ros.sh rosservice call /airsim_node/drone_1/takeoff "{waitOnLastTask: true}"`

坐标系：世界系/机体系均为 **NED**。机体 **x=前、y=右、z=下**（上升=`-vz`）。世界系原点在 1 号标识点。

---

## 一、通用调试

| 目的 | 命令（均经 `./scripts/ros.sh`） |
|---|---|
| 列全部话题 | `./scripts/ros.sh rostopic list` |
| 列全部服务 | `./scripts/ros.sh rosservice list` |
| 看话题类型 | `./scripts/ros.sh rostopic type /airsim_node/drone_1/imu/imu` |
| 看话题发布者/订阅者(**md5 不匹配时订阅者为 0**) | `./scripts/ros.sh rostopic info /airsim_node/drone_1/vel_body_cmd` |
| 看服务类型/参数 | `./scripts/ros.sh rosservice info /airsim_node/drone_1/takeoff` |
| 看话题频率 | `./scripts/ros.sh rostopic hz /airsim_node/drone_1/imu/imu` |
| 看一条数据 | `./scripts/ros.sh rostopic echo -n1 /airsim_node/drone_1/debug/pose_gt` |
| 录包 | `./scripts/ros.sh rosbag record -O /tmp/run.bag /airsim_node/drone_1/imu/imu /airsim_node/drone_1/vel_body_cmd` |
| 回放 | `./scripts/ros.sh rosbag play /tmp/run.bag` |

---

## 二、查看无人机状态（订阅话题）

| 内容 | 话题 | 类型（`rostopic type` 核对） | 频率 |
|---|---|---|---|
| 位姿真值 | `/airsim_node/drone_1/debug/pose_gt` | `geometry_msgs/PoseStamped`* | — |
| IMU | `/airsim_node/drone_1/imu/imu` | `sensor_msgs/Imu` | 100 Hz |
| GPS（±0.1m 位置/±0.2rad 姿态误差） | `/airsim_node/drone_1/gps` | `airsim_ros/GPSYaw`(lat/lon/alt/yaw) | 10 Hz |
| 激光雷达 | `/airsim_node/drone_1/lidar` | `sensor_msgs/PointCloud2` | 10 Hz,20000 点/帧 |
| 风速（世界系真值 m/s） | `/airsim_node/drone_1/debug/wind` | `geometry_msgs/TwistStamped`* | 50 Hz |
| 四电机 PWM 反馈 | `/airsim_node/drone_1/debug/rotor_pwm` | `airsim_ros/RotorPWM` | — |
| 前视双目 | `/airsim_node/drone_1/front_left/Scene`、`/front_right/Scene` | `sensor_msgs/Image` | 20 Hz,960×720@60° |
| 后视双目 | `/airsim_node/drone_1/back_left/Scene`、`/back_right/Scene` | `sensor_msgs/Image` | 20 Hz |
| 起始位姿（准备阶段） | `/airsim_node/initial_pose` | — | 10 Hz |
| 当前路径终点 | `/airsim_node/end_goal` | — | 10 Hz |

> 带 `*` 为推断，**以 `./scripts/ros.sh rostopic type <话题>` 输出为准**。
> 每个相机还另有 `/Scene/camera_info`（内参）和 `/Scene/mouse_click` 子话题。

常用：
```bash
./scripts/ros.sh rostopic echo -n1 /airsim_node/drone_1/debug/pose_gt   # 当前位姿真值
./scripts/ros.sh rostopic hz   /airsim_node/drone_1/imu/imu              # IMU 频率(应≈100)
./scripts/ros.sh rostopic echo /airsim_node/drone_1/debug/rotor_pwm      # 四电机实时 PWM
rqt_image_view                                                          # 看相机(需图形)
rviz -d ~/RMUA/simulator/rmua_full.rviz                            # 雷达点云+相机
```

---

## 三、控制指令

### 1) 速度控制（VEL）— 话题 `/airsim_node/drone_1/vel_body_cmd`，类型 `airsim_ros/VelCmd`

| 字段 | 含义 |
|---|---|
| `header.stamp` | **必须用仿真时钟（IMU 的 stamp）**，墙上时钟会被当过期丢弃 |
| `vx`/`vy`/`vz` | 机体 x/y/z 速度 m/s（NED，上升=`-vz`） |
| `yawRate` | 偏航角速度 rad/s |
| `va` | 加速度上限 0–8 m/s²；`0`=不限加速度（瞬时）；默认 4 |
| `stop` | `1`=急停悬停（忽略其余），`0`=正常 |

```bash
# ⚠️ rostopic pub 的 stamp 是墙上时钟,模拟器大概率丢弃 → 不会真动。下面仅作消息结构测试:
# 要让无人机真动,得用 IMU 时间戳盖戳(在算法节点里订阅 imu/imu 取 stamp)。
./scripts/ros.sh rostopic pub -1 /airsim_node/drone_1/vel_body_cmd airsim_ros/VelCmd \
  "{header: {frame_id: 'drone_1'}, vx: 2.0, vy: 0.0, vz: 0.0, yawRate: 0.0, va: 4, stop: 0}"
```

### 2) PWM 控制 — 话题 `/airsim_node/drone_1/rotor_pwm_cmd`，类型 `airsim_ros/RotorPWM`（`rotorPWM0..3`）

电机下标顺序（命令与反馈一致）：**0=右前，1=左后，2=左前，3=右后**

```bash
./scripts/ros.sh rostopic pub -1 /airsim_node/drone_1/rotor_pwm_cmd airsim_ros/RotorPWM \
  "{header: {frame_id: 'drone_1'}, rotorPWM0: 0.5, rotorPWM1: 0.5, rotorPWM2: 0.5, rotorPWM3: 0.5}"
```

> ⚠️ **VEL 与 PWM 不可在同一场混用**：规则手册规定"控制接口类型以模拟器首次接收到的信号类型为准"——先发哪种，整场锁定哪种，另一种被静默忽略。

---

## 四、服务

```bash
# 起飞(已验证可调用)
./scripts/ros.sh rosservice call /airsim_node/drone_1/takeoff "{waitOnLastTask: true}"
# 降落
./scripts/ros.sh rosservice call /airsim_node/drone_1/land "{waitOnLastTask: true}"
# 重置当前局
./scripts/ros.sh rosservice call /airsim_node/reset
```

| 服务 | 类型 | 说明 |
|---|---|---|
| `/airsim_node/drone_1/takeoff` | `airsim_ros/Takeoff` | `bool waitOnLastTask`→`bool success` |
| `/airsim_node/drone_1/land` | `airsim_ros/Land` | 同上 |
| `/airsim_node/reset` | `airsim_ros/Reset` | 空请求→`bool success`，重开一局 |
| `/airsim_node/meter_report` | `airsim_ros/MeterReport` | 工厂巡检上报：`index=0`=中央枢纽**前**工厂、`1`=**后**工厂；`value`=仪表读数(0–50)。**上报错误=任务失败**。该 srv 不在脚手架 `airsim_ros` 内（模拟器侧定义），`rosservice call` 需先拿到 `MeterReport.srv`；可用 `rosservice info` 查看 |
| `/airsim_node/any_report` | `airsim_ros/AnyReport` | 通用上报，同样不在脚手架内 |
| `/airsim_node/drone_1/trigger_port` | `airsim_ros/TriggerPort` | **测试接口，正式比赛勿用**（`.srv` 内自带此注释）。参数：`port enter uselessbelow age height weight uselessabove` |
| `/airsim_node/drone_1/debug_sphere` | `airsim_ros/DebugSphere` | 调试用 |

---

## 五、注意事项

1. **ROS 命令在容器里跑**（`./scripts/ros.sh`），宿主 Humble 与 Noetic 冲突。
2. **时间戳用 IMU 的 stamp**，不是墙上时钟（差约 20s，会被当过期丢弃）；`rostopic pub` 手动发 vel 多半不动即此因——得在算法节点里用 IMU 时间戳盖戳。
3. **`airsim_ros/VelCmd` 是 6 字段版**；脚手架自带的旧版是 `geometry_msgs/Twist twist` → md5 不匹配 → 发布者看似连上但无人机不动（`rostopic info` 看 subscriber 数为 0 可确认）。
4. **指令频率上限 100 Hz**（规则 §2.3）；保持发布频率 ≤100 Hz。
5. **VEL/PWM 首发锁定**，别混用。
6. **开发前把 `Build/LinuxNoEditor/RMUA/Content/Configs/GameConfig.json` 的 `IgnoreAllHitCollision`/`IgnoreOverTime` 设 `true` 并重启 UE**，否则超时/撞击结束本局、无人机随后无视所有指令（reset 后能动、悬停十几秒后卡死即此现象）。
7. 工厂内 **GPS 读 0**，巡检靠视觉/雷达定位。
