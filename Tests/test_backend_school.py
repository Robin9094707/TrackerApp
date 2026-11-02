"""School bag mode, native guest app API and admin sharing; offline, temporary data."""
import copy
from pathlib import Path
import sys
import time
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_backend_calendar_mcp import APP, M, STATE

SCHOOL = {'id': 'school', 'kind': 'school', 'name': 'Schule', 'lat': 51.4300, 'lon': 6.7600, 'radius_m': 120, 'created_ts': 0}
HOME = {'id': 'home', 'kind': 'home', 'name': 'Zuhause', 'lat': 51.4400, 'lon': 6.7800, 'radius_m': 80, 'created_ts': 0}
# ~111 m per 0.001 degree latitude
def at(place, ts, north_m=0.0, acc=20.0):
    return {'lat': place['lat'] + north_m / 111_000, 'lon': place['lon'], 'acc': acc, 'ts': ts, 'source': 'apple'}


class PresenceEngineTests(unittest.TestCase):
    intervals = staticmethod(M['school_place_intervals'])

    def test_two_inside_reports_enter_and_two_outside_reports_leave(self):
        t = 1_800_000_000
        points = [at(SCHOOL, t, 900), at(SCHOOL, t + 300, 10), at(SCHOOL, t + 420, -20),
                  at(SCHOOL, t + 3600, 15), at(SCHOOL, t + 7200, 900), at(SCHOOL, t + 7500, 1200)]
        rows, now = self.intervals(points, SCHOOL, t + 8000)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['enter_ts'], t + 300)
        self.assertFalse(rows[0]['entered_unknown'])
        self.assertEqual(rows[0]['leave_ts'], t + 7200)
        self.assertEqual(rows[0]['last_in_ts'], t + 3600)
        self.assertFalse(now['inside'])

    def test_single_outlier_does_not_count_as_leaving(self):
        t = 1_800_000_000
        points = [at(SCHOOL, t, 900), at(SCHOOL, t + 60, 0), at(SCHOOL, t + 120, 5),
                  at(SCHOOL, t + 600, 600, acc=80),  # one inaccurate stray report
                  at(SCHOOL, t + 900, 10), at(SCHOOL, t + 1500, -5)]
        rows, now = self.intervals(points, SCHOOL, t + 1600)
        self.assertEqual(len(rows), 1)
        self.assertIsNone(rows[0]['leave_ts'])
        self.assertTrue(now['inside'])

    def test_two_quick_outside_reports_wait_for_confirmation(self):
        t = 1_800_000_000
        points = [at(SCHOOL, t, 900), at(SCHOOL, t + 60, 0), at(SCHOOL, t + 120, 5),
                  at(SCHOOL, t + 600, 500, acc=40), at(SCHOOL, t + 660, 520, acc=40)]
        rows, now = self.intervals(points, SCHOOL, t + 700)
        self.assertIsNone(rows[0]['leave_ts'])
        self.assertEqual(now['pending'], 'leaving')
        rows, _ = self.intervals(points + [at(SCHOOL, t + 720, 530, acc=40)], SCHOOL, t + 800)
        self.assertEqual(rows[0]['leave_ts'], t + 600)

    def test_precise_single_report_is_confirmed_after_eight_minutes(self):
        t = 1_800_000_000
        points = [at(SCHOOL, t, 900), at(SCHOOL, t + 600, 5, acc=15)]
        rows, _ = self.intervals(points, SCHOOL, t + 700)
        self.assertEqual(rows, [])
        rows, now = self.intervals(points, SCHOOL, t + 600 + 8 * 60 + 1)
        self.assertEqual(rows[0]['enter_ts'], t + 600)
        self.assertTrue(now['inside'])

    def test_vague_reports_are_ignored_and_buffer_prevents_flapping(self):
        t = 1_800_000_000
        points = [at(SCHOOL, t, 900), at(SCHOOL, t + 60, 0, acc=1500), at(SCHOOL, t + 120, 0, acc=1200)]
        self.assertEqual(self.intervals(points, SCHOOL, t + 2000)[0], [])
        # 150 m from the center: inside the exit buffer, so it keeps presence.
        inside = [at(SCHOOL, t + 200, 0), at(SCHOOL, t + 260, 0)]
        near = [at(SCHOOL, t + 900 + i * 300, 150, acc=10) for i in range(5)]
        rows, now = self.intervals(points + inside + near, SCHOOL, t + 3000)
        self.assertIsNone(rows[0]['leave_ts'])

    def test_short_gap_between_visits_is_merged(self):
        t = 1_800_000_000
        points = [at(SCHOOL, t, 900), at(SCHOOL, t + 60, 0), at(SCHOOL, t + 120, 0),
                  at(SCHOOL, t + 600, 2000, acc=20),  # far, precise: immediate leave
                  at(SCHOOL, t + 700, 0), at(SCHOOL, t + 760, 0)]
        rows, now = self.intervals(points, SCHOOL, t + 900)
        self.assertEqual(len(rows), 1)
        self.assertTrue(now['inside'])


class AttendanceTests(unittest.TestCase):
    def setUp(self):
        self.schedule = M['normalize_school_schedule']({'days': {'1': {'enabled': True, 'start': '08:00', 'end': '13:00'}}})
        self.day = '2026-11-02'  # Monday
        self.start = M['school_day_window'](self.day, self.schedule)[2]

    def record(self, school_visits, home_visits=(), points=(), now=None):
        visits = {'school': list(school_visits), 'home': list(home_visits)}
        return M['school_attendance_record'](self.day, visits, {'school': SCHOOL, 'home': HOME}, self.schedule, list(points), now or self.start + 9 * 3600)

    def visit(self, enter, leave, unknown=False):
        return {'enter_ts': enter, 'last_in_ts': leave - 120 if leave else enter, 'leave_ts': leave, 'entered_unknown': unknown}

    def test_on_time_with_home_departure_and_duration(self):
        row = self.record([self.visit(self.start - 900, self.start + 5 * 3600)], [self.visit(self.start - 9 * 3600, self.start - 2400)])
        self.assertEqual(row['status'], 'on_time')
        self.assertEqual(row['travel_minutes'], 25)
        self.assertEqual(row['present_minutes'], 315)
        self.assertFalse(row['early_leave'])

    def test_late_arrival_and_early_leave(self):
        row = self.record([self.visit(self.start + 1200, self.start + 3 * 3600)])
        self.assertEqual(row['status'], 'late')
        self.assertEqual(row['late_minutes'], 20)
        self.assertTrue(row['early_leave'])

    def test_absent_with_evidence_or_without_data(self):
        evidence = [at(HOME, self.start + 1800, 0)]
        row = self.record([], points=evidence, now=self.start + 3 * 3600)
        self.assertEqual(row['status'], 'absent')
        self.assertEqual(row['evidence']['near_place'], 'Zuhause')
        self.assertEqual(self.record([], now=self.start + 3 * 3600)['status'], 'no_data')
        self.assertEqual(self.record([], now=self.start + 1800)['status'], 'missing')
        self.assertEqual(self.record([], now=self.start - 600)['status'], 'upcoming')

    def test_off_days_and_weekends(self):
        schedule = M['normalize_school_schedule']({'off_days': [{'day': self.day, 'label': 'Herbstferien'}]})
        row = M['school_attendance_record'](self.day, {}, {'school': SCHOOL}, schedule, [], self.start + 3600)
        self.assertEqual((row['status'], row['label']), ('free', 'Herbstferien'))
        row = M['school_attendance_record']('2026-11-01', {}, {'school': SCHOOL}, self.schedule, [], self.start)
        self.assertEqual(row['status'], 'free')


class SchoolApiTests(unittest.TestCase):
    def setUp(self):
        self.keys = ('google_devices', 'google_locations', 'google_history', 'shared_links', 'history_retention')
        self.original = {key: copy.deepcopy(STATE.get(key)) for key in self.keys}
        self.original_school = copy.deepcopy(STATE.get('school_mode'))
        now = time.time()
        STATE['google_devices']['bag1'] = {'name': 'Schultasche Lea'}
        STATE['google_locations']['bag1'] = {'lat': SCHOOL['lat'], 'lon': SCHOOL['lon'], 'acc': 15, 'ts': now - 60}
        STATE['google_history']['bag1'] = {'enabled': True, 'points': [
            {**at(SCHOOL, now - 3600, 900), 'source': 'google'},
            {**at(SCHOOL, now - 1800, 5), 'source': 'google'},
            {**at(SCHOOL, now - 1500, -5), 'source': 'google'},
        ]}
        STATE['school_mode'] = M['default_school_store']()
        self.admin = APP.test_client()
        pair = self.admin.post('/api/mobile/v1/pair', json={'pw': 'Regression-Test-Password'})
        self.headers = {'X-CSRF-Token': pair.json['csrf_token']}
        self.trigger = Mock(return_value=['google'])
        self.patches = patch.dict(M['school_evaluate'].__globals__, mcp_trigger_locate=self.trigger)
        self.patches.start()

    def tearDown(self):
        self.patches.stop()
        for key, value in self.original.items():
            STATE[key] = value
        STATE['school_mode'] = self.original_school

    def admin_post(self, path, body):
        response = self.admin.post(path, json=body, headers=self.headers)
        self.assertEqual(response.status_code, 200, response.json)
        return response.json

    def test_full_school_flow_without_account(self):
        state = self.admin.get('/admin/api/school').json
        self.assertIn('google:bag1', [row['ref'] for row in state['trackers']])
        self.admin_post('/admin/api/school/bags', {'ref': 'google:bag1', 'enabled': True, 'child_name': 'Lea'})
        self.assertIn('school_bag', M['google_active_reasons']('bag1'))
        self.assertEqual(M['google_interval_for']('bag1'), (30, 35))
        self.assertTrue(STATE['google_history']['bag1']['enabled'])
        url = self.admin_post('/admin/api/school/links', {'viewer_name': 'Jessy'})['created_url']
        token = url.rsplit('/', 1)[-1]
        guest = APP.test_client()  # no session, no password
        overview = guest.get(f'/api/school/{token}')
        self.assertEqual(overview.status_code, 200)
        self.assertEqual(overview.json['viewer_name'], 'Jessy')
        self.assertEqual(overview.json['bags'][0]['child_name'], 'Lea')
        self.assertIsNotNone(overview.json['bags'][0]['location'])
        latest = overview.json['latest_event_seq']
        place = guest.post(f'/api/school/{token}/places', json={'kind': 'school', 'name': 'Grundschule', 'lat': SCHOOL['lat'], 'lon': SCHOOL['lon'], 'radius_m': 120})
        self.assertEqual(place.status_code, 200)
        # Simulate a place that existed before today's visit (events are only
        # announced for visits that start after a place was configured).
        STATE['school_mode']['places'][place.json['place']['id']]['created_ts'] = 0
        schedule = guest.post(f'/api/school/{token}/schedule', json={'days': {'1': {'enabled': True, 'start': '07:55', 'end': '13:10'}}, 'grace_minutes': 5})
        self.assertEqual(schedule.json['schedule']['days']['1']['start'], '07:55')
        self.assertEqual(guest.post(f'/api/school/{token}/schedule', json={'days': {'1': {'start': '25:00'}}}).status_code, 400)
        STATE['school_mode']['bags']['google:bag1']['created_ts'] = 0
        STATE['school_mode']['event_index'] = []
        M['school_evaluate'](force=True)
        overview = guest.get(f'/api/school/{token}').json
        self.assertEqual(overview['bags'][0]['current_place']['name'], 'Grundschule')
        history = guest.get(f'/api/school/{token}/history?ref=google:bag1&from={int(time.time()) - 7200}').json
        self.assertEqual(history['raw_count'], 4)
        self.assertEqual(history['visits'][0]['place_name'], 'Grundschule')
        events = guest.get(f'/api/school/{token}/events?after={latest}').json
        self.assertTrue(any(row['type'] == 'school_enter' for row in events['events']), events)
        # A schedule configured just now never produces a retroactive absence alarm.
        self.assertFalse(any(row['kind'] == 'absent' for row in events['events']), events)
        locate = guest.post(f'/api/school/{token}/locate', json={'ref': 'google:bag1'})
        self.assertEqual(locate.json['status'], 'scheduled')
        self.trigger.assert_called_once()
        self.assertEqual(guest.get(f'/api/school/{token}/attendance?days=7').status_code, 200)
        self.assertIn('schoolsection', self.admin.get('/').get_data(as_text=True))
        self.assertIn('Schultasche', guest.get(f'/school/{token}').get_data(as_text=True))
        self.admin.delete(f'/admin/api/school/links/{token}', json={}, headers=self.headers)
        self.assertEqual(guest.get(f'/api/school/{token}').status_code, 404)

    def test_invalid_school_link_is_rejected(self):
        self.assertEqual(APP.test_client().get('/api/school/' + 'x' * 32).status_code, 404)

    def test_guest_share_for_single_google_tracker(self):
        url = self.admin_post('/admin/api/shares', {'ref': 'google:bag1', 'password': 'mama1', 'expires_hours': 168, 'show_history': True})['created_url']
        link_id = url.rsplit('/', 1)[-1]
        guest = APP.test_client()
        self.assertEqual(guest.post(f'/api/shared/{link_id}/app', json={}).json['code'], 'password_required')
        self.assertEqual(guest.post(f'/api/shared/{link_id}/app', json={'pw': 'wrong'}).status_code, 401)
        first = APP.test_client().post(f'/api/shared/{link_id}/app', json={'pw': 'mama1'})
        self.assertEqual(first.status_code, 200)
        token = first.json['app_token']
        self.assertEqual(first.json['title'], 'Schultasche Lea')
        self.assertAlmostEqual(first.json['location']['lat'], SCHOOL['lat'], places=4)
        fresh = APP.test_client()
        again = fresh.post(f'/api/shared/{link_id}/app', json={}, headers={'X-Share-Token': token})
        self.assertEqual(again.status_code, 200)
        history = fresh.post(f'/api/shared/{link_id}/app/history', json={'from': time.time() - 7200}, headers={'X-Share-Token': token})
        self.assertEqual(history.json['raw_count'], 4)
        locate = fresh.post(f'/api/shared/{link_id}/app/locate', json={}, headers={'X-Share-Token': token})
        self.assertEqual(locate.json['status'], 'scheduled')
        # The established guest endpoint keeps working for such links.
        legacy = APP.test_client().post(f'/api/shared/{link_id}', json={'pw': 'mama1'})
        self.assertEqual(legacy.status_code, 200)
        self.assertIn('Gastlink', self.admin.get('/').get_data(as_text=True))

    def test_asset_links_are_public(self):
        response = APP.test_client().get('/.well-known/assetlinks.json')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json[0]['target']['package_name'], 'eu.rjuhas.rjtracker.android')


if __name__ == '__main__':
    unittest.main()
