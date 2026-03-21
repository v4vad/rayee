#!/usr/bin/env python3
"""
Rayee Server Entry Point

Run this script to start the transcription server:

    cd python
    source venv/bin/activate
    python run_server.py

The server communicates via a Unix domain socket at ~/.rayee/server.sock
(avoids interfering with VPNs like Cloudflare WARP).

For development with TCP instead:
    python run_server.py --tcp

Press Ctrl+C to stop the server.
"""

import multiprocessing
import sys

# CRITICAL: This must be called at the very start for PyInstaller bundled apps
# It allows multiprocessing to work correctly in frozen (bundled) applications
# Without this, spawned processes will fail or hang on macOS
if __name__ == "__main__":
    multiprocessing.freeze_support()

    # On macOS, use 'spawn' method for multiprocessing (required for frozen apps)
    # This must be set before any other multiprocessing code runs
    if sys.platform == "darwin":
        try:
            multiprocessing.set_start_method("spawn", force=True)
        except RuntimeError:
            pass  # Already set

    from rayee.startup import SOCKET_PATH, run_server

    use_tcp = "--tcp" in sys.argv

    print("\nStarting Rayee Transcription Server...")
    if use_tcp:
        print("Mode: TCP (http://127.0.0.1:8765)")
    else:
        print(f"Mode: Unix socket ({SOCKET_PATH})")
    print("Press Ctrl+C to stop.\n")

    run_server(use_socket=not use_tcp)
