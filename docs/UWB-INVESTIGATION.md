# UWB-Untersuchung: Moto Tag 1 und iPhone

Stand: 24.10.2026. Ergebnis: **Keine funktionierende UWB-Pfeilortung für den Moto Tag der ersten Generation nachgewiesen. Version 5.2.0 enthält eine experimentelle Fähigkeitsabfrage, keine fertige UWB-Ortung.**

## Geprüfte Ausgangsbasis

- TrackerApp-Ausgangsstand `51c28b6630d0ba58c226618fda2775b2278d75dd`.
- Zusätzlich geprüft: `Robin9094707/Spot`, Stand `6e00a95f4e3a38bf8586728888ea95f3d3cfeb44`, README, Bluetooth-Owner-Operationen und RSSI-Implementierung sowie Dateibaum. Die Nahsuche dort basiert auf Bluetooth/RSSI; keine UWB-/Nearby-Interaction-Implementierung im Quellstand gefunden. Das Referenz-Repo wurde nicht verändert.
- Offizielle Google-Find-Hub-/Android-OOB-Spezifikation und Apples öffentliche Nearby-Interaction-Dokumentation.

## Technische Einordnung

Der Moto Tag besitzt UWB. Motorola nennt für präzise Ortung u. a. Firmware ab 2.0.93 und ein geeignetes gekoppeltes Smartphone. Das bestätigt keine Interoperabilität mit einer eigenen iPhone-App.

Google definiert für Precision Finding authentifizierte Fast-Pair-Beacon-Aktionen: 0x0A liest Fähigkeiten, 0x0B konfiguriert Ranging, 0x0D beendet es. Die Out-of-Band-Daten enthalten u. a. Adresse, Konfigurationsprofil, Kanal, Timing und Sitzungsschlüssel. Google nennt insbesondere Profil 6/P-STS und Kanal 9.

Apples öffentliche iOS-Schnittstelle `NINearbyAccessoryConfiguration` erwartet Zubehör-Konfigurationsdaten nach Apples Nearby Interaction Accessory Protocol. Zusätzlich muss der Rückkanal die von `NISession` erzeugten shareable configuration data an kompatible Zubehör-Firmware übermitteln. Ein Google-Accountschlüssel, die Google-UWB-Adresse oder ein aktiver UWB-Chip sind kein Ersatz für diesen Ablauf. Die öffentliche Schnittstelle bietet keinen allgemeinen Setter für beliebige Google-/FiRa-Sitzungsschlüssel und Ranging-Profile.

Daraus folgt für diesen Build: Die Google-Fähigkeitsantwort lässt sich abfragen und validieren. Ein funktionierender Übersetzer zwischen dem Google-Sitzungsaufbau und Apples Zubehörprotokoll ist für diesen Moto Tag nicht belegt. Auch neue FiRa-/DL-TDoA-Funktionen bedeuten nicht automatisch, dass dieses konkrete bidirektionale Tracker-Profil unterstützt wird. Eine behauptete Richtung aus GPS-Koordinaten oder RSSI wäre keine UWB-Pfeilortung und wird nicht angezeigt.

Diese Einordnung ist eine technische Schlussfolgerung aus den Schnittstellen und dem verfügbaren Quellcode, kein Beweis einer grundsätzlichen Unmöglichkeit für jede zukünftige Firmware oder iOS-Version. Ein nachgewiesenes kompatibles Zubehörprotokoll, geeignete Hersteller-Firmware oder ein verifizierter Protokolladapter könnte die Bewertung ändern.

## Experiment in Version 5.2.0

Unter einem lokal verfügbaren Google-Tracker → **UWB prüfen · experimentell**:

1. iOS meldet, ob dieses Gerät präzise Entfernungs-/Richtungsmessung grundsätzlich unterstützt.
2. Den eigenen Tracker in Bluetooth-Reichweite bringen und Google-Schlüssel entsperren.
3. Die App liest den aktuellen Authentifizierungs-Nonce und sendet ausschließlich Operation 0x0A mit einer OOB-v1-Anfrage nach UWB-Fähigkeiten. Neuere Gegenstellen sollen auf v1 herunterhandeln; ältere/proprietäre Implementierungen können die Anfrage ablehnen oder ignorieren.
4. Die Antwort wird mit dem eigenen Accountschlüssel und Nonce authentifiziert. Längen, Version, TLV-Grenzen und widersprüchliche Antworten werden geprüft. Bestätigte Kanäle, Profile und Timing werden angezeigt.
5. **Es werden keine UWB-Sitzung konfiguriert, keine Messung vorgetäuscht und keine Pairing-/Reset-Befehle gesendet.** Der Test verändert weder Eigentümerschlüssel noch Kontobindung oder Firmware. Eine ausbleibende Antwort wird als unbekannt behandelt, nicht als Beweis fehlender UWB-Hardware.
6. Das teilbare Prüfergebnis enthält Fähigkeitswerte und Fehlertext, keine Accountschlüssel, Tokens, Nonces oder UWB-Adressen.

Ohne echten Moto Tag und iPhone können weder die Firmware-Antwort noch eine Funkverbindung bestätigt werden. Simulator- und Pakettests prüfen lediglich Code-/Parser-Verhalten. Auf der Hardware bleibt insbesondere die tatsächliche Unterstützung dieser Capability-Operation zu prüfen.

## Quellen

- [Apple Nearby Interaction und Zubehör-/Chipset-Anforderungen](https://developer.apple.com/nearby-interaction/)
- [Apple Nearby Interaction Framework](https://developer.apple.com/documentation/nearbyinteraction)
- [Apple NINearbyAccessoryConfiguration](https://developer.apple.com/documentation/nearbyinteraction/ninearbyaccessoryconfiguration)
- [Apple Accessory Protocol Specification R4](https://developer.apple.com/download/files/Nearby-Interaction-Accessory-Protocol-Specification-R4.pdf)
- [Google Find Hub Network Accessory Specification – Precision Finding](https://developers.google.com/nearby/fast-pair/specifications/extensions/fmdn)
- [Android Ranging OOB v1](https://source.android.com/docs/core/connect/ranging-oob-spec)
- [Android Ranging OOB v2 – Byte-Reihenfolge und Kompatibilität](https://source.android.com/docs/core/connect/ranging-oob-spec-v2)
- [Motorola Moto Tag: UWB und Firmwareanforderungen](https://en-us.support.motorola.com/app/answers/detail/a_id/180783/~/ultra-wideband-information-%7C-moto-tag)
