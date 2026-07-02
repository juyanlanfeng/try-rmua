# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is the **RMUA (RoboMaster University AI Challenge) Intelligent UAV Championship Simulator** — a drone-racing / autonomous-flight competition simulator built on **Unreal Engine 4 + AirSim**.

Crucially, **this repo contains no compilable source code.** The actual simulator is a pre-built, shipping UE binary (`RMUA-Linux-Shipping`) downloaded separately as a zip. What is version-controlled here is only the **thin wrapper** around that binary:

- Launch scripts (`run_simulator*.sh`, `start.bash`, `Build/LinuxNoEditor/RMUA.sh`)
- A `Dockerfile` that packages the binary + ROS into an image
- AirSim `settings.json` (vehicle / sensor / camera configuration)
- `README.md` (release notes + the ROS topic contract) and `docs/`

So "developing" here means: configuring the simulator (cameras/sensors, game/ROS config), packaging it into Docker, and understanding the **ROS topic interface** that a competitor's algorithm talks to. The algorithm itself lives in a *separate* repo (`RoboMaster/IntelligentUAVChampionshipBase`) and is not part of this project.

## How the pieces fit together

```
run_simulator.sh <seed>            # rendered (UE window)
run_simulator_offscreen.sh <seed>  # offscreen (-RenderOffscreen, no window)
        │  sources ROS, starts `roscore &`, then:
        ▼
Build/LinuxNoEditor/RMUA.sh seed <seed>   # UE launcher wrapper
        ▼
Build/LinuxNoEditor/RMUA/Binaries/Linux/RMUA-Linux-Shipping   # the actual UE+AirSim binary
        ▼
publishes/subscribes ROS topics under /airsim_node/...  ◄──► competitor algorithm (separate repo)
```

- **`<seed>`** is a random seed that selects the track/scenario configuration. Different seeds → different layouts. It is the one required CLI argument.
- **`roscore` runs inside the launch scripts**, so the simulator process is also the ROS master. Tools (`rostopic`, `rviz`, `rqt`) connect to `localhost:11311`.
- **Time sync gotcha:** the simulator clock differs from wall-clock. Algorithms must use the timestamp from the IMU topic (`/airsim_node/drone_1/imu/imu`) as the global clock. This is the single most important integration nuance.

## Common commands

There is no compile/lint/unit-test step — the binary is prebuilt. The real workflow:

```bash
# --- Local (host) run ---
mkdir -p ~/Documents/AirSim
cp settings.json ~/Documents/AirSim/        # AirSim reads its config from here
./run_simulator.sh 123                       # rendered, seed 123
./run_simulator_offscreen.sh 123             # headless

# Inspect the ROS interface (in another shell)
source /opt/ros/noetic/setup.bash
rostopic list
rostopic hz /airsim_node/drone_1/imu/imu     # confirm data is flowing

# --- Docker (offscreen only) ---
docker build -t simulator01 .                # see "Docker build" note below
./run_docker_simulator.sh 123                # passes seed via -e Seed=, --gpus, --net host
```

`run_docker_simulator.sh` runs `docker run ... -e Seed=$1 ...`; inside the container `start.bash` reads `$Seed` and launches with `-RenderOffscreen`. **Docker mode is always offscreen.**

### Docker build note
The `Dockerfile` does **not** copy the local `Build/` directory. It `ADD`s a simulator zip from Aliyun OSS and unzips it inside the image (the `ADD Build` line is commented out). It also bakes `settings.json` into `.../RMUA/Binaries/Linux/`. Consequences:
- Changing `settings.json` (e.g. to disable a camera) requires a **`docker build` rebuild** to take effect. Host runs only need the file re-copied to `~/Documents/AirSim/`.
- The zip URL / version in the `Dockerfile` is pinned per season; bumping the simulator version means updating that URL.

## The ROS interface (the real "API")

All interaction is over ROS Noetic topics/services under `/airsim_node/`. The authoritative list is in `README.md`; the essentials:

**Sensors (subscribe):** four cameras `front_left/right` + `back_left/right` (`.../Scene`), `imu/imu`, `lidar`, `gps` (pose with error), `debug/pose_gt` (ground-truth pose), `debug/wind` (anemometer, semifinal), `debug/rotor_pwm`. Plus `/airsim_node/initial_pose` and `/airsim_node/end_goal`.

**Commands (publish):** `vel_cmd_body_frame` (velocity) and `rotor_pwm_cmd` (PWM). **Rotor index order is `0:front-right, 1:back-left, 2:front-left, 3:back-right`** — non-obvious, used by both the PWM command and feedback topics.

**Services:** `takeoff`, `land`, `/airsim_node/reset`, and `/airsim_node/meter_report` (factory-inspection reporting, semifinal).

> If `rqt`/`rviz` reports missing message types, source the `airsim_ros` package from `RoboMaster/IntelligentUAVChampionshipBase` (matching the season branch).

## Configuration files

| File | Purpose |
|---|---|
| `settings.json` (repo root) → `~/Documents/AirSim/settings.json`, or baked into the Docker image | AirSim vehicle/sensor/camera config. **This is where you disable cameras to cut VRAM/stabilize frame rate** — remove the camera's block. Defines the 4 cameras and a 32-channel lidar. |
| `Build/LinuxNoEditor/RMUA/Content/Configs/GameConfig.json` | Debug flags: `IgnoreAllHitCollision` (collisions don't end the run), `IgnoreOverTime` (timeout doesn't end the run). Both default `false`. |
| `Build/LinuxNoEditor/RMUA/Content/Configs/ROSConfig.json` | Rosbag/video recording paths, recorded topic list, and `FrameTimeTolerance`. |

## Branches = competition seasons / stages

Branch names track the contest: `RMUA2023*`, `RMUA2025-01`, `RMUA2026-01` (latest / current checkout), plus `stage1_*` / `stage2_*` / `stage3` variants. Each season pins a simulator binary version — though `RMUA2026-01` and `RMUA2025-01` actually pin the **same** `simulator_12.0.0.5` binary and differ only in wrapper files (`RMUA2026-01`'s `settings.json` adds a `CameraDirector` block + changes the lidar vertical FOV to 40/-19, and adds `VelCmdmsg/VelCmd.msg`). Competition stages (in `README.md`, Chinese): 初赛 (preliminary), 复赛 (semifinal — adds factory-inspection task, crosswind, anemometer), 决赛 (final) — each historically a different zip/seed set.

## Working-tree state to be aware of

`Build/` and the simulator binary are **downloaded artifacts, not tracked by git** (no `.gitignore`; they're simply untracked). The git-tracked wrapper files (`Dockerfile`, `run_*.sh`, `settings.json`, `start.bash`, `README.md`, `LICENSE`, `docs/`) may show as deleted in `git status` on a working copy where someone unzipped the simulator over a fresh clone. When in doubt, recover wrapper files from git (`git show HEAD:<file>`); the `Build/` tree comes from the simulator zip, not from git.

## Hardware / runtime context

Officially Ubuntu 20.04 + ROS Noetic + NVIDIA GPU. Newer setups (e.g. Ubuntu 22.04 + RTX 50-series) run the official Docker container (which is 20.04 + Noetic inside) on the host, using `nvidia-container-toolkit` to pass the GPU through — the container needs `--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all`, otherwise UE falls back to software rendering (llvmpipe). See `RMUA2026模拟器_Ubuntu22.04_Docker部署文档.md` for the full host-setup walkthrough. On low-VRAM GPUs, disable unneeded cameras in `settings.json`.
