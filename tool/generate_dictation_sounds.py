"""Generate AuraScribe's short local earcons. Run from the project root."""
import math
import struct
import wave
from pathlib import Path

Path('assets/sounds').mkdir(parents=True, exist_ok=True)
for name, tones in {
    'ready': [(660, .065), (880, .085)],
    'stop': [(660, .06), (440, .09)],
    'success': [(880, .055), (1100, .08)],
    'error': [(220, .12)],
}.items():
    samples = []
    for hz, seconds in tones:
        count = int(24000 * seconds)
        for i in range(count):
            envelope = math.sin(math.pi * i / count) ** 2
            samples.append(int(9000 * envelope * math.sin(2 * math.pi * hz * i / 24000)))
    with wave.open(f'assets/sounds/{name}.wav', 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(24000)
        output.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
