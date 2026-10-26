"""Apple per-tracker completion; offline fixtures and existing store formats."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_backend_calendar_mcp import M, APP, STATE
G = M['fetch_from_apple'].__globals__

class RefreshTests(unittest.TestCase):
    def setUp(self):
        self.original = {key: STATE.get(key) for key in ('account', 'accessories', 'apple_inflight', 'report_stats', 'polling_runtime', 'apple_next_fetch', 'sync_failures', 'sync_backoff_until')}
        self.a, self.b = object(), object()
        self.account = Mock()
        STATE.update(account=self.account, accessories={'first': self.a, 'second': self.b},
                     apple_inflight=set(), report_stats={'devices': {}}, polling_runtime={'providers': {}}, apple_next_fetch={})
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

if __name__ == '__main__': unittest.main()
