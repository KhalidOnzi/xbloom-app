from __future__ import annotations

import json
import os
import re
from typing import Any

import httpx

OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
TEXT_MODEL = "llama3.2"
VISION_MODEL = "llama3.2-vision"


class OllamaError(RuntimeError):
    pass


def _extract_json(text: str) -> dict[str, Any]:
    text = text.strip()
    try:
        value = json.loads(text)
        if isinstance(value, dict):
            return value
    except json.JSONDecodeError:
        pass
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        raise OllamaError("Ollama did not return JSON")
    value = json.loads(match.group(0))
    if not isinstance(value, dict):
        raise OllamaError("Ollama JSON was not an object")
    return value


def chat(prompt: str, images: list[str] | None = None, *, model: str | None = None) -> dict[str, Any]:
    chosen = model or (VISION_MODEL if images else TEXT_MODEL)
    message: dict[str, Any] = {"role": "user", "content": prompt}
    if images:
        message["images"] = images
    try:
        response = httpx.post(
            f"{OLLAMA_URL.rstrip('/')}/api/chat",
            json={
                "model": chosen,
                "messages": [message],
                "stream": False,
                "format": "json",
            },
            timeout=180.0,
        )
        response.raise_for_status()
    except httpx.HTTPStatusError as exc:
        body = exc.response.text[:240]
        if images and chosen != TEXT_MODEL:
            # llama3.2 is text-only; llama3.2-vision reads photos.
            raise OllamaError(
                f"Ollama vision model '{chosen}' failed ({exc.response.status_code}): {body}. "
                f"Run: ollama pull {VISION_MODEL}"
            ) from exc
        raise OllamaError(f"Ollama request failed ({exc.response.status_code}): {body}") from exc
    except httpx.ConnectError as exc:
        raise OllamaError(
            f"Cannot reach Ollama at {OLLAMA_URL}. Start it with: ollama serve"
        ) from exc

    payload = response.json()
    content = ((payload.get("message") or {}).get("content")) or ""
    return _extract_json(str(content))


def ping() -> dict[str, Any]:
    try:
        response = httpx.get(f"{OLLAMA_URL.rstrip('/')}/api/tags", timeout=5.0)
        response.raise_for_status()
        names = [str(item.get("name") or "") for item in (response.json().get("models") or [])]
        return {"ok": True, "url": OLLAMA_URL, "models": names, "textModel": TEXT_MODEL, "visionModel": VISION_MODEL}
    except Exception as exc:
        return {"ok": False, "url": OLLAMA_URL, "error": str(exc)}
