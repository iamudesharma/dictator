#!/usr/bin/env python3
"""Repeat fresh release launches; samples the app's own configured launch state.

No UI automation, microphone access, model downloads or settings changes.
Run only when AuraScribe is closed. Report the supplied label honestly (e.g.
settings-open, or hidden-tray); this tool does not alter window visibility.
"""
import argparse
import json
import pathlib
import statistics
import subprocess
import time
from measure_memory import sample


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True)
    parser.add_argument('--label', required=True)
    parser.add_argument('--runs', type=int, default=3)
    parser.add_argument('--settle', type=float, default=8)
    args = parser.parse_args()
    if args.runs < 1 or args.settle < 0:
        parser.error('runs must be positive and settle nonnegative')
    if subprocess.run(['pgrep', '-x', 'AuraScribe'], capture_output=True).returncode == 0:
        raise SystemExit('Close the running AuraScribe before benchmarking fresh launches.')
    binary = pathlib.Path(args.app).resolve() / 'Contents/MacOS/AuraScribe'
    records = []
    for run in range(args.runs):
        process = subprocess.Popen([str(binary)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            time.sleep(args.settle)
            result = sample(process.pid)
            result.update(label=args.label, run=run + 1, settleSeconds=args.settle)
            records.append(result)
            print(json.dumps(result), flush=True)
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    folder = pathlib.Path(__file__).resolve().parent.parent / '.aurascribe/benchmarks/memory'
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / f'{time.time_ns()}-launch.json'
    result = {'label': args.label, 'runs': records}
    footprints = [r['physicalFootprintBytes'] for r in records if 'physicalFootprintBytes' in r]
    if footprints:
        result.update(medianFootprintBytes=statistics.median(footprints), minFootprintBytes=min(footprints), maxFootprintBytes=max(footprints))
    target.write_text(json.dumps(result, indent=2))
    print(json.dumps({k: v for k, v in result.items() if k != 'runs'}), flush=True)
    print(f'Saved {target}')


if __name__ == '__main__':
    main()
