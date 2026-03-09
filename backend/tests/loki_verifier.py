
import pytest
import sys
import os
from datetime import datetime

def run_loki_verification(target_tests=None):
    """
    Runs the Loki Mode verification suite.
    """
    print(f"🚀 Starting Loki Mode Verification at {datetime.now()}")
    
    if not target_tests:
        target_tests = ["backend/tests/test_messaging_loki_full_flow.py"]
    
    print(f"🎯 Targets: {target_tests}")
    
    # Run pytest
    # -v: verbose
    # -s: show stdout/stderr
    exit_code = pytest.main(["-v", "-s"] + target_tests)
    
    if exit_code == 0:
        print("\n✅ VERIFICATION SUCCESS: All systems go!")
    else:
        print(f"\n❌ VERIFICATION FAILED: Exit Code {exit_code}")
        
    return exit_code

if __name__ == "__main__":
    # Ensure we are in the project root or adjust path
    # Assuming run from C:\Projects\almudeer
    # We might need to add current dir to sys.path
    sys.path.append(os.getcwd())
    
    # Allow passing specific test files via args
    targets = sys.argv[1:] if len(sys.argv) > 1 else None
    
    sys.exit(run_loki_verification(targets))
