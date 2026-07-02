# try-rmua

RMUA 2026 自主无人机竞速模拟器 + 算法工作区(个人整理版)。基于 UE4 + AirSim,ROS1 Noetic 交互。

## 目录结构

| 目录 | 说明 | 入库? |
|---|---|---|
| `simulator/` | 模拟器配置(启动脚本、Docker、AirSim `settings.json`、`GameConfig`、文档)。`Build/` 是下载的 2G UE 二进制,**未入库** | 源码入库,`Build/` 忽略 |
| `IntelligentUAVChampionshipBase/` | 官方脚手架 + 自研算法(catkin 工作区在 `basic_dev/src/`:airsim_ros、controller、odometry、imu_gps_odometry…) | 源码入库,`build/devel/install` 忽略 |
| `rmua_roslibs/` | 从 `simulator01` 镜像抽取的 ROS1 Noetic 运行库(宿主原生跑 UE 用) | **忽略**,由 `simulator/scripts/extract_roslibs.sh` 重建 |

## 快速开始

- 模拟器怎么跑、ROS 接口、避坑要点:见 `simulator/AGENTS.md`、`simulator/ROS接口速查.md`。
- 首次需先下载 `simulator_12.0.0.5.zip` 解压出 `simulator/Build/`(见 `simulator/README.md`)。
- 宿主原生跑 UE 还需:`simulator/scripts/extract_roslibs.sh` 抽库 + `simulator/scripts/run_roscore.sh` 起 roscore + `simulator/scripts/run_host_window.sh <seed>`。

## 环境

- 宿主:Ubuntu 22.04(混合显卡 Intel+NVIDIA Optimus)。
- 模拟器二进制链接 ROS1 Noetic;宿主若装的是 Humble,ROS CLI 需在 `simulator01` 容器里跑(见 `simulator/scripts/ros.sh`)。
