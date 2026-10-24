# RJ Tracker 5.2.0 / Build 20

## Installieren

`RJ-Tracker-v5.2.0-unsigned.ipa` mit derselben Signierungsidentität und Bundle-ID `eu.rjuhas.rjtracker` über Version 5.1.2 installieren. Vorhandene App nicht vorher löschen. Mindestversion bleibt iOS 18.1. `SHA256SUMS.txt` enthält die Prüfsumme. Backend und Server-Datenordner benötigen kein Update.

Google-Keychain-Service, Konto-Preferences, verschlüsselte Archive, bisherige Verläufe und Serverzugänge behalten ihre Speicherorte. Die bisherige Auswahl `native.localMode=false` verhindert den lokalen Notbetrieb nicht mehr. Die neue Option ist standardmäßig eingeschaltet.

## Google und Filter

Google-Karte, Google-Verbindungsstatus und Google-Einstellungen erscheinen bei **Alle Netze** und **Google**. Unter Apple, Samsung oder Fusion ist die zusätzliche Google-Karte ausgeblendet. Ein leerer Filter erhält eine Leermeldung, auch wenn andere Google-Tracker existieren.

## Wenn dein Server ausfällt

Mit gespeichertem lokalem Google-Zugang öffnet sich die Hauptansicht auch während einer Server-Wiederherstellung, bei Zeitüberschreitung oder abgelaufener Server-Sitzung. Google-Anmeldung, Abruf, Entschlüsselung, lokale Historie und Bluetooth funktionieren weiterhin unabhängig von deinem eigenen Tracker-Server. Google-Funktionen benötigen gegebenenfalls weiterhin Googles Dienste und Internet; ein Serverausfall ist kein vollständiger Offline-Modus.

Die optionale Serveranbindung bleibt erhalten. Im Vordergrund prüft die App eine ausgefallene Verbindung erneut; ein ausdrücklich abgemeldeter Server wird nicht automatisch angemeldet. Unter **Ich → Mit Tracker-Server verbinden** kann man die Server-Anmeldung öffnen und schließen, ohne die lokale Google-Ansicht zu verlassen. Serverabhängige Ansichten sind während des Ausfalls als solche gekennzeichnet. Ein schon geladener Serverstand wird gegebenenfalls weiter als alter Stand angezeigt, nach einem Kaltstart wird kein nicht vorhandener Servercache behauptet.

Unter **Ich → Einstellungen → Google ohne eigenen Server** kann der automatische lokale Einstieg ausgeschaltet werden. Diese Google-Option ist nur bei passendem Netzwerkfilter sichtbar.

## Automatischer Google-Verlauf

- Pro lokalem Google-Tracker: **Verlauf automatisch sammeln**. Bisherige Tracker bleiben standardmäßig aktiv; bestehende Punkte werden beim Pausieren nicht gelöscht.
- Google-Konto → Aktualisierung: bestehendes Vordergrundintervall, unabhängig von der Serververbindung.
- Optional **Verlauf auch im Hintergrund anfragen**. Die App meldet einen iOS-Hintergrundversuch mit frühestens 15 Minuten an. iOS kann ihn verschieben, kürzen oder auslassen; kein festes Hintergrundintervall. Manuelle Einstellung des Abrufintervalls auf „Manuell“ unterbindet diese automatischen Versuche ebenfalls.
- Manuelle Einzelabrufe und **Alle Tracker orten** funktionieren auch bei pausiertem automatischem Sammeln und speichern empfangene Berichte. Beim Entsperren gesicherter Originalberichte können ebenfalls Punkte nachgetragen werden.

Die lokalen Google-Daten werden nicht automatisch in den eigenen Server hochgeladen. Bestehende Server-Verlaufsaufzeichnungen bleiben ein separater kompatibler Pfad.

## UWB-Experiment

Google-Tracker → **UWB prüfen · experimentell** liest iPhone-Fähigkeiten und versucht eine authentifizierte Google-UWB-Capability-Abfrage am eigenen Tracker. **Keine fertige UWB-Pfeilortung für Moto Tag 1.** Die Hürde ist der noch nicht nachgewiesene kompatible Sitzungsaustausch mit Apples Nearby Interaction. [Untersuchung und Quellen](UWB-INVESTIGATION.md).

## Validierung

Pipeline: Backend-Regressionen; Google-Protokoll und Datenbankmigration; Unit-Tests für Serverausfall/Wiederverbindung, Filter und Migration der lokalen Option; Google-Sammeloptionen pro Konto/Tracker; authentifizierte UWB-Testpakete inklusive Manipulation, falscher Schlüssel, Nonce, Trunkierung und ungültiger Längen; Simulator-UI für lokale Google-Ansicht bei Serverausfall und während Wiederherstellung, Filter und UWB-Hinweise; Release-Kaltstart und Neustart. Erst nach erfolgreichen Pflichtprüfungen wird die IPA erzeugt.

Echte Moto-Tag-Antworten, Bluetooth-Reichweite und Hintergrundzuteilung durch iOS sind mit eigener Hardware zu prüfen.
