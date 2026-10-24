# Copies a course file into Ember's Documents/Import on the iPad (USB or Wi-Fi sync). Ember
# merges it the next time it opens or comes back to the front: subjects, topics, past papers.
#   python tools/push_courses.py out/import/courses-4-1.json
import asyncio
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
    raise SystemExit("iPad not reachable, or Ember is not installed.")


async def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__ or "usage: push_courses.py <file.json>")
    path = sys.argv[1]
    data = open(path, "rb").read()
    ha = await connect()
    try:
        await ha.makedirs("/Documents/Import")
    except Exception:
        pass
    target = "/Documents/Import/" + os.path.basename(path)
    await ha.set_file_contents(target, data)
    print(f"{len(data)} bytes -> {target}. Open Ember (or bring it to the front) to merge.")


asyncio.run(main())
