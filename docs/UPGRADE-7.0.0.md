# RJ Tracker 7.0.0 · Backend 21.0.0

## Installation

1. Backend anhalten und den bestehenden Datenordner sichern.
2. `Tracker_Backend_AMP.py` anstelle der bisherigen Serverdatei ablegen. Bisherigen Dateinamen, Ordner, Port und Umgebungsvariablen beibehalten. Nicht mit einem leeren Datenordner starten.
3. Server starten. AMP-Einrichtung und vorhandene Apple-/Google-Umgebungen bleiben nutzbar.
4. `RJ-Tracker-v7.0.0-unsigned.ipa` mit der bisherigen Bundle-ID und Signierungsidentität signieren und über die bestehende App installieren. Nicht vorher deinstallieren.

Die Änderungen werden als Pull Request bereitgestellt. Das Erstellen des Builds installiert nichts auf dem laufenden Server und führt den Pull Request nicht zusammen. PANELAPios und die Android-App werden nicht geändert.

## Oberfläche

Das Tracker-Panel bietet eine vollflächige Übersicht mit adaptiven Karten, türkisfarbenem Akzent, ruhigem Hintergrund und direkten Einstiegen in Karte, Schultaschen und Bark. Die Darstellung passt sich iPhone, iPad, dunkler Darstellung und größerer Schrift an. Objekte, Orte, Meldungen und Kontoverwaltung bleiben erreichbar. Beim Öffnen eines Trackers erscheint direkt eine Karte seines letzten gültigen Standorts mit Genauigkeitskreis. Über die Vergrößern-Taste öffnet sie sich im Vollbild mit Zentrieren und Satellitenansicht. Das gilt für Apple-, Samsung-, Fusion- und Google-Tracker sowie lokal gespeicherte Google-Standorte und Serverstandorte bei Serverausfall. Ohne gültigen Standort erscheint ein klarer Hinweis; es wird kein Standort erfunden. Für diese Kartenanzeige ist kein Backend-Update nötig.

Die Übersichtskarte wird bei Bedarf geöffnet; die Objektliste liegt nicht mehr in einem dauerhaft eingeblendeten Kartenblatt.

## Schultasche

Unter **Objekte → Schultaschen** einen Server-Tracker wählen, Orte und Routinen festlegen und den Modus einschalten. Wochenübersicht und Tagesdetails beruhen auf denselben serverseitigen Auswertungen. Freie Tage lassen sich ausnehmen.

- **Pünktlich geortet:** eine bestätigte Meldung am Ort liegt innerhalb der eingestellten Toleranz vor.
- **Etwa N Minuten verspätet:** die erste bestätigte Ortung folgt einer präzisen Außenmeldung nach Schulbeginn und höchstens 15 Minuten vor der ersten Innenmeldung. Die Zeit bleibt eine Schätzung.
- **Erste Ortung +N Minuten:** Anwesenheit bestätigt, aber die wirkliche Ankunft kann früher gewesen sein. Keine behauptete Verspätung.
- **Anwesenheit nicht bestätigt:** keine ausreichende Ortung. Das bedeutet nicht, dass das Kind nicht in der Schule war. Geortet wird die Tasche.

Gemeldete Aufenthaltsdauer endet an der letzten Innenmeldung; lange Funklücken werden nicht als beobachtete Anwesenheit gezählt. Meldungen bei Ankunft, Verlassen, ausstehender Bestätigung und am Tagesende lassen sich pro Plan aktivieren. Erinnerungsabstand und Toleranz sind einstellbar. Änderungen erzeugen keine alten Warnungen nachträglich. Deduplizierung bleibt über einen Serverneustart erhalten.

Die vorhandenen Android-Links, Authentifizierung, Tracker-IDs und Antwortfelder bleiben erhalten. Bei einem in iOS eingerichteten Plan liefert der Server dessen Auswertung auch über die bestehenden Android-Schultaschen-Endpunkte. Ohne iOS-Plan wird die bisherige globale Konfiguration weiterverwendet. Androids ältere Oberfläche kennt die neuen Statusdetails nicht vollständig; „Ankunftszeit unklar“ bleibt ausdrücklich gekennzeichnet. Neue Einstellungen werden in iOS verwaltet.

## Bark

1. Bark auf dem iPhone installieren und dessen Geräteschlüssel kopieren.
2. In RJ Tracker **Bark & Sammelmeldungen** öffnen.
3. Serveradresse (standardmäßig `https://api.day.app`) und bis zu 50 Geräteschlüssel, einen pro Zeile, eintragen. Keine vollständigen Push-URLs.
4. Bark aktivieren und sichern; im Schulplan **Schulmeldungen senden** aktivieren.

Die Schlüssel liegen verschlüsselt auf dem Tracker-Server; die API gibt nur die Anzahl zurück. Eine leere Eingabe beim Sichern behält vorhandene Schlüssel. Neue Schlüssel ersetzen die Liste, „Verbindung entfernen“ löscht sie.

Standardmäßig sendet der Server einzeln an alle Empfänger. Die optionale Batch-API (`device_keys`) setzt Unterstützung des gewählten Bark-Servers voraus (bark-server ab 2.1.9). Sie wird nicht ungeprüft für jeden Server angenommen. Manuelle Sammelmeldungen benötigen Titel, Text und eine Bestätigung in der App; höchstens eine alle 30 Sekunden. Der Zustellstatus steht im Detail der Meldung. Bark bestätigt die Annahme beim Zustelldienst, nicht das Lesen auf dem iPhone. Ruhezeiten und der globale Benachrichtigungsschalter gelten weiterhin. Nach einer Teilzustellung werden nur noch fehlgeschlagene Empfänger erneut versucht. Bei einem Netzabbruch nach Annahme sind doppelte Pushes technisch möglich.

Bark benötigt eine laufende Serverinstanz, Internet sowie die Mitteilungsberechtigung der Bark-App. APNs der Tracker-App bleibt als bisherige Option erhalten.

## Google: Untersuchung und Änderungen

Geprüfte Originalquellen am 06.11.2026:

- [GoogleFindMyTools, letzter Protokollstand d46e952](https://github.com/leonboe1/GoogleFindMyTools/commit/d46e9528578015b51d3b84dd91bf8f16e9ab850f). Die folgende Revision 660be539 ändert nur den README-Link; ein blindes Update hätte die Ortung nicht repariert.
- [PR #114: beschädigte/erweiterte Push-Header, Entschlüsselungsfehler, hängende Wartevorgänge](https://github.com/leonboe1/GoogleFindMyTools/pull/114), geprüft bei `c378f8cffe5892c63de1361767eb1647dc584c45`.
- [PR #122: unterbrochener FCM-Empfänger](https://github.com/leonboe1/GoogleFindMyTools/pull/122), geprüft bei `85bf667bca1289b33dd8cd6898e9b714f5078719`.
- [BSkando/GoogleFindMy-HA](https://github.com/BSkando/GoogleFindMy-HA) und [diminDDL/OpenTagBridge](https://github.com/diminDDL/OpenTagBridge) als weitere gepflegte Ableger.
- [Bark Batch-API](https://github.com/finb/bark/blob/master/docs/en-us/batch.md).

Übernommen wurden gezielte Transportkorrekturen, kein vollständiger ungetesteter Fork-Wechsel: benannte Headerparameter statt fester Zeichenabschnitte, korrektes Base64url-Padding, fremde oder beschädigte Pakete isolieren, mehrere korrelierte Antwortpakete sammeln, doppelte Pakete verwerfen und Metadaten nicht mit einem fertigen Standortergebnis verwechseln. Der iOS-Empfänger erhält ebenfalls die Headerkorrektur.

Der Server liest entschlüsselte Protobuf-Werte direkt statt formatierte Konsolenausgabe auszuwerten. Ein defekter Standortreport verwirft nicht mehr die übrigen Meldungen. Reine Entschlüsselungsfehler werden getrennt von einem leeren Ergebnis diagnostiziert. FCM-Registrierung, Socket-Bereitschaft und Antwortfenster passen in das äußere Prozesszeitlimit. Vorhandene Schlüssel und letzte Standorte bleiben erhalten.

Diese Codekorrekturen sind offline reproduziert; echte neue Find-Hub-Meldungen und Anmeldung mit dem Nutzerkonto erfordern einen Test nach Installation. Schlüsselprobleme oder ausbleibende Meldungen des Google-Netzes können durch Transportkorrekturen allein nicht garantiert gelöst werden. Kein Konto, Schlüssel oder Tracker wird automatisch zurückgesetzt.

## Prüfungen

Die CI verlangt Backend-Regressionsprüfungen einschließlich bisheriger Android-/Gastlinks, isolierte Google-Paketprüfungen, Bark-API-/Retry-/Schlüsselprüfungen, Schulwochen-/Feiertags-/Zeitzonenprüfungen sowie iPhone-Unit- und UI-Tests einschließlich der Trackerkarten, Vollbildansicht und fehlender Standorte. Ein iPad-Simulatortest wird nicht ausgeführt. Die IPA wird erst nach erfolgreichem Release-Build, Debug-Tests und Release-Kaltstarttest veröffentlicht. Simulator-Screenshots liegen beim Testartefakt.
