# RJ Tracker 5.1 – native Google-Integration

Google ist jetzt eine Datenquelle der bestehenden TrackerApp. Die komplette Spot-Einführung, Navigation, Geräteansichten und die LUI-Oberflächenbibliothek wurden entfernt. Übernommen wurden ausschließlich Protokoll-, Verschlüsselungs-, Bluetooth- und Speicherfunktionen.

## Bestehende Anmeldung übernehmen

Die IPA mit derselben App-ID `eu.rjuhas.rjtracker` über die bestehende App installieren. Nicht vorher löschen. Der Keychain-Service `.spot.credentials`, die Google-Preference-Suite und die kontospezifischen Verlaufsdateien behalten ihre bisherigen Namen. Ein vorhandener AAS-Token reicht zum Fortsetzen, unabhängig davon, ob die alte Einführung abgeschlossen wurde. Bei einem unterbrochenen abschließenden Token-Austausch versucht die App, den vorhandenen Google-Login-Cookie zu übernehmen. Falls Google keine gültige Sitzung mehr liefert, die Anmeldung in den nativen Google-Einstellungen erneuern.

FCM-Registrierung und Push-Verbindung können die Oberfläche nicht mehr unbegrenzt blockieren. Der Datenstrom wird ohne blockierende Semaphore verarbeitet. Registrierung, TLS-Verbindung und Token-Austausch haben Zeitlimits; ein Fehler löscht keine bestehende Anmeldung.

## Tracker und Aktualisierung

Google-Geräte erscheinen direkt zwischen Apple-, Samsung- und Fusion-Objekten auf derselben Karte und in derselben Liste. Bei derselben kanonischen Google-ID wird der neuere Standort verwendet, ohne einen zweiten Tracker anzulegen. Lokale Google-Aktionen verwenden die native Google-Verbindung.

Unter **Google Find Hub → Aktualisierung** ist der Vordergrundabruf auf manuell, 1, 2, 5 oder 15 Minuten einstellbar. Standard: 1 Minute, alle verfügbaren Bereiche. Google bestimmt, wann neue Reports bereitstehen. Im Hintergrund gelten iOS-Systemgrenzen; es wird keine feste Hintergrundrate versprochen.

Jeder Standortabruf hört 35 Sekunden auf weitere passende Push-Nachrichten. Mehrere Pakete sowie fragmentierte Netzwerkpakete werden in Reihenfolge verarbeitet. Alle unterschiedlichen Reports bleiben erhalten; Wiederholungen werden anhand von Zeit, Status, eigener Sichtung und Standort/Payload zusammengeführt. Verschlüsselte Originalberichte werden geschützt pro Konto gespeichert und nach dem Entsperren erneut verarbeitet. Die optionale Core-Data-Eigenschaft für semantische Ortsnamen wird per leichter Migration ergänzt; vorhandene Dateien werden nicht gelöscht.

Kurzlebige Google-Zugriffstokens werden aus dem gespeicherten AAS-Token erneuert. HTTP 401/403 erlaubt einen erneuten Token-Austausch, ohne den langfristigen Zugang zu entfernen. Es gibt keine Garantie für unbegrenzte Google-Sitzungen: Widerruf oder Sicherheitsprüfungen von Google können eine erneute Anmeldung verlangen.

## Nutzung

- Google-Konto und Aktualisierung direkt in den nativen Einstellungen öffnen.
- Bei gesperrten Standorten **Google-Schlüssel entsperren** verwenden. PIN/Passwort des Android-Geräts kann von Google verlangt werden; Sperrmuster sind im zugrunde liegenden Verfahren nicht unterstützt.
- Im Tracker sind Aktualisieren, alle Reports, Klingeln, Bluetooth-Nahsuche, Namen, Verlustmodus und Freigaben native App-Ansichten.
- Der bestehende Tracker-Server und sein Datenordner bleiben unverändert. Für 5.1 ist kein neues Backend erforderlich.

Die Action testet Fragmentierung, mehrere Reports, Timeouts, Mehrfach-Callbacks, Abbruch und die v5.0-Preference-Übernahme ohne Simulator. Zusätzlich sind iOS-Datenbank- und UI-Tests enthalten. Echte Anmeldung, Entschlüsselung und Klingeln benötigen das eigene Google-Konto und echte Tracker.
