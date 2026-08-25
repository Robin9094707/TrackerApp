# RJ Tracker — Native iOS + Universal Tag Studio 19

Dieses Repository enthält **beides**:

- `App/` — native SwiftUI-iPhone/iPad-App mit MapKit, Liquid Glass, Fusion/Apple/Google/Samsung, Verlauf, Alerts, Geofences, Recovery Guard, APNs und Web-Studio-Fallback.
- `Backend/findmyairtags.py` — das vollständige bestehende Universal Tag Studio, additiv auf Version 19 erweitert. Die vorhandene Weboberfläche und bestehenden API-Routen bleiben enthalten.

## 1. IPA auf GitHub bauen

1. GitHub → **Actions** → **Build RJ Tracker IPA** → **Run workflow**.
2. Nach erfolgreichem Lauf das Artefakt `RJ-Tracker-unsigned-IPA` laden.
3. Die unsigned IPA anschließend mit deinem normalen Signaturdienst/Provisioning-Profil signieren.

Bei einem Xcode-Fehler wird stattdessen `RJ-Tracker-build-log` hochgeladen.

## 2. Backend aktualisieren

Deine bisherige Python-Datei durch `Backend/findmyairtags.py` ersetzen. **Deinen bestehenden Datenordner nicht löschen.** Das Backend verwendet weiterhin die bisherigen Daten, Sessions, Tracker/Fusionen, Nutzer, Geofences, Alerts usw.

Die iOS-App koppelt sich mit:

- Server-URL, bevorzugt `https://...`
- optionalem Benutzernamen
- Passwort
- bestehender Server-2FA, falls aktiviert

Das Passwort wird von der iOS-App **nicht dauerhaft gespeichert**. Die Anmeldung verwendet die vorhandene serverseitige Session und CSRF-Schutzlogik.

## 3. Funktionsumfang

Native iOS-Oberflächen sind für die täglichen Tracking-Funktionen vorhanden: Tracker/Fusionen, Karte, Standortdetails, Ortung, Verlauf, Geofences, gespeicherte Orte, Alert-Center, Recovery Guard, Systemstatus, Push und Serverwerkzeuge.

Für server-/browsergebundene Spezialfunktionen bietet die App zusätzlich **Web Studio**. Es übernimmt die gekoppelte Sitzung und öffnet die unveränderte bestehende Weboberfläche innerhalb der App.

Siehe außerdem:

- `FEATURES.md`
- `BACKEND-SETUP.md`
- `BUILD-NOTES.md`
- `VALIDATION.md`
- `CHANGELOG-v19.md`

## Push-Mitteilungen

Lokale iOS-Benachrichtigungen funktionieren ohne Apple-Server-Key bei App-Synchronisation. Für echte Remote-Push-Mitteilungen im Hintergrund/bei beendeter App werden ein Apple Push Notification Key und ein zum Bundle-Identifier passendes Push-Entitlement benötigt. Details stehen in `BACKEND-SETUP.md`.
