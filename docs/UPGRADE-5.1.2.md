# RJ Tracker 5.1.2 installieren

## Dateien

- `RJ-Tracker-v5.1.2-unsigned.ipa`: iPhone-/iPad-App ab iOS 18.1, muss vor Installation mit dem eigenen Profil signiert werden.
- `SHA256SUMS.txt`: SHA-256 der IPA, im selben GitHub-Actions-Download.
- Quellcode einschließlich Backend: Repository-Download zum zugehörigen Commit.
- `Backend/tracker_backend.py` und `Backend/requirements.txt`: bestehendes Backend bleibt kompatibel und ist für dieses Update unverändert. Ein Backendwechsel ist nicht erforderlich.

## Aktualisieren

1. IPA mit derselben Signierungsidentität wie bisher signieren; Bundle-ID `eu.rjuhas.rjtracker` beibehalten.
2. Über die vorhandene App installieren. Nicht vorher löschen; sonst können lokale App-Daten verloren gehen.
3. App öffnen, erneut öffnen und vorhandene Serververbindung und Google-Konto prüfen.
4. In **Google Find Hub** aktualisieren. Bei gesperrten Reports die vorhandene Schlüsselwiederherstellung verwenden.
5. Mit eigenen Trackern Standortabruf, Entschlüsselung, Bluetooth und Klingeln prüfen. Google kann eine erneute Anmeldung verlangen.

Server-Datenordner, Google-Keychain-Service, Konto-Preferences, verschlüsselte Archive und Core-Data-Verläufe verwenden die bisherigen Speicherorte. Keine Löschmigration und kein neuer Server erforderlich. Vorhandene Sicherungen behalten.

## Behobene Fehler

Die letzten Builds von 5.1.1 scheiterten beim Kompilieren der Release-Tests, weil Unit-Tests auf ausschließlich in Debug vorhandene Beispieldaten zugriffen. Ein separates `RJTrackerReleaseLaunch`-Scheme prüft jetzt die echte optimierte App ohne diese Unit-Test-Abhängigkeit. Die Debug-Tests bleiben unverändert aktiv. Es werden keine Beispieldaten in die Release-App aufgenommen.

Bei Google-Berichten hatten die Dublettenprüfung und die IDs der Verlaufszeilen unterschiedliche Merkmale: Höhe und semantische Namen konnten verloren gehen oder dieselbe Zeilen-ID ergeben. Beide Pfade verwenden nun dieselbe vollständige Identität. Auch die Datenbank unterscheidet Genauigkeitsänderungen und übernimmt Ortsbezeichnungen beim Neuladen. Ein Test prüft getrennte Speicher-Batches und wiederholtes Einlesen. Bestehende Daten bleiben lesbar.

## Prüfumfang

Die Pipeline prüft Backend, Google-Stream-Fragmentierung und Mehrfachmeldungen, Timeouts/Abbruch, Preference-Übernahme, Core-Data-Migration, Konto-Verlaufsisolation, Report-Identitäten, API-/Verlaufslogik sowie Debug-UI und Release-Kaltstart/Neustart. Erst danach wird eine IPA bereitgestellt.

Das eigene Apple-/Google-/Samsung-Konto und echte Geräte sind nicht Teil der automatisierten Tests. APNs benötigt die passende Signierung/Entitlements und vorhandene Serverkonfiguration. Im Hintergrund gelten die iOS-Grenzen. Die IPA ist kein bereits signierter App-Store- oder TestFlight-Build.
