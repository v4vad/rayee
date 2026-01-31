---
name: check-health
description: Check if the Rayee server is running and healthy
disable-model-invocation: true
allowed-tools: Bash(curl *)
---

# Check Rayee Server Health

Quick check to see if the Python server is running properly.

## Steps

1. Check the health endpoint:
   ```bash
   curl -s http://localhost:8765/health
   ```

2. Check the current status:
   ```bash
   curl -s http://localhost:8765/status
   ```

3. Report results to the user:
   - If both work: "Server is running and ready"
   - If health fails: "Server is not running - use /run-server to start it"
   - If status shows busy: "Server is currently recording or transcribing"
