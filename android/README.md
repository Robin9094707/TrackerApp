# RJ Tracker Share — Android

Native Android companion app for **guest/share links** from RJ Tracker / Universal Tag Studio.

## Purpose

This app is intentionally separated from the owner/admin iOS client. It does not log in to Apple Find My, Google Find Hub, Samsung SmartThings Find, or the RJ Tracker owner account. A guest only adds an existing `https://…/shared/<id>` link and its guest password.

## v1.0.0 features

- Native Kotlin + Jetpack Compose UI using Material 3 and Android dynamic colors.
- Directly installable debug APK from GitHub Actions.
- Stores multiple share links until the user removes them; expired/revoked links are shown as unavailable.
- Accepts links pasted manually or shared into the app with the Android Sharesheet.
- Supports single-provider shares and Apple/Google/Samsung Fusion shares.
- Fusion view shows all provider locations by default; Apple, Google, or Samsung can be hidden locally without changing server permissions.
- Main location automatically follows the newest visible provider report.
- Native MapLibre map with OpenFreeMap/OpenStreetMap data.
- Provider markers and a geographic accuracy circle.
- Exact guest-visible address through `/api/shared/<id>/address` when the share permission allows it.
- Manual live locate through `/api/shared/<id>/locate` with the server's 30-second cooldown.
- Source/provider, timestamp, accuracy, expiry, and per-provider last-report overview.
- Optional handoff to the installed Android maps/navigation app.
- Guest passwords are encrypted at rest with an AES-GCM key stored in Android Keystore.

## Share API used

The app only calls the public guest endpoints already exposed by the backend:

- `POST /api/shared/<id>` — authenticate and read the share payload.
- `POST /api/shared/<id>/locate` — request a guest-authorized refresh.
- `POST /api/shared/<id>/address` — resolve the currently shared provider location to a guest-visible address.

Every request includes the guest password. No owner session, CSRF token, provider secret, or provider account is required.

## Build

GitHub Actions workflow: **Build RJ Tracker Android APK**.

Local build with a compatible Android SDK/JDK/Gradle installation:

```bash
cd android
gradle :app:assembleDebug
```

APK output:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

The GitHub workflow renames the artifact to `RJ-Tracker-Share-v1.0.0-debug.apk`.
