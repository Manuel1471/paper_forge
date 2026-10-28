#!/usr/bin/env python3
"""Wait cheaply for an existing campaign, then build its final report."""
import os
import pathlib
import subprocess
import sys
import time

output = pathlib.Path(sys.argv[1]).resolve()
pid = int(sys.argv[2])
while not (output / 'complete.json').exists():
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        break
    time.sleep(60)
subprocess.run(
    [sys.executable, str(pathlib.Path(__file__).with_name('summarize_campaign.py')), str(output)],
    check=True,
)
