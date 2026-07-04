#!/bin/bash
# postStartCommand —— 每次容器启动时跑(含首次创建后)。
# 职责:若 11311 端口没人在听,就在后台起 roscore(--net host 下宿主 UE 也能连)。
#   不强占:已有 roscore 则跳过,避免与 run_roscore.sh / 手动 roscore 冲突。

if ss -tlnp 2>/dev/null | grep -q ':11311'; then
  echo "[poststart] 11311 已有监听,跳过 roscore 启动。"
else
  echo "[poststart] 启动 roscore(后台)..."
  nohup roscore > /tmp/roscore.log 2>&1 &
  sleep 2
  if ss -tlnp 2>/dev/null | grep -q ':11311'; then
    echo "[poststart] roscore 已上线 (日志 /tmp/roscore.log)"
  else
    echo "[poststart] ⚠ roscore 未起来,看 /tmp/roscore.log"
  fi
fi
