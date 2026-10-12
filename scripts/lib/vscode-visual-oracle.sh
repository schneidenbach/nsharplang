#!/usr/bin/env bash
set -euo pipefail

mode="${1:?mode is required}"
shift

case "$mode" in
    references)
        cli_dll="${1:?CLI DLL is required}"
        project="${2:?project is required}"
        file="${3:?file is required}"
        position="${4:?position is required}"
        exec dotnet "$cli_dll" query references --project "$project" --file "$file" --pos "$position" --json --no-daemon
        ;;
    diagnostics|tokens)
        exec python3 - "$mode" "$@" 3<&0 <<'PY'
import json
import pathlib
import re
import subprocess
import sys

mode, *args = sys.argv[1:]

def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)

if mode == "diagnostics":
    cli_dll, workspace = args
    workspace = pathlib.Path(workspace).resolve()
    request = json.load(__import__("os").fdopen(3))
    files = sorted(set(request["files"]))
    projects = set()
    for relative in files:
        current = (workspace / relative).parent
        found = False
        while current == workspace or workspace in current.parents:
            if (current / "project.yml").is_file():
                projects.add(current)
                found = True
                break
            if current == workspace:
                break
            current = current.parent
        if not found:
            projects.add(workspace)
    expected = []
    for project in sorted(projects):
        run = subprocess.run(
            ["dotnet", cli_dll, "check", "--project", str(project), "--json", "--no-daemon"],
            cwd=workspace, capture_output=True, text=True, timeout=120,
            env={**__import__("os").environ, "NLC_NO_DAEMON": "1"})
        if run.returncode not in (0, 1):
            fail(f"nlc check failed for {project}: {run.stderr}\n{run.stdout}")
        try:
            report = json.loads(run.stdout)
        except json.JSONDecodeError as error:
            fail(f"nlc check returned invalid JSON for {project}: {error}\n{run.stdout}")
        for item in report.get("results", []):
            absolute = (project / item["file"]).resolve()
            expected.append("|".join((
                str(item.get("code", "")), str(item.get("severity", "")).lower(),
                absolute.relative_to(workspace).as_posix(), str(item["line"]),
                str(item["column"]), str(item["length"]), item["message"])))
    print(json.dumps({"files": files, "census": sorted(expected)}))
elif mode == "tokens":
    workspace, old_symbol, new_symbol = args
    workspace = pathlib.Path(workspace).resolve()
    identifiers = re.compile(r"//[^\n]*|/\*.*?\*/|\"\"\"[\s\S]*?\"\"\"|\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|([A-Za-z_][A-Za-z0-9_]*)", re.S)
    counts = {}
    for file in sorted(workspace.rglob("*.nl")):
        if any(part in {".git", "node_modules", "bin", "obj"} for part in file.relative_to(workspace).parts):
            continue
        source = file.read_text(encoding="utf-8")
        names = [match.group(1) for match in identifiers.finditer(source) if match.group(1)]
        old_count, new_count = names.count(old_symbol), names.count(new_symbol)
        if old_count or new_count:
            counts[file.relative_to(workspace).as_posix()] = {"old": old_count, "new": new_count}
    print(json.dumps(counts))
else:
    fail(f"unsupported oracle mode: {mode}")
PY
        ;;
    *)
        echo "Unsupported visual oracle mode: $mode" >&2
        exit 2
        ;;
esac
