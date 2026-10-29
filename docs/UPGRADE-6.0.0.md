# RJ Tracker 6.0.0 / Backend 20.5.0

## Neu in der App

- **Neues Erscheinungsbild im Stil von „Wo ist?“ (iOS 26):** Kartenpins als weiße Scheiben mit Spitze und Favoritenmarke, gruppierte Liquid-Glass-Kartensteuerung, Listenzeilen mit Netzwerkplakette, Aktionskacheln mit farbigen Symbolen sowie gruppierte Abschnitte mit Einstellungs-Symbolen in der Objektansicht.
- **Standortverlauf komplett neu:** Kalenderleiste der letzten 14 Tage mit Meldungsmarken, Zeitraum-Menü (7/14/30/90 Tage, freie Auswahl), Karte mit Farbverlauf von früheren zu späteren Meldungen, Start- und Endflagge, pulsierender Auswahl und eigenen Cluster-Blasen, Satellitenkarte, Vollbildkarte mit Wiedergabe, Wiedergabe mit Meldungsdichte-Diagramm und bis 8× Tempo, Kennzahlen (geschätzte Strecke, Meldungen, Zeitraum, Genauigkeit), Zeitleiste mit Uhrzeitspalte und Verbindungslinie, Aufenthalte und Analyse mit Netzverteilung.
- **Lokaler Google-Verlauf** (Google direkt auf dem iPhone) nutzt dieselbe Karte, Wiedergabe und Zeitleiste.
- **Google häufiger:** neue Option „Alle 30 Sekunden“ für den Vordergrundabruf; neue Installationen starten damit. Eine bereits gespeicherte Auswahl bleibt erhalten.
- **Google-Erfassung auf dem Server pausieren:** unter Ich → Serverzentrale → Automatische Ortung, global oder pro Google-Tracker (benötigt Backend 20.5.0; ältere Backends blenden den Schalter aus).

## Neu im Backend 20.5.0

- `google_server_collection` in `GET/POST /api/polling/settings` sowie `server_collection_paused` in `POST /api/google/settings`. Pausiert: keine automatischen Google-Abrufe, kein neuer Google-Verlauf und keine Aufzeichnungssitzungen. Gespeicherte Daten bleiben unverändert; manuelle Ortung aktualisiert nur den aktuellen Standort.
- Google-Standardintervall 45–50 s statt 60–70 s. Nur unveränderte Altinstallationen (nie gespeicherte Intervalle) wechseln automatisch; eigene Einstellungen bleiben.
- Admin-Website unter `/` im Apple-Stil (helles/dunkles Erscheinungsbild, Karten, Pillen-Schaltflächen). Funktionen und Endpunkte unverändert.

## Installation

1. Backend stoppen, `data/` wie gewohnt sichern.
2. Nur die bisherige Python-Startdatei durch `Tracker_Backend_AMP.py` (Artefakt `RJ-Tracker-Backend-20.5.0-AMP`) ersetzen, Dateiname darf bleiben. Gleiches Verzeichnis, gleiche Umgebungsvariablen, gleiche Python-Umgebung – keine Neueinrichtung, keine neue Anmeldung.
3. `RJ-Tracker-v6.0.0-unsigned.ipa` mit derselben Bundle-ID (`eu.rjuhas.rjtracker`) und Signierung über die bestehende App installieren. Nicht vorher löschen.

## Kompatibilität

Keine Änderung an Datenpfaden, Tracker-IDs, Schlüsseln, Sitzungen, Keychain, Historienformaten oder Google Core Data. Neue Felder sind optional; ältere Apps ignorieren sie, die neue App funktioniert auch mit älteren Backends (ohne Server-Pause-Schalter).
