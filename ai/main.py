import os
import json
from typing import Any, Dict, List, Literal, Optional
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from google import genai
from google.genai import types

load_dotenv(Path(__file__).parent / ".env")


# -------------------------
# Config
# -------------------------
MODEL_ID = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")


# -------------------------
# API models
# -------------------------
ResponseType = Literal["COMMAND", "EXPLAIN", "QUERY"]

# All cloud commands the ESP32 mesh understands
CloudCommand = Literal[
    "open_blinds", "close_blinds",
    "open_windows", "close_windows",
    "turn_on_fan", "turn_off_fan",
    "turn_on_lights", "turn_off_lights",
    "turn_on_heater", "turn_off_heater",
    "trigger_alarm",
]


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    state: Dict[str, Any]


class Command(BaseModel):
    cloud_command: CloudCommand
    room_id: str
    reason: Optional[str] = None


class ChatResponse(BaseModel):
    type: ResponseType
    reply: str
    command: Optional[Command] = None
    confidence: float = Field(..., ge=0.0, le=1.0)
    blocked_reason: Optional[str] = None


# -------------------------
# Helper functions
# -------------------------
def get_room(state: Dict[str, Any], room_id: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Return the first matching room dict from state['rooms'], or the first room if room_id is None."""
    rooms: List[Dict[str, Any]] = state.get("rooms") or []
    if not rooms:
        return None
    if room_id is None:
        return rooms[0]
    for r in rooms:
        if r.get("room_id") == room_id:
            return r
    return rooms[0]


def validate_and_policy_gate(resp: ChatResponse, state: Dict[str, Any]) -> ChatResponse:
    """
    Validate command against current sensor state and add safety warnings.
    Commands are NEVER blocked — only annotated with warnings.
    """
    if resp.command is None:
        return resp

    cmd = resp.command
    room = get_room(state, cmd.room_id)

    if room is None:
        return resp

    rain = room.get("rain_detected", False)
    co2 = room.get("co2_ppm", 0) or 0
    aqi = str(room.get("aqi", "good")).lower()

    warnings: List[str] = []

    # Rain warning when opening windows/blinds
    if rain and cmd.cloud_command in ("open_windows", "open_blinds"):
        warnings.append("Rain detected outside — this may let water in.")

    # High CO2 — suggest turning on fan when opening windows
    if co2 > 1000 and cmd.cloud_command == "open_windows":
        warnings.append(f"CO₂ is high ({int(co2)} ppm). Good call ventilating.")

    # Poor air quality warning
    if aqi in ("unhealthy", "very_unhealthy", "hazardous") and cmd.cloud_command == "open_windows":
        warnings.append(f"Outdoor air quality is {aqi}. Opening windows may worsen indoor air.")

    if warnings:
        suffix = " ⚠️ " + " ".join(warnings)
        resp.reply = (resp.reply or "") + suffix

    return resp


# -------------------------
# Gemini client
# -------------------------
client = genai.Client()


SYSTEM_INSTRUCTIONS = """
You are the AI assistant for the GossipHome smart-home IoT system.

You MUST output STRICT JSON matching the ChatResponse schema.

## Your responsibilities
1. Control requests  → type=COMMAND  (include a command object)
2. Explanations      → type=EXPLAIN  (no command)
3. Status queries    → type=QUERY    (no command)

## Input format
You receive a JSON object with two fields:
- "user_message": what the user said
- "state": { "rooms": [ <room objects> ] }

Each room object has:
  room_id, name, is_online,
  temperature (°C), humidity (%), light_lux,
  co2_ppm, aqi ("good"/"moderate"/"unhealthy"/...),
  rain_detected (bool)

## Available cloud commands
open_blinds, close_blinds,
open_windows, close_windows,
turn_on_fan, turn_off_fan,
turn_on_lights, turn_off_lights,
turn_on_heater, turn_off_heater,
trigger_alarm

## Command object format
{
  "cloud_command": "<one of the commands above>",
  "room_id": "<room_id from state, e.g. living_room>",
  "reason": "<optional short reason>"
}

## Rules
- Use the room_id from the state when issuing commands.
  If no specific room is mentioned and state has only one room, use that room_id.
- NEVER block or refuse a user command. The backend handles safety warnings.
- If the user asks about sensor values, read them from state and answer directly.
- Be concise and friendly.
"""


def gemini_chat(message: str, state: Dict[str, Any]) -> ChatResponse:
    payload = {"user_message": message, "state": state}

    response = client.models.generate_content(
        model=MODEL_ID,
        contents=[
            types.Content(
                role="user",
                parts=[types.Part(text=json.dumps(payload))]
            )
        ],
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_INSTRUCTIONS,
            temperature=0,
            response_mime_type="application/json",
            response_schema=ChatResponse,
        ),
    )

    parsed = getattr(response, "parsed", None)
    if parsed is not None:
        return parsed

    try:
        return ChatResponse.model_validate_json(response.text)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Gemini returned invalid JSON: {e}")


# -------------------------
# FastAPI app
# -------------------------
app = FastAPI(title="Smart Home Gemini AI", version="1.0.0")


@app.get("/health")
def health():
    return {"ok": True, "model": MODEL_ID}


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest):
    llm_resp = gemini_chat(req.message, req.state)
    safe_resp = validate_and_policy_gate(llm_resp, req.state)
    return safe_resp
