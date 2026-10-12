#!/bin/sh
# Fixture tests for scripts/coupling-check.sh.
#
# The gate's whole job is to fail closed, and every bug it has had was a way to
# report a pass over something it never read: #49 (hooks/ outside a hardcoded
# allowlist), and then six more found across two rounds of #53's own critic pass
# -- files at a plugin root unscanned, a whole plugin skipped by a repo-wide
# counter, a trailing newline defeating the exclusion `case`, grep's exit 2 read
# as "no match", an exclusion matching a plugin-root file by name when it is
# justified by type, and dotglob (which alone makes a root .mcp.json visible)
# pinned by nothing. A gate that silently stops gating looks exactly like a gate
# that passed, so the behaviour is pinned here rather than left to convention.
# Each assertion that pins a fix is mutation-checked: reverting that fix must fail
# it. The rest are deliberate controls -- a clean tree, the real exclusions, a
# nested reference/, the working-grep pair, and the App-login controls (generic `[bot]`
# handling, a third-party bot, a reference/ worked example) -- which pin the absence of false
# positives and so have no fix to revert.
# See issue #53.
#
# Each fixture is a throwaway plugins/ tree in a tempdir; the script is run with
# that tree as cwd, which is how CI runs it.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/coupling-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

# A literal from TIER1 -- the pattern set is the script's business, not this
# suite's; these tests are about which paths get looked at at all.
LITERAL='hatch run'

assert_status() {
  desc="$1"
  expected="$2"
  dir="$3"
  actual=0
  ( cd "$dir" && bash "$script" >/dev/null 2>&1 ) || actual=$?
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected exit [$expected], got [$actual]" >&2
    fail=1
  fi
}

tree() {
  d="$tmp/$1"
  mkdir -p "$d/plugins"
  echo "$d"
}

# --- a clean tree passes ----------------------------------------------------
d="$(tree clean)"
mkdir -p "$d/plugins/wow/skills"
echo "portable content" >"$d/plugins/wow/skills/a.md"
assert_status "clean: a portable plugin passes" 0 "$d"

# --- #90: the skill named architect-review is not the check name -------------
# The bare token used to be a TIER1 literal (a consuming repo's check name). The
# pattern now misses the token only after `:`, after `/`, or after `: ` (the three
# contexts the skill's own name occupies: invocation, path, frontmatter) and catches it
# everywhere else. The first fixture pins the three allowed contexts; the next six pin
# placements that must still fail, including the shell-argument shape the plugin
# itself now teaches (`review-gate-state.sh <gate>`), which the first version of this
# pattern missed, and a single-space indent, which the second version missed; the last
# pins the `key: token` gap so the comment's scope claim stays measured. Reverting to
# the bare token fails the first; dropping any one alternative fails at least one of
# the caught set.
d="$(tree skill_name)"
mkdir -p "$d/plugins/wow/skills/architect-review"
printf 'name: architect-review\n# /way-of-working:architect-review <PR>\nsee skills/architect-review/SKILL.md\n' \
  >"$d/plugins/wow/skills/architect-review/SKILL.md"
assert_status "check name: the architect-review skill's own name, invocation and path pass" 0 "$d"

check_name_caught() { # check_name_caught <desc> <line>
  d="$(tree "cn_$(printf '%s' "$1" | tr -c 'a-z0-9' _)")"
  mkdir -p "$d/plugins/wow/skills"
  printf '%s\n' "$2" >"$d/plugins/wow/skills/a.md"
  assert_status "check name: $1 is caught" 1 "$d"
}
check_name_caught "a quoted check name" 'select(.name=="architect-review")'
check_name_caught "a job name derived from the check name" 'wait for the architect-review-runner job'
check_name_caught "the bare token as a shell argument" 'cat gate.tsv | review-gate-state.sh architect-review'
check_name_caught "the bare token in prose" 'the architect-review check is red'
check_name_caught "the bare token at line start" 'architect-review is required'
check_name_caught "the bare token after a single leading space" ' architect-review is required'

# The stated gap: a YAML key's value is the frontmatter's shape, so it cannot be caught
# without catching the frontmatter. A consuming repo's config carries this shape;
# plugin prose has no reason to.
d="$(tree yaml_scalar_gap)"
mkdir -p "$d/plugins/wow/skills"
echo 'check: architect-review' >"$d/plugins/wow/skills/a.md"
assert_status "check name: a YAML key's value is the stated gap and passes" 0 "$d"

# --- #530: an App login is a repo-specific value, whatever its role suffix ----
# TIER2 named the org (`glunk-works`) but not `glunk-<role>[bot]`, so #476's critics found
# `glunk-dev[bot]` in shared skill prose while the gate passed. Dropping TIER4 fails the
# App-login, 603 and GHCR cases; the upper-case, `seuss27` and `Claude-Workbench` cases pin
# the case-insensitive (-i) pass instead. The three controls pin that generic `[bot]` handling, third-party bots and a
# reference/ worked example stay legal.
app_login_caught() { # app_login_caught <desc> <line>
  d="$(tree "app_$(printf '%s' "$1" | tr -c 'a-z0-9' _)")"
  mkdir -p "$d/plugins/wow/skills"
  printf '%s\n' "$2" >"$d/plugins/wow/skills/a.md"
  assert_status "App login: $1 is caught" 1 "$d"
}
app_login_caught "the dev App login" 'push as glunk-dev[bot] when the token is an App'
app_login_caught "the review App login" 'the reviewer is `glunk-review[bot]`'
app_login_caught "an App login not yet minted" 'authored by glunk-triage[bot]'
app_login_caught "a 603 App login" 'push as 603id-dev[bot] when the token is an App'
app_login_caught "the 603 org name" 'clone 603-Identity/devcontainers'
app_login_caught "a lowercase GHCR image path" 'docker pull ghcr.io/603-identity/devcontainer-base'
app_login_caught "an upper-case App login" 'push as Glunk-Dev[bot]'
app_login_caught "a 603 repo name" 'see 603identity-site'

d="$(tree bot_suffix_generic)"
mkdir -p "$d/plugins/wow/skills"
echo 'fold case and a trailing [bot] on both logins before comparing' >"$d/plugins/wow/skills/a.md"
assert_status "App login: generic [bot] suffix handling is not coupling" 0 "$d"

d="$(tree third_party_bot)"
mkdir -p "$d/plugins/wow/skills"
echo 'github-actions[bot] and dependabot[bot] are third-party Apps' >"$d/plugins/wow/skills/a.md"
assert_status "App login: third-party bots with hyphenated logins are not coupling" 0 "$d"

app_login_caught "a lowercase maintainer login" 'ask seuss27 to merge'
app_login_caught "a differently-cased repo name" 'the Claude-Workbench repo'

d="$(tree app_login_in_reference)"
mkdir -p "$d/plugins/wow/reference" "$d/plugins/wow/skills"
echo 'example: glunk-dev[bot]' >"$d/plugins/wow/reference/schema.md"
echo "portable content" >"$d/plugins/wow/skills/a.md"
assert_status "App login: a worked example in reference/ is still allowed" 0 "$d"

# --- the #49 bug: a component directory nobody added to a list --------------
d="$(tree newdir)"
mkdir -p "$d/plugins/wow/commands" "$d/plugins/wow/skills"
echo "$LITERAL" >"$d/plugins/wow/commands/c.md"
# The sibling matters: without a second scannable directory this fixture would
# also fail via the per-plugin guard, and would then still pass if commands/
# were wrongly excluded. The clean sibling keeps the guard quiet so the only
# thing that can fail this case is commands/ actually being read.
echo "portable content" >"$d/plugins/wow/skills/a.md"
assert_status "denylist: a brand-new component directory is scanned" 1 "$d"

# --- files at a plugin's root are plugin content too ------------------------
d="$(tree rootfile)"
mkdir -p "$d/plugins/wow/skills"
echo "portable content" >"$d/plugins/wow/skills/a.md"
# A non-dot name deliberately: this case must prove the `*/` -> `*` glob change
# on its own, independently of dotglob, which the .mcp.json case below covers.
echo "$LITERAL" >"$d/plugins/wow/plugin-notes.md"
assert_status "root file: a literal in a plain plugin-root file is caught" 1 "$d"

# --- the exclusions are real, and only they are ------------------------------
d="$(tree excluded)"
mkdir -p "$d/plugins/wow/reference" "$d/plugins/wow/.claude-plugin" "$d/plugins/wow/skills"
echo "$LITERAL" >"$d/plugins/wow/reference/schema.md"
echo "$LITERAL" >"$d/plugins/wow/.claude-plugin/plugin.json"
echo "portable content" >"$d/plugins/wow/skills/a.md"
assert_status "exclusions: reference/ and .claude-plugin/ may carry literals" 0 "$d"

# The exclusions are justified by what the entry IS, so they must match on type
# as well as name: a plugin-root FILE named `reference` is not documentation.
# Matching on name alone was a green pass over unread content.
d="$(tree named_like_exclusion)"
mkdir -p "$d/plugins/wow/skills"
echo "portable content" >"$d/plugins/wow/skills/a.md"
echo "$LITERAL" >"$d/plugins/wow/reference"
assert_status "exclusions: a plugin-root FILE named reference is still scanned" 1 "$d"

# dotglob is what makes the exclusion `case` a real decision rather than an
# accident -- without it the glob never yields dot-entries at all, so
# .claude-plugin/ would be skipped for the wrong reason and a dot-named root
# file (.mcp.json carries MCP server commands) would never be scanned.
d="$(tree dotfile)"
mkdir -p "$d/plugins/wow/skills"
echo "portable content" >"$d/plugins/wow/skills/a.md"
echo "$LITERAL" >"$d/plugins/wow/.mcp.json"
assert_status "dotglob: a literal in a plugin-root .mcp.json is caught" 1 "$d"

# A reference/ nested BELOW a component dir is not the documentation exclusion
# -- the exclusion is by name at depth 1 only.
d="$(tree nested_reference)"
mkdir -p "$d/plugins/wow/skills/reference"
echo "$LITERAL" >"$d/plugins/wow/skills/reference/a.md"
assert_status "exclusions: a nested reference/ is still scanned" 1 "$d"

# --- a plugin the gate never looked at is not a pass ------------------------
# One repo-wide counter used to let any single scannable directory anywhere
# satisfy the guard, so this second plugin passed green.
d="$(tree unscanned_plugin)"
mkdir -p "$d/plugins/good/skills" "$d/plugins/second/reference"
echo "portable content" >"$d/plugins/good/skills/a.md"
echo "docs" >"$d/plugins/second/reference/r.md"
assert_status "per-plugin: a plugin with nothing scannable fails the gate" 1 "$d"

# --- nothing to scan at all is a failure, not a pass ------------------------
d="$(tree empty)"
assert_status "empty: a plugins/ tree with no plugins fails" 1 "$d"

d="$tmp/noplugins"
mkdir -p "$d"
assert_status "missing: no plugins/ tree at all fails" 1 "$d"

# --- the exclusion compares the name actually used --------------------------
# $(basename ...) strips trailing newlines, so `reference<LF>` compared equal to
# `reference` and was skipped. A newline is a legal path character in git, so
# that was a committable bypass. Skipped where the filesystem will not hold such
# a name (Windows transliterates it), because there the bypass is unreachable.
d="$(tree newline_name)"
mkdir -p "$d/plugins/wow/skills"
echo "portable content" >"$d/plugins/wow/skills/a.md"
NL='
'
nl_dir="$d/plugins/wow/reference$NL"
mkdir "$nl_dir" 2>/dev/null || true
# Only assert if the filesystem really produced that name. Windows transliterates
# the newline to a lookalike codepoint, which makes the bypass unreachable there
# and the fixture meaningless -- so verify the name before trusting it.
nl_real=0
for entry in "$d/plugins/wow/"*; do
  [ "${entry##*/}" = "reference$NL" ] && nl_real=1
done
if [ "$nl_real" -eq 1 ]; then
  echo "$LITERAL" >"$nl_dir/e.md"
  assert_status "newline: 'reference<LF>' does not hit the exclusion" 1 "$d"
else
  rm -rf "$nl_dir"
  echo "ok - newline: skipped, filesystem will not hold the name"
fi

# --- a grep that errors must not read as "clean" ----------------------------
# The old `if hits=$(grep ...)` form took grep's exit 2 (a real error: unreadable
# file, I/O error) down the same branch as exit 1 (clean), so the gate reported a
# pass over a tree it could not read. Forcing a genuine grep error from a
# committable fixture is platform-dependent, so the error is injected instead:
# a stub grep earlier on PATH that always exits 2. The script must fail.
stub="$tmp/stub"
mkdir -p "$stub"
printf '#!/bin/sh\nexit 2\n' >"$stub/grep"
chmod +x "$stub/grep"

d="$(tree greperr)"
mkdir -p "$d/plugins/wow/skills"
echo "portable content" >"$d/plugins/wow/skills/a.md"
actual=0
( cd "$d" && PATH="$stub:$PATH" bash "$script" >/dev/null 2>&1 ) || actual=$?
if [ "$actual" -eq 1 ]; then
  echo "ok - grep: an erroring grep fails the gate instead of reading as clean"
else
  echo "FAIL - grep: expected exit [1] when grep errors, got [$actual]" >&2
  fail=1
fi

# The case-insensitive pass has its own exit-status branch: a grep that errors only when
# given -i (the case-insensitive pass) must fail the gate too, not just one that always errors.
real_grep="$(command -v grep)"
stub2="$tmp/stub2"
mkdir -p "$stub2"
cat >"$stub2/grep" <<EOF
#!/bin/sh
case "\$1" in *i*) exit 2 ;; esac
exec "$real_grep" "\$@"
EOF
chmod +x "$stub2/grep"
d2="$(tree greperr_ci)"
mkdir -p "$d2/plugins/wow/skills"
echo "portable content" >"$d2/plugins/wow/skills/a.md"
actual=0
( cd "$d2" && PATH="$stub2:$PATH" bash "$script" >/dev/null 2>&1 ) || actual=$?
if [ "$actual" -eq 1 ]; then
  echo "ok - grep: an erroring case-insensitive pass fails the gate instead of reading as clean"
else
  echo "FAIL - grep: expected exit [1] when only the -i pass errors, got [$actual]" >&2
  fail=1
fi

# The same tree with the real grep must pass -- otherwise the case above proves
# nothing about grep's exit status.
assert_status "grep: the same tree passes with a working grep" 0 "$d"

exit "$fail"
