#!/usr/bin/env bash
# Shared helpers for the candidate-repo evaluation harness.
#
# Design note: these helpers only *record*. They never retry, patch, pin, or
# otherwise coerce a repo into working. A failing step is a result.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CANDIDATES="$ROOT/candidates"
LOGS="$ROOT/logs"

# Every venv lands in <repo>/.venv. Nothing is installed globally, and no
# `poetry config` is run (that would mutate shared state on this machine).
export POETRY_VIRTUALENVS_IN_PROJECT=1
export POETRY_NO_INTERACTION=1

# Keep output deterministic and non-interactive.
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1

# run_step <label> <cmd...>
# Runs a documented command verbatim, echoing it into the log with its exit
# code and elapsed seconds. Returns the command's own exit code.
run_step() {
  local label="$1"; shift
  local start end rc
  echo ""
  echo "### STEP: $label"
  echo "### CMD: $*"
  echo "### START: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  start=$SECONDS
  "$@"
  rc=$?
  end=$SECONDS
  echo "### EXIT: $rc"
  echo "### ELAPSED_SEC: $((end - start))"
  return $rc
}

# timed_step <label> <cmd...>
# Same as run_step but also writes the elapsed time to $ELAPSED_FILE so the
# caller can read wall-clock back out for the report.
timed_step() {
  local label="$1"; shift
  local start end rc
  echo ""
  echo "### STEP: $label"
  echo "### CMD: $*"
  echo "### START: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  start=$SECONDS
  "$@"
  rc=$?
  end=$SECONDS
  echo "### EXIT: $rc"
  echo "### ELAPSED_SEC: $((end - start))"
  [ -n "${ELAPSED_FILE:-}" ] && echo "$((end - start))" > "$ELAPSED_FILE"
  return $rc
}

# Test runs are capped at 15 minutes per the task's time-box. Installs are not
# timed (explicit user decision).
TEST_TIMEOUT_SEC=900
