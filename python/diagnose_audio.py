#!/usr/bin/env python3
"""
Diagnostic script to check if audio and VAD are working.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
import sounddevice as sd
import torch

# Load VAD
print("Loading VAD model...")
model, utils = torch.hub.load(
    repo_or_dir='snakers4/silero-vad',
    model='silero_vad',
    force_reload=False,
    onnx=False,
    trust_repo=True
)
print("VAD loaded!")

SAMPLE_RATE = 16000
CHUNK_SIZE = 512  # Required by Silero VAD

print("\n" + "=" * 50)
print("AUDIO DIAGNOSTIC")
print("=" * 50)
print("\nSpeak into your microphone. You'll see:")
print("  - Audio level (how loud)")
print("  - VAD score (0-1, higher = more likely speech)")
print("\nPress Ctrl+C to stop.\n")

try:
    with sd.InputStream(
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype='float32',
        blocksize=CHUNK_SIZE
    ) as stream:
        while True:
            audio_chunk, _ = stream.read(CHUNK_SIZE)
            audio_chunk = audio_chunk.flatten()

            # Calculate audio level (RMS)
            level = np.sqrt(np.mean(audio_chunk ** 2))
            level_db = 20 * np.log10(level + 1e-10)  # Convert to dB

            # Get VAD score
            audio_tensor = torch.from_numpy(audio_chunk).float()
            vad_score = model(audio_tensor, SAMPLE_RATE).item()

            # Visual bar for level
            bar_len = int(min(50, max(0, (level_db + 60) / 60 * 50)))
            bar = "#" * bar_len + "-" * (50 - bar_len)

            # Color code VAD score
            if vad_score > 0.5:
                status = "SPEECH"
            else:
                status = "silence"

            print(f"\rLevel: [{bar}] {level_db:6.1f}dB | VAD: {vad_score:.2f} ({status})  ", end="", flush=True)

except KeyboardInterrupt:
    print("\n\nDone!")
