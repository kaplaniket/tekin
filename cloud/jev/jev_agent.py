#!/usr/bin/env python3
"""Jev-Agent: stellt TypeSafes Jev-Modell (System One) auf dem Cloud-Server bereit.

Jev liefert typisierte Urteile statt Text: choice (eine Option aus mehreren),
noul (Wahrscheinlichkeit fuer ja) und score (Stufe auf einer Skala).

Zwei Betriebsarten:
  jev ask anfrage.json          # oder: cat anfrage.json | jev ask -
  jev serve [--port 8765]       # HTTP-Dienst nur auf 127.0.0.1, POST /ask

Anfrage (JSON):
  {"state": "Text oder JSON", "questions": {"name": {"type": "choice", ...}}}
Antwort: das SystemOne-Ergebnis als JSON (model, usage, answers).

Der Schluessel kommt aus TYPESAFE_API_KEY (siehe ~/.hermes/.env).
"""
import argparse
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from typesafe_sdk import TypeSafeAPIError, TypeSafeClient, TypeSafeError


def ask(client: TypeSafeClient, request: dict) -> dict:
    if not isinstance(request, dict) or "state" not in request or not request.get("questions"):
        raise ValueError('Anfrage braucht "state" und mindestens eine Frage in "questions".')
    response = client.system_one(
        state=request["state"],
        questions=request["questions"],
        model=request.get("model"),
    )
    return response.model_dump(mode="json")


def cmd_ask(args: argparse.Namespace) -> int:
    raw = sys.stdin.read() if args.file == "-" else open(args.file, encoding="utf-8").read()
    with TypeSafeClient() as client:
        result = ask(client, json.loads(raw))
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


def cmd_serve(args: argparse.Namespace) -> int:
    client = TypeSafeClient()

    class Handler(BaseHTTPRequestHandler):
        def _reply(self, status: int, body: dict) -> None:
            data = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self) -> None:
            if self.path == "/health":
                self._reply(200, {"ok": True})
            else:
                self._reply(404, {"error": "nicht gefunden"})

        def do_POST(self) -> None:
            if self.path != "/ask":
                self._reply(404, {"error": "nicht gefunden"})
                return
            try:
                length = int(self.headers.get("Content-Length", 0))
                self._reply(200, ask(client, json.loads(self.rfile.read(length))))
            except (ValueError, json.JSONDecodeError) as error:
                self._reply(400, {"error": str(error)})
            except TypeSafeAPIError as error:
                self._reply(502, {"error": str(error)})
            except TypeSafeError as error:
                self._reply(500, {"error": str(error)})

        def log_message(self, fmt: str, *fmt_args) -> None:
            sys.stderr.write("jev: " + fmt % fmt_args + "\n")

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Jev-Agent laeuft auf http://{args.host}:{args.port}", file=sys.stderr)
    try:
        server.serve_forever()
    finally:
        client.close()
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(prog="jev", description="Jev (TypeSafe System One) auf dem Server.")
    sub = parser.add_subparsers(dest="command", required=True)
    p_ask = sub.add_parser("ask", help="eine Anfrage aus Datei oder stdin beantworten")
    p_ask.add_argument("file", help="JSON-Datei oder - fuer stdin")
    p_ask.set_defaults(func=cmd_ask)
    p_serve = sub.add_parser("serve", help="lokalen HTTP-Dienst starten")
    p_serve.add_argument("--host", default="127.0.0.1")
    p_serve.add_argument("--port", type=int, default=8765)
    p_serve.set_defaults(func=cmd_serve)
    args = parser.parse_args()
    try:
        return args.func(args)
    except (ValueError, json.JSONDecodeError, TypeSafeError) as error:
        print(f"jev: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
