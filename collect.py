#!/usr/bin/env python3
"""Vikunja collector for the Omarchy bar/panel plugin.

Fetches projects + open tasks from a self-hosted Vikunja instance and
writes a JSON state record for the QML shell to render.

Reads config from ~/.config/omarchy-vikunja/config.json (0600):
  {
    "url": "http://vikunja.example.com:3450",
    "token": "<API token>"
  }

Falls back to env vars VIKUNJA_URL / VIKUNJA_TOKEN.

Usage:
  collect.py --write            fetch and write the state record
  collect.py                    fetch and print to stdout (dry run)
  collect.py --clear            remove the state record
  collect.py --toggle <task_id> toggle a task's done state, then refresh

Auth: a long-lived API token (Vikunja: Settings > API Tokens / "Generate
a new API token", scope: read+write for tasks and projects). No password
login, no expiry handling.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import date, datetime
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "omarchy-vikunja" / "config.json"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) \
    / "omarchy" / "plugins" / "vikunja"
STATE_PATH = STATE_DIR / "tasks.json"
HTTP_TIMEOUT = 15


def load_config():
    cfg = {}
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            cfg = json.load(f)
    url = cfg.get("url") or os.environ.get("VIKUNJA_URL")
    token = cfg.get("token") or os.environ.get("VIKUNJA_TOKEN")
    if not url or not token:
        print("ERROR: no Vikunja url/token in %s or env (VIKUNJA_URL/VIKUNJA_TOKEN)"
              % CONFIG_PATH, file=sys.stderr)
        sys.exit(2)
    return url.rstrip("/"), token


def api(base, token, method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(base + "/api/v1" + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    if data:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
        return json.load(resp)


def parse_due(task):
    """Vikunja due dates can be date-only or full ISO datetimes."""
    d = task.get("due_date") or ""
    if not d:
        return None
    try:
        due = datetime.fromisoformat(d.replace("Z", "+00:00")).date()
    except ValueError:
        return None
    # Vikunja uses 0001-01-01 as its zero value for "no due date".
    if due.year <= 1:
        return None
    return due


def fetch_state(base, token):
    today = date.today()
    projects = [p for p in api(base, token, "GET", "/projects") if p.get("id", 0) > 0]

    # NOTE: fetch tasks per project. The /tasks/all endpoint is convenient but
    # rejects project-scoped API tokens on some Vikunja versions, and we need
    # the project list anyway, so one request per project is the robust path.
    proj_out = []
    total = 0
    overdue = 0
    due_today = 0
    for pr in projects:
        data = api(base, token, "GET", "/projects/%d/tasks" % pr["id"])
        if isinstance(data, dict):
            data = data.get("tasks", [])
        items = []
        for t in data:
            if t.get("done"):
                continue
            due = parse_due(t)
            is_overdue = bool(due and due < today)
            is_today = bool(due and due == today)
            if is_overdue:
                overdue += 1
            if is_today:
                due_today += 1
            items.append({
                "id": t["id"],
                "title": t.get("title", ""),
                "due": t.get("due_date") if due else None,
                "overdue": is_overdue,
                "due_today": is_today,
            })
        total += len(items)
        if items:
            proj_out.append({
                "id": pr["id"],
                "title": pr.get("title", ""),
                "tasks": items,
            })

    return {
        "updated": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "total": total,
        "overdue": overdue,
        "due_today": due_today,
        "projects": proj_out,
    }


def toggle_task(base, token, task_id, target_done):
    # On Vikunja 2.x, task updates are POST /tasks/{id} with a partial body.
    # Scoped API tokens cannot GET a single task, so the caller passes the
    # target state from the cached panel data.
    payload = {"done": bool(target_done)}
    updated = api(base, token, "POST", "/tasks/%d" % task_id, payload)
    if updated.get("done") != payload["done"]:
        print("ERROR: toggle not confirmed for task %d" % task_id, file=sys.stderr)
        sys.exit(3)


def create_task(base, token, title, project_id, due=None):
    # Create = PUT /projects/{id}/tasks on Vikunja 2.x.
    payload = {"title": title}
    if due:
        payload["due_date"] = due
    created = api(base, token, "PUT", "/projects/%d/tasks" % project_id, payload)
    if not created.get("id"):
        print("ERROR: task not confirmed created", file=sys.stderr)
        sys.exit(3)
    return created


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="write the state record")
    ap.add_argument("--clear", action="store_true", help="remove the state record")
    ap.add_argument("--toggle", type=int, metavar="TASK_ID",
                    help="set a task done (with --done) or pending (default), then refresh")
    ap.add_argument("--done", action="store_true",
                    help="with --toggle: mark done instead of pending")
    ap.add_argument("--create", metavar="TITLE",
                    help="create a task (requires --project)")
    ap.add_argument("--project", type=int, metavar="PROJECT_ID",
                    help="with --create: project to add the task to")
    ap.add_argument("--due", metavar="YYYY-MM-DD",
                    help="with --create: due date")
    args = ap.parse_args()

    if args.clear:
        STATE_PATH.unlink(missing_ok=True)
        print("cleared", STATE_PATH)
        return

    base, token = load_config()

    if args.toggle:
        toggle_task(base, token, args.toggle, args.done)

    if args.create:
        if not args.project:
            print("ERROR: --create requires --project PROJECT_ID", file=sys.stderr)
            sys.exit(2)
        create_task(base, token, args.create, args.project, args.due)

    state = fetch_state(base, token)
    text = json.dumps(state, indent=2)

    if args.write:
        STATE_DIR.mkdir(parents=True,exist_ok=True)
        tmp = STATE_PATH.with_suffix(".tmp")
        tmp.write_text(text)
        tmp.replace(STATE_PATH)
        print("wrote %s (%d open tasks)" % (STATE_PATH, state["total"]))
    else:
        print(text)


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        print("ERROR: HTTP %d from Vikunja" % e.code, file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print("ERROR: cannot reach Vikunja: %s" % e.reason, file=sys.stderr)
        sys.exit(1)