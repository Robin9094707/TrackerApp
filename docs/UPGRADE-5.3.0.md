# RJ Tracker 5.3.0 / Build 21

Über die bestehende Installation mit gleicher Signierungsidentität installieren. Bundle-ID eu.rjuhas.rjtracker und Mindestversion iOS 18.1 bleiben erhalten. App vorher nicht löschen. Server, lokale Google-Zugänge und bisherige Verläufe benötigen keine Migration.

Eigener lokaler Google-Tracker mit bekannter Motorola-Modellkennung → **Moto-Tag-Firmware aktualisieren**. Original-APKM/APK 01.01.101.23 oder unveränderte OTA.bin über den Dateidialog importieren, Tag prüfen, anschließend Installation bestätigen. Der Import wird auf 2.0.104 für XT2445-1 begrenzt. Mit mindestens 30 % Tag-Batterie, entsperrten Eigentümerschlüsseln und älterer Firmware kann der experimentelle native Bluetooth-Updater starten. Erneutes Auslesen nach dem Neustart bestätigt das Resultat. Nach Abbruch oder Fehler vor einem neuen Versuch erneut prüfen.

XT2561-1 wird erkannt, erhält aber keine Installation mit dem falschen Verfahren. Automatisches Herunterladen der jeweils neuesten Motorola-Serverfirmware und UWB-Pfeilortung sind nicht integriert. Der Funk-/Flashpfad ist ohne echte Moto-Tag-Hardware unbestätigt. Details und reproduzierbare Analysebefunde: [Motorola-Untersuchung](MOTOROLA-FIRMWARE-INVESTIGATION.md).

Pflichtprüfungen vor IPA-Erzeugung: bestehende Backend-, Google-, Debug- und Release-Startprüfungen sowie neue Eigentümerauthentifizierungs-, Paketimport-, Vendor-Protokoll- und Firmware-Vorprüfungen. Hardwaretests bleiben erforderlich.
