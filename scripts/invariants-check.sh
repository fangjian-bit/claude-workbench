#!/usr/bin/env bash
# The regression gate: the invariants that have already been got wrong, in prose.
#
# This repo's skills describe MECHANICAL procedures in English, and English has no
# compiler. Every check below exists because the described procedure shipped wrong at
# least once -- twice, in the first case -- and nothing in `lint` or `coupling` could
# have caught it. A grep cannot prove a procedure is right; it can stop a specific
# known-wrong form from coming back, which is exactly what happened here.
#
# Adding a check: it must correspond to a defect that actually shipped. Speculative
# invariants belong in the skill's own prose, not in a gate.
set -euo pipefail

fail=0
# Appendices are prose a session is told to read on demand; they carry the same procedures.
SKILLS=(plugins/*/skills/*/SKILL.md plugins/*/skills/*/appendices/*.md)
AGENTS=(plugins/*/agents/*.md)
BIN_SCRIPTS=(plugins/*/bin/*.sh)
HOOK_SCRIPTS=(plugins/*/hooks/*.sh)
REFERENCE_DOCS=(plugins/*/reference/*.md)

report() {
  echo "INVARIANT FAIL: $1" >&2
  shift
  printf '%s\n' "$@" >&2
  fail=1
}

# --- 1. Cursor freshness is compared by CONTENT, never by commit range -------------
#
# `git diff A..HEAD` and `git rev-list --count A..HEAD` are commit RANGES, and a range
# only means what you want when A is an ancestor of HEAD. Under squash-merge -- this
# project's default -- the recorded `last_commit` frequently never becomes an ancestor
# of the base branch at all, so a range-based check fails closed forever. Shipped wrong
# in v0.3.0 (SHA equality) and again in v0.4.0 (the range form); see WB-D7.
#
# The classifier itself now lives in plugins/*/bin/cursor-drift.sh (issue #21) rather
# than in skill prose, so this scans that script too -- it is where the bug would
# actually regress. tests/cursor-drift.test.sh is the authoritative behavioral guard
# (a fixture, not a regex, catches a wrong answer the regex's shape doesn't cover);
# this stays as a cheap, independent static check on top of it.
#
# Comments are stripped first ON PURPOSE: cursor-drift.sh's own comment carries
# `# TWO arguments -- never <last_commit>..HEAD`, which is the warning against this
# exact mistake and must not trip the gate that enforces it. Same reasoning as the
# coupling check's note about check names in illustrative output.
# Per file, not over a concatenated stream, so a hit names the file it is in.
range_hits=""
for f in "${SKILLS[@]}" "${AGENTS[@]}" "${BIN_SCRIPTS[@]}"; do
  h=$(sed 's/#.*//' "$f" | grep -nE 'git (diff|rev-list).*last_commit[^ ]*\.\.' || true)
  [ -n "$h" ] && range_hits+="  $f:$h"$'\n'
done
if [ -n "$range_hits" ]; then
  report "cursor freshness compared by commit range, not content" \
    "$range_hits" \
    "Use a TWO-ARGUMENT diff -- 'git diff --name-only <last_commit> HEAD' -- which" \
    "compares trees and survives squash-merge. See docs/decisions.md WB-D7."
fi

# --- 2. `gh auth status` is never parsed ------------------------------------------
#
# It reports token SCOPE, and scope is not reach: an account with no membership in the
# owning org can advertise a broader scope list than the one that actually works, so it
# prints green while reach is zero. The question a skill actually wants is answered by
# `gh api repos/OWNER/REPO --jq .permissions`. Mentioning the command in prose (to warn
# against it) is fine; piping or capturing its output is the defect. See issue #13.
auth_hits=$(grep -nE 'gh auth status[^`]*(\||\$\()' "${SKILLS[@]}" "${AGENTS[@]}" || true)
if [ -n "$auth_hits" ]; then
  report "'gh auth status' output is being parsed" \
    "$auth_hits" \
    "Scope is not reach. Ask the repo what the token can do:" \
    "  gh api repos/{repo} --jq .permissions"
fi

# --- 2b. A config value is bound to jq, never spliced into its argument ------------
#
# `jq --arg n '{ruleset.name}'` fills a repo-controlled value into single-quoted shell text.
# Once a name may legally contain `'` or `$` (#451), that form closes the quote (and a
# double-quoted one runs `$(...)`), so both quote styles and the bare form are caught. A value is read into
# a variable and passed as `--arg n "$VAR"`. Shipped wrong in resume's ruleset check.
Q="'"
splice_hits=$(grep -nE -- "--arg(json)? +[A-Za-z_]+ +[\"$Q]?[^\" $Q$]*\{[A-Za-z_.]+\}" "${SKILLS[@]}" || true)
if [ -n "$splice_hits" ]; then
  report "a config value is spliced into a jq --arg argument" \
    "$splice_hits" \
    "Read the value into a variable and bind it:" \
    "  bind it as resume's ruleset check does: read it into a variable, then jq --arg n \"\$VAR\" ..."
fi

# --- 3. The reach check precedes the ruleset call in /resume ----------------------
#
# An identity that cannot see a ruleset gets 404, NOT 403 -- so the ruleset preflight
# reads "that ruleset does not exist", which is indistinguishable from the security
# finding it exists to raise and points the wrong way. The reach call is only useful
# BEFORE the call whose answer it qualifies. Ordering, not presence, is the invariant.
RESUME=$(printf '%s\n' "${SKILLS[@]}" | grep '/resume/SKILL.md$' || true)
if [ -n "$RESUME" ]; then
  # `|| true` is load-bearing: under `set -o pipefail` a grep that legitimately finds
  # nothing kills the script, and `set -e` makes that a SILENT exit -- a gate that dies
  # quietly reports the same "nothing to see" as a gate that passed. Caught by running
  # the deliberate regression below rather than by reading the code.
  reach=$(grep -n 'gh api repos/{repo} --jq .permissions' "$RESUME" | head -1 | cut -d: -f1 || true)
  # The ruleset call is written `gh api --paginate repos/{repo}/rules/branches/...`, so
  # flags sit between `gh api` and the path and the pattern must tolerate any number of
  # them. The first version required `gh api repos/...` adjacent and never matched the
  # real call, leaving the ordering half of this check a silent no-op (#162). The `gh api`
  # prefix stays so a line that merely names the path (an echo, a sentence) is not taken
  # for the call. Known looseness: any words between `gh api` and the path are accepted,
  # and a quoted path or a tab after `gh api` does not match -- that fails loudly below.
  ruleset=$(grep -nE 'gh api( +[^ ]+)* +repos/\{repo\}/rules/branches' "$RESUME" | head -1 | cut -d: -f1 || true)
  if [ -z "$reach" ]; then
    report "/resume has no repo-reach preflight" \
      "  expected: gh api repos/{repo} --jq .permissions" \
      "Without it, a 404 from the ruleset call cannot be told from 'wrong identity'."
  elif [ -z "$ruleset" ]; then
    report "/resume's ruleset call could not be found" \
      "  expected: gh api [flags] repos/{repo}/rules/branches/..." \
      "The ordering check can't run without it -- a silent pass here is worse than a" \
      "loud one. If the call was reworded, update this anchor to match, deliberately."
  elif [ "$reach" -gt "$ruleset" ]; then
    report "/resume checks the ruleset before establishing reach" \
      "  reach check at line $reach, ruleset call at line $ruleset" \
      "The reach call must come FIRST -- it is what makes the ruleset result mean anything."
  fi
fi

# --- 4. /handoff guards WHOSE sprint it is before it determines the new cursor -----
#
# Handoff regenerates .ai/state.json and .ai/next-steps.md WHOLESALE (its *Write
# `.ai/state.json`* and *Regenerate `.ai/next-steps.md`* steps), so
# a handoff for work on some other sprint overwrites the cursor's sprint's in-flight
# state, with nothing left to restore it from. Shipped wrong: the guard-less prose ran in
# a consuming repo, whose cursor-sync PR would have done exactly that over a `blocked`
# sprint and was closed instead -- the evidence WB-D12 records, and the reason
# /way-of-working:park-sprint exists. The fix is a guard that names that way out BEFORE
# the step that decides the new cursor. As with check 3, ordering is the invariant, not
# presence: a guard after the rewrite guards nothing. Issue #89.
#
# The guard is matched by its own bullet, not by any mention of park-sprint: a mention in
# the frontmatter description would pin the first hit above the fold forever, and the
# guard could then be deleted without tripping the gate. Rewording the bullet means
# updating this pattern deliberately -- say so in the commit.
#
# `rewrite` is anchored to the numbered HEADING itself (a list item whose bold text is
# exactly "Determine the new cursor"), not a bare substring search: since issue #61's
# name-based step references (check 6, below), the step's own name is legitimately cited
# in prose earlier in the file too (the sprint-guard paragraph above it does exactly
# that), and a bare substring search would grab the first such mention instead of the
# heading -- reporting "determines before guarding" for a file where the guard is
# correctly first. The number itself is not pinned -- `[0-9]+` matches whatever position
# the step currently holds, so renumbering does not retrigger this note.
HANDOFF=$(printf '%s\n' "${SKILLS[@]}" | grep '/handoff/SKILL.md$' || true)
if [ -n "$HANDOFF" ]; then
  guard=$(grep -nF '**Park the cursor'"'"'s sprint first**' "$HANDOFF" | head -1 | cut -d: -f1 || true)
  rewrite=$(grep -nE '^[0-9]+\.[[:space:]]+\*\*Determine the new cursor\*\*' "$HANDOFF" | head -1 | cut -d: -f1 || true)
  if [ -z "$guard" ]; then
    report "/handoff has no parked-sprint guard" \
      "  expected: a '**Park the cursor's sprint first**' way out before 'Determine the new cursor'" \
      "Without it a handoff for another sprint's work overwrites the cursor's in-flight state."
  elif [ -z "$rewrite" ]; then
    report "/handoff's 'Determine the new cursor' heading could not be found" \
      "  expected a numbered list item whose bold text is exactly 'Determine the new cursor'" \
      "The ordering check below can't run without it -- a silent pass here is worse than a" \
      "loud one. If the step was renamed, update this anchor to match, deliberately."
  elif [ "$guard" -gt "$rewrite" ]; then
    report "/handoff determines the new cursor before guarding whose sprint it is" \
      "  park guard at line $guard, 'Determine the new cursor' at line $rewrite" \
      "The guard must come FIRST -- a wholesale rewrite has already lost the state it guards."
  fi
fi

# --- 5. The two prune-block copies stay byte-identical ----------------------------
#
# docs/decisions.md asserts the branch-prune block in resume/SKILL.md and
# archive-sprint/SKILL.md is byte-identical, and a future bin/ extraction of that block
# depends on it staying that way. Nothing enforced it: #60 roughly doubled the block's
# intricacy, and three critic rounds each verified parity BY HAND -- the third round
# flagged the invariant as prose-only. A hand check repeated every round is the
# definition of something to mechanize. See issue #62.
extract_prune_block() {
  local file="$1" hit fence_start fence_end
  hit=$(grep -n 'base=\$(yq -r \.pr_base' "$file" | head -1 | cut -d: -f1 || true)
  [ -n "$hit" ] || return 1
  fence_start=$(head -n "$hit" "$file" | grep -n '^ *```bash$' | tail -1 | cut -d: -f1 || true)
  fence_end=$(tail -n "+$((hit + 1))" "$file" | grep -n '^ *```$' | head -1 | cut -d: -f1 || true)
  [ -n "$fence_start" ] && [ -n "$fence_end" ] || return 1
  # fence_end here is a line number in the tail STREAM, whose line 1 is file line
  # hit+1 -- so file_line = hit + stream_line, not hit + stream_line - 1. Getting
  # this wrong silently drops the block's last line (its closing `fi`) from the
  # comparison, which is exactly the shape of divergence this check exists to catch.
  fence_end=$((hit + fence_end))
  sed -n "$((fence_start + 1)),$((fence_end - 1))p" "$file"
}
RESUME_FILE=$(printf '%s\n' "${SKILLS[@]}" | grep '/resume/SKILL.md$' || true)
ARCHIVE_FILE=$(printf '%s\n' "${SKILLS[@]}" | grep '/archive-sprint/SKILL.md$' || true)
if [ -z "$RESUME_FILE" ] || [ -z "$ARCHIVE_FILE" ]; then
  report "could not find resume/SKILL.md and/or archive-sprint/SKILL.md to compare" \
    "  resume: ${RESUME_FILE:-<not found>}" \
    "  archive-sprint: ${ARCHIVE_FILE:-<not found>}" \
    "A rename or move here would otherwise silently turn this check off."
else
  resume_block=$(extract_prune_block "$RESUME_FILE" || true)
  archive_block=$(extract_prune_block "$ARCHIVE_FILE" || true)
  if [ -z "$resume_block" ] || [ -z "$archive_block" ]; then
    report "could not locate the prune block in resume and/or archive-sprint" \
      "  expected a fenced bash block containing 'base=\$(yq -r .pr_base' in both files"
  elif [ "$resume_block" != "$archive_block" ]; then
    diff_out=$(diff <(printf '%s\n' "$resume_block") <(printf '%s\n' "$archive_block") || true)
    report "the two prune-block copies have diverged" \
      "$(printf '%s\n' "$diff_out" | sed 's/^/  /')" \
      "resume/SKILL.md and archive-sprint/SKILL.md must carry byte-identical prune" \
      "blocks -- see docs/decisions.md and issue #62."
  fi
fi

# --- 6. A skill step is cited by name, never by position ---------------------------
#
# Skill steps are referenced by position (the word "step" or "steps" followed by a
# number), so inserting a step silently breaks every reference to the ones after it --
# including references in OTHER files, which the person doing the renumbering never sees.
# Shipped wrong repeatedly: a recount during Sprint 2 planning found the form in 66 places
# across 15 files, up from 34 across 8 when first raised, because nothing stopped it from
# coming back. The fix, approved 2026-09-23: cite a step by its own bolded name in prose
# (e.g. "the *Prune squash-merged local branches* step"), with no exception for a
# reference to a step within the SAME file -- a single rule with no exceptions is
# checkable by grep, and "except when it's the same file" is not.
#
# The pattern covers three shapes, not just "step N": "step 5", "steps 3 and 4" (a plural
# citing more than one position), and "step-5" (a hyphenated form). The first version of
# this check only caught the singular space-separated form and shipped with a live plural
# ("steps 3 and 4") and a live hyphenated one ("step-5") still in the tree, caught only by
# a critic pass reviewing the very PR that added this check -- exactly the shape of defect
# this check exists to make impossible. No left word-boundary is enforced, so a real
# compound like "lockstep 2" would also match; no such text exists in this plugin's prose
# today, and a false positive here just means an unnecessary rename, never a missed one.
#
# Comments are NOT stripped here, unlike check 1 -- a bin/ script's own comment is exactly
# where a cross-file "step N" reference tends to live (it is prose describing another
# skill's procedure, not code), so it must count. Scanned over every prose surface this
# plugin ships: skills, agents, bin/ and hooks/ scripts, and reference/ -- docs/decisions.md
# is a historical log of decisions as they read AT THE TIME and is intentionally out of
# scope; rewriting its past tense would misrepresent what was actually approved when.
step_hits=""
for f in "${SKILLS[@]}" "${AGENTS[@]}" "${BIN_SCRIPTS[@]}" "${HOOK_SCRIPTS[@]}" "${REFERENCE_DOCS[@]}"; do
  h=$(grep -inE 'steps?[-[:space:]]*#?[0-9]+' "$f" || true)
  [ -n "$h" ] && step_hits+="  $f:"$'\n'"$(printf '%s\n' "$h" | sed 's/^/    /')"$'\n'
done
if [ -n "$step_hits" ]; then
  report "a skill step is cited by number, not by name" \
    "$step_hits" \
    "Cite the step's own bolded name instead, e.g. 'the *Prune squash-merged local" \
    "branches* step' -- never a number, including within the same file. See issue #61."
fi

# --- 7. WB-D17 (#142): the completeness checker's key set, the doc's own examples,
#        and this repo's own file all agree ---------------------------------------
#
# `.ai/project.yml`'s schema doc (`project-schema.md`) and its completeness checker
# (`bin/schema-complete.sh`) are two independent surfaces describing the SAME key
# set, and nothing forced them to agree until now -- exactly the "documented but
# not enforced" gap that let this repo run two sprints on an undeclared
# `planning.kind` while behaving like `github_milestones`, the defect `#142` exists
# to close for every key, not just that one.
#
# `yq` (mikefarah v4) is a hard dependency of this assertion, same as of
# `schema-complete.sh` itself, and its absence FAILS the check -- it does not skip
# it. A required gate that silently skips its own enforcement on a missing tool is
# the same defect as any other silent pass.
SCHEMA_COMPLETE_SCRIPT=$(printf '%s\n' "${BIN_SCRIPTS[@]}" | grep '/schema-complete\.sh$' || true)
SCHEMA_DOC=$(printf '%s\n' "${REFERENCE_DOCS[@]}" | grep '/project-schema\.md$' || true)
if [ -z "$SCHEMA_COMPLETE_SCRIPT" ] || [ -z "$SCHEMA_DOC" ]; then
  report "could not find bin/schema-complete.sh and/or reference/project-schema.md" \
    "  schema-complete.sh: ${SCHEMA_COMPLETE_SCRIPT:-<not found>}" \
    "  project-schema.md: ${SCHEMA_DOC:-<not found>}" \
    "A rename or move here would otherwise silently turn this check off."
elif ! command -v yq >/dev/null 2>&1; then
  report "yq is not on PATH -- WB-D17's schema-completeness assertions cannot run" \
    "bin/schema-complete.sh and this check both require mikefarah yq v4. A CI runner" \
    "missing it must fail this gate, not silently skip the assertions it backs."
else
  extract_yaml_fence() { # extract_yaml_fence <heading-prefix> <file>
    awk -v heading="$1" '
      $0 ~ "^"heading { found=1 }
      found && /^```yaml/ { infence=1; next }
      found && infence && /^```/ { exit }
      found && infence { print }
    ' "$2"
  }
  # NOTE: this walk descends into maps, so neither example may show a populated {login, id}
  # pair for identities.*_app (it would surface as doc-only identities.dev_app.login keys);
  # the populated form lives in the un-walked § `identities` fence.
  walk_leaf_paths() { # walk_leaf_paths <yaml-file> -- dotted leaf paths, stopping at sequences
    yq eval '.. | select(tag != "!!map") | (path | join("."))' "$1" 2>/dev/null \
      | grep -vE '(^|\.)[0-9]+(\.|$)' || true
  }

  full_tmp=$(mktemp)
  worked_tmp=$(mktemp)
  extract_yaml_fence "## Full schema" "$SCHEMA_DOC" >"$full_tmp"
  extract_yaml_fence "## Worked example" "$SCHEMA_DOC" >"$worked_tmp"

  if [ ! -s "$full_tmp" ] || [ ! -s "$worked_tmp" ]; then
    report "could not extract a yaml fence for 'Full schema' and/or 'Worked example'" \
      "  Full schema fence: $([ -s "$full_tmp" ] && echo found || echo empty)" \
      "  Worked example fence: $([ -s "$worked_tmp" ] && echo found || echo empty)" \
      "Expected a \`\`\`yaml fence directly under each heading in $SCHEMA_DOC."
  else
    # 7a. Set equality, both ways -- the script's keys (any if-* suffix stripped)
    # against the union of both examples' own leaf paths. The Full schema alone
    # cannot supply the four `review.ci_gate.*` sub-keys (it keeps `ci_gate: null`
    # there deliberately, so a plain walk finds none of them); the Worked example
    # carries `ci_gate` as a live map precisely so the union supplies all four.
    script_keys=$("$SCHEMA_COMPLETE_SCRIPT" keys | sed 's/ if-[a-z-]*$//' | sort -u)
    doc_keys=$( { walk_leaf_paths "$full_tmp"; walk_leaf_paths "$worked_tmp"; } | sort -u)
    doc_only=$(comm -23 <(printf '%s\n' "$doc_keys") <(printf '%s\n' "$script_keys"))
    script_only=$(comm -13 <(printf '%s\n' "$doc_keys") <(printf '%s\n' "$script_keys"))
    if [ -n "$doc_only" ] || [ -n "$script_only" ]; then
      report "bin/schema-complete.sh's key set and project-schema.md's own examples disagree" \
        "${doc_only:+  in the doc, not in the script:
$doc_only}" \
        "${script_only:+  in the script, not in the doc:
$script_only}" \
        "A key added to one must be added to the other in the same change" \
        "(project-schema.md § 'Adding a key')."
    fi

    # 7b. Both documented examples themselves check complete.
    for label_file in "Full schema:$full_tmp" "Worked example:$worked_tmp"; do
      label="${label_file%%:*}"; f="${label_file#*:}"
      verdict=$("$SCHEMA_COMPLETE_SCRIPT" check "$f" | head -1)
      if [ "$verdict" != complete ]; then
        report "project-schema.md's '$label' example is not schema-complete" \
          "$("$SCHEMA_COMPLETE_SCRIPT" check "$f")" \
          "Both documented examples must be a clean, complete path through the schema."
      fi
    done

    # 7c. This repo's own .ai/project.yml is complete -- e.g. `migration_base: null`
    # must land in the SAME PR as a change that adds a key, or the build fails its
    # own gate before it can merge.
    if [ -f .ai/project.yml ]; then
      own_verdict=$("$SCHEMA_COMPLETE_SCRIPT" check .ai/project.yml | head -1)
      if [ "$own_verdict" != complete ]; then
        report "this repo's own .ai/project.yml is not schema-complete" \
          "$("$SCHEMA_COMPLETE_SCRIPT" check .ai/project.yml)" \
          "Every dotted key path in the schema must be present here too -- see" \
          "project-schema.md's 'When it is missing or unreadable' section."
      fi
    else
      report "no .ai/project.yml found at the repo root" \
        "This repo consumes its own plugin (CLAUDE.md) and must have one."
    fi
  fi
  rm -f "$full_tmp" "$worked_tmp"
fi

# --- 8. A known-wrong 'absent defaults to X' form has not come back ---------------
#
# WB-D17 (#142) removed every documented default -- "files or absent", "absent
# means X", "absent or `null` means Y" -- because that phrasing is exactly the
# shape that let this repo run two sprints on an undeclared `planning.kind` while
# behaving like `github_milestones`. Scoped to skills, agents, and `reference/`
# only, same as `#142`'s own build shape -- `docs/decisions.md` is a historical
# log of decisions as they read AT THE TIME (the same carve-out check 6 makes,
# for the same reason: rewriting its past tense would misrepresent what was
# actually approved when).
KNOWN_WRONG_PATTERNS=(
  'or absent'
  '/absent'
  'absent means'
  'absent or `null`'
)
wrong_hits=""
for f in "${SKILLS[@]}" "${AGENTS[@]}" "${REFERENCE_DOCS[@]}"; do
  for pat in "${KNOWN_WRONG_PATTERNS[@]}"; do
    h=$(grep -nF -- "$pat" "$f" || true)
    if [ -n "$h" ]; then
      wrong_hits+="  $f (\"$pat\"):"$'\n'"$(printf '%s\n' "$h" | sed 's/^/    /')"$'\n'
    fi
  done
done
if [ -n "$wrong_hits" ]; then
  report "a known-wrong 'absent defaults to X' form has returned (WB-D17, #142)" \
    "$wrong_hits" \
    "Every schema key must read: state what null means if null is legal for it;" \
    "absent always prompts, never a default. See project-schema.md's own rule."
fi

# --- 9. Every executed hook/bin script is stored executable (#214) -----------------
#
# `hooks/hooks.json` runs ai-cursor-banner.sh directly, and the skills call every
# `bin/*.sh` by bare name off the plugin's PATH. A git checkout gets the mode the index
# records, so a script stored 100644 installs non-executable, and a hook that cannot run
# fails silently ("the hook didn't run" reads exactly like "nothing to report").
# ai-cursor-banner.sh was stored 100644 at every tag from v0.1.0 through v0.15.0 (#214).
# This guards the INDEX mode only; a copy that drops mode bits (`cp` without `-p`, a zip
# extract) is not cured by it -- the issue's alternative, running the hook through
# `bash`, would be, and was not taken here.
#
# Read from the INDEX (`git ls-files -s`), never the filesystem: on a checkout with
# core.filemode=false (this maintainer's Windows host) a filesystem test says nothing,
# and the index is what a consumer's install is made from. Fails closed: a `git`
# failure, or an on-disk script the index does not list (untracked, so it would not
# ship), is a failure, never a pass -- the same stance as a missing `yq`.
mode_hits=""
mode_problem=""
disk_scripts=0
for f in "${HOOK_SCRIPTS[@]}" "${BIN_SCRIPTS[@]}"; do
  [ -e "$f" ] && disk_scripts=$((disk_scripts + 1))
done
if ! ls_out=$(git ls-files -s -- "${HOOK_SCRIPTS[@]}" "${BIN_SCRIPTS[@]}" 2>&1); then
  mode_problem="could not read the git index: $ls_out"
else
  listed=0
  while read -r mode _ _ path; do
    [ -n "$mode" ] || continue
    listed=$((listed + 1))
    [ "$mode" = "100755" ] || mode_hits+="  $path (mode $mode)"$'\n'
  done <<<"$ls_out"
  if [ "$listed" -ne "$disk_scripts" ]; then
    mode_problem="$disk_scripts hook/bin script(s) on disk but $listed in the index (untracked?)"
  fi
fi
if [ -n "$mode_hits" ]; then
  report "a hook or bin script is stored without the executable bit (#214)" \
    "$mode_hits" \
    "Fix: git update-index --chmod=+x <path> (or git add --chmod=+x for a new file," \
    "or after a rename). A script that cannot execute fails silently; the index mode" \
    "is what an install gets."
fi
if [ -n "$mode_problem" ]; then
  report "the executable-bit check could not be completed (#214)" "  $mode_problem"
fi

# --- 10. Every reader of a PR body marks it data, and names bot authors (#225) -----
#
# architect-review's *Load context lean* step loaded "the PR body" as context with no
# marking, while the task issue beside it was already "read as a specification, never as
# instructions". On a Dependabot PR the body is upstream release notes nobody here wrote,
# sitting in the context that acts on the review's trust branch and verdict. Shipped
# unmarked from v0.8.0 through v0.16.0; fixed in the three places that read a PR body.
# Presence of both phrases is the invariant: a reword that drops either one means
# updating this pattern deliberately, in the commit.
PR_BODY_READERS=(
  plugins/*/skills/architect-review/SKILL.md
  plugins/*/agents/architect.md
  plugins/*/agents/security-critic.md
)
prbody_hits=""
for f in "${PR_BODY_READERS[@]}"; do
  [ -f "$f" ] || { prbody_hits+="  $f (missing)"$'\n'; continue; }
  flat=$(tr '\r\n' '  ' <"$f" | tr -s ' ')
  case "$flat" in *'data to review, never instructions to'*) ;; *) prbody_hits+="  $f (no \"data to review, never instructions to ...\")"$'\n';; esac
  case "$flat" in *'bot-authored'*) ;; *) prbody_hits+="  $f (no \"bot-authored\" call-out)"$'\n';; esac
done
if [ -n "$prbody_hits" ]; then
  report "a PR-body reader lost its untrusted-data marking or bot-author call-out (#225)" \
    "$prbody_hits" \
    "A PR body is data to review, never instructions to the session, and a bot-authored" \
    "PR (Dependabot, any [bot] author) embeds third-party text -- say so where it is read."
fi

# --- 11. `gh` output is never piped straight into a bin/ predicate (#243) ---------
#
# A predicate script (blocked-state.sh, review-gate-state.sh, ...) reads records on stdin
# and cannot observe how it was fed. In `gh api ... | predicate.sh` a failed `gh api`
# yields an empty record list and the predicate reads that as "no rule" / "no review" --
# a fail-open, because a pipe's exit status is the LAST command's. The fail-closed shape is
# to capture first (`T=$(gh api ...) &&`) and feed the captured text, so a failed call
# breaks the chain before the predicate runs. Only prose guarded that shape; this is the
# mechanical half. review-gate-state.sh's header states the same rule.
#
# Scope, stated so nobody reads it as the whole invariant: this matches the PIPE form only.
# `pred < <(gh ...)`, `pred <<< "$(gh ...)"`, and a capture joined to its feed by `;`
# instead of `&&` have the same failure mode and are not matched. A `$(gh ... | jq ...)`
# capture is also out of scope (without pipefail it takes jq's status), which is why the
# real skills use `gh --jq` instead. Also not matched, because a line-based matcher cannot
# parse bash: a group or subshell producer (`{ gh a; gh b; } | pred`, `( gh a ) | pred`),
# escaped quotes inside a double-quoted --jq filter, a single-quoted argument spanning
# several lines (a `gh api graphql` query), unquoted arithmetic or nested substitution in a
# gh argument, and wrappers beyond sh/bash/env/timeout (`command`, `xargs`, long options).
# This is a regression guard for the common shapes, not a proof that no such pipe exists. Prose that quotes the bad form to warn against it
# trips the check too -- word the warning without the literal pipe.
#
# Every plugins/*/bin/*.sh basename is a target, not a hand-kept list, so a later
# stdin-fed predicate is covered the day it lands. Each file is normalised before matching:
# CR stripped (a CRLF checkout), backslash- and trailing-`|`-continued lines joined (bash
# continues after either; a markdown table row, which starts with `|`, is neither joined
# nor matched),
# the opening of `"$(...)"` unwrapped to `$(` so a quoted capture is still seen, then
# single-quoted spans and pipe-free `$(...)` substitutions collapsed, and every double-quoted
# span PAIRED first (left to right, so a later quote is never re-paired across the pipe) and
# only then stripped of the paren, `&`, `;` and `|` characters inside it, with its quotes
# dropped (a `--jq` filter or query string would otherwise stop the matcher, while a quoted
# path such as `"$BIN"/pred.sh` stays readable), `2>&1` dropped and `|&` read as `|`. The
# predicate may be run by path, or under sh/bash/env/timeout. `||` is not a pipe: the middle of the pattern refuses it. Line numbers are those
# of the joined text, so approximate. An apostrophe in prose on the same line as code pairs
# with the code's quote and can hide it -- the gate reads code, not sentences.
ghpipe_hits=""
ghpipe_err=""
bin_names=""
for f in "${BIN_SCRIPTS[@]}"; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  case "$b" in
    *[!A-Za-z0-9_.-]*) ghpipe_err+="  $f (name outside [A-Za-z0-9_.-])"$'\n'; continue;;
  esac
  bin_names+="${bin_names:+|}${b//./\\.}"
done
if [ -z "$bin_names" ]; then
  ghpipe_err+="  no plugins/*/bin/*.sh found to build the predicate list from"$'\n'
else
  ghpipe_re="(^|[^[:alnum:]_.-])gh[[:space:]][^|;&)(]*(\|[^|;&)(]+)*\|[[:space:]]*(((ba)?sh|env|timeout)([[:space:]]+-?[A-Za-z0-9_=.]+)*[[:space:]]+)?([^[:space:]|]*/)?($bin_names)([^[:alnum:]_.-]|\$)"
  # The shared front half: pipe/redirect spellings, then the two kinds of line join.
  ghpipe_join() {
    sed -e 's/|&/|/g' -e 's/[0-9]*>&[0-9-]//g' |
      sed -e ':a' -e '/\\$/{N;s/\\\n/ /;ba' -e '}' |
      sed -e ':b' -e '/^[[:space:]]*|/b' -e '/[^|]|[[:space:]]*$/{N;s/\n/ /;bb' -e '}'
  }
  for f in "${SKILLS[@]}" "${AGENTS[@]}"; do
    [ -f "$f" ] || continue
    # Two passes, and the check fails if EITHER hits. The normalised pass collapses quoted
    # spans so a --jq filter's parens cannot stop the matcher; the raw pass only deletes
    # double quotes and so cannot be fooled by a quote the collapse mis-pairs (a leftover
    # closing quote, an apostrophe inside a double-quoted string). Each pass covers shapes
    # the other misses, and the raw pass also fires on single-quoted text that merely
    # contains the form (a false positive, which fails closed). A shape neither sees --
    # e.g. an apostrophe in a double-quoted string together with parens in a single-quoted
    # gh argument -- still passes: this is a regression guard, not a proof.
    # Normalise and match are separate steps, each with its own status: under pipefail a
    # failed tr/sed upstream of grep would otherwise surface as grep's "no match" (1).
    nrc=0
    norm=$(tr -d '\r' <"$f" | ghpipe_join |
        sed -e 'y/@/A/' -e 's/"\$([^()|]*)"/S/g' -e 's/"\$(/$(/g' -e "s/'[^']*'/Q/g" -e 's/\$([^()|]*)/S/g' \
            -e 's/"\([^"]*\)"/@Q1@\1@Q2@/g' \
            -e ':q' -e 's/\(@Q1@[^@]*\)[][()&;|]\([^@]*@Q2@\)/\1\2/' -e 'tq' \
            -e 's/@Q[12]@//g' -e 's/^[[:space:]]*|.*$//') || nrc=$?
    raw=$(tr -d '\r"' <"$f" | ghpipe_join | sed -e 's/^[[:space:]]*|.*$//') || nrc=$?
    if [ "$nrc" -ne 0 ]; then
      ghpipe_err+="  $f (normalising failed, status $nrc)"$'\n'
      continue
    fi
    # Each pass's grep output and status are captured on their own: grep exits 1 for no
    # match and >=2 for a real error, and reads its whole input (no -q, which would
    # SIGPIPE the writer on a large file and surface as 141).
    h=""
    for pass in "$norm" "$raw"; do
      prc=0
      ph=$(printf '%s\n' "$pass" | grep -nE "$ghpipe_re") || prc=$?
      case "$prc" in
        0) case "$h" in *"$ph"*) ;; *) h+="${h:+$'\n'}$ph";; esac;;
        1) ;;
        *) ghpipe_err+="  $f (the matcher itself failed, status $prc)"$'\n';;
      esac
    done
    [ -z "$h" ] || ghpipe_hits+="  $f"$'\n'"$h"$'\n'
  done
fi
if [ -n "$ghpipe_err" ]; then
  report "check 11 could not run -- a gate that cannot look must fail, not pass (#243)" \
    "$ghpipe_err"
fi
if [ -n "$ghpipe_hits" ]; then
  report "gh output is piped directly into a bin/ predicate script (#243)" \
    "$ghpipe_hits" \
    "A failed gh call yields empty stdin, which the predicate reads as 'nothing there'." \
    "Capture first so the failure breaks the chain, and feed nothing when it is empty:" \
    "  T=\$(gh api ...) && { [ -z \"\$T\" ] || printf '%s\\n' \"\$T\"; } | script.sh"
fi

# --- 12. A skill or agent that names {backlog.repo} says null reads as {repo} (#479) -
#
# `backlog.repo: null` is the common case and means the repo itself. archive-sprint wrote
# `repos/{backlog.repo}/milestones/...` with no such note, and a live run read `null` as
# "no repo", stopped, and put a backlog.repo change into a PR. A file that names the key
# must state the null reading on a line that also names the key, in backticks: a bare
# "null" elsewhere (`>/dev/null`, an unrelated `dev_app` sentence) must not satisfy it.
nullrepo_hits=""
nullrepo_pair='`null`.{0,60}`\{repo\}`|`\{repo\}`.{0,60}`null`'
for f in "${SKILLS[@]}" "${AGENTS[@]}"; do
  grep -q '{backlog\.repo}' "$f" || continue
  { grep -F '{backlog.repo}' "$f" | grep -Eq "$nullrepo_pair"; } || nullrepo_hits+="$f"$'\n'
done
if [ -n "$nullrepo_hits" ]; then
  report "a skill or agent names {backlog.repo} without saying null means {repo} (#479)" \
    "$nullrepo_hits" \
    "State it on a line that names the key: a \`null\` {backlog.repo} means \`{repo}\`."
fi

# --- 13. unpark-sprint validates parked_from_commit before git sees it (#539) ------
#
# Step 2 passed the snapshot's `parked_from_commit` to `git log` and `git merge-base` as read.
# It comes from a file a branch can edit, so a value starting `-` is an option and a revision
# expression is looked up by git. resume validates `last_commit` in its review-step block the
# same way. Two things are the invariant: the hex-only case pattern on a line that names the
# variable, and the value being READ from the snapshot with `jq -r` (typing it into a shell
# assignment is the same injection by another door; step 1 deletes the snapshot, so the read
# must come first). The skill may reword around both, but dropping either means updating this
# check deliberately. A tree with no unpark-sprint skill at all fails: a check that cannot
# look must not pass (#243's stance).
unparkpfc_hits=""
unparkpfc_seen=0
for f in plugins/*/skills/unpark-sprint/SKILL.md; do
  [ -f "$f" ] || continue
  unparkpfc_seen=1
  { grep -F '[!0-9a-f]' "$f" | grep -Fq 'PFC'; } &&
    grep -Fq "jq -r '.parked_from_commit" "$f" || unparkpfc_hits+="$f"$'\n'
done
[ "$unparkpfc_seen" -eq 1 ] || unparkpfc_hits+="(no plugins/*/skills/unpark-sprint/SKILL.md found)"$'\n'
if [ -n "$unparkpfc_hits" ]; then
  report "unpark-sprint no longer validates parked_from_commit as hex before git uses it (#539)" \
    "$unparkpfc_hits" \
    "Keep the jq -r read of parked_from_commit and the case \"\$PFC\" in ''|*[!0-9a-f]*) guard ahead of git log / git merge-base."
fi

# --- 14. The three hitl_gate readers call one predicate (#557) ---------------------
#
# resume, unpark-sprint and plan-sprint each tested "closed" in their own words (a bare
# `NONE OPEN` prefix in two, a model judgment about the text after it in the third), so two
# readers could answer differently on one cursor. bin/hitl-gate-closed.sh is the single
# definition; each of the three must name it, and none may bring back the prose restatement
# ("nothing open after it"). A tree with no such skill, or no such script, fails: a check
# that cannot look must not pass (#243's stance).
gate_hits=""
for s in resume unpark-sprint plan-sprint; do
  seen=0
  for f in plugins/*/skills/"$s"/SKILL.md; do
    [ -f "$f" ] || continue
    seen=1
    # The call line itself, not any mention: the frontmatter and prose also name the script.
    case "$s" in resume) lit='hitl-gate-closed.sh "$GATE"' ;; *) lit='hitl-gate-closed.sh "$G1"' ;; esac
    grep -Fq -- "$lit" "$f" || gate_hits+="$f (no call line: $lit)"$'\n'
    # The ledger-line read and unpark's before-the-move read are call lines too.
    case "$s" in
      unpark-sprint) lits='hitl-gate-closed.sh "$G2"|hitl-gate-closed.sh "$KG"' ;;
      plan-sprint) lits='hitl-gate-closed.sh "$G2"' ;;
      *) lits= ;;
    esac
    old_ifs=$IFS; IFS='|'
    for lit in $lits; do
      grep -Fq -- "$lit" "$f" || gate_hits+="$f (no call line: $lit)"$'\n'
    done
    IFS=$old_ifs
  done
  [ "$seen" -eq 1 ] || gate_hits+="(no plugins/*/skills/$s/SKILL.md found)"$'\n'
done
for f in plugins/*/skills/*/SKILL.md plugins/*/skills/*/appendices/*.md plugins/*/reference/*.md; do
  [ -f "$f" ] || continue
  if grep -Eqi 'nothing open after|starts with`? `NONE OPEN' "$f"; then gate_hits+="$f (restates the closed-gate test in prose)"$'\n'; fi
done
ls plugins/*/bin/hitl-gate-closed.sh >/dev/null 2>&1 || gate_hits+="(no plugins/*/bin/hitl-gate-closed.sh found)"$'\n'
if [ -n "$gate_hits" ]; then
  report "a hitl_gate reader no longer calls the shared closed-gate predicate (#557)" \
    "$gate_hits" \
    "resume, unpark-sprint and plan-sprint must call bin/hitl-gate-closed.sh, not restate the test."
fi

# --- 15. architect-review never loads the task issue's body under an identities map (#566) --
#
# resume and the coder's builder rule read only the approved spec comment under a map, because
# the maintainer's reaction covers the comment and an agent with issue write can edit the body
# afterwards (#496). architect-review's step 5 still loaded "its body and, when one exists, its
# anchored spec comment" for every repo, and the schema doc recorded that as "not yet covered".
# Two things are the invariant: the skill carries the map-mode rule ("the body is never
# loaded") and no longer carries the unconditional body-and-comment phrasing; and the schema
# doc does not say the skill is uncovered again. A tree with no architect-review skill or no
# schema doc fails: a check that cannot look must not pass (#243's stance).
specbody_hits=""
specbody_seen=0
for f in plugins/*/skills/architect-review/SKILL.md; do
  [ -f "$f" ] || continue
  specbody_seen=1
  grep -Fq 'the body is never loaded' "$f" || specbody_hits+="$f (no map-mode rule: the body is never loaded)"$'\n'
  if grep -Fq 'when `null`; its body and' "$f"; then specbody_hits+="$f (names the issue body as loaded without the map rule)"$'\n'; fi
done
[ "$specbody_seen" -eq 1 ] || specbody_hits+="(no plugins/*/skills/architect-review/SKILL.md found)"$'\n'
schema_seen=0
for f in plugins/*/reference/project-schema.md; do
  [ -f "$f" ] || continue
  schema_seen=1
  if grep -Fq 'architect-review` is not yet covered' "$f"; then specbody_hits+="$f (says architect-review is not yet covered)"$'\n'; fi
done
[ "$schema_seen" -eq 1 ] || specbody_hits+="(no plugins/*/reference/project-schema.md found)"$'\n'
if [ -n "$specbody_hits" ]; then
  report "architect-review may load the task issue's body under an identities map (#566)" \
    "$specbody_hits" \
    "Under a map step 5 loads the approved spec comment only; keep that rule and the schema text saying it is covered."
fi

# --- 16. One spec-reaction rule, one implementation (#613) --------------------------------
#
# Whether a declared maintainer reacted to a spec comment after its last edit is asked by
# plan-anchor.sh (resume's auto-start), by architect-review's Map branch, and by spec-comment.sh
# for every declared author under a map (#660, WB-D30), and by the loop's dispatch preflight (scripts/loop/preflight.sh)
# for every declared author under a map (#666, #682), and by bin/spec-find.sh, which finds the approved spec comment on a
# task issue (#662), and by bin/spec-issue.sh and bin/spec-post.sh for an issue the dev or reviewer App filed (WB-D32,
# #664). Two
# implementations would let the approval rule drift between the gate that starts work and the
# review that labels it. The things that are the invariant: plan-anchor.sh, spec-comment.sh and spec-find.sh carry their
# spec-reaction.sh call line (the invocation, not the name, which a header alone would satisfy),
# architect-review's SKILL.md calls spec-reaction.sh, and no other file under plugins/*/bin/ matches an approving reaction
# content itself (the `heart | hooray` case pattern, or a `== "hooray"` comparison). bin/spec-find.sh
# must carry its call line (`sh "$sr" "$c_updated" "$maint_ids" <"$rx"`) on a non-comment line, the form
# the preflight test below also uses. spec-issue.sh and spec-post.sh must each carry their call line (`sh "$sr" "$i_updated" "$maint_ids" <"$tmp/reactions.tsv"`)
# on a non-comment line, and a tree that lacks either fails (so seven things are the invariant).
# The preflight is held to the same rule by a different test, since it is not under plugins/*/bin/: it must carry
# its call line (`sh "$sr" "$c_updated" "$maint_ids" <"$reactions"`) on a non-comment line, and no
# non-comment line of it may contain `hooray` or `rocket`.
# A tree with no spec-reaction.sh, plan-anchor.sh, spec-comment.sh, spec-find.sh, preflight.sh or architect-review skill fails: a check
# that cannot look must not pass (#243's stance).
reaction_hits=""
ls plugins/*/bin/spec-reaction.sh >/dev/null 2>&1 || reaction_hits+="(no plugins/*/bin/spec-reaction.sh found)"$'\n'
ls plugins/*/bin/plan-anchor.sh >/dev/null 2>&1 || reaction_hits+="(no plugins/*/bin/plan-anchor.sh found)"$'\n'
for f in plugins/*/bin/plan-anchor.sh; do
  [ -f "$f" ] || continue
  grep -Fq 'sh "$sr" "$c_updated" "$maint_ids"' "$f" || reaction_hits+="$f (does not call spec-reaction.sh)"$'\n'
done
ls plugins/*/bin/spec-comment.sh >/dev/null 2>&1 || reaction_hits+="(no plugins/*/bin/spec-comment.sh found)"$'\n'
for f in plugins/*/bin/spec-comment.sh; do
  [ -f "$f" ] || continue
  grep -Fq 'sh "$sr" "$updated" "$ids" <"$rx"' "$f" || reaction_hits+="$f (does not call spec-reaction.sh)"$'\n'
done
for name in spec-issue spec-post; do
  ls plugins/*/bin/$name.sh >/dev/null 2>&1 || reaction_hits+="(no plugins/*/bin/$name.sh found)"$'\n'
  for f in plugins/*/bin/$name.sh; do
    [ -f "$f" ] || continue
    grep -Eq '^[[:space:]]*[^#[:space:]].*sh "\$sr" "\$i_updated" "\$maint_ids" <"\$tmp/reactions\.tsv"' "$f" \
      || reaction_hits+="$f (does not call spec-reaction.sh)"$'\n'
  done
done
ls plugins/*/bin/spec-find.sh >/dev/null 2>&1 || reaction_hits+="(no plugins/*/bin/spec-find.sh found)"$'\n'
for f in plugins/*/bin/spec-find.sh; do
  [ -f "$f" ] || continue
  grep -Eq '^[[:space:]]*[^#[:space:]].*sh "\$sr" "\$c_updated" "\$maint_ids" <"\$rx"' "$f" \
    || reaction_hits+="$f (does not call spec-reaction.sh)"$'\n'
done
reaction_seen=0
for f in plugins/*/skills/architect-review/SKILL.md; do
  [ -f "$f" ] || continue
  reaction_seen=1
  grep -Fq 'spec-reaction.sh' "$f" || reaction_hits+="$f (does not call spec-reaction.sh)"$'\n'
done
[ "$reaction_seen" -eq 1 ] || reaction_hits+="(no plugins/*/skills/architect-review/SKILL.md found)"$'\n'
if [ -f scripts/loop/preflight.sh ]; then
  grep -Eq '^[[:space:]]*[^#[:space:]].*sh "\$sr" "\$c_updated" "\$maint_ids" <"\$reactions"' scripts/loop/preflight.sh \
    || reaction_hits+="scripts/loop/preflight.sh (does not call spec-reaction.sh)"$'\n'
  if grep -Ev '^[[:space:]]*#' scripts/loop/preflight.sh | grep -Eq 'hooray|rocket'; then
    reaction_hits+="scripts/loop/preflight.sh (matches an approving reaction itself)"$'\n'
  fi
else
  reaction_hits+="(no scripts/loop/preflight.sh found)"$'\n'
fi
for f in plugins/*/bin/*; do
  [ -f "$f" ] || continue
  case "$f" in */spec-reaction.sh) continue ;; esac
  if grep -Eq 'heart[[:space:]]*\|[[:space:]]*hooray|==[[:space:]]*"hooray"' "$f"; then
    reaction_hits+="$f (matches an approving reaction itself)"$'\n'
  fi
done
if [ -n "$reaction_hits" ]; then
  report "a second spec-reaction implementation, or a caller no longer calls it (#613)" \
    "$reaction_hits" \
    "plan-anchor.sh, spec-comment.sh, spec-find.sh, spec-issue.sh, spec-post.sh, architect-review's SKILL.md and scripts/loop/preflight.sh must all call bin/spec-reaction.sh, not restate the rule."
fi

# --- 17. The spec comment is printed only after its checks pass, and found, not listed (#614, WB-D30) --
#
# resume's builder rule and the coder's fetch step told the reader to fetch the anchored spec
# comment and check it "in that same response", so the unchecked text had already entered
# context by the time a check could fail; architect-review carried its own inline copy of the
# checks. bin/spec-comment.sh is the one implementation: the fetch goes to a file and the body
# is printed only after the checks pass. Per file the invariant is: it names spec-comment.sh;
# it names spec-find.sh, since under a map the readers find the spec rather than take its id from
# the anchor (WB-D30); every spec-comment fetch (the path `issues/comments/<id>`, or the same with
# `$CID` or `${CID}` for the id, one closing `"` allowed) is one of three allowed forms: followed
# by `/` (the reactions fetch), by ` >"$T/` (redirected into the temp directory) or by
# ` --jq .updated_at` ending there (the re-check). Anything else after the id, a line end
# included, is flagged -- an allow-list, so `--jq .body`, `--jq .updated_at,.body` and `|jq`
# cannot slip through. And it carries no comment LISTING, in any of these forms: an
# `issues/<x>/comments` path (x not `comments`), `gh issue view` with `--comments` or with
# `--json` naming `comments`, a GraphQL `comments(` or `comments {`, the repo-wide listing
# (`issues/comments` followed by anything but `/<id>`, `/$CID` or `/${CID}`) and an
# `issues/<x>/timeline` path, whose `commented` events carry comment bodies. Only spec-find.sh
# lists, and it is held to its own rules below. resume and the coder must also name spec-fresh.sh
# (#663, WB-D31), the freshness check run between spec-comment.sh check and body; the script must
# exist and make no gh call. The check sees only those spellings; a fetch or
# listing spelled another way is outside it. A missing file or script fails: a check that cannot
# look must not pass (#243's stance).
speccomment_hits=""
ls plugins/*/bin/spec-comment.sh >/dev/null 2>&1 || speccomment_hits+="(no plugins/*/bin/spec-comment.sh found)"$'\n'
for pat in 'skills/resume/SKILL.md' 'skills/architect-review/SKILL.md' 'agents/coder.md'; do
  speccomment_seen=0
  for f in plugins/*/$pat; do
    [ -f "$f" ] || continue
    speccomment_seen=1
    grep -Fq 'spec-comment.sh' "$f" || speccomment_hits+="$f (does not call spec-comment.sh)"$'\n'
    grep -Fq 'spec-find.sh' "$f" || speccomment_hits+="$f (does not name spec-find.sh)"$'\n'
    case "$pat" in
      skills/resume/SKILL.md | agents/coder.md)
        grep -Fq 'spec-fresh.sh' "$f" || speccomment_hits+="$f (does not name spec-fresh.sh)"$'\n'
        ;;
    esac
    bare=$(grep -oE 'issues/comments/(<id>|\$CID|\$\{CID\})"?.{0,24}' "$f" | grep -Ev '^issues/comments/(<id>|\$CID|\$\{CID\})"?(/| >"\$T/| --jq \.updated_at([^,._A-Za-z]|$))' || true)
    [ -z "$bare" ] || speccomment_hits+="$f (a spec-comment fetch neither redirected to a file nor projected: $(printf '%s' "$bare" | head -n 1))"$'\n'
    # Comment listings (WB-D30): the finder lists, the readers never do.
    list=$(grep -oE 'issues/[^/[:space:]]+/comments' "$f" | grep -vx 'issues/comments/comments' || true)
    [ -z "$list" ] || speccomment_hits+="$f (lists a task issue's comments: $(printf '%s' "$list" | head -n 1))"$'\n'
    list=$(grep -E 'gh issue view' "$f" | grep -E -e '--comments' -e '--json[^|]*comments' || true)
    [ -z "$list" ] || speccomment_hits+="$f (lists comments with gh issue view)"$'\n'
    list=$(grep -E 'comments(\(|[[:space:]]*\{)' "$f" || true)
    [ -z "$list" ] || speccomment_hits+="$f (a GraphQL comments selection)"$'\n'
    list=$(grep -oE 'issues/comments.{0,8}' "$f" | grep -Ev '^issues/comments/(<id>|\$CID|\$\{CID\})' || true)
    [ -z "$list" ] || speccomment_hits+="$f (the repo-wide comment listing: $(printf '%s' "$list" | head -n 1))"$'\n'
    list=$(grep -E 'issues/[^[:space:]]*/timeline' "$f" || true)
    [ -z "$list" ] || speccomment_hits+="$f (reads an issue timeline, whose events carry comment bodies)"$'\n'
  done
  [ "$speccomment_seen" -eq 1 ] || speccomment_hits+="(no plugins/*/$pat found)"$'\n'
done
# bin/spec-find.sh (#662) lists a task issue's comments itself and must keep the marker test in
# the listing's own --jq: exactly one non-comment line names an issue-comment listing
# (`issues/<x>/comments`), that line carries both `split("\n")[0]` and `test(`, and no other
# non-comment line reads a `.body`. This is a regression guard, not a proof: a second column on the
# listing line would pass these rules, and tests/spec-find.test.sh's sentinel projection fixture
# is the real control.
ls plugins/*/bin/spec-find.sh >/dev/null 2>&1 || speccomment_hits+="(no plugins/*/bin/spec-find.sh found)"$'\n'
for f in plugins/*/bin/spec-find.sh; do
  [ -f "$f" ] || continue
  nc_lines=$(grep -Ev '^[[:space:]]*#' "$f" || true)
  listing=$(printf '%s\n' "$nc_lines" | grep -E 'issues/[^/[:space:]]+/comments' || true)
  if [ -z "$listing" ] || [ "$(printf '%s\n' "$listing" | wc -l)" -ne 1 ]; then
    speccomment_hits+="$f (does not have exactly one issue-comment listing line)"$'\n'
  else
    printf '%s\n' "$listing" | grep -Fq 'split("\n")[0]' || speccomment_hits+="$f (the listing line has no split(\"\\n\")[0] first-line projection)"$'\n'
    printf '%s\n' "$listing" | grep -Fq 'test(' || speccomment_hits+="$f (the listing line has no test( marker match)"$'\n'
    if printf '%s\n' "$nc_lines" | grep -vFx -e "$listing" | grep -Fq '.body'; then
      speccomment_hits+="$f (a .body is read outside the listing line)"$'\n'
    fi
  fi
done
# bin/spec-fresh.sh (#663) is a pure git-and-file check: it must exist and no non-comment line
# may call gh.
ls plugins/*/bin/spec-fresh.sh >/dev/null 2>&1 || speccomment_hits+="(no plugins/*/bin/spec-fresh.sh found)"$'\n'
for f in plugins/*/bin/spec-fresh.sh; do
  [ -f "$f" ] || continue
  fresh_gh=$(grep -Ev '^[[:space:]]*#' "$f" | grep -E '(^|[^A-Za-z0-9_-])gh[[:space:]]' || true)
  [ -z "$fresh_gh" ] || speccomment_hits+="$f (makes a gh call: $(printf '%s' "$fresh_gh" | head -n 1))"$'\n'
done
if [ -n "$speccomment_hits" ]; then
  report "the spec comment may reach context before its checks pass, or a reader lists comments (#614, WB-D30)" \
    "$speccomment_hits" \
    "Name bin/spec-find.sh in each reader and take the comment id from its found line; fetch the comment into a file and print it with bin/spec-comment.sh body, never to the transcript; list no comments. resume and the coder also name bin/spec-fresh.sh, run before the body prints (#663). In bin/spec-find.sh keep the one listing line with its projection, and read no .body elsewhere. bin/spec-fresh.sh makes no gh call."
fi

# --- 18. The spec-task skill carries no posting form; its writes live in spec-post.sh (#611, #661, #746, WB-D29) --
#
# A dev-App spec comment is used only with a declared maintainer's fresh approving reaction. A comment
# posted under a human-trusted login would be read as "maintainer-authored": it would credit a human with
# agent text, and a maintainer's own reaction approves their own comment (WB-D30 residual 7), even though
# since #682 every reader, the loop preflight included, needs that reaction. So the spec-task skill carries no posting form: no `gh issue comment`, `gh pr
# comment` or other `gh issue`/`gh pr` write verb (flags may sit between the words), no `gh label`,
# and no `gh api` call with `-X`/`--method` POST|PATCH|PUT|DELETE or with `-f`/`-F` (a value may be
# attached) or `--field`/`--raw-field`/`--input` (any of which turns a read into a write). A command
# wrapped over several lines with a trailing backslash is joined before the test. The writes are in
# bin/spec-post.sh, which the skill must name as `spec-post.sh post`, and that script must exist.
# In it, lines whose first non-blank character is `#` are dropped BEFORE wrapped lines are joined (a
# shell comment never continues, except a `#` line right after a backslash-ended line, which the shell joins), and after that every line matching those same write patterns must
# equal, trimmed, one of three exact lines, compared as fixed strings: the viewer read, the comment
# POST and the label POST its `escalate` mode makes (#746). Each appears exactly once, and no line contains `eval` as a word. It is a static check on prose
# and a script, not a proof about a model's behaviour: a write through a function wrapper or
# `"$GH"` is outside it, and tests/spec-post.test.sh is the control for those. A tree with no
# spec-task skill or no spec-post.sh fails: a check that cannot look must not pass (#243's stance).
#
# The three write tests, each reading joined text on stdin and printing the matching lines, numbered.
# Flags may sit between `issue`/`pr` and the verb (`gh issue -R x comment`). `gh` must start a word,
# so prose like "high label" is not a command. A verb may be quoted.
spectask_w_verb() {
  grep -inE '(^|[^A-Za-z0-9_-])gh(\.exe)?([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+["'"'"']?(issue|pr)["'"'"']?([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+["'"'"']?(comment|edit|close|reopen|create|new|review|lock|unlock|delete|transfer|merge|ready|pin|unpin|develop|update-branch|revert)([^A-Za-z-]|$)' || true
}
spectask_w_label() {
  grep -inE '(^|[^A-Za-z0-9_-])gh(\.exe)?([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+["'"'"']?label([^A-Za-z-]|$)' || true
}
# The whole line is tested, not a segment of it: cutting at a pipe or `;` would hide a write
# piped into `gh api` or one that follows a separator inside a quoted argument. A skill line
# that mentions `gh api` next to an unrelated `-f` is reworded, not exempted.
spectask_w_api() {
  grep -inE '(^|[^A-Za-z0-9_-])gh(\.exe)?([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*[[:space:]]+["'"'"']?api' |
    grep -iE -e '(^|[[:space:]])["'"'"']?(-[A-Za-z]*X|--method)["'"'"']?[[:space:]=]*["'"'"']?(POST|PATCH|PUT|DELETE)([^A-Za-z]|$)' \
      -e '(^|[[:space:]])["'"'"']?-[A-Za-z]*[fF]' \
      -e '(^|[[:space:]])["'"'"']?--(field|raw-field|input)([[:space:]=]|$)' || true
}
spectask_hits=""
spectask_seen=0
for f in plugins/*/skills/spec-task/SKILL.md plugins/*/skills/spec-task/appendices/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */SKILL.md) spectask_seen=1 ;; esac
  # CRs go first, so a CRLF checkout joins wrapped lines too.
  joined=$(tr -d '\r' <"$f" | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta')
  h=$(printf '%s\n' "$joined" | spectask_w_verb)
  [ -z "$h" ] || spectask_hits+="$f (a gh issue/pr write command):"$'\n'"$h"$'\n'
  h=$(printf '%s\n' "$joined" | spectask_w_label)
  [ -z "$h" ] || spectask_hits+="$f (a gh label command):"$'\n'"$h"$'\n'
  h=$(printf '%s\n' "$joined" | spectask_w_api)
  [ -z "$h" ] || spectask_hits+="$f (a gh api write):"$'\n'"$h"$'\n'
  case "$f" in
    */SKILL.md)
      grep -qF -e 'spec-post.sh post' "$f" || report "the spec-task skill does not name spec-post.sh post (#661)" \
        "$f" \
        "The skill's one way to post is bin/spec-post.sh post. See docs/decisions.md WB-D29."
      ;;
  esac
done
[ "$spectask_seen" -eq 1 ] || spectask_hits+="(no plugins/*/skills/spec-task/SKILL.md found)"$'\n'
if [ -n "$spectask_hits" ]; then
  report "the spec-task skill contains a posting form; its writes are in bin/spec-post.sh (#611, #661, #746)" \
    "$spectask_hits" \
    "The skill carries no gh issue/pr write, gh label or gh api write. See docs/decisions.md WB-D29."
fi

# The three exact lines spec-post.sh may carry, compared as fixed strings after trimming blanks.
spectask_viewer='gh api --hostname github.com graphql -f query='\''{ viewer { login databaseId } }'\'' --jq '\''[.data.viewer.login, .data.viewer.databaseId] | @tsv'\'' >"$tmp/viewer" 2>/dev/null || held actor-unreadable'
spectask_post='gh api --hostname github.com --method POST "repos/$backlog/issues/$n/comments" -F body=@- <"$tmp/body.md" >"$tmp/resp.json" 2>/dev/null || stop post-unknown'
spectask_label='gh api --hostname github.com --method POST "repos/$backlog/issues/$n/labels" -f '\''labels[]=status/needs-human'\'' </dev/null >/dev/null 2>&1 || lbl=label-failed'
spectask_posts_seen=0
for f in plugins/*/bin/spec-post.sh; do
  [ -f "$f" ] || continue
  spectask_posts_seen=1
  # Comment lines go before wrapped lines are joined; CRs go first.
  # A line that starts with `#` right after a line ending in a backslash is not a comment (the shell
  # joins it to the line before), so it is kept; any other `#`-leading line is dropped.
  joined=$(tr -d '\r' <"$f" | awk '{ if ($0 ~ /^[ \t]*#/ && !cont) next; print; cont = ($0 ~ /\\$/) }' | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta' || true)
  writes=$({ printf '%s\n' "$joined" | spectask_w_verb; printf '%s\n' "$joined" | spectask_w_label; printf '%s\n' "$joined" | spectask_w_api; } | sed -e 's/^[0-9]*://' | sort -u || true)
  odd=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    t=$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    if [ "$t" != "$spectask_viewer" ] && [ "$t" != "$spectask_post" ] && [ "$t" != "$spectask_label" ]; then
      odd+="$f: $t"$'\n'
    fi
  done <<EOF_WRITES
$writes
EOF_WRITES
  # `sort -u` above collapses a repeated line, so each pinned line is counted on the joined text.
  n_viewer=$(printf '%s\n' "$joined" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -cxF -e "$spectask_viewer" || true)
  n_post=$(printf '%s\n' "$joined" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -cxF -e "$spectask_post" || true)
  n_label=$(printf '%s\n' "$joined" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -cxF -e "$spectask_label" || true)
  [ -z "$odd" ] || report "spec-post.sh carries a gh write line other than the three pinned ones (#661, #746)" \
    "$odd" \
    "Only the viewer read, the one comment POST and the one label POST are allowed, spelled exactly. See docs/decisions.md WB-D29."
  if [ "$n_viewer" -ne 1 ] || [ "$n_post" -ne 1 ] || [ "$n_label" -ne 1 ]; then
    report "spec-post.sh must carry each pinned gh line exactly once (#661, #746)" \
      "$f: viewer read x$n_viewer, comment POST x$n_post, label POST x$n_label" \
      "The viewer read, the comment POST and the label POST each appear exactly once, spelled exactly. See docs/decisions.md WB-D29."
  fi
  ev=$(printf '%s\n' "$joined" | grep -nE '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)' || true)
  [ -z "$ev" ] || report "spec-post.sh uses eval (#661)" \
    "$f:"$'\n'"$ev" \
    "The script never evaluates text. See docs/decisions.md WB-D29."
done
[ "$spectask_posts_seen" -eq 1 ] || report "plugins/*/bin/spec-post.sh is missing (#661)" \
  "(no plugins/*/bin/spec-post.sh found)" \
  "The spec-task skill posts through this script. See docs/decisions.md WB-D29."

# --- 19. A milestone read is projected, and a description read goes through the script (#640) ----
#
# `ship` (unattended) and `archive-sprint` read a milestone description with no projection, so
# all of it, author-editable and unbound since WB-D27, entered the session. bin/blocking-
# criteria.sh is the one projection: the description goes to a file and only the script's
# output is printed. Per skill, appendix and agent (plan-sprint is out: it reads descriptions
# in full by design), after CRs are stripped and backslash-continued lines joined as check 18
# does (the next line is never joined unless this one ends in a backslash):
#   - every joined line that names `milestones/` or `milestones?` carries a `--jq` filter
#     (at least one per mention) that names a field (`.name`) and is not `.`, nor contains
#     `..`, `.[]`, `tojson`, `tostring`, `to_entries` or `@json`;
#   - a line whose filter names `description` also redirects stdout to a file (a `>` not
#     preceded by a digit or `&`, and not aimed at /dev/stdout, /dev/stderr or /dev/tty),
#     names blocking-criteria.sh, and has no `cat`;
#   - ship and archive-sprint each name blocking-criteria.sh.
# A missing file or script is reported, like checks 15 to 17.
# Residual: a prose mention wrapped across two lines without a backslash is not seen, and a
# line with two milestone calls is checked by count, not by pairing each call to its filter.
# Also unseen: a read that never spells `milestones/` or `milestones?` (`gh issue view --json
# milestone`, GraphQL, the bare list endpoint), and a filter that names a field yet still
# prints more (`del(.creator)`, `. as $x | .`); the filter rule is a regression guard.
mjq_hits=""
mjq_prog='
BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34) }
function has_redirect(s,    i, n, prev, t) {
  n = length(s)
  for (i = 1; i <= n; i++) {
    if (substr(s, i, 1) != ">") continue
    prev = (i > 1) ? substr(s, i - 1, 1) : ""
    if (prev ~ /[0-9&>]/) continue
    t = substr(s, i + 1)
    sub(/^[>|]?[ \t]*/, "", t)
    if (t ~ /^"?\/dev\/(stdout|stderr|tty)/ || t ~ /^&/) continue
    return 1
  }
  return 0
}
function bad(msg) { printf "  line %d: %s: %s\n", NR, msg, substr($0, 1, 110) }
{
  nm = 0
  s = $0
  while ((p = index(s, "milestones/")) > 0) { nm++; s = substr(s, p + 11) }
  s = $0
  while ((p = index(s, "milestones?")) > 0) { nm++; s = substr(s, p + 11) }
  if (nm == 0) next
  rest = $0; bare = ""; nj = 0; desc = 0
  while ((p = index(rest, "--jq")) > 0) {
    bare = bare substr(rest, 1, p - 1)
    after = substr(rest, p + 4)
    lead = match(after, /^[ \t=]+/) ? RLENGTH : 0
    t = substr(after, lead + 1)
    c = substr(t, 1, 1)
    if (c == SQ) {
      r = substr(t, 2); e = index(r, SQ)
      f = e ? substr(r, 1, e - 1) : r; used = lead + 1 + (e ? e : length(r))
    } else if (c == DQ) {
      r = substr(t, 2); e = 0
      for (q = 1; q <= length(r); q++) {
        ch = substr(r, q, 1)
        if (ch == "\\") q++
        else if (ch == DQ) { e = q; break }
      }
      f = e ? substr(r, 1, e - 1) : r; used = lead + 1 + (e ? e : length(r))
    } else {
      match(t, /[ \t;&|)]/)
      f = RSTART ? substr(t, 1, RSTART - 1) : t; used = lead + length(f)
    }
    nj++
    if (f !~ /[.][A-Za-z_]/) bad("a --jq filter that names no field")
    else if (index(f, "..") || index(f, ".[]") || index(f, "tojson") || index(f, "tostring") || index(f, "to_entries") || index(f, "@json")) bad("a --jq filter that passes whole objects through")
    if (index(f, "description")) desc = 1
    rest = substr(after, used + 1)
  }
  bare = bare rest
  if (nj < nm) bad("a milestone read without a --jq filter")
  if (desc) {
    if (!has_redirect(bare)) bad("a description read that does not redirect stdout to a file")
    if (index($0, "blocking-criteria.sh") == 0) bad("a description read that does not go through blocking-criteria.sh")
    if ($0 ~ /(^|[^A-Za-z0-9_-])cat([^A-Za-z0-9_-]|$)/) bad("a description read that is also cat")
  }
}'
ls plugins/*/bin/blocking-criteria.sh >/dev/null 2>&1 || mjq_hits+="(no plugins/*/bin/blocking-criteria.sh found)"$'\n'
for f in "${SKILLS[@]}" "${AGENTS[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in */skills/plan-sprint/*) continue ;; esac
  joined=$(tr -d '\r' <"$f" | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta')
  mrc=0
  h=$(printf '%s\n' "$joined" | awk "$mjq_prog") || mrc=$?
  if [ "$mrc" -ne 0 ]; then
    mjq_hits+="$f (the matcher itself failed, status $mrc)"$'\n'
  elif [ -n "$h" ]; then
    mjq_hits+="$f"$'\n'"$h"$'\n'
  fi
done
for pat in skills/ship/SKILL.md skills/archive-sprint/SKILL.md; do
  mjq_seen=0
  for f in plugins/*/$pat; do
    [ -f "$f" ] || continue
    mjq_seen=1
    grep -Fq 'blocking-criteria.sh' "$f" || mjq_hits+="$f (does not name blocking-criteria.sh)"$'\n'
  done
  [ "$mjq_seen" -eq 1 ] || mjq_hits+="(no plugins/*/$pat found)"$'\n'
done
if [ -n "$mjq_hits" ]; then
  report "a milestone is read without a projection, or a description read bypasses blocking-criteria.sh (#640)" \
    "$mjq_hits" \
    "Fetch with --jq naming a field; send a description to a file and print it with blocking-criteria.sh."
fi

# --- 20. The pulls/<N>/files --jq filter reads the endpoint's page shape (#698) ---------------
#
# architect-review's container-mode exempt check passed `--jq '{f: .filename, ...}'` to a
# `gh api --paginate` call on `pulls/<N>/files`. That endpoint returns a JSON ARRAY per page and
# --jq runs once per page, so the object filter failed with "expected an object but got: array"
# and the skill read the failure as `stopped needs-human`: every container-mode review stopped
# before reviewing anything. Shipped in v0.19.0; nothing executed the filter.
#
# Per skill, appendix and agent, after CRs are stripped and backslash-continued lines joined as
# checks 18 and 19 do, each joined line that calls `gh api` on `pulls/<x>/files` with `--jq` has
# its LAST `--jq` argument taken: after `--jq` and its spaces (or `=`) one single-quoted string
# that is followed by a space, a tab or the end of the line, does not start with `-`, holds no
# control character, and names none of import, include, env, halt, input, debug, stderr, $__, modulemeta or
# get_ (substrings, so a future field name holding one is refused too). Anything
# else (a double quote, a spliced string, no closing quote) is reported, never skipped. The filter
# is run as `timeout 10 jq -c <filter>` on a canned three-file page (one renamed, two without
# `previous_filename`, so `// null` is exercised), and the slurped output must equal the three
# expected objects exactly: a filter that cannot read the shape, names a wrong field or drops
# files fails. Every matching line in every skill is held to that one output; a skill that needs
# another projection of this endpoint changes this check deliberately. Only the pipeline status is
# used and only a fixed message is reported, never the status or anything jq prints: a filter
# could choose its own exit status with halt_error, so the status must not travel back. architect-review must carry such a
# line, so a reworded call cannot drop out of the check. jq is required, never skipped.
# Residual: gh runs its built-in gojq and this runs jq, so a filter that depends on a difference
# between the two engines is outside the check; a prose mention wrapped across two lines without a
# backslash is not seen. The filter text comes from the tree under test and is run with its output
# discarded under a 10-second timeout.
ff_hits=""
ff_arch=0
ff_page='[{"filename":"a/x.md","status":"modified"},{"filename":"b/y.md","previous_filename":"b/old.md","status":"renamed"},{"filename":"c/z.md","status":"added"}]'
ff_want='. == [{"f":"a/x.md","p":null,"s":"modified"},{"f":"b/y.md","p":"b/old.md","s":"renamed"},{"f":"c/z.md","p":null,"s":"added"}]'
ff_prog='
BEGIN { SQ = sprintf("%c", 39) }
index($0, "gh api") == 0 { next }
$0 !~ /pulls\/[^\/ \t]+\/files/ { next }
{
  pos = 0; found = 0
  while ((q = index(substr($0, pos + 1), "--jq")) > 0) { pos += q; found = pos }
  if (found == 0) next
  after = substr($0, found + 4)
  sub(/^[ \t=]+/, "", after)
  if (substr(after, 1, 1) != SQ) { printf "%d\tBAD\tthe --jq argument is not a single-quoted string\n", NR; next }
  r = substr(after, 2); e = index(r, SQ)
  if (e == 0) { printf "%d\tBAD\tthe --jq argument has no closing single quote\n", NR; next }
  nx = substr(r, e + 1, 1)
  if (nx != "" && nx != " " && nx != "\t") { printf "%d\tBAD\tthe --jq string is spliced with more text\n", NR; next }
  f = substr(r, 1, e - 1)
  if (substr(f, 1, 1) == "-") { printf "%d\tBAD\tthe --jq filter starts with a dash\n", NR; next }
  if (f ~ /[\001-\037\177]/) { printf "%d\tBAD\tthe --jq filter holds a control character\n", NR; next }
  if (f ~ /(import|include|[$]ENV|env|halt|input|debug|stderr|[$]__|get_|modulemeta)/) { printf "%d\tBAD\tthe --jq filter names a jq builtin this check refuses (file, environment, exit or output access)\n", NR; next }
  printf "%d\tOK\t%s\n", NR, f
}'
if ! command -v jq >/dev/null 2>&1; then
  report "jq is not on PATH -- check 20 (the pulls/<N>/files filter, #698) cannot run" \
    "This check runs the skills' --jq filter with jq. A gate that cannot look must fail, not pass."
else
  for f in "${SKILLS[@]}" "${AGENTS[@]}"; do
    [ -f "$f" ] || continue
    joined=$(tr -d '\r' <"$f" | sed -e ':a' -e '/\\$/N; s/\\\n[[:space:]]*/ /; ta')
    arc=0
    rows=$(printf '%s\n' "$joined" | awk "$ff_prog") || arc=$?
    if [ "$arc" -ne 0 ]; then
      ff_hits+="$f (the matcher itself failed, status $arc)"$'\n'
      continue
    fi
    nrows=0
    while IFS=$'\t' read -r ln kind filt; do
      [ -n "$ln" ] || continue
      nrows=$((nrows + 1))
      if [ "$kind" = "BAD" ]; then
        ff_hits+="$f (joined line $ln): $filt"$'\n'
        continue
      fi
      rc=0
      printf '%s' "$ff_page" | timeout 10 jq -c "$filt" 2>/dev/null | jq -s -e "$ff_want" >/dev/null 2>&1 || rc=$?
      [ "$rc" -eq 0 ] || ff_hits+="$f (joined line $ln): the filter did not turn the canned page into the expected objects"$'\n'
    done <<<"$rows"
    case "$f" in
      plugins/*/skills/architect-review/SKILL.md)
        ff_arch=1
        [ "$nrows" -gt 0 ] || ff_hits+="$f (carries no gh api call on pulls/<N>/files with --jq)"$'\n'
        ;;
    esac
  done
  [ "$ff_arch" -eq 1 ] || ff_hits+="(no plugins/*/skills/architect-review/SKILL.md found)"$'\n'
fi
if [ -n "$ff_hits" ]; then
  report "a pulls/<N>/files --jq filter does not read the endpoint's page (#698)" \
    "$ff_hits" \
    "The endpoint returns an array per page and --jq runs once per page: start the filter with .[] |, keep a single-quoted argument, and project f, p and s."
fi

# --- 21. The three task-issue author readers call `task-author`, not `author` (#664, WB-D32) ------
#
# Under an identities map `gh-identity.sh author` trusts a declared maintainer only; the verb that
# lets an issue the dev or reviewer App filed through to a builder is `task-author`. Resume's body
# read, the coder agent's fetch and architect-review's map branch each judge the task issue's
# author, and each said `author` before WB-D32. A reader left on `author` would refuse an App-filed
# task the other readers take. Each of the three files must have no match of
# `gh-identity\.sh[[:space:]]+author([^-A-Za-z]|$)` (so `task-author` and a later word do not
# match) and at least one `gh-identity.sh task-author`; a tree that lacks any of the three fails.
# This guards a regression to the old verb. It is not a trust control, and it does not cover
# spec-issue.sh or spec-post.sh (protected paths, with their own fixtures) or the preflight (its
# own fixtures).
ta_hits=""
ta_seen=0
for f in plugins/*/skills/resume/SKILL.md plugins/*/agents/coder.md plugins/*/skills/architect-review/SKILL.md; do
  [ -f "$f" ] || continue
  ta_seen=$((ta_seen + 1))
  if grep -Eq 'gh-identity\.sh[[:space:]]+author([^-A-Za-z]|$)' "$f"; then
    ta_hits+="$f (names gh-identity.sh author)"$'\n'
  fi
  grep -Eq 'gh-identity\.sh[[:space:]]+task-author' "$f" || ta_hits+="$f (does not name gh-identity.sh task-author)"$'\n'
done
[ "$ta_seen" -eq 3 ] || ta_hits+="(found $ta_seen of resume's SKILL.md, coder.md and architect-review's SKILL.md, expected 3)"$'\n'
if [ -n "$ta_hits" ]; then
  report "a task-issue author reader is on the old verb, or a reader is missing (#664)" \
    "$ta_hits" \
    "Judge the task issue's author with gh-identity.sh task-author (trusted or agent passes under a map); author is for comment and PR authors (and plan-sprint's display)."
fi

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

One or more shipped-defect invariants regressed. Each check above corresponds to a
real defect this repo has already released at least once. If a check is wrong rather
than the code, fix the check deliberately and say so in the commit -- do not weaken it
to make a diff pass.
EOF
  exit 1
fi

echo "Invariant check passed: no known-wrong form has returned."
