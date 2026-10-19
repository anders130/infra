import datetime
import json
import os
import sys

import caldav
from icalendar import Calendar, Event

NEXTCLOUD_URL = os.environ["NEXTCLOUD_URL"]
USER = os.environ["NEXTCLOUD_USER"]
PASSWORD = open(os.environ["NEXTCLOUD_APP_PASSWORD_FILE"]).read().strip()
SOURCE_CALENDARS = json.loads(open(os.environ["SOURCE_CALENDARS_FILE"]).read())
DEST_CALENDAR_NAME = os.environ["DEST_CALENDAR_NAME"]
WINDOW_DAYS = int(os.environ.get("WINDOW_DAYS", "180"))

CONTENT_FIELDS = ("summary", "location", "description")


def resolve_field(vevent, field, policy):
    if policy == "omit":
        return None
    raw = vevent.get(field)
    if not raw:
        return None
    if policy == "passthrough":
        return str(raw)
    return policy


client = caldav.DAVClient(url=f"{NEXTCLOUD_URL}/remote.php/dav/", username=USER, password=PASSWORD)
principal = client.principal()
calendars = {c.name: c for c in principal.calendars()}

dest = calendars.get(DEST_CALENDAR_NAME)
if dest is None:
    print(
        f"Destination calendar '{DEST_CALENDAR_NAME}' not found. "
        "Create it once in the Nextcloud UI and share it with family, then re-run.",
        file=sys.stderr,
    )
    sys.exit(1)

for event in dest.events():
    event.delete()

now = datetime.datetime.now(datetime.timezone.utc)
window_end = now + datetime.timedelta(days=WINDOW_DAYS)

synced = 0
for cal_name, fields in SOURCE_CALENDARS.items():
    src = calendars.get(cal_name)
    if src is None:
        print(f"Source calendar '{cal_name}' not found, skipping", file=sys.stderr)
        continue

    for src_event in src.search(start=now, end=window_end, event=True, expand=False):
        for vevent in src_event.icalendar_instance.walk("VEVENT"):
            uid = str(vevent.get("uid"))
            recurrence_id = vevent.get("recurrence-id")
            busy_uid = f"busy-{cal_name}-{uid}" + (f"-{recurrence_id.dt.isoformat()}" if recurrence_id else "")

            busy_cal = Calendar()
            busy_cal.add("prodid", "-//nextcloud-busy-sync//EN")
            busy_cal.add("version", "2.0")

            busy_event = Event()
            busy_event.add("uid", busy_uid)

            for field in CONTENT_FIELDS:
                value = resolve_field(vevent, field, fields.get(field, "omit"))
                if value is not None:
                    busy_event.add(field, value)

            busy_event.add("dtstart", vevent.get("dtstart").dt)
            if vevent.get("dtend"):
                busy_event.add("dtend", vevent.get("dtend").dt)
            elif vevent.get("duration"):
                busy_event.add("duration", vevent.get("duration").dt)
            if vevent.get("rrule"):
                busy_event.add("rrule", vevent.get("rrule"))
            if vevent.get("exdate"):
                busy_event.add("exdate", vevent.get("exdate"))
            if recurrence_id:
                busy_event.add("recurrence-id", recurrence_id.dt)
            busy_event.add("transp", "OPAQUE")
            busy_event.add("status", "CONFIRMED")

            busy_cal.add_component(busy_event)
            dest.save_event(busy_cal.to_ical().decode())
            synced += 1

print(f"Synced {synced} busy block(s) from {list(SOURCE_CALENDARS)} into '{DEST_CALENDAR_NAME}'.")
