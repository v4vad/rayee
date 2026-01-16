#!/usr/bin/env python3
"""
Rayee Test Script

This script tests the complete voice-to-text pipeline:
1. Records audio from your microphone
2. Converts speech to text using Whisper AI
3. Prints the transcribed text

Run with: python test_rayee.py
"""

import sys
import os

# Add the rayee package to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rayee.audio import AudioRecorder, record_for_duration, list_audio_devices
from rayee.transcribe import Transcriber
from rayee.vad import SmartRecorder
from rayee.models import list_available_models


def test_fixed_duration():
    """Test recording for a fixed duration (5 seconds)."""
    print("\n" + "=" * 60)
    print("TEST: Fixed Duration Recording (5 seconds)")
    print("=" * 60)

    # Record for 5 seconds
    print("\nGet ready to speak! Recording starts in 2 seconds...")
    import time
    time.sleep(2)

    audio = record_for_duration(5.0)

    if len(audio) == 0:
        print("ERROR: No audio recorded!")
        return

    # Transcribe
    print("\nTranscribing... (this may take a moment on first run)")
    transcriber = Transcriber(model_size="small")
    text = transcriber.transcribe(audio)

    print("\n" + "-" * 40)
    print("TRANSCRIPTION:")
    print("-" * 40)
    print(text)
    print("-" * 40)


def test_smart_recording():
    """Test smart recording with automatic stop."""
    print("\n" + "=" * 60)
    print("TEST: Smart Recording (auto-stops when you stop talking)")
    print("=" * 60)
    print("\nSpeak into your microphone.")
    print("Recording will automatically stop after 1.5 seconds of silence.")
    print()

    # Record with VAD
    recorder = SmartRecorder(
        silence_duration=1.5,  # Stop after 1.5 seconds of silence
        max_duration=30.0,     # Maximum 30 seconds
    )

    audio = recorder.record()

    if len(audio) == 0:
        print("No speech detected!")
        return

    # Transcribe
    print("\nTranscribing...")
    transcriber = Transcriber(model_size="small")
    text = transcriber.transcribe(audio)

    print("\n" + "-" * 40)
    print("TRANSCRIPTION:")
    print("-" * 40)
    print(text)
    print("-" * 40)


def test_manual_recording():
    """Test manual start/stop recording."""
    print("\n" + "=" * 60)
    print("TEST: Manual Recording (press Enter to stop)")
    print("=" * 60)

    recorder = AudioRecorder()

    print("\nPress Enter to START recording...")
    input()

    recorder.start()

    print("Recording... Press Enter to STOP...")
    input()

    audio = recorder.stop()

    if len(audio) == 0:
        print("No audio recorded!")
        return

    # Transcribe
    print("\nTranscribing...")
    transcriber = Transcriber(model_size="small")
    text = transcriber.transcribe(audio)

    print("\n" + "-" * 40)
    print("TRANSCRIPTION:")
    print("-" * 40)
    print(text)
    print("-" * 40)


def main():
    """Main test menu."""
    print("\n" + "=" * 60)
    print("  RAYEE - Voice Transcription Test")
    print("=" * 60)

    # Show available audio devices
    print("\nChecking audio devices...")
    list_audio_devices()

    # Show available models
    list_available_models()

    print("\nChoose a test to run:")
    print("  1. Fixed duration (5 seconds)")
    print("  2. Smart recording (auto-stops when you stop talking)")
    print("  3. Manual recording (press Enter to stop)")
    print("  q. Quit")

    while True:
        print()
        choice = input("Enter choice (1/2/3/q): ").strip().lower()

        if choice == '1':
            test_fixed_duration()
        elif choice == '2':
            test_smart_recording()
        elif choice == '3':
            test_manual_recording()
        elif choice == 'q':
            print("Goodbye!")
            break
        else:
            print("Invalid choice. Please enter 1, 2, 3, or q.")


if __name__ == "__main__":
    main()
