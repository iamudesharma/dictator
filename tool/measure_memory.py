#!/usr/bin/env python3
"""Record macOS footprint and simultaneous process-tree RSS without audio/UI input.

python3 tool/measure_memory.py --pid PID --seconds 30 --label tray-idle
Output stays under .aurascribe/benchmarks/memory/. No process command lines,
transcripts, credentials or audio are collected. RSS and footprint stay separate.
"""
import argparse
import datetime
import json
import pathlib
import re
import subprocess
import time


def sample(pid):
    rows = {}
    output = subprocess.check_output(['ps', '-axo', 'pid=,ppid=,rss='], text=True)
    for line in output.splitlines():
        process, parent, rss = map(int, line.split())
        rows[process] = (parent, rss * 1024)
    if pid not in rows:
        raise SystemExit('Target process exited')
    family = {pid}
    while True:
        children = {p for p, (parent, _) in rows.items() if parent in family}
        if children.issubset(family):
            break
        family.update(children)
    result = {
        'time': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'pid': pid,
        'rootRssBytes': rows[pid][1],
        'treeRssBytes': sum(rows[p][1] for p in family),
        'childrenRssBytes': {str(p): rows[p][1] for p in family if p != pid},
    }
    vm = subprocess.run(['vmmap', '-summary', str(pid)], capture_output=True, text=True, timeout=30)
    for label, key in [('Physical footprint:', 'physicalFootprintBytes'),
                       ('Physical footprint (peak):', 'lifetimePeakFootprintBytes')]:
        match = re.search(re.escape(label) + r'\s*([\d.]+)([KMGT]?)', vm.stdout)
        if match:
            result[key] = int(float(match[1]) * 1024 ** (' KMGT'.index(match[2]) if match[2] else 0))
    if vm.returncode or 'physicalFootprintBytes' not in result:
        result['footprintUnavailable'] = True
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--seconds', type=float, default=30)
    parser.add_argument('--interval', type=float, default=5)
    parser.add_argument('--label', default='sample')
    args = parser.parse_args()
    if args.pid <= 0 or args.seconds < 0 or args.interval <= 0:
        parser.error('Use a positive PID/interval and nonnegative duration')
    root = pathlib.Path(__file__).resolve().parent.parent
    folder = root / '.aurascribe/benchmarks/memory'
    folder.mkdir(parents=True, exist_ok=True)
    label = re.sub(r'[^A-Za-z0-9_-]', '_', args.label)
    target = folder / f'{time.time_ns()}-{label}.jsonl'
    start = time.monotonic()
    with target.open('w') as stream:
        while True:
            data = sample(args.pid)
            data['label'] = args.label
            stream.write(json.dumps(data) + '\n')
            stream.flush()
            print(json.dumps(data), flush=True)
            remaining = args.seconds - (time.monotonic() - start)
            if remaining <= 0:
                break
            time.sleep(min(args.interval, remaining))
    print(f'Saved {target}')


if __name__ == '__main__':
    main()
