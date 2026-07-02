# AGENTS.md

> 本文件位于 `try-rmua` 仓库的 `simulator/` 子目录;下述命令默认在该目录执行(`cd ~/RMUA/simulator`)。算法工作区在 `../IntelligentUAVChampionshipBase/basic_dev/`。

High-signal guidance for AI agents working in this repo. Every line is something an agent would likely get wrong without it.

## What this is (and isn't)

- RMUA 2026 drone-racing simulator: a **prebuilt UE4 + AirSim binary** (`Build/LinuxNoEditor/RMUA/Binaries/Linux/RMUA-Linux-Shipping`) wrapped by launch scripts + Docker + AirSim `settings.json`. **There is no compilable source here** — "development" means configuring the sim, building Docker images, and talking to the ROS interface.
- `Build/` is a **downloaded, gitignored artifact** (from `simulator_12.0.0.5.zip`). It is not in git; recover it from the zip, not from `git show`.
- The competitor algorithm + `airsim_ros` message package live in the sibling `../IntelligentUAVChampionshipBase/basic_dev/` (same `try-rmua` repo).

## Running the simulator

`<seed>` is the one required arg (selects track layout). Launch scripts start `roscore` themselves; tools connect to `localhost:11311`.

```bash
./run_simulator.sh 123              # host, rendered (needs ROS Noetic installed on host)
./run_simulator_offscreen.sh 123    # host, headless (-RenderOffscreen)

docker build -t simulator01 .       # needs Build/ present locally (see Docker images)
./run_docker_simulator.sh 123       # docker, offscreen only; --gpus 'device=0' --cpuset-cpus=0-9 --net host
```

### Mixed-GPU laptops (Intel+NVIDIA Optimus): use the `scripts/` host-native flow

Container Vulkan **cannot present to the host desktop** on Optimus — UE crashes at the swapchain (`vkGetPhysicalDeviceSurfacePresentModesKHR → VkResult=-13 → SIGSEGV`). `run_docker_simulator_render.sh` documents this; **don't use it on hybrid-GPU machines.** Run UE natively on the host with ROS borrowed from the image (host needs no ROS install):

```bash
./scripts/extract_roslibs.sh     # one-time: copy ROS noetic libs from simulator01 → ~/RMUA/rmua_roslibs (ldd-verified)
./scripts/run_roscore.sh         # roscore in a container, --net host
./scripts/run_host_window.sh 123 # UE binary natively, LD_LIBRARY_PATH=~/RMUA/rmua_roslibs, DISPLAY=:0
./scripts/run_viz.sh             # rviz in simulator01-viz, software-rendered so it won't fight UE for the dGPU
```

- **Single-instance rule:** only one `RMUA-Linux-Shipping` may run at a time; a second triggers `VK_ERROR_DEVICE_LOST`. `run_host_window.sh` enforces this via `pgrep`.
- Script image names default to `simulator01` / `simulator01-viz`; override with `IMAGE=`.

## Docker images (two Dockerfiles, chained)

| Dockerfile | Image | Adds |
|---|---|---|
| `Dockerfile` | `simulator01` | UE binary + ROS Noetic (base). **`ADD`s local `Build/LinuxNoEditor`** (not a zip) and bakes `settings.json` into the binary dir. |
| `Dockerfile.viz` | `simulator01-viz` | rviz + rqt + mesa. |

- `.dockerignore` excludes `*.md`, `docs/`, `CLAUDE.md`, `LICENSE`, `.git` → editing docs does **not** need a rebuild. Editing `settings.json` or `Build/` **does** (they're `ADD`ed into the image).
- apt/pip use USTC / Tsinghua mirrors (CN network). The ROS apt source is HTTP, not HTTPS, on purpose.
- Current image state: `simulator01` has `GameConfig.json` baked with both flags `true` (dev mode, patched via a thin layer — a full `docker build` re-bakes whatever `Build/.../GameConfig.json` says, which the working tree also has `true`). `simulator01-viz` has `ENTRYPOINT ["/bin/bash"]` so `docker run -it <img>` gives a shell, not a UE crash (`Dockerfile.viz` sets this; `run_viz.sh` still passes `--entrypoint bash`).

## ROS interface (the real API)

> ⚠️ `CLAUDE.md` is **stale on two points**: it says the Dockerfile downloads a zip from Aliyun (it actually `ADD`s local `Build/`), and it calls the velocity topic `vel_cmd_body_frame`. The real topic is **`vel_body_cmd`**. Trust this file + `README.md` over `CLAUDE.md`.

Full topic list is in `README.md`; all live under `/airsim_node/`. Commands: `drone_1/vel_body_cmd` (velocity) and `drone_1/rotor_pwm_cmd` (PWM). Services: `drone_1/takeoff`, `drone_1/land`, `/airsim_node/reset`, `/airsim_node/meter_report` (factory inspection, semifinal).

### Integration gotchas (each will silently break you)

1. **Velocity topic is `drone_1/vel_body_cmd`, NOT `vel_cmd_body_frame`.** The scaffold's `basic_dev.cpp` still uses the old name — commands go nowhere.
2. **`airsim_ros/VelCmd` is the 6-field version** (see `VelCmdmsg/VelCmd.msg`): `header, vx, vy, vz, yawRate, va, stop`. The scaffold ships an **old** `VelCmd.msg` (`geometry_msgs/Twist twist`) → md5 mismatch → publisher connects but **the drone never moves**. Before building any publisher, overwrite it:
   ```bash
   cp VelCmdmsg/VelCmd.msg  <ws>/src/airsim_ros/msg/VelCmd.msg
   ```
3. **Rotor index order** (PWM command + feedback): `0:front-right, 1:back-left, 2:front-left, 3:back-right`.
4. **Use the IMU timestamp as the global clock**, not wall-clock. They differ by ~20s and the sim discards "expired" msgs. `header.stamp` must come from `/airsim_node/drone_1/imu/imu`.
5. **Body frame is NED**: x=front, y=right, z=down (so "up" = `-vz`). `va` = acceleration cap 0–8 (default 4; `0` = no accel, avoid). `stop=1` = emergency hover.
6. **The race locks the drone without dev flags.** By default a timeout/collision ends the run (State: Finished) and the drone then **ignores all commands**. Symptom: works right after reset, freezes after ~10s of hover. Fix: set both flags in `GameConfig.json` and restart UE (see Config).
7. **Control interface locks to whichever type the sim receives first** (PWM vs VEL) — rules manual: "控制接口类型以每场比赛模拟器首次接收到的信号类型为准". Don't mix `vel_body_cmd` and `rotor_pwm_cmd` in one run; the first one wins, the other is silently ignored.
8. **Command rate max 100 Hz** (rules §2.3); keep publishers ≤100 Hz.

### Rules-manual reference (§2.3 模拟器参数, for the competitor algorithm)

- World frame: **NED, origin at marker #1**; body frame also NED (x=front, y=right, z=down, so up = `-vz`).
- Sensors: IMU 100 Hz · front/rear stereo 960×720 @60°, 20 Hz, baseline 300 mm · MID360 lidar 30 m, 10 Hz, 20000 pts/frame · GPS 10 Hz (±0.1 m pos, ±0.2 rad att noise) · wind 50 Hz world-frame truth.
- Failure = collision with rigid body, >2 s in the off-road static force-field, wrong factory meter value, or segment time limit (180/180/180/200/220/200 s). GPS reads 0 inside factories; factory inspection reported via `/airsim_node/meter_report`.
- Submission image constraints: <15 G, **no GUI**, must leave the start trigger zone within 30 s of deploy, must not self-exit. (Applies to the competitor algorithm image, not this dev repo.)

## Config files

| File | Purpose / gotcha |
|---|---|
| `settings.json` (root) → host: `~/Documents/AirSim/settings.json`; docker: baked into image | AirSim vehicle/sensor/camera config. **Disable cameras here to cut VRAM / stabilize fps** by removing the camera block. Defines 4 cameras (960×720@60°) + 32-ch lidar (VerticalFOV 40/-19, 30 m range). |
| `Build/LinuxNoEditor/RMUA/Content/Configs/GameConfig.json` | `IgnoreAllHitCollision`, `IgnoreOverTime`. **For any dev work set both `true` and restart UE** (read once at startup) — otherwise the race ends on timeout/collision and the drone stops responding (gotcha #6). Current working tree has both `true`. |
| `Build/LinuxNoEditor/RMUA/Content/Configs/ROSConfig.json` | rosbag/video record paths, recorded topic list, `FrameTimeTolerance`. Its record list uses `drone_1/pose_gt` (no `debug/`), slightly different from the live `drone_1/debug/pose_gt` topic. |

## Verification (there is no lint / test / typecheck)

- The only "build" is `docker build`. The only "test" is: run the sim, then in another shell `source /opt/ros/noetic/setup.bash && rostopic list && rostopic hz /airsim_node/drone_1/imu/imu` to confirm data flows.
- If `rqt`/`rviz` report missing message types, you need the `airsim_ros` package sourced — it's in the scaffold repo, not here.

## Git state (so `git status` doesn't surprise you)

- 本目录(`simulator/`)是 `try-rmua` 仓库的子目录;git 操作在仓库根 `~/RMUA` 进行。
- 已入库:本目录全部源码/配置/文档。在根 `.gitignore` 中忽略:`Build/`(2G 二进制)、`../rmua_roslibs/`、`*.pdf`、`../IntelligentUAVChampionshipBase/basic_dev/{build,devel,install}`、`.claude/`、`.vscode/`、`__pycache__`。
