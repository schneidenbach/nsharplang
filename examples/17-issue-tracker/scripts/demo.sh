#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"
PORT="${ISSUE_TRACKER_PORT:-5167}"
HOLD_OPEN="${ISSUE_TRACKER_HOLD:-1}"
LOG_DIR="$ROOT/.demo-artifacts"
SERVER_LOG="$LOG_DIR/backend.log"
SERVER_PID=""

mkdir -p "$LOG_DIR"

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

step() {
  printf '\n\033[1;36m==> %s\033[0m\n' "$1"
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

wait_for_backend() {
  local url="http://localhost:$PORT/api/health"
  for _ in {1..60}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "Backend did not become healthy at $url" >&2
  echo "--- backend log ---" >&2
  tail -80 "$SERVER_LOG" >&2 || true
  exit 1
}

step "Checking prerequisites"
need npm
need dotnet
need curl

NLC=("$ROOT/scripts/nlc-local.sh")

step "Installing npm dependencies"
cd "$ROOT"
npm install
npm --prefix "$FRONTEND" install

step "Building React frontend into backend/wwwroot"
npm --prefix "$FRONTEND" run build

step "Restoring and building N# ASP.NET backend"
cd "$BACKEND"
"${NLC[@]}" restore
dotnet build IssueTracker.csproj

step "Running N# backend tests"
"${NLC[@]}" test

step "Starting ASP.NET backend on http://localhost:$PORT"
ASPNETCORE_URLS="http://localhost:$PORT" dotnet run --project IssueTracker.csproj --no-build --urls "http://localhost:$PORT" >"$SERVER_LOG" 2>&1 &
SERVER_PID="$!"
wait_for_backend

step "Exercising API: health, list, create, list"
curl -fsS "http://localhost:$PORT/api/health" | tee "$LOG_DIR/health.txt"
printf '\n'
curl -fsS "http://localhost:$PORT/api/issues" | tee "$LOG_DIR/issues-before.json"
printf '\n'
curl -fsS -X POST "http://localhost:$PORT/api/issues" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Demo issue from scripts/demo.sh","description":"Created through the N# ASP.NET API during the flagship demo.","priority":"High","tags":["cli","aspnet","nsharp"]}' \
  | tee "$LOG_DIR/create-response.json"
printf '\n'
curl -fsS "http://localhost:$PORT/api/issues" | tee "$LOG_DIR/issues-after.json"
printf '\n'

step "Asserting API JSON contract"
node - "$LOG_DIR/create-response.json" "$LOG_DIR/issues-after.json" <<'NODE'
const fs = require('fs');
const [createdPath, issuesPath] = process.argv.slice(2);
const created = JSON.parse(fs.readFileSync(createdPath, 'utf8'));
const issues = JSON.parse(fs.readFileSync(issuesPath, 'utf8'));

if (created.id !== 1 || created.title !== 'Demo issue from scripts/demo.sh') {
  throw new Error('create-response.json does not contain the created issue shape');
}
if (created.status?.type !== 'Open' || created.priority !== 'High') {
  throw new Error('create-response.json does not contain the expected status/priority contract');
}
if (!Array.isArray(created.tags) || !created.tags.includes('nsharp')) {
  throw new Error('create-response.json does not contain expected tags');
}
if (!Array.isArray(issues) || issues.length !== 1 || issues[0].id !== created.id || issues[0].status?.type !== 'Open') {
  throw new Error('issues-after.json does not contain the created issue contract');
}
console.log('API smoke assertions passed: health/list/create/list JSON contract is intact.');
NODE

step "Demo is live"
echo "Open http://localhost:$PORT in a browser."
echo "Evidence logs written to $LOG_DIR"

if [[ "$HOLD_OPEN" == "0" ]]; then
  echo "ISSUE_TRACKER_HOLD=0 set; stopping after API proof path."
  exit 0
fi

echo "Press Ctrl-C to stop, or leave this script running while you capture screenshots."

wait "$SERVER_PID"
