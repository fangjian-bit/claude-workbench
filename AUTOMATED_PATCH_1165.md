Contributor details
Your Expensify account email: 3055073676@qq.com
Upwork Profile Link: https://www.upwork.com/freelancers/~01a6c3832b8108493d

## Proposal

### Please re-state the problem that we are trying to solve in this issue.

In `glunk-works/claude-workbench`, developer and way-of-working sessions operate inside a dedicated dev container acting as the GitHub dev App using ephemeral, broker-minted installation tokens mounted read-only at `/run/wow`. Under the shared-template route adopted in decision **`WB-D42`** (Issue #1163), consumer repositories across the `glunk-works` organization (`bounty-infra`, `scope-core`, `bedrock-serverless-rag`, `global-bootstrap`, and later `loop-orchestrator`) are scheduled to consume dev containers via the dev-App flavour of the base image (`603-Identity/devcontainers`) and the shared template, rather than maintaining error-prone per-repo copies of `claude-workbench`'s `.devcontainer/`.

While #1163 establishes the architectural decision record `WB-D42`, the operator-facing procedure was split out into **Issue #1165** on milestone 26 (*Identity M5b: dev containers on the shared template*), describing host onboarding that takes effect after migration step 5 (when the dev-App image flavour is published and the template is updated).

Currently, `docs/identity/DEV-CONTAINER.md` documents only `claude-workbench`'s single-repo operation. It lacks the operator runbook section **"Adding a repo to this host"**. Without this section:
1. An operator cannot onboard consumer repositories such as `bounty-infra` or `scope-core` without reverse-engineering `claude-workbench`'s internal scripts (`scripts/identity/broker.ps1`, `scripts/identity/install-host-tools.ps1`, `scripts/identity/wow-driver.ps1`).
2. There is no documented enforcement of the critical security sequencing rule: a repository's branch approval ruleset (#406 to #410 cutover) must be active and confirmed via read-back **before** the repository enters `broker.json` or has the dev App installed (because the host broker keeps an active write token current every ~30 minutes, and with approvals at 0, a dev-App write token could merge PRs or push directly to the default branch).
3. The exact configuration steps across `broker.json`, `review-poll.json`, `install-host-tools.ps1`, GitHub App permission acceptance, token mint verification, and `-Reference` clone separation are undocumented.

**Done when:** An operator can bring `bounty-infra` and `scope-core` into a container acting as the dev App from that section alone, reading nothing from this repository's own implementation files.

---

### What is the root cause of that problem?

1. **Missing Multi-Repo Operator Section in `docs/identity/DEV-CONTAINER.md`**:
   `docs/identity/DEV-CONTAINER.md` terminates at line 225 with `## PowerShell` and `## Not adopted here yet`. It contains no instructions for onboarding additional repositories onto a host that runs the identity broker and launchers.

2. **Dangerous State Transition between Broker Enrollment and Branch Ruleset Activation**:
   - In `scripts/identity/broker.ps1:10-35`, the host broker loops over every repository listed in `$WowHome\broker.json` (`repos` array) and invokes `scripts/identity/mint.sh` to mint a high-privilege dev App installation token (granting write access to `contents`, `pull_requests`, `issues`, and `workflows`), writing it to `$WowHome\tokens\<repo>\dev-token` every ~30 minutes.
   - In `scripts/identity/install-host-tools.ps1:40-45` (step 5), re-running the installer provisions `$WowHome\tokens\<repo>` for each repository in `broker.json`.
   - **The Flaw**: If an operator registers a repository in `broker.json` or installs the dev App before the repository's branch approval ruleset (#406–#410) is active and verified, the repository enters a vulnerable state where an active dev write token exists while required approvals are at `0`. Any script or container session holding that token could push directly to `main` or merge unreviewed pull requests.

3. **Undocumented Per-Repo Dev Container Invariants**:
   - In the shared template (`603-Identity/devcontainers`), the `/run/wow` token bind mount source must be set to the bare repository name (`tokens/<repo>`).
   - If an operator copies `.devcontainer/` from `claude-workbench` rather than deriving from the shared template, they inadvertently carry forward legacy dual mounts (`/run/glunk-identity/dev`), hardcoded `tokens/claude-workbench` paths (violating #1164), devcontainer Features (which fail template verification lint), or `~/.aws` bind mounts (which leak active SSO bearer tokens in violation of `WB-D42`).

4. **Launcher Workspace Isolation Invariants**:
   - In `scripts/identity/wow-driver.ps1` and `scripts/identity/wow-launch-common.ps1`, `Test-DevTree` compares files and bytes between `-Clone` and `-Reference`, and #1164 enforces that `-Reference` matches the origin repository. Without explicit documentation instructing the operator to create a distinct secondary clone (e.g. `<repo>-ref`), operators reuse existing working directories, resulting in launcher crashes or dirty tree rejections.

---

### What changes do you think we should make in order to solve the problem?

Add the complete, self-contained section **`## Adding a repo to this host`** at the end of `docs/identity/DEV-CONTAINER.md`.

```diff
--- a/docs/identity/DEV-CONTAINER.md
+++ b/docs/identity/DEV-CONTAINER.md
@@ -218,3 +218,124 @@ The template's `.github/workflows` (`devcontainer-image.yml`, `architect-review-
 `secret-scan.yml`) are not copied: adding required checks is a ruleset decision for the
 maintainer. This repo has its own gate workflow of the name `architect-review-gate.yml` (#458,
 `WB-D37`), not the template's copy. The Dockerfile header lists what `verify / verify` would enforce, and the
 attestation command to check the pinned digest by hand.
+
+## Adding a repo to this host
+
+Follow this procedure to add a new `glunk-works` repository to a host that already runs the host-identity broker tools (WB-D42, #1163, #1165; linked from cutover issues #406 to #410). Complete every step in exact order before launching container sessions.
+
+An operator can onboard `bounty-infra` and `scope-core` (and subsequent repositories) from this section alone, without reading any other file in this repository.
+
+### 1. Prerequisite: Enforce and read back the approval ruleset
+
+> [!IMPORTANT]
+> **Strict Ordering Rule:** The repository's branch approval ruleset (#406 to #410 cutover) **MUST be live and read back before** the repository is added to `broker.json` or has the dev App installed. The broker keeps an active write token current for every repository listed in `broker.json`; if approvals are at 0, a dev-App write token could merge a green PR or push to the default branch without review.
+
+1. Confirm that the repository's branch ruleset requires pull requests and at least 1 approval before merging.
+2. Read back the ruleset via the GitHub CLI on the host to prove enforcement:
+   ```bash
+   gh api repos/glunk-works/<repo>/rulesets --jq '.[] | select(.target == "branch") | {id: .id, name: .name, enforcement: .enforcement}'
+   ```
+   Verify that the ruleset is in `active` (enforced) status and that bypass actors do not include the dev App.
+
+### 2. Configure the repository's `.devcontainer/` from the template
+
+The repository's `.devcontainer/` must derive from the dev-App flavour of `603-Identity/devcontainers` (migration step 5), not copied from `claude-workbench`.
+
+1. Set the per-repo values to the repository's own bare name (matching its GitHub slug):
+   - In `.devcontainer/devcontainer.json`, declare exactly one token bind mount pointing to `/run/wow`:
+     ```json
+     "mounts": [
+       "source=${localEnv:USERPROFILE}/.config/glunk-identity/tokens/<repo>,target=/run/wow,type=bind,readonly"
+     ]
+     ```
+     *(On Linux/macOS hosts, use `${localEnv:HOME}/.config/glunk-identity/tokens/<repo>` or `${localEnv:WOW_HOME}/tokens/<repo>`)*.
+   - Ensure `name` matches the repository name: `"name": "<repo>"`.
+   - Set `"remoteUser": "app"`.
+   - Do **NOT** declare `/run/glunk-identity/dev` (retired by WB-D42; all shims read `/run/wow/dev-token`).
+   - Do **NOT** declare devcontainer Features (rejected by the template's verification lint).
+   - **Strict AWS Credential Rule (WB-D42):** Do **NOT** bind-mount `~/.aws`. Cached SSO sessions are active bearer tokens. Cloud plan roles execute in CI on read-only roles, and applies run only in CI behind protected Environments or directly on the host.
+2. **Per-repo dispositions:**
+   - `scope-core`: Standard template configuration works as is.
+   - `bounty-infra`: Strip existing devcontainer Features, remove any `~/.aws` bind mounts, and ensure `remoteUser: app`.
+   - `loop-orchestrator`: **Blocked / deferred** (glunk-works/loop-orchestrator#215). Privileged docker-in-docker cannot hold dev App tokens under WB-D24 item 4; cutover waits for session container split.
+
+### 3. Register the repository in host configurations
+
+On the host, add the repository name to both host configuration files:
+
+1. Edit `$WowHome\broker.json` (default: `$HOME\.config\glunk-identity\broker.json`) and append `<repo>` to the `repos` array:
+   ```json
+   {
+     "repos": [
+       "claude-workbench",
+       "<repo>"
+     ]
+   }
+   ```
+2. Edit `$WowHome\review-poll.json` and append `<repo>` to its `repos` array to enable automated background review polling:
+   ```json
+   {
+     "repos": [
+       "claude-workbench",
+       "<repo>"
+     ]
+   }
+   ```
+
+### 4. Re-run `install-host-tools.ps1`
+
+Re-run the host installer from an elevated PowerShell 7.2+ session. This reads the updated `broker.json` and provisions the required token directory under `$WowHome\tokens\<repo>`:
+
+```powershell
+pwsh -File "$env:WOW_HOME\bin\install-host-tools.ps1"
+```
+
+*Verification:* Confirm that directory `$WowHome\tokens\<repo>` exists:
+```powershell
+Test-Path "$env:USERPROFILE\.config\glunk-identity\tokens\<repo>"
+```
+
+### 5. Install GitHub Apps on the repository
+
+In the GitHub Organization settings (`https://github.com/organizations/glunk-works/settings/installations`), install the three standard workflow Apps onto the repository and accept their requested permissions:
+1. **Dev App**: Grants write access to contents, pull requests, issues, and workflows.
+2. **Reviewer App**: Grants access to checks and pull request reviews.
+3. **Loop App**: Grants access to workflow dispatch and automation events.
+
+### 6. Verify token minting with a read-only mint pass
+
+Execute a single, synchronous host broker pass to prove that the broker successfully mints valid dev App tokens for the newly registered repository:
+
+```powershell
+# Run one broker pass on the host:
+pwsh -File "$env:WOW_HOME\bin\broker.ps1" -Once
+```
+
+*Verification:* Confirm that `$WowHome\tokens\<repo>\dev-token` exists, contains a live GitHub installation token (`ghs_...`), and has an unexpired timestamp:
+```powershell
+Get-Content "$env:USERPROFILE\.config\glunk-identity\tokens\<repo>\dev-token"
+```
+
+### 7. Create the `-Reference` clone
+
+The host driver and lane launchers (`wow-driver.ps1`, `wow-lane.ps1`) require a dedicated, untouched reference clone to validate the working tree (`Test-DevTree`) and supply reference models without risking workspace corruption:
+
+```powershell
+# Clone into a distinct directory alongside the working clone:
+git clone git@github.com:glunk-works/<repo>.git C:\work\<repo>-ref
+```
+- The reference clone must remain on the default branch (`main`) with a clean working tree.
+- Development occurs in the primary working clone (e.g., `C:\work\<repo>`).
+
+### 8. Smoke test container startup
+
+Launch the container with the Dev Containers CLI and verify App identity inside:
+
+```bash
+devcontainer up --workspace-folder "C:/work/<repo>"
+docker exec -it <container-id> /usr/local/libexec/dev-token
+docker exec -it <container-id> gh auth status
+```
+Confirm that `gh auth status` reports the active token as an installation token for `glunk-works/<repo>`.
```

---

### What alternative solutions did you explore? (Optional)

1. **Permitting dev App installation before ruleset cutover**:
   - *Explored*: Installing Apps and registering `broker.json` before configuring repository branch protection rulesets.
   - *Why rejected*: Critical security flaw. As noted in `WB-D42`, the host broker mints and maintains high-privilege write tokens (`contents: write`, `pull_requests: write`) in `$WowHome/tokens/<repo>/dev-token`. If approvals are at `0` on the repository's default branch, any container process or background lane with access to that token could push directly or merge PRs without human review. The approval ruleset must be verified first.
2. **Duplicating `claude-workbench`'s `.devcontainer/` into consumer repos**:
   - *Explored*: Manually copying `.devcontainer/` from `claude-workbench` into `bounty-infra` and `scope-core`.
   - *Why rejected*: Per-repo copies lead to configuration drift, cannot be updated via base image tags, and defeat `Test-DevTree` in `wow-launch-common.ps1` (which compares file sets and byte hashes without checking git remote origins, allowing mismatched references to pass undetected per #1161/#1164).
3. **Preserving dual mounts (`/run/glunk-identity/dev` and `/run/wow`)**:
   - *Explored*: Maintaining both paths in consumer repositories.
   - *Why rejected*: `/run/glunk-identity/dev` was an interim migration artifact in `claude-workbench`. All tools, shims (`dev-token`, `gh`), and tests now resolve tokens exclusively at `/run/wow/dev-token`. Consumer repositories must adopt the clean single-mount layout directly.
4. **Mounting `~/.aws` for cloud-dependent repositories (`bedrock-serverless-rag`, `bounty-infra`)**:
   - *Explored*: Allowing read-only bind mounts of host `~/.aws` into containers.
   - *Why rejected*: Violates `WB-D42` invariant. Cached SSO sessions are valid bearer credentials. In accordance with the IaC security rules folded into #406–#408, all plan and apply steps must run in CI behind protected Environments or on the host, never inside the dev container.

---

### What automated tests can you add to prevent this from re-occurring?

Add a POSIX shell test `tests/devcontainer-add-repo-docs.test.sh` to enforce that `docs/identity/DEV-CONTAINER.md` contains the complete "Adding a repo to this host" section, validates all mandatory security checkpoints, and verifies that `bounty-infra` and `scope-core` can be onboarded from the documentation alone:

```sh
#!/bin/sh
# Static documentation assertions for "Adding a repo to this host" (Issue #1165, WB-D42).
# Verifies that docs/identity/DEV-CONTAINER.md contains the complete operator runbook
# with all mandatory security sequencing constraints, host configs, and verification steps.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
doc="$root_dir/docs/identity/DEV-CONTAINER.md"

fail=0
ok() { printf 'ok - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1" >&2; fail=1; }
check() {
  desc=$1; shift
  if "$@"; then ok "$desc"; else bad "$desc"; fi
}

[ -f "$doc" ] || { echo "FAIL - $doc not found" >&2; exit 1; }

# 1. Section Header
check "DEV-CONTAINER.md has '## Adding a repo to this host' header" \
  grep -q "^## Adding a repo to this host" "$doc"

# 2. Strict Ordering Rule: Ruleset verification precedes broker.json & App installation
check "Documents ruleset cutover prerequisite before broker.json entry" \
  grep -q "MUST be live and read back before.*broker.json" "$doc"

check "Documents gh api ruleset read-back verification command" \
  grep -q "gh api repos/glunk-works/<repo>/rulesets" "$doc"

# 3. Per-Repo Template Configuration Invariants
check "Specifies single /run/wow bind mount target" \
  grep -q "target=/run/wow,type=bind,readonly" "$doc"

check "Specifies remoteUser: app" \
  grep -q '"remoteUser": "app"' "$doc"

check "Enforces WB-D42 AWS credential exclusion rule (~/.aws prohibited)" \
  grep -q "Do NOT bind-mount \`~/.aws\`" "$doc"

check "Explicitly rejects legacy /run/glunk-identity/dev mount" \
  grep -q "/run/glunk-identity/dev" "$doc"

# 4. Host Configuration and Tool Execution
check "Documents registration in broker.json" \
  grep -q "broker.json" "$doc"

check "Documents registration in review-poll.json" \
  grep -q "review-poll.json" "$doc"

check "Documents install-host-tools.ps1 rerun" \
  grep -q "install-host-tools.ps1" "$doc"

check "Documents Dev, Reviewer, and Loop App installation" \
  sh -c 'grep -q "Dev App" "$1" && grep -q "Reviewer App" "$1" && grep -q "Loop App" "$1"' _ "$doc"

# 5. Token Mint & Isolation Verification
check "Documents read-only mint test with broker.ps1 -Once" \
  grep -q "broker.ps1.*-Once" "$doc"

check "Documents distinct -Reference clone setup" \
  grep -q "\-Reference" "$doc"

# 6. Consumer Repo Coverage (Done when condition)
check "Specifically covers bounty-infra and scope-core onboarding" \
  sh -c 'grep -q "bounty-infra" "$1" && grep -q "scope-core" "$1"' _ "$doc"

[ "$fail" -eq 0 ] || exit 1
echo "All 'Adding a repo to this host' documentation checks passed."
```