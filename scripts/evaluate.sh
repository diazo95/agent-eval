#!/usr/bin/env bash
# Candidate-repo evaluation harness.
#
# Usage: scripts/evaluate.sh <repo> <phase>
#   repo  : holmesgpt | integuru | gptme
#   phase : clone | install | test | excluded
#
# The commands below are transcribed VERBATIM from each project's own
# documentation (README / CONTRIBUTING / Makefile). Where a documented command
# cannot run on this machine, the harness still attempts it and records the
# failure, then continues via the non-interactive equivalent. It never edits a
# cloned repo, never pins or upgrades a dependency, and never retries to force a
# pass.
#
# Documented sources:
#   holmesgpt : CONTRIBUTING.md steps 2 and 5; Makefile target `test-without-llm`
#   integuru  : README.md "Setup" steps 2-4 and "Running Unit Tests"
#   gptme     : docs/contributing.rst; Makefile targets `build` and `test`

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPO="${1:?repo required}"
PHASE="${2:?phase required}"

case "$REPO" in
  holmesgpt) URL="https://github.com/HolmesGPT/holmesgpt" ;;
  integuru)  URL="https://github.com/Integuru-AI/Integuru" ;;
  gptme)     URL="https://github.com/gptme/gptme" ;;
  *) echo "unknown repo: $REPO" >&2; exit 2 ;;
esac

DIR="$CANDIDATES/$REPO"

# ---------------------------------------------------------------- clone -----
phase_clone() {
  run_step "git clone" git clone "$URL" "$DIR"
  run_step "record HEAD" git -C "$DIR" rev-parse HEAD
  run_step "record branch" git -C "$DIR" rev-parse --abbrev-ref HEAD
  run_step "record tip commit" git -C "$DIR" log -1 --format='%H %ci %s'
}

# -------------------------------------------------------------- install -----
phase_install() {
  cd "$DIR" || exit 1
  case "$REPO" in
    holmesgpt)
      # CONTRIBUTING.md step 2. Python 3.11 (default here) satisfies the
      # documented 3.11-3.13 range, so no interpreter selection is needed.
      run_step "poetry install --with dev" poetry install --with dev
      ;;
    integuru)
      # pyproject.toml declares python = ">=3.12,<3.13"; the default interpreter
      # on this box is 3.11, so Poetry is pointed at the 3.12 the project asks
      # for. This selects an interpreter only - no dependency is pinned or
      # changed, and no repo file is touched.
      run_step "poetry env use /usr/bin/python3.12" poetry env use /usr/bin/python3.12
      # README step 2
      run_step "poetry install" poetry install
      # README step 3. Poetry 2.x removed `poetry shell`; attempted anyway so
      # the failure is on the record.
      run_step "poetry shell (documented)" poetry shell
      # README step 4
      run_step "poetry run ipython kernel install --user --name=integuru" \
        poetry run ipython kernel install --user --name=integuru
      ;;
    gptme)
      # docs/contributing.rst documents `pipx install poetry` then `poetry
      # shell` then `make build`. pipx is not installed here and Poetry 2.3.3
      # already is, so the pipx step is skipped (recorded); `poetry shell` is
      # attempted so its removal in Poetry 2.x is on the record.
      run_step "pipx install poetry (documented)" command -v pipx
      run_step "poetry shell (documented)" poetry shell
      run_step "make build" make build
      ;;
  esac
}

# ----------------------------------------------------------------- test -----
phase_test() {
  cd "$DIR" || exit 1
  export ELAPSED_FILE="$LOGS/$REPO-test.elapsed"
  case "$REPO" in
    holmesgpt)
      # CONTRIBUTING.md step 5 -> Makefile: poetry run pytest tests -m "not llm"
      timed_step "make test-without-llm" timeout "$TEST_TIMEOUT_SEC" make test-without-llm
      ;;
    integuru)
      # README "Running Unit Tests"
      timed_step "poetry run pytest" timeout "$TEST_TIMEOUT_SEC" poetry run pytest
      ;;
    gptme)
      # docs/contributing.rst -> Makefile: pytest -n 16 --timeout 10
      #                                    -m "not slow and not eval" + coverage
      timed_step "make test" timeout "$TEST_TIMEOUT_SEC" make test
      ;;
  esac
  echo "### TIMEOUT_CAP_SEC: $TEST_TIMEOUT_SEC"
}

# ------------------------------------------------------------- excluded -----
# Read-only collection counts, run AFTER the graded test run. These answer
# "how many tests were excluded because they need an API key / network" with a
# number instead of a guess. They do not affect the graded numbers.
phase_excluded() {
  cd "$DIR" || exit 1
  case "$REPO" in
    holmesgpt)
      run_step "collect llm-marked tests" \
        poetry run pytest tests --collect-only -q -m "llm"
      run_step "collect all tests (no marker filter)" \
        poetry run pytest tests --collect-only -q
      ;;
    integuru)
      run_step "list test files" find . -path ./.venv -prune -o -name 'test_*.py' -print -o -name '*_test.py' -print
      run_step "collect all tests" poetry run pytest --collect-only -q
      ;;
    gptme)
      for m in requires_api eval slow; do
        run_step "collect $m-marked tests" \
          poetry run pytest --collect-only -q -m "$m"
      done
      run_step "collect all tests (no marker filter)" \
        poetry run pytest --collect-only -q
      ;;
  esac
}

case "$PHASE" in
  clone)    phase_clone ;;
  install)  phase_install ;;
  test)     phase_test ;;
  excluded) phase_excluded ;;
  *) echo "unknown phase: $PHASE" >&2; exit 2 ;;
esac
