# RJ Tracker 5.0 – Google direkt auf dem iPhone

Die vollständigen Tracker-Funktionen von Spot sind als SpotIntegration in derselben RJ-Tracker-App enthalten. Mindestversion iOS/iPadOS 18.1. Bundle-ID `eu.rjuhas.rjtracker`, bestehender Server-Keychain-Service und Server-Session bleiben erhalten. Die App über die vorhandene Installation installieren und mit demselben Bundle-Identifier signieren. Vorheriges Löschen der App würde lokale App-Daten entfernen.

## Nutzung

- In der Objektübersicht **Google Find Hub** öffnen. Ohne Serverkopplung ist derselbe Einstieg auf der Anmeldeseite verfügbar.
- Bluetooth/Standort nach Wunsch freigeben, Google-Anmeldung in der App abschließen. AAS-Token, FCM und Eigentümerschlüssel entstehen auf dem iPhone.
- Bei gesperrten Trackern die Schlüsselwiederherstellung öffnen und den Google-Schritten folgen. Ein Android-Sperrmuster muss laut Spot für diesen Schritt vorübergehend auf PIN/Passwort geändert werden.
- Alternativ beim Google-Login **JSON importieren** oder nachher in den Google-Einstellungen wählen. `username`, `aas_token` und optionale 32-Byte-Hexschlüssel `owner_key`/`shared_key` werden lokal importiert. FCM wird für dieses iPhone registriert; ein Server-FCM-Client wird nicht kopiert.
- Tracker werden direkt aus deinem Google-Konto geladen. Klingeln funktioniert in Bluetooth-Reichweite direkt, sonst als Google-Anfrage. Standortberichte, Freigaben/Einladungen, Umbenennen, Verlustmodus, Löschen und eigene ESP32-Tracker bleiben über die integrierten Spot-Menüs erreichbar.
- Google-Tracker erscheinen zusätzlich in der RJ-Objektübersicht und auf der Karte. Bereits serverseitig vorhandene Google-Kartenmarker werden nicht doppelt angezeigt. Lokale Google-Funktionen öffnen die lokale Detailansicht; Server-Automationen, Fusionen und Serververlauf bleiben in ihren bisherigen Ansichten.

## Daten und Server

Der lokale Google-Zugang ist unabhängig von der Google-Sitzung im Backend. Schlüssel und Tokens werden nicht automatisch hochgeladen. Lokale Google-Verläufe liegen in separaten SQLite-Dateien je Google-Konto. Beim Abmelden bleiben sie erhalten. Abmeldungen entfernen die lokalen Google-Tokens.

Das Backend-Update ist für lokale Google-Funktionen nicht erforderlich. Version 20.4.0 ergänzt ausschließlich den authentifizierten Leseendpunkt `GET /api/mobile/v1/google/local` und die Capability `google_local_client`. Es ändert keine vorhandenen Datenschemata, Pfade oder Schlüsseldateien. Vorhandene Apple-, Google-, Samsung- und Fusion-Daten bleiben im bisherigen Datenordner.

Zum Update den bisherigen Dienst stoppen, eine Sicherung des vorhandenen Datenordners erstellen, nur `tracker_backend.py` ersetzen und den Dienst mit denselben Umgebungsvariablen, derselben Python-Umgebung und demselben `ULTRA_TRACKER_DATA_DIR` starten. `Backend/requirements.txt` ist unverändert. API-Details: `docs/API-EDITION.md`.

## Build und Prüfung

GitHub Actions **Build RJ Tracker IPA** wird bei Push auf main und manuell gestartet. Es prüft das Backend, erzeugt das Xcode-Projekt, baut das integrierte Framework und die App und stellt `RJ-Tracker-v5.0.0-unsigned.ipa` als Artefakt bereit. Zum Installieren mit deinem Signaturdienst signieren.

Google-Protokolle sind inoffiziell. Echte Google-Anmeldung, Geräte-Schlüsselwiederherstellung, Bluetooth-Klingeln und Reichweitensuche benötigen dein Konto und echte Hardware; ein erfolgreicher Build ersetzt diese Gerätetests nicht. Die Nahsuche verwendet wie Spot Bluetooth-Signalstärke, kein UWB-Richtungssystem. Gewerbliche Tracker werden weiterhin über ein kompatibles Android-Gerät gekoppelt.

## Lizenzen

Spot von Leon Böttger (GPL-3.0-only), Version und Anpassungen in `Vendor/Spot/UPSTREAM.md`. Vollständiger Quellcode, GPL und Drittanbieterhinweise sind enthalten. Das ausgeschlossene Spot-App-Icon wird nicht übernommen; RJ Tracker verwendet sein eigenes generiertes Icon.
