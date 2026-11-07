"""Panel edition: real API/storage contracts and isolated Google/Bark transports."""
import ast
import copy
import json
import sys
import threading
import time
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_backend_calendar_mcp import M, STATE, APP
from test_backend_school import SCHOOL, HOME, at
G = M['native_school_day'].__globals__


class SchoolWeekTests(unittest.TestCase):
    def setUp(self):
        self.day = '2026-11-02'
        self.midnight = M['local_day_bounds'](self.day)[0]
        self.begin = self.midnight + 8 * 3600
        self.routine = {'id': 'lesson', 'place_id': 'school', 'days': [1, 2, 3, 4, 5], 'start': '08:00', 'end': '13:00'}
        self.options = M['native_school_options']({'notifications_enabled': True})
        self.plan = {'places': [SCHOOL], 'routines': [self.routine], 'options': self.options, 'updated_ts': self.midnight}

    def result(self, points, now=None, options=None):
        with patch.dict(G, school_model_points=lambda model, start, end: [p for p in points if start <= p['ts'] <= end]):
            return M['native_school_day']({}, [SCHOOL], [self.routine], self.day, now or self.begin + 6 * 3600, options or self.options)

    def test_late_first_report_does_not_claim_proven_delay(self):
        row = self.result([at(SCHOOL, self.begin + 1200), at(SCHOOL, self.begin + 1320)])['checks'][0]
        self.assertEqual((row['attendance_status'], row['delay_minutes'], row['late_minutes']), ('observed_late', 20, 0))
        self.assertEqual(row['observed_minutes'], 2, 'No invented hours of presence through a report gap')

    def test_precise_outside_report_supports_estimated_lateness(self):
        points = [at(SCHOOL, self.begin + 600, 2000), at(SCHOOL, self.begin + 1200), at(SCHOOL, self.begin + 1320)]
        row = self.result(points)['checks'][0]
        self.assertEqual((row['attendance_status'], row['late_minutes']), ('late', 20))
        self.assertTrue(row['arrival_is_estimate'])

    def test_future_duplicate_and_nonfinite_reports_do_not_confirm_presence(self):
        self.assertFalse(self.result([at(SCHOOL, self.begin + 60)] * 2, now=self.begin + 120)['checks'][0]['status'] == 'confirmed')
        intervals, _ = M['school_place_intervals']([at(SCHOOL, self.begin + 3600), {**at(SCHOOL, self.begin), 'lat': float('nan')}], SCHOOL, self.begin)
        self.assertEqual(intervals, [])

    def test_week_separates_future_free_and_unconfirmed_days_and_off_days(self):
        plan = copy.deepcopy(self.plan); plan['options']['off_days'] = [self.day]
        with patch.dict(G, school_model_points=Mock(return_value=[])):
            week = M['native_school_week']({}, plan, self.day, self.begin + 6 * 3600)
        self.assertEqual(len(week['days']), 7)
        self.assertEqual(week['days'][0]['status'], 'free')
        self.assertEqual(week['days'][1]['status'], 'upcoming')
        self.assertEqual(week['summary']['unconfirmed_days'], 0)
        self.assertEqual(week['summary']['planned_days'], 4)

    def test_notifications_are_durable_unique_and_do_not_replay_on_edit(self):
        store = M['default_school_store']()
        bag = {'ios_plan': self.plan, 'created_ts': self.midnight}
        send = Mock()
        points = [at(SCHOOL, self.begin + 600, 2000), at(SCHOOL, self.begin + 1200), at(SCHOOL, self.begin + 1320)]
        with patch.dict(G, append_notification_event=send, school_model_points=lambda model, start, end: [p for p in points if start <= p['ts'] <= end]):
            for _ in range(2):
                M['native_school_evaluate_bag'](store, 'google:bag', bag, {'name': 'Test'}, self.begin + 1800)
            self.assertEqual(send.call_count, 1)
            restored = M['normalize_school_store'](store)
            M['native_school_evaluate_bag'](restored, 'google:bag', bag, {'name': 'Test'}, self.begin + 1900)
            self.assertEqual(send.call_count, 1)
            bag['ios_plan']['updated_ts'] = self.begin + 2000
            M['native_school_evaluate_bag'](M['default_school_store'](), 'google:bag', bag, {'name': 'Test'}, self.begin + 2100)
            self.assertEqual(send.call_count, 1)

    def test_missing_reminders_stop_at_confirmation_and_respect_disable(self):
        store = M['default_school_store'](); bag = {'ios_plan': self.plan, 'created_ts': self.midnight}
        send = Mock()
        with patch.dict(G, append_notification_event=send, school_model_points=Mock(return_value=[])):
            M['native_school_evaluate_bag'](store, 'google:bag', bag, {}, self.begin + 600)
            M['native_school_evaluate_bag'](store, 'google:bag', bag, {}, self.begin + 900)
            self.assertEqual(send.call_count, 1)
            M['native_school_evaluate_bag'](store, 'google:bag', bag, {}, self.begin + 4200)
            self.assertEqual(send.call_count, 2)
            self.plan['options']['notifications_enabled'] = False
            M['native_school_evaluate_bag'](store, 'google:bag', bag, {}, self.begin + 8000)
            self.assertEqual(send.call_count, 2)

    def test_dst_week_uses_calendar_days(self):
        with patch.dict(G, school_model_points=Mock(return_value=[])):
            week = M['native_school_week']({}, self.plan, '2026-10-25', M['local_day_bounds']('2026-10-26')[0])
        self.assertEqual([row['day'] for row in week['days']], [f'2026-10-{d}' for d in range(19, 26)])

    def test_options_validation_preserves_old_client_fields(self):
        current = M['native_school_options']({'off_days': ['2026-11-02'], 'notifications_enabled': True})
        self.assertEqual(M['native_school_options']({}, current), current)
        for raw in ({'off_days': ['2026-02-30']}, {'grace_minutes': True}, {'reminder_minutes': 1}, []):
            with self.assertRaises(M['SchoolError']):
                M['native_school_options'](raw)


class BarkTests(unittest.TestCase):
    def setUp(self):
        self.original = {key: copy.deepcopy(STATE.get(key)) for key in ('notification_settings', 'notification_events')}
        STATE['notification_settings'] = M['default_notification_settings']()
        STATE['notification_events'] = []
        self.client = APP.test_client()
        pair = self.client.post('/api/mobile/v1/pair', json={'pw': 'Regression-Test-Password'})
        self.headers = {'X-CSRF-Token': pair.json['csrf_token']}
        self.path = '/api/mobile/v1/bark'
        self.payload = {'enabled': True, 'server': 'https://api.day.app', 'device_keys': ['key-one', 'key-two']}

    def tearDown(self):
        STATE.update(self.original)

    def save(self):
        response = self.client.put(self.path, json=self.payload, headers=self.headers)
        self.assertEqual(response.status_code, 200, response.json)
        return response

    def test_api_authorization_csrf_encryption_redaction_and_preservation(self):
        self.assertEqual(APP.test_client().get(self.path).status_code, 401)
        self.assertEqual(self.client.put(self.path, json=self.payload).status_code, 403)
        response = self.save()
        self.assertEqual(response.json['device_count'], 2)
        self.assertNotIn('key-one', json.dumps(response.json))
        stored = STATE['notification_settings']['channels']['bark']
        self.assertNotIn('key-one', json.dumps(stored))
        self.assertEqual(M['bark_keys'](stored), ['key-one', 'key-two'])
        self.assertIn('bark', M['notification_channel_names']())
        response = self.client.put(self.path, json={'enabled': True}, headers=self.headers)
        self.assertEqual(response.json['device_count'], 2)
        self.assertNotIn('key-one', json.dumps(M['notification_public_state']()))

    def test_invalid_update_does_not_partially_change_saved_channel(self):
        self.save(); before = copy.deepcopy(STATE['notification_settings'])
        response = self.client.put(self.path, json={'enabled': False, 'device_keys': ['https://example.com/key']}, headers=self.headers)
        self.assertEqual(response.status_code, 400)
        self.assertEqual(before, STATE['notification_settings'])
        self.assertEqual(self.client.put(self.path, json={'server': 'https://example.com/secret-key'}, headers=self.headers).status_code, 400)

    def test_fanout_retry_does_not_resend_accepted_recipient(self):
        self.save()
        event = {'id': 'bark-test', 'title': 'Schule', 'body': 'Bestätigt'}
        STATE['notification_events'] = [event]
        call = Mock(side_effect=[(200, '{"code":200}'), RuntimeError('secret-key'), (200, '{"code":200}')])
        config = STATE['notification_settings']['channels']['bark']
        with patch.dict(G, http_request=call):
            with self.assertRaisesRegex(RuntimeError, '1 angenommen, 1 Empfänger'):
                M['send_bark_channel'](config, event)
            M['send_bark_channel'](config, event)
        self.assertEqual([c.kwargs['payload']['device_key'] for c in call.call_args_list], ['key-one', 'key-two', 'key-two'])

    def test_batch_and_http200_api_error(self):
        self.payload['batch'] = True; self.save()
        config = STATE['notification_settings']['channels']['bark']
        call = Mock(return_value=(200, '{"code":400,"message":"secret-key"}'))
        with patch.dict(G, http_request=call):
            with self.assertRaisesRegex(RuntimeError, 'nicht angenommen'):
                M['send_bark_channel'](config, {'id': 'batch', 'body': 'x'})
        self.assertEqual(call.call_args.kwargs['payload']['device_keys'], ['key-one', 'key-two'])

    def test_critical_bark_opens_exact_tracker_and_cancellation_blocks_sends(self):
        self.save()
        event = {'id': 'evt_123_012345abcdef', 'tracker_ref': 'samsung:key / ä',
                 'type': 'movement_exit', 'bark_alarm': 'critical_repeat', 'bark_next_ts': 123}
        STATE['notification_events'] = [event]
        config = STATE['notification_settings']['channels']['bark']
        send = Mock(return_value=(200, '{"code":200}'))
        with patch.dict(G, http_request=send):
            M['send_bark_channel'](config, event)
            payload = send.call_args.kwargs['payload']
            self.assertEqual(payload['level'], 'critical')
            self.assertEqual(payload['url'], 'rjtracker://tracker?ref=samsung%3Akey%20%2F%20%C3%A4&alarm=1&event=evt_123_012345abcdef')
            self.assertEqual(M['stop_tracker_bark_alarms'](['samsung:key / ä']), 1)
            send.reset_mock()
            M['send_bark_channel'](config, {**event, 'bark_accepted': []})
            send.assert_not_called()

    def test_reminder_queues_once_and_confirmation_stops_it(self):
        event = {'id': 'evt_123_012345abcdef', 'tracker_ref': 'google:test',
                 'type': 'location_found', 'bark_alarm': 'critical_repeat', 'bark_next_ts': 100}
        STATE['notification_events'] = [event]
        queue = Mock()
        with patch.dict(G, notification_queue=queue):
            M['queue_bark_alarm_reminders'](100)
            M['queue_bark_alarm_reminders'](110)
            self.assertEqual(queue.put_nowait.call_count, 1)
            self.assertEqual(event['bark_next_ts'], 160)
            with patch.dict(G, mcp_resolve_tracker=lambda ref: {'ref': ref}):
                action = '/api/mobile/v1/action'
                data = {'action': 'confirm_tracker_bark_alarm', 'event_id': event['id']}
                self.assertEqual(self.client.post(action, json={**data, 'tracker': 'samsung:other'},
                                                  headers=self.headers).status_code, 404)
                self.assertEqual(self.client.post(action, json={**data, 'tracker': 'google:test'},
                                                  headers=self.headers).status_code, 200)
            self.assertTrue(event['acknowledged'])
            self.assertEqual(event['bark_next_ts'], 0)
            M['queue_bark_alarm_reminders'](170)
            self.assertEqual(queue.put_nowait.call_count, 1)

    def test_movement_uses_distinct_consecutive_reports_in_one_batch(self):
        now = int(time.time())
        def point(offset, lat=51.44, acc=10, name=None):
            return {'ts': now + offset, 'lat': lat, 'lon': 6.76, 'acc': acc,
                    'report_id': name or str(offset)}
        movement = M['normalize_tracker_notification_config']({'movement': {
            'enabled': True, 'anchor_lat': 51.43, 'anchor_lon': 6.76, 'radius': 150,
            'armed_ts': now - 120, 'strict_reports': True, 'min_confirmations': 3,
        }})['movement']
        runtime = {'stable': 'inside', 'baseline_report_ts': now - 120}
        outside = point(-60)
        self.assertIsNone(M['confirmed_departure'](movement, runtime, [outside, outside, point(-50, acc=2000)]))
        self.assertEqual(runtime['pending_count'], 0)
        departure = M['confirmed_departure'](movement, runtime, [point(-40), point(-30), point(-20)])
        self.assertEqual(departure[0]['report_id'], '-20')

    def test_bulk_queues_once_and_does_not_send_network_from_request(self):
        self.save()
        with patch.dict(G, http_request=Mock(side_effect=AssertionError('network is worker-only'))):
            response = self.client.post(self.path + '/bulk', json={'title': 'Test', 'body': 'Hallo'}, headers=self.headers)
            self.assertEqual(response.status_code, 202, response.json)
            self.assertEqual(self.client.post(self.path + '/bulk', json={'title': 'Test', 'body': 'Hallo'}, headers=self.headers).status_code, 429)
        event = STATE['notification_events'][0]
        self.assertEqual(event['requested_channels'], ['bark'])
        self.assertTrue(event['bark_only'])
        STATE['notification_settings']['enabled'] = False
        self.assertEqual(M['notification_channel_names'](['bark']), [])
        response = self.client.delete(self.path, headers=self.headers)
        self.assertEqual(response.json['device_count'], 0)


def bridge_definitions(*names):
    tree = ast.parse(M['GOOGLE_BRIDGE_SOURCE'])
    nodes = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in names]
    namespace = {'threading': threading, 'time': time, 'json': json}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), '<isolated-google-bridge>', 'exec'), namespace)
    return namespace


class GoogleTransportTests(unittest.TestCase):
    def packet(self, uuid, key, location=False):
        locations = types.SimpleNamespace(networkLocations=[1] if location else [], HasField=lambda field: False)
        return types.SimpleNamespace(fcmMetadata=types.SimpleNamespace(requestUuid=uuid), SerializeToString=lambda: key,
            deviceMetadata=types.SimpleNamespace(information=types.SimpleNamespace(locationInformation=types.SimpleNamespace(reports=types.SimpleNamespace(recentLocationAndNetworkLocations=locations)))))

    def test_metadata_first_then_multiple_packets_and_duplicates(self):
        cls = bridge_definitions('GoogleResponseWindow')['GoogleResponseWindow']
        window = cls('wanted')
        window.add(self.packet('other', b'wrong', True))
        window.add(self.packet('wanted', b'metadata'))
        packet = self.packet('wanted', b'first', True)
        window.add(packet); window.add(packet)
        timer = threading.Timer(0.01, lambda: window.add(self.packet('wanted', b'second', True)))
        timer.start()
        result = window.collect(0.2, settle=0.03); timer.join()
        self.assertEqual([p.SerializeToString() for p in result], [b'metadata', b'first', b'second'])

    def test_empty_metadata_does_not_pretend_to_be_location(self):
        cls = bridge_definitions('GoogleResponseWindow')['GoogleResponseWindow']
        window = cls('wanted'); window.add(self.packet('wanted', b'empty'))
        self.assertIsNone(window.last_location_packet)
        self.assertEqual(len(window.collect(0.001)), 1)
        self.assertEqual(M['google_classify_error']('google_decryption_failed:encrypted_reports_received'), 'decryption_failed')

    def test_header_padding_parameters_and_bad_packet_isolation(self):
        calls = []
        class Client:
            @staticmethod
            def _decrypt_raw_data(credentials, key, salt, raw):
                calls.append((key, salt))
                if raw == b'bad': raise ValueError()
                return b'{"payload":"ok"}'
        module = types.ModuleType('Auth.firebase_messaging.fcmpushclient'); module.FcmPushClient = Client
        with patch.dict(sys.modules, {'Auth': types.ModuleType('Auth'), 'Auth.firebase_messaging': types.ModuleType('Auth.firebase_messaging'), 'Auth.firebase_messaging.fcmpushclient': module}):
            bridge_definitions('install_fcm_message_guard')['install_fcm_message_guard']()
        client = Client(); client.credentials = {'gcm': {'app_id': 'ours'}}; client.callback = Mock(); client.callback_context = None
        def message(subtype, raw):
            fields = {'crypto-key': 'p256ecdsa=other; dh=abc-_', 'encryption': 'rs=4096;salt=xyz', 'subtype': subtype}
            return types.SimpleNamespace(app_data=[types.SimpleNamespace(key=k, value=v) for k,v in fields.items()], raw_data=raw, persistent_id='id')
        client._handle_data_message(message('foreign', b'ok'))
        client._handle_data_message(message('ours', b'bad'))
        client._handle_data_message(message('ours', b'ok'))
        self.assertEqual(calls, [('abc-_===', 'xyz='), ('abc-_===', 'xyz=')])
        self.assertEqual(client.callback.call_count, 1)


if __name__ == '__main__':
    unittest.main()
