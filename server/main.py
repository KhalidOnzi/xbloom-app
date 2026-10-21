from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from ollama_client import OllamaError, TEXT_MODEL, VISION_MODEL, chat, ping
from xbloom import XBloomError, login, sync_recipe

app = FastAPI(title="BloomRecipe API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

sessions: dict[str, dict[str, Any]] = {}


class AnalyzeBody(BaseModel):
    frontJpegB64: str
    backJpegB64: str | None = None


class RefineBody(BaseModel):
    profile: dict[str, Any]
    recipe: dict[str, Any]


class LoginBody(BaseModel):
    email: str
    password: str


class SyncBody(BaseModel):
    email: str
    password: str
    recipe: dict[str, Any] = Field(default_factory=dict)


ANALYZE_PROMPT = """Read this coffee bag label. Return JSON only with keys:
name, roaster, origin, region, variety, process, roast, tastingNotes, roastDate, altitude, extraNotes.
process must be one of: washed, natural, honey, anaerobic, other, unknown.
roast must be one of: light, mediumLight, medium, mediumDark, dark, unknown.
Use empty strings when a field is not visible. Do not invent a famous roaster if the bag is unreadable."""


@app.get("/health")
def health() -> dict[str, Any]:
    return {"ok": True, "ollama": ping()}


@app.post("/analyze")
def analyze(body: AnalyzeBody) -> dict[str, Any]:
    images = [body.frontJpegB64]
    if body.backJpegB64:
        images.append(body.backJpegB64)
    try:
        return chat(ANALYZE_PROMPT, images, model=VISION_MODEL)
    except OllamaError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.post("/refine")
def refine(body: RefineBody) -> dict[str, Any]:
    prompt = f"""You refine xBloom Studio Omni Dripper recipes. Stay inside these hard limits:
dose 5-18 g, grind 1-80, pour temp 40-95 C, flow 3.0-3.5 ml/s, rpm 60-120 in steps of 10,
pause 0-255 s, patterns spiral|ring|center, agitation only with spiral.
Pour volumes MUST sum to dose * ratio (rounded to whole ml).

Return JSON only:
{{"grind": <int>, "rpm": <int>, "rationale": "<2-4 sentences>", "pours": [...]}}

Coffee profile:
{body.profile}

Baseline recipe (already valid — make small, justified changes only):
{body.recipe}
"""
    try:
        return chat(prompt, model=TEXT_MODEL)
    except OllamaError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@app.post("/xbloom/login")
def xbloom_login(body: LoginBody) -> dict[str, Any]:
    try:
        session = login(body.email.strip(), body.password)
    except XBloomError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc
    sessions[session["email"].lower()] = session
    return session


@app.post("/xbloom/sync")
def xbloom_sync(body: SyncBody) -> dict[str, Any]:
    email = body.email.strip().lower()
    session = sessions.get(email)
    if session is None:
        try:
            session = login(body.email.strip(), body.password)
        except XBloomError as exc:
            raise HTTPException(status_code=401, detail=str(exc)) from exc
        sessions[email] = session
    try:
        return sync_recipe(session, body.recipe)
    except XBloomError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
