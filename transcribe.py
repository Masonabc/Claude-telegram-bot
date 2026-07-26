"""Shared speech-to-text module — channel-agnostic (Feishu, Telegram, ...).

Runs faster-whisper in-process (same venv as the bot), so the model stays
resident in memory: only the first transcription pays the load cost, the rest
are fast. Hand it audio bytes in any ffmpeg/PyAV-decodable format (opus/ogg/
m4a/wav/...) and get text back — usable by any message channel.

Env overrides:
  WHISPER_MODEL    model size: tiny/base/small/medium (default: base)
  WHISPER_DEVICE   cpu/cuda (default: cpu)
  WHISPER_COMPUTE  compute type (default: int8)
"""
import os
import threading
import tempfile

WHISPER_MODEL = os.environ.get("WHISPER_MODEL", "base")
WHISPER_DEVICE = os.environ.get("WHISPER_DEVICE", "cpu")
WHISPER_COMPUTE = os.environ.get("WHISPER_COMPUTE", "int8")

_model = None
_model_lock = threading.Lock()


def _get_model():
    """Lazily load and cache the Whisper model (first call pays ~2s)."""
    global _model
    if _model is None:
        with _model_lock:
            if _model is None:
                from faster_whisper import WhisperModel
                _model = WhisperModel(WHISPER_MODEL, device=WHISPER_DEVICE, compute_type=WHISPER_COMPUTE)
    return _model


def transcribe_file(path, language=None):
    """Transcribe an audio file. Returns recognized text, or None on failure/empty."""
    try:
        model = _get_model()
        segments, info = model.transcribe(
            path, beam_size=1, language=language,
            initial_prompt="以下是简体中文普通话的语音内容。",
        )
        text = "".join(s.text for s in segments).strip()
        return text or None
    except Exception as e:
        print(f"[TRANSCRIBE] error: {e}", flush=True)
        return None


def transcribe_bytes(audio_bytes, suffix=".opus", language=None):
    """Transcribe raw audio bytes in any decodable format (opus/ogg/m4a/wav/...)."""
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
            f.write(audio_bytes)
            tmp = f.name
        return transcribe_file(tmp, language=language)
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def available():
    """True if faster-whisper is importable in this environment."""
    try:
        import faster_whisper  # noqa: F401
        return True
    except Exception:
        return False
