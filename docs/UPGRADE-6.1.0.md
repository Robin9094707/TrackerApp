# RJ Tracker 6.1.0 / Backend 20.6.0

Dieses Update fasst die bisher getrennten Stände 6.0.0 (neues Design, Standortverlauf, Backend 20.5.0) und 5.6.0 (Google-Zuverlässigkeit, Backend 20.4.3) zusammen und repariert den AMP-Start.

## AMP startet nicht mehr: `Failed to import encodings module`

**Ursache:** Die Backend-Datei legt beim ersten Start im Backend-Ordner eine eigene Python-Umgebung `.tracker-apple-python-20.4.1` an. Bisher enthielt sie eine *Kopie* des damaligen Server-Pythons. Nach einem Python-Update am Server (z. B. Debian-Upgrade von Python 3.11 auf 3.13) findet diese Kopie ihre Standardbibliothek nicht mehr:

```
Could not find platform independent libraries <prefix>
Fatal Python error: Failed to import encodings module
ModuleNotFoundError: No module named 'encodings'
```

Die alte Startdatei prüfte das nicht und startete die defekte Umgebung bei jedem Versuch erneut. Dieselbe Ursache konnte die Server-Google-Umgebung (`data/google/venv`) lahmlegen.

**Behebung in 20.6.0:**

- Vor jedem Start wird geprüft, ob die private Python-Umgebung wirklich startet und ihre Pakete laden kann. Eine defekte Umgebung wird automatisch entfernt und mit dem aktuellen Server-Python neu aufgebaut. Daten, Anmeldungen, Tracker und `runtime/CoreADI.x86_64` bleiben unverändert; die Apple-Bibliothek wird nicht erneut geladen.
- Eine funktionierende Umgebung wird wie bisher weiterverwendet, ohne Neuinstallation.
- Fremde Python-Variablen (`PYTHONHOME`, `PYTHONPATH`, `VIRTUAL_ENV` …) aus AMP oder Shell-Profilen werden nicht mehr an die private Umgebung und an Google weitergegeben.
- Die Google-Umgebung des Servers wird ebenfalls geprüft und bei Bedarf automatisch im Hintergrund neu aufgebaut. Bis dahin wird nie ein defektes Python für Google-Abrufe verwendet.
- In der App unter **Ich → Serverzentrale → System prüfen** zeigen „Python-Laufzeit“ und „Google-Python-Umgebung“ den Zustand.
- Neue Optionen: `--amp-check` meldet zusätzlich den Zustand der Umgebung (ohne etwas zu ändern), `--amp-repair` baut sie gezielt neu auf und startet danach (alternativ Umgebungsvariable `RJ_TRACKER_AMP_REPAIR=1`).

## Update in AMP

1. Instanz in AMP stoppen. Backend-Ordner einschließlich `data/` sichern.
2. Die bisherige Python-Startdatei durch die neue `Tracker_Backend_AMP.py` ersetzen – am selben Ort und unter dem bisherigen Dateinamen (z. B. `findmyairtags.py`).
3. Einmalig sicherstellen, dass am VPS die Programme vorhanden sind: `apt update && apt install -y git 7zip python3-venv`.
4. Instanz starten. Beim ersten Start nach einem Python-Update erscheint in der Konsole „Die vorhandene Python-Umgebung startet nicht mehr … wird jetzt automatisch neu aufgebaut“. Die Paketinstallation dauert einige Minuten; danach folgt die normale Startmeldung `Universal Tag Studio 20.6.0 API EDITION startet …`.

Startparameter, Port, Umgebungsvariablen und `ULTRA_TRACKER_DATA_DIR` bleiben unverändert.

### Falls der Fehler trotzdem sofort erscheint

Kommt `Failed to import encodings module` bereits **bevor** irgendeine Zeile `[AMP-Einrichtung]` ausgegeben wird, ist nicht die Tracker-Umgebung, sondern das Python defekt, mit dem AMP die Datei startet:

- In der AMP-Instanz unter den Python-/Start-Einstellungen prüfen, welches Python verwendet wird, und auf das System-Python (`/usr/bin/python3`) stellen. Eine gesetzte Umgebungsvariable `PYTHONHOME` entfernen.
- Verwendet AMP für die Instanz eine eigene virtuelle Umgebung (Ordner wie `venv/` oder `.venv/` im Instanzverzeichnis), diesen Ordner bei gestoppter Instanz löschen bzw. in AMP „Update“/„Reinstall“ ausführen, damit AMP ihn mit dem aktuellen Python neu anlegt. Daten im Backend-Ordner bleiben dabei erhalten.
- Prüfen am VPS: `python3 --version` muss 3.11 bis 3.14 melden.

Manuelle Reparatur der Tracker-Umgebung (normalerweise nicht nötig): Instanz stoppen, im Backend-Ordner `.tracker-apple-python-20.4.1` löschen, Instanz starten.

## App 6.1.0

- Enthält das neue Design im Stil von „Wo ist?“ und den neuen Standortverlauf aus 6.0.0: [Details](UPGRADE-6.0.0.md).
- Enthält die Google-Korrekturen aus 5.6.0: wartende Google-Ortungen überleben Verbindungsabbrüche, der erste Abruf nutzt sofort den Gerätekatalog, gültige Serverstandorte werden nicht von ungültigen lokalen Punkten verdrängt, „Erneut verbinden“ bei Serverfehlern: [Details](UPGRADE-5.6.0.md).
- Version 6.1.0 / Build 26. Bundle-ID `eu.rjuhas.rjtracker`, Google-Keychain, Core-Data-Modell und alle Datenformate unverändert. Über die bestehende App installieren, nicht vorher löschen.

## Prüfungen

Neue Regressionstests (`Tests/test_backend_amp_bootstrap.py`) stellen den Fehler mit einem Python nach, das genau diese Meldung ausgibt, sowie einen ins Leere zeigenden Python-Link. Geprüft wird: Erkennung, automatischer Neuaufbau ohne Datenänderung, Wiederverwendung gesunder Umgebungen, `--amp-check` ohne Reparatur, Entfernen fremder Python-Variablen und der Neuaufbau der Google-Umgebung. Zusätzlich wurde die gepackte Datei in einem echten Lauf gegen eine defekte Umgebung gestartet (Neuaufbau mit Python 3.13, Apple-Bibliothek geprüft, Server antwortet; zweiter Start ohne Neuinstallation).
