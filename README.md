# RJ Tracker — iOS owner app + Android share viewer

Dieses Repository enthält zwei sauber getrennte mobile Clients für Universal Tag Studio / RJ Tracker:

- **iOS:** bestehender nativer Owner-Client (SwiftUI/XcodeGen) im bisherigen Repository-Root.
- **Android:** neuer nativer Gast-/Share-Client unter [`android/`](android/), der ausschließlich vorhandene `/shared/…`-Freigaben verwendet.

Die iOS-App wurde absichtlich nicht in einen neuen Ordner verschoben, damit der bestehende XcodeGen-/IPA-Build unverändert weiter funktioniert.

## iOS — Build als IPA

Der Workflow **Build RJ Tracker IPA** baut die bestehende iOS-App auf macOS/Xcode. Reine Änderungen unter `android/` starten diesen Workflow nicht mehr.

Bei Erfolg entsteht die versionierte unsigned IPA. Die IPA kann anschließend mit einem eigenen Signing-Dienst bzw. Provisioning-Profil signiert werden.

### iOS-Funktionen

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

Die iOS-App erwartet die Mobile-API des Universal-Tag-Studio-v19-Backends (`/api/mobile/v1/...`).

## Android — RJ Tracker Share

Der Android-Client liegt vollständig unter [`android/`](android/) und besitzt einen eigenen Workflow **Build RJ Tracker Android APK**.

Er ist für Personen gedacht, die nur einen vom Besitzer erzeugten Gastlink bekommen, zum Beispiel Familienmitglieder. Er benötigt **keinen Owner-Login** und keine Apple-/Google-/Samsung-Zugangsdaten.

### Android-Funktionen v1.0.0

- Native Kotlin-/Jetpack-Compose-App mit Material 3 und Dynamic Color
- Mehrere `/shared/…`-Links lokal speichern
- Gast-Passwörter verschlüsselt im Android Keystore
- Einzeltracker und Fusionen aus Apple, Google und Samsung
- Bei Fusionen standardmäßig alle Quellen; einzelne Netze lokal ein-/ausblendbar
- Neueste sichtbare Provider-Meldung als Hauptposition
- Native MapLibre-Karte mit OpenFreeMap/OpenStreetMap
- Genauigkeitskreis, Adresse, Zeitstempel und Provideranzeige
- Manueller Ortungsbutton unter Beachtung des serverseitigen Cooldowns
- Übergabe an installierte Android-Karten-/Navigationsapps
- Einfügen per Text oder direkt über den Android Sharesheet

Details: [`android/README.md`](android/README.md)

## Repository-Struktur

```text
TrackerApp/
├── App/                         # bestehende iOS-Quellen
├── project.yml                  # bestehendes XcodeGen-Projekt
├── android/                     # vollständig eigenständige Android-App
│   ├── app/
│   ├── build.gradle.kts
│   └── settings.gradle.kts
└── .github/workflows/
    ├── build-ios.yml
    └── build-android.yml
```
