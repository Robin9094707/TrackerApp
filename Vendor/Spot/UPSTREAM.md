# Spot integration

Source: https://github.com/leonboe1/Spot
Commit: 55f87f62302fae24150188124e8e07d5285568d8
Copyright © 2024–2026 Leon Böttger. GPL-3.0-only.

Vendored as the SpotIntegration framework in RJ Tracker 5.0. Original application entry point and restricted icon artwork are excluded. RJ Tracker retains its own icon.

Integration changes: public host/snapshot bridge; separate Keychain/preferences and account-specific history stores; non-destructive Core Data migration; authenticated async login completion; request validation; local secrets import; lifecycle forwarding. All original tracker management, Bluetooth, crypto, location, sharing and ESP32 creation sources are included.

The complete combined application source is distributed under GPL-3.0-only. Third-party notices remain in Licenses and Configuration.swift. Backend dependencies retain their respective licenses.
