#!/usr/bin/env python3
"""MCP-Server, der Hermes (oder jedem anderen MCP-Client) Jev als Werkzeug gibt.

Jev (TypeSafe System One) beantwortet Fragen nicht mit Text, sondern mit typisierten
Urteilen: choice, noul (Wahrscheinlichkeit fuer ja) und score.

Start (stdio):  python jev_mcp.py
Der Schluessel wird aus TYPESAFE_API_KEY gelesen, sonst aus ~/.hermes/.env.
"""
import json
import os
from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP
from typesafe_sdk import TypeSafeClient, TypeSafeError


def _load_typesafe_env() -> None:
    """Nur TYPESAFE_*-Zeilen aus ~/.hermes/.env uebernehmen; Hermes reicht sie nicht durch."""
    env_file = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes")) / ".env"
    if not env_file.is_file():
        return
    for line in env_file.read_text(encoding="utf-8", errors="replace").splitlines():
        key, sep, value = line.strip().partition("=")
        if sep and key.startswith("TYPESAFE_") and value and key not in os.environ:
            os.environ[key] = value.strip().strip("'\"")


_load_typesafe_env()
mcp = FastMCP("jev")
_client: TypeSafeClient | None = None


def _ask(state: Any, questions: dict[str, Any], model: str | None = None) -> dict[str, Any]:
    global _client
    if not questions:
        raise ValueError("Mindestens eine Frage noetig.")
    if _client is None:
        _client = TypeSafeClient()
    response = _client.system_one(state=state, questions=questions, model=model)
    return response.model_dump(mode="json")


def _safe(call) -> str:
    try:
        return json.dumps(call(), ensure_ascii=False)
    except (TypeSafeError, ValueError) as error:
        return json.dumps({"error": str(error)}, ensure_ascii=False)


@mcp.tool()
def jev_ask(state: Any, questions: dict[str, Any], model: str | None = None) -> str:
    """Stellt Jev mehrere Fragen zu demselben Zustand auf einmal (laufen parallel).

    state: Text oder JSON-Objekt mit allem, was zur Beurteilung noetig ist.
    questions: {name: frage}. Jede Frage ist eines von
      {"type": "choice", "instructions": "...", "criteria": {"label": "Beschreibung", ...}}
      {"type": "noul",   "instructions": "Ja/Nein-Frage ...", "criteria": {"true": "...", "false": "..."}}
      {"type": "score",  "instructions": "...", "criteria": ["Stufe 0", "Stufe 1", ...]}
    Felder in state koennen in instructions mit Backticks referenziert werden, z. B. `mail.betreff`.
    Antwort: JSON mit answers[name] = choice+confidence+probabilities, noul (0..1) bzw. score+confidence.
    """
    return _safe(lambda: _ask(state, questions, model))


@mcp.tool()
def jev_classify(text: str, question: str, options: dict[str, str]) -> str:
    """Ordnet text genau einer Option zu. options: {"label": "wann diese Option passt"}.
    Fuer "nichts passt" eine eigene Option wie "sonstiges" mitgeben."""
    return _safe(lambda: _ask(text, {"antwort": {"type": "choice", "instructions": question, "criteria": options}})["answers"]["antwort"])


@mcp.tool()
def jev_check(text: str, question: str) -> str:
    """Ja/Nein-Pruefung. Liefert noul = Wahrscheinlichkeit fuer ja (0..1); 0.5 heisst unsicher."""
    return _safe(lambda: _ask(text, {"antwort": {"type": "noul", "instructions": question}})["answers"]["antwort"])


@mcp.tool()
def jev_score(text: str, question: str, levels: list[str]) -> str:
    """Bewertet text auf einer Skala. levels: aufsteigende Stufenbeschreibungen, Index = Punktzahl."""
    return _safe(lambda: _ask(text, {"antwort": {"type": "score", "instructions": question, "criteria": levels}})["answers"]["antwort"])


if __name__ == "__main__":
    mcp.run()
