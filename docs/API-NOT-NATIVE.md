# API-Endpunkte ohne direkten nativen Aufruf – iOS 2.1.1

Abgleich des iOS-Quellcodes mit der hochgeladenen Backend-Datei `findmyairtags 2(3).py`. Stand: 6. September 2026. Keine dieser zusätzlichen Funktionen wird durch diesen Bericht implementiert.

**Definition:** Die Tabellen nennen HTTP-Methoden, für die keine fest eingebaute native iOS-Funktion einen direkten Request sendet. Die manuelle API-Konsole und das eingebettete Web Studio sind ausgenommen. Das ist eine statische Codeanalyse, keine Auswertung tatsächlicher Serverzugriffe. Manche Routen sind Alternativen zu bereits genutzten Mobile-Aktionen oder Bootstrap-Daten und bedeuten daher keine fehlende Funktion.

Erfasst: **200 verschiedene API-Pfade**. **19 Pfade** werden direkt genutzt. Bei **183 Pfaden** bleibt mindestens eine HTTP-Methode ohne direkten nativen Aufruf (darunter teilweise genutzte Pfade).

## Noch ungenutzte Mobile-Aktionen

Unter `POST /api/mobile/v1/action` fehlen eigene Bedienelemente für:

- `mark_recovery_found` – einen Recovery-Fall als wiedergefunden markieren.
- `global_pause` – automatische Serverabrufe zentral pausieren/fortsetzen.

## Vollständige Liste nach Bereichen

### Weitere Tracker-, Verlaufs- und Systemrouten

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| POST | `/api/2fa/request` |  |
| POST | `/api/2fa/submit` |  |
| POST | `/api/apple/auth/logout` |  |
| GET | `/api/device/<name>/insights` |  |
| POST | `/api/devices` |  |
| DELETE | `/api/devices/<name>` |  |
| GET | `/api/exports/history` | CSV/GPX werden in der App lokal erzeugt. |
| POST | `/api/geofences` | Erstellen über Mobile-Aktion bereits vorhanden. |
| DELETE, POST | `/api/geofences/<gid>` | Ändern/Löschen über Mobile-Aktionen bereits vorhanden. |
| GET | `/api/health/details` |  |
| POST | `/api/history/maintenance` |  |
| GET, POST | `/api/history/policy/<provider>/<path:tracker_id>` | Verlauf/Aufbewahrung bereits über Mobile-Aktion set_history einstellbar. |
| GET | `/api/history7/<name>` | Verlaufssteuerung/-abruf teilweise bereits über Mobile history/action vorhanden. |
| POST | `/api/history7/<name>/start` | Verlaufssteuerung/-abruf teilweise bereits über Mobile history/action vorhanden. |
| POST | `/api/history7/<name>/stop` | Verlaufssteuerung/-abruf teilweise bereits über Mobile history/action vorhanden. |
| POST | `/api/locate/<name>` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/locate/all` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/locate/apple/all` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/locate/google/all` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/locate/samsung/all` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/login` |  |
| DELETE, GET, POST | `/api/mcp/settings` |  |
| POST | `/api/meta/<name>` |  |
| POST | `/api/record/<name>/start` |  |
| POST | `/api/record/<name>/stop` |  |
| POST | `/api/reset/<name>` |  |
| POST | `/api/reverse-geocode` | Adressauflösung in der App über CoreLocation. |
| GET | `/api/route/history7/<name>` |  |
| GET | `/api/route/session/<name>/<int:s_id>` |  |
| DELETE, GET | `/api/session/<name>/<int:s_id>` |  |
| POST | `/api/settings/background` |  |
| POST | `/api/settings/pause` |  |
| GET | `/api/state` |  |
| POST | `/api/trackers/<provider>/<path:tracker_id>/visibility` |  |
| GET | `/api/v2/activity` |  |
| GET | `/api/v2/audit` |  |
| GET, POST | `/api/v2/places` | Orte sind über Bootstrap und Mobile-Aktionen bereits nutzbar. |
| DELETE, GET, POST | `/api/v2/places/<place_id>` | Orte sind über Bootstrap und Mobile-Aktionen bereits nutzbar. |
| POST | `/api/v2/settings/freshness` |  |
| GET, POST | `/api/v2/trackers/<provider>/<path:tracker_id>/details` | Bearbeiten ist bereits über Mobile-Aktion update_tracker_details vorhanden. |
| GET | `/api/v2/trackers/<provider>/<path:tracker_id>/preferences` | POST vorhanden; GET separat fehlt. Werte kommen auch über Bootstrap. |

### Konten, Sicherheit und Benutzer

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| GET, PATCH | `/api/account/profile` |  |
| GET, POST | `/api/admin/users` |  |
| DELETE, PATCH | `/api/admin/users/<user_id>` |  |
| POST | `/api/admin/users/<user_id>/2fa/reset` |  |
| POST | `/api/admin/users/<user_id>/passkeys/reset` |  |
| POST | `/api/passkeys/auth/begin` |  |
| POST | `/api/passkeys/auth/finish` |  |
| POST | `/api/password-reset/confirm` |  |
| POST | `/api/password-reset/request` |  |
| DELETE, GET | `/api/security/2fa` |  |
| POST | `/api/security/2fa/confirm` |  |
| POST | `/api/security/2fa/setup` |  |
| GET | `/api/security/2fa/setup/qr` |  |
| GET | `/api/security/passkeys` |  |
| DELETE, PATCH | `/api/security/passkeys/<credential_id>` |  |
| POST | `/api/security/passkeys/register/begin` |  |
| POST | `/api/security/passkeys/register/finish` |  |
| POST | `/api/security/password` |  |
| POST | `/api/unlock` |  |
| POST | `/api/unlock/2fa` |  |

### Benachrichtigungen und Kurzbefehle

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| POST | `/api/alerts/automation-tokens` |  |
| DELETE | `/api/alerts/automation-tokens/<token_id>` |  |
| POST | `/api/alerts/channels/<channel>` |  |
| DELETE, GET | `/api/alerts/console` |  |
| POST | `/api/alerts/console/client` |  |
| GET | `/api/alerts/console/export` |  |
| DELETE, GET | `/api/alerts/events` |  |
| DELETE, POST | `/api/alerts/events/<event_id>` |  |
| POST | `/api/alerts/events/<event_id>/retry` |  |
| POST | `/api/alerts/settings` |  |
| POST | `/api/alerts/test` |  |
| POST | `/api/alerts/trackers/<provider>/<path:tracker_id>` |  |
| GET | `/api/alerts/webpush/public-key` |  |
| DELETE, POST | `/api/alerts/webpush/subscriptions` |  |
| GET | `/api/shortcut/status` |  |

### Fusion und Vergleichstests

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| GET, POST | `/api/comparison-tests` |  |
| DELETE, GET | `/api/comparison-tests/<test_id>` |  |
| POST | `/api/comparison-tests/<test_id>/finish` |  |
| POST | `/api/comparison-tests/<test_id>/refresh` |  |
| POST | `/api/fusion/profiles/<path:apple_name>/locate` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/fusion/profiles/<path:apple_name>/optimization` |  |
| GET | `/api/fusion/profiles/<path:apple_name>/route/history` |  |
| DELETE | `/api/fusion/tests/<test_id>` |  |
| POST | `/api/fusion/tests/<test_id>/refresh` |  |
| GET | `/api/fusion/tests/<test_id>/route` |  |
| POST | `/api/fusion/tests/<test_id>/stop` |  |
| POST | `/api/fusion/tests/start` |  |

### Recovery und Fallexporte

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| GET, POST | `/api/exports/cases` |  |
| DELETE, GET | `/api/exports/cases/<job_id>` |  |
| GET | `/api/exports/cases/<job_id>/download` |  |
| DELETE, GET | `/api/recovery/<name>` |  |
| POST | `/api/recovery/<name>/activate` | Start über Mobile-Aktion start_recovery bereits vorhanden. |
| POST | `/api/recovery/<name>/found` |  |
| GET | `/api/recovery/<name>/pdf` |  |
| POST | `/api/recovery/<name>/resolve-addresses` |  |
| POST | `/api/recovery/<name>/settings` |  |
| POST | `/api/recovery/<name>/share` |  |
| DELETE | `/api/recovery/<name>/share/<link_id>` |  |

### Google-Netzwerk

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| DELETE | `/api/google/devices/<path:device_id>/history` |  |
| POST | `/api/google/devices/<path:device_id>/history/start` | Verlaufssteuerung/-abruf teilweise bereits über Mobile history/action vorhanden. |
| POST | `/api/google/devices/<path:device_id>/history/stop` | Verlaufssteuerung/-abruf teilweise bereits über Mobile history/action vorhanden. |
| POST | `/api/google/devices/<path:device_id>/locate` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/google/devices/<path:device_id>/record/start` |  |
| POST | `/api/google/devices/<path:device_id>/record/stop` |  |
| GET | `/api/google/devices/<path:device_id>/route/history` |  |
| DELETE, GET | `/api/google/devices/<path:device_id>/sessions/<int:session_id>` |  |
| POST | `/api/google/devices/<path:device_id>/settings` |  |
| POST | `/api/google/devices/sync` |  |
| POST | `/api/google/guardian/reload-secrets` |  |
| POST | `/api/google/guardian/repair` |  |
| GET | `/api/google/guardian/status` |  |
| POST | `/api/google/links` |  |
| DELETE | `/api/google/links/<path:apple_name>` |  |
| POST | `/api/google/probe` |  |
| DELETE, POST | `/api/google/secrets` |  |
| POST | `/api/google/settings` |  |
| DELETE | `/api/google/tests/<test_id>` |  |
| GET | `/api/google/tests/<test_id>/route` |  |
| POST | `/api/google/tests/<test_id>/stop` |  |
| POST | `/api/google/tests/start` |  |
| POST | `/api/google/tools` |  |
| POST | `/api/google/tools/dependencies` |  |
| POST | `/api/google/tools/download` |  |

### Freigaben und Gastzugriff

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| GET, POST | `/api/internal-shares` |  |
| DELETE, PATCH | `/api/internal-shares/<share_id>` |  |
| POST | `/api/internal-shares/<share_id>/locate` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/recovery-share/<link_id>` |  |
| POST | `/api/share/<name>/password` |  |
| POST | `/api/share/<name>/permissions` |  |
| POST | `/api/share_history/<name>/<state_str>` |  |
| POST | `/api/shared/<link_id>` |  |
| POST | `/api/shared/<link_id>/address` |  |
| POST | `/api/shared/<link_id>/locate` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| DELETE, GET, POST | `/api/shared/<link_id>/push` |  |
| GET | `/api/shared/<link_id>/push/public-key` |  |

### Mobile API: zusätzliche Abrufe und Geräteverwaltung

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| GET | `/api/mobile/v1/advanced` | Zusammengefasster Abruf; Diagnose/Speicher sind teilweise schon über Einzelrouten eingebunden. |
| GET | `/api/mobile/v1/alerts` | Separater Abruf; Meldungen kommen bereits über Bootstrap. |
| DELETE, GET | `/api/mobile/v1/push` | POST-Registrierung vorhanden; GET-Geräteliste und DELETE-Abmeldung fehlen. |
| GET | `/api/mobile/v1/tracker` | Einzelabruf; die App liest Tracker bereits über Bootstrap/Katalog. |

### Samsung-Netzwerk

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| POST | `/api/samsung/auth/complete` |  |
| POST | `/api/samsung/auth/logout` |  |
| POST | `/api/samsung/auth/start` |  |
| DELETE | `/api/samsung/devices/<path:device_id>/history` |  |
| POST | `/api/samsung/devices/<path:device_id>/history/start` | Verlaufssteuerung/-abruf teilweise bereits über Mobile history/action vorhanden. |
| POST | `/api/samsung/devices/<path:device_id>/history/stop` | Verlaufssteuerung/-abruf teilweise bereits über Mobile history/action vorhanden. |
| POST | `/api/samsung/devices/<path:device_id>/locate` | Ortung existiert bereits über Mobile locate/action; diese Route wird nicht direkt genutzt. |
| POST | `/api/samsung/devices/<path:device_id>/record/start` |  |
| POST | `/api/samsung/devices/<path:device_id>/record/stop` |  |
| GET | `/api/samsung/devices/<path:device_id>/route/history` |  |
| POST | `/api/samsung/devices/sync` |  |
| POST | `/api/samsung/links` |  |
| DELETE | `/api/samsung/links/<path:apple_name>` |  |
| DELETE, POST | `/api/samsung/pin` |  |
| POST | `/api/samsung/settings` |  |

### Tracker-Labor und Firmware

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| POST | `/api/tracker-lab/<kind>/<record_id>/build` |  |
| DELETE | `/api/tracker-lab/<kind>/<record_id>/delete` |  |
| GET | `/api/tracker-lab/<kind>/<record_id>/firmware/<path:filename>` |  |
| GET | `/api/tracker-lab/<kind>/<record_id>/manifest` |  |
| POST | `/api/tracker-lab/<kind>/<record_id>/retire` |  |
| POST | `/api/tracker-lab/apple/create` |  |
| GET | `/api/tracker-lab/esptool-js.js` |  |
| POST | `/api/tracker-lab/flash/finish` |  |
| POST | `/api/tracker-lab/flash/force-release` |  |
| POST | `/api/tracker-lab/flash/heartbeat` |  |
| POST | `/api/tracker-lab/flash/start` |  |
| POST | `/api/tracker-lab/google/refresh` |  |
| POST | `/api/tracker-lab/google/register` |  |
| DELETE | `/api/tracker-lab/jobs` |  |
| DELETE | `/api/tracker-lab/jobs/<job_id>` |  |
| POST | `/api/tracker-lab/jobs/<job_id>/cancel` |  |
| POST | `/api/tracker-lab/multi/create` |  |
| GET | `/api/tracker-lab/status` |  |
| POST | `/api/tracker-lab/toolchain/install` |  |

### ÖPNV-Erkennung

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| POST | `/api/transit/analyze` |  |
| GET, POST | `/api/transit/settings` |  |
| GET | `/api/transit/status` |  |

### Backups und Speicherverwaltung

| Methode ohne direkten Aufruf | Endpunkt | Einordnung |
|---|---|---|
| GET, POST | `/api/v2/backups` |  |
| DELETE, GET | `/api/v2/backups/<name>` |  |
| POST | `/api/v2/backups/<name>/restore` |  |
| POST | `/api/v2/storage/cleanup` |  |
| POST | `/api/v2/storage/cleanup/preview` |  |
| POST | `/api/v2/storage/policy` |  |
