# Claude Telegram Bot 部署指南

这是一份完整的部署文档，覆盖项目的三个组件：主 Bot（`bot.py`）、Userbot（`userbot.py`）、Android 客户端（`android/`）。目标是在 Linux 服务器上运行 bot，通过 Telegram 和 Android App 远程控制 Claude CLI。

---

## 一、前置准备清单

### 1.1 服务器要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Linux（推荐 Ubuntu 22.04+/Debian 12+），需要 systemd |
| Python | 3.8+ |
| 内存 | 建议 2GB+（bot 有 2GB RSS 阈值会触发 GC） |
| 网络 | 能访问 `api.telegram.org`（443 端口） |
| 存储 | 预留 1GB+（上传文件缓存、会话数据） |

### 1.2 需要安装的软件

| 软件 | 用途 | 安装方式 |
|------|------|----------|
| **Claude CLI** | 核心 — bot 通过 subprocess 调用它 | `npm install -g @anthropic-ai/claude-code` |
| **Node.js 18+** | Claude CLI 依赖 | `curl -fsSL https://deb.nodesource.com/setup_18.x \| sudo bash - && sudo apt install nodejs` |
| **Python 3 + pip** | 运行 bot | `sudo apt install python3 python3-pip python3-venv` |
| **Tailscale**（可选） | Android App 通过 Tailscale VPN 连接 API | `curl -fsSL https://tailscale.com/install.sh \| sh` |
| **Ollama**（可选） | 仅 userbot 需要，本地 LLM | `curl -fsSL https://ollama.ai/install.sh \| sh` |

### 1.3 需要申请的账号/Token

| 项目 | 如何获取 | 用于 |
|------|----------|------|
| **Telegram Bot Token** | 在 Telegram 找 @BotFather → `/newbot` → 获取 token | 主 Bot |
| **你的 Chat ID** | 给 bot 发条消息，然后访问 `https://api.telegram.org/bot<TOKEN>/getUpdates`，找 `"chat":{"id":XXXXX}` | 权限控制 |
| **Anthropic API Key** | https://console.anthropic.com → API Keys | Claude CLI 调用 |
| **TG API ID + Hash**（可选） | https://my.telegram.org → API development tools | 仅 Userbot |
| **OpenAI API Key**（可选） | https://platform.openai.com | JustDoIt/Omni 编排中的 Codex 调用 |
| **Google AI API Key**（可选） | https://aistudio.google.com/apikey | Gemini 模型调用 |

---

## 二、主 Bot 部署步骤

### Step 1: 克隆代码

```bash
cd /opt  # 或你喜欢的目录
git clone <repo-url> claude-telegram-bot
cd claude-telegram-bot
```

### Step 2: 创建 Python 虚拟环境

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

> `requirements.txt` 包含：`requests>=2.28.0`, `fastapi>=0.100.0`, `uvicorn>=0.23.0`

### Step 3: 配置 Claude CLI

```bash
# 安装 Claude CLI
npm install -g @anthropic-ai/claude-code

# 登录/设置 API key
claude login
# 或手动设置
export ANTHROPIC_API_KEY=sk-ant-xxxxx

# 设置模型（bot.py 默认用 opus）
claude config set model claude-opus-4-5-20250514

# 验证安装
claude -p "hello" --output-format stream-json
```

**重要**：Claude CLI 必须在运行 bot 的用户 PATH 中可用。bot 调用的命令格式为：
```
claude -p --verbose --output-format stream-json --model opus --allowedTools Write,Edit,Bash,Read,... -- "prompt"
```

### Step 4: 创建 `.env` 配置文件

```bash
cat > .env << 'EOF'
# === 必填 ===
TELEGRAM_TOKEN=你的Bot_Token
ALLOWED_CHAT_IDS=你的Chat_ID          # 多个用逗号分隔：123,456
PROJECTS_DIR=/home/你的用户名          # Claude 工作的根目录

# === API 服务（Android App 连接用） ===
API_HOST=0.0.0.0                       # 或你的 Tailscale IP，如 100.x.x.x
API_PORT=8642
API_SECRET=一个随机密码                 # API 认证密钥，留空=不认证

# === 可选覆盖 ===
# CLAUDE_ALLOWED_TOOLS=Write,Edit,Bash,Read,Glob,Grep,Task,WebFetch,WebSearch,NotebookEdit,TodoWrite
# CODEX_MODEL=gpt-5.3-codex
# GEMINI_MODEL=gemini-3.1-pro-preview
EOF

chmod 600 .env
```

### Step 5: 手动测试运行

```bash
# 加载环境变量（bot.py 依赖 os.environ，不会自己读 .env）
export $(grep -v '^#' .env | xargs)

# 启动 bot
python bot.py
```

在 Telegram 中给 bot 发消息测试，看到回复即说明工作正常。`Ctrl+C` 停止。

### Step 6: 部署为 Systemd 服务

**方式 A — 使用自动脚本：**
```bash
./setup.sh
```
脚本会交互式引导你填写 Token 和 Chat ID，然后自动创建 systemd 服务。

**方式 B — 手动创建服务：**

```bash
# 生成 service 文件
cat > claude-telegram-bot.service << EOF
[Unit]
Description=Claude Telegram Bot
After=network.target

[Service]
Type=simple
User=$(whoami)
WorkingDirectory=$(pwd)
EnvironmentFile=$(pwd)/.env
Environment="PATH=$HOME/.local/bin:$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:/bin"
ExecStart=$(pwd)/venv/bin/python $(pwd)/bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 安装并启动
sudo cp claude-telegram-bot.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable claude-telegram-bot
sudo systemctl start claude-telegram-bot
```

### Step 7: 验证服务

```bash
# 查看状态
sudo systemctl status claude-telegram-bot

# 实时日志
journalctl -u claude-telegram-bot -f

# 重启
sudo systemctl restart claude-telegram-bot
```

---

## 三、Userbot 部署（可选）

Userbot 以你本人的 Telegram 账号发消息（非 bot 身份），使用本地 Ollama 模型自动回复。

### Step 1: 安装额外依赖

```bash
source venv/bin/activate
pip install telethon httpx
```

> 注意：`telethon` 和 `httpx` 未写在 `requirements.txt` 中，需手动安装。

### Step 2: 安装并配置 Ollama

```bash
# 安装 Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# 拉取模型
ollama pull gemma3:12b

# 验证运行
curl http://localhost:11434/api/generate -d '{"model":"gemma3:12b","prompt":"hello"}'
```

### Step 3: 添加 Userbot 环境变量到 `.env`

```bash
cat >> .env << 'EOF'

# === Userbot ===
TG_API_ID=你的API_ID                # 从 https://my.telegram.org 获取
TG_API_HASH=你的API_HASH
TARGET_CHAT_ID=目标聊天的ID          # 要自动回复的聊天
EOF
```

### Step 4: 首次运行（需要交互认证）

```bash
export $(grep -v '^#' .env | xargs)
python userbot.py
```

首次运行会提示输入手机号和验证码，认证后会生成 `userbot_session.session` 文件，后续运行不需要再认证。

### Step 5: 创建 Userbot Systemd 服务（可选）

与主 bot 类似，`ExecStart` 改为 `python userbot.py`。

---

## 四、Android 客户端部署（可选）

Android App 通过 WebSocket 连接到服务器 API，提供移动端聊天界面。

### 前置条件

- Android SDK 34+、Gradle 8.5、Kotlin 1.9.22
- 手机与服务器在同一网络（推荐 Tailscale VPN）
- 服务器 API 已启动（`API_HOST`/`API_PORT` 已配置）

### 构建 APK

```bash
cd android
./gradlew assembleDebug
# 产出：app/build/outputs/apk/debug/app-debug.apk
```

### 部署到手机

**方式 A — 使用部署脚本**（需配置 Termux + SSH）：

编辑 `android/deploy.sh` 中的变量：
```bash
PHONE_IP=你手机的IP     # Tailscale IP
PHONE_PORT=8022          # Termux SSH 端口
```

```bash
./android/deploy.sh
```

**方式 B — 手动安装：**

将 APK 传到手机并安装。在 App 设置中配置：
- Server URL: `ws://你的服务器IP:8642/ws`
- API Secret: 与 `.env` 中 `API_SECRET` 一致

### App 权限需求

- `INTERNET` — WebSocket 通信
- `POST_NOTIFICATIONS` — 消息通知
- `FOREGROUND_SERVICE` — 保持 WebSocket 连接

---

## 五、网络架构总览

```
┌─────────────┐     HTTPS (443)      ┌─────────────────┐
│  Telegram    │◄────────────────────►│   Linux Server   │
│  Cloud API   │    Long-polling      │                  │
└─────────────┘                       │  bot.py (主进程)  │
                                      │   ├─ Telegram轮询 │
┌─────────────┐  WS (8642)           │   ├─ API Server   │
│ Android App │◄─────────────────────►│   │  (FastAPI)    │
│ (Tailscale) │  Tailscale VPN       │   └─ Claude CLI   │
└─────────────┘                       │      (subprocess) │
                                      └─────────────────┘
```

---

## 六、更新与维护

```bash
# 拉取最新代码
cd /opt/claude-telegram-bot
git pull

# 更新依赖
source venv/bin/activate
pip install -r requirements.txt

# 重启服务
./update-service.sh
# 或手动：
sudo systemctl restart claude-telegram-bot
```

---

## 七、常用命令速查

| 操作 | 命令 |
|------|------|
| 查看 bot 状态 | `sudo systemctl status claude-telegram-bot` |
| 实时日志 | `journalctl -u claude-telegram-bot -f` |
| 重启 bot | `sudo systemctl restart claude-telegram-bot` |
| 停止 bot | `sudo systemctl stop claude-telegram-bot` |
| 健康检查 API | `curl http://localhost:8642/api/health` |
| API 文档 | 浏览器打开 `http://服务器IP:8642/docs` |

---

## 八、故障排查

| 问题 | 排查 |
|------|------|
| Bot 无响应 | 检查 `journalctl -u claude-telegram-bot -f`，确认 Token 正确 |
| Claude 调用失败 | 确认 `claude` 在 PATH 中：`which claude`，确认 API key 有效 |
| API/WebSocket 连不上 | 检查 `API_HOST` 是否绑定正确 IP，防火墙是否放行端口 |
| 内存占用高 | bot 有内置内存监控，超 2GB 自动 GC；可通过 `systemctl restart` 重启 |
| Userbot 认证失败 | 删除 `*.session` 文件，重新运行 `python userbot.py` 交互认证 |
