#!/usr/bin/env python3
"""AuraScribe CLI and Python SDK for the opt-in local control API."""
import argparse
import json
from pathlib import Path
from urllib.request import Request, urlopen

class AuraScribe:
    def __init__(self, project=None):
        root = Path(project) if project else Path(__file__).resolve().parent.parent
        self.connection = json.loads((root / '.aurascribe/control/connection.json').read_text())

    def request(self, endpoint, body=None):
        request = Request(f"http://127.0.0.1:{self.connection['port']}{endpoint}",
                          data=None if body is None else json.dumps(body).encode(),
                          headers={'Authorization': f"Bearer {self.connection['token']}",
                                   'Content-Type': 'application/json'})
        with urlopen(request, timeout=600) as response:
            return json.load(response)

    def transcribe(self, path, *, process=False, timestamps='none', instruction=None):
        return self.request('/transcriptions', {'path': str(Path(path).resolve()),
                            'process': process, 'timestamps': timestamps, 'instruction': instruction})

    def meeting_events(self):
        request = Request(f"http://127.0.0.1:{self.connection['port']}/meetings/events",
                          headers={'Authorization': f"Bearer {self.connection['token']}"})
        with urlopen(request, timeout=90) as response:
            for line in response:
                if line.startswith(b'data: '): yield json.loads(line[6:])

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['status', 'history', 'start', 'stop', 'cancel', 'paste-last', 'transcribe'])
    parser.add_argument('path', nargs='?')
    parser.add_argument('--project')
    parser.add_argument('--raw', action='store_true')
    parser.add_argument('--process', action='store_true', help='Apply global output processing')
    parser.add_argument('--timestamps', choices=['none', 'segment', 'word'], default='none')
    parser.add_argument('--instruction')
    args = parser.parse_args()
    app = AuraScribe(args.project)
    if args.command == 'transcribe':
        if not args.path: parser.error('transcribe requires a PCM WAV path')
        result = app.transcribe(args.path, process=args.process, timestamps=args.timestamps, instruction=args.instruction)
    elif args.command in ['status', 'history']:
        result = app.request('/' + args.command)
    else:
        endpoint = '/paste-last' if args.command == 'paste-last' else '/dictations/' + args.command
        result = app.request(endpoint, {'raw': args.raw})
    print(json.dumps(result, ensure_ascii=False, indent=2))
