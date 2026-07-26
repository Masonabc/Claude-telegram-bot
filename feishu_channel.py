"""Feishu (Lark) channel adapter.

Runs a lark-oapi WebSocket long-connection client (no public URL needed) and
bridges Feishu events into the existing bot.py handlers. Outbound messages are
rendered as interactive cards (markdown + buttons) so they can be patched
in-place for streaming progress updates.

chat_key namespacing: Feishu chats use chat_id strings like
  "feishu:ou_xxx"  - p2p chat, keyed by the user's open_id
                     (menu events only carry open_id, so p2p must key on it)
  "feishu:oc_xxx"  - group chat, keyed by the group's chat_id
bot.py routes any chat_id with the "feishu:" prefix back to this module.

Not hot-reloadable: changing this file requires a full process restart
(loader.py only reloads the bot/api modules; the WS thread survives SIGHUP
and resolves bot.* handlers at call time, so reloaded bot code is picked up).
"""
import json
import os
import re
import threading
import time
import uuid
from collections import OrderedDict

import lark_oapi as lark
from lark_oapi.api.im.v1 import (
    CreateMessageRequest,
    CreateMessageRequestBody,
    P2ImMessageReceiveV1,
    PatchMessageRequest,
    PatchMessageRequestBody,
)
from lark_oapi.api.application.v6 import P2ApplicationBotMenuV6
from lark_oapi.event.callback.model.p2_card_action_trigger import (
    P2CardActionTrigger,
    P2CardActionTriggerResponse,
)

PREFIX = "feishu:"

FEISHU_APP_ID = os.environ.get("FEISHU_APP_ID", "")
FEISHU_APP_SECRET = os.environ.get("FEISHU_APP_SECRET", "")
FEISHU_ALLOWED_IDS = [s.strip() for s in os.environ.get("FEISHU_ALLOWED_IDS", "").split(",") if s.strip()]

MAX_CHUNK = 3500

_client = None  # lark.Client for REST calls, built lazily
_ws_client = None
_started = False
_start_lock = threading.Lock()

# Feishu event delivery is at-least-once — dedup by event_id (LRU ~500)
_seen_event_ids = OrderedDict()
_seen_lock = threading.Lock()

# Mirror bot.py's per-message edit throttle (EDIT_MIN_INTERVAL)
_last_edit_time = {}
_last_edit_cleanup = 0
EDIT_MIN_INTERVAL = 1.0


def _bot():
    # Resolve at call time so SIGHUP-reloaded bot code is used
    import bot
    return bot


def _raw_id(chat_id):
    return str(chat_id)[len(PREFIX):]


def _receive_id_type(raw):
    return "open_id" if raw.startswith("ou_") else "chat_id"


def is_allowed(chat_id):
    """Allowlist check. Empty FEISHU_ALLOWED_IDS denies everyone (safer default)."""
    if not FEISHU_ALLOWED_IDS:
        return False
    return _raw_id(chat_id) in FEISHU_ALLOWED_IDS


def _dedup(event_id):
    """Return True if this event_id was already processed."""
    if not event_id:
        return False
    with _seen_lock:
        if event_id in _seen_event_ids:
            return True
        _seen_event_ids[event_id] = True
        while len(_seen_event_ids) > 500:
            _seen_event_ids.popitem(last=False)
    return False


def _get_client():
    global _client
    if _client is None:
        _client = (
            lark.Client.builder()
            .app_id(FEISHU_APP_ID)
            .app_secret(FEISHU_APP_SECRET)
            .log_level(lark.LogLevel.WARNING)
            .build()
        )
    return _client


# ---------------------------------------------------------------------------
# Markdown conversion: Telegram-flavored -> lark_md
# ---------------------------------------------------------------------------

_CODE_SPLIT_RE = re.compile(r"(```[\s\S]*?```|`[^`\n]*`)")
# *bold* -> **bold**, but leave **already-bold** alone
_TG_BOLD_RE = re.compile(r"(?<!\*)\*([^*\n]+?)\*(?!\*)")
# _italic_ -> *italic*, lookarounds protect snake_case and file_paths
_TG_ITALIC_RE = re.compile(r"(?<![\w_])_([^_\n]+?)_(?![\w_])")


def tg_md_to_lark_md(text):
    parts = _CODE_SPLIT_RE.split(text)
    out = []
    for part in parts:
        if part.startswith("`"):
            out.append(part)  # code: pass through untouched
        else:
            part = _TG_BOLD_RE.sub(r"**\1**", part)
            part = _TG_ITALIC_RE.sub(r"*\1*", part)
            out.append(part)
    return "".join(out)


# ---------------------------------------------------------------------------
# Card building
# ---------------------------------------------------------------------------

def _buttons_from_reply_markup(reply_markup, chat_key):
    """Convert Telegram inline_keyboard rows to Feishu action elements.

    One action element per TG row keeps the vertical list layout.
    Button value carries callback_data plus chat_key/label so the card
    callback can reconstruct a Telegram-shaped callback_query.
    """
    elements = []
    for row in (reply_markup or {}).get("inline_keyboard", []):
        actions = []
        for btn in row:
            label = str(btn.get("text", ""))[:100]
            actions.append({
                "tag": "button",
                "text": {"tag": "plain_text", "content": label},
                "type": "default",
                "value": {"cb": btn.get("callback_data", ""), "ck": chat_key, "lb": label},
            })
        if actions:
            elements.append({"tag": "action", "actions": actions})
    return elements


def _build_card(text, reply_markup=None, chat_key=""):
    elements = [{"tag": "markdown", "content": tg_md_to_lark_md(text)}]
    if reply_markup:
        elements.extend(_buttons_from_reply_markup(reply_markup, chat_key))
    return {"config": {"wide_screen_mode": True}, "elements": elements}


# ---------------------------------------------------------------------------
# Outbound: send / edit
# ---------------------------------------------------------------------------

def send_message(chat_id, text, reply_markup=None, parse_mode="Markdown", retries=3, session_name=None):
    """Send text as interactive card(s). Returns the om_ message_id of the
    first chunk (so subsequent edit_message calls patch the right card)."""
    chat_key = str(chat_id)
    raw = _raw_id(chat_key)
    chunks = [text[i:i + MAX_CHUNK] for i in range(0, len(text), MAX_CHUNK)] or [""]
    first_msg_id = None

    for i, chunk in enumerate(chunks):
        markup = reply_markup if i == len(chunks) - 1 else None
        card = _build_card(chunk, markup, chat_key)
        msg_id = _create_message(raw, "interactive", json.dumps(card), retries=retries)
        if msg_id is None:
            # Card failed (e.g. markdown edge case) — fall back to plain text
            msg_id = _create_message(raw, "text", json.dumps({"text": chunk}), retries=1)
        if i == 0:
            first_msg_id = msg_id
    return first_msg_id


def send_input_card(chat_id, title, placeholder, cmd, default=""):
    """Send a card with a text input box. On submit, the typed text is appended
    to `cmd` and run as a command (e.g. cmd='/new' + input 'foo' -> '/new foo')."""
    chat_key = str(chat_id)
    raw = _raw_id(chat_key)
    card = {
        "config": {"wide_screen_mode": True, "update_multi": True},
        "elements": [
            {"tag": "markdown", "content": tg_md_to_lark_md(title)},
            {
                "tag": "input",
                "name": "arg",
                "default_value": default,
                "placeholder": {"tag": "plain_text", "content": placeholder},
                "value": {"inp": cmd, "ck": chat_key},
            },
        ],
    }
    return _create_message(raw, "interactive", json.dumps(card))


def _create_message(raw_receive_id, msg_type, content, retries=3):
    try:
        client = _get_client()
    except Exception as e:
        print(f"[FEISHU] client init failed: {e}", flush=True)
        return None
    req = (
        CreateMessageRequest.builder()
        .receive_id_type(_receive_id_type(raw_receive_id))
        .request_body(
            CreateMessageRequestBody.builder()
            .receive_id(raw_receive_id)
            .msg_type(msg_type)
            .content(content)
            .build()
        )
        .build()
    )
    for attempt in range(retries):
        try:
            resp = client.im.v1.message.create(req)
            if resp.success():
                return resp.data.message_id
            print(f"[FEISHU] send failed code={resp.code} msg={resp.msg}", flush=True)
            return None  # API error — not retryable
        except Exception as e:
            if attempt < retries - 1:
                wait = 2 ** attempt
                print(f"[FEISHU] send retry {attempt+1}/{retries} after {wait}s: {e}", flush=True)
                time.sleep(wait)
            else:
                print(f"[FEISHU] send failed after {retries} attempts: {e}", flush=True)
    return None


def edit_message(chat_id, message_id, text, parse_mode="Markdown", force=False):
    """Patch an interactive card in place (streaming progress + final output).
    Falls back to a new message when a forced edit fails."""
    global _last_edit_cleanup
    if not message_id:
        if force:
            send_message(chat_id, text)
        return

    now = time.time()
    if not force and message_id in _last_edit_time:
        if now - _last_edit_time[message_id] < EDIT_MIN_INTERVAL:
            return
    _last_edit_time[message_id] = now

    if now - _last_edit_cleanup > 300:
        _last_edit_cleanup = now
        cutoff = now - 600
        for k in [k for k, v in _last_edit_time.items() if v < cutoff]:
            del _last_edit_time[k]

    if len(text) > MAX_CHUNK:
        text = text[:MAX_CHUNK - 3] + "..."

    card = _build_card(text)
    req = (
        PatchMessageRequest.builder()
        .message_id(message_id)
        .request_body(PatchMessageRequestBody.builder().content(json.dumps(card)).build())
        .build()
    )
    max_attempts = 3 if force else 1
    for attempt in range(max_attempts):
        try:
            resp = _get_client().im.v1.message.patch(req)
            if resp.success():
                return
            print(f"[FEISHU] patch failed code={resp.code} msg={resp.msg} (msg_id={message_id})", flush=True)
            break  # API error — not retryable
        except Exception as e:
            print(f"[FEISHU] patch exception (msg_id={message_id}, attempt {attempt+1}/{max_attempts}): {e}", flush=True)
            if attempt < max_attempts - 1:
                time.sleep(2)
    if force:
        # Final output must reach the user — send as a new message
        send_message(chat_id, text)


# ---------------------------------------------------------------------------
# Inbound event handlers
# ---------------------------------------------------------------------------

_MENTION_RE = re.compile(r"@_user_\d+\s*")


def _dispatch(fn, *args):
    """Run handler work off the lark ws dispatcher thread so slow handlers
    (Claude runs, disk scans) never block the WS heartbeat."""
    def run():
        try:
            fn(*args)
        except Exception as e:
            import traceback
            print(f"[FEISHU] handler error: {e}", flush=True)
            traceback.print_exc()
    threading.Thread(target=run, daemon=True).start()


def _handle_text(chat_key, text):
    bot = _bot()
    text = text.strip()
    if not text:
        return
    if text.startswith("/"):
        if bot.handle_command(chat_key, text):
            return
    bot.handle_message(chat_key, text)


def _download_audio(message_id, file_key):
    """Download a voice message's audio (opus) bytes via im.v1 message resource."""
    from lark_oapi.api.im.v1 import GetMessageResourceRequest
    req = (GetMessageResourceRequest.builder()
           .message_id(message_id).file_key(file_key).type("file").build())
    try:
        resp = _get_client().im.v1.message_resource.get(req)
        if resp.success() and resp.file:
            return resp.file.read()
        print(f"[FEISHU] audio download failed code={getattr(resp,'code',None)} msg={getattr(resp,'msg',None)}", flush=True)
    except Exception as e:
        print(f"[FEISHU] audio download exception: {e}", flush=True)
    return None


def _handle_audio(chat_key, message_id, content_json):
    """Voice message -> download -> transcode -> STT -> echo text -> run as a message."""
    try:
        file_key = json.loads(content_json).get("file_key")
    except Exception:
        file_key = None
    if not file_key:
        send_message(chat_key, "⚠️ 无法解析语音消息")
        return

    audio = _download_audio(message_id, file_key)
    if not audio:
        send_message(chat_key, "❌ 语音下载失败 (检查 im:resource 权限)")
        return

    import transcribe
    text = transcribe.transcribe_bytes(audio, suffix=".opus")
    if not text:
        send_message(chat_key, "❌ 没听清 / 识别失败,请再说一遍")
        return

    print(f"[FEISHU] voice transcribed for {chat_key}: {text[:80]!r}", flush=True)
    send_message(chat_key, f"🗣️ *识别结果*\n> {text}")
    _handle_text(chat_key, text)


def _on_message(data: P2ImMessageReceiveV1):
    if _dedup(data.header.event_id):
        return
    msg = data.event.message
    sender_open_id = data.event.sender.sender_id.open_id
    if msg.chat_type == "p2p":
        chat_key = f"{PREFIX}{sender_open_id}"
    else:
        chat_key = f"{PREFIX}{msg.chat_id}"

    if not is_allowed(chat_key):
        print(f"[FEISHU] unauthorized message from open_id={sender_open_id} "
              f"chat={msg.chat_id} ({msg.chat_type}) — add to FEISHU_ALLOWED_IDS to allow", flush=True)
        return

    if msg.message_type == "audio":
        _dispatch(_handle_audio, chat_key, msg.message_id, msg.content)
        return

    if msg.message_type != "text":
        _dispatch(send_message, chat_key, "⚠️ 暂只支持文本和语音消息 (图片/文件开发中)")
        return

    try:
        text = json.loads(msg.content).get("text", "")
    except Exception:
        return
    text = _MENTION_RE.sub("", text)
    print(f"[FEISHU] message from {chat_key}: {text[:80]!r}", flush=True)
    _dispatch(_handle_text, chat_key, text)


def _on_menu(data: P2ApplicationBotMenuV6):
    if _dedup(data.header.event_id):
        return
    event_key = (data.event.event_key or "").strip()
    open_id = data.event.operator.operator_id.open_id
    chat_key = f"{PREFIX}{open_id}"
    print(f"[FEISHU] menu click: event_key={event_key!r} from {chat_key}", flush=True)
    if not is_allowed(chat_key):
        print(f"[FEISHU] unauthorized menu click from open_id={open_id}", flush=True)
        return
    if not event_key:
        return
    cmd = event_key if event_key.startswith("/") else f"/{event_key}"
    _dispatch(_handle_text, chat_key, cmd)


def _on_card_action(data: P2CardActionTrigger) -> P2CardActionTriggerResponse:
    value = data.event.action.value or {}
    chat_key = value.get("ck", "") or f"{PREFIX}{data.event.operator.open_id}"

    if _dedup(data.header.event_id):
        return P2CardActionTriggerResponse({})

    if not is_allowed(chat_key):
        return P2CardActionTriggerResponse({
            "toast": {"type": "error", "content": "Unauthorized"}
        })

    # Input-box submission: append typed text to the command and run it
    if "inp" in value:
        cmd = value["inp"]
        typed = (data.event.action.input_value or "").strip()
        print(f"[FEISHU] input submit: cmd={cmd!r} text={typed!r} chat={chat_key}", flush=True)
        if not typed:
            return P2CardActionTriggerResponse({"toast": {"type": "error", "content": "未输入内容"}})
        full = f"{cmd} {typed}"
        _dispatch(_bot().handle_command, chat_key, full)
        ack_card = {
            "config": {"wide_screen_mode": True},
            "elements": [{"tag": "markdown", "content": f"📨 已提交: `{full}`"}],
        }
        return P2CardActionTriggerResponse({
            "toast": {"type": "success", "content": "已提交"},
            "card": {"type": "raw", "data": ack_card},
        })

    cb = value.get("cb", "")
    label = value.get("lb", "")
    print(f"[FEISHU] card action: cb={cb!r} label={label!r} chat={chat_key}", flush=True)

    synth = {
        "id": f"{PREFIX}{uuid.uuid4()}",
        "data": cb,
        "message": {
            "chat": {"id": chat_key},
            "message_id": data.event.context.open_message_id,
        },
    }
    _dispatch(_bot().handle_callback_query, synth)

    # Replace the card with a button-less ack (native UX, prevents double-click)
    ack_card = {
        "config": {"wide_screen_mode": True},
        "elements": [{"tag": "markdown", "content": f"✅ 已选择: **{label}**"}],
    }
    return P2CardActionTriggerResponse({
        "toast": {"type": "success", "content": f"已选择: {label}"[:30]},
        "card": {"type": "raw", "data": ack_card},
    })


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

def start():
    """Start the WS long-connection client in a daemon thread. No-op when
    FEISHU_APP_ID/SECRET are not configured or when already started."""
    global _ws_client, _started
    with _start_lock:
        if _started:
            return
        if not FEISHU_APP_ID or not FEISHU_APP_SECRET:
            print("[FEISHU] FEISHU_APP_ID/FEISHU_APP_SECRET not set — Feishu channel disabled", flush=True)
            return
        _started = True

    handler = (
        lark.EventDispatcherHandler.builder("", "")
        .register_p2_im_message_receive_v1(_on_message)
        .register_p2_application_bot_menu_v6(_on_menu)
        .register_p2_card_action_trigger(_on_card_action)
        .build()
    )
    _ws_client = lark.ws.Client(
        FEISHU_APP_ID,
        FEISHU_APP_SECRET,
        event_handler=handler,
        log_level=lark.LogLevel.INFO,
        auto_reconnect=True,
    )

    def run():
        try:
            _ws_client.start()  # blocks; SDK auto-reconnects
        except Exception as e:
            print(f"[FEISHU] ws client crashed: {e}", flush=True)

    threading.Thread(target=run, daemon=True, name="feishu-ws").start()
    if not FEISHU_ALLOWED_IDS:
        print("[FEISHU] Warning: FEISHU_ALLOWED_IDS is empty — all Feishu users will be denied", flush=True)
    print("[FEISHU] WebSocket long-connection client starting", flush=True)
