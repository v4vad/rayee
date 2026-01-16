#!/usr/bin/env python3
"""
Rayee Server Entry Point

Run this script to start the transcription server:

    cd python
    source venv/bin/activate
    python run_server.py

The server will run on http://localhost:8765

Press Ctrl+C to stop the server.
"""

from rayee.server import run_server, HOST, PORT

if __name__ == "__main__":
    print(f"\nStarting Rayee Transcription Server...")
    print(f"Server will be available at: http://{HOST}:{PORT}")
    print("Press Ctrl+C to stop.\n")

    run_server()
