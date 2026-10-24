# Copies Ember's Lock Lab log (and, later, its data files) from the iPad to the PC over USB.
# Read-only on the iPad.
#   python tools/pull_lab.py                 -> D:\ipad\ember\out\device\<date-time>
#   python tools/pull_lab.py "D:\somewhere"
import asyncio
import datetime
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService

BUNDLE = "app.ember.focus.89MB4XXLYZ"


async def connect():
    for _ in range(40):
        try:
            lockdown = await create_using_usbmux()
            return await HouseArrestService.create(lockdown, BUNDLE, documents_only=True)
        except Exception as e:
            print("waiting for iPad:", type(e).__name__, flush=True)
            await asyncio.sleep(3)
    raise SystemExit("iPad not reachable.")


async def main():
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H%M")
    target = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "out", "device", stamp)
    os.makedirs(target, exist_ok=True)
    ha = await connect()
    copied = 0
    for name in await ha.listdir("/Documents"):
        if not name.endswith(".json"):
            continue
        data = await ha.get_file_contents("/Documents/" + name)
        with open(os.path.join(target, name), "wb") as f:
            f.write(data)
        copied += 1
        print(f"{name}: {len(data)} bytes")
    print(f"{copied} files copied to {os.path.abspath(target)}")


asyncio.run(main())
