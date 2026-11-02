"""Create an isolated backend data directory for the Android emulator test.

One Google tracker is marked as school bag with home/school places, today's
timetable and a realistic route (home -> walk -> school) so the app shows the
school mode with real backend responses. No real accounts or providers.
"""
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

TOKEN = "e2e-school-link-0123456789abcdef"
data = Path(sys.argv[1]).resolve()
(data / "google").mkdir(parents=True, exist_ok=True)
zone = ZoneInfo("Europe/Berlin")
now = time.time()
home = (51.4302, 6.7601)
school = (51.4361, 6.7712)
start_ts = now - 4 * 3600  # left home four hours ago


def lerp(a, b, f):
    return a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f


points = []
for i in range(6):  # at home
    points.append({"lat": home[0] + 0.00003 * i, "lon": home[1], "acc": 18, "ts": start_ts - 3600 + i * 500})
for i in range(1, 12):  # on the way
    lat, lon = lerp(home, school, i / 12)
    points.append({"lat": lat, "lon": lon, "acc": 25, "ts": start_ts + i * 120})
for i in range(40):  # at school, incl. one inaccurate outlier
    jitter = 0.00004 * ((i % 5) - 2)
    points.append({"lat": school[0] + jitter, "lon": school[1] - jitter, "acc": 22, "ts": start_ts + 1500 + i * 300})
points.insert(30, {"lat": school[0] + 0.006, "lon": school[1], "acc": 90, "ts": start_ts + 1500 + 7 * 300 + 30})
for index, point in enumerate(points):
    point.update(source="google", report_id=f"e2e-{index}", received_at=point["ts"] + 20)

current = dict(points[-1])
(data / "google" / "devices.json").write_text(json.dumps({"bag1": {"name": "Schultasche Lea"}}))
(data / "google" / "locations.json").write_text(json.dumps({"bag1": current}))
(data / "google" / "history.json").write_text(json.dumps({"bag1": {"enabled": True, "points": points}}))
weekday = datetime.now(zone).isoweekday()
arrival = datetime.fromtimestamp(start_ts + 1500, zone)
school_start = f"{arrival.hour:02d}:{(arrival.minute // 5) * 5:02d}"
days = {str(day): {"enabled": True, "start": school_start, "end": ""} for day in range(1, 8)}
(data / "school_mode.json").write_text(json.dumps({
    "schema": 1,
    "bags": {"google:bag1": {"enabled": True, "child_name": "Lea", "label": "Schultasche", "created_ts": 0}},
    "links": {TOKEN: {"viewer_name": "Jessy", "label": "Leas Schultasche", "refs": ["*"], "can_edit": True, "active": True, "created_ts": int(now)}},
    "places": {
        "home": {"id": "home", "kind": "home", "name": "Zuhause", "lat": home[0], "lon": home[1], "radius_m": 80, "created_ts": 0, "updated_ts": 0},
        "school": {"id": "school", "kind": "school", "name": "Gesamtschule", "lat": school[0], "lon": school[1], "radius_m": 150, "created_ts": 0, "updated_ts": 0},
    },
    "schedule": {"days": days, "grace_minutes": 5, "absent_after_minutes": 90, "off_days": [], "updated_ts": 0},
}))
print(TOKEN)
