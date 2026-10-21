#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/schema-complete.sh (WB-D17, #142).
#
# Runs the REAL script against real, throwaway `.ai/project.yml`-shaped files built
# from one base fixture (`complete.yml`) with single, targeted edits -- the same
# "one real difference per fixture" discipline plan-anchor.test.sh uses, so a
# failure names exactly which check regressed. `yq` is a hard dependency of the
# script itself (see its header), so this suite needs the real mikefarah `yq` on
# PATH -- the one fixture that needs it ABSENT hides it via a PATH-scoped shim
# directory (`review-base-anchor.test.sh`'s own pattern), never by clearing PATH
# outright, which would also break the POSIX utilities this test script itself
# uses (mkdir, sed, cat).
#
# Permitted toolset: POSIX sh, real `yq` on PATH, `git` (only for the
# check-ref-format shape-check fixtures -- the script's own dependency, not an
# extra one this suite adds). No jq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/plugins/way-of-working/bin/schema-complete.sh"

if ! command -v yq >/dev/null 2>&1; then
  echo "skip - schema-complete.sh fixtures: no yq on PATH" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

assert_eq() {
  desc="$1"; expected="$2"; actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok - $desc"
  else
    echo "FAIL - $desc: expected [$expected], got [$actual]" >&2
    fail=1
  fi
}

run_check() { "$script" check "$1"; }

# --- the base fixture: every required key present and well-formed ----------
base="$tmp/complete.yml"
cat >"$base" <<'EOF'
repo: acme/widgets
pr_base: main
migration_base: null

roadmap: docs/roadmap.md
sprints_dir: sprints
threat_model: docs/roadmap.md

planning:
  kind: files

decisions:
  log: docs/roadmap.md
  prefix: WB-D

backlog:
  kind: github_issues
  repo: null
  path: null
  item_prefix: null

load_bearing_docs:
  - CLAUDE.md

code_paths:
  - src/

gates:
  green:
    - { run: echo ok }

ruleset:
  name: protected
  rule_types: [deletion]
  required_checks: [lint]

review:
  ci_gate: null

agents:
  enabled: [architect]
models:
  architect: opus
  coder: sonnet
  second_opinion: null

orchestration: null

identities: null
EOF

echo "# keys"

expected_keys="repo
pr_base
migration_base
roadmap
sprints_dir
threat_model
planning.kind
decisions.log
decisions.prefix
backlog.kind
backlog.repo
backlog.path
backlog.item_prefix
load_bearing_docs
code_paths
gates.green
agents.enabled
models.architect
models.coder
models.second_opinion
ruleset.name
ruleset.rule_types
ruleset.required_checks
rulesets if-present
lanes if-present
lanes.dir if-map
review.ci_gate
review.ci_gate.check if-map
review.ci_gate.header if-map
review.ci_gate.attestation if-map
review.ci_gate.triggers_on if-map
orchestration
orchestration.critics if-map
orchestration.round_cap if-map
orchestration.human_only_paths if-map
orchestration.restrict_updates if-map
orchestration.loop_identity if-map
identities
identities.maintainer if-map
identities.dev_app if-map
identities.reviewer_app if-map
identities.loop_app if-map"
assert_eq "keys: the exact required path set, conditionals suffixed if-map, optional rulesets and lanes if-present" \
  "$expected_keys" "$("$script" keys)"

echo "# check -- the complete fixture"

assert_eq "check: every required key present and well-formed is complete" \
  "complete" "$(run_check "$base")"

echo "# check -- each nullable key absent (its whole line removed) is 'missing ... nullable'"

f="$tmp/absent_migration_base.yml"; grep -v '^migration_base:' "$base" >"$f"
assert_eq "missing migration_base (line removed entirely)" \
  "incomplete
missing migration_base nullable" "$(run_check "$f")"

f="$tmp/absent_backlog_repo.yml"; sed '/^  repo: null$/d' "$base" >"$f"
assert_eq "missing backlog.repo (line removed entirely)" \
  "incomplete
missing backlog.repo nullable" "$(run_check "$f")"

f="$tmp/absent_second_opinion.yml"; grep -v 'second_opinion:' "$base" >"$f"
assert_eq "missing models.second_opinion (line removed entirely)" \
  "incomplete
missing models.second_opinion nullable" "$(run_check "$f")"

f="$tmp/absent_ci_gate.yml"; grep -v 'ci_gate: null' "$base" >"$f"
assert_eq "missing review.ci_gate (line removed entirely)" \
  "incomplete
missing review.ci_gate nullable" "$(run_check "$f")"

echo "# check -- 'key:' with an empty value, and '~', both parse as null and are legal"

f="$tmp/bare_empty_nullable.yml"; sed 's/^  repo: null$/  repo:/' "$base" >"$f"
assert_eq "backlog.repo: (bare, empty value) is a legal null, same as complete" \
  "complete" "$(run_check "$f")"

f="$tmp/tilde_nullable.yml"; sed 's/^  repo: null$/  repo: ~/' "$base" >"$f"
assert_eq "backlog.repo: ~ is a legal null, same as complete" \
  "complete" "$(run_check "$f")"

echo "# check -- each enum, an out-of-set value is 'invalid', not silently accepted"

f="$tmp/bad_planning_kind.yml"; sed 's/kind: files/kind: bogus/' "$base" >"$f"
assert_eq "planning.kind: bogus is invalid" \
  'incomplete
invalid planning.kind "bogus"' "$(run_check "$f")"

f="$tmp/bad_backlog_kind.yml"; sed 's/kind: github_issues/kind: bogus/' "$base" >"$f"
assert_eq "backlog.kind: bogus is invalid" \
  'incomplete
invalid backlog.kind "bogus"' "$(run_check "$f")"

f="$tmp/bad_models_architect.yml"; sed 's/architect: opus/architect: gpt5/' "$base" >"$f"
assert_eq "models.architect: gpt5 (not a harness model name) is invalid" \
  'incomplete
invalid models.architect "gpt5"' "$(run_check "$f")"

echo "# check -- review.ci_gate: null vs. a map missing triggers_on"

f="$tmp/ci_gate_null.yml"
assert_eq "review.ci_gate: null needs no sub-keys -- complete" \
  "complete" "$(run_check "$base")"

f="$tmp/ci_gate_map_missing_triggers_on.yml"
awk '{ if ($0 == "  ci_gate: null") {
         print "  ci_gate:"; print "    check: architect-review";
         print "    header: h"; print "    attestation: a";
       } else print }' "$base" >"$f"
assert_eq "review.ci_gate as a map without triggers_on: missing that one sub-key" \
  "incomplete
missing review.ci_gate.triggers_on nullable" "$(run_check "$f")"

f="$tmp/ci_gate_map_complete.yml"
awk '{ if ($0 == "  ci_gate: null") {
         print "  ci_gate:"; print "    check: architect-review";
         print "    header: h"; print "    attestation: a";
         print "    triggers_on: null";
       } else print }' "$base" >"$f"
assert_eq "review.ci_gate as a map with all four sub-keys (triggers_on: null) is complete" \
  "complete" "$(run_check "$f")"

f="$tmp/ci_gate_not_a_map.yml"; sed 's/  ci_gate: null/  ci_gate: "yes"/' "$base" >"$f"
assert_eq "review.ci_gate: a bare string (neither null nor a map) is invalid" \
  'incomplete
invalid review.ci_gate "yes"' "$(run_check "$f")"

# Round-2 architect + docs-consistency finding: triggers_on's non-null form is a
# LIST (project-schema.md's own documented example: `triggers_on: [src/]`), not a
# scalar -- the type-tag fix that closed the pr_base/repo gap above briefly
# regressed this by rejecting every !!seq through the shapeless catch-all.
f="$tmp/ci_gate_map_triggers_on_list.yml"
awk '{ if ($0 == "  ci_gate: null") {
         print "  ci_gate:"; print "    check: architect-review";
         print "    header: h"; print "    attestation: a";
         print "    triggers_on: [src/]";
       } else print }' "$base" >"$f"
assert_eq "review.ci_gate.triggers_on: [src/] (a list, the documented non-null form) is complete" \
  "complete" "$(run_check "$f")"

f="$tmp/ci_gate_map_triggers_on_scalar.yml"
awk '{ if ($0 == "  ci_gate: null") {
         print "  ci_gate:"; print "    check: architect-review";
         print "    header: h"; print "    attestation: a";
         print "    triggers_on: src/";
       } else print }' "$base" >"$f"
assert_eq "review.ci_gate.triggers_on: src/ (a scalar, not a list) is invalid" \
  'incomplete
invalid review.ci_gate.triggers_on "src/"' "$(run_check "$f")"

echo "# check -- orchestration (#234): a nullable map like review.ci_gate"

# orch_fixture <out> <body-line>... -- the base fixture with `orchestration: null`
# replaced by `orchestration:` and the given lines (already indented by the caller).
orch_fixture() {
  out="$1"; shift
  { grep -v '^orchestration:' "$base"; echo "orchestration:"; printf '%s\n' "$@"; } >"$out"
}
orch_ok='  critics: [architect, security-critic]
  round_cap: 2
  human_only_paths: [.github/, .ai/]
  restrict_updates: restrict-updates-to-main
  loop_identity: "glunk-loop[bot]"'

f="$tmp/orch_absent.yml"; grep -v '^orchestration:' "$base" >"$f"
assert_eq "orchestration absent entirely is missing, printed as nullable (the interview asks null-or-map)" \
  'incomplete
missing orchestration nullable' "$(run_check "$f")"

assert_eq "orchestration: null is the explicit no-loop answer -- complete (the base fixture)" \
  "complete" "$(run_check "$base")"

f="$tmp/orch_str.yml"; sed 's/^orchestration: null/orchestration: yes-please/' "$base" >"$f"
assert_eq "orchestration: a bare string (neither null nor a map) is invalid" \
  'incomplete
invalid orchestration "yes-please"' "$(run_check "$f")"

f="$tmp/orch_full.yml"; orch_fixture "$f" "$orch_ok"
assert_eq "orchestration: a full map is complete" "complete" "$(run_check "$f")"

f="$tmp/orch_empty_map.yml"; { grep -v '^orchestration:' "$base"; echo "orchestration: {}"; } >"$f"
assert_eq "orchestration: {} reports all five sub-keys missing (absent prompts, loop_identity included)" \
  'incomplete
missing orchestration.critics list
missing orchestration.round_cap int
missing orchestration.human_only_paths list
missing orchestration.restrict_updates nullable
missing orchestration.loop_identity nullable' "$(run_check "$f")"

for k in critics round_cap human_only_paths restrict_updates loop_identity; do
  f="$tmp/orch_no_$k.yml"; orch_fixture "$f" "$orch_ok"; grep -v "^  $k:" "$f" >"$f.2"
  case "$k" in critics|human_only_paths) kind=list ;; round_cap) kind=int ;; loop_identity|restrict_updates) kind=nullable ;; *) kind=value ;; esac
  assert_eq "orchestration.$k removed is missing, kind $kind" \
    "incomplete
missing orchestration.$k $kind" "$(run_check "$f.2")"
done

f="$tmp/orch_loop_null.yml"; orch_fixture "$f" "$orch_ok"; sed 's/^  loop_identity:.*/  loop_identity: null/' "$f" >"$f.2"
assert_eq "orchestration.loop_identity: null (not declared yet; plan 8.13d) is complete" "complete" "$(run_check "$f.2")"

# Empty lists are a control turned off, and a raw spelling the checker's own parse would
# normalize is not what a later `yq` read returns: both must not read complete.
f="$tmp/orch_critics_empty.yml"; orch_fixture "$f" "$orch_ok"; sed 's/^  critics:.*/  critics: []/' "$f" >"$f.2"
assert_eq "orchestration.critics: [] is invalid (no critic could satisfy the floor)" \
  'incomplete
invalid orchestration.critics []' "$(run_check "$f.2")"
f="$tmp/orch_paths_empty.yml"; orch_fixture "$f" "$orch_ok"; sed 's/^  human_only_paths:.*/  human_only_paths: []/' "$f" >"$f.2"
assert_eq "orchestration.human_only_paths: [] is invalid (no path protected)" \
  'incomplete
invalid orchestration.human_only_paths []' "$(run_check "$f.2")"

for v in 0x2 02 +2 1_0 0o7; do
  f="$tmp/orch_cap_raw.yml"; orch_fixture "$f" "$orch_ok"; sed "s/^  round_cap:.*/  round_cap: $v/" "$f" >"$f.2"
  assert_eq "orchestration.round_cap: $v (non-decimal spelling) is not complete" \
    "incomplete" "$(run_check "$f.2" | head -1)"
done

for v in 'restrict-updates-to-main' 'Restrict updates (main)'; do
  f="$tmp/orch_rule_ok.yml"; orch_fixture "$f" "$orch_ok"; sed "s/^  restrict_updates:.*/  restrict_updates: \"$v\"/" "$f" >"$f.2"
  assert_eq "orchestration.restrict_updates: $v is a legal ruleset name (spaces allowed)" "complete" "$(run_check "$f.2")"
done
for v in true 5 '[a]'; do
  f="$tmp/orch_rule_type.yml"; orch_fixture "$f" "$orch_ok"; sed "s/^  restrict_updates:.*/  restrict_updates: $v/" "$f" >"$f.2"
  assert_eq "orchestration.restrict_updates: $v (not a string) is not complete" \
    "incomplete" "$(run_check "$f.2" | head -1)"
done
for v in '' '-x' '--jq=.x' 'a"b'; do
  f="$tmp/orch_rule_bad.yml"; orch_fixture "$f" "$orch_ok"
  awk -v v="$v" 'BEGIN { q = sprintf("%c", 39) } /^  restrict_updates:/ { print "  restrict_updates: " q v q; next } { print }' "$f" >"$f.2"
  assert_eq "orchestration.restrict_updates: [$v] is not complete" "incomplete" "$(run_check "$f.2" | head -1)"
done

for v in '"2"' 0 -1 1000 2.5 '[2]' yes; do
  f="$tmp/orch_cap.yml"; orch_fixture "$f" "$orch_ok"; sed "s/^  round_cap:.*/  round_cap: $v/" "$f" >"$f.2"
  assert_eq "orchestration.round_cap: $v is invalid (a positive integer of at most three digits)" \
    "incomplete
invalid orchestration.round_cap $(printf '%s' "$v" | sed 's/^yes$/"yes"/; s/^2\.5$/2.5/')" "$(run_check "$f.2")"
done
f="$tmp/orch_cap_999.yml"; orch_fixture "$f" "$orch_ok"; sed 's/^  round_cap:.*/  round_cap: 999/' "$f" >"$f.2"
assert_eq "orchestration.round_cap: 999 (three digits) is complete" "complete" "$(run_check "$f.2")"

f="$tmp/orch_cap_null.yml"; orch_fixture "$f" "$orch_ok"; sed 's/^  round_cap:.*/  round_cap: null/' "$f" >"$f.2"
assert_eq "orchestration.round_cap: null is invalid -- a cap with no value is no cap" \
  'incomplete
invalid orchestration.round_cap null' "$(run_check "$f.2")"

f="$tmp/orch_critics_scalar.yml"; orch_fixture "$f" "$orch_ok"; sed 's/^  critics:.*/  critics: architect/' "$f" >"$f.2"
assert_eq "orchestration.critics as a scalar is invalid (a list)" \
  'incomplete
invalid orchestration.critics "architect"' "$(run_check "$f.2")"

f="$tmp/orch_paths_scalar.yml"; orch_fixture "$f" "$orch_ok"; sed 's#^  human_only_paths:.*#  human_only_paths: .github/#' "$f" >"$f.2"
assert_eq "orchestration.human_only_paths as a scalar is invalid (a list)" \
  'incomplete
invalid orchestration.human_only_paths ".github/"' "$(run_check "$f.2")"

echo "# check -- orchestration.restrict_updates: null (WB-D24: nothing to name after a cutover)"

f="$tmp/orch_restrict_null.yml"; orch_fixture "$f" "$orch_ok"; sed 's/^  restrict_updates:.*/  restrict_updates: null/' "$f" >"$f.2"
assert_eq "orchestration.restrict_updates: null is complete (cut over, no restricting ruleset)" \
  "complete" "$(run_check "$f.2")"

# loop_identity's shape: a login, or an App's `<slug>[bot]`. It will be compared with PR
# authors and handed to commands by a later driver, so a flag-shaped, spaced or
# metacharacter-bearing value must not read complete. Single-quoted so the fixture-building
# shell never expands the payload.
for v in 'glunk-loop' 'glunk-loop[bot]' '603-gh-loop' 'a'; do
  f="$tmp/orch_id_ok.yml"; orch_fixture "$f" "$orch_ok"; sed "s/^  loop_identity:.*/  loop_identity: \"$v\"/" "$f" >"$f.2"
  assert_eq "orchestration.loop_identity: $v is a legal login" "complete" "$(run_check "$f.2")"
done
for v in '-loop[bot]' 'loop-' 'a b' 'a$(id)' 'a;b' 'a[bot]x' '[bot]' 'a[bot][bot]' 'a/b' '' 'loop[BOT]' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; do
  f="$tmp/orch_id_bad.yml"; orch_fixture "$f" "$orch_ok"
  awk -v v="$v" 'BEGIN { q = sprintf("%c", 34) } /^  loop_identity:/ { print "  loop_identity: " q v q; next } { print }' "$f" >"$f.2"
  out="$(run_check "$f.2" | head -1)"
  assert_eq "orchestration.loop_identity: [$v] is not complete" "incomplete" "$out"
done

f="$tmp/orch_id_int.yml"; orch_fixture "$f" "$orch_ok"; sed 's/^  loop_identity:.*/  loop_identity: 12345/' "$f" >"$f.2"
assert_eq "orchestration.loop_identity: a bare integer is invalid (a string)" \
  'incomplete
invalid orchestration.loop_identity 12345' "$(run_check "$f.2")"

f="$tmp/orch_id_nl.yml"; orch_fixture "$f" "$orch_ok"
awk '/^  loop_identity:/ { print "  loop_identity: |"; print "    glunk-loop"; next } { print }' "$f" >"$f.2"
assert_eq "orchestration.loop_identity: a block scalar (trailing newline) is invalid, ONE line" \
  'incomplete
invalid orchestration.loop_identity "glunk-loop\n"' "$(run_check "$f.2")"

echo "# check -- a block-scalar value stays a legal single value, and its invalid form stays ONE line"

f="$tmp/block_scalar_ok.yml"
awk '{ if ($0 == "roadmap: docs/roadmap.md") { print "roadmap: |"; print "  line one"; print "  line two"; } else print }' "$base" >"$f"
assert_eq "roadmap as a block scalar is still a legal 'value' key -- complete" \
  "complete" "$(run_check "$f")"

f="$tmp/block_scalar_bad.yml"
awk '{ if ($0 == "  kind: files") { print "  kind: |"; print "    line one"; print "    line two"; } else print }' "$base" >"$f"
assert_eq "a block scalar where an enum is expected is invalid, reported on ONE line" \
  'incomplete
invalid planning.kind "line one\nline two\n"' "$(run_check "$f")"

echo "# check -- the routing-key shape checks"

f="$tmp/bad_repo_shape.yml"; sed 's#repo: acme/widgets#repo: acme#' "$base" >"$f"
assert_eq "repo without a '/' fails the owner/name shape check" \
  'incomplete
invalid repo "acme"' "$(run_check "$f")"

f="$tmp/bad_repo_shape2.yml"; sed 's#repo: acme/widgets#repo: acme/widgets/extra#' "$base" >"$f"
assert_eq "repo with more than one '/' fails the owner/name shape check" \
  'incomplete
invalid repo "acme/widgets/extra"' "$(run_check "$f")"

f="$tmp/bad_backlog_repo_shape.yml"; sed 's/^  repo: null$/  repo: nope/' "$base" >"$f"
assert_eq "backlog.repo (non-null) also gets the owner/name shape check" \
  'incomplete
invalid backlog.repo "nope"' "$(run_check "$f")"

# Round-3 security-critic finding, confirmed live against a real GitHub API call:
# a "." or ".." segment is syntactically owner/name-shaped (one slash, non-empty
# both sides, safe charset) but is a path-traversal token GitHub's own API
# actually walks -- `gh api repos/../user` resolves to `/user`, not a 404.
f="$tmp/backlog_repo_path_traversal.yml"; sed 's/^  repo: null$/  repo: "..\/user"/' "$base" >"$f"
assert_eq 'backlog.repo: "../user" (path traversal, not a real owner) is invalid' \
  'incomplete
invalid backlog.repo "../user"' "$(run_check "$f")"

f="$tmp/repo_path_traversal.yml"; sed 's#repo: acme/widgets#repo: ./x#' "$base" >"$f"
assert_eq 'repo: ./x (a "." segment, not a real owner) is invalid' \
  'incomplete
invalid repo "./x"' "$(run_check "$f")"

# The option-injection shape this check exists to catch (review-base-anchor.sh's
# own header): a value that would reach `git switch` as a FLAG, not a ref, if the
# shape check were skipped.
f="$tmp/bad_pr_base_shape.yml"; sed 's/pr_base: main/pr_base: "-Cmain"/' "$base" >"$f"
assert_eq "pr_base spelled -Cmain (option-injection shape) fails check-ref-format" \
  'incomplete
invalid pr_base "-Cmain"' "$(run_check "$f")"

f="$tmp/bad_migration_base_shape.yml"; sed 's/migration_base: null/migration_base: "-Cmain"/' "$base" >"$f"
assert_eq "migration_base (non-null) also gets the check-ref-format shape check" \
  'incomplete
invalid migration_base "-Cmain"' "$(run_check "$f")"

echo "# check -- the routing keys reject shell metacharacters, not just bad shape"

# A security-critic pass on this script's first version found that neither the
# owner/name split nor a bare check-ref-format round-trip rejects shell
# metacharacters -- `repo: "a/b $(id)"` and `pr_base: "m$(id>&2)"` both read
# `complete`. These four keys are interpolated, unsanitized, into shell command
# templates OTHER skills build at runtime (a branch-cut, `gh pr create --base
# {pr_base}`, a `[ "$R" != "{repo}" ]` comparison) -- `complete` on them must mean
# safe to interpolate, not merely shape-plausible. Single-quoted throughout so
# the fixture-building shell never itself expands the payload.
f="$tmp/repo_shell_injection.yml"
awk '{ if ($0 == "repo: acme/widgets") print "repo: \"a/b $(id)\""; else print }' "$base" >"$f"
assert_eq 'repo containing a command substitution is invalid, not complete' \
  'incomplete
invalid repo "a/b $(id)"' "$(run_check "$f")"

f="$tmp/pr_base_shell_injection.yml"
awk '{ if ($0 == "pr_base: main") print "pr_base: \"m$(id>&2)\""; else print }' "$base" >"$f"
assert_eq 'pr_base containing a command substitution is invalid, not complete' \
  'incomplete
invalid pr_base "m$(id>&2)"' "$(run_check "$f")"

f="$tmp/backlog_repo_shell_injection.yml"
awk '{ if ($0 == "  repo: null") print "  repo: \"evil/x; rm -rf /\""; else print }' "$base" >"$f"
assert_eq 'backlog.repo containing a shell metacharacter (;) is invalid, not complete' \
  'incomplete
invalid backlog.repo "evil/x; rm -rf /"' "$(run_check "$f")"

f="$tmp/migration_base_shell_injection.yml"
awk '{ if ($0 == "migration_base: null") print "migration_base: \"m`id`\""; else print }' "$base" >"$f"
assert_eq 'migration_base containing a backtick command substitution is invalid, not complete' \
  'incomplete
invalid migration_base "m`id`"' "$(run_check "$f")"

f="$tmp/repo_legit_chars.yml"
awk '{
  if ($0 == "repo: acme/widgets") print "repo: acme-org/widgets_v2.0";
  else if ($0 == "migration_base: null") print "migration_base: release/2";
  else print
}' "$base" >"$f"
assert_eq 'legitimate repo/migration_base characters (hyphen, underscore, dot, slash) still pass' \
  "complete" "$(run_check "$f")"

echo "# check -- a trailing newline a shell capture would strip is still caught"

# Round-2 security-critic finding: \$(...) strips every trailing newline BEFORE
# is_safe_chars ever sees the value, so a YAML block scalar (which always ends in
# exactly one trailing newline under clip mode) rendered as a harmless string once
# captured through the shell. The charset check must run INSIDE yq, against the
# file directly, to see the byte it's validating.
f="$tmp/pr_base_block_scalar_trailing_newline.yml"
awk '{ if ($0 == "pr_base: main") { print "pr_base: |"; print "  main" } else print }' "$base" >"$f"
assert_eq 'pr_base as a block scalar (trailing newline a shell capture would strip) is invalid' \
  'incomplete
invalid pr_base "main\n"' "$(run_check "$f")"

echo "# check -- a value cannot forge a row, and a second document cannot add rows (#189)"

# The batched read emits one tab-separated row per key. A security-critic pass on
# the batching found (1) that a verbatim YAML tag `!<...%0A...>` is percent-decoded
# by yq into a real newline, so a hostile value could write a whole forged row for
# another key, leaving `pr_base: "m$(id>&2)"` reading `complete`; and (2) that
# yq runs the expression once PER DOCUMENT, so `---` plus a second document made
# two row sets that each looked fine. The tag is now a closed set inside yq, and
# the rows must match the key table exactly, in order.
f="$tmp/forged_row_via_tag.yml"
awk '{ if ($0 == "pr_base: main") print "pr_base: !<!!str%09true%09%22main%22%0Aroadmap%09value%09-%09true%09!!str> \"m$(id>&2)\""; else print }' "$base" >"$f"
assert_eq 'a percent-encoded tag cannot forge a row that validates a hostile pr_base' \
  'incomplete
invalid pr_base "m$(id>&2)"' "$(run_check "$f")"

f="$tmp/two_documents.yml"
{ cat "$base"; echo '---'; sed 's/^pr_base: main/pr_base: bin\/evil.sh/' "$base"; } >"$f"
assert_eq 'a second YAML document is unreadable, never a second passing row set' \
  "unreadable" "$(run_check "$f")"

f="$tmp/enum_trailing_newline.yml"
awk '{ if ($0 == "  coder: sonnet") { print "  coder: |"; print "    sonnet" } else print }' "$base" >"$f"
assert_eq 'an enum value with a trailing newline is invalid (tightened by #189, was complete)' \
  'incomplete
invalid models.coder "sonnet\n"' "$(run_check "$f")"

f="$tmp/root_sequence.yml"; printf -- '- a\n- b\n' >"$f"
assert_eq 'a root that is a sequence, not a mapping, is unreadable (fail closed)' \
  "unreadable" "$(run_check "$f")"

f="$tmp/aliased_list_keeps_its_value.yml"
awk '{ if ($0 == "code_paths:") { print "cp: &cp [a]"; print "code_paths: *cp" } else if ($0 == "  - src/") { next } else print }' "$base" >"$f"
assert_eq 'an aliased value (empty yq tag) reports its own value, columns do not shift' \
  'incomplete
invalid code_paths ["a"]' "$(run_check "$f")"

echo "# check -- a shape check requires the node to actually BE a string"

# An architect pass on this script's first version found that a shape check
# (owner/name, check-ref-format) ran on yq's plain scalar RENDERING of a value
# without ever confirming that value's own YAML tag was a string -- so
# `pr_base: true` (tag !!bool, renders as the string "true", which
# check-ref-format happily accepts as a ref name) and `repo: [a/b]` (tag !!seq)
# both read `complete`.
f="$tmp/pr_base_not_a_string.yml"
awk '{ if ($0 == "pr_base: main") print "pr_base: true"; else print }' "$base" >"$f"
assert_eq 'pr_base: true (a YAML boolean, not a string) is invalid, not complete' \
  'incomplete
invalid pr_base true' "$(run_check "$f")"

f="$tmp/repo_a_sequence.yml"
awk '{ if ($0 == "repo: acme/widgets") print "repo: [a/b]"; else print }' "$base" >"$f"
assert_eq 'repo: [a/b] (a sequence, not a string) is invalid, not complete' \
  'incomplete
invalid repo ["a/b"]' "$(run_check "$f")"

echo "# check -- a shapeless 'value' key still rejects a map or a sequence"

f="$tmp/roadmap_a_map.yml"
awk '{ if ($0 == "roadmap: docs/roadmap.md") print "roadmap: {a: 1}"; else print }' "$base" >"$f"
assert_eq 'roadmap given as a map (no shape check, but still not a scalar) is invalid' \
  'incomplete
invalid roadmap {"a":1}' "$(run_check "$f")"

echo "# check -- models.second_opinion is validated against the same enum as models.architect/coder"

f="$tmp/second_opinion_bad_model.yml"
awk '{ if ($0 == "  second_opinion: null") print "  second_opinion: not-a-model"; else print }' "$base" >"$f"
assert_eq 'models.second_opinion: not-a-model is invalid, not complete' \
  'incomplete
invalid models.second_opinion "not-a-model"' "$(run_check "$f")"

f="$tmp/second_opinion_good_model.yml"
awk '{ if ($0 == "  second_opinion: null") print "  second_opinion: fable"; else print }' "$base" >"$f"
assert_eq 'models.second_opinion: fable (a real harness model name) is complete' \
  "complete" "$(run_check "$f")"

f="$tmp/good_migration_base_shape.yml"; sed 's/migration_base: null/migration_base: release\/2/' "$base" >"$f"
assert_eq "migration_base a real branch name is valid -- complete" \
  "complete" "$(run_check "$f")"

echo "# check -- a wrong-type list key"

f="$tmp/list_as_scalar.yml"
awk '{ if ($0 == "code_paths:") { print "code_paths: not-a-list" } else if ($0 == "  - src/") { next } else print }' "$base" >"$f"
assert_eq "code_paths given as a scalar, not a list, is invalid" \
  'incomplete
invalid code_paths "not-a-list"' "$(run_check "$f")"

echo "# check -- multiple findings accumulate, one line each, in schema order"

f="$tmp/multi.yml"; grep -v '^migration_base:' "$base" | sed 's/kind: files/kind: bogus/' >"$f"
assert_eq "two independent findings both appear, migration_base before planning.kind" \
  "incomplete
missing migration_base nullable
invalid planning.kind \"bogus\"" "$(run_check "$f")"

echo "# check -- identities (WB-D24, #378): a nullable map like orchestration"

# ident_fixture <out> <body-line>... -- the base fixture with `identities: null`
# replaced by `identities:` and the given lines (already indented by the caller).
ident_fixture() {
  out="$1"; shift
  { grep -v '^identities:' "$base"; echo "identities:"; printf '%s\n' "$@"; } >"$out"
}
ident_ok='  maintainer:
    - { login: some-maintainer, id: 1001 }
  dev_app: { login: "dev-app[bot]", id: 2001 }
  reviewer_app: null
  loop_app: null'

f="$tmp/ident_absent.yml"; grep -v '^identities:' "$base" >"$f"
assert_eq "identities absent entirely is missing, printed as nullable" \
  'incomplete
missing identities nullable' "$(run_check "$f")"

assert_eq "identities: null (not cut over) is complete -- the base fixture" \
  "complete" "$(run_check "$base")"

f="$tmp/ident_str.yml"; sed 's/^identities: null/identities: yes-please/' "$base" >"$f"
assert_eq "identities: a bare string (neither null nor a map) is invalid" \
  'incomplete
invalid identities "yes-please"' "$(run_check "$f")"

f="$tmp/ident_full.yml"; ident_fixture "$f" "$ident_ok"
assert_eq "identities: a full map (one App a pair, the rest null) is complete" "complete" "$(run_check "$f")"

f="$tmp/ident_empty_map.yml"; { grep -v '^identities:' "$base"; echo "identities: {}"; } >"$f"
assert_eq "identities: {} reports all four sub-keys missing" \
  'incomplete
missing identities.maintainer list
missing identities.dev_app nullable
missing identities.reviewer_app nullable
missing identities.loop_app nullable' "$(run_check "$f")"

f="$tmp/ident_no_maintainer.yml"; ident_fixture "$f" "$ident_ok"; grep -v 'maintainer:\|some-maintainer' "$f" >"$f.2"
assert_eq "identities.maintainer removed is missing, kind list" \
  'incomplete
missing identities.maintainer list' "$(run_check "$f.2")"

f="$tmp/ident_maintainer_empty.yml"; ident_fixture "$f" "$ident_ok"
awk '/^  maintainer:/ { print "  maintainer: []"; skip=1; next } skip && /^    - / { next } { skip=0; print }' "$f" >"$f.2"
assert_eq "identities.maintainer: [] is invalid (trusts no one is not a declaration)" \
  'incomplete
invalid identities.maintainer []' "$(run_check "$f.2")"

f="$tmp/ident_app_scalar.yml"; ident_fixture "$f" "$ident_ok"; sed 's/^  reviewer_app:.*/  reviewer_app: a-slug/' "$f" >"$f.2"
assert_eq "identities.reviewer_app: a bare string is invalid (a { login, id } pair or null)" \
  'incomplete
invalid identities.reviewer_app "a-slug"' "$(run_check "$f.2")"

f="$tmp/ident_app_seq.yml"; ident_fixture "$f" "$ident_ok"; sed 's/^  loop_app:.*/  loop_app: [a, b]/' "$f" >"$f.2"
assert_eq "identities.loop_app: a list is invalid" \
  'incomplete
invalid identities.loop_app ["a","b"]' "$(run_check "$f.2")"

echo "# check -- rulesets (WB-D24, #378): an optional extra beside the REQUIRED legacy ruleset"

rulesets_block='rulesets:
  - name: protected
    source: repo
    rule_types: [deletion]
    required_checks: [lint]
  - name: approval
    source: org
    rule_types: [pull_request]'

# the base fixture without its legacy `ruleset:` map
no_legacy() { awk '/^ruleset:/ { skip=1; next } skip && /^  / { next } { skip=0; print }' "$base"; }

assert_eq "no rulesets at all (the old shape) is complete -- the base fixture" \
  "complete" "$(run_check "$base")"

f="$tmp/rs_both.yml"; { cat "$base"; printf '%s\n' "$rulesets_block"; } >"$f"
assert_eq "rulesets beside the legacy ruleset is complete (the new shape for this release)" \
  "complete" "$(run_check "$f")"

f="$tmp/rs_new_only.yml"; { no_legacy; printf '%s\n' "$rulesets_block"; } >"$f"
assert_eq "rulesets WITHOUT the legacy ruleset is incomplete -- no reader understands the list yet" \
  'incomplete
missing ruleset.name value
missing ruleset.rule_types list
missing ruleset.required_checks list' "$(run_check "$f")"

f="$tmp/rs_legacy_partial.yml"; { grep -v '^  required_checks: \[lint\]$' "$base"; printf '%s\n' "$rulesets_block"; } >"$f"
assert_eq "a valid rulesets does not excuse a legacy sub-key that is missing" \
  'incomplete
missing ruleset.required_checks list' "$(run_check "$f")"

f="$tmp/rs_empty.yml"; { cat "$base"; echo 'rulesets: []'; } >"$f"
assert_eq "rulesets: [] is invalid (a repo with no ruleset is not a declaration)" \
  'incomplete
invalid rulesets []' "$(run_check "$f")"

f="$tmp/rs_scalar.yml"; { cat "$base"; echo 'rulesets: protected'; } >"$f"
assert_eq "rulesets: a scalar is invalid (a list)" \
  'incomplete
invalid rulesets "protected"' "$(run_check "$f")"

f="$tmp/rs_null.yml"; { cat "$base"; echo 'rulesets: null'; } >"$f"
assert_eq "rulesets: null is invalid (absent is the old shape; null is not an answer)" \
  'incomplete
invalid rulesets null' "$(run_check "$f")"

echo "# check -- lanes (WB-D34): the second optional key; null or a map with an absolute dir"

lanes_fixture() { { cat "$base"; printf '%s\n' "$1"; } >"$2"; }

assert_eq "lanes absent is complete -- never asked (the base fixture)" \
  "complete" "$(run_check "$base")"

lanes_fixture 'lanes: null' "$tmp/ln_null.yml"
assert_eq "lanes: null is complete (the repo runs no lanes)" \
  "complete" "$(run_check "$tmp/ln_null.yml")"

lanes_fixture 'lanes:
  dir: /tmp/lanes' "$tmp/ln_map.yml"
assert_eq "lanes: { dir: /tmp/lanes } is complete" \
  "complete" "$(run_check "$tmp/ln_map.yml")"

lanes_fixture 'lanes: {}' "$tmp/ln_nodir.yml"
assert_eq "a lanes map without dir is incomplete" \
  'incomplete
missing lanes.dir value' "$(run_check "$tmp/ln_nodir.yml")"

lanes_fixture 'lanes:
  dir: null' "$tmp/ln_nulldir.yml"
assert_eq "lanes.dir: null is invalid (a declared map needs a path)" \
  'incomplete
invalid lanes.dir null' "$(run_check "$tmp/ln_nulldir.yml")"

lanes_fixture 'lanes:
  dir: lanes/work' "$tmp/ln_rel.yml"
assert_eq "a relative lanes.dir is invalid" \
  'incomplete
invalid lanes.dir "lanes/work"' "$(run_check "$tmp/ln_rel.yml")"

for d in '/tmp/../etc' '/tmp/./lanes' '/tmp//lanes' '/tmp/lanes/' '/tmp/..' '/tmp/lanes//'; do
  lanes_fixture "lanes:
  dir: $d" "$tmp/ln_bad.yml"
  assert_eq "lanes.dir $d is invalid (lane.sh's shape rule)" \
    "incomplete
invalid lanes.dir \"$d\"" "$(run_check "$tmp/ln_bad.yml")"
done

lanes_fixture 'lanes:
  dir: "/tmp/a b"' "$tmp/ln_space.yml"
assert_eq "a lanes.dir outside the charset is invalid" \
  'incomplete
invalid lanes.dir "/tmp/a b"' "$(run_check "$tmp/ln_space.yml")"

lanes_fixture 'lanes: /tmp/lanes' "$tmp/ln_scalar.yml"
assert_eq "lanes: a scalar is invalid" \
  'incomplete
invalid lanes "/tmp/lanes"' "$(run_check "$tmp/ln_scalar.yml")"

lanes_fixture 'lanes: [a]' "$tmp/ln_seq.yml"
assert_eq "lanes: a list is invalid" \
  'incomplete
invalid lanes ["a"]' "$(run_check "$tmp/ln_seq.yml")"

echo "# check -- ruleset.name (#451): bound as a value, so only an empty or control-character name is rejected"

# name_fixture <file> <yaml scalar> -- the base fixture with ruleset.name replaced. The scalar
# travels through the environment: awk -v would turn a `\n` escape into a real newline.
name_fixture() { V="$2" awk '/^ruleset:/ { in_rs=1; print; next } in_rs && /^  name:/ { print "  name: " ENVIRON["V"]; in_rs=0; next } { print }' "$base" >"$1"; }
sq="'"
for v in "\"it${sq}s a name\"" "${sq}say \"hi\"${sq}" '"Protected branches (main)"' '"a $(id) `x` ; | & b"' '"-leads-with-dash"' "${sq}back\slash${sq}"; do
  name_fixture "$tmp/rn_ok.yml" "$v"
  assert_eq "ruleset.name: $v is a legal name (bound as a value, not spliced)" "complete" "$(run_check "$tmp/rn_ok.yml")"
done
for v in '""' '"a\nb"' '"a\tb"' '"a\u0007b"' '"a\u0085b"' '"a\rb"'; do
  name_fixture "$tmp/rn_bad.yml" "$v"
  out=$(run_check "$tmp/rn_bad.yml")
  assert_eq "ruleset.name: $v (empty or a control character) is invalid" \
    "incomplete|invalid ruleset.name" "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')"
  assert_eq "ruleset.name: $v is the only finding" "2" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done
for v in true 5 '[a]' null; do
  name_fixture "$tmp/rn_type.yml" "$v"
  assert_eq "ruleset.name: $v (not a string) is not complete" "incomplete" "$(run_check "$tmp/rn_type.yml" | head -1)"
done
awk '/^ruleset:/ { print; print "  name: |-"; print "    first"; print "    second"; skip=1; next } skip && /^  name:/ { skip=0; next } { print }' "$base" >"$tmp/rn_block.yml"
assert_eq "ruleset.name: a multi-line block scalar is invalid, and the only finding" \
  'incomplete
invalid ruleset.name "first\nsecond"' "$(run_check "$tmp/rn_block.yml")"

# rulesets[].name gets the same rule (#451); the rest of an entry's shape is #452's
rs_name_fixture() { { cat "$base"; printf 'rulesets:\n  - name: %s\n    source: repo\n    rule_types: [deletion]\n' "$1"; } >"$2"; }
for v in "\"it${sq}s a name\"" '"a $(id) b"' "${sq}back\slash${sq}"; do
  rs_name_fixture "$v" "$tmp/rsn_ok.yml"
  assert_eq "rulesets[0].name: $v is a legal name" "complete" "$(run_check "$tmp/rsn_ok.yml")"
done
for v in '""' '"a\nb"' '"a\tb"' '"a\u001b[31mb"' '"a\u0085b"' 5 null; do
  rs_name_fixture "$v" "$tmp/rsn_bad.yml"
  out=$(run_check "$tmp/rsn_bad.yml")
  assert_eq "rulesets[0].name: $v is invalid, and the only finding" \
    "incomplete|invalid rulesets[0].name|2" \
    "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done
{ cat "$base"; printf 'rulesets:\n  - name: fine\n    source: repo\n    rule_types: [deletion]\n  - source: org\n    rule_types: [deletion]\n'; } >"$tmp/rsn_missing.yml"
assert_eq "rulesets[1].name: an entry with no name is invalid at its own index" \
  'incomplete
invalid rulesets[1].name null' "$(run_check "$tmp/rsn_missing.yml")"

echo "# check -- identities and rulesets ELEMENTS (#452)"

# ident_with <file> <maintainer-entry> <dev_app value>
ident_with() {
  ident_fixture "$1" "  maintainer:" "    - $2" "  dev_app: $3" "  reviewer_app: null" "  loop_app: null"
}
ok_login='{ login: some-maintainer, id: 1001 }'

ident_with "$tmp/el_ok.yml" "$ok_login" '{ login: "dev-app[bot]", id: 2001 }'
assert_eq "a well-formed maintainer and App is complete" "complete" "$(run_check "$tmp/el_ok.yml")"
ident_with "$tmp/el_ok.yml" '{ login: x, id: 123456789012345 }' '{ login: "a-b[bot]", id: 9 }'
assert_eq "a real-sized id (15 digits) and a one-character login are complete" "complete" "$(run_check "$tmp/el_ok.yml")"

# each rejected maintainer shape, named by index
for m in 'some-login' '[a, b]' 'null' '{}' '{ id: 1 }' '{ login: some-login }' '{ login: some-login, id: "1001" }' \
         '{ login: some-login, id: 0 }' '{ login: some-login, id: -3 }' '{ login: some-login, id: 1.5 }' \
         '{ login: some-login, id: 0x10 }' '{ login: some-login, id: 0123 }' '{ login: some-login, id: true }' \
         '{ login: some-login, id: [1] }' '{ login: 1001, id: 1001 }' '{ login: "", id: 1 }' \
         '{ login: "-lead", id: 1 }' '{ login: "trail-", id: 1 }' '{ login: "a b", id: 1 }' '{ login: "a$(id)", id: 1 }' \
         '{ login: "a[bot", id: 1 }' '{ login: "a\nb", id: 1 }'; do
  ident_with "$tmp/el_bad.yml" "$m" 'null'
  out=$(run_check "$tmp/el_bad.yml")
  assert_eq "identities.maintainer[0]: $m is invalid, and the only finding" \
    "incomplete|invalid identities.maintainer[0]|2" \
    "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done

# id spellings and bounds, login length, and a maintainer that is really an App
for m in '{ login: some-login, id: 1234567890123456 }' '{ login: some-login, id: +5 }' '{ login: some-login, id: 1_000 }' \
         '{ login: some-login, id: 0o17 }' '{ login: some-login, id: 1e3 }' '{ login: "aaaaaaaaaabbbbbbbbbbccccccccccdddddddddde", id: 1 }' \
         '{ login: "dev-app[bot]", id: 1 }' '{ login: "[bot]", id: 1 }'; do
  ident_with "$tmp/el_bad.yml" "$m" 'null'
  out=$(run_check "$tmp/el_bad.yml")
  assert_eq "identities.maintainer[0]: $m is invalid, and the only finding" \
    "incomplete|invalid identities.maintainer[0]|2" \
    "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done
ident_with "$tmp/el_ok.yml" '{ login: "aaaaaaaaaabbbbbbbbbbccccccccccddddddddd", id: 123456789012345 }' 'null'
assert_eq "a 39-character login and a 15-digit id are the largest legal pair" "complete" "$(run_check "$tmp/el_ok.yml")"

# aliases and merge keys are read as the readers read them (explode): the earlier merge source wins
anchors='x-bad: &bad { login: "-bad", id: "7" }
x-good: &good { login: alice, id: 42 }'
alias_fixture() { { grep -v '^identities:' "$base"; printf '%s\n' "$anchors" "identities:" "$@"; } >"$tmp/el_alias.yml"; }
alias_fixture "  maintainer:" '    - { <<: [*bad, *good] }' "  dev_app: null" "  reviewer_app: null" "  loop_app: null"
assert_eq "a merge-key sequence whose first source is malformed is invalid (the reader binds the first)" \
  'incomplete
invalid identities.maintainer[0] {"login":"-bad","id":"7"}' "$(run_check "$tmp/el_alias.yml")"
alias_fixture "  maintainer:" '    - { <<: [*good, *bad] }' "  dev_app: null" "  reviewer_app: null" "  loop_app: null"
assert_eq "a merge-key sequence whose first source is well-formed is complete (the reader binds the first)" \
  "complete" "$(run_check "$tmp/el_alias.yml")"
alias_fixture "  maintainer:" '    - *good' "  dev_app: { <<: [*bad, *good] }" "  reviewer_app: null" "  loop_app: null"
assert_eq "an App read through a malformed merge source is invalid" \
  'incomplete
invalid identities.dev_app {"login":"-bad","id":"7"}' "$(run_check "$tmp/el_alias.yml")"
{ cat "$base"; printf '%s\n' 'x-bad: &rbad { name: "ok", source: evil, rule_types: zz }' 'x-good: &rgood { name: ok, source: repo, rule_types: [x] }' 'rulesets:' '  - { <<: [*rbad, *rgood] }'; } >"$tmp/el_ralias.yml"
assert_eq "a rulesets entry merged from a malformed source is invalid, both fields" \
  'incomplete
invalid rulesets[0].source "evil"
invalid rulesets[0].rule_types "zz"' "$(run_check "$tmp/el_ralias.yml")"

# the index names the bad entry, not the first
ident_fixture "$tmp/el_idx.yml" "  maintainer:" "    - $ok_login" "    - bare-login" "  dev_app: null" "  reviewer_app: null" "  loop_app: null"
assert_eq "identities.maintainer: the finding carries the index of the bad entry" \
  'incomplete
invalid identities.maintainer[1] "bare-login"' "$(run_check "$tmp/el_idx.yml")"

# each App slot
for app in dev_app reviewer_app loop_app; do
  for v in '{}' '{ id: 5 }' '{ login: a }' '{ login: a, id: "5" }' '{ login: a, id: 0 }' '{ login: "a b", id: 5 }'; do
    ident_fixture "$tmp/el_app.yml" "  maintainer:" "    - $ok_login" "  dev_app: null" "  reviewer_app: null" "  loop_app: null"
    sed "s/^  $app: null/  $app: $v/" "$tmp/el_app.yml" >"$tmp/el_app.2.yml"
    out=$(run_check "$tmp/el_app.2.yml")
    assert_eq "identities.$app: $v is invalid, and the only finding" \
      "incomplete|invalid identities.$app|2" \
      "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  done
done
ident_fixture "$tmp/el_app_ok.yml" "  maintainer:" "    - $ok_login" "  dev_app: { login: d, id: 1 }" "  reviewer_app: { login: \"r[bot]\", id: 2 }" "  loop_app: { login: \"l[bot]\", id: 3 }"
assert_eq "all three Apps well-formed is complete" "complete" "$(run_check "$tmp/el_app_ok.yml")"

# identities.dev_app.commit_route (#601, WB-D36): optional, git or api
for v in 'git' 'api' '"git"'; do
  ident_with "$tmp/el_cr.yml" "$ok_login" "{ login: \"dev-app[bot]\", id: 2001, commit_route: $v }"
  assert_eq "commit_route: $v is complete" "complete" "$(run_check "$tmp/el_cr.yml")"
done
ident_with "$tmp/el_cr.yml" "$ok_login" '{ login: "dev-app[bot]", id: 2001 }'
assert_eq "an undeclared commit_route is complete" "complete" "$(run_check "$tmp/el_cr.yml")"
ident_with "$tmp/el_cr.yml" "$ok_login" 'null'
assert_eq "a null dev_app has no commit_route finding" "complete" "$(run_check "$tmp/el_cr.yml")"
for v in 'null' 'yes' 'true' 'Git' '"git "' '1' '[git]' '{ a: b }'; do
  ident_with "$tmp/el_cr.yml" "$ok_login" "{ login: \"dev-app[bot]\", id: 2001, commit_route: $v }"
  out=$(run_check "$tmp/el_cr.yml")
  assert_eq "commit_route: $v is invalid, and the only finding" \
    "incomplete|invalid identities.dev_app.commit_route|2" \
    "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done
ident_with "$tmp/el_cr.yml" "$ok_login" '{ login: "dev-app[bot]", id: 2001, commit_route: null }'
assert_eq "a null commit_route names the offending value" \
  'incomplete
invalid identities.dev_app.commit_route null' "$(run_check "$tmp/el_cr.yml")"

# an element finding is never raised for an identities: null repo, nor stacked on a shape finding
ident_fixture "$tmp/el_shape.yml" "  maintainer: some-login" "  dev_app: null" "  reviewer_app: null" "  loop_app: null"
assert_eq "a maintainer that is not a list is one shape finding, with no element findings" \
  'incomplete
invalid identities.maintainer "some-login"' "$(run_check "$tmp/el_shape.yml")"

# rulesets entries
rs_entry() { { cat "$base"; printf 'rulesets:\n'; printf '%s\n' "$@"; } >"$tmp/rse.yml"; }
rs_entry '  - { name: protected, source: repo, rule_types: [deletion] }' '  - { name: approval, source: org, rule_types: [] }'
assert_eq "rulesets entries with source repo/org and a rule_types list (even empty) are complete" "complete" "$(run_check "$tmp/rse.yml")"
for e in '{ name: a, rule_types: [x] }' '{ name: a, source: bogus, rule_types: [x] }' '{ name: a, source: Repo, rule_types: [x] }' \
         '{ name: a, source: "repo ", rule_types: [x] }' '{ name: a, source: 1, rule_types: [x] }' '{ name: a, source: null, rule_types: [x] }'; do
  rs_entry "  - $e"
  out=$(run_check "$tmp/rse.yml")
  assert_eq "rulesets[0]: $e has a bad source, and that is the only finding" \
    "incomplete|invalid rulesets[0].source|2" \
    "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done
for e in '{ name: a, source: repo }' '{ name: a, source: repo, rule_types: !!seq deletion }' '{ name: a, source: repo, rule_types: deletion }' '{ name: a, source: repo, rule_types: null }' \
         '{ name: a, source: repo, rule_types: { a: 1 } }'; do
  rs_entry "  - $e"
  out=$(run_check "$tmp/rse.yml")
  assert_eq "rulesets[0]: $e has a bad rule_types, and that is the only finding" \
    "incomplete|invalid rulesets[0].rule_types|2" \
    "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done
for e in 'protected' '5' 'null' '[a, b]'; do
  rs_entry "  - $e"
  out=$(run_check "$tmp/rse.yml")
  assert_eq "rulesets[0]: $e (not a map) is invalid as a whole entry, and the only finding" \
    "incomplete|invalid rulesets[0]|2" \
    "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done
rs_entry '  - { name: ok, source: repo, rule_types: [x] }' '  - { name: bad, source: nope, rule_types: x }'
assert_eq "a bad second entry is named by its own index, both fields" \
  'incomplete
invalid rulesets[1].source "nope"
invalid rulesets[1].rule_types "x"' "$(run_check "$tmp/rse.yml")"

# rulesets[].required_checks (#527): absent, null or a list is fine; anything else is invalid
for e in '{ name: a, source: repo, rule_types: [x] }' '{ name: a, source: repo, rule_types: [x], required_checks: [lint, test] }' \
         '{ name: a, source: repo, rule_types: [x], required_checks: [] }' '{ name: a, source: repo, rule_types: [x], required_checks: null }' '{ name: a, source: repo, rule_types: [x], required_checks: ~ }'; do
  rs_entry "  - $e"
  assert_eq "rulesets[0]: $e has a legal required_checks" "complete" "$(run_check "$tmp/rse.yml")"
done
for e in 'lint' '5' 'true' 'false' '0' '{ a: 1 }' '""' '!!s lint' '!!se lint' '! lint' '!!seq lint'; do
  rs_entry "  - { name: a, source: repo, rule_types: [x], required_checks: $e }"
  out=$(run_check "$tmp/rse.yml")
  assert_eq "rulesets[0].required_checks: $e is invalid, and the only finding" \
    "incomplete|invalid rulesets[0].required_checks|2" \
    "$(printf '%s\n' "$out" | sed -n '1p;2p' | cut -d' ' -f1,2 | paste -sd'|')|$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
done
rs_entry '  - { name: ok, source: repo, rule_types: [x], required_checks: [a] }' '  - { name: bad, source: repo, rule_types: [x], required_checks: lint }'
assert_eq "a bad required_checks is named by its own entry's index, with its value" \
  'incomplete
invalid rulesets[1].required_checks "lint"' "$(run_check "$tmp/rse.yml")"

echo "# check -- unreadable: no file, unparseable YAML, yq missing"

assert_eq "a nonexistent file is unreadable" \
  "unreadable" "$(run_check "$tmp/does-not-exist.yml")"

f="$tmp/malformed.yml"; printf 'a: [1,2\n' >"$f"
assert_eq "unparseable YAML is unreadable, never complete or incomplete" \
  "unreadable" "$(run_check "$f")"

# Shadow ONLY yq, by prepending a directory that shadows it ahead of the real
# PATH (review-base-anchor.test.sh's own pattern) -- never by clearing PATH
# outright, which would take the shell's own builtins/utilities with it.
fakebin="$tmp/no-yq-path"
mkdir -p "$fakebin"
cat >"$fakebin/yq" <<'EOF'
#!/bin/sh
echo "yq: not found (test stub)" >&2
exit 127
EOF
chmod +x "$fakebin/yq"
# The shim directory alone (no real PATH behind it) is enough here: `check`
# mode's very first action is `command -v yq`, before it touches the file.
out="$(PATH="$fakebin" "$script" check "$base")"
assert_eq "yq entirely absent from PATH is unreadable, never 'no findings therefore complete'" \
  "unreadable" "$out"

echo "# keys -- needs no yq at all (a pure static table)"

out="$(PATH="$fakebin" "$script" keys)"
assert_eq "keys mode works even with yq absent -- it is a static list, not a YAML read" \
  "$expected_keys" "$out"

exit "$fail"
