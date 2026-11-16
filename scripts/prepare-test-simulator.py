"""Create an isolated device using an installed runtime, not OS=latest.

Runner images sometimes contain a newer, unavailable runtime which causes
xcodebuild's name/OS=latest destination lookup to reject otherwise valid devices.
"""
import json
import subprocess
import sys


def simctl(*args):
    return subprocess.check_output(["xcrun", "simctl", *args], text=True)


runtimes = [r for r in json.loads(simctl("list", "runtimes", "--json"))["runtimes"]
            if r.get("isAvailable") and r["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
if not runtimes:
    sys.exit("No available iOS runtime. Download the platform first.")
runtime = max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))
types = json.loads(simctl("list", "devicetypes", "--json"))["devicetypes"]
device = next(d for d in types if d["name"] == sys.argv[1])
identifier = simctl("create", "Wield Review", device["identifier"], runtime["identifier"]).strip()
print("TEST_SIMULATOR_ID=" + identifier)
