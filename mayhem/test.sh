#!/usr/bin/env bash
#
# mayhem/test.sh — RUN stratagus's own tests/network/test_network.cpp suite
# (built by mayhem/build.sh into /mayhem/net_message_tests). Runs only; never
# compiles. This is the exact code net_message_fuzz/netinit_fuzz fuzz: each
# TEST_CASE serializes a message with fixed, hand-chosen field values then
# deserializes it back and asserts byte-for-byte equality (CheckSerialization
# in the upstream test file) — a genuine behavioral oracle, not an exit-code
# check: a no-op/neutered binary produces no doctest summary at all, which
# this script treats as a hard failure below.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/mayhem/net_message_tests"
if [ ! -x "$RUNNER" ]; then
  RUNNER="/mayhem/net_message_tests"
fi
if [ ! -x "$RUNNER" ]; then
  echo "FATAL: net_message_tests missing — mayhem/build.sh must build it" >&2
  emit_ctrf "doctest" 0 1 0
  exit 1
fi

OUT="$("$RUNNER" 2>&1)"
STATUS=$?
echo "$OUT" | tail -20

# doctest prints: "[doctest] test cases: 7 | 7 passed | 0 failed | 0 skipped"
CASES_LINE="$(echo "$OUT" | grep -m1 'test cases:')"
TOTAL=$(echo "$CASES_LINE" | sed -n 's/.*test cases:[[:space:]]*\([0-9]\+\).*/\1/p')
PASSED=$(echo "$CASES_LINE" | sed -n 's/.*test cases:[[:space:]]*[0-9]\+[[:space:]]*|[[:space:]]*\([0-9]\+\) passed.*/\1/p')
SKIPPED=$(echo "$CASES_LINE" | sed -n 's/.*|[[:space:]]*\([0-9]\+\) skipped.*/\1/p')
TOTAL=${TOTAL:-0}; PASSED=${PASSED:-0}; SKIPPED=${SKIPPED:-0}
FAILED=$(( TOTAL - PASSED - SKIPPED ))

# A crashed/neutered/aborted runner prints no doctest summary at all: TOTAL
# stays 0. Treat that — and any nonzero exit that didn't get counted as a
# doctest failure — as a hard failure, never a silent pass.
if [ "$STATUS" -ne 0 ] && [ "$FAILED" -le 0 ]; then FAILED=1; fi
if [ "$TOTAL" -eq 0 ]; then FAILED=$(( FAILED > 0 ? FAILED : 1 )); fi

# This suite is small (7 cases in the upstream file as of the pinned commit);
# sanity-check we actually ran a plausible number, not e.g. 1 because the
# binary was silently truncated by a stripped build context.
if [ "$TOTAL" -gt 0 ] && [ "$TOTAL" -lt 7 ]; then
  echo "WARN: only $TOTAL doctest cases ran (expected >= 7) — build context may be incomplete" >&2
  FAILED=$(( FAILED > 0 ? FAILED : 1 ))
fi

emit_ctrf "doctest" "$PASSED" "$FAILED" "$SKIPPED"
