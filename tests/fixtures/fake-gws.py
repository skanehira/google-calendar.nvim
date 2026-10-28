#!/usr/bin/env python3
import json
import os
import random
import string
import sys
import tempfile
import uuid
from datetime import datetime


def emit_json(value):
    print(json.dumps(value, ensure_ascii=False))


def emit_error(code, message, reason, exit_code=1):
    emit_json({"error": {"code": code, "message": message, "reason": reason}})
    sys.exit(exit_code)


def state_path():
    return os.environ.get("FAKE_GWS_STATE") or os.path.join(
        tempfile.gettempdir(), "google-calendar-fake-gws-state.json"
    )


def load_state():
    path = state_path()
    if not os.path.exists(path):
        return {"items": []}
    with open(path, encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, dict) or not isinstance(data.get("items"), list):
        return {"items": []}
    return data


def save_state(state):
    path = state_path()
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "w", encoding="utf-8") as file:
        json.dump(state, file, ensure_ascii=False)


def record_call(argv):
    path = os.environ.get("FAKE_GWS_CALL_LOG")
    if not path:
        return
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(path, "a", encoding="utf-8") as file:
        file.write(json.dumps({"argv": argv, "cwd": os.getcwd()}, ensure_ascii=False) + "\n")


def parse_flags(argv):
    flags = {}
    index = 0
    while index < len(argv):
        argument = argv[index]
        if argument.startswith("--"):
            name = argument[2:]
            if index + 1 < len(argv) and not argv[index + 1].startswith("--"):
                flags[name] = argv[index + 1]
                index += 2
            else:
                flags[name] = True
                index += 1
        else:
            index += 1
    return flags


def parse_json_flag(flags, name):
    value = flags.get(name)
    if not isinstance(value, str):
        emit_error(400, "Missing --" + name, "invalidArgument")
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        emit_error(400, "Invalid JSON for --" + name, "invalidArgument")


def parse_rfc3339(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def filter_events(items, params):
    time_min = params.get("timeMin")
    time_max = params.get("timeMax")
    if not time_min and not time_max:
        return items

    min_datetime = parse_rfc3339(time_min) if time_min else None
    max_datetime = parse_rfc3339(time_max) if time_max else None
    min_date = time_min[:10] if time_min else None
    max_date = time_max[:10] if time_max else None

    filtered = []
    for item in items:
        start = item.get("start", {})
        end = item.get("end", {})
        if "dateTime" in start:
            start_datetime = parse_rfc3339(start["dateTime"])
            end_datetime = parse_rfc3339(end["dateTime"]) if "dateTime" in end else start_datetime
            if min_datetime is not None and end_datetime <= min_datetime:
                continue
            if max_datetime is not None and start_datetime >= max_datetime:
                continue
            filtered.append(item)
        elif "date" in start:
            start_date = start["date"]
            end_date = end.get("date", start_date)
            if max_date is not None and start_date >= max_date:
                continue
            if min_date is not None and end_date <= min_date:
                continue
            filtered.append(item)
        else:
            filtered.append(item)

    return filtered


def generate_id():
    return "evt-" + uuid.uuid4().hex[:12]


def generate_meet_link():
    letters = string.ascii_lowercase
    code = (
        "".join(random.choice(letters) for _ in range(3))
        + "-"
        + "".join(random.choice(letters) for _ in range(4))
        + "-"
        + "".join(random.choice(letters) for _ in range(3))
    )
    return "https://meet.google.com/" + code


def find_event(event_id):
    for item in load_state().get("items", []):
        if item.get("id") == event_id:
            return item
    return None


def list_events(flags):
    params = parse_json_flag(flags, "params")
    items = filter_events(load_state().get("items", []), params)

    try:
        page_size = int(os.environ.get("FAKE_GWS_PAGE_SIZE", "2500"))
    except ValueError:
        page_size = 2500
    if page_size < 1:
        page_size = 2500

    token = params.get("pageToken")
    try:
        offset = int(token) if token is not None else 0
    except (TypeError, ValueError):
        offset = 0

    page = items[offset : offset + page_size]
    body = {"items": page}
    next_offset = offset + page_size
    if next_offset < len(items):
        body["nextPageToken"] = str(next_offset)
    emit_json(body)


def insert_timed_event(flags):
    summary = flags.get("summary")
    start = flags.get("start")
    end = flags.get("end")
    if not isinstance(summary, str) or not isinstance(start, str) or not isinstance(end, str):
        emit_error(400, "Missing --summary/--start/--end", "invalidArgument")

    event = {
        "id": generate_id(),
        "summary": summary,
        "start": {"dateTime": start},
        "end": {"dateTime": end},
    }
    if flags.get("meet") is True:
        event["hangoutLink"] = generate_meet_link()

    state = load_state()
    state.setdefault("items", []).append(event)
    save_state(state)
    emit_json(event)


def insert_event(flags):
    body = parse_json_flag(flags, "json")
    if not isinstance(body, dict):
        emit_error(400, "Invalid event body", "invalidArgument")

    event = dict(body)
    event.setdefault("id", generate_id())
    state = load_state()
    state.setdefault("items", []).append(event)
    save_state(state)
    emit_json(event)


def get_event(flags):
    params = parse_json_flag(flags, "params")
    event = find_event(params.get("eventId"))
    if event is None:
        emit_error(404, "Not Found", "notFound")
    emit_json(event)


def update_event(flags):
    params = parse_json_flag(flags, "params")
    body = parse_json_flag(flags, "json")
    event_id = params.get("eventId")
    if not isinstance(body, dict):
        emit_error(400, "Invalid event body", "invalidArgument")

    state = load_state()
    items = state.get("items", [])
    for index, item in enumerate(items):
        if item.get("id") == event_id:
            updated = dict(body)
            updated["id"] = event_id
            items[index] = updated
            save_state(state)
            emit_json(updated)
            return
    emit_error(404, "Not Found", "notFound")


def delete_event(flags):
    params = parse_json_flag(flags, "params")
    event_id = params.get("eventId")
    state = load_state()
    items = state.get("items", [])
    for index, item in enumerate(items):
        if item.get("id") == event_id:
            del items[index]
            save_state(state)

            with open("download.html", "w", encoding="utf-8"):
                pass

            log = os.environ.get("FAKE_GWS_CWD_LOG")
            if log:
                parent = os.path.dirname(log)
                if parent:
                    os.makedirs(parent, exist_ok=True)
                with open(log, "a", encoding="utf-8") as file:
                    file.write(os.getcwd() + "\n")

            emit_json({"status": "success"})
            return
    emit_error(404, "Not Found", "notFound")


def list_calendars():
    emit_json(
        {
            "items": [
                {
                    "id": "primary",
                    "summary": "primary",
                    "timeZone": "Asia/Tokyo",
                    "backgroundColor": "#039be5",
                }
            ]
        }
    )


def use_error_fixture():
    fixture = os.environ.get("FAKE_GWS_ERROR_FIXTURE")
    if not fixture:
        return False
    try:
        with open(fixture, encoding="utf-8") as file:
            body = json.load(file)
    except OSError:
        emit_error(500, "Error fixture not found: " + fixture, "internalError")
    emit_json(body)
    reason = body.get("error", {}).get("reason")
    sys.exit(2 if reason == "authError" else 1)


def main():
    sys.stderr.write("Using keyring backend: fake\n")
    argv = sys.argv[1:]
    record_call(argv)
    use_error_fixture()

    if not argv or argv[0] != "calendar":
        emit_error(400, "Unsupported command", "invalidArgument")

    rest = argv[1:]
    if not rest:
        emit_error(400, "Missing command", "invalidArgument")

    command = rest[0]
    if command == "calendarList":
        if len(rest) < 2 or rest[1] != "list":
            emit_error(400, "Unsupported calendarList command", "invalidArgument")
        list_calendars()
        return

    if command == "+insert":
        insert_timed_event(parse_flags(rest[1:]))
        return

    if command != "events" or len(rest) < 2:
        emit_error(400, "Unsupported command", "invalidArgument")

    action = rest[1]
    flags = parse_flags(rest[2:])
    if action == "list":
        list_events(flags)
    elif action == "insert":
        insert_event(flags)
    elif action == "get":
        get_event(flags)
    elif action == "update":
        update_event(flags)
    elif action == "delete":
        delete_event(flags)
    else:
        emit_error(400, "Unsupported events command: " + action, "invalidArgument")


if __name__ == "__main__":
    main()
