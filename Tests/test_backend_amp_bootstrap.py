"""AMP start and Google interpreter self-healing; offline, temporary folders only.

Reproduces the AMP failure "Fatal Python error: Failed to import encodings
module" that appears when the private Python environment was created by a
server Python that has since been upgraded or removed.
"""
import os
from pathlib import Path
import runpy
import shutil
import stat
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
BROKEN_PYTHON = """#!/bin/sh
echo "Could not find platform independent libraries <prefix>" >&2
echo "Fatal Python error: Failed to import encodings module" >&2
echo "ModuleNotFoundError: No module named 'encodings'" >&2
exit 1
"""


def write_broken_python(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(BROKEN_PYTHON)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return path


@unittest.skipIf(os.name != 'posix', 'AMP runs on Linux')
class AmpBootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='amp-bootstrap-')
        self.root = Path(self.temporary.name)
        shutil.copy(ROOT / 'Backend' / 'amp_bootstrap.py', self.root / 'Tracker_Backend_AMP.py')
        # run_path returns a copy; patch the namespace the functions really use.
        self.B = runpy.run_path(str(self.root / 'Tracker_Backend_AMP.py'), run_name='amp_bootstrap_test')['_amp_bootstrap'].__globals__
        self.support = self.root / '.tracker-apple-support' / self.B['_AMP_PAYLOAD_SHA'][:16]
        self.environment = self.root / self.B['_AMP_ENV_NAME']
        self.python = self.environment / 'bin' / 'python'
        self.marker = self.environment / '.tracker-ready'

    def tearDown(self):
        self.temporary.cleanup()

    def test_existing_environment_id_is_kept_for_healthy_installations(self):
        self.assertEqual(self.B['_AMP_ENV_NAME'], '.tracker-apple-python-20.4.1')

    def test_missing_environment_is_reported_as_first_start(self):
        self.assertEqual(self.B['_amp_environment_state'](self.environment, self.python, self.marker)[0], 'missing')

    def test_interpreter_without_standard_library_is_detected(self):
        write_broken_python(self.python)
        self.marker.write_text(self.B['_AMP_PAYLOAD_SHA'])
        state, detail = self.B['_amp_environment_state'](self.environment, self.python, self.marker)
        self.assertEqual(state, 'broken')
        self.assertIn('encodings', detail)

    def test_dangling_interpreter_link_is_detected(self):
        self.python.parent.mkdir(parents=True)
        self.python.symlink_to(self.root / 'removed-python3.11')
        self.assertEqual(self.B['_amp_environment_state'](self.environment, self.python, self.marker)[0], 'broken')

    def test_healthy_legacy_marker_only_needs_missing_packages(self):
        import venv
        venv.EnvBuilder(with_pip=False, symlinks=True).create(self.environment)
        self.marker.write_text(self.B['_AMP_PAYLOAD_SHA'])  # 20.4.x/20.5.x marker format
        self.assertEqual(self.B['_amp_environment_state'](self.environment, self.python, self.marker)[0], 'packages')
        with patch.dict(self.B, _AMP_PACKAGE_PROBE='import json'):
            self.assertEqual(self.B['_amp_environment_state'](self.environment, self.python, self.marker)[0], 'ready')
        self.marker.write_text('{"payload": "different"}')
        self.assertEqual(self.B['_amp_environment_state'](self.environment, self.python, self.marker)[0], 'outdated')

    def test_foreign_python_variables_never_reach_private_interpreter(self):
        with patch.dict(os.environ, PYTHONHOME='/nonexistent', PYTHONPATH='/foreign', VIRTUAL_ENV='/old', KEEP='1'):
            environment = self.B['_amp_clean_environment']()
        self.assertNotIn('PYTHONHOME', environment)
        self.assertNotIn('PYTHONPATH', environment)
        self.assertNotIn('VIRTUAL_ENV', environment)
        self.assertEqual(environment['KEEP'], '1')

    def test_broken_environment_is_rebuilt_without_touching_data(self):
        data = self.root / 'data'
        data.mkdir()
        (data / 'account.json').write_text('{"keep": true}')
        write_broken_python(self.python)
        (self.environment / 'lib' / 'python3.11' / 'site-packages').mkdir(parents=True)
        self.marker.write_text(self.B['_AMP_PAYLOAD_SHA'])
        (self.support / 'setup_apple_adi.py').write_text("print('Apple ADI is already installed and verified.')\n")

        def create(environment):
            import venv
            venv.EnvBuilder(with_pip=False, clear=True, symlinks=True).create(environment)

        install = Mock()
        with patch.dict(self.B, _amp_require_tools=Mock(), _amp_create_environment=create,
                        _amp_install_packages=install, _AMP_PACKAGE_PROBE='import json'):
            self.B['_amp_prepare_environment'](self.root, self.support, self.environment, self.python, self.marker)
            state = self.B['_amp_environment_state'](self.environment, self.python, self.marker)[0]
        install.assert_called_once()
        self.assertEqual(state, 'ready')
        self.assertFalse((self.environment / 'lib' / 'python3.11').exists())
        self.assertEqual((data / 'account.json').read_text(), '{"keep": true}')
        self.assertEqual([path.name for path in self.root.iterdir() if '.defekt-' in path.name], [])

    def test_healthy_environment_is_reused_without_installation(self):
        import venv
        venv.EnvBuilder(with_pip=False, symlinks=True).create(self.environment)
        self.marker.write_text(self.B['_AMP_PAYLOAD_SHA'])
        guard = Mock(side_effect=AssertionError('no installation expected'))
        with patch.dict(self.B, _amp_require_tools=guard, _amp_create_environment=guard,
                        _amp_install_packages=guard, _AMP_PACKAGE_PROBE='import json'):
            self.B['_amp_prepare_environment'](self.root, self.support, self.environment, self.python, self.marker)

    def test_packaged_file_check_reports_broken_environment_without_repairing(self):
        import subprocess
        output = self.root / 'packaged' / 'Tracker_Backend_AMP.py'
        subprocess.run([sys.executable, str(ROOT / 'Scripts' / 'package_amp_backend.py'), str(output)], check=True, capture_output=True)
        write_broken_python(output.parent / self.B['_AMP_ENV_NAME'] / 'bin' / 'python')
        completed = subprocess.run([sys.executable, str(output), '--amp-check'], capture_output=True, text=True, timeout=120)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn('broken', completed.stdout)
        self.assertTrue((output.parent / self.B['_AMP_ENV_NAME'] / 'bin' / 'python').is_file())


@unittest.skipIf(os.name != 'posix', 'server venv layout is POSIX')
class GoogleInterpreterHealingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from test_backend_calendar_mcp import M
        cls.M = M
        cls.G = M['google_python_path'].__globals__

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='google-venv-')
        self.venv = Path(self.temporary.name) / 'venv'
        self.patches = patch.dict(self.G, GOOGLE_VENV_DIR=self.venv)
        self.patches.start()
        self.G['google_venv_probe_cache'].clear()

    def tearDown(self):
        self.patches.stop()
        self.G['google_venv_probe_cache'].clear()
        self.temporary.cleanup()

    def test_dead_google_interpreter_is_never_used_and_repair_is_scheduled(self):
        write_broken_python(self.venv / 'bin' / 'python')
        repair = Mock(return_value=True)
        with patch.dict(self.G, google_schedule_venv_repair=repair), patch.dict(os.environ, {}, clear=False) as environment:
            environment.pop('ULTRA_TRACKER_GOOGLE_PYTHON', None)
            self.assertEqual(self.M['google_python_path'](), sys.executable)
        repair.assert_called_once()

    def test_working_google_interpreter_is_used(self):
        import venv
        venv.EnvBuilder(with_pip=False, symlinks=True).create(self.venv)
        repair = Mock()
        with patch.dict(self.G, google_schedule_venv_repair=repair):
            self.assertEqual(self.M['google_python_path'](), str(self.venv / 'bin' / 'python'))
        repair.assert_not_called()

    def test_bridge_environment_drops_foreign_python_home(self):
        with patch.dict(os.environ, PYTHONHOME='/nonexistent', PYTHONPATH='/foreign'):
            environment = self.M['google_child_environment']('/tools')
        self.assertNotIn('PYTHONHOME', environment)
        self.assertEqual(environment['PYTHONPATH'], '/tools')

    def test_repair_worker_rebuilds_broken_venv(self):
        tools = Path(self.temporary.name) / 'tools'
        tools.mkdir()
        (tools / 'requirements.txt').write_text('')
        write_broken_python(self.venv / 'bin' / 'python')
        with patch.dict(self.G, google_tools_path=lambda: tools, google_ensure_auth_dependency=Mock(return_value=True),
                        google_dependency_status=Mock(return_value={'ready': True}), google_auth_save=Mock()):
            self.M['google_dependency_install_worker'](repair=True)
        self.assertTrue(self.M['google_python_runs'](self.venv / 'bin' / 'python', force=True))


if __name__ == '__main__':
    unittest.main()
