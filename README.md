# RJ Tracker 8.0.0 · Backend 22.0.0 · Overhaul

Neues Design mit Startanimation, responsive **Web-App unter `/app`** (Karte, Ortung, Verlauf, Taschen, Mitteilungen), **Netz-Priorität für Fusionen** (Hauptnetz plus Backup) und Taschenmodus für jedes Objekt einschließlich Fusionen. Alle Server- und App-Daten bleiben kompatibel.

[Update, Web-App und Netz-Priorität](docs/UPGRADE-8.0.0.md) · [Changelog](IOS-CHANGELOG.md)

---

# RJ Tracker 7.0.0 · Backend 21.0.0

Tracker-Panel im Stil der Panel-App, Schulwochen mit nachvollziehbaren Ortungsnachweisen, serverseitige Schulmeldungen und Bark mit mehreren Empfängern. Verbesserter Google-FCM-Empfang und direkte Protobuf-Auswertung.

[Update, Einrichtung und Grenzen](docs/UPGRADE-7.0.0.md) · [Google-Quellen](Vendor/Spot/UPSTREAM.md)

Die Pull-Request-Action erzeugt die unsignierte IPA und `Tracker_Backend_AMP.py` nach erfolgreichen Pflichtprüfungen. PANELAPios und die Android-App bleiben unverändert. Bestehende Android-APIs werden weiter unterstützt.

---

# RJ Tracker 6.2.0 · Backend 20.7.1

**Schultasche & Routinen:** Hauptadmins können pro Server-Tracker Orte und wöchentliche Zeitfenster festlegen. Die Tagesübersicht zeigt erkannte Aufenthalte und Standortmeldungen im geplanten Zeitfenster. Der Standortverlauf bietet außerdem eine stabilere Kartensteuerung und die Ansicht „Heute komplett“.

- [iOS 6.2.0 (Build 28, unsignierte IPA)](https://github.com/Robin9094707/TrackerApp/actions/runs/42212846517/artifacts/13501571800)
- [AMP-Serverdatei 20.7.1](https://github.com/Robin9094707/TrackerApp/actions/runs/42212846517/artifacts/13499687738)
- [Installationsanleitung](docs/UPGRADE-6.2.0.md) · [Änderungen](IOS-CHANGELOG.md) · [Getesteter Build auf `main`](https://github.com/Robin9094707/TrackerApp/actions/runs/42212846517)

Für den Schultaschenmodus ist das Backend-Update erforderlich. Die IPA wird mit der bisherigen Signierungsidentität über die vorhandene App installiert.

---

# RJ Tracker 6.1.0 · Backend 20.6.0

**AMP startet wieder:** Die Backend-Datei erkennt eine nach einem Server-Python-Update defekte Python-Umgebung (`Failed to import encodings module`) und baut sie automatisch neu auf. Dasselbe gilt für die Google-Umgebung des Servers. Daten, Anmeldungen und Tracker bleiben unverändert.

Enthält außerdem das neue „Wo ist?“-Design mit neuem Standortverlauf (6.0.0) und die Google-Zuverlässigkeitskorrekturen (5.6.0) in einem gemeinsamen Stand.

[Update und AMP-Reparatur 6.1.0](docs/UPGRADE-6.1.0.md) · [Changelog](IOS-CHANGELOG.md)

Die Action **Build RJ Tracker IPA** erzeugt `RJ-Tracker-v6.1.0-unsigned.ipa`, `SHA256SUMS.txt` und `Tracker_Backend_AMP.py` (20.6.0).

---

# RJ Tracker 6.0.0 · Backend 20.5.0

Neues Design im Stil der aktuellen „Wo ist?“-App, komplett neuer Standortverlauf, häufigere Google-Abrufe und eine abschaltbare Google-Erfassung auf dem Server. Backend-Update: nur die eine Backend-Datei ersetzen; alle Daten und Anmeldungen bleiben erhalten.

[Installation und Neuerungen 6.0.0](docs/UPGRADE-6.0.0.md) · [Changelog](IOS-CHANGELOG.md)

Die Action **Build RJ Tracker IPA** erzeugt `RJ-Tracker-v6.0.0-unsigned.ipa`, `SHA256SUMS.txt` und `Tracker_Backend_AMP.py` (20.5.0).

# RJ Tracker 5.6.0 · Google-Ortung und Zuverlässigkeit

Reparierte Google-Anfragen nach Verbindungsabbrüchen und beim ersten Laden, klarere Standort-/Aktualisierungsanzeige und ein datenkompatibles Serverupdate 20.4.3.

[Update und Datenerhalt](docs/UPGRADE-5.6.0.md) · [Änderungen](IOS-CHANGELOG.md) · [Google-Quellen und Lizenzen](Vendor/Spot/UPSTREAM.md)

Die GitHub Action **Build RJ Tracker IPA** erstellt nach erfolgreichen Pflichtprüfungen `RJ-Tracker-v5.6.0-unsigned.ipa` mit SHA-256-Prüfsumme und `Tracker_Backend_AMP.py`. Auch Pull Requests gegen `main` bauen diese Artefakte, ohne den Hauptbranch zu ändern. Die IPA benötigt zum Installieren die eigene Signierung; bestehende App mit derselben Bundle-ID und Signierungsidentität aktualisieren, ohne Deinstallation. Serverdatei im selben Verzeichnis ersetzen und vorhandene Datenpfade/Startparameter beibehalten.

Echte Google-Anmeldung und neue Netzwerk-Standorte benötigen das eigene Konto, erreichbare Google-Dienste und Meldungen des Find-Hub-Netzes. Automatische Tests prüfen die Fehlerfälle und Datenkompatibilität mit Testdaten.

---

# RJ Tracker 5.2.0

Google direkt auf dem iPhone bleibt bei Ausfall des optionalen Tracker-Servers erreichbar. Google-Bedienelemente erscheinen nur bei Alle Netze/Google. Pro Tracker pausierbare automatische Verlaufsabfrage, optionale iOS-Hintergrundversuche und ein experimentelles UWB-Prüflabor.

**Moto Tag 1: Keine funktionierende UWB-Pfeilortung bestätigt.** Das Labor prüft Gerätefähigkeiten; es zeigt keine erfundenen Richtungen oder Entfernungen. [Technische Untersuchung](docs/UWB-INVESTIGATION.md).

[Installation und Nutzung 5.2.0](docs/UPGRADE-5.2.0.md) · [Changelog](IOS-CHANGELOG.md)

Die Action erzeugt `RJ-Tracker-v5.2.0-unsigned.ipa` und `SHA256SUMS.txt` nach allen Pflichtprüfungen. Zum Update dieselbe Bundle-ID/Signierungsidentität beibehalten und die bestehende App nicht vorher löschen. iOS 18.1+, Backend unverändert kompatibel.

---

# RJ Tracker 5.1.2

Native iPhone-/iPad-App für Apple-, Google-, Samsung- und Fusion-Tracker, mit Google Find Hub direkt auf dem Gerät. Mindestversion: iOS 18.1.

[Update und Installation 5.1.2](docs/UPGRADE-5.1.2.md) · [Änderungen](IOS-CHANGELOG.md) · [API/Backend](docs/API-EDITION.md)

Die GitHub Action **Build RJ Tracker IPA** erstellt `RJ-Tracker-v5.1.2-unsigned.ipa` und `SHA256SUMS.txt`. Sie prüft Backend, Google-Protokoll und Datenbankmigration, Debug-Unit-/UI-Tests sowie den Kaltstart und Neustart der optimierten Release-App. Die IPA muss anschließend mit dem eigenen Profil signiert werden. Echte Google-Anmeldung, Entschlüsselung und Tracker-Klingeln benötigen ein eigenes Konto und Hardware; Simulatorprüfungen ersetzen diese Prüfung nicht.

Bestehende App mit derselben Bundle-ID und Signierungsidentität aktualisieren, ohne sie vorher zu löschen. Serverdaten und Google-Kontoverläufe bleiben erhalten. Für dieses Update ist kein Backendwechsel nötig.

---

# RJ Tracker 5.1

Native Google-Find-Hub-Datenquelle in derselben universellen TrackerApp. Die Spot-App-Oberfläche wurde entfernt; nur die Google-Protokolltechnik wird als Bibliothek verwendet.

[Migration und Nutzung](docs/UPGRADE-5.1.md). Bestehender Google-Keychain-Service, Konto-Preferences, lokale Verläufe und alle Serverdaten bleiben erhalten. Google-Anmeldung und Verbindung haben Zeitlimits und einen erneuten Versuch. Alle gelieferten Report-Pakete werden verarbeitet; Vordergrundabrufe sind einstellbar.

# RJ Tracker 5.0

Universelle iPhone-/iPad-Tracker-App mit bestehendem Apple-/Google-/Samsung-/Fusion-Backend und vollständig integriertem lokalem Google-Find-Hub-Client auf Basis von [Spot](https://github.com/leonboe1/Spot).

Google direkt auf dem iPhone: Anmeldung und AAS-Token, Schlüsselwiederherstellung, lokale secrets.json-Imports, Geräteimport, verschlüsselte Standorte und lokale Historie, Bluetooth-Suche/Klingeln, Google-Klingelanfragen, Freigaben, Verlustmodus und ESP32-Erstellung. Die bestehenden Serverfunktionen bleiben erhalten.

[Upgrade und Nutzung](docs/UPGRADE-5.0.md) · [API](docs/API-EDITION.md) · [Spot-Quellstand/Lizenzen](Vendor/Spot/UPSTREAM.md)

Mindestversion iOS 18.1. Die GitHub Action **Build RJ Tracker IPA** erzeugt eine unsigned IPA zum anschließenden Signieren.

Der kombinierte App-Quellcode steht unter GPL-3.0-only; Drittanbieterhinweise sind in `Vendor/Spot/Licenses` enthalten. Das eingeschränkt lizenzierte Spot-App-Icon ist nicht enthalten.

---

# RJ Tracker 4.4.1 · native iOS + API Backend 20.3.1

Fix 4.4.1: MCP-Tool-Erkennung auch bei POST an die Domainwurzel und mit abschließendem Slash. Vorhandene Daten bleiben erhalten; die App zeigt die letzte erfolgreiche Erkennung. [Update 4.4.1](docs/UPGRADE-4.4.1.md).

Neu in 4.4: reparierte MCP-Discovery, sichtbarer Tool-Katalog, FindMy.py-Paketverwaltung, vollständiges Löschen importierter Apple-Tracker und erweiterte API-Werkzeuge. [Update 4.4](docs/UPGRADE-4.4.md).

Weiterhin: vollständige Kalendertage und freie Mehrfachauswahl, Benachrichtigungen leeren, native MCP-Verwaltung sowie MCP-Kontrollen im Admin-Bereich. [Update-Anleitung und Kompatibilität](docs/UPGRADE-4.3.md).

Native SwiftUI-/MapKit-App für Apple-, Google-, Samsung- und Fusion-Tracker. Android und der Android-Workflow wurden entfernt. Das Backend stellt die bisherigen Tracker-APIs sowie neue Import-, Geräte-, Passkey- und API-Key-Endpunkte bereit. Die Browseroberfläche unter `/` bietet ausschließlich Hauptadmin-Anmeldung, Statistik, Geräte-Abmeldung Passwortverwaltung sowie MCP- und FindMy.py-Verwaltung.

## Dateien

- `Backend/tracker_backend.py`: eigenständiges Python-Backend; keine separate Frontend-Datei erforderlich.
- `Backend/requirements.txt`: aktuelle stabile Python-Abhängigkeiten, fest versioniert.
- `App/`: nativer iOS-Client, iOS 18.1+, Liquid Glass ab iOS 26.
- `docs/API-EDITION.md`: Einrichtung, API-Beispiele und Migration.

## Bestehendes Backend aktualisieren

Backend stoppen, bisherigen `data/`-Ordner sichern und die neue Python-Datei an die Stelle der alten legen. Dateiname darf beibehalten werden. Bestehende Umgebungsvariablen, Accounts, Tracker-Schlüssel, Historien, Fusionen und Benutzer weiterverwenden. Bei anderem Speicherort `ULTRA_TRACKER_DATA_DIR` ausdrücklich auf den bestehenden Ordner setzen.

```sh
python3 -m pip install -r requirements.txt
python3 tracker_backend.py
```

Es wird keine neue Datenbank verlangt. Neue Gerätezugänge und API-Schlüssel werden ergänzend in `data/.client_access.json` gespeichert. Alte ESP32-Daten bleiben als inaktive Dateien erhalten; Firmware-Erstellung, Registrierung und Web-Flash stehen nicht mehr zur Verfügung. Alte Web-Tracker-/Freigabeseiten und Service Worker entfallen; Freigabe-Daten-APIs und MCP-OAuth bleiben für native Clients/Skripte verfügbar.

## iOS

Unter **Ich → Accounts, Import & Fusionen** Apple Account inklusive 2FA verbinden, Apple-Tracker-JSON oder Google-Secrets importieren, Samsung-Login-Link öffnen/teilen und die Rückleitungsadresse einfügen. Fusionen werden nativ aus vorhandenen Quellen eingerichtet. **Ich → Geräte & API-Schlüssel** verwaltet Sessions und Skriptzugriffe.

### JSON importieren ohne Picker

Unter **Accounts, Import & Fusionen → Apple-Tracker-JSON / Google secrets.json** stehen drei Wege bereit:

- **Datei:** nativer iOS-Picker, der auch generisch gekennzeichnete JSON-Dateien zulässt; der Inhalt wird anschließend validiert.
- **Text einfügen:** vollständigen JSON-Inhalt einfügen und prüfen. Optional als JSON-Datei lokal speichern.
- **App-Ordner:** in der Dateien-App unter **Auf meinem iPhone → RJ Tracker → Imports** Dateien ablegen, dann in der App den Ordner neu einlesen und eine Datei auswählen. Auch JSON-Dateien direkt im Ordner RJ Tracker werden angezeigt. Finder-/iTunes-Dateifreigabe ist aktiviert.

Die App erstellt den Imports-Ordner beim ersten Start. Lokale Dateien werden erst nach ausdrücklicher Importbestätigung auf den eigenen Server übertragen; Dateigröße maximal 1 MB. Lokale Kopien vertraulicher Schlüssel können danach in Dateien gelöscht werden.

### Standortverlauf und Batch-Reports

Backend 20.1 fragt Apple standardmäßig alle 20 Sekunden über `fetch_location_history` ab und speichert jeden eindeutigen Report eines Batches. Eine bewusst pausierte Aufzeichnung bleibt pausiert; neue Apple-Tracker und frühere Standardkonfigurationen sammeln automatisch. Bestehende individuelle Aufbewahrungsfristen bleiben gültig. Innerhalb dieser Frist begrenzt Apple die Speicherung nicht mehr auf eine feste Punktzahl. Providerfehler, langsame Antworten und die vorhandene globale Pause werden weiterhin berücksichtigt. Ein Abruf ist keine Garantie für neue Meldungen des Find-My-Netzes.

Die iOS-App zeigt standardmäßig **Übersichtlich**: nahe Meldungen werden nur für die Darstellung gebündelt. **Jeder Report** enthält alle geladenen Originalreports, auch bei gleichem Zeitpunkt und gleicher Position. Die Karte bündelt überlappende Marker nativ beim Herauszoomen; die Liste enthält die einzelnen Reports mit ihrer ID. CSV/GPX exportieren die geladenen Originalreports der Tages-/Quellenauswahl. CSV enthält zusätzlich Report-ID, Batch-ID und Empfangszeit.

Der geöffnete Verlauf übernimmt gespeicherte neue Reports alle fünf Sekunden über Cursor-Seiten. Auch ein später eingetroffener Report mit älterer Standortzeit wird berücksichtigt. Größere Historien werden automatisch nachgeladen; ein sichtbarer Ladehinweis bleibt bestehen, bis die Seiten geladen sind. Aufenthalte haben Datum, Dauer, Reportzahl und Genauigkeit und lassen sich direkt auf der Karte öffnen. Tages- und Quellenfilter schränken die Aufenthaltsliste ein; bei gemischten Aufenthalten beziehen sich die Kennzahlen weiterhin auf die serverseitige Auswertung über die beteiligten Quellen.

Die Tracker-Ansicht hat in jeder Höhe einen deckenden Hintergrund. Die App benötigt für die vollständige Live-Historie dieses Backend 20.1; ältere Server funktionieren weiterhin mit dem ausdrücklich bezeichneten bisherigen Ausschnitt.

Neue Passkeys und Passkey-Anmeldung starten direkt aus der App einen Sicherheitsdialog für die Serverdomain. Die Sicherheitsseite bietet keine Ortung. Der Rückkanal zur App nutzt einen einmaligen, an einen geheimen Verifier gebundenen Code. HTTPS ist dafür erforderlich; kein fest eingebauter Serverdomain-Entitlement nötig.

## IPA-Build

GitHub Actions baut bei Pull Requests gegen `main`, Push nach `main` oder manuellem Start die Release-App und erzeugt `RJ-Tracker-v5.6.0-unsigned.ipa` mit SHA-256-Prüfsumme. Backend-, Protokoll-, Migrations- sowie Debug- und Release-Startprüfungen sind Pflicht. Die Release-Startprüfung nutzt ein eigenes Scheme ohne Debug-Unit-Test-Abhängigkeiten.

Die IPA ist **unsigniert** und muss für das iPhone mit einem geeigneten Profil signiert werden. APNs benötigt zusätzlich die bestehenden Servervariablen für Team-ID, Key-ID und `.p8` sowie passende App-Entitlements beim Signieren.

## Rückkehr zum bisherigen Stand

- `backup/before-api-only-2026-10-06`: ursprünglicher Repositorystand einschließlich Android.
- `backup/ios-without-android-2026-10-06`: unmittelbar nach Android-Entfernung, vor iOS-/API-Umbau.

Für Rollback den Snapshot wiederherstellen oder einen Revert-Commit erstellen; die neuen Dateien allein ersetzen kein Backup der privaten Serverdaten.

### Apple-Anmeldung seit Oktober 2026

Für `Email verification failed` und fehlende Apple-Ortung siehe [Backend-Update 20.4.1](Backend/APPLE-UPDATE.md). Das Paket enthält mehrere Backend-Dateien; der bisherige Ein-Datei-Austausch und ein reines PyPI-Update reichen für diesen Fix nicht. Eine neue IPA ist dafür nicht erforderlich.
