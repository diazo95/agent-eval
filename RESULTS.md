# Candidate repo evaluation — clean-state runnability

Each repo was cloned fresh, installed **exactly** as its own documentation
prescribes, and run with its **documented** test command. Nothing was fixed,
pinned, upgraded, or edited — every repo's working tree was verified clean
(`git status --porcelain`) after the run. No recommendation is made here.

Run date: 2026-07-24. Raw untruncated logs for every step are in [`logs/`](logs/);
the harness that produced them is [`scripts/evaluate.sh`](scripts/evaluate.sh).

## Results

| repo | install worked | total | passed | failed | skipped | needs API key | HEAD SHA | notes |
|---|---|---|---|---|---|---|---|---|
| [HolmesGPT/holmesgpt](https://github.com/HolmesGPT/holmesgpt) | ✅ yes (62s) | 3040 collected / **2747 run** | **2649** | **0** | **98** | Not for the documented command. 293 `llm`-marked tests are deselected by `-m "not llm"`; those need an LLM key (`make test-llm-ask-holmes`). | `20c62adbc01d094716b5872fe813656847aaae82` | Cleanest of the three. `poetry install --with dev` → exit 0, 522 pkgs, Python 3.11.15. `make test-without-llm` → exit 0 in 81.79s. All 98 skips are missing third-party integration credentials, not LLM keys. Passed with no Kubernetes cluster present (logs `Running without kube-config`). |
| [Integuru-AI/Integuru](https://github.com/Integuru-AI/Integuru) | ⚠️ partial (21s) | **3** | **0** | **3** | **0** | No — the 3 tests mock the LLM (`patch('integuru.agent.llm.get_instance')`). `OPENAI_API_KEY` is only needed for actual use. | `b063940a23deb9ac4d4ca4452731bc479b688f87` | Whole suite fails at HEAD, for a repo-content reason: all 3 error in `setUp` with `FileNotFoundError: 'test.har'` — a fixture file that is not in the repo. Not environmental. Documented step 3 `poetry shell` fails (removed in Poetry 2.0). Needs Python 3.12 (`>=3.12,<3.13`). |
| [gptme/gptme](https://github.com/gptme/gptme) | ✅ yes (32s) | 8507 collected / **8456 run** | **8297** | **31** | **179** | Yes — 10 `requires_api` tests auto-skip with reason `No API key configured`; conftest then forces `MODEL=local/test` and `OPENAI_BASE_URL=http://localhost:666`. | `38a311d14cba6eaedd7ad3f3d9e177d358a25a22` | Installs fine, but `make test` exits non-zero: 31 failures in 433.76s. 12 are `pytest-timeout (>10.0s)` — the Makefile hardcodes `-n 16 --timeout 10`, and 16 workers on this 4-core box drove load to ~16. 5 are network-blocked (below). Documented `pipx` and `poetry shell` steps both unavailable. |

Errored: **0** for all three (no collection or internal errors; gptme's failures are
test failures, not errors).

Wall-clock, documented test command only (install excluded, per the agreed time-box):

| repo | pytest wall-clock | harness wall-clock | hit 15-min cap? |
|---|---|---|---|
| holmesgpt | 81.79s | 111s | no |
| Integuru | 2.59s | 6s | no |
| gptme | 433.76s | 439s | no |

All three completed inside the 15-minute cap.

## Per-repo detail

### HolmesGPT/holmesgpt — `20c62adb`

Documented source: `CONTRIBUTING.md` steps 2 and 5; `Makefile: test-without-llm`.

```
poetry install --with dev        # exit 0, 62s
make test-without-llm            # -> poetry run pytest tests -m "not llm"
                                 # exit 0, 81.79s
```

`=========== 2649 passed, 98 skipped, 65 warnings in 81.79s (0:01:21) ===========`

Reconciles exactly: 3040 tests in the repo, 293 carry the `llm` marker and are
deselected, leaving 2747 run = 2649 passed + 98 skipped.

The 98 skips are third-party integration credentials, **not** LLM API keys:

| count | reason |
|---|---|
| 22 | `ROBUSTA_UI_TOKEN not set` |
| 15 | Slow test — needs `RUN_SLOW_TESTS=1` + Datadog credentials |
| 8 | `GRAFANA_URL environment variable not set` |
| 6 | Grafana not running on localhost:3000 |
| 4 | `VICTORIALOGS_URL` not set |
| 4 | mTLS Kafka env vars not set |
| 2 | Azure credentials not set |
| 1 | `PROMETHEUS_URL must be set` |
| 1 | `pytest -m manual` |
| 1 | root bypasses file permissions (chmod 000 stays readable) |

Network/cluster: the documented suite needs neither. It logs
`Running without kube-config! e=Invalid kube-config file` and still passes.

### Integuru-AI/Integuru — `b063940a`

Documented source: `README.md` "Setup" steps 2–4 and "Running Unit Tests".

```
poetry env use /usr/bin/python3.12   # exit 0  (see note)
poetry install                       # exit 0, 21s
poetry shell                         # exit 1  <- documented step, unavailable
poetry run ipython kernel install --user --name=integuru   # exit 0, 2s
poetry run pytest                    # exit 1, 2.59s
```

`============================== 3 failed in 2.59s ===============================`

All three tests fail identically, in `setUp`, before any test logic runs:

```
self.agent = IntegrationAgent(self.prompt, self.har_file_path, self.cookie_path)
integuru/agent.py:30: in __init__
    self.req_to_res_map: Dict[Request, str] = parse_har_file(har_file_path)
E   FileNotFoundError: [Errno 2] No such file or directory: 'test.har'
```

`tests/test_integration_agent.py` sets `self.har_file_path = "test.har"`, but no
`test.har` exists anywhere in the repo. This is a property of the checkout, not of
this machine — it would fail the same way on any clean clone.

Two environment notes, neither of which caused the failures:

- **Python.** `pyproject.toml` pins `python = ">=3.12,<3.13"`. The default
  interpreter here is 3.11, so Poetry was pointed at `/usr/bin/python3.12`. This
  selects an interpreter to satisfy the project's own constraint; no dependency was
  pinned or altered.
- **`poetry shell`** (README step 3) no longer exists:

  ```
  Since Poetry (2.0.0), the shell command is not installed by default.
  ```

  Not needed for the test command, which uses `poetry run`. `poetry install` also
  warns that `[tool.poetry.dev-dependencies]` is deprecated, but still installed
  pytest 9.0.3.

### gptme/gptme — `38a311d1`

Documented source: `docs/contributing.rst`; `Makefile: build`, `test`.

```
pipx install poetry     # pipx NOT INSTALLED on this box; skipped (Poetry 2.3.3 present)
poetry shell            # exit 1  <- documented step, unavailable (same Poetry 2.0 removal)
make build              # -> poetry install, exit 0, 32s
make test               # exit 2 (make: *** [Makefile:56: test] Error 1), 433.76s
```

`= 31 failed, 8297 passed, 179 skipped, 4 warnings, 4 subtests passed in 433.76s (0:07:13) =`

Selected 8456 of 8507 collected (`16 workers [8456 items]`); the Makefile's
`-m "not slow and not eval"` deselects the 51 `slow` tests.

Marker census (`--collect-only`): `requires_api` = 10, `eval` = 4, `slow` = 51,
total = 8507.

Failures by file, and what they are:

| count | file | cause |
|---|---|---|
| 12 | `test_auto_compact.py` | `Failed: Timeout (>10.0s) from pytest-timeout` — the Makefile hardcodes `-n 16 --timeout 10`; 16 workers on 4 cores pushed load average to ~16, so the 10s per-test budget is exceeded under self-inflicted contention. |
| 10 | `test_util_gh_mocked.py` | `assert None is not None` — `get_github_pr_content()` returns `None` even though `subprocess.run` is mocked. Cause not isolated inside the time-box; note that with no API key the conftest sets `MODEL=local/test` and `OPENAI_BASE_URL=http://localhost:666`. |
| 5 | `test_util_tokens.py` | Network-blocked (verified, see below). |
| 2 | `test_subagent_unit.py` | control-channel read-error assertions |
| 1 | `test_reduce.py` | timeout |
| 1 | `test_agent.py` | `test_install_detects_existing_workspace` |

**Network.** The `test_util_tokens` failures are environmental and confirmed by
direct check — tiktoken cannot fetch its vocabulary through this environment's proxy:

```
ProxyError(MaxRetryError("HTTPSConnectionPool(host='openaipublic.blob.core.windows.net', port=443):
Max retries exceeded with url: /encodings/o200k_base.tiktoken
(Caused by ProxyError('Unable to connect to proxy', OSError('Tunnel connection failed: 403 Forbidden')))"))
```

so `get_tokenizer("gpt-4o")` returns `None` and the assertions fail. On a host with
open egress these would presumably pass.

**API keys.** `tests/conftest.py::pytest_collection_modifyitems` skips every
`requires_api` test with reason `No API key configured` when no key is present — 10
tests, included in the 179 skips. The documented command does not require a key;
`make test SLOW=true` and `make test-api` do.

## Environment

Recorded in [`logs/env.txt`](logs/env.txt). Relevant facts:

- Python 3.10/3.11/3.12/3.13 available; default `python3` = **3.11.15**
- **Poetry 2.3.3** — `poetry shell` removed in 2.0, which is why two repos' documented
  steps fail
- **pipx not installed** — gptme documents it for installing Poetry
- 4 cores, 15 GB RAM — relevant to gptme's `-n 16` timeouts
- Outbound HTTPS via a filtering proxy; `openaipublic.blob.core.windows.net` is 403-blocked

## Method / caveats

- Isolation: `POETRY_VIRTUALENVS_IN_PROJECT=1`, so each venv lives in
  `candidates/<repo>/.venv`. Nothing installed globally; no `poetry config` run.
- Graded test runs were executed **sequentially**, one repo at a time, so no run's
  wall-clock was inflated by another. (gptme's oversubscription is self-inflicted by
  its own Makefile, not by concurrent work.)
- Counts are parsed from the pytest summary line in the committed logs rather than
  from an added `--junitxml`, so the graded command stays byte-identical to what each
  project documents. Reproduce with `scripts/summarize.sh <repo>`.
- Time-box: installs untimed, test command capped at 900s. No repo hit the cap.
- Marker/`--collect-only` counts were gathered **after** the graded run and did not
  affect it. For gptme these were collected without the Makefile's `${SRCDIRS}`
  argument, so 8507 is the config-default scope; the graded run selected 8456 of them.

---

# Re-run — gptme @ `38a311d14cba6eaedd7ad3f3d9e177d358a25a22`

Requested: re-run the gptme evaluation on hardware meeting two stated
requirements, pinned to the same SHA for comparability.

## Verdict

**Is `make test` green on adequate hardware? — NOT ESTABLISHED.**

The re-run did not happen. Both stated environment requirements are unavailable in
this session, and the instruction was to fix the machine, never the repo, and to stop
if either is missing. Neither can be fixed from inside the session. No adjustment to
worker count or timeouts was made, so the documented command is unchanged and no
substitute figure is reported in place of the real one.

## Precondition check (blocking) — `logs/rerun-preconditions.log`

| Requirement | Required | Actual | Status |
|---|---|---|---|
| CPU cores | ≥ 16 | **4** | ❌ FAIL |
| Unrestricted outbound HTTPS | yes | `openaipublic.blob.core.windows.net` blocked | ❌ FAIL |
| Live API key (needed for step 3) | yes | none set | ❌ FAIL |

**1. CPU — 4 cores, 16 required.** `nproc`, `getconf _NPROCESSORS_ONLN` and
`/proc/cpuinfo` all report 4; `lscpu` shows `Core(s) per socket: 4`, `Socket(s): 1` on
an Intel Xeon @ 2.80GHz. There is no cgroup CPU quota to raise (`cpu.max` absent) —
the container has 4 physical cores. Core count is fixed when the remote environment is
created and cannot be changed from within a session.

**2. Outbound HTTPS — blocked by egress policy.** The exact host tiktoken needs still
returns 403 at CONNECT:

```
$ curl https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken
curl: (56) CONNECT tunnel failed, response 403
```

The proxy's own status endpoint records the reason:

```json
"recentRelayFailures": [{
  "kind": "connect_rejected",
  "detail": "gateway answered 403 to CONNECT (policy denial or upstream failure)",
  "host": "openaipublic.blob.core.windows.net:443"
}]
```

`"selective": false` — this is the organization's egress policy for the session, not a
per-tool scope. `/root/.ccr/README.md` is explicit that this is not mine to work
around: *"The destination host is not allowed by your organization's egress policy for
this session. Do not retry or route around it — report the blocked host."* Changing it
requires a different network policy on the environment
([docs](https://code.claude.com/docs/en/claude-code-on-the-web)).

**3. No API key (blocks step 3 independently).** `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, `OPENROUTER_API_KEY`, `DEEPSEEK_API_KEY`, `GEMINI_API_KEY`,
`XAI_API_KEY`, `GROQ_API_KEY` are all unset.

## Step 1 — `make test`: NOT RUN

Blocked on requirements 1 and 2. No total/passed/failed/skipped, wall-clock, or
`git status` verification is reported, because producing them on 4 cores with blocked
egress would reproduce the previous invalid run rather than replace it.

## Step 3 — `requires_api` end-to-end tests: NOT RUN

Blocked on requirement 3. `make test-api` runs `pytest -m "requires_api"`, and
`tests/conftest.py::pytest_collection_modifyitems` skips all 10 with *"No API key
configured"* when no key is present. **No API cost was incurred: $0.00** — no request
was issued to any provider. The per-test pass/fail table and a real cost figure both
require a funded key.

## Step 2 — diagnosis of the 10 `test_util_gh_mocked.py` failures ✅ DONE

This did not depend on either failed precondition, so it was completed.
Log: `logs/rerun-gh-mocked-diagnosis.log`.

**Result: environmental. Not a genuine defect at this SHA.**

Evidence, in order:

1. **Not the core-count problem.** Run alone — single process, no xdist, no
   `--timeout` — the same 10 fail in 2.36s while the other 27 in the file pass:
   `10 failed, 27 passed in 2.36s`. Oversubscription is ruled out.

2. **The guard clause.** `gptme/util/gh.py:669-673`:

   ```python
   def get_github_pr_content(url: str) -> str | None:
       """Get GitHub PR content with comments and reviews using gh CLI."""
       if not shutil.which("gh"):
           logger.debug("gh CLI not available for GitHub PR handling")
           return None
   ```

3. **`gh` is not installed on this machine** (`command -v gh` → not found).

4. **The failing tests patch `subprocess.run` but not `shutil.which`.** The 27 passing
   tests in the same file patch it explicitly — e.g.
   `@patch("gptme.util.gh.shutil.which", return_value="/usr/bin/gh")` at lines 754,
   780, 793, 810, 826, 842, 865, and `test_no_gh_cli` deliberately patches it to
   `None`. The 10 failures therefore return `None` at the guard clause **before
   reaching any mock**, and `assert result is not None` fails.

5. **Proof.** With a stub `gh` placed on `PATH` (scratchpad only — no repo file
   touched, nothing installed): **`37 passed in 0.39s`**, all 10 green.

So these 10 are a host-dependency assumption in the test file — despite the name
`test_util_gh_mocked.py`, they require the real `gh` binary to exist on `PATH` — not a
runtime bug in `get_github_pr_content`. Nothing was fixed.

This also revises the previous run's failure accounting: of 31 failures, **10 are the
missing `gh` CLI**, 5 are the blocked tiktoken host, and 12 are `-n 16` timeouts on 4
cores. That leaves 4 (`test_subagent_unit.py` ×2, `test_reduce.py`, `test_agent.py`)
whose cause is still not isolated.

## Step 4 — eval workflows ✅ DONE

Pure file reading; independent of the failed preconditions.

### `.github/workflows/eval.yml` — "Evals"

**Trigger.** Nightly cron plus manual dispatch:

```yaml
on:
  schedule:
    - cron: '0 2 * * *'  # Run daily at 2 AM UTC
  workflow_dispatch:
```

**Can it fail a build? No — it never touches a build.** It has no `pull_request`
trigger, so it is not attached to PRs and cannot block a merge. The job itself can go
red as a scheduled run (there is no `continue-on-error`), but nothing gates on it. It
writes results to a separate branch, explicitly marked to not re-trigger CI:

```yaml
git commit -m "chore: add eval results for run ${{ github.run_number }} [skip ci]" || echo "No changes to commit"
git push origin eval-results
```

**When is it skipped?** Never conditionally — the job carries no `if:`, and no step is
guarded. It runs on every scheduled tick regardless of key availability. If keys are
absent the evals simply run badly rather than being skipped; the only tolerance built
in is the `|| echo "No changes to commit"` on the results commit.

### `.github/workflows/eval-ci.yml` — "Eval Quality Gate"

**Trigger.** PRs to `master`, but only when agent-relevant paths change:

```yaml
on:
  pull_request:
    branches: [ master ]
    types: [opened, synchronize, reopened]
    paths:
      - 'gptme/tools/**'
      - 'gptme/models/**'
      - 'gptme/eval/**'
      - 'gptme/prompts/**'
      - 'gptme/message*.py'
      - 'gptme/llm/**'
      - 'gptme/chat.py'
      - 'gptme/codeblock.py'
      - 'gptme/session.py'
```

**Can it fail a build? No.** Despite being named a "Quality Gate", it is explicitly
non-blocking:

```yaml
    # Non-blocking in Phase 1 — informational only
    continue-on-error: true
```

Every PR comment it can post — pass, fail, skipped, or could-not-run — ends with the
same line: `*Informational only — does not block merge*`.

**When is it skipped?** Four distinct ways:

1. **Path filter** — a PR touching none of the paths above never triggers it.
2. **Draft PRs** — `if: ${{ !github.event.pull_request.draft }}`, commented
   `# Skip draft PRs to save API cost`.
3. **Fork PRs / no secret** — the first step checks the key and short-circuits
   everything downstream:

   ```yaml
   if [ -z "$ANTHROPIC_API_KEY" ]; then
     echo "available=false" >> "$GITHUB_OUTPUT"
     echo "Fork PRs do not have access to ANTHROPIC_API_KEY — skipping eval."
   ```

   Every subsequent step is gated on `if: steps.check_key.outputs.available == 'true'`,
   and it comments *"Eval Quality Gate — skipped (fork PR)"*.
4. **Self-neutralising on API trouble** — if all tests fail in under 5s average it
   assumes auth/quota rather than real failures and reports skipped:

   ```python
   fast_fail = passed_count == 0 and total_count > 0 and avg_duration < 5.0
   ```

**What it runs when it does run:** 5 evals (`hello prime100 fix-bug hello-patch
init-git`) on `anthropic/claude-haiku-4-5@tool` with `--timeout 60 --parallel 5`,
annotated in the workflow as `# 5 basic tests with Haiku — fast and cheap
(~$0.03-0.08/run)`.

## What would unblock this

A remote environment with ≥16 cores, an egress policy permitting
`openaipublic.blob.core.windows.net`, and a funded `ANTHROPIC_API_KEY` in the session
environment. With those, steps 1 and 3 run unchanged — the harness and pinned SHA are
already committed here.
