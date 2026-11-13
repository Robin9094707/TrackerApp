"""22.0 overhaul: network priority, bags for fusions, gzip and the web app."""
import gzip
import json
import sys
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_backend_calendar_mcp import M, STATE, APP


def loc(lat, ts, acc=12):
    return {"lat": lat, "lon": 6.76, "acc": acc, "ts": ts}


class NetworkPriorityTests(unittest.TestCase):
    def setUp(self):
        now = time.time()
        self.now = now
        self.sources = {"apple": loc(51.0, now - 1800), "google": loc(52.0, now - 120), "samsung": loc(53.0, now - 600)}

    def policy(self, **raw):
        base = {"mode": "newest", "order": ["apple", "google", "samsung"], "primary": "apple",
                "backups": ["google", "samsung"], "backup_after_minutes": 10, "backup_polling": "always"}
        base.update(raw)
        base["primary"] = base["order"][0]
        base["backups"] = base["order"][1:]
        return base

    def test_newest_keeps_previous_behaviour(self):
        chosen, selection = M["fusion_policy_pick"](self.sources, self.policy())
        self.assertEqual((chosen["lat"], selection["source"]), (52.0, "google"))

    def test_priority_prefers_primary_until_backup_is_clearly_newer(self):
        chosen, selection = M["fusion_policy_pick"](self.sources, self.policy(mode="priority", backup_after_minutes=40))
        self.assertEqual((selection["source"], selection["reason"]), ("apple", "primary"))
        chosen, selection = M["fusion_policy_pick"](self.sources, self.policy(mode="priority", backup_after_minutes=10))
        self.assertEqual((selection["source"], selection["reason"]), ("google", "backup_newer"))

    def test_priority_order_and_primary_only(self):
        chosen, selection = M["fusion_policy_pick"](self.sources, self.policy(mode="primary_only", order=["samsung", "apple", "google"]))
        self.assertEqual(selection["source"], "samsung")
        sources = {"google": loc(52.0, self.now - 60)}
        chosen, selection = M["fusion_policy_pick"](sources, self.policy(mode="primary_only"))
        self.assertEqual((selection["source"], selection["reason"]), ("google", "primary_missing"))
        self.assertEqual(M["fusion_policy_pick"]({}, self.policy())[0], None)


class OverhaulApiTests(unittest.TestCase):
    def setUp(self):
        self.client = APP.test_client()
        pair = self.client.post("/api/mobile/v1/pair", json={"pw": "Regression-Test-Password"})
        self.assertEqual(pair.status_code, 200)
        self.headers = {"X-CSRF-Token": pair.json["csrf_token"]}
        now = time.time()
        STATE["accessories"]["Bag"] = object()
        STATE["google_devices"]["gbag"] = {"name": "Bag Google"}
        STATE["google_locations"]["gbag"] = {"lat": 52.0, "lon": 6.76, "acc": 10, "ts": now - 60}
        STATE["fusion_profiles"]["Bag"] = {"google_id": "gbag", "created_ts": int(now)}
        self.original_links = STATE.get("google_links")

    def tearDown(self):
        STATE["accessories"].pop("Bag", None)
        STATE["google_devices"].pop("gbag", None)
        STATE["google_locations"].pop("gbag", None)
        STATE["fusion_profiles"].pop("Bag", None)
        store = M["school_store"]()
        store["bags"].pop("fusion:Bag", None)

    def test_policy_round_trip_is_validated_and_persisted(self):
        response = self.client.get("/api/mobile/v1/fusion-networks?ref=fusion:Bag")
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json["policy"]["mode"], "newest")
        self.assertEqual(response.json["policy"]["order"], ["apple", "google"])
        bad = self.client.put("/api/mobile/v1/fusion-networks?ref=fusion:Bag", headers=self.headers, json={"order": ["nokia"]})
        self.assertEqual(bad.status_code, 400)
        no_csrf = self.client.put("/api/mobile/v1/fusion-networks?ref=fusion:Bag", json={"mode": "priority"})
        self.assertEqual(no_csrf.status_code, 403)
        ok = self.client.put("/api/mobile/v1/fusion-networks?ref=fusion:Bag", headers=self.headers,
                             json={"mode": "priority", "order": ["google", "apple"], "backup_after_minutes": 5, "backup_polling": "when_stale"})
        self.assertEqual(ok.status_code, 200, ok.json)
        self.assertEqual(ok.json["policy"]["primary"], "google")
        self.assertEqual(STATE["fusion_profiles"]["Bag"]["network_policy"]["backup_polling"], "when_stale")
        self.assertEqual(STATE["fusion_profiles"]["Bag"]["google_id"], "gbag", "existing fields are preserved")
        self.assertTrue(M["fusion_primary_fresh"]("Bag"))
        self.assertTrue(M["fusion_backup_paused"]("apple", "Bag"))
        self.assertFalse(M["fusion_backup_paused"]("google", "gbag"))

    def test_any_tracker_including_fusion_can_be_a_bag(self):
        listing = self.client.get("/api/mobile/v1/bags")
        self.assertEqual(listing.status_code, 200, listing.json)
        self.assertIn("fusion:Bag", [row["ref"] for row in listing.json["bags"]])
        enabled = self.client.post("/api/mobile/v1/bags", headers=self.headers, json={"ref": "fusion:Bag", "enabled": True, "label": "Schulranzen"})
        self.assertEqual(enabled.status_code, 200, enabled.json)
        row = next(row for row in enabled.json["bags"] if row["ref"] == "fusion:Bag")
        self.assertTrue(row["is_bag"])
        self.assertEqual(row["label"], "Schulranzen")
        disabled = self.client.post("/api/mobile/v1/bags", headers=self.headers, json={"ref": "fusion:Bag", "enabled": False})
        self.assertFalse(next(r for r in disabled.json["bags"] if r["ref"] == "fusion:Bag")["is_bag"])
        self.assertEqual(M["school_store"]()["bags"]["fusion:Bag"]["label"], "Schulranzen", "disabling keeps the plan")

    def test_web_app_is_public_shell_and_api_stays_protected(self):
        anonymous = APP.test_client()
        page = anonymous.get("/app")
        self.assertEqual(page.status_code, 200)
        self.assertIn(b"RJ Tracker Web", page.data)
        self.assertIn("frame-ancestors 'none'", page.headers["Content-Security-Policy"])
        self.assertEqual(anonymous.get("/app/manifest.webmanifest").json["start_url"], "/app")
        self.assertEqual(anonymous.get("/api/mobile/v1/bootstrap").status_code, 401)
        self.assertEqual(anonymous.get("/api/mobile/v1/bags").status_code, 401)

    def test_web_app_map_tiles_are_allowed_and_page_is_cached(self):
        client = APP.test_client()
        page = client.get("/app", headers={"Accept-Encoding": "gzip"})
        self.assertEqual(page.headers.get("Content-Encoding"), "gzip")
        body = gzip.decompress(page.data).decode("utf-8")
        self.assertIn("tiles.openfreemap.org", body)
        self.assertNotIn("tile.openstreetmap.org", body)
        self.assertNotIn("resolve_addresses=1", body, "history must not block on geocoding every point")
        csp = page.headers["Content-Security-Policy"]
        for host in ("https://tiles.openfreemap.org", "https://server.arcgisonline.com", "blob:"):
            self.assertIn(host, csp)
        # Tile servers reject requests without a Referer; only the origin is sent.
        self.assertEqual(page.headers["Referrer-Policy"], "strict-origin-when-cross-origin")
        again = client.get("/app/", headers={"If-None-Match": page.headers["ETag"]})
        self.assertEqual(again.status_code, 304)
        self.assertEqual(client.get("/app").data.decode("utf-8"), body)

    def test_large_json_is_gzip_compressed_when_accepted(self):
        plain = self.client.get("/api/mobile/v1/bootstrap")
        packed = self.client.get("/api/mobile/v1/bootstrap", headers={"Accept-Encoding": "gzip"})
        self.assertNotIn("Content-Encoding", plain.headers)
        self.assertEqual(packed.headers.get("Content-Encoding"), "gzip")
        self.assertEqual(json.loads(gzip.decompress(packed.data))["status"], "ok")

    def test_tracker_rows_expose_bag_flag_and_policy(self):
        rows = self.client.get("/api/mobile/v1/trackers").json["trackers"]
        self.assertTrue(all("school_bag" in row for row in rows))
        detail = self.client.get("/api/mobile/v1/tracker?ref=fusion:Bag")
        self.assertEqual(detail.status_code, 200, detail.json)
        self.assertEqual(detail.json["tracker"]["network_policy"]["mode"], "newest")


if __name__ == "__main__":
    unittest.main()
