#!/bin/bash
# 启动 Claude Telegram Bot
# launchd 不支持 systemd 那样的 EnvironmentFile,所以在这里手动把 .env 读进环境变量
cd "$(dirname "$0")" || exit 1
set -a                 # 之后 source 进来的变量自动导出为环境变量
source .env
set +a
export PYTHONUNBUFFERED=1
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
exec venv/bin/python bot.py
