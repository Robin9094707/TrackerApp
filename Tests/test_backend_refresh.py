"""Apple per-tracker completion; offline fixtures and existing store formats."""
import asyncio
import copy
from pathlib import Path
import sys
import time
from queue import Queue
from types import SimpleNamespace
import unittest
from unittest.mock import AsyncMock, Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_backend_calendar_mcp import M, APP, STATE
G = M['fetch_from_apple'].__globals__

class RefreshTests(unittest.TestCase):
    def setUp(self):
        self.original = {key: STATE.get(key) for key in ('account', 'accessories', 'apple_inflight', 'report_stats', 'polling_runtime', 'apple_next_fetch', 'sync_failures', 'sync_backoff_until', 'locations', 'since_ts', 'notification_settings', 'notification_runtime')}
        self.a, self.b = object(), object()
        self.account = Mock()
        STATE.update(account=self.account, accessories={'first': self.a, 'second': self.b},
                     apple_inflight=set(), report_stats={'devices': {}}, polling_runtime={'providers': {}}, apple_next_fetch={},
                     locations={}, since_ts={}, notification_settings=M['default_notification_settings'](), notification_runtime={})
        self.patches = patch.dict(G, save_account_state=Mock(), save_accessory_state=Mock(),
                                  append_notification_console=Mock(), apple_active_reasons=lambda _: [],
                                  apple_schedule_next=lambda *a, **k: 0)
        self.patches.start()

    def tearDown(self):
        self.patches.stop()
        STATE.update(self.original)

    def refresh(self, name='first'):
        return M['mobile_tracker_refresh_state']({'provider': 'apple', 'id': name})

    def test_first_tag_finishes_before_second_and_empty_is_success(self):
        before = self.refresh()['completion']
        def respond(devices):
            if devices == [self.b]:
                first = self.refresh()
                self.assertGreater(first['completion'], before)
                self.assertEqual(first['status'], 'empty')
                self.assertNotIn('first', STATE['apple_inflight'])
                self.assertIn('second', STATE['apple_inflight'])
            return {devices[0]: []}
        self.account.fetch_location_history.side_effect = respond
        self.assertTrue(M['fetch_from_apple'](['first', 'second']))
        self.assertEqual(self.account.fetch_location_history.call_count, 2)
        self.assertFalse(STATE['apple_inflight'])

    def test_failure_is_terminal_and_other_tag_still_collects(self):
        self.account.fetch_location_history.side_effect = [RuntimeError('offline'), {self.b: []}]
        self.assertTrue(M['fetch_from_apple'](['first', 'second']))
        self.assertEqual(self.refresh()['status'], 'error')
        self.assertGreater(self.refresh()['completion'], 0)
        self.assertEqual(self.refresh('second')['status'], 'empty')
        self.assertGreater(STATE['sync_backoff_until'], 0)
        self.assertFalse(STATE['apple_inflight'])

    def test_inflight_tag_is_coalesced_and_duplicate_input_is_deduplicated(self):
        STATE['apple_inflight'].add('first')
        self.account.fetch_location_history.return_value = {self.b: []}
        self.assertTrue(M['fetch_from_apple'](['first', 'second', 'second']))
        self.account.fetch_location_history.assert_called_once_with([self.b])
        self.assertEqual(STATE['apple_inflight'], {'first'})

    def test_completed_tag_new_queued_request_is_not_cleared_by_old_batch(self):
        def respond(devices):
            if devices == [self.b]:
                STATE['apple_inflight'].add('first')
            return {devices[0]: []}
        self.account.fetch_location_history.side_effect = respond
        M['fetch_from_apple'](['first', 'second'])
        self.assertEqual(STATE['apple_inflight'], {'first'})

    def test_all_reports_reach_existing_processing_without_truncation(self):
        reports = [object() for _ in range(12)]
        response = {self.a: reports}
        self.account.fetch_location_history.return_value = response
        with patch.dict(G, process_report_results=Mock(return_value=(12, 12))):
            M['fetch_from_apple'](['first'])
            G['process_report_results'].assert_called_once_with([('first', self.a)], response, 'history')
        self.assertEqual(STATE['report_stats']['devices']['first']['last_received'], 12)

    def test_locate_baseline_is_before_dispatch_even_when_worker_finishes_immediately(self):
        client = APP.test_client()
        paired = client.post('/api/mobile/v1/pair', json={'pw': 'Regression-Test-Password'})
        headers = {'X-CSRF-Token': paired.json['csrf_token']}
        model = {'provider': 'apple', 'id': 'first', 'ref': 'apple:first', 'name': 'First'}
        def dispatch(_):
            M['polling_attempt_finish']('apple', 'first', 'test', 'success')
            return ['apple']
        before = self.refresh()['completion']
        with patch.dict(G, mcp_resolve_tracker=lambda _: model, mcp_trigger_locate=dispatch):
            response = client.post('/api/mobile/v1/locate', json={'tracker': 'apple:first'}, headers=headers)
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json['trackers'][0]['refresh']['completion'], before)
        self.assertGreater(self.refresh()['completion'], before)

    def test_lightweight_status_returns_reply_before_apple_history_write(self):
        client = APP.test_client()
        self.assertEqual(client.get('/api/mobile/v1/tracker-refresh?ref=apple:first').status_code, 401)
        client.post('/api/mobile/v1/pair', json={'pw': 'Regression-Test-Password'})
        current = SimpleNamespace(latitude=51.43, longitude=6.76, horizontal_accuracy=10, timestamp=time.time())
        self.account.fetch_location_history.return_value = {self.a: [current]}
        baseline = self.refresh()['completion']
        path = f'/api/mobile/v1/tracker-refresh?ref=apple:first&after={baseline}'

        def store(*args, **kwargs):
            reply = client.get(path).json
            self.assertEqual(reply['refresh']['status'], 'success')
            self.assertTrue(reply['refresh']['reply_ready'])
            self.assertGreater(reply['refresh']['completion'], baseline)
            self.assertEqual(reply['location']['latitude'], 51.43)
            return 0

        with patch.dict(G, add_persistent_history_points=store, add_recording_points=Mock(return_value=0),
                        add_shared_history_points=Mock(return_value=0), add_points_to_apple_tests=Mock(),
                        recovery_capture_points=Mock(), process_tracker_location_reports=Mock()):
            self.assertTrue(M['fetch_from_apple'](['first']))

    def test_findmy_empty_http_response_publishes_before_library_can_retry(self):
        provider = SimpleNamespace(user_agent='test')
        session = M['AppleIdentityHttpSession'](provider)
        reply = SimpleNamespace(status_code=200, text=lambda: '')
        M['polling_attempt_begin']('apple', 'first', 'test')
        token = M['apple_reply_tracker'].set('first')
        try:
            with patch.object(M['FindMyHttpSession'], 'request', AsyncMock(return_value=reply)):
                returned = asyncio.run(session.request('POST', 'https://gateway.icloud.com/findmyservice/v2/fetch'))
            self.assertIs(returned, reply)
            self.assertEqual(self.refresh()['status'], 'responded')
            self.assertGreater(self.refresh()['completion'], 0)
        finally:
            M['apple_reply_tracker'].reset(token)

    def test_samsung_reports_current_reply_before_history_call_and_keeps_current_on_history_error(self):
        keys = ('samsung_devices', 'samsung_locations', 'samsung_stats', 'samsung_inflight',
                'samsung_failures', 'samsung_next_fetch')
        saved = {key: STATE.get(key) for key in keys}
        point = {'ts': time.time(), 'lat': 51.44, 'lon': 6.76, 'acc': 12, 'report_id': 'fresh'}
        try:
            STATE.update(samsung_devices={'tag': {'name': 'Tag'}}, samsung_locations={}, samsung_stats={},
                         samsung_inflight=set(), samsung_failures={}, samsung_next_fetch={})
            def execute(method, path, **kwargs):
                if path == '/trackers/geolocation':
                    return {'items': [{'deviceId': 'tag', 'geolocations': [point]}]}
                refresh = M['mobile_tracker_refresh_state']({'provider': 'samsung', 'id': 'tag'})
                self.assertEqual(refresh['status'], 'success')
                self.assertTrue(refresh['reply_ready'])
                self.assertEqual(STATE['samsung_locations']['tag'], point)
                raise RuntimeError('history timed out')

            with patch.dict(G, samsung_execute=execute, normalize_samsung_location=lambda raw, *_: (raw, False),
                            samsung_active_reasons=lambda _: ['history'], samsung_store_points=Mock(return_value=(1, 0)),
                            samsung_register_sync=Mock(), add_points_to_samsung_tests=Mock(),
                            process_tracker_location_reports=Mock(), save_json=Mock()):
                self.assertTrue(M['fetch_from_samsung']('tag'))
                G['samsung_store_points'].assert_called_once_with('tag', [point])
        finally:
            STATE.update(saved)

    def test_manual_queue_deduplicates_and_bounds_pending_requests(self):
        jobs = Queue(maxsize=1)
        with patch.dict(G, manual_locate_queues={'apple': jobs}, manual_locate_started={'apple'},
                        manual_locate_pending={}):
            schedule = M['schedule_manual_locate']
            self.assertTrue(schedule('apple:first', 'test'))
            self.assertTrue(schedule('apple:first', 'other'))
            self.assertFalse(schedule('apple:second', 'test'))
            self.assertEqual(jobs.get_nowait()[1:], ('first', 'test'))

    def test_compact_departure_skips_provider_wait_and_uses_saved_anchor(self):
        model = {'ref': 'apple:first', 'id': 'first', 'provider': 'apple',
                 'location': {'lat': 51.43, 'lon': 6.76, 'acc': 12, 'ts': time.time()}}
        with patch.dict(G, schedule_manual_locate=Mock(), mcp_live_models=Mock(side_effect=AssertionError('live wait')),
                        mcp_departure_notifications_status=Mock(side_effect=AssertionError('full status'))):
            result = M['mcp_set_departure_notification'](model, {'enabled': True}, compact=True)
            self.assertTrue(result['notification']['enabled'])
            self.assertEqual(result['notification']['sources'][0]['anchor']['latitude'], 51.43)
            G['schedule_manual_locate'].assert_called_once_with('apple:first', 'mobile_departure_armed')

    def test_logged_out_account_rejected_without_dispatch_and_history_unchanged(self):
        client = APP.test_client()
        paired = client.post('/api/mobile/v1/pair', json={'pw': 'Regression-Test-Password'})
        before = copy.deepcopy(STATE['seven_day_history'])
        STATE['account'] = None
        with patch.dict(G, mcp_resolve_tracker=lambda _: {'provider':'apple', 'id':'first', 'ref':'apple:first'}, mcp_trigger_locate=Mock()):
            response = client.post('/api/mobile/v1/locate', json={'tracker':'apple:first'}, headers={'X-CSRF-Token':paired.json['csrf_token']})
            self.assertEqual(response.status_code, 400)
            G['mcp_trigger_locate'].assert_not_called()
        self.assertEqual(STATE['seven_day_history'], before)

class GoogleServerCollectionTests(unittest.TestCase):
    def setUp(self):
        self.original = {key: copy.deepcopy(STATE.get(key)) for key in ('google_settings', 'google_devices', 'google_history', 'google_next_fetch', 'google_pending_fetch', 'settings')}
        STATE.update(google_devices={'tag': {'name': 'Tag'}}, google_history={'tag': {'points': [], 'enabled': True}},
                     google_next_fetch={'tag': 1}, google_pending_fetch={}, google_settings={'devices': {}, 'background_tracking': True})
        self.patches = patch.dict(G, save_json=Mock(), audit_event=Mock())
        self.patches.start()

    def tearDown(self):
        self.patches.stop()
        STATE.update(self.original)

    def test_pause_stops_polling_and_history_but_keeps_stored_points(self):
        self.assertIn('background', M['google_active_reasons']('tag'))
        STATE['google_history']['tag']['points'] = [{'ts': 1, 'lat': 1, 'lon': 1}]
        M['set_google_server_collection'](True)
        self.assertEqual(M['google_active_reasons']('tag'), [])
        self.assertNotIn('tag', STATE['google_next_fetch'])
        self.assertEqual(M['google_store_history']('tag', [{'ts': 2, 'lat': 2, 'lon': 2}]), 0)
        self.assertEqual(len(STATE['google_history']['tag']['points']), 1)
        M['set_google_server_collection'](False, {'tag': True})
        self.assertTrue(M['google_server_collection_paused']('tag'))
        self.assertEqual(M['google_server_collection_public']()['paused_devices'], ['tag'])
        M['set_google_server_collection'](None, {'tag': False, 'unknown': True})
        self.assertFalse(M['google_server_collection_paused']('tag'))
        self.assertIn('background', M['google_active_reasons']('tag'))

    def test_untouched_legacy_google_window_moves_to_faster_default(self):
        legacy = M['normalize_polling_settings']({'google': {'interval_min': 60, 'interval_max': 70}})
        self.assertLess(legacy['google']['interval_min'], 60)
        saved = M['normalize_polling_settings']({'google': {'interval_min': 60, 'interval_max': 70}, 'updated_ts': 5})
        self.assertEqual((saved['google']['interval_min'], saved['google']['interval_max']), (60, 70))

if __name__ == '__main__': unittest.main()
