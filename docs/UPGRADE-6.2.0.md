# RJ Tracker 6.2.0 · Schultasche und Routinen

Öffne als Hauptadmin **Objekte → Tracker → Schultasche & Routinen**. Aktiviere den Modus für dieses Objekt, lege Schule, Zuhause oder weitere Orte per Adresse oder Karte fest und speichere wöchentliche Zeitfenster. Die Tagesübersicht zeigt geplante Zeiten, bestätigte Meldungen und erkannte Aufenthalte. Sie reicht bis zu 30 Tage zurück, soweit Standortmeldungen vorliegen. Die Orte und Zeitfenster gelten jeweils für den eingerichteten Tracker. Reine On-Device-Tracker benötigen einen zugehörigen Server-Tracker.

## AMP-Update

1. Stoppe die Instanz. Sichere die bisherige Startdatei und den bestehenden Datenordner.
2. Lade aus dem iOS-Build das Artefakt **RJ-Tracker-Backend-20.7.1-AMP** und entpacke `Tracker_Backend_AMP.py`.
3. Ersetze die bisherige Startdatei durch diese Datei. Behalte den vorhandenen Dateinamen, Ordner, Datenpfad und die AMP-Startparameter bei.
4. Starte die Instanz und prüfe die Startmeldung für Version 20.7.1.

Das Update enthält die Schultaschen- und Freigabe-Schnittstellen des Android-Backends 20.7.0. Vorhandene Android-Freigaben verwenden weiterhin ihre gemeinsamen Orte und ihren Stundenplan. Persönliche iOS-Routinen werden separat pro Tracker gespeichert.

Die iOS-IPA ist unsigniert. Signiere sie mit derselben Identität wie die bisherige Version und installiere sie über die vorhandene App.
