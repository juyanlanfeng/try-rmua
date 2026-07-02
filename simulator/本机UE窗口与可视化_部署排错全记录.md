# RMUA 模拟器 — 从零部署到本机 UE 大窗口 + 传感器可视化 全流程手册

> 适用分支:`RMUA2026-01`(最新赛季;pin 的仿真器版本就是本地 Build 的 `simulator_12.0.0.5`)
> 说明:`RMUA2026-01` 与 `RMUA2025-01` 用的是**同一个 12.0.0.5 二进制**,差异仅在封装文件:`settings.json` 加了 `CameraDirector`、雷达垂直 FOV 改为 40/-19(原 52/-7);新增 `VelCmdmsg/VelCmd.msg`(速度指令消息:`vx/vy/vz/yawRate/va/stop`);README 更新。本手册的全部流程对两分支通用。
> 目标读者:有 **Ubuntu 22.04** + 一定 ROS/命令行基础(有没有 ROS2 都行)。
> 读完照做,你将能:① 构建并离屏运行官方提交用的 Docker 镜像;② 在本机弹出 **UE 大窗口**实时观察仿真;③ 用 rviz 看 **4 路相机 + 激光雷达**。
>
> 文档分两部分:**第一部分是从零照抄就能跑通的分步手册**;**第二部分是原理与踩坑记录**(出问题时回来查)。
>
> 本机验证环境:Ubuntu 22.04.5(内核 6.8)、24 核、30G 内存、RTX 5070 Laptop(驱动 595.58.03)、Docker 29.5.3、nvidia-container-toolkit 1.19.1。

---

## ⚠️ 一上来必须知道的两件事

1. **关于 ROS 版本**:本项目用的是 **ROS1 Noetic**,但 **Noetic 全部跑在 Docker 容器里,宿主机不需要安装 ROS1**。你宿主上的 ROS2 既不会被用到、也不会冲突(ROS2 用 DDS,这里用的是 ROS1 master `localhost:11311`)。保险起见,执行本手册命令时**用一个没 source 过任何 ROS 的干净终端**即可。

2. **关于"开窗"**:在**混合显卡**机器上(如本机 Intel 核显 + NVIDIA 独显),**容器内无法把 UE 窗口显示到屏幕**(Vulkan present 报 `-13` 崩溃)。解决办法是**把同一个二进制拿到宿主机原生运行**(present 路径就通了)。代价:要给二进制补 ROS 运行库(从容器抽 57 个 `.so`,有脚本一键完成)。原理见 [附录 A](#附录-a原理为什么容器开窗失败宿主原生成功)。
   - 如果你是**单显卡纯 NVIDIA 台式机**,容器内开窗大概率能直接成功,可跳过"路线 B 抽库"的麻烦,直接用 `run_docker_simulator_render.sh`。本手册以**混合显卡(较难的情况)** 为主线。

---

## 0. 总览:架构与两条路线

```
┌───────────────────────────── 宿主机 (Ubuntu 22.04) ─────────────────────────────┐
│  路线A(官方提交形态):                                                          │
│     [容器 sim01] RMUA -RenderOffscreen  → 无窗口,发布 ROS 话题(GPU 加速)      │
│                                                                                  │
│  路线B(本机开窗,开发调试用):                                                  │
│     [原生进程] RMUA-Linux-Shipping seed N                                        │
│         ├ LD_LIBRARY_PATH=~/RMUA/rmua_roslibs (抽自容器的 ROS 库)                    │
│         ├ DISPLAY=:0  → 在 RTX 5070 渲染 → 弹出 UE 大窗口                        │
│         └ ROS_MASTER_URI=localhost:11311                                         │
│              │ 发布 /airsim_node/... 话题                                        │
│              ▼                                                                    │
│     [容器 roscore_host --net host] ROS master(占宿主 localhost:11311)          │
│              ▲ 订阅                                                              │
│     [容器 viz_all --net host] rviz: 雷达点云 + 4 路相机(软件渲染,不抢独显)    │
└──────────────────────────────────────────────────────────────────────────────────┘
```

建议**先把路线 A 跑通**(最简单,验证镜像/GPU 没问题),再做路线 B 开窗。

---

# 第一部分:从零分步手册

> 约定:`▶` = 要敲的命令;`✔` = 预期结果/如何验证。
> 仓库根目录假设为 `~/RMUA/simulator`(按你的实际路径替换)。

## 1. 前置条件与安装

### 1.1 确认 NVIDIA 驱动

▶
```bash
nvidia-smi
```
✔ 能看到你的 GPU 和驱动版本(如 `RTX 5070 ... 595.58.03`)。
若 `command not found` 或报错 → 先装好 NVIDIA 驱动再继续(`ubuntu-drivers devices` 选推荐版本,或装官方 `.run`)。

### 1.2 安装 Docker(若已装可跳过)

▶
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USER          # 把自己加进 docker 组
newgrp docker                          # 或重新登录,使免 sudo 生效
```
✔ `docker run --rm hello-world` 能跑通。
> 🇨🇳 国内拉不动 → 见 [§1.5 国内网络](#15-仅国内网络代理与镜像源)。

### 1.3 安装 nvidia-container-toolkit(GPU 直通,关键)

▶
```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```
✔ **GPU 直通自检**(最重要的一步验证):
▶
```bash
docker run --rm --gpus all nvidia/cuda:12.2.0-base-ubuntu22.04 nvidia-smi
```
能在容器里看到 GPU 就 OK。**如果这里看不到 GPU,后面 UE 会退化成软件渲染(llvmpipe),必须先解决。**

### 1.4 获取代码与预编译仿真器 `Build/`

本仓库只是**薄封装**(脚本 + Dockerfile + 配置),**不含**几个 G 的预编译 UE 二进制。你需要单独拿到 `Build/`。

▶ 克隆封装仓库:
```bash
git clone <本仓库地址> ~/RMUA/simulator
cd ~/RMUA/simulator
git checkout RMUA2026-01      # 最新赛季分支
```
▶ 放入预编译仿真器:把官方发布的仿真器压缩包(对应本分支版本,`LinuxNoEditor` 那一份)解压到仓库下,使目录结构为:
```
~/RMUA/simulator/Build/LinuxNoEditor/RMUA/Binaries/Linux/RMUA-Linux-Shipping
```
> 压缩包来源:官方 RMUA 发布渠道 / 你队伍的共享存储(历史上 `Dockerfile` 里有一条从阿里云 OSS 下载的 `ADD` 链接,现已改用本地 `Build/`)。**版本必须与分支匹配。**

✔ 验证二进制就位:
▶
```bash
ls -lh ~/RMUA/simulator/Build/LinuxNoEditor/RMUA/Binaries/Linux/RMUA-Linux-Shipping
```
能看到约 110+ MB 的可执行文件即可。

### 1.5 (仅国内)网络代理与镜像源

> 不在国内/网络通畅可**整节跳过**。本仓库的 `Dockerfile` 已内置把 apt/ROS 源换成中科大镜像,所以**构建阶段**基本不用额外配代理;唯一需要代理的是**拉基础镜像** `adamrehn/ue4-runtime`(Docker Hub)。

▶ 给 Docker daemon 配代理(假设你有 HTTP 代理 `127.0.0.1:10808`):
```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf >/dev/null <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10808"
Environment="HTTPS_PROXY=http://127.0.0.1:10808"
Environment="NO_PROXY=localhost,127.0.0.1"
EOF
sudo systemctl daemon-reload && sudo systemctl restart docker
```
✔ `docker pull hello-world` 能拉下来。
> 注意:`sudo` 要在**真实终端**里执行(无 TTY 的环境会失败)。

---

## 2. 构建镜像

仓库已带改好的 `Dockerfile`(国内源 + 本地 Build + 把 settings.json bake 进镜像)和 `Dockerfile.viz`。

### 2.1 构建离屏仿真镜像 `simulator01`

▶
```bash
cd ~/RMUA/simulator
docker build -t simulator01 .
```
✔ 结束后:
▶
```bash
docker images | grep simulator01
```
看到 `simulator01  latest  ... 8.7GB` 左右即成功。
> 构建报错排查见 [附录 C](#附录-c构建常见报错对照)。

### 2.2 构建可视化镜像 `simulator01-viz`(在上一步基础上加 rviz/rqt)

▶
```bash
docker build -t simulator01-viz -f Dockerfile.viz .
```
✔ `docker images | grep simulator01-viz` → 约 10.4GB。
> 这一步 apt 走镜像里已配好的中科大源,很快,无需额外代理。

---

## 3. 路线 A:离屏运行(官方提交形态,先验证基础链路)

▶ 启动离屏仿真(seed 任意,这里 123):
```bash
cd ~/RMUA/simulator
./run_docker_simulator.sh 123
```
> 该脚本实际执行:`docker run -it --cpuset-cpus="0-9" -e Seed=123 --rm --name sim01 --net host --gpus 'device=0' simulator01`。容器内 `start.bash` 会 `source` ROS、起 `roscore &`,再以 `-RenderOffscreen` 启动仿真。

✔ **另开一个终端**验证 ROS 话题在发(用容器自带的 rostopic,免在宿主装 ROS):
▶
```bash
docker exec sim01 bash -lc "source /opt/ros/noetic/setup.bash && rostopic list"
docker exec sim01 bash -lc "source /opt/ros/noetic/setup.bash && rostopic hz /airsim_node/drone_1/imu/imu"
```
看到一堆 `/airsim_node/...` 话题、IMU 稳定 ~100Hz,就说明镜像 + GPU 一切正常。
> ✅ 到这里,**官方提交形态已跑通**。如果你只需要提交,做到这步即可。下面是为了本机开窗。

▶ 关掉它,进入路线 B:
```bash
docker rm -f sim01
```

---

## 4. 路线 B:本机 UE 大窗口(开发调试)

> 思路回顾:容器内开窗在混合显卡上不通,所以**二进制原生跑在宿主**;ROS master 借一个容器里的 roscore(免在宿主装 Noetic)。

### 4.1 抽取 ROS 运行库(一次性,之后复用)

▶
```bash
cd ~/RMUA/simulator
./scripts/extract_roslibs.sh            # 默认抽到 ~/RMUA/rmua_roslibs
```
✔ 末尾打印 `✅ ldd 校验通过:0 not found`(共 57 项)。
> 原理:UE 二进制链接了 ROS1,宿主没装 Noetic;glibc 向后兼容,故从 Noetic 容器抽库到宿主可直接用。脚本做了三件事:拷 `/opt/ros/noetic/lib`、拷 boost1.71/console_bridge、用 `tar -ch` 解引用拷 log4cxx/ICU66/apr。

### 4.2 启动 roscore(容器,占宿主 11311)

▶
```bash
./scripts/run_roscore.sh
```
✔ 打印 `✅ roscore 已就绪:localhost:11311`。

### 4.3 启动 UE 大窗口(单实例!)

▶
```bash
./scripts/run_host_window.sh 123        # 参数是 seed
```
> 脚本会自动把 `settings.json` 拷到 `~/Documents/AirSim/`,做单实例保护,然后用 `LD_LIBRARY_PATH=~/RMUA/rmua_roslibs DISPLAY=:0 ROS_MASTER_URI=http://localhost:11311` 启动二进制。
> ⚠️ **铁律:同一时刻只能有一个 UE 实例**。两个实例会抢 GPU 触发 `VK_ERROR_DEVICE_LOST` 崩溃。

✔ 几秒后**桌面弹出 UE 大窗口**(无人机停在 "R" 起降坪上,右上角有 Time/Score/State 等 HUD)。

✔ 命令行/日志层面的验证(**另开终端**):
▶
```bash
# 1) 进程在(注意:别用 pgrep -x,进程名会被截断到15字符导致假阴性)
pgrep -af "RMUA-Linux-Shipping RMUA seed"
# 2) 窗口确实用独显渲染(日志里应有 Using Device 0: NVIDIA ... + swapchain 创建成功)
# 3) 话题在发
docker exec roscore_host bash -lc "source /opt/ros/noetic/setup.bash && rostopic list"
docker exec roscore_host bash -lc "source /opt/ros/noetic/setup.bash && rostopic hz /airsim_node/drone_1/imu/imu"
```
✔ IMU ~100Hz、雷达 ~10Hz、4 路相机 ~13–16Hz。

---

## 5. 传感器可视化(rviz:雷达 + 4 路相机)

> 为什么不用 `rqt_image_view`:它在"容器→宿主 X11 + 软件渲染"下会**灰屏空转**(帧数据是好的,Qt 画不出来)。改用 rviz 的 Image 显示,rviz 的 GL 路径在本机可用。详见 [附录 B](#附录-b相机为何用-rviz-而非-rqt)。

▶
```bash
./scripts/run_viz.sh
```
✔ 弹出一个 rviz 窗口(标题 `rmua_full.rviz - RViz`),里面有:
- 3D 区:**激光雷达点云**(随无人机周围障碍/赛道门变化);
- **4 个相机面板**:`front_left / front_right / back_left / back_right`。

> 相机面板默认可能堆叠成标签页,用鼠标把标签拖开摆成田字形即可。
> 关闭可视化:`docker rm -f viz_all`。

---

## 6. UE 窗口操作指南

`settings.json` 里 `ViewMode=FlyWithMe`(摄像机在无人机后上方跟随)、`SimMode=Multirotor`。

**无人机默认不动** —— 没有算法发指令时它停在起飞点。点一下窗口让它获得键盘焦点,然后:

| 按键 | 作用 |
|---|---|
| `F1` | 显示/隐藏全部快捷键帮助(以这个 build 实际支持的为准) |
| `F8` | 切到自由飞行摄像机:`W/A/S/D` 平移、`E/Q` 升降、**按住鼠标右键拖动**转视角、滚轮调速 |
| `F2` | 开/关渲染(临时省 GPU) |
| `F5` | 开/关屏幕调试 HUD |
| `Backspace` / 再按 `F8` | 视角复位 / 回到跟随无人机 |

**让无人机飞起来**(需要外部 ROS 指令,任选其一):
▶
```bash
# 起飞服务
docker exec roscore_host bash -lc "source /opt/ros/noetic/setup.bash && rosservice call /airsim_node/drone_1/takeoff '{}'"
# 或往机体系速度话题发指令:/airsim_node/drone_1/vel_body_cmd
# 或直接跑算法仓库 RoboMaster/IntelligentUAVChampionshipBase 接管控制
```
> HUD 显示 `State:Finished` 表示这一局已结束(无算法接管会自然结束);此时被动传感器(IMU/雷达)仍发,相机 scene-capture 可能停发。要重来:`rosservice call /airsim_node/reset '{}'` 或重启窗口进程。

> 注意:上面 UE 窗口自带的 `F8/WASD` 只是**移动观察摄像机**,不是控制无人机。要像玩游戏一样用键盘**操纵无人机本身**,见下一节 `drone_teleop`。

---

## 6.5 键盘遥控无人机飞行(drone_teleop)

一个独立 ROS1 功能包 `drone_teleop/`,用 `pynput` **全局捕获**键盘 → 发速度指令到
`/airsim_node/drone_1/vel_body_cmd`,**不修改模拟器**。全局捕获 = 焦点在哪都能控制,
可以一直盯着 UE 窗口按键。

### 6.5.1 一次性准备(clone 脚手架 + 编译)

VelCmd 等消息来自官方脚手架的 `airsim_ros` 包,需和本功能包在**同一 catkin 工作区**编译。

```bash
cd ~/RMUA/simulator
# ① clone 官方脚手架(算法侧),拿 airsim_ros
git clone -b RMUA2026 https://github.com/RoboMaster/IntelligentUAVChampionshipBase ~/IntelligentUAVChampionshipBase

# ② ⚠️关键:脚手架自带的 VelCmd.msg 是过时的 Twist 版,对本二进制无效!
#    必须换成本仓库 6 字段版,否则指令发出去无人机【完全不动】(md5 不匹配)
cp VelCmdmsg/VelCmd.msg ~/IntelligentUAVChampionshipBase/basic_dev/src/airsim_ros/msg/VelCmd.msg

# ③ 把功能包拷进工作区
cp -r drone_teleop ~/IntelligentUAVChampionshipBase/basic_dev/src/

# ④ 构建带编译工具 + pynput + airsim_ros 依赖的镜像
docker build -f Dockerfile.teleop -t simulator01-teleop .

# ⑤ 在容器里编译(白名单只编 airsim_ros + drone_teleop,跳过 C++ 重包)
WS=~/IntelligentUAVChampionshipBase/basic_dev
docker run --rm --net host -v "$WS":/ws --entrypoint bash simulator01-teleop -lc \
  'source /opt/ros/noetic/setup.bash && cd /ws && \
   catkin_make -DCATKIN_WHITELIST_PACKAGES="airsim_ros;drone_teleop" install'
# 注:build/devel 由容器内 root 创建,宿主删不掉时用:
#   docker run --rm -v "$WS":/ws --entrypoint bash simulator01-teleop -lc 'rm -rf /ws/build /ws/devel /ws/install'
```

### 6.5.2 启动键盘控制(每次)

前置:`run_roscore.sh` + `run_host_window.sh` 已在跑。

```bash
cd ~/RMUA/simulator
./scripts/run_teleop.sh        # 前台交互式;Ctrl+C 或按 ESC 退出
```

或后台拉起(不占终端,照样全局抓键):

```bash
WS=~/IntelligentUAVChampionshipBase/basic_dev
xhost +local:
docker run -d --rm --net host \
  -e DISPLAY="${DISPLAY:-:0}" -e ROS_MASTER_URI=http://localhost:11311 \
  -v /tmp/.X11-unix:/tmp/.X11-unix -v "$WS":/ws \
  --name teleop_node --entrypoint bash simulator01-teleop -lc \
  'source /opt/ros/noetic/setup.bash && source /ws/devel/setup.bash && exec python3 -u /ws/devel/lib/drone_teleop/keyboard_teleop.py'
docker logs teleop_node          # 看到帮助信息即就绪
docker rm -f teleop_node         # 停止
```

### 6.5.3 键位

盯着 UE 窗口直接按:**`T` 起飞**(地面必按)/ `L` 降落 / `WASD` 平移 /
`R`-`F` 升降 / `Q`-`E` 偏航 / `Space` 急停 / `=`-`-` 调速 / `ESC` 退出。松开自动悬停。

### 6.5.4 ⚠️ 必做:开 IgnoreOverTime,否则起飞后无人机会"锁死"

查实(2026-06-21):这是**竞速比赛**,默认**超时/撞击就结束本局(State:Finished),
结束后无人机忽略所有控制指令**。表现为"刚 reset 能动、悬停十几秒后 WASD 突然推不动"——
那不是 bug,是这一局超时结束了。

**解法**:编辑 `Build/LinuxNoEditor/RMUA/Content/Configs/GameConfig.json`,两个开关都置 `true`:
```json
{ "IgnoreAllHitCollision": true, "IgnoreOverTime": true }
```
然后**重启 UE**(GameConfig 只在启动时读一次)。之后无人机不会被超时/撞击踢出局,
键盘速度控制 airborne 完全正常(实测按住 W → 前进 13.78m)。
> 宿主开窗读 Build 里这份;Docker 离屏读镜像 bake 的那份。

### 6.5.5 实测踩坑

| 现象 | 原因 / 解法 |
|---|---|
| 起飞后飞一会就推不动 | 这一局超时结束(见 6.5.4 开 IgnoreOverTime);或 `rosservice call /airsim_node/reset` 重开 |
| 想确认按键链路是否正常 | 按住 W 时 `rostopic echo /airsim_node/drone_1/vel_body_cmd` 看是否发出 `vx=2.0`;发了即键盘→发布全通 |
| 命令发出但 md5 不匹配收不到 | `VelCmd.msg` 没换 6 字段版(见 6.5.1②);`pub.get_num_connections()>0` 才算真握手 |
| 按住一卡一卡 / 按一下就停 | 本节点用"按下集合+松开宽限"判定,不依赖自动重复(老版靠自动重复,某些 X 会话不发重复→按住失效) |
| 按键完全无反应 | 必须 X11(`echo $XDG_SESSION_TYPE`=x11);容器要 `-e DISPLAY`+挂 `/tmp/.X11-unix`+宿主 `xhost +local:` |
| 反复连/断后新节点连不上 | master 残留幽灵 publisher:`rosnode cleanup` |
| 杀 UE 误杀自己的 shell | 用 `pkill -x RMUA-Linux-Ship`(comm 名),别用 `pkill -f`(会匹配自己的 bash) |

详细说明见 `drone_teleop/README.md`。

---

## 7. 一键全流程(把路线 B 串起来)

首次部署(假设镜像已构建、`Build/` 已就位):
```bash
cd ~/RMUA/simulator
./scripts/extract_roslibs.sh        # ① 抽 ROS 库(一次性)
./scripts/run_roscore.sh            # ② 起 roscore
./scripts/run_host_window.sh 123    # ③ 开 UE 窗口(前台,Ctrl+C 关)—— 建议单独开一个终端
./scripts/run_viz.sh                # ④ 开 rviz 看相机/雷达(另一个终端)
./scripts/run_teleop.sh             # ⑤ 键盘遥控无人机(可选;先按 6.5.1 编好包)
```

## 8. 关闭与清理

```bash
pkill -f "RMUA-Linux-Shipping RMUA seed"   # 关 UE 窗口
docker rm -f teleop_node viz_all roscore_host   # 关遥控 + 可视化 + roscore
# 离屏模式:docker rm -f sim01
```

---

# 第二部分:原理、排错与记录

## 9. 常见问题排查(FAQ)

| 症状 | 原因 | 解决 |
|---|---|---|
| UE 窗口一闪退,日志 `VkResult=-13` at `...SurfacePresentModesKHR` | 容器内 → 宿主 Vulkan present 在混合显卡上不通 | **别在容器里开窗**,用路线 B 宿主原生跑 |
| UE 崩 `VK_ERROR_DEVICE_LOST (VkResult=-4)` | **同时跑了两个 UE 实例**抢 GPU | 单实例铁律;`pkill -f "RMUA-Linux-Shipping RMUA seed"` 后只起一个 |
| `error while loading shared libraries: libroscpp.so` | 宿主缺 ROS 运行库 | 跑 `scripts/extract_roslibs.sh`,启动时带 `LD_LIBRARY_PATH=~/RMUA/rmua_roslibs` |
| 窗口里画面全是软件渲染/极卡,日志用了 `llvmpipe` | GPU 没直通 / DISPLAY 不对 | 查 §1.3 GPU 自检;确认 `DISPLAY=:0` |
| `pgrep -x RMUA-Linux-Shipping` 永远查不到进程 | 进程名被截断到 15 字符,`-x` 精确匹配失败 | 改用 `pgrep -f "RMUA-Linux-Shipping RMUA seed"` |
| 日志停在 `LogTemp: drone_1` 不动 | 这是进了稳定渲染循环、不再打日志 | **不是崩溃**,正常 |
| rqt 4 个相机窗口全灰 | rqt 在容器→宿主X11+软件渲染下空转 | 用 `scripts/run_viz.sh`(rviz)看相机 |
| rviz 报 `Global Status: Warn` / 没点云 | Fixed Frame 或话题没数据 | 确认 UE 在跑且雷达在发;Fixed Frame=`lidar` |
| `docker build` 时 apt 503 / ROS 装不上 | 国内网络 | 仓库 Dockerfile 已用中科大源;基础镜像拉取配 daemon 代理(§1.5) |
| 容器 GUI 连不上宿主 X:`cannot open display` | X11 访问控制 | 宿主执行 `xhost +local:`(`run_viz.sh` 已自动做) |

## 10. 关键经验总结

1. **混合显卡:容器内 present 不通,宿主原生可通**——这是能否开窗的分水岭。判据:`vkcube` 容器内崩、宿主正常。
2. **`VK_ERROR_DEVICE_LOST` 先查是不是开了第二个实例**,别急着怪相机/分辨率。**单实例铁律。**
3. **`pgrep -x` 对长进程名假阴性**(15 字符截断),验活一律 `pgrep -f`。
4. **UE 进渲染循环后不打日志**,"日志静默" ≠ "进程死了"。
5. **rqt_image_view 在本机这套环境会灰屏**,相机改用 **rviz 的 Image 显示**。
6. **可视化容器一律 `--net host` + 软件渲染**:既连宿主 11311,又不抢独显。
7. **抽 ROS 库要 `tar -ch` 解引用符号链接**,否则拷过去是断链。
8. **time 同步**:算法须以 IMU 时间戳(`/airsim_node/drone_1/imu/imu`)为全局时钟。
9. **话题名与 README 有出入**:速度指令实际是 `vel_body_cmd`(README 写的 `vel_cmd_body_frame` 不准)。
10. **离屏 Docker 才是比赛提交形态**;本机窗口仅供开发。

---

## 附录 A:原理 —— 为什么容器开窗失败、宿主原生成功

本机是 **Optimus 反向 PRIME** 混合显卡:NVIDIA 独显负责渲染,画面再交给 **Intel 核显**扫描到屏幕(显示器物理接在核显)。而这台机器的 Intel iGPU(PCI id `0x7d67`)**太新,Mesa ANV 驱动还不支持**。

- **容器内**:UE 用 Vulkan 渲染后要把画面 present 到宿主的 X/显示链路,这条"容器 → 宿主 → 核显扫描"的 WSI present 路径在此混合显卡上走不通 → `vkGetPhysicalDeviceSurfacePresentModesKHR` 返回 `VkResult=-13 (VK_ERROR_UNKNOWN)` → SIGSEGV。
  - 已证实**与 UE 无关**:容器内裸跑 `vkcube` 同样崩在 swapchain;宿主 `vkcube` 正常。
  - 试过但**全部无效**:挂 `/dev/dri`+video/render 组、`NVIDIA_DRIVER_CAPABILITIES=all`、Optimus offload 环境变量、补 DRI3 库、换宿主 Vulkan loader 1.3.204(撞 `GLIBC_2.34` 不兼容)。
- **宿主机原生**:present 走的是宿主本地的完整图形栈,路径打通。日志可见:
  ```
  LogVulkanRHI: Device 0: NVIDIA GeForce RTX 5070 Laptop GPU
  LogVulkanRHI: Using Device 0 ...
  LogVulkanRHI: Creating new VK swapchain with present mode 2, format 44, num images 3   ← 成功,无 -13
  ```

## 附录 B:相机为何用 rviz 而非 rqt

抓一帧相机原始数据统计:`enc=bgr8 960x720 bytes=2073600 min=0 max=231 mean=83.6 std=83.3`。`std≈83` 说明**画面内容丰富、绝非空白灰帧**——发布端没问题。但 4 个 `rqt_image_view` 各自吃满一个 CPU 核(~100%)却显示灰色:rqt(Qt)在"容器→宿主 X11 + 软件渲染"下绘制路径不通、退化成空转(`QT_X11_NO_MITSHM=1` 也救不回)。rviz 走 Ogre/GL 渲染(雷达点云就是它画的,本机可用),故相机改用 `rviz/Image` 显示,配置见 `rmua_full.rviz`。

## 附录 C:构建常见报错对照

| 报错 | 原因 | 修复 |
|---|---|---|
| `FROM` 拉镜像 i/o timeout | Docker Hub 直连不通 | 配 daemon 代理(§1.5) |
| apt `archive.ubuntu.com` 503 | 明文 HTTP 走代理高并发不稳 | Dockerfile 已换中科大直连镜像 |
| ROS 装不上:`No system certificates available` | 基础镜像无 ca-certificates,HTTPS 源失败 | Dockerfile 已改用中科大 **HTTP** ROS 源 |

## 附录 D:文件 / 镜像 / 传感器参数

**脚本(本仓库 `scripts/`)**

| 脚本 | 作用 |
|---|---|
| `extract_roslibs.sh` | 从 simulator01 抽 ROS 库到 `~/RMUA/rmua_roslibs`(含 ldd 校验) |
| `run_roscore.sh` | 起容器内 roscore(占宿主 11311) |
| `run_host_window.sh [seed]` | 宿主原生开 UE 窗口(单实例保护 + 自动放 settings.json) |
| `run_viz.sh` | 开 rviz(雷达 + 4 相机) |

**配置/封装文件**

| 文件 | 说明 |
|---|---|
| `Dockerfile` | 国内源 + 本地 Build + bake settings.json |
| `Dockerfile.viz` | simulator01 上加 rviz/rqt → simulator01-viz |
| `rmua_full.rviz` | **雷达 + 4 路相机** 的 rviz 配置(最终用) |
| `rmua_lidar.rviz` | 仅雷达点云的 rviz 配置 |
| `run_docker_simulator.sh` | 离屏运行(官方形态) |
| `run_docker_simulator_render.sh` | 容器开窗尝试(**本机混合显卡不可用**,留作记录) |
| `settings.json` → `~/Documents/AirSim/` | AirSim 车辆/传感器配置 |

**镜像**

```
simulator01:latest        8.71 GB   (离屏仿真,提交基底)
simulator01-viz:latest   10.4  GB   (+ rviz/rqt,仅本机可视化)
```

**传感器(settings.json)**

```
SimMode=Multirotor   ViewMode=FlyWithMe
相机 ×4: front/back × left/right,每路 960×720,FOV 60°,ImageType=0 (Scene/bgr8)
激光雷达: 32 线,range=30m,10 rot/s,200000 pts/s
```

**ROS 话题清单**(`/airsim_node/` 下)

```
drone_1/{front,back}_{left,right}/Scene (+/camera_info)   # 4 相机
drone_1/imu/imu  drone_1/lidar  drone_1/gps               # 传感器
drone_1/debug/{pose_gt, wind, rotor_pwm}                  # 调试/真值
drone_1/vel_body_cmd  drone_1/rotor_pwm_cmd               # 指令(注意是 vel_body_cmd)
initial_pose  end_goal
```
