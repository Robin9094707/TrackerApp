"""Google catalog and durable-storage regressions; offline, temporary stores only."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_backend_calendar_mcp import M, STATE
G = M['sync_google_devices'].__globals__


class GoogleCatalogTests(unittest.TestCase):
    def setUp(self):
        self.keys = ('google_devices', 'google_links', 'google_history', 'google_locations', 'google_next_fetch')
        self.original = {key: copy.deepcopy(STATE[key]) for key in self.keys}
        STATE.update(google_devices={
            'one': {'id': 'one', 'name': 'My tag', 'name_override': 'My tag', 'custom_metadata': 'retain'},
            'two': {'id': 'two', 'name': 'Temporarily absent'},
        }, google_links={'apple-tag': {'google_id': 'two'}},
            google_history={'two': {'enabled': True, 'points': [{'report_id': 'existing'}]}},
            google_locations={'two': {'lat': 51, 'lon': 6, 'ts': 123}}, google_next_fetch={})
        self.before = {key: copy.deepcopy(STATE[key]) for key in self.keys}
        self.bridge = Mock()
        self.save = Mock()
        self.patches = patch.dict(G, run_google_bridge=self.bridge, save_json=self.save)
        self.patches.start()

    def tearDown(self):
        self.patches.stop()
        STATE.update(self.original)

    def test_partial_catalog_preserves_missing_tracker_links_and_history(self):
        self.bridge.return_value = {'devices': [{'id': 'one', 'name': 'Provider name'}]}
        self.assertEqual(M['sync_google_devices'](), 2)
        self.assertEqual(STATE['google_devices']['two'], self.before['google_devices']['two'])
        self.assertEqual(STATE['google_devices']['one']['name'], 'My tag')
        self.assertEqual(STATE['google_devices']['one']['custom_metadata'], 'retain')
        for key in ('google_links', 'google_history', 'google_locations'):
            self.assertEqual(STATE[key], self.before[key])

    def test_empty_listing_cannot_erase_saved_trackers(self):
        self.bridge.return_value = {'devices': []}
        with self.assertRaises(M['GoogleBridgeError']):
            M['sync_google_devices']()
        self.assertEqual({key: STATE[key] for key in self.keys}, self.before)
        self.save.assert_not_called()

    def test_malformed_listing_cannot_overwrite_saved_catalog(self):
        self.bridge.return_value = {'devices': [None, 'bad', {}, {'name': 'No ID'}]}
        with self.assertRaises(M['GoogleBridgeError']):
            M['sync_google_devices']()
        self.assertEqual({key: STATE[key] for key in self.keys}, self.before)
        self.save.assert_not_called()

    def test_valid_devices_still_import_from_mixed_listing(self):
        self.bridge.return_value = {'devices': [None, {'id': 'three', 'name': 'New tag'}]}
        self.assertEqual(M['sync_google_devices'](), 3)
        self.assertEqual(STATE['google_devices']['three']['name'], 'New tag')
        self.assertEqual(STATE['google_links'], self.before['google_links'])

    def test_nonfinite_reports_cannot_poison_latest_location_or_json(self):
        valid = {'lat': 51, 'lon': 6, 'ts': time.time(), 'acc': 12}
        self.assertIsNotNone(M['normalize_google_report'](valid, 'batch'))
        for field in ('lat', 'lon', 'ts', 'acc'):
            for invalid in (float('inf'), float('-inf'), float('nan')):
                with self.subTest(field=field, value=invalid):
                    self.assertIsNone(M['normalize_google_report']({**valid, field: invalid}, 'batch'))
        normalized = M['normalize_google_report']({**valid, 'alt': float('nan')}, 'batch')
        self.assertNotIn('alt', normalized)
        json.dumps(normalized, allow_nan=False)


class DurableStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / 'history.json'
        self.backup = self.path.with_name('history.json.bak')
        self.saved = {'tag': {'enabled': True, 'points': [{'report_id': 'keep-me'}]}}
        self.backup.write_text(json.dumps(self.saved))

    def tearDown(self):
        self.temp.cleanup()

    def test_corrupt_primary_recovers_and_keeps_good_backup_after_next_save(self):
        self.path.write_text('{ interrupted')
        self.assertEqual(M['safe_load_json'](self.path, {}), self.saved)
        self.assertEqual(json.loads(self.path.read_text()), self.saved)
        self.assertEqual(next(self.path.parent.glob('*.corrupt.*')).read_text(), '{ interrupted')
        M['atomic_write_json'](self.path, {'new': True})
        self.assertEqual(json.loads(self.backup.read_text()), self.saved)

    def test_missing_primary_keeps_intentionally_deleted_credentials_deleted(self):
        self.assertEqual(M['safe_load_json'](self.path, {}), {})
        self.assertFalse(self.path.exists())
        self.assertEqual(json.loads(self.backup.read_text()), self.saved)

    def test_missing_primary_recovers_existing_backup_when_explicitly_enabled(self):
        self.assertEqual(M['safe_load_json'](self.path, {}, recover_missing=True), self.saved)
        self.assertEqual(json.loads(self.path.read_text()), self.saved)

    def test_invalid_backup_type_is_not_restored(self):
        self.path.write_text('broken')
        self.backup.write_text('[]')
        self.assertEqual(M['safe_load_json'](self.path, {}), {})
        self.assertEqual(self.path.read_text(), 'broken')

    def test_normal_and_external_writes_do_not_rotate_corruption_into_backup(self):
        for external in (False, True):
            with self.subTest(external=external):
                self.path.write_text('broken')
                if external:
                    M['atomic_external_json_write'](self.path, lambda file: file.write_text('{"new":true}'))
                else:
                    M['atomic_write_json'](self.path, {'new': True})
                self.assertEqual(json.loads(self.backup.read_text()), self.saved)
                self.assertEqual(json.loads(self.path.read_text()), {'new': True})

    def test_backup_copy_failure_keeps_complete_previous_generation(self):
        self.path.write_text('{"current":true}')
        def interrupted_copy(source, target):
            Path(target).write_text('{')
            raise OSError('simulated full disk')
        with patch.dict(G, shutil=Mock(copy2=interrupted_copy)):
            M['atomic_write_json'](self.path, {'new': True})
        self.assertEqual(json.loads(self.backup.read_text()), self.saved)
        self.assertEqual(json.loads(self.path.read_text()), {'new': True})

    def test_google_recording_recovers_backup_before_appending(self):
        original = copy.deepcopy(STATE['google_recordings'])
        now = int(time.time())
        STATE['google_recordings']['recover'] = {'id': now - 60}
        path = Path(self.temp.name) / f"{M['google_device_safe_id']('recover')}_{now - 60}.json"
        old = {'lat': 51, 'lon': 6, 'ts': now - 20, 'acc': 10, 'report_id': 'old'}
        new = {**old, 'ts': now, 'report_id': 'new'}
        try:
            for missing in (False, True):
                with self.subTest(missing_primary=missing):
                    path.unlink(missing_ok=True)
                    if not missing:
                        path.write_text('interrupted')
                    path.with_name(path.name + '.bak').write_text(json.dumps({'id': now - 60, 'points': [old]}))
                    with patch.dict(G, GOOGLE_SESSIONS_DIR=Path(self.temp.name)):
                        self.assertEqual(M['google_store_recording']('recover', [new], now), 1)
                    self.assertEqual({point['report_id'] for point in json.loads(path.read_text())['points']}, {'old', 'new'})
        finally:
            STATE['google_recordings'] = original


if __name__ == '__main__':
    unittest.main()
