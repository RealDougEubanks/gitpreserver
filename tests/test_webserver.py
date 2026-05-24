"""
Unit tests for docker/webserver.py — stdlib unittest, no pip dependencies.

Covers pure functions only (no HTTP server spinup needed):
  read_status, write_status, get_config, _esc, trigger_backup guard.
"""

import json
import os
import sys
import tempfile
import unittest
import unittest.mock

# Make docker/webserver.py importable from the repo root.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'docker'))
import webserver  # noqa: E402  (import after sys.path manipulation)


class TestReadStatus(unittest.TestCase):
    def setUp(self):
        self._orig_status_file = webserver.STATUS_FILE

    def tearDown(self):
        webserver.STATUS_FILE = self._orig_status_file

    def test_missing_file_returns_unknown_status(self):
        webserver.STATUS_FILE = '/nonexistent/__gitpreserver_test__.json'
        result = webserver.read_status()
        self.assertEqual(result['status'], 'unknown')
        self.assertIsNone(result['last_run'])

    def test_invalid_json_returns_unknown_status(self):
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            f.write('not { valid json')
            webserver.STATUS_FILE = f.name
        try:
            result = webserver.read_status()
            self.assertEqual(result['status'], 'unknown')
        finally:
            os.unlink(webserver.STATUS_FILE)

    def test_valid_file_is_returned_unchanged(self):
        data = {'status': 'success', 'last_run': '2026-05-22T02:00:00Z',
                'message': 'All stages complete.'}
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
            json.dump(data, f)
            webserver.STATUS_FILE = f.name
        try:
            result = webserver.read_status()
            self.assertEqual(result['status'], 'success')
            self.assertEqual(result['last_run'], '2026-05-22T02:00:00Z')
        finally:
            os.unlink(webserver.STATUS_FILE)


class TestGetConfig(unittest.TestCase):
    """get_config must include GITPRESERVER_* and RCLONE_CONFIG_* vars only,
    with sensitive values redacted."""

    def setUp(self):
        self._saved = {k: v for k, v in os.environ.items()
                       if k.startswith(('GITPRESERVER_', 'RCLONE_CONFIG_'))}
        for k in self._saved:
            del os.environ[k]

    def tearDown(self):
        for k in list(os.environ):
            if k.startswith(('GITPRESERVER_', 'RCLONE_CONFIG_')):
                del os.environ[k]
        os.environ.update(self._saved)

    def test_returns_empty_dict_when_no_relevant_vars(self):
        self.assertEqual(webserver.get_config(), {})

    def test_includes_gitpreserver_vars(self):
        os.environ['GITPRESERVER_USERNAME'] = 'alice'
        cfg = webserver.get_config()
        self.assertIn('GITPRESERVER_USERNAME', cfg)
        self.assertEqual(cfg['GITPRESERVER_USERNAME'], 'alice')

    def test_includes_rclone_config_vars(self):
        os.environ['RCLONE_CONFIG_B2_TYPE'] = 'b2'
        cfg = webserver.get_config()
        self.assertEqual(cfg['RCLONE_CONFIG_B2_TYPE'], 'b2')

    def test_token_is_redacted_when_non_empty(self):
        os.environ['GITPRESERVER_TOKEN'] = 'github_pat_secret123'
        cfg = webserver.get_config()
        self.assertEqual(cfg['GITPRESERVER_TOKEN'], '***')

    def test_password_is_redacted(self):
        os.environ['RCLONE_CONFIG_MYCRYPT_PASSWORD'] = 'supersecret'
        cfg = webserver.get_config()
        self.assertEqual(cfg['RCLONE_CONFIG_MYCRYPT_PASSWORD'], '***')

    def test_key_is_redacted(self):
        os.environ['RCLONE_CONFIG_B2_KEY'] = 'myapikey'
        cfg = webserver.get_config()
        self.assertEqual(cfg['RCLONE_CONFIG_B2_KEY'], '***')

    def test_empty_secret_var_not_replaced_with_stars(self):
        os.environ['GITPRESERVER_TOKEN'] = ''
        cfg = webserver.get_config()
        self.assertEqual(cfg['GITPRESERVER_TOKEN'], '')

    def test_non_secret_var_not_redacted(self):
        os.environ['GITPRESERVER_USERNAME'] = 'bob'
        cfg = webserver.get_config()
        self.assertEqual(cfg['GITPRESERVER_USERNAME'], 'bob')

    def test_other_env_vars_excluded(self):
        os.environ['HOME'] = '/root'
        cfg = webserver.get_config()
        self.assertNotIn('HOME', cfg)


class TestEsc(unittest.TestCase):
    def test_ampersand(self):
        self.assertEqual(webserver._esc('a&b'), 'a&amp;b')

    def test_less_than(self):
        self.assertEqual(webserver._esc('<b>'), '&lt;b&gt;')

    def test_greater_than(self):
        self.assertEqual(webserver._esc('x>y'), 'x&gt;y')

    def test_double_quote(self):
        self.assertEqual(webserver._esc('"hi"'), '&quot;hi&quot;')

    def test_no_special_chars_unchanged(self):
        self.assertEqual(webserver._esc('hello world 123'), 'hello world 123')

    def test_non_string_coerced(self):
        self.assertEqual(webserver._esc(42), '42')

    def test_xss_payload_fully_escaped(self):
        payload = '<script>alert("xss")</script>'
        escaped = webserver._esc(payload)
        self.assertNotIn('<', escaped)
        self.assertNotIn('>', escaped)
        self.assertNotIn('"', escaped)


class TestTriggerBackup(unittest.TestCase):
    def setUp(self):
        self._orig_status_file = webserver.STATUS_FILE
        self._tmp = tempfile.NamedTemporaryFile(
            mode='w', suffix='.json', delete=False)
        self._tmp_name = self._tmp.name
        self._tmp.close()
        webserver.STATUS_FILE = self._tmp_name

    def tearDown(self):
        webserver.STATUS_FILE = self._orig_status_file
        try:
            os.unlink(self._tmp_name)
        except FileNotFoundError:
            pass

    def test_does_not_start_subprocess_when_already_running(self):
        with open(self._tmp_name, 'w') as f:
            json.dump({'status': 'running'}, f)

        with unittest.mock.patch('subprocess.run') as mock_run:
            webserver.trigger_backup()
            mock_run.assert_not_called()

    def test_writes_success_status_on_exit_code_zero(self):
        with open(self._tmp_name, 'w') as f:
            json.dump({'status': 'idle'}, f)

        mock_result = unittest.mock.MagicMock()
        mock_result.returncode = 0
        mock_result.stdout = 'All stages complete.'
        mock_result.stderr = ''

        with unittest.mock.patch('subprocess.run', return_value=mock_result):
            webserver.trigger_backup()

        with open(webserver.STATUS_FILE) as f:
            status = json.load(f)
        self.assertEqual(status['status'], 'success')

    def test_writes_failed_status_on_nonzero_exit_code(self):
        with open(self._tmp_name, 'w') as f:
            json.dump({'status': 'idle'}, f)

        mock_result = unittest.mock.MagicMock()
        mock_result.returncode = 1
        mock_result.stdout = ''
        mock_result.stderr = 'mirror failed'

        with unittest.mock.patch('subprocess.run', return_value=mock_result):
            webserver.trigger_backup()

        with open(webserver.STATUS_FILE) as f:
            status = json.load(f)
        self.assertEqual(status['status'], 'failed')


if __name__ == '__main__':
    unittest.main()
