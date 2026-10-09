# Update to RJ Tracker 4.3 / backend 20.2

## Safe installation

1. Stop the running Python backend. Keep a copy of the existing script and the complete `data/` directory (or your configured `ULTRA_TRACKER_DATA_DIR`). GitHub’s backup branch protects source code; it does not contain your private server data.
2. Replace the script in its existing directory. Keep the existing data directory, environment variables and credentials. The attached standalone Python script is identical to `Backend/tracker_backend.py`.
3. Start the backend with the same command. Dependencies are unchanged from 20.1. No new store or destructive schema migration is needed.
4. Install the new unsigned IPA using your existing signing method and signing identity. Retain bundle identifier `eu.rjuhas.rjtracker`; do not uninstall the existing app first.

## Calendar history

`GET /api/mobile/v1/history/days?ref=google:ID` returns all stored calendar dates, point counts, contributing networks and the server timezone.

`GET /api/mobile/v1/history?ref=google:ID&dates=2026-10-07,2026-10-09` selects only those complete local days. The stream endpoint accepts the same `dates` selection and pages every original report. Old `days`, `period`, `from` and `to` requests remain compatible.

A stored date stays selectable while its points are retained under that tracker’s existing retention policy. This update does not reconstruct previously deleted history or change retention.

## MCP management

Open **Ich → Server verwalten → ChatGPT / MCP**. Enter the public HTTPS root URL, choose the permissions, enable MCP and save. Copy/share the displayed tenant-aware `/mcp` link into ChatGPT’s custom MCP connection setup. OAuth opens the server HTML sign-in page with the master/account password and optional 2FA. No password is stored in the iOS app.

“Configuration check” verifies local readiness, HTTPS settings and OAuth routes. ChatGPT verifies the external domain’s actual reachability when connecting.

Individual connection removal revokes its complete access/refresh token family. Other connections remain valid. Changing the public base URL, disabling/enabling MCP or revoking all connections requires OAuth authentication again. The app cannot automatically install a connection inside ChatGPT; the link and setup instructions make that step explicit.

The `/admin` page adds the same MCP controls to the existing authenticated main-admin console. API-key authentication cannot manage MCP, passwords or users.

## Notifications

Clearing the inbox removes notification events only. Rules, push registrations, provider data, shares and location history remain in place. New events still arrive normally.

## Rollback

Source snapshot: branch `backup/before-calendar-mcp-2026-10-09`, commit `c9b2abff943872874fae54836876f835ff3a585e`.

The stored data format remains readable by 20.1. Reinstalling the previous app and backend preserves those stores; events deliberately cleared or grants deliberately revoked are not restored by a source rollback.
