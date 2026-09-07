# iOS 2.2.0

- Konto und Profil bearbeiten; Hauptadministrator kann Benutzer anlegen, bearbeiten, deaktivieren, löschen sowie Passwort, 2FA und Passkeys zurücksetzen.
- Passwortwechsel, Authenticator-Einrichtung mit lokal erzeugtem QR-Code, 2FA-Bestätigung und einmalige Wiederherstellungscodes. Rotierende CSRF-Tokens aus Sicherheitsantworten werden übernommen.
- Passkeys auflisten, umbenennen und entfernen. Neue Passkeys werden über die HTTPS-Website des gekoppelten Servers eingerichtet, weil die Registrierung an dessen Domain gebunden ist.
- Backups erstellen, herunterladen/teilen, wiederherstellen und löschen. Wiederherstellung verlangt eine Bestätigung und nutzt das automatische Vorab-Backup des Servers.
- Interne Freigaben an andere Benutzer erstellen, Rechte ändern, deaktivieren, entfernen sowie freigegebene Standorte und Verläufe ansehen und Ortung anfordern.
- Google Guardian prüfen, Reparatur starten und Zugangsdaten neu einlesen.
- Netzwerkvergleiche starten, Meldungen anfordern, Ergebnisse ansehen, beenden und löschen.
- Speicherbereinigung nach Kategorie mit verbindlicher Servervorschau und ausdrücklicher Bestätigung.
- Automatische Ortung global pausieren/fortsetzen und Recovery-Fälle als gefunden abschließen.
- Aktualisieren lädt den Tracker-Katalog statt stets des vollständigen Bootstrap-Pakets. „Alle Tracker orten“ ist eine separate Menüaktion. Einzelortung bestätigt die Anfrage sofort nach Serverantwort und lädt Standorte gezielt im Hintergrund nach.
- Verlauf startet mit 24 Stunden, merkt sich den Zeitraum und nutzt einen 45-Sekunden-Cache sowie gemeinsam verwendete laufende Abrufe. Ziehen lädt neu. Sortierung und Linienaufbereitung erfolgen einmal pro Datensatz/Netzfilter; die Meldungsliste lädt weitere Zeilen auf Wunsch.
- Karten- und GPX-Linien werden je Ortungsnetz getrennt. Ungültige Punkte, Duplikate, große Lücken und unplausible Sprünge werden berücksichtigt. Ein auf die neuesten 2.000 Punkte begrenztes Serverergebnis wird ausdrücklich als Ausschnitt bezeichnet.

Validierung: zusätzliche Unit-Tests für CSRF-Wechsel, History-Cache, gezielte Trackerabfrage und getrennte Netzverläufe; Simulatorprüfung für Konto/Sicherheit und Verlauf im IPA-Workflow. Der Buildstatus ist separat in GitHub Actions zu prüfen. Provider-Latenz und serverseitige Verlaufsauswertung bleiben vom jeweiligen Server/Ortungsnetz abhängig. Vollständige Metadaten werden im Vordergrund etwa alle zwei Minuten und bei gezieltem Aktualisieren entsprechender Seiten nachgeladen.

# iOS 2.1.1

- Filter und Sortierung über App-Neustarts speichern, einschließlich „Neueste zuerst“ und „Nächste zuerst“.
- Bei gespeicherter Entfernungssortierung die eigene Position mit vorhandener Berechtigung aktualisieren.
- Deckender Panelhintergrund bei jeder Höhe, auch im Dunkelmodus.
- Fehlende Einbindung des Asset-Katalogs korrigiert und eigenes Radar-/Pin-Icon in allen iPhone-/iPad-Größen ergänzt.
- IPA-Erstellung prüft Assets.car, AppIcon-Dateien und CFBundleIcons.

# iOS 2.1.0

- Kompakter Detailkopf und Kartenübersicht mit Platz für das Objektpanel.
- Native Gruppen erstellen, bearbeiten, löschen und Objekte zuordnen.
- Passwortgeschützte Gastfreigaben mit Ablauf, Standortgenauigkeit und Zugriffsrechten; bestehende Links ausdrücklich ersetzen oder widerrufen.
- Objekte ausblenden/archivieren und im Archiv wiederherstellen.
- Serverzentrale mit Netzwerkstatus, validierten Ortungsintervallen, Schnellprüfung und Speicherübersicht.
- Kontowechsel schützt vor verspäteten Antworten; erste Synchronisierung erzeugt keine Benachrichtigungsflut.
- GPX-Dateityp und CSV-Export verbessert; vorhandene Aufbewahrung beim Bearbeiten bleibt erhalten.
- API-Werkzeuge unterstützen Query-Parameter. Web-Backend und Android unverändert.
- Simulatorprüfungen verwenden synthetische Daten; Gastfreigaben nur für vom bestehenden Share-Endpunkt unterstützte Apple-/Fusion-Objekte.

# RJ Tracker iOS 2.0

The iOS app now uses a single MapKit canvas with a native, resizable inspector on iPhone and a sidebar on iPad. Objects, places, alerts and account settings share this navigation. System tab bars, toolbars, menus and sheets adopt Liquid Glass on iOS 26; the deployment target remains iOS 17 with native material fallbacks. Content cards use standard system surfaces rather than stacking glass effects.

## Features

- Search names, notes, aliases and supplied addresses; filter by network, favorites, freshness and server groups; sort by favorite, name, newest report or distance to the iPhone.
- Synchronize every 30 seconds while the app is active. Server failures retain the last in-memory snapshot and label it clearly. Locate requests wait for actual newer timestamps and explain when no new report has arrived.
- Favorite changes synchronize through the existing preferences API. Edit a tracker's name, emoji and note without changing its provider ID or history links.
- See fusion network timestamps and accuracy individually, with the server's disagreement explanation.
- Configure found/departure alarms and history retention. Add a geofence at the selected object, scoped to that object and its linked sources.
- Choose saved places and geofence centers on the map or use an existing tracker. Rename/edit saved places and confirm deletion. Own-location access is requested only when used and stays on the iPhone.
- Choose walking, driving or transit directions in Apple Maps. Share a timestamped location snapshot through the system share sheet (this is not a live server share).
- Filter history by source, scrub/play observations, inspect accuracy and export the displayed subset to CSV or GPX. Break lines across gaps over 30 minutes or implausible jumps. The UI explicitly reports server result limits.
- Read/unread alert filters, bulk acknowledgement, related tracker details, light/dark/system appearance, Dynamic Type support and reduced map motion.

## Backend and scope

Uses the supplied Python server's `/api/mobile/v1/*` and `/api/v2/trackers/<provider>/<id>/preferences` endpoints. No Python changes are required. Android sources and the Android workflow are unchanged.

APNs still requires valid signing entitlements and an APNs-configured backend. An unsigned IPA must be signed by a sideloading tool before installation. Foreground polling does not provide continuous background location updates.

## Validation

The GitHub workflow runs unit tests for API decoding, IDs, filtering, freshness, sorting, history segmentation and CSV/GPX export. Simulator UI tests exercise map/list selection, tracker details, saved places and dark appearance with larger text; screenshot attachments are exported as a workflow artifact. It then creates and validates a Release IPA with code signing disabled. The sample data exists only in Debug builds behind the `--ui-testing` launch argument; the Release IPA contains no demo dataset.

Design references: [Apple's Liquid Glass adoption guide](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [SwiftUI design session](https://developer.apple.com/videos/play/wwdc2025/323/).
