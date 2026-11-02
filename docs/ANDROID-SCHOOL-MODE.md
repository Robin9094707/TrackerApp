# RJ Tracker Android 1.0 · Schultaschenmodus · Backend 20.7.0

Native Android-App (Kotlin, Jetpack Compose, Material 3) für Familienmitglieder **ohne Konto**: Sie nimmt Gastfreigaben und dauerhafte Schultaschen-Links an und speichert sie, bis sie ablaufen oder entfernt werden.

## Einrichten (einmalig)

1. **Backend aktualisieren:** Die Python-Startdatei durch die neue `Tracker_Backend_AMP.py` (20.7.0) ersetzen, gleicher Name, gleicher Ort. In AMP neu starten. Daten bleiben erhalten.
2. **Admin-Seite öffnen:** `https://find.rjuhas.eu/` → als Hauptadmin anmelden → Bereich **Schultaschen & Freigaben**.
3. **Tracker als Schultasche markieren:** Beim gewünschten Tracker „Als Schultasche“ wählen (Apple, Google, Samsung oder Fusion; mehrere möglich) und optional den Namen des Kindes eintragen. Der Server sammelt ab dann alle Reports dieser Tasche dauerhaft im Verlauf (Apple alle 20 s, Google alle 30–35 s, Samsung alle 20–30 s).
4. **Dauerhaften Link erzeugen:** Begrüßungsnamen eintragen (z. B. „Jessy“) → „Neuen Link erzeugen“. Der Link wird kopiert. Er lautet `https://find.rjuhas.eu/school/…` und kann jederzeit widerrufen werden.
5. **App installieren:** `RJ-Tracker-Android-v1.1.1.apk` auf dem Handy öffnen (Installation aus unbekannten Quellen erlauben).
6. **Link in der App einfügen:** Nach der Begrüßung und kurzen Einführung „Aus Zwischenablage einfügen“ → „Verbinden“. Alternativ den Link direkt antippen; Android öffnet ihn in der App.
7. **In der App Orte festlegen:** Tab **Orte** → „Schule festlegen“ und „Zuhause festlegen“ (Karte verschieben, Radius einstellen). Dann **Einstellungen** (Zahnrad) → Stundenplan (Schulbeginn, optional Schulende, schulfreie Tage) speichern.

Gastlinks für einzelne Tracker (auch einzelne Google- oder Samsung-Tracker) entstehen im selben Admin-Bereich unter **Gastlink erstellen** (mit Passwort, Ablaufzeit, optional Verlauf und „Gast darf aktualisieren“). Bestehende Gastlinks funktionieren in der App ebenfalls.

## Was die App kann

- **Heute:** Status (pünktlich, verspätet, noch nicht da, nicht in der Schule), Schulweg mit „Zuhause verlassen → unterwegs → in der Schule → Schule verlassen“ samt Dauer, letzter Standort mit Adresse, Genauigkeit, Batterie und **Navigieren** (nur dieser Knopf öffnet Google Maps).
- **Verlauf:** Tage der letzten drei Wochen, Route aus allen Reports und Batch-Reports, Aufenthalts-Cluster mit Anzahl, Start/Ende, Zeitreise-Regler, Orts-Besuche mit Ankunft, Verlassen und „zuletzt dort“.
- **Protokoll:** Verspätungs- und Anwesenheitsprotokoll (bis 400 Tage) mit Ankunft, Verlassen, Aufenthaltsdauer, Abfahrt von Zuhause und Wegzeit; bei Abwesenheit, wo die Tasche stattdessen war. **Protokoll teilen** erzeugt einen Text, z. B. als Nachweis.
- **Orte:** Zuhause, Schule und weitere Orte mit Radius.
- **Aktualisieren:** löst einen sofortigen Abruf aus; danach erscheint unten ein kurzer Hinweis „Neuer Standort aufgetaucht“ oder „Kein neuer Standort aufgetaucht“. Bei geöffneter App wird alle 20 s neu geladen.
- **Benachrichtigungen** je Ereignis **Aus / Einmal / Immer**: Zuhause verlassen, Schule erreicht, Schule verlassen (mit Aufenthaltsdauer), Zuhause angekommen, Verspätung, nicht in der Schule, weitere Orte. Ohne Konto und ohne Firebase: Ein unauffälliger Hintergrund-Wächter fragt alle 30 s beim Server nach (abschaltbar; dann alle 15 min). Für zuverlässige Zustellung in den Einstellungen „Akku-Optimierung ausschalten“ wählen.

## Wie Ankunft und Verlassen berechnet werden

AirTags und Find-Hub-Tracker melden sich über fremde Handys und sind manchmal ungenau. Der Server wertet deshalb alle Reports mit einer Hysterese aus:

- Ein Report zählt als „drinnen“, wenn sein Genauigkeitskreis den Ort erreicht und die Genauigkeit zur Ortsgröße passt. Reports mit mehr als 1 km Ungenauigkeit werden ignoriert.
- **Ankunft** braucht zwei Reports im Ort (oder einen sehr genauen, der 8 Minuten lang nicht widerlegt wird). Die Ankunftszeit ist der erste dieser Reports.
- **Verlassen** braucht Reports deutlich außerhalb einer Pufferzone (Radius + 40 bis 200 m): mindestens zwei über vier Minuten, drei Reports, einen sehr weit entfernten genauen Report oder einen genauen Report, der 20 Minuten lang nicht widerlegt wird. Ein einzelner Ausreißer zählt nie als „verlassen“.
- Kurze Unterbrechungen unter 6 Minuten werden zu einem Aufenthalt zusammengeführt. Gespeichert werden sowohl „verlassen um ca.“ als auch „zuletzt dort“.
- Abwesenheits- und Verspätungsmeldungen kommen nur zeitnah zur jeweiligen Frist und nie rückwirkend für einen gerade erst eingerichteten Stundenplan.

## Karte und Signatur (GitHub-Secrets)

Die Action **Build RJ Tracker Android** baut die APK, führt Unit-Tests aus und testet die App im Emulator gegen ein echtes Backend mit Testdaten (Screenshots als Artefakt).

| Secret | Zweck |
|---|---|
| `ANDROID_KEYSTORE_BASE64` + `ANDROID_KEYSTORE_PASSWORD` | Fester Signaturschlüssel, damit neue APKs über die installierte App aktualisieren. Der Schlüssel liegt **nicht** im öffentlichen Repository. Ohne Secret wird mit einem Test-Schlüssel signiert. |
| `ANDROID_MAPS_API_KEY` (optional) | Google-Maps-Karte in der App. Ohne Schlüssel nutzt die App eine vollwertige OpenStreetMap-Karte. Der Schlüssel benötigt das „Maps SDK for Android“ (Google Cloud, mit Abrechnungskonto) und sollte auf das Paket `eu.rjuhas.rjtracker.android` mit dem SHA-256 des Signaturzertifikats beschränkt werden. |

Der Server liefert unter `/.well-known/assetlinks.json` den Fingerabdruck des Signaturschlüssels, damit Android `https://find.rjuhas.eu/school/…` und `/shared/…` direkt in der App öffnet. Für einen anderen Schlüssel `ULTRA_TRACKER_ANDROID_CERT_SHA256` setzen.

## Neue Server-Schnittstellen (20.7.0)

Öffentlich, Token im Pfad, ohne Konto: `GET /api/school/<token>`, `…/history?ref&from&to`, `…/attendance?days`, `…/events?after`, `POST …/locate`, `POST …/places`, `DELETE …/places/<id>`, `POST …/schedule`. Gastfreigaben für native Apps: `POST /api/shared/<id>/app` (Passwort einmalig, danach `X-Share-Token`), `…/app/history`, `…/app/locate`. Admin (Hauptadmin-Sitzung): `GET /admin/api/school`, `POST /admin/api/school/bags`, `POST|DELETE /admin/api/school/links`, `POST|DELETE /admin/api/shares`. Bisherige Endpunkte, Datenformate und die iOS-App bleiben unverändert; die Daten des Schultaschenmodus liegen zusätzlich in `data/school_mode.json`.
