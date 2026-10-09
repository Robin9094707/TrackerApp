# RJ Tracker 4.4 / Backend 20.3

## Daten erhalten

Serverdienst stoppen und den bestehenden Datenordner sichern. Die Python-Datei am bisherigen Ort ersetzen; den bisherigen Dateinamen und Startbefehl beibehalten. `ULTRA_TRACKER_DATA_DIR` muss weiterhin auf den vorhandenen Ordner zeigen. Den Datenordner nicht löschen, verschieben oder neu anlegen. Danach den Serverdienst starten. Schema 19.0, Accounts, Schlüssel, Verlaufsformate, Freigaben und Benutzer bleiben kompatibel. Neue Paketwartungsinformationen liegen ergänzend in `.findmy_update.json`.

Die IPA ist unsigned. Für die Installation mit der eigenen bisherigen Signiermethode signieren; dieselbe Bundle-ID `eu.rjuhas.rjtracker` und Signieridentität verwenden. Die App als Update installieren, nicht vorher deinstallieren.

## ChatGPT neu verbinden

Unter **Ich → Server verwalten → ChatGPT / MCP** die Konfiguration prüfen und den Tool-Katalog öffnen. Die Diagnose prüft lokal HTTPS-Konfiguration, Anmeldung und Tool-Erzeugung; sie garantiert nicht die öffentliche Erreichbarkeit.

Bei der Meldung „Authentication succeeded, action discovery failed“ erst Backend und IPA aktualisieren. Danach die fehlgeschlagene Verbindung in ChatGPT entfernen und mit dem angezeigten MCP-Link und OAuth neu anlegen. Im geöffneten Serverfenster mit Master-/Kontopasswort und gegebenenfalls 2FA anmelden. Bestehende funktionierende Verbindungen müssen nicht pauschal widerrufen werden. Widerruf ist weiterhin einzeln oder gesammelt möglich.

Die kompatiblen älteren Protokolle bleiben erhalten. 2026-07-28-Anfragen bekommen `resultType: complete`; fiktive Protokollrevisionen werden nicht mehr zugesagt. Der stateless Server gibt keine ungespeicherte Session-ID mehr aus. Jeder Tool-Descriptor hat genau ein OAuth-Schema und spiegelt es in `_meta`. Altverbindungen sehen nur die durch ihre granularen Scopes erlaubten Tools. Die Ursache auf einem fremden laufenden Server lässt sich ohne dessen Logs und URL nicht abschließend nachweisen.

## FindMy.py aktualisieren

**Ich → Server verwalten → FindMy.py & Serverpakete**, alternativ die HTML-Administration. Nur der Hauptadmin kann Versionen prüfen und Pakete installieren. Der Server muss in einer eigenen Python-venv laufen und pip sowie Zugriff auf PyPI haben. Nach einer aktuellen Versionsprüfung kann nur die dabei ermittelte offizielle stabile Version installiert werden; freie Paketnamen, URLs oder Shellbefehle werden nicht angenommen.

Das Update lädt zuerst alte und neue Wheels, prüft die neue API und Abhängigkeiten isoliert, erstellt ein privates Backup des Hauptkontos mit Zugangsdaten und installiert ausschließlich das geprüfte FindMy-Paket. Eine inkompatible Version wird vor der Installation abgelehnt. Die bestehenden Abhängigkeiten werden nicht automatisch verändert. Bei einem Installationsfehler wird das alte Paket zurückgespielt. Das Datenformat wird dabei nicht migriert. Danach den Serverdienst mit der bisherigen Dienstverwaltung neu starten. Die App zeigt installierte und geladene Version getrennt an.

## Apple-Tracker entfernen

Im Detailmenü eines **Apple**-Trackers **Aus dieser App löschen** wählen und bestätigen. Importdatei, aktive App-Daten, Verlauf, Alarme, Freigaben, Recovery und direkte Fusion-Zuordnungen werden entfernt. Ein vorher angelegtes privates Backup enthält weiterhin die alten Daten und den Importschlüssel; falls auch diese Kopie entfernt werden soll, das Backup ausdrücklich unter Backups löschen. Die Bindung im Apple-Wo-ist?-Konto kann diese API nicht entfernen. Bei laufender Apple-Ortung die Löschung nach deren Abschluss wiederholen. Andere Anbieter und deren Verlaufsdaten bleiben erhalten.

Google- und Samsung-Geräte bleiben kontosynchronisiert; einzelne Geräte können ausgeblendet oder archiviert werden.

## Alle API-Endpunkte

**Ich → Erweitert → API-Werkzeuge** liest den vollständigen Katalog der laufenden Backend-Version. Für häufige Aufgaben gibt es native Formulare; weitere Funktionen sind über die erweiterte Konsole erreichbar. Pfadparameter ausfüllen, Methode wählen, Query-Parameter an den Pfad anhängen und JSON-, Formular- oder Dateidaten senden. Dateien maximal 20 MB, eventuell strengere Grenzen des Zielendpunkts gelten zusätzlich. Antwortdateien können gespeichert/geteilt werden. Die Konsole ersetzt keine Serverberechtigung und bietet keine automatische Beschreibung unbekannter Request-Bodys.

## Rollback

GitHub-Backup: `backup/before-mcp-discovery-2026-10-09` am Stand `056d7385e5e5247062863d75f3b2a8fd2310ddba`. Zum Rückwechsel auf Backend 20.2 den Server stoppen und dessen Python-Datei aus diesem Branch zurücklegen; vorhandene Daten weiterverwenden. Ein separat aktualisiertes FindMy-Paket bei Bedarf auf seine vorherige Version zurücksetzen. App 4.3 kann weiterhin mit den bestehenden Daten arbeiten.
