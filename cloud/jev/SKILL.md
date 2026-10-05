---
name: jev
description: Schnelle, typisierte Urteile mit Jev (TypeSafe) - klassifizieren, ja/nein pruefen, bewerten, sortieren. Nutzen statt eigener Freitext-Einschaetzung, wenn eine Entscheidung zaehlbar, wiederholbar oder fuer viele Eintraege noetig ist.
version: 1.0.0
author: Tekin
platforms: [linux, macos]
metadata:
  hermes:
    tags: [Jev, TypeSafe, Klassifizierung, Triage, Bewertung]
    related_skills: []
---

# Jev (TypeSafe System One)

Jev schreibt keinen Text. Es liefert Urteile, die Code direkt weiterverarbeiten kann:

| Werkzeug | Wofuer | Ergebnis |
|---|---|---|
| `jev_classify` | genau eine von mehreren Optionen | `choice`, `confidence`, `probabilities` |
| `jev_check` | Trifft etwas zu? | `noul` = Wahrscheinlichkeit fuer ja (0..1) |
| `jev_score` | Grad auf einer Skala | `score` (kann zwischen Stufen liegen), `confidence` |
| `jev_ask` | mehrere Fragen zum selben Zustand in einem Aufruf | alles oben, je Frage |

Die Werkzeuge kommen vom MCP-Server `jev`. Fehlen sie, laeuft der Server nicht:
`hermes mcp test jev`.

## Wann Jev nehmen

- Mail-, Telegram- oder Kleinanzeigen-Triage: Absicht, Spam/Betrug, Dringlichkeit.
- Viele Eintraege gleich behandeln (Listen, Postfach, Inserate): pro Eintrag Jev fragen,
  dann im Code sortieren oder filtern.
- Pruefen, ob ein Text eine Bedingung erfuellt, bevor eine Aktion laeuft
  (z. B. "Ist das eine Rechnung?", "Verlangt die Mail eine Antwort?").

Nicht fuer: Texte schreiben, Fakten nachschlagen, Rechnen, exakte Suche - das bleibt bei
Hermes selbst bzw. im Code.

## Gute Fragen stellen

- Eine enge Frage pro Urteil. Unabhaengige Aspekte als eigene Fragen in **einem**
  `jev_ask`-Aufruf (laufen parallel, sehen einander nicht).
- Alles Noetige in `state` geben: Text, Absender, Kontext, Regeln. Felder mit Backticks
  referenzieren: "Will `nachricht.text` den Artikel kaufen?"
- Bei `choice` immer eine Ausweich-Option ("sonstiges") anbieten, wenn nichts passen koennte.
- `score`-Stufen als konkrete Situationen beschreiben, aufsteigend, jede fuer sich verstaendlich.
- Frage-Namen sind nur fuer den Code; die Bedeutung muss in `instructions` stehen.

## Ergebnisse nutzen

- `noul` nahe 0.5 heisst unsicher, nicht "mittel". Schwellen bewusst setzen
  (z. B. Betrug ab 0.7 markieren, nicht automatisch loeschen).
- Niedrige `confidence` -> Tekin fragen oder selbst genauer pruefen.
- Vor destruktiven Aktionen (Loeschen, Antworten an Dritte, Kaeufe) zaehlt Jevs Urteil
  als Hinweis, nicht als Erlaubnis.

## Beispiel

```json
jev_ask({
  "state": {"nachricht": "Ist das Sofa noch da? Hole morgen ab, zahle bar."},
  "questions": {
    "absicht": {"type": "choice", "instructions": "Was will `nachricht`?",
                "criteria": {"kaufen": null, "verhandeln": null, "frage": null, "spam": null}},
    "betrug": {"type": "noul", "instructions": "Ist `nachricht` ein typischer Kleinanzeigen-Betrug?"},
    "dringlichkeit": {"type": "score", "instructions": "Wie schnell antworten?",
                      "criteria": ["kann warten", "heute", "sofort"]}
  }
})
```
