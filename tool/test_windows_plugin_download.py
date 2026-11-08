"""Run the patched CMake downloader against a local fault-injecting server."""

import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

from patch_windows_plugins import fix_media_kit


CMAKE = shutil.which('cmake')
PAYLOAD = b'verified native dependency fixture'
ORIGINAL = '''function(download_and_verify url md5 locationForArchive)
  message(FATAL_ERROR "original downloader must be replaced")
endfunction()
'''


@unittest.skipUnless(CMAKE, 'CMake is required for native download tests')
class PluginDownloadTests(unittest.TestCase):
    def scenario(self, responses, cached=None):
        received = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                status, body = responses[min(len(received), len(responses) - 1)]
                received.append(self.path)
                self.send_response(status)
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix='thmr cmake ') as temporary:
                directory = Path(temporary)
                archive = directory / 'native.7z'
                if cached is not None:
                    archive.write_bytes(cached)
                script = directory / 'download.cmake'
                script.write_text(fix_media_kit(ORIGINAL) +
                    f'\ndownload_and_verify("http://127.0.0.1:{server.server_port}/native.7z" '
                    f'"{hashlib.md5(PAYLOAD).hexdigest()}" "{archive.as_posix()}")\n')
                result = subprocess.run([CMAKE, '-P', str(script)],
                                        capture_output=True, text=True, timeout=50)
                body = archive.read_bytes() if archive.exists() else None
                return result, body, len(received)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_http_504_is_retried(self):
        result, body, requests = self.scenario([(504, b'gateway'), (200, PAYLOAD)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((body, requests), (PAYLOAD, 2))

    def test_corrupt_download_is_retried_and_verified(self):
        result, body, requests = self.scenario([(200, b'partial'), (200, PAYLOAD)])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((body, requests), (PAYLOAD, 2))

    def test_exhausted_download_fails_and_removes_bad_archive(self):
        result, body, requests = self.scenario([(200, b'corrupt')])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('after 3 attempts', ' '.join(result.stderr.split()))
        self.assertEqual((body, requests), (None, 3))

    def test_valid_cache_avoids_network(self):
        result, body, requests = self.scenario([(504, b'gateway')], cached=PAYLOAD)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((body, requests), (PAYLOAD, 0))

    def test_corrupt_cache_is_replaced(self):
        result, body, requests = self.scenario([(200, PAYLOAD)], cached=b'corrupt')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((body, requests), (PAYLOAD, 1))

    def test_patch_is_idempotent(self):
        patched = fix_media_kit(ORIGINAL)
        self.assertEqual(fix_media_kit(patched), patched)


if __name__ == '__main__':
    unittest.main()
