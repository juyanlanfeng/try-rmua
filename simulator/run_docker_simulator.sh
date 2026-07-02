#!/bin/bash
# Docker 离屏模式运行模拟器。用法: ./run_docker_simulator.sh [seed](默认 123)
# 镜像 simulator01 里已 bake GameConfig(IgnoreOverTime/IgnoreAllHitCollision=true)。
SEED="${1:-123}"
docker run -it --cpuset-cpus="0-9" -e Seed="$SEED" --rm --name sim01 --net host --gpus 'device=0' simulator01
