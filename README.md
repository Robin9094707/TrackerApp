## iOS 3.0

Der aktuelle IPA-Build heißt `RJ-Tracker-v3.0.0-unsigned-IPA`. Standard-Pushes bauen direkt die Release-IPA. Für gezielte Tests und einen Screenshot der Verlaufsansicht lässt sich beim manuellen Workflowstart `review` aktivieren. Die IPA benötigt wie bisher eine Signierung zum Installieren.

Vor der Umgestaltung wurde `backup/pre-liquid-glass-2026-10-03` angelegt. Dieser Branch zeigt unverändert auf `73f46c4733b03968058168a9c3bbdec822e7de0d`. Ein späteres Rückgängigmachen sollte die Änderungen durch einen neuen Commit zurücknehmen, um neuere Arbeit nicht durch einen Force-Push zu überschreiben.

# RJ Tracker — iOS owner app + Android share viewer

Dieses Repository enthält zwei sauber getrennte mobile Clients für Universal Tag Studio / RJ Tracker:

- **iOS:** bestehender nativer Owner-Client (SwiftUI/XcodeGen) im bisherigen Repository-Root.
- **Android:** neuer nativer Gast-/Share-Client unter [`android/`](android/), der ausschließlich vorhandene `/shared/…`-Freigaben verwendet.

Die iOS-App wurde absichtlich nicht in einen neuen Ordner verschoben, damit der bestehende XcodeGen-/IPA-Build unverändert weiter funktioniert.

## iOS 2.2 — Native Karte, Sicherheit und Verwaltung

Die iOS-App bietet jetzt eine große MapKit-Karte mit nativem Schiebepanel, Favoriten, Quellenvergleich bei Fusionen, Namens-/Symbolbearbeitung, Kartenwahl für Orte und Geofences, Bewegungsalarme sowie einen abspielbaren Verlauf mit Netzfiltern und CSV-/GPX-Export. [Alle Neuerungen und technische Grenzen](IOS-CHANGELOG.md).

Neu in 2.2: Konto, Benutzer, Passwort/2FA, Passkey-Verwaltung, interne Freigaben, Backups, Google-Reparatur, Netzwerkvergleich, Speicherbereinigung sowie schnellere gezielte Standortabrufe und überarbeitete Verläufe. Neue Passkeys werden auf der HTTPS-Serverwebsite registriert.

Seit 2.1: Gruppenverwaltung, passwortgeschützte Gastfreigaben, Archiv und Wiederherstellung sowie eine Serverzentrale mit Ortungsintervallen, Diagnose und Speicherübersicht. Details und Grenzen stehen im [iOS-Changelog](IOS-CHANGELOG.md).

Der iOS-Build prüft Logik und Bedienung mit Unit-/Simulator-Tests, speichert Bildschirmaufnahmen und erzeugt anschließend **RJ-Tracker-v2.2.0-unsigned.ipa**. Android bleibt davon unabhängig.

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


### iOS 2.1.1

Sortierung, Netzwerk-, Ansichts- und Gruppenfilter bleiben beim Neustart erhalten. Das Objektpanel verwendet in jeder Höhe einen deckenden Systemhintergrund. Der Asset-Katalog wird jetzt tatsächlich eingebunden; das neue Radar-/Pin-Icon wird durch `python3 Scripts/generate_app_icon.py` vor `xcodegen generate` reproduzierbar erzeugt. CI prüft den Icon-Eintrag und die kompilierten Assets in der fertigen App.

