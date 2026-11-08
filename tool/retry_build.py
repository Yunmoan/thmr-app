"""Retry a build only for transient dependency/network failures."""

import argparse
import re
import subprocess
import sys
import time


TRANSIENT_FAILURE = re.compile(
    r'(?:HTTP(?: response:)?|status code)[: ]+(?:408|429|5\d\d)\b'
    r'|(?:connection|read|connect) (?:reset|timed out)'
    r'|temporary failure in name resolution'
    r'|remote host terminated the handshake',
    re.IGNORECASE,
)


def run(command, attempts=3):
    for attempt in range(1, attempts + 1):
        output = []
        with subprocess.Popen(command, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True,
                              encoding='utf-8', errors='replace') as process:
            for line in process.stdout:
                print(line, end='', flush=True)
                output.append(line)
            code = process.wait()
        if code == 0 or attempt == attempts:
            return code
        if not TRANSIENT_FAILURE.search(''.join(output)):
            return code
        delay = attempt * 15
        print(f'Transient dependency download failure; retrying build '
              f'in {delay}s ({attempt + 1}/{attempts}).', flush=True)
        time.sleep(delay)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ['--']:
        command = command[1:]
    if not command:
        parser.error('a build command is required after --')
    return run(command)


if __name__ == '__main__':
    sys.exit(main())
