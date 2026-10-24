# Reads `xcrun simctl list devices available -j` on stdin and prints the UDID of a simulator.
# usage: python3 .github/pick_sim.py iPad|iPhone < sims.json
# Prefers an iOS 18 runtime (the iPad runs iPadOS 18.7), then the newest one. For iPad it
# prefers the plain iPad (closest to an iPad 9th gen); for iPhone the smallest screen.
import json
import re
import sys

family = sys.argv[1] if len(sys.argv) > 1 else "iPad"
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(x) for x in re.findall(r"\d+", runtime.split("iOS")[-1]))
    is18 = 1 if version[:1] == (18,) else 0
    for dev in devs:
        name = dev["name"]
        if not name.startswith(family) or not dev.get("isAvailable", True):
            continue
        if family == "iPad":
            kind = 2 if re.match(r"iPad \(", name) else (1 if "Air" in name else 0)
        else:
            kind = 2 if "SE" in name else (1 if re.fullmatch(r"iPhone \d+", name) else 0)
        score = (is18, kind, version)
        if best is None or score > best[0]:
            best = (score, dev["udid"], name, runtime)

if best is None:
    sys.exit(f"no {family} simulator found")
sys.stderr.write(f"Using {best[2]} on {best[3]}\n")
print(best[1])
