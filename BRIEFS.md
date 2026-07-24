# Agent briefs

Covers the two repos that installed cleanly in the [evaluation](RESULTS.md):
**holmesgpt** and **gptme**. Integuru is excluded — its suite fails 3/3 at HEAD.

Scope note: sections 1–4 and 6 are established by reading the checkout at the
pinned SHA. Section 5 combines the observed run in `RESULTS.md` with source
reading. The live-LLM tests in both projects (293 and 10 respectively) were
**not executed** — no API key was configured — so they are described from their
code, not from observed behaviour.

---

## HolmesGPT — `20c62adbc01d094716b5872fe813656847aaae82`

### 1. Claimed job

From `README.md`:

> "Open-source AI agent for investigating production incidents and finding root
> causes. Works with any stack — Kubernetes, VMs, cloud providers, databases, and
> SaaS platforms."

And on Operator mode:

> "Most AI agents are great at troubleshooting problems, but still need a human to
> notice something is wrong and trigger an investigation. Operator mode fixes that —
> HolmesGPT runs in the background 24/7, spots problems before your customers
> notice, and messages you in Slack with the fix. Connect the GitHub integration and
> it can even open PRs to fix what it finds."

**The decision it takes on the user's behalf:** it decides *what caused a production
incident*. It runs an agentic loop that picks which observability sources to query,
issues those queries against live production systems, and emits a root-cause
conclusion. In Operator mode it also decides *when* to investigate — unprompted, on a
schedule or on deployment — and then decides that a finding is worth paging a human
about, or worth a pull request.

### 2. Consequence of getting it wrong

- **Incident misdiagnosed.** It names the wrong service, pod, or deploy as the root
  cause during an outage. Responders roll back or restart the wrong component while
  the real fault continues; MTTR extends and the failing change stays live.
- **False finding broadcast unprompted.** Operator mode posts conclusions to Slack
  with no human in the loop. A confident wrong answer at 3am pulls people onto a
  non-issue, or worse, gives an on-call engineer a reason to close a real page.
- **Incident record corrupted.** `holmes/plugins/destinations/` ships Slack and
  PagerDuty destinations, and the README advertises writeback to AlertManager,
  PagerDuty, OpsGenie and Jira. A wrong root cause written back attaches a false
  narrative to the permanent incident record that postmortems then build on.
- **Bad PR opened.** The GitHub MCP integration can open PRs "to fix what it finds."
  A fix for a misdiagnosis is a change to production code justified by a wrong premise.
- **Mutating command against a live cluster.** The `bash` and `kubectl_run` toolsets
  execute real commands. These are gated (see §4), but the blast radius is a
  production cluster, not a sandbox.
- **Untrusted input path.** The agent's whole job is ingesting logs, alerts and
  ticket text from production. Those are attacker-influencable strings flowing into
  an LLM that can then invoke tools — prompt injection here is a live concern, not a
  theoretical one.

### 3. Tool surface

47 entries under `holmes/plugins/toolsets/`. By category:

- **Kubernetes / orchestration:** kubernetes, kubernetes_logs, openshift, helm,
  argocd, crossplane, kubevela, cilium, inspektor_gadget, aks, aks-node-health,
  `kubectl_run`
- **Metrics / traces / logs:** prometheus, grafana (incl. Tempo), datadog, newrelic,
  coralogix, elasticsearch/OpenSearch, victorialogs, loki
- **Databases / queues:** azure_sql, mongodb, atlas_mongodb, `database` (SQLAlchemy —
  pg8000, pymysql, pymssql, clickhouse), rabbitmq, kafka
- **Docs / ticketing / SaaS:** confluence, slab, servicenow_tables, robusta,
  robusta_platform_mcp
- **Generic execution & fetch:** `bash`, `http`, `internet`, `connectivity_check`,
  `service_discovery`, `skills`, `investigator`
- **Via MCP:** GitHub, GitLab, Jenkins, AWS, Azure, GCP, Confluence
- **Outbound destinations:** Slack, PagerDuty (`holmes/plugins/destinations/`)
- **LLM providers:** OpenAI, Anthropic, Azure, Bedrock, Gemini and others via litellm

### 4. Autonomy

Predominantly **read-and-conclude**, with a real but gated write surface, and a
genuinely autonomous mode.

- The default posture is investigation: query data sources, produce a root cause.
- Execution tools are gated by an explicit approval mechanism. `holmes/core/tools.py`
  defines `StructuredToolResultStatus.APPROVAL_REQUIRED` (:68) and an
  `ApprovalRequirement` model (:143); a tool invocation that trips the check returns
  `APPROVAL_REQUIRED` rather than running (:364-374).
- `bash` validates via prefix allow/deny lists with `bashlex` parsing, distinguishing
  `ALLOWED` / `DENIED` / `APPROVAL_REQUIRED`, plus `HARDCODED_BLOCKS`.
- `kubectl_run` refuses outright unless images are explicitly whitelisted: *"The
  command `kubectl run` is not allowed. The user must whitelist specific images and
  commands but none have been configured."*
- **Operator mode is the autonomous path:** it initiates investigations with no human
  trigger, messages Slack, and can open PRs. The human approves the *fix*, not the
  *decision to investigate and conclude*.

### 5. Test scope

3040 tests collected. The documented default command (`make test-without-llm` →
`pytest tests -m "not llm"`) runs 2747 of them — 2649 passed, 98 skipped, 0 failed in
81.79s. The bulk is unit-level: 813 under `tests/plugins` (toolset config parsing,
query builders, output transformers, per-toolset validators), 624 under `tests/core`,
plus 107 MCP/OAuth tests, 103 bash-validation tests, 100 utils. These assert on helper
behaviour — that a Prometheus query is built correctly, that a bash command is
classified allowed/denied, that a config merges — not on investigative quality.
Crucially, the agent loop *is* exercised without a live model: roughly **229 tests
across 14 files** drive `ToolCallingLLM` against a `mock_llm` fixture, covering the
happy path, streaming, cost accumulation across iterations, cancellation at three
different points, and approval approved/denied-with-feedback; 22 further tests cover
approval tokens and their security. True end-to-end quality lives in `tests/llm/` —
**293 `llm`-marked tests**, 279 of them in `test_ask_holmes.py`, backed by 266 fixture
directories — which replay real investigation scenarios against a live model and
judge the answer. Those are excluded from the default command and need an API key.
**Ratio: ~9.6% (293/3040) are live-LLM end-to-end evals, none of which run by default;
~7.5% (229/3040) exercise the agent loop against a mocked LLM; the remaining ~83% are
unit tests on helpers.**

### 6. Team

**168 commits in the last 90 days from 23 distinct authors.** Most recent commit
2026-07-21. CNCF sandbox project, originally by Robusta.Dev with contributions from
Microsoft.

---

## gptme — `38a311d14cba6eaedd7ad3f3d9e177d358a25a22`

### 1. Claimed job

From `README.md`:

> "📜 A personal AI agent that runs *anywhere a terminal runs* — your laptop, ssh
> sessions, tmux, headless servers, CI pipelines. Provider-agnostic, local-first, and
> unconstrained: ships with shell, Python, web, vision, and everything else an agent
> needs. A great coding agent, but general-purpose enough to assist in all kinds of
> knowledge-work."

**The decision it takes on the user's behalf:** it decides *which commands to run and
which files to change on your machine*. Given a natural-language goal, it selects
shell commands, Python to execute, patches to apply, and pages to browse, then carries
them out in the user's own environment with the user's own credentials. The word the
README uses for its posture is "unconstrained."

### 2. Consequence of getting it wrong

- **Source silently corrupted.** `patch.py`, `patch_anchored.py`, `patch_many.py`,
  `morph.py` and `save.py` write directly to disk. A misapplied patch mutates a
  working tree; if the mistake is subtle it survives review.
- **Bad code committed and pushed.** `autocommit.py` commits on message completion
  (`autocommit_on_message_complete`). A wrong change plus autocommit means the error
  is in version history before a human reads it.
- **Arbitrary command execution as the user.** `shell.py` and `shell_background.py`
  run with full user privileges. This is the intended feature; the failure mode is
  that a wrong command is indistinguishable from a right one until it has run.
- **The human gate can be switched off entirely.** `no_confirm` (`gptme/chat.py:60`)
  disables prompting, and the README advertises CI pipelines and headless servers as
  targets. In that configuration a wrong decision executes unattended, with no
  approval step anywhere in the path.
- **Actions taken inside authenticated sessions.** The browser and computer-use tools
  drive a real browser and a real X11 desktop. Mistakes there are clicks and form
  submissions in whatever accounts are already logged in.
- **Untrusted content reaches the loop.** `browser.py`, `rag.py`, `gh.py` and
  arbitrary MCP servers pull external text into a context that can invoke shell.

The distinguishing property: gptme's wrong answer is not a bad suggestion a human
then evaluates. It is an executed command or a written file.

### 3. Tool surface

45 modules under `gptme/tools/`:

- **Execution:** `shell`, `shell_background`, `shell_validation`, `_allowlist`,
  `python` (IPython), `tmux`, `restart`
- **File mutation:** `patch`, `patch_anchored`, `patch_many`, `morph`, `save`, `read`
- **VCS / CI:** `autocommit` (git commit), `gh` (GitHub PR/issue content), `precommit`
- **Web & vision:** `browser` with `_browser_playwright`, `_browser_lynx`,
  `_browser_perplexity`, `_browser_format`, `_browser_thread`, `screenshot`, `vision`
- **Computer use:** `computer`, `computer_semantic`, `computer_transport`,
  `_computer_gate` (X11 desktop control)
- **Extensibility:** `mcp`, `mcp_adapter` — arbitrary external MCP servers
- **Agent-structural:** subagent (`tests/test_tools_subagent.py`), `todo`, `chats`,
  `rag`, `lessons`, `pruner`, `progress`, `complete`, `elicit`, `form`, `choice`,
  `clarify`, `vent`
- **LLM providers:** Anthropic, OpenAI, Google, xAI, DeepSeek, OpenRouter, or fully
  local via `llama.cpp`

### 4. Autonomy

**It acts.** Human approval is the default but is defeasible in three documented ways.

- Confirmation is a first-class type: `ConfirmFunc = Callable[[str], bool]`
  (`gptme/tools/base.py:139`), and tools route through
  `execute_with_confirmation(..., confirm_msg="Run command?")` (`shell.py:1724-1732`).
- **Allowlist bypass:** `shell.py:1712` — *"Skip confirmation for allowlisted
  commands"*; allowlist entries support shell globs and `hint:` patterns matching
  whole classes of tools (`_allowlist.py`).
- **Global bypass:** `no_confirm` threads from the CLI through `chat.py` (:60, :171,
  :206, :338), removing prompting altogether.
- **Computer-use gating is opt-in and off by default.** `_computer_gate.py`:
  *"Gating is opt-in via `GPTME_COMPUTER_CONFIRM_SENSITIVE`: (unset or "0") — gate
  disabled, actions proceed silently (default, back-compat)."* Sensitive actions
  include keystrokes, drags and browser form fills — i.e. typing into authenticated
  pages proceeds without a prompt unless the operator has explicitly enabled the gate.

### 5. Test scope

8507 tests collected; `make test` selects 8456 (the 51 `slow` tests are deselected).
Observed: 8297 passed, 31 failed, 179 skipped in 433.76s. The suite is
overwhelmingly **unit tests on helper functions** — the largest files are
`test_eval_behavioral.py` (316 tests), `test_subagent_unit.py` (276),
`test_tools_base.py` (156), `test_server_v2.py` (136),
`test_tools_shell_validation.py` (114) — asserting on command parsing, patch
application, tool-spec registration, output formatting and shell-validation edge cases
(e.g. "pipe in single quotes"). Many tests invoke the CLI through Click's `CliRunner`,
but with no key configured the conftest forces `MODEL=local/test` and
`OPENAI_BASE_URL=http://localhost:666`, so those exercise CLI plumbing rather than
agent behaviour. What genuinely exercises the agent end-to-end against a real model is
`requires_api`: **10 tests** — `test_cli.py::test_generate_primes` (asks for the first
10 primes via IPython and asserts `"23"` and `"29"` appear in output), `test_tmux`,
`test_subagent`, `test_vision`, `test_url`, `test_chain`, `test_command_summarize`,
`test_command_rename_auto`, plus `test_eval.py::test_eval` and `test_eval_cli`.
`pytest_collection_modifyitems` skips all 10 with *"No API key configured"* — they did
not run here. A further 4 tests are `eval`-marked (subagent) and deselected by default,
and 38 carry `integration` marks (computer-use, X11, server).
**Ratio: 10/8507 ≈ 0.12% exercise the agent end-to-end against a live model, and 0 of
them ran in this evaluation; ~99.9% are unit-level.** Of `test_cli.py`'s 82 tests,
10 need a live model.

### 6. Team

**946 commits in the last 90 days from 11 distinct authors.** Most recent commit
2026-07-24 — the same day as this evaluation.
