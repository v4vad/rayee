---
name: build-app
description: Build the Rayee macOS Swift app
disable-model-invocation: true
allowed-tools: Bash(xcodebuild *)
---

# Build Rayee App

Build the macOS menu bar app from source.

## Steps

1. Run the Xcode build command:
   ```bash
   xcodebuild -project swift/Rayee/Rayee.xcodeproj -scheme Rayee build
   ```

2. Wait for the build to complete (may take a minute)

3. Report the result:
   - If successful: Tell the user where the app is located
   - If failed: Show the specific errors with file names and line numbers

## Notes

- The build output goes to `~/Library/Developer/Xcode/DerivedData/`
- You can also open `swift/Rayee/Rayee.xcodeproj` in Xcode to build from there
