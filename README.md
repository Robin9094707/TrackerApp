# RJ Tracker — native iOS client

Dieses Repository enthält den nativen iOS-Client für Universal Tag Studio / RJ Tracker v19.

## Build als IPA

Der Workflow **Build RJ Tracker IPA** startet automatisch bei einem Push auf `main` und kann zusätzlich manuell über **Actions → Build RJ Tracker IPA → Run workflow** gestartet werden.

Bei Erfolg entsteht das Artefakt `RJ-Tracker-unsigned-IPA`. Die IPA ist absichtlich unsigned und kann anschließend mit einem eigenen Signing-Dienst bzw. Provisioning-Profil signiert werden.

## App-Funktionen

- SwiftUI, iOS 17+
- Liquid Glass auf iOS 26+, Material-Fallback auf älteren unterstützten Versionen
- Apple MapKit
- Apple-, Google-, Samsung- und Fusion-Tracker
- Tracker-Details, Live-Ortung, Locate-All und Verlauf
- Geofences und gespeicherte Orte
- Alert-Center und Recovery Guard
- Push-Registrierung / lokale Benachrichtigungen
- Provider-, Polling- und Serverstatus
- Web-Studio für server-/browsergebundene Spezialfunktionen
- Keychain für sensible Sitzungsdaten / CSRF

Die App erwartet die Mobile-API des Universal-Tag-Studio-v19-Backends (`/api/mobile/v1/...`). Das Backend selbst wird getrennt betrieben und muss nicht mit der IPA gebaut werden.
