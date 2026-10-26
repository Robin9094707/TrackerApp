# RJ Tracker 5.5.0

- Einheitliche deutsche Standortzeiten, auch bei englischer Gerätesprache; automatische Aktualisierung der Anzeige.
- Google und Server-Tracker nutzen dieselbe kompakte Standortübersicht. Der Name steht einmal in der Navigationsleiste; ein größerer verschiebbarer Detailbereich verkleinert den Kartenanteil.
- Google: direktes „Jetzt orten“, Aktualisieren in der Titelleiste und Herunterziehen. Die Übersicht fragt alle lokalen Google-Tracker parallel an, auch bei pausierter Automatik. Ein Google-only-Abruf wartet nicht auf den optionalen Server.
- Der Ladezustand endet pro Tracker nach einer verarbeiteten Antwort oder einem Fehler, spätestens nach dem Empfangszeitlimit. Weitere Pakete werden weiterhin entschlüsselt, gespeichert und angezeigt. Alte Rückmeldungen können einen neuen Abruf nicht beenden.
- Google bestimmt, wann neue Standorte verfügbar sind. Eine Antwort garantiert keine neue Sichtung. Ohne Antwort bleiben bisherige Standorte sichtbar; ein erneuter Abruf ist möglich.

## Installation und Daten

Die Action „Build RJ Tracker IPA“ läuft auch für Pull Requests. Nach den bestehenden Pflichtprüfungen erzeugt sie `RJ-Tracker-v5.5.0-unsigned.ipa` mit Prüfsumme. Kleine zusätzliche Tests prüfen deutsche Zeitgrenzen, parallele Google-Abrufe mit verspäteten Rückmeldungen und die Detailansicht.

Mit dem bisherigen Profil signieren und über die vorhandene App installieren. Bundle-ID `eu.rjuhas.rjtracker` bleibt gleich; die App nicht vorher löschen. Schlüsselbund, Google-Konto, Einstellungen, Core-Data-Modell und Reports bleiben erhalten. Das Backend und seine Datenformate sind unverändert. Kein Serverupdate erforderlich.

## Spot-Abgleich

Referenz: leonboe1/Spot, Commit `55f87f62302fae24150188124e8e07d5285568d8`. Geräteabfrage, LocationRequest, Anfrage-UUID und FCM-Antworten sind bereits integriert. Upstream beendet seine Ladeanzeige auf eine Antwort; diese Version ergänzt einen Schutz vor alten Rückmeldungen und verarbeitet weiterhin spätere Pakete. Vorhandene Transportzeitlimits, Streaming-Verarbeitung, Auth-Wiederholung und Archivierung bleiben erhalten.

Echte Google-Anmeldung, Standorte, Bluetooth-Klingeln und Hardware benötigen für die abschließende Prüfung ein eigenes Konto und Tracker. Simulatorprüfungen verwenden Testdaten.
