#!/usr/bin/env bash
# Two-phase device test: the install registration survives a process
# kill. Phase 1 launches the example app against a mock API that answers 503,
# so the SDK persists .adto_install.json as failed and the process is then
# force-stopped. Phase 2 relaunches against an API that accepts, and the SDK
# must retry with the SAME install_attempt_id and record the install as
# tracked. Needs one booted Android emulator or device (adb) and Flutter.
#
#   tool/device_restart_test.sh [port]
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${1:-8799}"
PKG=com.example.example
MOCK="http://127.0.0.1:$PORT"

dart run tool/mock_install_server.dart "$PORT" > "${TMPDIR:-/tmp}/adto-mock.log" 2>&1 &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do curl -sf "$MOCK/_mock/installs" > /dev/null && break; sleep 0.5; done

# The emulator reaches the host as 10.0.2.2; adb reverse makes the same
# address work on a USB device too.
adb reverse "tcp:$PORT" "tcp:$PORT" > /dev/null
(
  cd example
  flutter build apk --debug \
    --dart-define=ADTO_API_KEY=adto_pub_00000000000000000000000000000000 \
    --dart-define=ADTO_BASE_URL="http://127.0.0.1:$PORT"
)
adb install -r example/build/app/outputs/flutter-apk/app-debug.apk > /dev/null
adb shell pm clear "$PKG" > /dev/null   # a fresh install's state

installs() { curl -sf "$MOCK/_mock/installs"; }
count() { installs | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
wait_for() { # wait_for N: until at least N install POSTs arrived
  for _ in $(seq 1 120); do [ "$(count)" -ge "$1" ] && return 0; sleep 1; done
  echo "FAIL: expected $1 install POSTs, got $(count)"; exit 1
}
state() { adb exec-out run-as "$PKG" sh -c 'cat $(find . -name .adto_install.json | head -1)'; }

echo "Phase 1: the API is down"
adb shell am start -n "$PKG/.MainActivity" > /dev/null
wait_for 2   # the first launch tries twice in-process
sleep 3      # let markFailed write the sentinel
PHASE1="$(state)"
echo "  sentinel: $PHASE1"
adb shell am force-stop "$PKG"

echo "Phase 2: the API accepts"
BEFORE="$(count)"
curl -sf -X POST "$MOCK/_mock/accept" > /dev/null
adb shell am start -n "$PKG/.MainActivity" > /dev/null
wait_for $((BEFORE + 1))
sleep 3
PHASE2="$(state)"
echo "  sentinel: $PHASE2"

python3 - "$PHASE1" "$PHASE2" "$(installs)" <<'PY'
import json, sys
phase1, phase2, installs = (json.loads(a) for a in sys.argv[1:])
ids = {i["install_attempt_id"] for i in installs}
assert phase1["status"] == "failed", f"phase 1 status {phase1['status']}"
assert len(ids) == 1, f"install_attempt_id changed across the kill: {ids}"
assert phase1["install_attempt_id"] in ids
assert phase2["status"] == "tracked", f"phase 2 status {phase2['status']}"
assert phase2["install_attempt_id"] == phase1["install_attempt_id"]
print(f"PASS: {len(installs)} install POSTs, one install_attempt_id, tracked after the restart")
PY
