# Build Rayee Release DMG

Build the complete Rayee distribution package (DMG) with both the Swift app and bundled Python server.

## Steps

1. Run the release build script:
   ```bash
   ./build_release.sh
   ```

2. Wait for the build to complete (typically 3-5 minutes). The script will:
   - Build the Python server with PyInstaller (~600MB bundle)
   - Build the Swift app with Xcode (Release configuration)
   - Bundle the Python server into the app
   - Create a DMG disk image

3. Report the result:
   - If successful: Tell the user where Rayee.dmg is located and its size
   - If failed: Show the specific error from the build output

## Output

The final DMG will be at: `./Rayee.dmg`

## Prerequisites

The build script checks for these automatically:
- Xcode command line tools
- Python 3.11+ with virtual environment in `python/venv`
- PyInstaller (installed automatically if missing)

## Notes

- This is a full release build - it takes several minutes
- For quick testing, use `/build-app` instead (Swift only, no DMG)
- The DMG includes an Applications symlink for easy drag-and-drop install
