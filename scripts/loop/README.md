# scripts/loop

Host tooling for the orchestrator loop (`WB-D23`). Never on an adopter's `PATH`, outside the
coupling gate. See `docs/proposals/orchestrator-m2-decisions.md` for what each piece is for.

## baseline.sh: the PR-flow baseline

Read-only. Derives work PRs, cursor PRs per work PR, median open-to-merge, the likely-dependent
share, wave overlap and an open-to-merge time per work PR for one repo from its merged-PR
history on GitHub. The method is in the script's header. `open_to_merge_min_per_work_pr` is
wait-to-merge time, not keyboard time (GitHub does not record attention), and it is **not** the
M2b exit metric: that needs a different source. The dependent and overlap shares print `n/a`
under 21 work PRs.

```
bash scripts/loop/baseline.sh <owner/repo> [--days 60] [--until YYYY-MM-DD]
```

Pass `--until` to reproduce an earlier run; the window is the merged PRs in the `--days` days
ending on the `--until` day, that day included. Tests: `sh tests/loop-baseline.test.sh`.

### Adoption step: run it before enabling the loop on a repo

1. Run `baseline.sh` against the repo and read the numbers. Do this **before** the first
   dispatch: afterwards the loop's own PRs are in the history and the "before" is gone.
2. If cursor_prs_per_work_pr is high (the brief saw 1.3 in devcontainers, where cursor PRs were 57% of merges), check that the repo
   has adopted the plugin version that addresses it (v0.17.0's no-op handoff); otherwise the baseline is not a valid
   "before".
3. Add one line to the table below: the repo, the date the loop was enabled and the window the
   baseline used (`--days`, `--until`). **Never record the numbers.** They are re-derivable
   from that window, as long as it still falls inside the newest 1000 merged PRs (the script warns when it hits that limit).

| Repo | Loop enabled | Baseline window |
|---|---|---|

## launch.sh: the assembled loop container

One scripted build-and-launch of the whole plan v9 § 7.3 container (`#317`): verify the base
image's build provenance, build the loop image, create the `--internal`,
`gateway_mode_ipv4=isolated` network, the allowlisting proxy and the credential-injecting proxy, run the preflight from outside
(`docker inspect`) and from inside (probes by IP), then run the coder launch line on a trivial
task in a seeded work volume and check the result. The session never holds the credential
(`#345`): it is piped to the injecting proxy's container and nowhere else. It refuses to start the session if any
preflight check fails. It is the container, not the driver: the clone, the post-exit checks,
the push and the PR belong to the driver-core issues, and the attack pass is `#318`.

```
LOOP_PREFLIGHT_ONLY=1 bash scripts/loop/launch.sh    # everything except the model call; no credential
LOOP_CREDENTIAL_FILE=<file> bash scripts/loop/launch.sh
```

Keep the credential file outside every repo (for example `~/.loop/credential.txt`, user-only permissions). Run it under Git Bash on the loop host; the variables are listed in the script's header. The
credential is the first line of `LOOP_CREDENTIAL_FILE`, piped to the injecting proxy's stdin: never
mounted, never in `docker inspect`, never in the session container. `LOOP_VERIFY_GH_TOKEN` is the token for the provenance check
when the ambient `gh` identity cannot read the base image's attestations (the base is published
by `603-Identity`); it is passed to that one command only.

| File | What it is |
|---|---|
| `Dockerfile` | The loop layer: base pinned by tag and digest, `claude` pinned by version and sha256 in `/usr/local/bin`, auto-update off, non-root `USER`, the files below baked in root-owned |
| `managed-settings.json` | Root-owned `/etc/claude-code/managed-settings.json`: the `allowManaged*` and `strictPluginOnlyCustomization` keys, `sandbox.enabled: false`, the allow list and the deny rules. The plan's PreToolUse guards are not in it yet (`allowManagedHooksOnly` means no hook runs); the attack pass (`#318`) decides what is missing |
| `proxy.py` | CONNECT-only allowlisting proxy, run from the same image; refuses IP literals, `host.docker.internal` and allowlisted names that resolve to a non-global address |
| `inject.py` | Credential-injecting reverse proxy, its own container: the session sends plain HTTP (`ANTHROPIC_BASE_URL`) with a placeholder token; this swaps in the real credential (`Authorization: Bearer` for a `CLAUDE_CODE_OAUTH_TOKEN` credential, `x-api-key` for an API key) and forwards over HTTPS to `api.anthropic.com`, only `POST /v1/messages`, `POST /v1/messages/count_tokens` and `GET /v1/models` (exact method and path, a query string allowed), the resolved address checked as global; a POST body that names `mcp_servers`, a `container`, a repeated key or a `tools` entry whose `type` is not `custom` is refused (`#318`) |
| `git_tools.py`, `managed-mcp.json` | The managed `loopgit` MCP server: `git_status`, `git_diff(staged)`, `git_log(count)`, `git_add(paths)`, `git_commit(message)`. The model supplies values, never options, so git's option parsing is not in reach; `managed-settings.json` allows these and no `Bash(git …)` |
| `attack.sh` | The attack pass (`#318`), sourced by `launch.sh` under `LOOP_ATTACK=1`; see below |
| `entrypoint.sh` | Makes the config directory and execs `claude`; no credential passes through it |
| `stop-schema.json` | The `--json-schema` the coder must answer with |

Bumping a pin is an edit in the `Dockerfile` (the base: one line; `claude`: the version and its
sha256): `launch.sh` reads the base digest and the
`claude` version back out of it, and the provenance check then covers the new digest. The
managed settings' human-only-path denies are this repo's own list (`orchestration.human_only_paths`
in `.ai/project.yml`): `allowManagedPermissionRulesOnly` ignores deny rules from anywhere else, so
a second repo's loop image needs its own copy. `LOOP_ALLOW_HOSTS` replaces the proxy's list
rather than adding to it, so a widened list names the four defaults as well. The `#317` residual (the allowed `git` subcommands could read `/proc/<pid>/environ`, where the session's
credential sat) is closed by construction in `#345`: there is no credential in the session to read, and
no free-form git option surface. The attack pass (`#318`, `attack.sh`) tested what was left, and the results are in plan v9 § 9: git option reads against the
fixed tools' argv, implicit no-index `git diff`, `.git`/config writes, and the injecting proxy's host-side
reachability. The session no longer *holds* the credential but can still *use* it through the proxy, for exactly those three requests. "No credential in the session's filesystem" holds by construction (nothing writes it there): the preflight checks `docker inspect` and the environment, not the volume. The launch line is plan § 7.3's minus `Bash` in `--tools` and minus `--strict-mcp-config` (claude refuses that flag beside a managed MCP config; `allowManagedMcpServersOnly` and the `.mcp.json` write denies stand in for it). `Bash` has no allow rules, so the coder cannot run commands (the repo's gate included) until
the driver issues decide how, and whoever adds a `Bash(git …)` allow must re-add the git-option denies this change removed (`--no-index`, `--output`, `commit -F`/`--file`); `GIT_CONFIG_GLOBAL=/dev/null` and the `.git` denies still close the git-config
code-execution route. Tests: `sh tests/loop-proxy.test.sh` (the proxy's
decision), `sh tests/loop-inject.test.sh` (the injecting proxy's path and header decisions),
`sh tests/loop-git-tools.test.sh` (the fixed git tools, driven over MCP); the in-container probes are
`launch.sh`'s preflight.

## attack.sh: the attack pass (`#318`)

```
LOOP_ATTACK=1 LOOP_CREDENTIAL_FILE=<file> bash scripts/loop/launch.sh                       # every probe, then the trivial task
LOOP_ATTACK=1 LOOP_PREFLIGHT_ONLY=1 LOOP_ATTACK_ITEMS="network breakout" bash scripts/loop/launch.sh   # a subset
```

Sourced by `launch.sh` after its preflight, so every probe sees the container exactly as built:
a throwaway container with the session's flags and network, running what a tool-started process
could run, and `claude -p` runs in the launch form for the live items. It prints `ATTACK <item>
<PASS|FAIL|NOTE> <text>` lines and fails the run on any `FAIL`. Items: `secret` (the credential
in env, `/proc`, files), `body` (what the session may ask the injecting proxy for), `network`
(host listeners on `0.0.0.0` and `[::]`, the `_ipv6` twin, host-side reach of the proxies),
`breakout` (writes outside the tmpfs, capabilities, the Docker socket, 22 CONNECT forms against
the allowlisting proxy), then the four that make model calls through the credential: `config`
(files seeded in the config dir), `agent` (`--append-system-prompt` with `--agent`), `rules` (a
matrix of Bash commands against candidate managed allow rules) and `autoallow` (Bash with none), and
`gitwrites` (the git tools outside a repository; Write against `.git`, symlinks into it, and the
other human-only paths). Run it after any change to the image, the managed settings, either proxy or the
launch line, and after any `claude` pin bump (a new version can send new request shapes the body filter would refuse; the proxy's `deny` log line names the block). Two rules it taught, for whoever adds a `Bash(...)` allow: use one exact rule per
script, never a glob (`Bash(sh tests/*.test.sh)` also matched `tests/../x.test.sh`), and know that Claude Code
allows a small read-only set with no rule at all (`echo`, `id`, `ps aux`, `git status|log|show|ls-files`).

## driver-core.sh: tree copy, checks and commit (`#319`)

```
bash scripts/loop/driver-core.sh run --session-tree DIR --session-id ID --origin URL --base BRANCH \
  --workdir DIR --branch task/NAME --stop-json FILE --author-name N --author-email E \
  --human-only-path PATH... --protected-paths-file FILE [--token-prefix STR]
```

The hermetic core of plan v9 § 7.3 / § 8.13a, from a dead session's working tree to one local
commit. It stops there: the App token, the push and the PR are later tasks. It runs, in order and
refusing at the first that fires: docker says no session container is running (an error from docker
is a refusal); the tree has no special file, no name that folds onto `.git` (any case, `.git.`, `GIT~1`) and no symlink that leaves it or names a `.git`; a fresh clone of
`origin/{base}` made by the driver is emptied and the tree is copied in with a non-dereferencing
`tar` that excludes `.git` at any depth; the staged diff touches no human-only path (rename detection
is off, so a move out of one lists its old path as a deletion) and no path in `--protected-paths-file` (nor any `.gitattributes` or NTFS alias of one, at any depth) (`scripts/loop/protected-paths.txt`: the trust predicates, the App-mode push pin and their own fixtures, `#296`, refused as `protected`; the rest of `bin/` and `tests/` stays open); a diff under `plugins/*/bin/` or
`scripts/` also changes something under `tests/`; the `commit_message` from the stop output passes
the commit grammar, with closing keywords, the final trailer paragraph and any Co-authored-by or Signed-off-by line stripped; the staged diff's added lines (symlink targets and converted encodings included), the changed paths and the
message hold no token prefix (default `sk-ant-oat`); then the commit, with
`GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1`, the bot as author and committer, no signing and no hooks.
Liveness reads a `loop.session` label that `launch.sh` does not set yet (#357 owns it), so until then that rule cannot see a running session. No git command runs in the session's tree and nothing here calls `gh`. One stdout line: `committed
<sha> <branch>`, `empty`, or `refused <rule>: <detail>` (exit 3); exit 2 is a usage or environment fault.

Not covered, by design of this task: the clone should live on a volume and the driver's git should run in a Linux driver container (plan § 7.3), which is the caller's placement, not
something the script can enforce. The symlink and case-fold fixtures skip themselves where the
filesystem cannot make the case (Git Bash without developer mode); run the suite under WSL or Linux
to exercise them. Tests: `sh tests/driver-core.test.sh`.

## preflight.sh: container and GitHub evaluators (`#320`)

```
bash scripts/loop/preflight.sh container --session F --network F --expect-network NAME --proxy F...
bash scripts/loop/preflight.sh github-dispatch --rules F --identities F --issue F --issue-number N \
  (--spec-comment F --spec-comment-id N | --no-spec-comment) [--spec-reactions F]
bash scripts/loop/preflight.sh github-push --installation F --repo OWNER/NAME --rules F --rulesets F \
  --app F --loop-identity LOGIN
```

Plan v9 § 7.3's preflight and decision 9, as pure functions over captured JSON: the driver runs
`docker inspect`, `docker network inspect` and the `gh api` reads, writes each to a file, and this
script only judges them (the header lists the endpoint behind each file). `container` checks the
session, its network and the proxies; `github-dispatch` runs at dispatch with the maintainer's view (the rules read needs no admin; a pre-cutover `author_association` is viewer-relative; the
approval gate is on `pr_base` -- a `pull_request` rule with `required_approving_review_count >= 1`,
`require_code_owner_review` and `require_last_push_approval`, each satisfied by some rule that applies, as
GitHub takes the strictest of overlapping rulesets; an `update` rule is neither required nor enough
(`WB-D24`) -- and the task issue and spec comment authors are trusted: by `identities` once the repo has
cut over, by `author_association` before; under a map any spec comment, a maintainer's included, passes only with a declared
maintainer's reaction after its last edit, from `--spec-reactions`, judged by `spec-reaction.sh`, and `--no-spec-comment` is refused, since the issue body is never the spec there); `github-push` runs once the token exists (it reaches exactly the
dispatched repo, every ruleset on `pr_base` reads `current_user_can_bypass: never` -- the App's own view,
the only bypass read, since `bypass_actors` is hidden from a non-admin -- the App's bot login
is `orchestration.loop_identity`). stdout is `pass` (exit 0) or one `refused <rule>: <detail>` /
`unreadable <rule>: <detail>` line per finding (exit 3); a missing field, a file that does not parse or a
truncated list is `unreadable`, never a pass. No gateway address is ever derived from a subnet. The
session may hold only named volumes and tmpfs (any bind is refused), no added capabilities, and one
network. Not checked: that the spec comment carries the `spec-task:` marker or is the one `spec-find.sh` selects (the driver takes it from the `found` line); which ruleset the approval rule comes from; that stale approvals are dismissed; that CODEOWNERS on `pr_base` exists and covers the changed paths; that the rules come only from active rulesets; a named volume backed by a host path (needs `docker volume inspect`); how many containers sit on
the network and the credential-not-in-inspect grep (`launch.sh` still does both). A paginated `gh api`
capture must be one complete document (the header says how). The live run against the real App is M2b. Tests: `sh tests/loop-preflight.test.sh`.

## critic.sh: critic staging, launch and load check (`#321`)

```
bash scripts/loop/critic.sh bundle --clone DIR --base BRANCH --out DIR --gate-output F --fixture-output F   --ci-jobs F --ruleset F [--ref-states F] [--load-bearing-doc PATH]... [--log-count N]
bash scripts/loop/critic.sh run --clone DIR --plugin-dir DIR --critic NAME --bundle DIR --stream-out F   --max-turns N --max-budget-usd X --settings-json JSON --schema-file F --task TEXT [--init-timeout S] [--run-timeout S]
bash scripts/loop/critic.sh check-init --stream F --plugin-dir DIR --critic NAME
```

Plan v9 § 7.3 ("Launch, each critic") and § 8.13b. Critics get no Bash, so `bundle` stages, from the
driver's committed clone, what they would have run git or gh for: the diff against `origin/{base}`, a
bounded log, the base-branch copy of every touched path, CI job conclusions and the ruleset JSON (both
captured by the driver), the state of every issue or PR id the diff's added lines and the touched
`--load-bearing-doc` files cite, and the session's gate and fixture output under `untrusted/`. An id the
`--ref-states` file does not carry reads `NOT CARRIED -- could not look`, never dangling; the launch's
staged-mode addendum says the same. Nothing here calls `gh`: the driver reads GitHub and hands the
results in.

`run` starts one critic from inside the clone with `--restricted --agent PLUGIN:CRITIC --plugin-dir
<pinned copy> --tools "Read,Grep,Glob" --model <frontmatter model> --add-dir <bundle>
--output-format stream-json --verbose`; the model and plugin name come from the pinned copy, not the
caller; every path is made absolute before claude starts in the clone, and `--plugin-dir` and
`--bundle` must lie outside it. It reads the stream's `system/init` event the moment it arrives and
**stops the session on a mismatch** (the pinned plugin missing or from another path or version, the
agent absent, any tool but exactly the frontmatter's `Read`/`Grep`/`Glob`, a model that is not the
frontmatter's, `plugin_errors`): TERM then KILL on its process group where `setsid` exists, within a
poll interval. That is defence in depth; the control that keeps Bash out is `--tools`. The check shows
the plugin, the agent and the flags took effect, not which agent is the running one. `--run-timeout`
bounds the session after a good init. Inline settings naming hooks, a `*Helper`, `statusLine`,
`permissions`, `enabledPlugins` or `extraKnownMarketplaces` (the exact list is in the script header), and a plugin dir or bundle inside the clone, are usage faults (exit 2). Open points for the first real run on the loop host: the plan's
`--strict-mcp-config` is refused by `claude` beside a managed MCP config (the coder line dropped it),
and `--json-schema` may add a structured-output tool to the init `tools`, which the exact-set check
would refuse; both fail closed and `refused ... (<stderr head>)` names the cause. `check-init` is that
check over a captured stream.
`findings-schema.json` is a starting `--json-schema` for the critics' answer. Not yet done: one real
critic run against a staged bundle on the loop host, recorded (the issue's last acceptance item). Tests:
`sh tests/loop-critic.test.sh`.
