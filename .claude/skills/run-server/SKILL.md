---
name: run-server
description: Start the Rayee Python transcription server
disable-model-invocation: true
allowed-tools: Bash(source *), Bash(python *)
---

# Start Rayee Server

Start the Python transcription server that powers Rayee.

## Steps

1. Navigate to the python directory
2. Activate the virtual environment: `source venv/bin/activate`
3. Start the server: `python run_server.py`

## What to expect

- Server starts on `http://localhost:8765`
- You'll see "Rayee Transcription Server Started" when ready
- The server must stay running while using the app

## If something goes wrong

- Check if port 8765 is already in use: `lsof -i :8765`
- Make sure dependencies are installed: `pip install -r requirements.txt`
