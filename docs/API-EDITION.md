# API Edition 20 · Einrichtung & Schnittstellen

## Kurze Migration

1. Backend stoppen, Python-Datei und `data/` sichern.
2. Neue Python-Datei neben den bisherigen `data/`-Ordner legen; alternativ `ULTRA_TRACKER_DATA_DIR=/absoluter/bisheriger/data` setzen.
3. Python 3.11+ und `python3 -m pip install -r requirements.txt` verwenden.
4. Bestehende Umgebungsvariablen beibehalten, Backend starten und in der iOS-App mit derselben Serveradresse anmelden.

Die bisherigen JSON-Daten, Benutzer, Provider-Sitzungen, Tracker-IDs, Historien und Fusionen bleiben im alten Layout. Keine Löschung oder Neukonvertierung der Bestandsdaten ist erforderlich. Neu sind `.client_access.json` sowie temporäre, maximal fünf Minuten gültige Passkey-Übergaben. Der Standardbetrieb verwendet **einen Python-Prozess mit Threads**, wie das bisherige Backend; mehrere WSGI-Prozesse würden die temporären Login-/Providerzustände nicht teilen.

## Anmeldung

`POST /api/mobile/v1/pair` mit `{"username":"admin","pw":"…"}`. Für den Hauptadmin ist `username` optional. Antwort `status=two_factor_required` erfordert `POST /api/mobile/v1/pair/2fa` mit `{"code":"…"}`. Session-Cookies übernehmen; jede schreibende Session-Anfrage braucht den erhaltenen `X-CSRF-Token`.

`GET /api/mobile/v1/session` prüft die Sitzung. Die App sendet bei der Kopplung `X-RJ-Device-Label`; neu gekoppelte Sessions können einzeln unter `/api/v3/clients` widerrufen werden. Bereits vorhandene alte Sessions behalten ihren bisherigen Schutz; neu anmelden, damit sie in der Geräteliste erscheinen.

## Neue Schnittstellen

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/api/v3/info` | Version und Funktionen |
| GET | `/api/v3/schema` | OpenAPI-Katalog aller verfügbaren API-Routen |
| GET | `/api/v3/providers` | Verbindungsstatus und Anzahl der Provider-Geräte, ohne Secrets |
| POST | `/api/v3/import` | Apple-Accessory-JSON oder Google-Secrets importieren |
| DELETE | `/api/v3/trackers/{provider}/{tracker_id}` | Apple lokal entfernen; Google/Samsung archivieren und aus Fusionen lösen |
| GET | `/api/v3/clients` | Eigene registrierte Gerätesitzungen |
| DELETE | `/api/v3/clients/{id}` | Eine Gerätesitzung widerrufen |
| GET, POST | `/api/v3/keys` | Eigene Schlüssel auflisten / erstellen |
| DELETE | `/api/v3/keys/{id}` | Einen Schlüssel sofort widerrufen |
| POST | `/api/v3/auth/browser/start` | Einmaligen Übergang zur Passkey-Registrierung erstellen |
| POST | `/api/v3/auth/exchange` | Passkey-Sicherheitsdialog gegen native Session tauschen |

Die bisherigen `/api/mobile/v1`, Apple-, Google-, Samsung-, Fusion-, Historien-, Backup-, Alarm-, Benutzer- und Geofence-APIs bleiben bestehen. `/api/tracker-lab/*`, PWA-Manifeste, Service Worker und Browser-Push-Endpunkte sind entfernt. `/shared/*` und `/recovery/*` liefern keine Tracker-Website mehr; die entsprechenden JSON-Freigabe-APIs bleiben bestehen.

Der OpenAPI-Katalog beschreibt Pfade, Methoden, Path-Parameter, Authentication und Key-Scopes. Die komplexen älteren Request-/Response-Bodys bleiben dieselben wie vorher; der Katalog erzeugt hierfür keine vollständigen Models.

## Importe

Apple:

```json
{"provider":"apple","name":"Schluessel","content":{"...":"FindMy-Accessory-Daten"},"replace":false}
```

Google:

```json
{"provider":"google","content":{"...":"Inhalt deiner secrets.json"}}
```

Maximal 1 MB JSON. Apple wird vor dem Speichern durch den vorhandenen Accessory-Parser geprüft. Bei vorhandenem Namen wird ohne ausdrückliches `replace=true` abgelehnt. Google verlangt gültige `username`, `aas_token` und `fcm_credentials` gemäß GoogleFindMyTools. Eine gewöhnliche Google-OAuth-Anmeldung allein liefert diese Find-Hub-Schlüssel nicht. Deshalb unterstützt die App den Secrets-Import und Einrichtung/Prüfung des bestehenden Google-Providers; sie behauptet keinen separaten Google-Passwortlogin.

## Provider und Fusionen

Apple: `POST /api/login` mit `email,password`; bei `status=2fa` eine Methode aus der Antwort auswählen, `POST /api/2fa/request` mit `index`, dann `POST /api/2fa/submit` mit `code`. Ein verbundener Apple Account ersetzt keine importierte Tracker-Key-Datei und bietet keine automatische Liste aller offiziellen AirTags.

Samsung: `POST /api/samsung/auth/start` erzeugt `login_url`; der Link kann auf dem iPhone oder am Computer geöffnet werden. `POST /api/samsung/auth/complete` mit `redirect_url` speichert die Anmeldung und synchronisiert Geräte. Provider-Fehler werden in der App angezeigt. PIN: `POST /api/samsung/pin`. Das Verfahren hängt weiterhin von Samsungs Provider-Endpunkten ab.

Fusion: `POST /api/google/links` mit `apple_name,google_id` und/oder `POST /api/samsung/links` mit `apple_name,samsung_id`. Bei Konflikt wird **nicht still ersetzt**. Bestehende Verbindungen werden unverändert übernommen. DELETE auf `/api/{google|samsung}/links/{apple_name}` löst nur die Verbindung.

## API-Schlüssel für Skripte

Erstellen mit `POST /api/v3/keys`:

```json
{"label":"Windows-Skript","scopes":["read","locate"],"expires_days":90,"current_password":"…","current_code":"…"}
```

`current_code` nur bei aktiviertem 2FA erforderlich. Das Secret wird genau einmal in `token` zurückgegeben; gespeichert wird ausschließlich der SHA-256-Hash. Laufzeit 1–365 Tage, default 90 Tage. Widerruf und geänderte Passwort-/2FA-Generation sperren den Key. Kein Benutzer-, Passwort-, Credential- oder Backup-Zugriff für Keys. Rate-Limit: 120 Anfragen pro Minute und Key.

| Scope | Erlaubte Endpunkte |
|---|---|
| read | GET info, schema, mobile session/capabilities/trackers/tracker/history/alerts |
| locate | POST mobile locate; mobile action `locate` |
| manage | POST mobile action `update_tracker_details` |

```python
import json, urllib.request
request = urllib.request.Request(
    'https://dein-server/api/mobile/v1/trackers',
    headers={'Authorization':'Bearer rjt_DEIN_SCHLUESSEL', 'Accept':'application/json'})
with urllib.request.urlopen(request, timeout=30) as response:
    print(json.load(response))
```

Neue native Apps können für vollständige Konto-/Provider-Verwaltung die vorhandene Passwort-/2FA-/Passkey-Session-Anmeldung nutzen. API-Schlüssel benötigen keinen CSRF-Header und werden nicht in Session-Cookies umgewandelt.

## Passkeys

Server muss über HTTPS erreichbar sein. Hinter einem Proxy `ULTRA_TRACKER_PASSKEY_ORIGIN=https://deine-domain` verwenden und vorhandene RP-ID-Konfiguration beibehalten. Die App öffnet `/auth/passkey` in ASWebAuthenticationSession; Signaturen und Domain werden von der bisherigen WebAuthn-Logik geprüft. Callback `rjtracker://auth` enthält nur einen maximal 90 Sekunden gültigen Einmalcode und State; der geheime Verifier verbleibt in der App. Die Sicherheitsseite kann keine Tracker-Daten abrufen. App-Passwort und Provider-Passwörter werden nicht auf dem iPhone gespeichert.

## Admin und Notfallzugang

`/` und `/admin` bieten Hauptadmin-Login, Gesamtzahlen ohne Koordinaten, Geräte-Abmeldung und Passwort-Reset anderer Benutzer. Diese Browser-Sitzung darf keine Tracker-APIs aufrufen. Hauptpasswort liegt als gesalzener Hash in `data/.master_password.json`, niemals als Klartext.

Bei vergessenem Hauptpasswort auf dem Server:

```sh
ULTRA_TRACKER_DISABLE_BACKGROUND=1 python3 tracker_backend.py --reset-admin-password
```

Das neue Passwort wird verdeckt abgefragt, Mindestlänge zehn Zeichen. Bestehende Sitzungen/Keys werden ungültig. 2FA/Passkeys bleiben bestehen; bei verlorenem zweiten Faktor gelten die bisherigen Wiederherstellungscodes und Notfall-Dateien. Private Dateien und `data/` gehören nicht ins öffentliche GitHub-Repository.

## Validierung und Grenzen

Syntax, Backend-Start, Login, Bootstrap, API-Katalog, Providerstatus und begrenzte Key-Rechte werden kurz geprüft. Der iOS-Workflow baut die Release-IPA ohne umfangreiche Testläufe. Echte Apple-/Google-/Samsung-Logins und Ortungen brauchen deine vorhandenen Zugangsdaten und werden nicht durch einen erfolgreichen Build bewiesen. APNs benötigt weiterhin Apple-Push-Key und gültige Signierung. Die erzeugte IPA ist unsigniert.


## Backend 20.1 / iOS 4.2: vollständige Report-Historie

Direkt die Python-Datei ersetzen und denselben `data/`-Ordner weiterverwenden. Keine separate Migration nötig. Report-ID, Batch-ID und Empfangszeit ergänzen bestehende Punktfelder. Bereits gespeicherte Historien bleiben lesbar; früher verworfene Reports können nur wieder aufgenommen werden, wenn der Provider sie erneut liefert.

`GET /api/mobile/v1/history/stream?ref=apple:Tracker&days=7&limit=3000` liefert gespeicherte Originalreports, `matching_total`, `has_more` und `next_cursor`. Solange `has_more` wahr ist, denselben Abruf mit `cursor=<next_cursor>` wiederholen. Danach alle fünf Sekunden mit letztem Cursor und `replay=1` lesen; das kurze Überlappungsfenster schützt gleichzeitig veröffentlichte Batches. Clients deduplizieren über **network + report_id**, nicht über Koordinaten/Zeitstempel. Die Cursor sind an Referenz und Zeitraum gebunden und enthalten keine Schlüssel. Der Endpunkt verlangt den bestehenden Login bzw. einen API-Schlüssel mit read-Scope und löst selbst keine Provider-Abfrage aus.

`received_at` bezeichnet die lokale erstmalige Speicherung; `timestamp` bleibt der ursprüngliche Beobachtungszeitpunkt. Der Stream sortiert nach Empfangsreihenfolge, damit nachgelieferte ältere Messungen ankommen. Darstellung und Export können anschließend nach `timestamp` sortieren. Fusionen liefern in diesem Endpunkt die unveränderten Reports ihrer verbundenen Quellen, unabhängig von der optimierten Fusion-Anzeige.

`POST /api/polling/settings` mit `{"apple":{"interval_min":20,"interval_max":20}}` setzt die Apple-Abrufkadenz. Alte Standardfenster 20–30 Sekunden werden als 20 Sekunden behandelt; andere individuelle Einstellungen bleiben bestehen. Explizite Verlaufspausen, globale Pause und Fehler-Backoff werden beachtet. `apple_batch_reports_default` steuert die automatische Aufzeichnung unkonfigurierter Apple-Tracker. Bestehende Aufbewahrungsfristen bleiben verbindlich.
