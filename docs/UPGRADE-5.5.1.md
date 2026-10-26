# RJ Tracker 5.5.1 / Backend 20.4.2

- Apple: Die Schaltfläche wird nach Eingang eines neueren Standorts oder nach Abschluss der jeweiligen Provider-Abfrage wieder freigegeben, auch bei unverändertem/leerem Ergebnis. Der Abschluss wird etwa im Sekundentakt geprüft, statt mit immer längeren Pausen.
- Ein abgeschlossener Apple-Tracker wartet beim Speichern und Anzeigen nicht mehr auf die restlichen Tracker eines Sammelabrufs. FindMy.py fragt rollierende Zubehörschlüssel ohnehin nacheinander ab; alle gelieferten Reports werden weiterhin verarbeitet.
- Fehler beenden die Ladeanzeige und behalten den letzten bekannten Standort. Ein fehlerhafter Tracker verhindert nicht die Verarbeitung der anderen Antworten. Die bisherige Fehlerbremse bleibt aktiv.
- Google: Haptik bei manueller Aktualisierung in der Übersicht, in den Einstellungen sowie auf der Trackerkarte; auf der Trackerkarte zusätzlich Ergebnis-Haptik. Spätere Reports werden weiterhin verarbeitet.
- Der Verlaufscache wird nach einer Trackeraktualisierung verworfen, damit beim anschließenden Öffnen aktuelle Reports geladen werden.

## Installation

1. Backend stoppen.
2. Nur die bisherige Python-Startdatei durch die mitgelieferte `Tracker_Backend_AMP.py` ersetzen. Den bisherigen Startdateinamen bei Bedarf beibehalten. Sie enthält denselben Backend-Code wie `Backend/tracker_backend.py`.
3. Im selben Verzeichnis, mit derselben Datenpfad-Konfiguration und bisherigen Umgebungsvariablen neu starten. Vorhandene Begleitdateien und Python-Umgebung weiterverwenden.
4. Die neue IPA mit derselben Bundle-ID (`eu.rjuhas.rjtracker`) und derselben bisherigen Signierkonfiguration über die vorhandene App installieren.

Die Abhängigkeiten entsprechen Backend 20.4.1. Es gibt keine neue Installation oder Anmeldung, sofern die bestehende Umgebung bereits mit 20.4.1 funktioniert. Keine Datenverzeichnisse löschen, verschieben oder durch ein leeres Verzeichnis ersetzen. Keine App-Deinstallation durchführen. Die tatsächlichen Live-Konten sind nicht Bestandteil der automatischen Tests.

## Kompatibilität

Keine Änderung an Datenpfaden, Tracker-IDs, importierten Schlüsseln, Kontensitzungen, Historienformaten, Keychain-Bezeichnern oder Google Core Data. Die neue Abschlussinformation ist ein optionales API-Feld aus dem bestehenden Laufzeitstatus; ältere Clients ignorieren es. Die neue App kann mit älteren Backends weiterhin einen neueren Standort erkennen; für den schnellen Abschluss bei unveränderten Antworten ist das neue Backend erforderlich.

## Upstream-Prüfung

Geprüft: `malmeloo/FindMy.py` Commit `22e4879426f97c9b0a1a33b22dac34ef0cf3d02f`, insbesondere `LocationReportsFetcher.fetch_location_history` in `findmy/reports/reports.py`. Die Zubehörabfragen laufen dort seriell. Die bereits vorhandenen, fest gepinnten Oktober-Kompatibilitätsversionen von FindMy und Anisette bleiben bestehen, damit die Apple-Anmeldekorrekturen erhalten bleiben.
