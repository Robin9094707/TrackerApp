# RJ Tracker 4.2 · native iOS + API Backend 20.1

Native SwiftUI-/MapKit-App für Apple-, Google-, Samsung- und Fusion-Tracker. Android und der Android-Workflow wurden entfernt. Das Backend stellt die bisherigen Tracker-APIs sowie neue Import-, Geräte-, Passkey- und API-Key-Endpunkte bereit. Die Browseroberfläche unter `/` bietet ausschließlich Hauptadmin-Anmeldung, Statistik, Geräte-Abmeldung und Passwortverwaltung.

## Dateien

- `Backend/tracker_backend.py`: eigenständiges Python-Backend; keine separate Frontend-Datei erforderlich.
- `Backend/requirements.txt`: aktuelle stabile Python-Abhängigkeiten, fest versioniert.
- `App/`: nativer iOS-Client, iOS 17+, Liquid Glass ab iOS 26.
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

GitHub Actions baut bei Push nach `main` die Release-App und erzeugt `RJ-Tracker-v4.2.0-unsigned.ipa`. Standardmäßig laufen keine Simulator-/UI-Tests. Optionale bisherige Review-Tests bleiben auf ausdrücklichen Workflow-Input beschränkt.

Die IPA ist **unsigniert** und muss für das iPhone mit einem geeigneten Profil signiert werden. APNs benötigt zusätzlich die bestehenden Servervariablen für Team-ID, Key-ID und `.p8` sowie passende App-Entitlements beim Signieren.

## Rückkehr zum bisherigen Stand

- `backup/before-api-only-2026-10-06`: ursprünglicher Repositorystand einschließlich Android.
- `backup/ios-without-android-2026-10-06`: unmittelbar nach Android-Entfernung, vor iOS-/API-Umbau.

Für Rollback den Snapshot wiederherstellen oder einen Revert-Commit erstellen; die neuen Dateien allein ersetzen kein Backup der privaten Serverdaten.
