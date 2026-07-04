# AGENTS.md

High-signal guidance for AI agents working in this repo (`~/RMUA`). Every line is something an agent would likely get wrong without it.

## What this repo is

A personal workspace for **RMUA 2026** autonomous drone racing: a prebuilt UE4+AirSim simulator + a catkin-based competitor algorithm workspace. Host is Ubuntu 22.04 with Intel+NVIDIA Optimus. The simulator binary links **ROS1 Noetic**; the host may run Humble, in which case ROS CLI work happens inside the `simulator01` container (see `simulator/scripts/ros.sh`).

There is **no compilable simulator source** anywhere in this repo — "development" means configuring the sim, building Docker images, and writing the competitor ROS algorithm against the `/airsim_node/` topic interface.

## Top-level layout (each dir has a different role; do not conflate)

| Dir | Role | Tracked? |
|---|---|---|
| `simulator/` | Prebuilt UE binary wrapper: launch scripts, Dockerfiles, AirSim `settings.json`, `GameConfig.json`, docs. **Has its own `AGENTS.md` — read it before touching the sim.** | source tracked; `Build/` ignored |
| `IntelligentUAVChampionshipBase/` | Official scaffold + self-developed algorithm. The catkin workspace is `basic_dev/` (`src/{airsim_ros,basic_dev,controller,odometry,imu_gps_odometry}`). | source tracked; `build/devel/install` ignored |
| `rmua_roslibs/` | ROS1 Noetic runtime libs extracted from the `simulator01` image, for running the UE binary natively on the host. | **gitignored** — rebuild via `simulator/scripts/extract_roslibs.sh` |

Git operations happen at the repo root (`~/RMUA`), not inside subdirs. Only `main` branch is used.

## Artifacts that are NOT in git (recover the right way)

- `simulator/Build/` — 2G UE binary from `simulator_12.0.0.5.zip`. Recover by downloading + unzipping the zip (see `simulator/README.md`), **not** `git show`.
- `rmua_roslibs/` — rebuild with `simulator/scripts/extract_roslibs.sh`.
- `basic_dev/{build,devel,install}` — catkin build outputs.

## Running the sim — pick the right flow

- **Standalone host with ROS Noetic installed:** `simulator/run_simulator.sh <seed>` (rendered) or `run_simulator_offscreen.sh <seed>`.
- **Docker (offscreen only):** `docker build -t simulator01 simulator/` then `simulator/run_docker_simulator.sh <seed>`. Requires `Build/` present locally (the Dockerfile `ADD`s it, despite what `simulator/CLAUDE.md` claims — that file is stale).
- **Mixed-GPU Optimus laptop (this host's case):** do **not** use `run_docker_simulator_render.sh` — Vulkan can't present on Optimus and UE crashes at the swapchain. Use the host-native flow:
  ```bash
  simulator/scripts/extract_roslibs.sh        # one-time
  simulator/scripts/run_roscore.sh            # roscore in container, --net host
  simulator/scripts/run_host_window.sh <seed> # UE natively, borrows ROS libs
  simulator/scripts/run_viz.sh                # rviz, software-rendered
  ```
  Only one `RMUA-Linux-Shipping` may run at a time (`VK_ERROR_DEVICE_LOST` otherwise).

Full sim/ROS details, gotchas, and config tables are in **`simulator/AGENTS.md`** — that file is the authoritative source for the simulator; trust it over `simulator/CLAUDE.md`.

## Building the competitor algorithm (catkin workspace)

```bash
cd IntelligentUAVChampionshipBase/basic_dev
source /opt/ros/noetic/setup.bash
catkin_make --only-pkg-with-deps airsim_ros   # build the msg package first
source devel/setup.bash
catkin_make --only-pkg-with-deps basic_dev    # then the node
```

The `basic_dev/Dockerfile` does exactly this sequence (build `airsim_ros`, source, build `basic_dev`); mirror it for local builds. `run_basic_dev.sh` runs the resulting image with `--net host` so the container talks to the host's roscore.

## Cross-cutting integration gotchas (each silently breaks the algorithm)

1. **Velocity topic is `drone_1/vel_body_cmd`, NOT `vel_cmd_body_frame`.** The scaffold's `basic_dev/src/basic_dev.cpp` still advertises the old name — commands go nowhere. Fix it before relying on the scaffold.
2. **The scaffold `basic_dev.cpp` is stale against the current `VelCmd.msg`.** It accesses `velcmd.twist.linear.*`, but `airsim_ros/msg/VelCmd.msg` is the 6-field version (`header, vx, vy, vz, yawRate, va, stop`) — there is no `twist` member. **`basic_dev.cpp` will not compile as-is.** The correct message is also mirrored at `simulator/VelCmdmsg/VelCmd.msg`.
3. **Use the IMU timestamp (`/airsim_node/drone_1/imu/imu`) as the global clock**, not wall-clock — they differ by ~20s and the sim drops "expired" messages.
4. **Body frame is NED** (x=front, y=right, z=down ⇒ up = `-vz`). `va` = accel cap 0–8 (0 means no accel, avoid). `stop=1` = emergency hover.
5. **Dev flags must be on for algorithm work:** `Build/LinuxNoEditor/RMUA/Content/Configs/GameConfig.json` → `IgnoreAllHitCollision=true`, `IgnoreOverTime=true`, then restart UE. Without them the race ends on timeout/collision and the drone then ignores all commands (symptom: works after reset, freezes after ~10s).
6. **Control interface locks to whichever type (PWM vs VEL) the sim receives first** in a run; the other is silently ignored. Don't mix `vel_body_cmd` and `rotor_pwm_cmd` in one run. Command rate ≤100 Hz.
7. **Rotor index order** (PWM cmd + feedback): `0:front-right, 1:back-left, 2:front-left, 3:back-right`.

Full topic/service list: `simulator/README.md` ("ros数据交互") and `simulator/AGENTS.md`.

## Submission image constraints (for the competitor image, not this dev repo)

- <15 GB, **no GUI / no X11**, program must auto-start on container run.
- Do **not** set `ROS_IP` or `ROS_MASTER_URI` in the image — the server assigns them externally, hardcoding breaks connectivity.
- Must leave the start trigger zone within 30 s of deploy; must not self-exit.

## Verification (no lint / test / typecheck exists)

The only "build" is `docker build` / `catkin_make`. The only "test" is running the sim and checking data flows:

```bash
source /opt/ros/noetic/setup.bash   # or use simulator/scripts/ros.sh on a Humble host
rostopic list
rostopic hz /airsim_node/drone_1/imu/imu
```

If `rqt`/`rviz` report missing message types, source the `airsim_ros` package from `basic_dev/devel/setup.bash` — the `airsim_ros` messages are defined in the algorithm workspace, not in the simulator.
