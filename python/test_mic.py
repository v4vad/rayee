#!/usr/bin/env python3
"""
Simple microphone test - records 3 seconds and shows if it captured anything.
"""

import numpy as np
import sounddevice as sd

print("Available audio devices:")
print(sd.query_devices())
print()

# Get default input device info
default_input = sd.query_devices(kind="input")
print(f"Default input device: {default_input['name']}")
print(f"  Max input channels: {default_input['max_input_channels']}")
print()

print("Recording 3 seconds... SPEAK NOW!")
print()

# Record
audio = sd.rec(
    int(3 * 16000),  # 3 seconds at 16kHz
    samplerate=16000,
    channels=1,
    dtype="float32",
    device=None,  # Use default
)
sd.wait()

# Check what we got
audio = audio.flatten()
max_level = np.max(np.abs(audio))
rms = np.sqrt(np.mean(audio**2))

print(f"Recording complete!")
print(f"  Max amplitude: {max_level:.6f}")
print(f"  RMS level: {rms:.6f}")
print()

if max_level < 0.001:
    print("❌ NO AUDIO DETECTED - microphone not working")
    print()
    print("Try:")
    print("  1. Quit Warp completely and reopen it")
    print("  2. Check System Settings > Sound > Input")
    print("     Make sure the right microphone is selected")
    print("  3. Speak louder / closer to the mic")
else:
    print("✅ AUDIO DETECTED - microphone is working!")
    print()
    print("You can now run: python test_rayee.py")
