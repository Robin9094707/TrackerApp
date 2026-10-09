# RJ Tracker 4.4.1 / Backend 20.3.1

## Fehlerursache

Das Serverprotokoll vom 9. Oktober zeigt: OAuth-Anmeldung und Token-Ausgabe funktionieren, anschließend bekommt `POST /` HTTP 405. Die öffentliche Prüfung bestätigt: `POST /mcp` liefert die erwartete OAuth-Anforderung (401), `POST /` dagegen 405. Ob eine gespeicherte Connector-Adresse oder eine Proxy-Weiterleitung diesen Pfad verursacht, ist damit noch nicht bewiesen.

Der vollständige ChatGPT-Link des Hauptkontos lautet `https://find.rjuhas.eu/mcp`. Weitere Benutzer verwenden ihren eigenen Link aus der App einschließlich `/t/<konto>/mcp`.

## Korrektur

- JSON-RPC POST an `/` verwendet direkt denselben MCP-Handler wie `/mcp`, ohne Umleitung und mit identischer Bearer-, Scope-, Origin- und Ratenprüfung.
- `/mcp/` wird ohne Umleitung akzeptiert. Die OAuth-Ressource bleibt `/mcp`; vorhandene Tokens bleiben gültig.
- GET an `/` mit `Accept: text/event-stream` liefert eine Protokollantwort statt der HTML-Administration. Gewöhnliche Browseraufrufe öffnen weiter die Admin-Anmeldeseite.
- Die MCP-Diagnose prüft die Kompatibilitätsroute und zeigt die letzte erfolgreiche Tool-Erkennung. Die App erklärt den vollständigen MCP-Link.

## Installation mit vorhandenen Daten

Serverdienst stoppen, bestehenden Datenordner sichern und die bisherige Python-Datei durch Backend 20.3.1 ersetzen. Bisherigen Dateinamen, Startbefehl, Umgebungsvariablen und `ULTRA_TRACKER_DATA_DIR` beibehalten. Danach den Dienst neu starten. Keine Daten neu anlegen oder löschen. Dieses Update benötigt keinen Wechsel des Datenformats.

IPA 4.4.1 / Build 15 mit derselben Signieridentität und Bundle-ID `eu.rjuhas.rjtracker` als Update installieren. Die IPA ist unsigned; nicht vorher deinstallieren.

Danach die Tool-Erkennung in ChatGPT erneut starten. Falls die fehlgeschlagene Verbindung eine falsche Adresse gespeichert hat, diese mit dem vollständigen Link und OAuth neu einrichten. Funktionierende Verbindungen müssen nicht pauschal widerrufen werden. Unter **Ich → Server verwalten → ChatGPT / MCP → Konfiguration prüfen** wird die erfolgreiche Erkennung sichtbar.

## Prüfung und Rückweg

17 fokussierte Backend-Prüfungen, einschließlich Passwort-Anmeldung, PKCE, Token-Ausgabe, Initialize, Tool-Katalog und Tool-Aufruf über alle drei POST-Adressen. Zusätzlich: fehlende Bearer-Tokens trotz App-Sitzung, gesperrter Connector, falscher Origin, CORS und ungültige JSON-RPC-Anfragen. Vorhandene Standortdaten und bisherige Verwaltungsfunktionen bleiben in der Regression enthalten. Der IPA-Workflow baut den Release ohne zusätzliche Simulator-Testreihen.

GitHub-Backup: `backup/before-root-mcp-fix-2026-10-09`, Commit `45c8c72244590bfab6c3bdba6c1a56a71200fa6c`. Für einen Rückweg Backend und App aus diesem Stand verwenden und den bestehenden Datenordner beibehalten.

Die Korrektur wird auf deinem laufenden Server erst nach Austausch der Datei und Neustart aktiv. Ein vollständiger Live-OAuth-Test benötigt deine Anmeldung.

Offizielle Referenzen: [OpenAI MCP-Einrichtung](https://developers.openai.com/plugins/build/app-quickstart), [MCP Streamable HTTP](https://github.com/modelcontextprotocol/modelcontextprotocol/blob/main/docs/specification/2025-11-25/basic/transports.mdx).
