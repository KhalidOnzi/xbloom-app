"""Unofficial xBloom account client for the user's own login.

Ported from the published MIT xbloom-ble cloud module. Creates recipes in
the official app library and never starts a brew.
"""

from __future__ import annotations

import base64
import json
import math
import time
from typing import Any

import httpx
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import load_der_public_key

BASE_URL = "https://client-api.xbloom.com/"
SKEY = "testskey"
INTERFACE_VERSION = 20240918
RSA_PUBLIC_KEY_B64 = (
    "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC4LF40GZ72SdhMyl765K/i4nY5"
    "CPcHz2Q1IKWKZ9S79xmK7G8pUhbVf4EZLvnNF1+9IvOFQUKV5Z7ZNNviqSpnql9"
    "tAT+8+J/He0R7pcirvVSxgdr2i9V/C/gmqAEZ5qVTzRnd3uWdFoKzPdEBxP0Ipor"
    "J1VBbCv90yBSOhVxO+QIDAQAB"
)
RSA_MAX_PLAIN_BLOCK = 117
PATTERN_CODES = {"center": 1, "circular": 2, "ring": 2, "spiral": 2}


class XBloomError(RuntimeError):
    pass


def _rsa_encrypt(plaintext: bytes) -> bytes:
    der = base64.b64decode(RSA_PUBLIC_KEY_B64)
    pub = load_der_public_key(der)
    blocks = max(1, math.ceil(len(plaintext) / RSA_MAX_PLAIN_BLOCK))
    out = bytearray()
    for i in range(blocks):
        chunk = plaintext[i * RSA_MAX_PLAIN_BLOCK : (i + 1) * RSA_MAX_PLAIN_BLOCK]
        out.extend(pub.encrypt(chunk, padding.PKCS1v15()))
    return bytes(out)


def encrypt_form(form: dict[str, Any]) -> str:
    raw = json.dumps(form, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return base64.b64encode(_rsa_encrypt(raw)).decode("ascii")


def _post(endpoint: str, form: dict[str, Any]) -> dict[str, Any]:
    body = encrypt_form(form)
    response = httpx.post(
        BASE_URL + endpoint,
        content=body.encode("utf-8"),
        headers={
            "Content-Type": "application/json; charset=utf-8",
            "Accept": "application/json, text/plain, */*",
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
        },
        timeout=20.0,
    )
    response.raise_for_status()
    data = response.json()
    if data.get("result") != "success":
        raise XBloomError(str(data.get("info") or data.get("error") or data))
    return data


def login(email: str, password: str) -> dict[str, Any]:
    data = _post(
        "tMemberLogin.thtml",
        {
            "interfaceVersion": INTERFACE_VERSION,
            "skey": SKEY,
            "phoneType": "iOS",
            "clientType": 2,
            "languageType": 1,
            "email": email,
            "password": password,
            "jpushId": "",
        },
    )
    member = data.get("member") or {}
    member_id = int(member.get("tableId") or 0)
    token = str(data.get("token") or "")
    if not member_id or not token:
        raise XBloomError("login succeeded but token was missing")
    return {"email": email, "memberId": member_id, "token": token}


def _auth(session: dict[str, Any]) -> dict[str, Any]:
    return {
        "interfaceVersion": INTERFACE_VERSION,
        "skey": SKEY,
        "phoneType": "iOS",
        "memberId": session["memberId"],
        "clientType": 2,
        "languageType": 1,
        "token": session["token"],
    }


def list_recipes(session: dict[str, Any]) -> list[dict[str, Any]]:
    data = _post(
        "tuMyTeaRecipeCreated.tuhtml",
        {**_auth(session), "pageNumber": 1, "countPerPage": 100, "adaptedModel": 0},
    )
    return list(data.get("list") or [])


def recipe_to_cloud(recipe: dict[str, Any], name: str) -> dict[str, Any]:
    pours = []
    for index, pour in enumerate(recipe.get("pours") or []):
        pattern = str(pour.get("pattern") or "spiral")
        pours.append(
            {
                "theName": "Bloom" if index == 0 else pour.get("name") or f"Pour {index + 1}",
                "volume": float(pour.get("volumeMl") or 0),
                "temperature": float(pour.get("temperatureC") or 92),
                "flowRate": float(pour.get("flowMlPerS") or 3.2),
                "pattern": PATTERN_CODES.get(pattern, 2),
                "pausing": int(pour.get("pauseSeconds") or 0),
                "isEnableVibrationBefore": 2,
                "isEnableVibrationAfter": 1 if pour.get("agitation") else 2,
            }
        )
    return {
        "theName": name,
        "dose": float(recipe.get("doseG") or 15),
        "grandWater": float(recipe.get("ratio") or 16),
        "grinderSize": float(recipe.get("grind") or 58),
        "rpm": int(recipe.get("rpm") or 100),
        "cupType": 2,
        "adaptedModel": 2,
        "isEnableBypassWater": 2,
        "isSetGrinderSize": 1,
        "theColor": "#C9D5B8",
        "theSubsetId": 0,
        "bypassTemp": 85.0,
        "bypassVolume": 0.0,
        "subSetType": 2,
        "appPlace": [4],
        "createTimeStamp": int(time.time() * 1000),
        "isShortcuts": 2,
        "pourDataJSONStr": json.dumps(pours, ensure_ascii=False, separators=(",", ":")),
    }


def sync_recipe(session: dict[str, Any], recipe: dict[str, Any]) -> dict[str, Any]:
    name = str(recipe.get("name") or "Untitled coffee").strip()
    if not name.startswith("BloomRecipe · "):
        name = "BloomRecipe · " + name
    payload = {**_auth(session), **recipe_to_cloud(recipe, name)}
    existing = next((row for row in list_recipes(session) if str(row.get("theName") or "") == name), None)
    if existing:
        payload["tableId"] = existing["tableId"]
        data = _post("tuRecipeUpdate.tuhtml", payload)
        return {"action": "updated", "tableId": existing.get("tableId"), "name": name, "raw": data}
    data = _post("tuRecipeAdd.tuhtml", payload)
    return {"action": "added", "tableId": data.get("tableId"), "name": name, "raw": data}
