"""Offline authentication tests; never load real credentials or contact AWS."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'run_aws_auth.sh'
MOCK = r'''
import json, os, sys
with open(os.environ['TEST_TRACE'], 'a') as trace:
    trace.write(json.dumps(sys.argv[1:]) + '\n')
if sys.argv[1:3] == ['sts', 'assume-role']:
    if os.environ['TEST_MODE'] == 'assume_failure':
        print('Requested duration exceeds role limit', file=sys.stderr)
        sys.exit(2)
    print(json.dumps({'Credentials': {
        'AccessKeyId': 'fixture-key', 'SecretAccessKey': 'fixture-secret',
        'SessionToken': 'fixture-token'}}))
elif sys.argv[1:3] == ['sts', 'get-caller-identity']:
    if os.environ['TEST_MODE'] == 'identity_failure': sys.exit(2)
    assert os.environ['AWS_SESSION_TOKEN'] == 'fixture-token'
    print(json.dumps({'Account': '123456789012'}))
else:
    raise AssertionError(sys.argv)
'''


class AuthTests(unittest.TestCase):
    def run_auth(self, duration=None, mode='normal', sourced=True):
        with tempfile.TemporaryDirectory(prefix='aws auth test ') as tmp:
            root = Path(tmp)
            # Replace both the prohibited credential loader and credential output
            # path before executing a disposable copy. No real auth script runs.
            source = SCRIPT.read_text()
            self.assertEqual(source.count('source ~/aws_env.sh'), 1)
            source = source.replace('source ~/aws_env.sh',
                                    'AWS_ACCOUNT_ID=123456789012\nAWS_ROLE_NAME=fixture-role')
            source = source.replace('CREDENTIALS_FILE="/tmp/aws_creds.json"',
                                    'CREDENTIALS_FILE="$TEST_CREDENTIALS_FILE"')
            script = root / 'auth.sh'
            script.write_text(source)
            binaries = root / 'bin'
            binaries.mkdir()
            aws = binaries / 'aws'
            aws.write_text(f'#!{sys.executable}\n' + MOCK)
            aws.chmod(0o755)
            jq = shutil.which('jq')
            self.assertIsNotNone(jq)
            (binaries / 'jq').symlink_to(jq)
            trace = root / 'trace'
            env = {'PATH': f'{binaries}:/usr/bin:/bin',
                   'TEST_TRACE': str(trace), 'TEST_MODE': mode,
                   'TEST_CREDENTIALS_FILE': str(root / 'credentials.json')}
            if duration is not None:
                env['AWS_SESSION_DURATION_SECONDS'] = duration
            command = (['/bin/bash', '-c', 'set -Eeuo pipefail; source "$1"',
                        'auth-test', str(script)] if sourced else ['/bin/bash', str(script)])
            result = subprocess.run(command, env=env, capture_output=True, text=True)
            calls = [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []
            self.assertNotIn('fixture-secret', result.stdout + result.stderr)
            self.assertNotIn('fixture-token', result.stdout + result.stderr)
            return result, calls

    def test_default_requests_three_hours(self):
        result, calls = self.run_auth()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[0][calls[0].index('--duration-seconds') + 1], '10800')
        self.assertIn('10800 seconds (requested)', result.stdout)

    def test_override_and_boundary_values(self):
        for duration in ['900', '7200', '43200']:
            with self.subTest(duration=duration):
                result, calls = self.run_auth(duration)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(calls[0][calls[0].index('--duration-seconds') + 1], duration)

    def test_invalid_duration_stops_before_aws(self):
        for duration in ['', '0', '899', '43201', '-1', '3h', '10800.0',
                         '010800', '1+10800', '999999999999999999999']:
            with self.subTest(duration=duration):
                result, calls = self.run_auth(duration)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(calls, [])
                self.assertIn('must be an integer', result.stderr)

    def test_role_limit_failure_has_no_retry_or_success(self):
        result, calls = self.run_auth(mode='assume_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertIn('MaxSessionDuration', result.stderr)
        self.assertNotIn('STS session duration:', result.stdout)

    def test_identity_failure_has_no_success(self):
        result, calls = self.run_auth(mode='identity_failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('STS session duration:', result.stdout)

    def test_executed_script_propagates_invalid_duration(self):
        result, calls = self.run_auth('invalid', sourced=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
