"""Exercise retry decisions against real failing subprocesses."""

from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

from retry_build import run


class RetryBuildTests(unittest.TestCase):
    def scenario(self, failure, succeeds_on=None):
        with tempfile.TemporaryDirectory() as temporary:
            counter = Path(temporary) / 'attempts'
            script = (
                'from pathlib import Path; import sys; '
                'p = Path(sys.argv[1]); '
                'n = int(p.read_text()) + 1 if p.exists() else 1; '
                'p.write_text(str(n)); '
                f'print({failure!r}); '
                f'sys.exit(0 if n == {succeeds_on!r} else 7)'
            )
            with patch('retry_build.time.sleep') as sleep:
                code = run([sys.executable, '-c', script, str(counter)])
            return code, int(counter.read_text()), sleep.call_count

    def test_gateway_failure_recovers_on_the_next_attempt(self):
        self.assertEqual(self.scenario(
            'Could not GET compiler.jar. Received status code 504', 2), (0, 2, 1))

    def test_network_failure_stops_after_three_attempts(self):
        self.assertEqual(self.scenario('HTTP 503: Service Unavailable'), (7, 3, 2))

    def test_gradle_wrapper_http_error_is_retried(self):
        self.assertEqual(self.scenario(
            'java.io.IOException: Server returned HTTP response code: 504 '
            'for URL: https://github.com/gradle/gradle-distributions/file.zip', 2),
            (0, 2, 1))

    def test_compiler_failure_is_not_retried(self):
        self.assertEqual(self.scenario('error: unresolved reference: widget'),
                         (7, 1, 0))

    def test_not_found_is_not_retried(self):
        self.assertEqual(self.scenario('Received status code 404'), (7, 1, 0))


if __name__ == '__main__':
    unittest.main()
