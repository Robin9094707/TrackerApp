# Apple-Backend-Fix 20.4.1 — 25. Oktober 2026

Für diesen Fehler reicht das Backend-Update. Die vorhandene iOS-App 5.4.0 kann unverändert weiterverwendet werden.

Apple hat die Geräteprüfung geändert. FindMy 0.10.2 mit der bisherigen Android-ADI-Identität kann vor der Zwei-Faktor-Abfrage mit „Email verification failed: This action cannot be completed at this time“ scheitern oder keinen `searchPartyToken` für die Ortung erhalten. Siehe [FindMy.py #278](https://github.com/malmeloo/FindMy.py/issues/278) und [Kompatibilitätspatch #279](https://github.com/malmeloo/FindMy.py/pull/279). Der Patch ist upstream noch nicht als stabile Version veröffentlicht.

## Installation auf deinem bestehenden Server

1. Backend im AMP-Panel stoppen und den vorhandenen Backend-Ordner inklusive `data/` sichern.
2. Den Inhalt dieses Pakets in denselben Ordner wie deine bisherige `tracker_backend.py` kopieren. Die Unterordner `apple_coreadi/` und die Datei `apple_adi.py` gehören dazu. Den bisherigen `data/`-Ordner behalten. Umgebungsvariablen, Port, Passwort, Reverse Proxy und Start-Arbeitsverzeichnis weiterverwenden.
3. Falls nötig unter Debian `apt install git 7zip python3-venv` ausführen. Auf älteren Distributionen heißt 7-Zip `p7zip-full`.
4. Im Backend-Ordner mit **dem Python deiner bisherigen Server-Umgebung** installieren:

   ```bash
   TRACKER_PYTHON=/pfad/zur/bisherigen/venv/bin/python bash install-apple-backend.sh
   ```

   Wenn deine bisherige venv bereits aktiviert ist:

   ```bash
   bash install-apple-backend.sh
   ```

   Der Installer lädt einmal etwa 278 MiB direkt von Apple, prüft die vollständige DMG-Prüfsumme und die extrahierte CoreADI-Prüfsumme. Er speichert nur die passende Bibliothek in `runtime/`. Temporäre Installationsdateien werden entfernt. Danach installiert er die festgelegten FindMy.py-/Anisette-Commits. Internetzugriff zu Apple, GitHub und PyPI ist erforderlich. Als derselbe Benutzer wie der Backend-Dienst ausführen; `runtime/` muss lesbar sein.
5. Backend mit derselben Python-Umgebung und dem bisherigen Startbefehl neu starten. Falls dein Startskript die Python-Datei anders benennt, den aktualisierten Inhalt unter diesem Namen verwenden; die Hilfsdateien müssen daneben liegen.
6. In der vorhandenen App **Apple erneut anmelden** und Zwei-Faktor-Bestätigung abschließen. Normales Apple-Account-Passwort verwenden. Alte Android-ADI-Sitzungen benötigen eine neue Anmeldung; es werden keine Tracker neu angelegt und keine Schlüssel oder Verläufe gelöscht. Google und Samsung benötigen keine neue Anmeldung.

Optional kann `MACOS_ADI_BINARY` einen anderen absoluten Pfad für die Bibliothek vorgeben. Installer und Dienst müssen denselben Wert verwenden. Für eine schon heruntergeladene offizielle DMG: `python3 setup_apple_adi.py --dmg /pfad/iTunes12.8.3.dmg`.

Der FindMy-Einzelupdater in der App ist für diesen Kompatibilitätsbuild gesperrt, damit er den Fix nicht durch die gleich nummerierte PyPI-Version ersetzt. Künftige Updates erfolgen als zusammen geprüfter Backend-Paketsatz.

## Was geprüft ist

- Bestehende Backend-Tests für Daten, Google-/Samsung-Verläufe, Kalender, MCP und Berechtigungen.
- Apple-Anmeldung mit simulierten Antworten: 2FA, fehlender Ortungstoken, Schonung bestehender Sitzung, Wiederholsperre, konkurrierende Ortung, verständliche Fehler und alte Sitzungsdateien.
- Offizielle Apple-DMG heruntergeladen und beide Prüfsummen kontrolliert; die extrahierte Bibliothek startet im passenden Emulator, und unprovisionierter Zustand lässt sich speichern und wiederherstellen.
- Ein echter Login, 2FA und die Ortung mit deinem Apple-Account sind ohne deinen Serverzugang/Bestätigungscode hier nicht abschließend geprüft. Eine grüne GitHub Action bestätigt die automatisierten Prüfungen, keine Live-Ortung. Der Versuch einer accountlosen Apple-Provisionierung war aus der Arbeitsumgebung durch eine HTTP-503-Antwort auf Apples Lookup-Endpunkt blockiert.

## Technische Quellen

- FindMy.py: `sacca97/FindMy.py@f2d24c86c3357f93cc19dd605fa9dc34d6d1b1c6` (PR #279).
- Anisette: `sacca97/Anisette.py@627c9c663062bd872182b653113759c9d66b7e13` (PR #6).
- iTunes-4.19-Emulator: vier MIT-Dateien aus `sacca97/os-findmy-e@374d83854f657a7fdca45f813387d99d491db0e2`, siehe `apple_coreadi/SOURCE.md`.
- Die Anisette-Quelle deklariert zusätzlich einen macOS-26-Emulator von `@main` als transitive Abhängigkeit. Dieser wird für unsere iTunes-4.19-Integration nicht verwendet.
- TLS-Prüfung bleibt aktiviert. Apple-Bibliotheken und Zugangsdaten sind nicht im Paket enthalten.
