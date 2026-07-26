# 飞书 (Feishu) 端配置指南

飞书端通过 **WebSocket 长连接** 接入(`feishu_channel.py` + lark-oapi SDK),无需公网回调地址,适合本机 Mac 部署。与 Telegram 并行运行,复用全部命令与会话逻辑。

## 一、飞书开放平台配置

1. [开放平台](https://open.feishu.cn/) → 创建**企业自建应用**,记下 **App ID** / **App Secret**
2. 添加应用能力 → **机器人**
3. 权限管理 → 开通:
   - `im:message`(读取消息)
   - `im:message:send_as_bot`(发送消息)
4. 事件与回调 → 订阅方式选 **长连接**,添加事件:
   - `im.message.receive_v1`(接收消息)
   - `application.bot.menu_v6`(机器人菜单)
5. 回调配置 → 卡片回传交互(`card.action.trigger`)同样选 **长连接**
6. 机器人 → **自定义菜单**,event_key 直接填命令名(不带 `/`):

   | 一级菜单 | 子项 event_key |
   |---------|----------------|
   | 会话 | `sessions` / `csessions` / `resume` / `new` / `status` |
   | 任务 | `cancel` / `approve` / `plan` |
   | 帮助 | `help` |

7. 版本管理与发布 → 创建版本并**发布**(可用范围包含自己;菜单/权限变更后需重新发布)

## 二、本机配置(launchd 部署)

本机 bot 由 launchd 管理,环境变量写在 `~/Library/LaunchAgents/com.claude.telegram-bot.plist` 的 `EnvironmentVariables` 里(**不是 .env**):

```xml
<key>FEISHU_APP_ID</key><string>cli_xxxxxxxx</string>
<key>FEISHU_APP_SECRET</key><string>xxxxxxxx</string>
<key>FEISHU_ALLOWED_IDS</key><string>ou_xxxxxxxx</string>
```

`FEISHU_ALLOWED_IDS` 逗号分隔,`ou_` 开头 = 私聊用户 open_id,`oc_` 开头 = 群 chat_id。**留空则拒绝所有飞书用户**(安全默认)。

然后重启:`launchctl kickstart -k gui/$UID/com.claude.telegram-bot`

> Linux/systemd 部署则把这三个变量加进 `.env`(见 DEPLOY.md),同样需完整重启进程。

## 三、获取自己的 open_id

首次配置时白名单为空,给机器人发一条消息,bot 不会回复,但日志会打印:

```
[FEISHU] unauthorized message from open_id=ou_xxxx chat=oc_xxxx (p2p) — add to FEISHU_ALLOWED_IDS to allow
```

把 `ou_xxxx` 填入 `FEISHU_ALLOWED_IDS` 重启即可。日志位置:`~/Library/Logs/claude-telegram-bot.log`。

## 四、验证清单

1. 重启后日志出现 `[FEISHU] WebSocket long-connection client starting`
2. 私聊发 "hello" → 收到卡片回复
3. `/new <项目名>` → `data/sessions.json` 出现 `"feishu:ou_..."` key
4. 发任务 → 「⏳ Thinking...」卡片被原地刷新,最终结果出现在同一张卡片
5. `/resume` → 卡片按钮,点击后卡片变「✅ 已选择」并恢复会话
6. 点自定义菜单「sessions」≡ 输入 `/sessions`
7. Telegram 端同时收发正常(回归)

## 已知限制(Phase 2 待做)

- 飞书端发图片/文件给 bot:暂不支持(会提示)
- `/file` 从 bot 下载文件:暂不支持(会提示)
- 飞书会话不出现在 mission-control WebSocket(api.py)中
- 修改 `feishu_channel.py` 本身需完整重启(不支持热重载)
