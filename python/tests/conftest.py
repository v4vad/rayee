"""
Pytest configuration for Rayee tests.

This file:
1. Adds the python directory to PYTHONPATH so imports work
2. Provides shared fixtures for tests
"""

import sys
from pathlib import Path

# Add the python directory to the path so rayee module can be imported
python_dir = Path(__file__).parent.parent
sys.path.insert(0, str(python_dir))
