# 在 Ubuntu 22.04 上用 Docker 部署 RMUA2026 无人机竞速模拟器

> 适用对象：已安装 **Win11 + Ubuntu 22.04 双系统**、显卡为 **RTX 5070（Blackwell）** 的同学。
> 目标项目：`RoboMaster/IntelligentUAVChampionshipSimulator`（分支 `RMUA2026-01`）。

---

## 0. 方案说明（先读这段，理解为什么这么做）

项目官方测试环境是 **Ubuntu 20.04 + ROS Noetic**。但我们不直接在 20.04 上装，而是采用：

> **宿主机 Ubuntu 22.04（原生）＋ 项目自带的 Docker 容器（容器内是 20.04 + ROS Noetic）**

原因有三，缺一不可：

1. **5070 驱动在 20.04 上很难装。** Blackwell（50 系）必须用 ≥580 的 **open 内核模块**驱动，20.04 系统太老、笔记本卡还有 Optimus，常出现"装上了但识别不到 GPU、回退软件渲染"。22.04 上装 5070 驱动顺畅得多。
2. **ROS Noetic 只支持 20.04。** 所以 Noetic 放进 Docker 容器里跑（容器是 20.04），宿主用 22.04，两不耽误。
3. **关键：原生 Linux 下，Docker 容器能拿到真正的 N 卡 Vulkan。** `nvidia-container-toolkit` 会把宿主的 NVIDIA 图形驱动注入容器，容器里的虚幻引擎（UE）就能用 GPU 离屏渲染相机画面。**这一点 WSL2 给不了**（WSL2 里只有软件渲染 llvmpipe），所以必须原生 Linux。

整体链路：

```
Windows 11 ──双系统──► Ubuntu 22.04（宿主）
                          ├─ NVIDIA 580-open 驱动（驱动 5070）
                          ├─ Docker + nvidia-container-toolkit（透传 GPU）
                          └─ 容器 simulator01（Ubuntu 20.04 + ROS Noetic + UE 模拟器）
                                  └─ 离屏渲染相机 → 发 ROS topic → 你的算法订阅 + rviz/rqt 看
```

> ⚠️ 你的 5070 只有 **8GB 显存**，官方用的是 3090Ti（24GB）。4 路相机一起渲染容易吃紧/掉帧，**建议后面按第 8 节关掉不需要的相机**。

全程命令默认在 Ubuntu 22.04 下、普通用户终端执行；需要 root 的地方都写了 `sudo`。

---

## 1. 系统准备

```bash
# 更新系统
sudo apt update && sudo apt upgrade -y

# 基础编译/工具依赖（装驱动、解压、拉代码都要用）
sudo apt install -y build-essential dkms gcc make pkg-config \
                    curl wget git unzip ca-certificates gnupg lsb-release
```

> 国内建议把 apt 源换成中科大/清华镜像提速（可选）。系统设置 → 软件和更新 → 下载服务器 → 选 `mirrors.ustc.edu.cn`。

---

## 2. 安装 RTX 5070 驱动（580-open）

**核心要点：Blackwell 必须用 `nvidia-driver-580-open`（open 内核模块版）。装成普通 proprietary 版会识别不到卡、黑屏。**

### 2.1 清理旧驱动（如果之前装过没成功）

```bash
sudo apt purge -y '^nvidia-.*' 'libnvidia-.*' 2>/dev/null
sudo apt autoremove -y
```

### 2.2 添加驱动源并安装

```bash
# 加 graphics-drivers PPA，确保有足够新的 580 驱动
sudo add-apt-repository ppa:graphics-drivers/ppa -y
sudo apt update

# 查看系统推荐（确认能看到 nvidia-driver-580 / -open）
ubuntu-drivers devices

# 安装 open 模块版（Blackwell 必须 open）
sudo apt install -y nvidia-driver-580-open
```

> 如果 `ubuntu-drivers devices` 列不出 580，说明 PPA 没生效或网络问题（PPA 在 launchpad，可能需要第 5 节的代理）。

### 2.3 Secure Boot 处理（重要）

如果你的 BIOS 开了 **Secure Boot**，安装时 apt 会让你设一个 MOK 密码。**重启时会进入蓝色的 MOK 管理界面 → 选 Enroll MOK → Continue → 输入刚才的密码**，否则内核模块加载不了，`nvidia-smi` 会报错。

实在搞不定就进 BIOS 把 Secure Boot 关掉，最省事。

### 2.4 重启并验证

```bash
sudo reboot
# 重启后：
nvidia-smi
```

能列出 `NVIDIA GeForce RTX 5070` 就成功了。记下 `Driver Version` 和 `CUDA Version`。

### 2.5 笔记本 Optimus 说明

5070 笔记本是混合显卡（核显 + 独显）。装好 `nvidia-driver-580-open` 会自带 `nvidia-prime`。默认 `on-demand` 模式即可——**Docker 离屏渲染不需要独显驱动桌面，只要驱动加载、`nvidia-smi` 能看到卡就行**。查看/切换模式：

```bash
prime-select query          # 一般是 on-demand
# 如需强制独显（更稳但更耗电）：sudo prime-select nvidia && sudo reboot
```

---

## 3. 安装 Docker Engine

```bash
# 卸载可能存在的旧版
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null

# 添加 Docker 官方源（国内可把 download.docker.com 换成 mirrors.ustc.edu.cn/docker-ce）
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
                    docker-buildx-plugin docker-compose-plugin

# 把当前用户加入 docker 组，免 sudo（重新登录或 newgrp 生效）
sudo usermod -aG docker $USER
newgrp docker

# 验证
docker run --rm hello-world
```

---

## 4. 安装 nvidia-container-toolkit（让容器用上 GPU）

```bash
# 添加源
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit

# 配置 docker 运行时并重启
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

> `nvidia.github.io` 在国内可能要走第 5 节的代理才能下到 key/list。

### 4.1 验证 GPU 计算透传

```bash
docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
```

容器里能看到 5070 即 OK。

### 4.2 ⭐ 验证容器内的 Vulkan 渲染（最关键的一步）

这一步直接决定模拟器能不能渲染。**注意必须加 `NVIDIA_DRIVER_CAPABILITIES=all`（或至少含 `graphics`），否则容器拿不到图形驱动、Vulkan 会退回 llvmpipe 软件渲染。**

```bash
docker run --rm --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all ubuntu:20.04 \
  bash -c "apt update -qq && apt install -y -qq vulkan-tools >/dev/null 2>&1 && vulkaninfo | grep -i deviceName"
```

- 输出里出现 `NVIDIA GeForce RTX 5070 ...` → **成了**，UE 能用 GPU 渲染，整条路通了。
- 如果只有 `llvmpipe` → 八成是漏了 `NVIDIA_DRIVER_CAPABILITIES=all`，或 toolkit 没配好，回头查第 4 节。

---

## 5. 配置代理（给 git / docker pull / nvidia 源用）

国内访问 GitHub、`docker.io`、`nvidia.github.io` 需要代理；而 **apt（用国内镜像）和模拟器 zip（在阿里云）不需要代理**。所以代理只给少数几个出口配上即可。

### 5.1 Linux 代理客户端（v2rayN 是 Windows 程序，Linux 用不了）

Linux 上推荐 **v2rayA**（带网页 UI，简单）：

```bash
# 添加 v2rayA 源（若此源本身也被墙，见下方"引导上网"）
wget -qO - https://apt.v2raya.org/key/public-key.asc | \
  sudo tee /usr/share/keyrings/v2raya.asc >/dev/null
echo "deb [signed-by=/usr/share/keyrings/v2raya.asc] https://apt.v2raya.org/ v2raya main" | \
  sudo tee /etc/apt/sources.list.d/v2raya.list
sudo apt update
sudo apt install -y v2raya xray
sudo systemctl enable --now v2raya
```

然后浏览器打开 `http://127.0.0.1:2017` → 导入你的节点 → 启动。在 v2rayA 的「设置」里能看到本地监听端口，**默认 SOCKS5 `20170` / HTTP `20171`**（下文按 HTTP `20171` 写，按你实际的改）。

> **引导上网（先有鸡才有蛋问题）**：如果连 `apt.v2raya.org` 都下不动，就在 Windows 那边（你已有可用代理）下载 v2rayA 和 xray 的 `.deb` 包，拷到 Ubuntu，`sudo dpkg -i *.deb` 离线安装；或临时用手机热点装一次。
>
> 替代品：`mihomo`(Clash 内核) / `nekoray` / `sing-box` 都行，原理一样——本地起一个 HTTP/SOCKS 代理端口。

### 5.2 给终端 / git 配代理

```bash
# 终端临时走代理（关掉终端就失效）
export https_proxy=http://127.0.0.1:20171
export http_proxy=http://127.0.0.1:20171

# git 全局走代理
git config --global http.proxy  http://127.0.0.1:20171
git config --global https.proxy http://127.0.0.1:20171
# 用完想取消： git config --global --unset http.proxy; git config --global --unset https.proxy
```

### 5.3 给 Docker 守护进程配代理（docker pull 拉基础镜像用）

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:20171"
Environment="HTTPS_PROXY=http://127.0.0.1:20171"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
sudo systemctl daemon-reload
sudo systemctl restart docker
```

### 5.4 给 docker build / 容器内进程配代理（构建时容器内 apt/curl 联网用）

编辑 `~/.docker/config.json`（没有就新建），让 build 和 run 的容器自动带上代理环境变量：

```json
{
  "proxies": {
    "default": {
      "httpProxy": "http://127.0.0.1:20171",
      "httpsProxy": "http://127.0.0.1:20171",
      "noProxy": "localhost,127.0.0.1"
    }
  }
}
```

> 注意：容器里的 `127.0.0.1` 指容器自己。要让容器用宿主的代理，配合 `--network host` 运行时 `127.0.0.1` 才指向宿主（项目脚本一般用 host 网络）；否则把代理地址换成宿主在 docker 网桥上的 IP（一般 `172.17.0.1`）。

---

## 6. 获取并构建模拟器

```bash
# 1) 克隆项目（指定 RMUA2026-01 分支）
git clone -b RMUA2026-01 https://github.com/RoboMaster/IntelligentUAVChampionshipSimulator.git
cd IntelligentUAVChampionshipSimulator

# 2) 下载模拟器本体（阿里云深圳 OSS，国内直连快，不用代理）
wget https://sz-rm-rmua-dispatch-prod.oss-cn-shenzhen.aliyuncs.com/b39a0194e982f0d987153c6016feb325/simulator_12.0.0.5.zip

# 3) 解压。解压后会出现 build/ 文件夹
unzip simulator_12.0.0.5.zip

# 4) 确认文件布局：build/ 要与 Dockerfile、run_docker_simulator.sh 等"同级"
#    （在仓库目录里直接解压就已经满足这个要求——build 和工程文件在同一层，不是把工程塞进 build 里）
ls
# 期望看到类似： build/  Dockerfile  run_docker_simulator.sh  settings.json  ...
```

### 6.1 构建镜像

```bash
docker build -t simulator01 .
```

> 构建会拉 ROS Noetic 等依赖，确保第 5 节代理已配好（尤其 `~/.docker/config.json`）。

### 6.2 检查/修正运行脚本的 GPU 参数（容易踩的坑）

打开 `run_docker_simulator.sh` 看里面的 `docker run`，**确认带了这两项**，没有就加上：

```
--gpus all  -e NVIDIA_DRIVER_CAPABILITIES=all
```

少了 `NVIDIA_DRIVER_CAPABILITIES=all`，容器里 UE 会退回软件渲染（跟 4.2 验证失败一个道理）。如果还想用第 7 节的图形界面/Unreal 窗口，再补上 X11 相关参数（见 7.3）。

### 6.3 运行模拟器

```bash
# 123 是随机种子，不同种子对应不同赛道配置，可改
./run_docker_simulator.sh 123
```

Docker 模式是**离屏运行**（不弹窗口，正常现象，见第 7 节）。

### 6.4 验证数据是否正常发出

另开一个终端，进容器看 ROS 主题：

```bash
docker ps                         # 找到容器名/ID
docker exec -it <容器名> bash
source /opt/ros/noetic/setup.bash
rostopic list                     # 应看到 /airsim_node/drone_1/... 一堆主题
rostopic hz /airsim_node/drone_1/imu/imu   # 看 IMU 在不在发
```

能看到主题并有数据，就说明模拟器跑起来了。

---

## 7. 可视化与开发

**"Docker 离屏" ≠ "看不到东西"。** GPU 照样在渲染相机画面，只是不弹 UE 的 3D 大窗口。你比赛真正要看的是**相机/雷达/位姿数据**，用 ROS 工具看即可。

### 7.1 可订阅的主要数据主题（来自 README）

| 用途 | 主题 |
|---|---|
| 前视相机（双目） | `/airsim_node/drone_1/front_left/Scene`、`.../front_right/Scene` |
| 后视相机（双目） | `/airsim_node/drone_1/back_left/Scene`、`.../back_right/Scene` |
| IMU | `/airsim_node/drone_1/imu/imu` |
| 雷达 | `/airsim_node/drone_1/lidar` |
| 位姿真值 | `/airsim_node/drone_1/debug/pose_gt` |
| GPS（含带误差姿态） | `/airsim_node/drone_1/gps` |
| 起点 / 终点 | `/airsim_node/initial_pose`、`/airsim_node/end_goal` |

发送指令：速度控制 `/airsim_node/drone_1/vel_body_cmd`、PWM 控制 `/airsim_node/drone_1/rotor_pwm_cmd`。

> 用 `rqt_topic`/`rviz` 时若提示缺数据类型（msg），参考官方开发样例里的 `airsim_ros` 包：`RoboMaster/IntelligentUAVChampionshipBase`（分支 RMUA2026）。

### 7.2 方案 A（推荐）：进容器跑 rviz / rqt_image_view + X11 转发

不用在宿主装 ROS。让容器的图形界面投到宿主桌面：

```bash
# 宿主机：允许本地容器访问 X 显示
xhost +local:root
```

确保模拟器容器启动时带了 X11 与 GPU 参数（在 `run_docker_simulator.sh` 的 `docker run` 里加，或单独再起一个共享网络的工具容器）：

```
--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all \
-e DISPLAY=$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix \
--network host
```

然后进容器开可视化：

```bash
docker exec -it <容器名> bash
source /opt/ros/noetic/setup.bash
rqt_image_view          # 选相机主题看画面
# 或
rviz                    # 加 PointCloud2 看雷达、加 Pose 看无人机位姿
```

### 7.3 方案 B：宿主机装 ROS Noetic（用 RoboStack）

22.04 不能原生装 Noetic，但可用 conda 系的 **RoboStack**：

```bash
# 装 miniforge/mambaforge 后：
mamba create -n ros_noetic ros-noetic-desktop -c robostack-staging -c conda-forge -y
mamba activate ros_noetic
```

让宿主 ROS 工具连容器的 ROS master（容器需用 `--network host` 运行）：

```bash
export ROS_MASTER_URI=http://localhost:11311
export ROS_IP=127.0.0.1
rqt_image_view
```

### 7.4 想要 Unreal 的 3D 大窗口（可选，非默认用法）

项目 Docker 默认只离屏。若一定要 UE 观察窗口：在容器里改用**渲染模式脚本** `run_simulator.sh`（而非 offscreen），并确保容器带了 7.2 的 X11 + `NVIDIA_DRIVER_CAPABILITIES=all` + `--gpus all`。原生 Linux + 真 N 卡 Vulkan 下窗口能投到桌面，但这属于自己改脚本，超出 README 默认支持范围，且更吃显存。

---

## 8. 降负载（8GB 显存必看）

你的卡显存小，4 路相机容易爆。**关掉不需要的相机能显著降显存、稳帧率**：

1. 编辑工程目录下的 `settings.json`，删掉不需要的相机配置项（比如只保留前视双目，删掉后视）。
2. **Docker 模式改了 settings.json 必须重新 `docker build`** 才生效（本机模式则直接重跑即可）。

调试相关（`模拟器路径/Build/LinuxNoEditor/RMUA/Content/Configs/GameConfig.json`）：

- `IgnoreAllHitCollision: true` → 撞击不结束比赛，方便调试。
- `IgnoreOverTime: true` → 超时不结束比赛。

> 时钟：模拟器时钟与本地有差异，**建议用 IMU 主题里的时间戳作为全局时钟**做程序设计。

---

## 9. 常见问题排查

| 现象 | 原因 / 解决 |
|---|---|
| `nvidia-smi` 宿主报错 / 找不到卡 | 驱动没装对：必须 `nvidia-driver-580-open`；Secure Boot 要 enroll MOK 或关掉；重启。 |
| 容器里 `nvidia-smi` 看不到卡 | nvidia-container-toolkit 没配：重跑 `sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker`；运行加 `--gpus all`。 |
| 容器里 `vulkaninfo` 只有 llvmpipe | 漏了 `-e NVIDIA_DRIVER_CAPABILITIES=all`（关键！），加上即可。 |
| UE 启动即崩 / 卡死 / 画面黑 | 多半显存不足（8GB）：按第 8 节关相机；确认 4.2 的 Vulkan 验证是通过的。 |
| `docker build` 拉不到基础镜像 / 卡住 | 代理没配：检查第 5.3、5.4 节；或给 docker 配国内镜像加速器。 |
| `git clone` 很慢/失败 | 第 5.2 节给 git 配代理。 |
| PCIe 速率异常 / 偶发挂起 | 5070 + 某些内核版本的已知小问题，更新到较新 HWE 内核通常缓解。 |
| 帧率波动严重 | 关多余相机；算法侧用 IMU 时间戳对齐。 |

---

## 10. 参考链接

- 项目仓库（RMUA2026-01）：https://github.com/RoboMaster/IntelligentUAVChampionshipSimulator/tree/RMUA2026-01
- 官方开发样例 / airsim_ros msg：https://github.com/RoboMaster/IntelligentUAVChampionshipBase/tree/RMUA2026
- RTX 50 系 Linux 驱动指南：https://gist.github.com/jatinkrmalik/86afb07cbe6abf5baa2d29d3842aa328
- 5070 + 580-open 实战记录：https://github.com/adamn1225/FIXED-NVIDIA-RTX-5070-on-Ubuntu-24.04---Working-580-open-Driver-Guide
- NVIDIA Container Toolkit 官方文档：https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/docker-specialized.html

---

### 一句话总结

宿主 22.04 负责"把 5070 驱动起来 + Docker + GPU 透传"，容器 20.04 负责"ROS Noetic + 模拟器"；只要第 **4.2** 步在容器里能用 `vulkaninfo` 看到 5070，后面就是按部就班。显存小，记得**关相机**。
