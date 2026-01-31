# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller Spec File for Rayee Server

This file tells PyInstaller how to bundle the Python transcription server
into a standalone executable that can run without Python being installed.

To build:
    cd python
    source venv/bin/activate
    pip install pyinstaller
    pyinstaller RayeeServer.spec

This creates: dist/RayeeServer/RayeeServer (the executable)
"""

import sys
from PyInstaller.utils.hooks import collect_data_files, collect_submodules

# Name of the output executable
APP_NAME = 'RayeeServer'

# Entry point script
ENTRY_POINT = 'run_server.py'

# Collect all hidden imports that PyInstaller might miss
# These are imports that happen dynamically or inside packages
hidden_imports = [
    # FastAPI and web server
    'uvicorn',
    'uvicorn.logging',
    'uvicorn.loops',
    'uvicorn.loops.auto',
    'uvicorn.protocols',
    'uvicorn.protocols.http',
    'uvicorn.protocols.http.auto',
    'uvicorn.protocols.websockets',
    'uvicorn.protocols.websockets.auto',
    'uvicorn.lifespan',
    'uvicorn.lifespan.on',
    'fastapi',
    'starlette',
    'pydantic',

    # Audio processing
    'sounddevice',
    'numpy',
    'scipy',
    'scipy.io',
    'scipy.io.wavfile',

    # PyTorch (for VAD)
    'torch',
    'torchaudio',

    # Faster Whisper
    'faster_whisper',
    'ctranslate2',

    # Our application package
    'rayee',
    'rayee.server',
    'rayee.transcribe',
    'rayee.vad',
    'rayee.audio',
    'rayee.models',
    'rayee.vocabulary',
]

# Collect all submodules for packages that have many internal imports
hidden_imports += collect_submodules('uvicorn')
hidden_imports += collect_submodules('fastapi')
hidden_imports += collect_submodules('starlette')
hidden_imports += collect_submodules('pydantic')
hidden_imports += collect_submodules('faster_whisper')
hidden_imports += collect_submodules('ctranslate2')
hidden_imports += collect_submodules('scipy')

# Collect data files that packages need at runtime
datas = []

# Silero VAD model files
try:
    datas += collect_data_files('torch')
except Exception:
    pass

# Faster Whisper assets
try:
    datas += collect_data_files('faster_whisper')
except Exception:
    pass

# CTranslate2 runtime files
try:
    datas += collect_data_files('ctranslate2')
except Exception:
    pass

# Analysis configuration
a = Analysis(
    [ENTRY_POINT],
    pathex=[],
    binaries=[],
    datas=datas,
    hiddenimports=hidden_imports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Exclude packages we don't need to reduce size
        'tkinter',
        'matplotlib',
        'PIL',
        'pandas',
        # Note: scipy is now REQUIRED for reading WAV files from Swift
        'IPython',
        'jupyter',
        'notebook',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=None,
    noarchive=False,
)

# Create the PYZ (compressed Python archive)
pyz = PYZ(a.pure, a.zipped_data, cipher=None)

# Create the executable
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name=APP_NAME,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,  # Don't compress - can cause issues on macOS
    console=True,  # Keep console for debugging output
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch='arm64',  # Apple Silicon (M1/M2/M3)
    codesign_identity=None,
    entitlements_file=None,
)

# Create the collection (folder with executable and all dependencies)
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name=APP_NAME,
)
