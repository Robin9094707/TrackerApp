# Motorola Moto Tag: Originalfirmware auf iOS

Untersucht am 24.10.2026, Ausgangscommit b816faed9cd98b804827c0f507cc100f6ff239d7. Backup: `backup/before-motorola-ota-2026-10-24`.

## Tatsächlich untersuchte Dateien

Die bereitgestellte APKM enthält `com.motorola.tag`, Version 01.01.101.23-Release (10110123). `base.apk` SHA-256: `b10d559db6be295372a220c1f9f990cd21bc201fd3653c4ae683052958e56861`.

Die als `uptodown-com.google.android.apps.adm.apk` bezeichnete Datei enthält laut binärem AndroidManifest tatsächlich `com.uptodown` 7.41 / 741, SHA-256 `dc885921fc2d141a53906675bd555f6f5d3705119f37f892d3edf3e61b342550`. Sie wurde deshalb nicht als Find Hub behandelt. Die öffentlich auffindbare Find-Hub-Version 3.1.763-05 wurde recherchiert; der direkte APKMirror-Binärdownload scheiterte mit HTTP 403. Es wird keine Analyse dieser nicht heruntergeladenen Google-Version behauptet.

Die Motorola-APK wurde mit Androguard und JADX statisch untersucht. JADX meldete bei 49 Methoden Dekompilierungsfehler. Die für diesen Pfad verwendeten Modelltabellen, Firmware-Assets, Vendor-PDUs und Nordic-Updatekonfiguration sind separat lesbar; eine vollständige fehlerfreie Rekonstruktion der gesamten App wird nicht behauptet. Kein Motorola-Programmcode und keine proprietären Firmwaredateien werden im öffentlichen Repository weiterverteilt.

## Befunde aus Motorola

`assets/firmware_asset_paths.json` ordnet zu:

| Modell | Google Fast Pair IDs | Originalasset | Firmware | Verfahren |
| --- | --- | --- | --- | --- |
| XT2445-1 | b4122f, 3390ea | assets/nano_v2.0.104/OTA.bin | 2.0.104 | Nordic SMP / MCUboot |
| XT2561-1 | 8c9712, 97b899 | assets/nanop_v1.30.22/OTA.atm | 1.30.22 | Atmosic BLE/UWB, nicht portiert |

`b5.e` / `d5.f` wählen das Updateverfahren anhand dieser Modellkennungen. `b5.C0771b` konfiguriert Nordic mit CONFIRM_ONLY und 10 Sekunden geschätztem Swap. Der iOS-Pfad verwendet dieselbe Aktivierungsart ohne Löschen von App-Einstellungen, konservativ mit Pipeline-Tiefe 1. SMP-Service: 8D53DC1D-1DB7-4CD3-868B-8A527460AA84, Characteristic DA2E7828-FBCE-4E01-AE9E-261174997C48.

Original-OTA.bin: 508762 Bytes, SHA-256 `e1fd8c3eb5be56010bfa6fbddcca3cf3df8418f336e1ce3a7d759271b72baa1e`. Original-OTA.atm: 668622 Bytes, SHA-256 `35089d871400120bb9d84f3da740d7dbc8088fe525d62c7a6dfffdc4940ac408`.

Vendor-Service 018EFC7C-6B58-79D2-BC8F-0BE0388883BB: Schreiben auf FC7C08A0…, Antworten per Notify auf FC7C08A1…. PDU = Feature, Subfeature, Flags, Payloadlänge (16 Bit Big Endian), Payload. Verwendet werden ausschließlich lesende Feature-0-Anfragen 4 (Modell/Farbe), 5 (Hardware/Firmware), 6 (Batterie). Antworten benötigen Response-Flag 0x20, Ergebnis 0 und exakte Länge. Hardwareinfo: 19 Bytes Seriennummer (wird nicht gespeichert/angezeigt), drei Firmwarebytes, zwei Hardwarebytes. Der Firmwareheader selbst meldet 0.0.0; deshalb darf er nicht als Produktversionsvergleich dienen.

## Implementierter iOS-Pfad und Grenzen

- Import von APK, APKM oder Original-OTA.bin direkt über den iOS-Dateidialog. Begrenzte Extraktion ausschließlich fester Archivpfade, CRC und exakt freigegebener SHA-256. Kein APK-Installieren auf iOS, keine Ausführung von Android-Code.
- Aktuell nur Originalfirmware 2.0.104 für XT2445-1 zugelassen. Kein ungeprüftes Aktualisieren fremder Modelle, keine frei gewählten BINs und keine Downgrades. Neuere Originale benötigen eine geprüfte neue Freigabe.
- Google Read Provisioning State (0x01) mit frischem Nonce, HMAC-verifizierter Antwort und gesetzten Bits „provisioniert“ UND „Eigentümerschlüssel“. Ein nur geteilter Tag genügt nicht.
- Zielperipherie ist die bereits durch Google-EID erkannte UUID des eigenen Trackers. Anschließend zusätzliche Bestätigung der identischen Fast-Pair-Modellkennung aus dem Motorola-Vendordienst, Firmwareversion und mindestens 30 % Batterie.
- Die normale Google-Bluetooth-Verwaltung gibt die Zielperipherie exklusiv für den Firmwarepfad frei. Andere Tracker können weiter gesichtet werden.
- Vor Start erneute Eigentümer-, Modell-, Versions- und Batterieprüfung. Originalbytes und MCUboot-Metadaten werden vor Übergabe an die native Nordic-iOS-Bibliothek geprüft.
- Fortschritt bezeichnet den Upload. Nach Aktivierung erfolgt ein erneutes Auslesen der Produktfirmware. Erst bestätigte Version 2.0.104 ergibt Erfolg. Ein fehlendes Nachlesen wird ausdrücklich als nicht bestätigtes Update angezeigt; erneutes Prüfen kann erforderlich sein.
- Originalimport bleibt lokal über Appstarts erhalten. Keine Änderung der App-ID, Konto-/Serverzugänge oder bestehenden Archive.
- Keine automatische Motorola-Serverabfrage für die jeweils neueste Firmware: Motorolas OTA-Client enthält einen weiteren gerätebezogenen CDS-Ablauf. Dieser wird nicht als fertiger öffentlicher Downloadservice ausgegeben.
- Ohne echten Tag und iPhone ist der Funk-/Flashpfad **experimentell und hardwareseitig unbestätigt**. Tests und erfolgreicher IPA-Build bestätigen keine erfolgreiche reale Installation und keine generelle Android-Unabhängigkeit.

## UWB

Keine kompatible Verbindung zwischen Googles Ranging-Sitzungsparametern und Apples Nearby Interaction für diesen Moto Tag nachgewiesen. Die Motorola-Begleit-App enthält den Firmwarepfad, liefert aber keinen nachgewiesenen Apple-kompatiblen Sitzungsaufbau. Firmwareaktualisierung allein löst diese Hürde nicht. Die bisherige authentifizierte Google-Fähigkeitsprüfung bleibt erhalten; keine vorgetäuschten Entfernungen/Richtungspfeile. Siehe [UWB-Untersuchung](UWB-INVESTIGATION.md).

## Primärquellen / Abhängigkeiten

- [Motorola Firmwareupdate](https://en-us.support.motorola.com/app/answers/detail/a_id/182011/~/update-the-moto-tag)
- [Motorola UWB-Anforderungen](https://de-de.support.motorola.com/app/answers/detail/a_id/172074/~/ultrabreitband-informationen-%257C-moto-tag)
- [Google FHNA: Read Provisioning State und HMAC](https://developers.google.com/nearby/fast-pair/specifications/extensions/fmdn)
- [Apple Nearby Interaction](https://developer.apple.com/nearby-interaction/)
- [Nordic native iOS-SMP-Bibliothek](https://github.com/nordicsemi/IOS-nRF-Connect-Device-Manager), fest auf a0443b52b9db4f6524c6dd659bff7deb45a1b963 fixiert, Apache-2.0, Lizenz in Abhängigkeit.
- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation), 0.9.20, MIT, Lizenz in Abhängigkeit.
