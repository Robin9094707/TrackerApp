# RJ Tracker 5.6.0 / Backend 20.4.3

## Google-Ortung

- Nach einem Socket-Neustart bleiben noch nicht gesendete Ortungsanfragen bis zum Zeitlimit erhalten. Jede parallele Anfrage besitzt ihre eigene Anmeldung; ein fremder Abschluss oder ein altes Zeitlimit kann sie nicht versehentlich entfernen.
- Beim ersten Abruf wird der geladene Gerätekatalog verwendet, auch wenn die Oberfläche ihre zusammengefasste Liste noch nicht veröffentlicht hat.
- Im adaptiven Modus folgt bei ausbleibenden neuen Meldungen wieder ein begrenzter Versuch mit dem All-Areas-Abfragetyp. Alle späteren Pakete im jeweiligen Empfangsfenster werden weiterhin verarbeitet. Das ist keine Änderung der Google-Kontoeinstellung.
- Fehlende Schlüssel in Google-Teilantworten löschen keine bereits funktionierenden Geräteschlüssel. Ältere Metadaten überschreiben keine neueren entschlüsselten Schlüssel.
- Anzeige und Route verwenden den gültigen verfügbaren Standort und dessen Zeit/Genauigkeit. Ein ungültiger neuer lokaler Punkt verdrängt keinen gültigen Serverstandort. Die Übersicht zeigt laufende Google-Anfragen und bietet bei Serverfehlern einen erneuten Verbindungsversuch.

Google liefert nicht bei jedem Abruf einen neueren Standort. Die Korrekturen beheben nachgewiesene Fehler der Anfrageverarbeitung. Eine Ende-zu-Ende-Prüfung mit dem eigenen Konto und einem echten Tracker ist nach dem Installieren weiterhin nötig. Bestehende Zugänge werden weiterverwendet; bei einem reinen Verbindungsproblem ist kein erneuter Schlüsselimport vorgesehen.

## Server und Daten

Backend 20.4.3 ergänzt vorhandene Google-Geräte, statt bei einer unvollständigen Liste fehlende Geräte samt Verknüpfungen aus dem Katalog zu entfernen. Standortwerte wie NaN/Infinity gelangen nicht mehr in Google-Historien. JSON-Backups werden atomar ersetzt; eine beschädigte Primärdatei verdrängt keine gültige Sicherung. Ein gültiges `.bak` kann eine beschädigte oder fehlende Primärdatei wiederherstellen. Dies ersetzt kein eigenes externes Backup.

Neue App und Backend funktionieren mit den bisherigen API-/Speicherformaten. Datenpfade, Tracker-IDs, Kontositzungen, Google-Keychain-Service, Preferences, Core-Data-Modell und Historienformat bleiben unverändert. Bestehende Anmelde-/Abhängigkeitskorrekturen für Apple bleiben erhalten. Anfragen einer abgelösten Server-Sitzung können die neue App-Sitzung nicht mehr überschreiben.

## Update durch Dateiaustausch

1. Backend stoppen und den bisherigen Serverordner einschließlich `data/` bzw. des konfigurierten Datenverzeichnisses sichern.
2. Aus den Artefakten der GitHub Action **Build RJ Tracker IPA** die Datei `Tracker_Backend_AMP.py` herunterladen. Nur die bisherige Python-Startdatei damit ersetzen, am selben Ort und bei Bedarf unter dem bisherigen Dateinamen.
3. Bestehende Begleitdateien, `.tracker-apple-python-20.4.1`, `.tracker-apple-support`, `runtime/`, Datenverzeichnis, Startparameter und Umgebungsvariablen beibehalten. `ULTRA_TRACKER_DATA_DIR` muss weiterhin auf das bisherige Verzeichnis zeigen. Neu starten. Für dieses Update sind keine neuen Abhängigkeiten erforderlich.
4. `RJ-Tracker-v5.6.0-unsigned.ipa` aus demselben Action-Lauf mit der bisherigen Signierkonfiguration signieren und über die vorhandene App installieren. Bundle-ID bleibt `eu.rjuhas.rjtracker`. App vorher **nicht deinstallieren**; dieselbe Signierungsidentität/Keychain-Gruppe ist für den Zugriff auf bestehende geschützte Daten erforderlich.
5. Vorhandene Tracker und Verlauf prüfen, dann einen Google-Tracker manuell aktualisieren. Der Zeitstempel zeigt die letzte Meldung des Netzes, nicht den Zeitpunkt des Tastendrucks.

Die IPA ist wie im bisherigen Workflow unsigniert. Signierungszertifikate werden durch dieses Update nicht neu erzeugt. Der Pull Request muss für den Download und die Prüfung nicht zusammengeführt werden.

## Prüfungen und Quellen

Pflichtprüfungen in GitHub Actions: Backend-Regressionen einschließlich Google-Katalog und Backup-Wiederherstellung, AMP-Paketprüfung, Google-Protokoll-/Migrationsprüfungen, native Google-/App-Unit-Tests, ausgewählte UI-Tests sowie Kaltstart/Neustart der Release-App. IPA, SHA-256-Prüfsumme und AMP-Datei werden als Artefakte desselben Laufs bereitgestellt.

Protokollvergleich: [Spot](https://github.com/leonboe1/Spot/tree/55f87f62302fae24150188124e8e07d5285568d8) und [GoogleFindMyTools](https://github.com/leonboe1/GoogleFindMyTools/tree/660be5395702ff7f1a6174f4ec4c865a57c7b527). Nova-Endpunkt, Header, Anfragezuordnung und Entschlüsselungszweige wurden verglichen. Die vorhandenen gepinnten Pakete und Lizenzhinweise bleiben bestehen; die Korrekturen erfolgen gezielt in der integrierten Engine.
