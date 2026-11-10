# RJ Tracker 8.x · Backend 22.x · Overhaul

Aktuell: App 8.1.0 (Build 34) und Backend 22.1.0. Die Schritte gelten für 8.0 und 8.1 gleichermaßen; die Dateien heißen `RJ-Tracker-v8.1.0-unsigned.ipa` und `Tracker_Backend_AMP.py`.

## Installation

1. Backend anhalten und den bestehenden Datenordner sichern.
2. `Tracker_Backend_AMP.py` (22.1.0) anstelle der bisherigen Serverdatei ablegen. Dateiname, Ordner, Port und Umgebungsvariablen bleiben gleich. Nicht mit einem leeren Datenordner starten.
3. Server starten. Alle Tracker, Verläufe, Fusionen, Taschen, Freigaben, Bark-Schlüssel und Anmeldungen bleiben unverändert erhalten. Es gibt keine Datenmigration; neue Felder werden nur ergänzt.
4. `RJ-Tracker-v8.1.0-unsigned.ipa` mit der bisherigen Bundle-ID und Signierungsidentität signieren und über die bestehende App installieren. Nicht vorher deinstallieren.

Die App 8.0 funktioniert auch mit Backend 21.x. Nur Netz-Priorität, Taschen-Schalter und Web-App benötigen Backend 22.0.

## Web-App

Unter `https://<dein-server>/app` läuft eine responsive Web-App (Desktop, Tablet, Handy; auf dem iPhone über „Zum Home-Bildschirm“ installierbar):

- Karte mit allen Objekten, Genauigkeitskreisen, Satellitenansicht, Hell/Dunkel
- Orten einzeln oder alle, Routenplanung
- Standortverlauf pro Tag mit Strecke, Aufenthalten und Zeitachse
- Taschen festlegen und Tagesstatus/Woche ansehen
- Mitteilungen
- Netz-Priorität für Fusionen

Login wie in der App, auch mit Zwei-Faktor-Code. Die Web-App verwendet nur die vorhandene, per Sitzung und CSRF geschützte Mobile-API. Jede Browser-Anmeldung erscheint unter **Geräte & API-Schlüssel** und lässt sich dort abmelden. Die Admin-Oberfläche unter `/` bleibt unverändert.

## Netz-Priorität für Fusionen

Im Tracker-Detail einer Fusion unter **Netz-Priorität & Backup** (oder in der Web-App):

| Modus | Verhalten |
|---|---|
| Neuester Report (Standard, wie bisher) | Die jüngste Meldung aller Netze wird angezeigt. |
| Priorität mit Backup | Das Hauptnetz wird bevorzugt. Ein Backup-Netz wird angezeigt, sobald seine Meldung die eingestellte Zahl an Minuten neuer ist. |
| Nur Hauptnetz | Nur das Hauptnetz. Andere Netze nur, wenn das Hauptnetz noch nie gemeldet hat. |

Die Reihenfolge der Netze ist frei wählbar. **Backup-Netze abfragen:**
- **Immer:** Alle Netze sammeln parallel. Das liefert die meisten Reports.
- **Nur wenn Hauptnetz veraltet:** Backups werden erst abgefragt, wenn das Hauptnetz länger als die Wartezeit nichts geliefert hat. Das schont Konten und Rate-Limits.

Gespeicherte Rohreports werden nie verändert. Verlauf und Schultaschen-Auswertung nutzen weiterhin alle Reports aller Netze.

## Taschen

Jedes Objekt kann jetzt per Schalter eine Tasche sein, auch Fusionen aus Apple, Google und Samsung: im Tracker-Detail, unter **Ich → Taschen & Wochenübersicht** oder in der Web-App. Bei einer Fusion sammeln alle beteiligten Netze den Verlauf. Beim Ausschalten bleibt ein vorhandener Tagesplan erhalten und gilt beim erneuten Einschalten wieder.

## Mehr Reports – was wirklich hilft

- **Apple:** Das Find-My-Netz hält Reports etwa 7 Tage vor. Der Server ruft bei aktivem Verlauf alle 20–30 Sekunden den kompletten Verlauf ab und speichert jeden eindeutigen Report. Mehr geht über Apple nicht.
- **Google Find Hub:** Standardmäßig zeigt Google einen Tracker nur, wenn mehrere Android-Geräte ihn gesehen haben („nur an belebten Orten“). Auf allen eigenen und geteilten Android-Geräten in den Find-Hub-Einstellungen unter **Offline-Geräte finden** die Option **In allen Gebieten / Überall auffindbar** wählen. Das bringt deutlich mehr Meldungen in ruhigen Gegenden. Das ist eine Einstellung auf dem Android-Gerät, kein Server-Schalter.
- **Samsung:** Es gibt keine offizielle Verlaufs-API. Der Server nutzt weiterhin die SmartThings-Find-Schnittstelle, die sich jederzeit ändern kann.
- **Fusionen:** „Backup immer abfragen“ liefert die meisten Reports. Die Priorität bestimmt nur, was angezeigt wird.

## Server-Optimierung

Große JSON- und HTML-Antworten werden gzip-komprimiert, wenn der Client das unterstützt. Das betrifft Bootstrap, Verlauf und Web-App. Die App nutzt das automatisch.

## Build

Die GitHub Action erstellt die IPA direkt nach dem Release-Build und lädt sie hoch. Danach läuft nur noch der Release-Kaltstarttest. Backend-Tests laufen vorher im Backend-Job.
