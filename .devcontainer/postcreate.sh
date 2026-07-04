#!/bin/bash
# postCreateCommand —— 仅在容器首次创建时跑一次。
# 职责:把 ROS + airsim_ros 的 source 写进 /root/.bashrc,并预编译 airsim_ros msg 包。
#     安装 Claude Code CLI 并配置 DeepSeek 接入。
set -e

ROS_SETUP="/opt/ros/noetic/setup.bash"
WS="/workspace/IntelligentUAVChampionshipBase/basic_dev"
DEV_SETUP="$WS/devel/setup.bash"

# 1) 往 /root/.bashrc 追加 source 链(每个新终端都自动有 ROS 环境 + 自定义 msg)
#    用标记块避免重复追加
MARK="# >>> rmua-dev ros env >>>"
if ! grep -qF "$MARK" /root/.bashrc 2>/dev/null; then
  cat >> /root/.bashrc <<EOF

$MARK
source $ROS_SETUP
[ -f $DEV_SETUP ] && source $DEV_SETUP
export ROS_MASTER_URI=http://localhost:11311
# <<< rmua-dev ros env <<<
EOF
  echo "[postcreate] 已写入 .bashrc source 链"
fi

# 2) 预编译 airsim_ros(让 devel/setup.bash 生成,供 rqt/rviz/rosservice 用自定义 msg)
if [ ! -f "$DEV_SETUP" ]; then
  echo "[postcreate] 首次构建 airsim_ros..."
  cd "$WS"
  . "$ROS_SETUP"
  catkin_make --only-pkg-with-deps airsim_ros
  echo "[postcreate] airsim_ros 构建完成"
else
  echo "[postcreate] airsim_ros 已构建过,跳过"
fi

# ============================================================
# 3) 写入 DeepSeek 接入配置(供 Claude Code 插件读取)
#    环境变量已在 devcontainer.json 的 containerEnv 中设置,
#    此处额外写入 settings.json 作为双保险。
# ============================================================
CLAUDE_SETTINGS="/root/.claude/settings.json"

if [ ! -f "$CLAUDE_SETTINGS" ]; then
  mkdir -p /root/.claude
  cat > "$CLAUDE_SETTINGS" <<'CLAUDE_EOF'
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "DEEPSEEK_API_KEY_PLACEHOLDER",
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_MODEL": "deepseek-v4-pro",
    "CLAUDE_CODE_EFFORT_LEVEL": "max",
    "CLAUDE_CODE_SUBAGENT_MODEL": "deepseek-v4-flash"
  },
  "theme": "auto"
}
CLAUDE_EOF
  echo "[postcreate] DeepSeek 配置已写入 $CLAUDE_SETTINGS"
else
  echo "[postcreate] Claude Code 配置已存在,跳过"
fi

echo "[postcreate] 完成。新终端自动 source ROS,Claude Code 可用。"
