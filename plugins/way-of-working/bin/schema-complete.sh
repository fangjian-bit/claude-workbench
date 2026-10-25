#!/bin/sh
# The deterministic predicate behind WB-D17 (#142) -- every dotted key path the
# schema documents must be PRESENT in a consuming repo's `.ai/project.yml`.
# `null` is the explicit "no value" wherever a key's own reference gives `null`
# a meaning; a key that is entirely absent is an unanswered question, never a
# silent default. Mirrors cursor-drift.sh's and plan-anchor.sh's shape: a
# predicate with a correctness argument, not a judgment call, so
# /way-of-working:resume's *Ensure the schema is complete* step and
# scripts/invariants-check.sh call this script rather than recomputing the
# check in prose.
#
# Usage:
#   schema-complete.sh check <file>
#     Prints, on stdout:
#       complete             -- every required key present and well-formed
#       incomplete           -- first line `incomplete`, then one line per
#                                finding:
#                                  missing <dotted.path> <kind>
#                                  invalid <dotted.path> <json-value>
#                                <dotted.path> may carry an index for one element of a list
#                                of maps: `identities.maintainer[1]`, `rulesets[0].source`.
#                                <kind> is one of: enum:<a>|<b>  nullable
#                                value  list  int. <json-value> is the OFFENDING
#                                value, compact JSON (`yq -o=json -I=0`),
#                                truncated. This is STRUCTURAL containment,
#                                not semantic neutralization: it keeps a
#                                malicious multi-line or fake-finding-shaped
#                                value from splitting across lines or forging
#                                a `missing `/`invalid ` line of its own (a
#                                JSON string literal can't open one), which
#                                matters because this file may be
#                                adversary-controlled on a branch other than
#                                the default (see resume/SKILL.md's *Check the
#                                branch-protection ruleset for drift* step
#                                and skills/resume/appendices/ruleset-migration.md,
#                                which reads a DIFFERENT copy of this same
#                                file for exactly that reason). It does NOT
#                                stop a quoted 200-character string from
#                                reading as an instruction to whatever later
#                                relays it in prose (a pick-up summary) --
#                                that reader must still treat the finding's
#                                value as data, never as something to act on,
#                                the same rule this schema's own § `planning`
#                                already states for a milestone description or
#                                issue body.
#       unreadable            -- the file doesn't exist or can't be read, its
#                                YAML doesn't parse, or `yq` is not on PATH
#     Always exits 0 -- the verdict is stdout, the caller decides policy.
#
#   schema-complete.sh keys
#     Prints the required dotted key paths, one per line, in schema order.
#     The four `review.ci_gate.*` sub-keys and the five `orchestration.*` sub-keys
#     are suffixed ` if-map` -- each group is required only when its parent
#     (`review.ci_gate`, `orchestration`) itself resolves to a map, never when it
#     is `null`. `identities` itself is unsuffixed and its four sub-keys carry ` if-map`,
#     as `orchestration` does. `rulesets` and `lanes` are suffixed ` if-present` -- the two OPTIONAL
#     paths: never reported when absent, validated when there (WB-D24 dual mode, WB-D34, below).
#     `lanes.dir` is suffixed ` if-map`, required only when `lanes` itself is a map.
#     Always exits 0.
#
# The key set is NOT derived from `.ai/project.yml` or from walking any YAML
# at all -- it is the union of the dotted paths BOTH documented examples in
# `reference/project-schema.md` show (Full schema + Worked example), STOPPING
# AT SEQUENCES (`gates.green`, `load_bearing_docs`, `code_paths`,
# `ruleset.*` lists are leaves; their elements are values, never keys of
# their own). Enum value sets (`planning.kind`, `backlog.kind`, `models.*`)
# are hardcoded below, not derived from the doc -- `scripts/invariants-check.sh`
# is what holds this list and the doc in sync, by set equality on `keys`'
# own output (conditional suffix stripped) against a real path-walk of both
# example blocks. A key present in `.ai/project.yml` but not in this list is
# ignored, never flagged -- two plugin versions may write the same file, and
# an unknown extra key is not this script's business.
#
# --- Presence vs. null, the whole point of this script -------------------
#
# A plain `yq eval '.a.b' file` traversal returns the literal string `null`
# BOTH when `.a.b` is present with an explicit null value AND when it is
# entirely absent -- yq does not distinguish the two on a bare path read
# (confirmed live: `.a.d` on a document with no `d` key under `a` prints
# `null`, tag `!!null`, exit 0, identical to `.a.b: null`). `has("key")`
# is what distinguishes them, and confirmed live to degrade gracefully
# rather than error when the node it's called on is itself null, a scalar,
# a sequence, or simply absent (`.x | has("y")` on a document with no `x`
# key at all still answers `false`, not an error) -- so a single-shot
# `<parent> | has("<lastseg>")` query is enough per key, with no need to
# walk each intermediate segment by hand.
#
# --- `invalid` is also a shape check for the routing keys ------------------
#
# `repo`/`backlog.repo` must match `owner/name` (checked in pure POSIX
# parameter expansion -- exactly one `/`, non-empty on both sides).
# `pr_base`/`migration_base` must round-trip through `git check-ref-format
# --branch` -- comparing the OUTPUT back to the input, not just the exit
# status, because `--branch` expands shorthand like `@{-1}` (the same
# reasoning `bin/review-base-anchor.sh`'s header records for the identical
# check there; a value spelled `-Cmain` reaching a later `git switch`
# un-checked is the exact bug that check guards against).
#
# All four also pass through `is_safe_chars`: every byte must be in
# `[A-Za-z0-9._/-]`. These are the keys OTHER skills interpolate, unsanitized,
# into shell command templates the model builds at runtime (a branch-cut, a
# `gh pr create --base {pr_base}`, a `[ "$R" != "{repo}" ]` comparison) --
# neither the owner/name split nor `check-ref-format` alone rejects shell
# metacharacters (a security-critic pass confirmed `repo: "a/b $(id)"` and
# ``pr_base: "m$(id>&2)"`` both read `complete` before this guard existed).
# `complete` on these four keys means safe to interpolate, not merely
# shape-plausible.
#
# --- What this script deliberately does NOT check --------------------------
#
# Cross-key consistency (`planning.kind: github_milestones` with
# `backlog.kind: file`; `backlog.kind: file` with `backlog.path: null`) is
# out of scope -- those are already documented config errors with their own
# reporting in the skills that hit them, and folding them in here would make
# this a validator, not a completeness check. `models.*` values are checked
# against the harness's known model names as a courtesy, not because this
# script is the enforcement point for that set changing.
#
# Permitted toolset: POSIX sh, `yq` (mikefarah v4 -- the python `yq` has a
# different syntax; `yq --version` in a fixture-less environment is the
# caller's job to confirm, not this script's), and `git` (check-ref-format
# only, the same narrow use `review-base-anchor.sh` makes of it). `yq`
# missing from PATH is `unreadable`, never treated as "no findings, therefore
# complete" -- `complete` needs positive evidence, exactly like
# `plan-anchor.sh`'s header states for its own `unreadable` cases.
#
# --- One yq call per key table, not per key (#189) -------------------------
#
# Every fact the checks need (present, tag, charset, compact JSON) is read in ONE
# `yq` expression per table, because process spawns dominate on Git Bash: the
# per-key form took ~100 spawns and ~3.6s per run (the fixture suite, ~2m15s).
# The `has()` query above is therefore `select(tag == "!!map") | has(...)`, which
# also reads as absent under a scalar parent instead of failing the whole call.
# Consequences kept on purpose, each with a fixture:
#   - rows must match the key table exactly, in order, else `unreadable` (a
#     multi-document file, or any row a value could forge, is never `complete`);
#   - the tag field is a closed set inside yq (a verbatim `!<..%0A..>` tag is
#     percent-decoded by yq into a real newline);
#   - an enum value must also pass the charset test, so `models.coder: "opus\n"`
#     is now `invalid` (it used to pass, via the lossy `$(...)` capture);
#   - a root that is a sequence is `unreadable` (yq refuses to index it -- a side
#     effect, not a deliberate check); a scalar, null or empty root still reads
#     `incomplete` with every key `missing`, as before;
#   - a trailing empty document (`---` after the content) is `unreadable` too;
#     it used to read every key `missing`, because yq answered once per document
#     (`true` then `false`), which never equalled `true`;
#   - a present child under a custom-tagged parent map (`planning: !custom`) reads
#     `missing`, because the guard requires the literal `!!map` tag. Fails closed,
#     and an exotic form; `yq`'s `kind` operator would restore the old answer.
# Needs a yq with `to_json(0)`, `to_string`, `//` and `select`; verified on
# v4.53.6. An older yq that cannot parse the expression prints `unreadable`.
set -eu

# --- the required key table -------------------------------------------------
# <dotted.path> <kind> <shape>
#   kind:  value | nullable | list | nelist | int | enum:<a>|<b>|...
#          | cigate (review.ci_gate only) | orchmap (orchestration only)
#          | identmap (identities only) | optnelist (rulesets only: optional, non-empty if present)
#          | optlanemap (lanes only: optional; null or a map if present)
#   shape: - | ownername | branch | ghlogin | rulename | textname | pair | lanesdir   (consulted for
#          value/nullable; `pair` is a {login, id} map, `identities.*_app` only; `textname`
#          is a ruleset name a reader binds as a value, #451; `lanesdir` is `lanes.dir`'s
#          absolute-path rule, WB-D34)
MAIN_KEYS='
repo value ownername
pr_base value branch
migration_base nullable branch
roadmap value -
sprints_dir value -
threat_model value -
planning.kind enum:files|github_milestones -
decisions.log value -
decisions.prefix value -
backlog.kind enum:github_issues|file -
backlog.repo nullable ownername
backlog.path nullable -
backlog.item_prefix nullable -
load_bearing_docs list -
code_paths list -
gates.green list -
review.ci_gate cigate -
agents.enabled list -
agents.diff_rule nullable list
models.architect enum:sonnet|opus|haiku|fable -
models.coder enum:sonnet|opus|haiku|fable -
models.second_opinion nullable enum:sonnet|opus|haiku|fable
orchestration orchmap -
identities identmap -
'

# WB-D24 (#378) dual-mode ruleset keys. `rulesets` is the new shape, a list of
# {name, source, rule_types} entries; the old `ruleset:` map is its alias for one
# release. Only resume and pr-checks read `rulesets` so far (#384); every other skill and bin/ script reads
# `ruleset.*`, so the legacy keys stay REQUIRED whether or not `rulesets` is present:
# a file with only the list would read `complete` and be unusable. `rulesets` is an
# optional extra -- silent when absent (`optnelist`), a non-empty sequence when present --
# and the checker does not compare it with `ruleset` (like every cross-key check). When a
# later release teaches the readers the list, the legacy keys become conditional here.
RULESETS_KEYS='
rulesets optnelist -
'
RULESET_KEYS='
ruleset.name value textname
ruleset.rule_types list -
ruleset.required_checks list -
'

# `lanes` (WB-D34) is the second OPTIONAL key. Absent is not declared and is never asked
# (`optlanemap`): silent when absent, `null` or a map when present (a scalar or a list is
# `invalid`). Only a map makes `lanes.dir` required, and it must be an absolute path of
# `A-Za-z0-9._/-` with no `//`, no `.` or `..` component and no trailing `/` -- the rule
# scripts/lanes/lane.sh holds for its lanes directory.
LANES_TOP='
lanes optlanemap -
'
LANES_KEYS='
lanes.dir value lanesdir
'

# `identities` is a nullable map exactly like `orchestration`: `null` is the explicit
# answer "this repo has not cut over to App identities" (the pre-WB-D24 model), a map is
# the declared set, and then these sub-keys are required -- present, so absent prompts.
# `maintainer` is a non-empty list of {login, id} pairs (trust is by declared identity,
# not author_association); each App is a {login, id} pair or `null` (not created yet).
# The checker confirms the sequence and the map, and every element (#452): a map with a
# positive-integer `id` and a `login` that passes the GitHub-login check. A reader still
# binds each login and id as a value, never splices one.
IDENT_KEYS='
identities.maintainer nelist -
identities.dev_app nullable pair
identities.reviewer_app nullable pair
identities.loop_app nullable pair
'

# The four sub-keys, required only when review.ci_gate resolves to a map.
CIGATE_KEYS='
review.ci_gate.check value -
review.ci_gate.header value -
review.ci_gate.attestation value -
review.ci_gate.triggers_on nullable list
'

# `orchestration` is a nullable map exactly like `review.ci_gate`: `null` is the
# explicit answer "the sprint-orchestrator loop never dispatches into this repo";
# a map is "it may", and then these sub-keys are required -- present, so absent
# prompts as everywhere else (WB-D17). `loop_identity` is `nullable`: `null` means
# "not declared yet" (plan v9 § 8.13d: optional until a dispatch), and a loop dispatch
# needing it non-null is the driver's own preflight, not this completeness check.
# `critics` and `human_only_paths` are `nelist`: an empty one is a control turned off
# (no critic can satisfy the floor; no path is protected) that must not read `complete`.
ORCH_KEYS='
orchestration.critics nelist -
orchestration.round_cap int -
orchestration.human_only_paths nelist -
orchestration.restrict_updates nullable rulename
orchestration.loop_identity nullable ghlogin
'

mode="${1:-}"
case "$mode" in
  keys)
    printf '%s\n' "$MAIN_KEYS" | while IFS=' ' read -r path kind shape; do
      [ -n "$path" ] || continue
      [ "$path" = "review.ci_gate" ] && continue   # printed via CIGATE_KEYS below
      [ "$path" = "orchestration" ] && continue    # printed via ORCH_KEYS below
      [ "$path" = "identities" ] && continue       # printed via IDENT_KEYS below
      printf '%s\n' "$path"
    done
    printf '%s\n' "$RULESET_KEYS" | while IFS=' ' read -r path kind shape; do
      [ -n "$path" ] || continue
      printf '%s\n' "$path"
    done
    printf '%s\n' "rulesets if-present"
    printf '%s\n' "lanes if-present"
    printf '%s\n' "$LANES_KEYS" | while IFS=' ' read -r path kind shape; do
      [ -n "$path" ] || continue
      printf '%s if-map\n' "$path"
    done
    printf '%s\n' "review.ci_gate"
    printf '%s\n' "$CIGATE_KEYS" | while IFS=' ' read -r path kind shape; do
      [ -n "$path" ] || continue
      printf '%s if-map\n' "$path"
    done
    printf '%s\n' "orchestration"
    printf '%s\n' "$ORCH_KEYS" | while IFS=' ' read -r path kind shape; do
      [ -n "$path" ] || continue
      printf '%s if-map\n' "$path"
    done
    printf '%s\n' "identities"
    printf '%s\n' "$IDENT_KEYS" | while IFS=' ' read -r path kind shape; do
      [ -n "$path" ] || continue
      printf '%s if-map\n' "$path"
    done
    exit 0
    ;;
  check) ;;
  *)
    echo "usage: schema-complete.sh check <file>" >&2
    echo "       schema-complete.sh keys" >&2
    echo unreadable
    exit 0
    ;;
esac

if [ "$#" -ne 2 ]; then
  echo "usage: schema-complete.sh check <file>" >&2
  echo unreadable
  exit 0
fi
FILE="$2"

if ! command -v yq >/dev/null 2>&1; then
  echo unreadable
  exit 0
fi
if [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then
  echo unreadable
  exit 0
fi
if ! yq eval '.' "$FILE" >/dev/null 2>&1; then
  echo unreadable
  exit 0
fi

findings=''
add_finding() { # add_finding <line, no trailing newline>
  if [ -z "$findings" ]; then
    findings="$1"
  else
    findings="$findings
$1"
  fi
}

truncate_json() { # truncate_json <compact-json> -- one line, capped length
  v="$1"
  max=200
  if [ "${#v}" -gt "$max" ]; then
    printf '%s...' "$(printf '%s' "$v" | cut -c1-"$max")"
  else
    printf '%s' "$v"
  fi
}

is_safe_chars() { # is_safe_chars <value> -- every byte in [A-Za-z0-9._/-], non-empty
  # These four routing keys (repo, pr_base, backlog.repo, migration_base) are read
  # by OTHER skills and interpolated -- unsanitized -- into shell command
  # templates the model builds at runtime (a branch-cut, a `gh pr create --base`,
  # a comparison against `{repo}`). "Shape-valid" alone is not "safe to
  # interpolate": `git check-ref-format --branch` and a bare owner/name split
  # both happily accept `$(id)`, backticks, `;`, `|`, `&`, spaces and quotes --
  # confirmed live, a security-critic pass found `complete` on
  # `repo: "a/b $(id)"` and `pr_base: "m$(id>&2)"`` before this charset guard
  # existed. Real GitHub owner/repo names and this plugin's own branch names
  # never need anything outside this set, so restricting to it costs nothing
  # legitimate and closes the injection path at the source, rather than
  # depending on every future reader to re-quote correctly.
  case "$1" in
    '') return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
    *) return 0 ;;
  esac
}

is_owner_name() { # is_owner_name <value> -- exactly one '/', non-empty, non-dot-only both sides
  v="$1"
  is_safe_chars "$v" || return 1
  case "$v" in
    */*) : ;;
    *) return 1 ;;
  esac
  before="${v%%/*}"
  after="${v#*/}"
  case "$after" in
    */*) return 1 ;;
  esac
  [ -n "$before" ] && [ -n "$after" ] || return 1
  # A segment of exactly "." or ".." is syntactically owner/name-shaped (one
  # slash, non-empty both sides) but is a path-traversal token, not a real
  # GitHub owner or repo name. A security-critic pass confirmed LIVE that
  # `backlog.repo: "../user"` read `complete` here and that `gh api
  # repos/../user` actually resolves -- the API does not reject a `..`
  # segment, it walks it, the same way a shell `cd` would.
  case "$before" in '.' | '..') return 1 ;; esac
  case "$after" in '.' | '..') return 1 ;; esac
  return 0
}

is_rule_name() { # is_rule_name <unquoted-json> -- see the rulename shape
  case "$1" in
    '' | -* | *\\* | *'"'*) return 1 ;;
  esac
}

is_lanes_dir() { # is_lanes_dir <value> -- an absolute path, no //, no . or .. component, no trailing /
  case "$1" in
    /*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *// | */) return 1 ;;
  esac
  case "$1/" in
    *//* | */./* | */../*) return 1 ;;
  esac
  return 0
}

is_gh_login() { # is_gh_login <value> -- a GitHub login, optionally an App's `<slug>[bot]`
  # `orchestration.loop_identity` is compared against PR authors and interpolated by a
  # later driver, so the stem is held to [A-Za-z0-9-], non-empty, never leading or trailing with
  # `-` (leading, it would reach a command as a flag), at most 39 characters (GitHub's own cap).
  # The bracketed suffix is the ONLY place a bracket is allowed, and only exactly `[bot]`.
  stem="${1%'[bot]'}"
  case "$stem" in
    '' | -* | *- | *[!A-Za-z0-9-]*) return 1 ;;
  esac
  [ "${#stem}" -le 39 ]
}

is_pos_int() { # is_pos_int <json> -- digits only, no leading zero, at most three
  case "$1" in
    '' | 0* | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 3 ]
}

is_branch_name() { # is_branch_name <value> -- safe charset, round-trips check-ref-format
  v="$1"
  is_safe_chars "$v" || return 1
  out=$(git check-ref-format --branch "$v" 2>/dev/null) || return 1
  [ "$out" = "$v" ]
}


# ONE `yq` call reads every fact the checks below need, instead of 3-5 spawns per
# key (#189: ~100 spawns per run made the fixture suite take ~2m15s on Git Bash,
# where process-spawn latency dominates). Each key becomes one tab-separated row,
# in table order:
#   <path> <kind> <shape> <present> <tag> <safe> <json>
# `kind`/`shape` are the table's own literals, echoed back so the loop below needs
# no lookup. `present` is `has()` on the parent, guarded by `select(tag == "!!map")`
# so a scalar parent (`planning: 5`) reads as absent, never as a failed call that
# would take every other key down with it. `safe` is the [A-Za-z0-9._/-] charset (or, for
# the `textname` shape, a no-control-character test)
# test done INSIDE yq, against the parsed string, never against a shell-captured
# `$(...)` value: `$(...)` strips every trailing newline, so `pr_base: "main\n"`
# would read back as the harmless "main" and pass a check that never saw the
# newline (a round-2 security-critic finding). `json` is `to_json(0)` -- compact,
# one line, newlines escaped -- so a row can never be split by a value, and a
# string that passed the charset `safe` test has no escapes to undo (see `unquote`; a `textname` is never unquoted). `@tsv` is not
# used: it csv-quotes fields containing `"`, which every JSON string does.
TAB=$(printf '\t')

build_rows() { # build_rows <table> -- the yq expression, one row per key
  expr=''
  while IFS=' ' read -r path kind shape; do
    [ -n "$path" ] || continue
    case "$path" in
      *.*) parent=".${path%.*}"; last="${path##*.}" ;;
      *)   parent="."; last="$path" ;;
    esac
    v="($parent | select(tag == \"!!map\") | .${last})"
    row="\"$path\t$kind\t$shape\t\""
    row="$row + (((($parent | select(tag == \"!!map\") | has(\"$last\")) // false)) | to_string)"
    row="$row + \"\t\" + (($v | tag | select(. == \"!!str\" or . == \"!!null\" or . == \"!!map\" or . == \"!!seq\" or . == \"!!bool\" or . == \"!!int\" or . == \"!!float\")) // \"other\")"
    # `safe`: a string by charset; an INT by its RAW spelling (`to_string` keeps `0x10`,
    # `+2`, `1_0`, `02` as written, which `to_json` would normalize to a clean number a
    # later `yq` read would not return).
    # `textname` (a ruleset name, which a reader reads into a variable and binds with
    # `jq --arg`, never splicing it into shell text, #451): any non-empty string with no control character
    # (`\p{Cc}`, so no newline or tab). A `'`, a space or a `$` is a legal name; the binding,
    # not the charset, is what keeps them inert.
    case "$shape" in
      textname) safe_test='test("^[^\\p{Cc}]+$")' ;;
      *) safe_test='test("^[A-Za-z0-9._/-]+$")' ;;
    esac
    row="$row + \"\t\" + ((($v | select(tag == \"!!str\") | $safe_test) // ($v | select(tag == \"!!int\") | to_string | test(\"^[1-9][0-9]{0,2}\$\")) // false) | to_string)"
    row="$row + \"\t\" + (($v | to_json(0)) // \"null\")"
    if [ -z "$expr" ]; then expr="$row"; else expr="$expr, $row"; fi
  done <<EOF_ROWS
$1
EOF_ROWS
  printf '%s' "$expr"
}

unquote() { # unquote <json-string> -- "abc" -> abc. Only ever called on a string whose
            # charset has no quote or backslash -- by the charset `safe` column (never `textname`'s), or (rulename, ghlogin) by a
            # check made right after -- so there are no JSON escapes to undo.
  v="${1#\"}"
  printf '%s' "${v%\"}"
}

enum_match() { # enum_match <value> <pipe-separated-set>
  v="$1"; set_str="$2"
  old_ifs="$IFS"
  IFS='|'
  match=1
  for opt in $set_str; do
    [ "$v" = "$opt" ] && match=0
  done
  IFS="$old_ifs"
  return "$match"
}

invalid_finding() { # invalid_finding <path> <json>
  add_finding "invalid $1 $(truncate_json "$2")"
}

check_value_shape() { # check_value_shape <shape> <tag> <safe> <json> -- exit 0 if OK,
                       # prints nothing; caller records the finding. Requires tag =
                       # !!str for every scalar shape (ownername/branch/enum:*) -- a
                       # critic pass on this script's first version found `pr_base:
                       # true` (tag !!bool) and `repo: [a/b]` (tag !!seq) both read
                       # as VALID, because `git check-ref-format`/the owner-name
                       # split ran on yq's plain scalar rendering of the value without
                       # ever checking what kind of node produced that rendering.
                       # "Shape-valid" now requires "is actually a string" first.
  shape="$1"; tag="$2"; safe="$3"; json="$4"
  case "$shape" in
    lanesdir)
      # `safe` holds the charset; the rest is lane.sh's lanes_shape_ok.
      [ "$tag" = '!!str' ] && [ "$safe" = true ] && is_lanes_dir "$(unquote "$json")"
      ;;
    ownername)
      [ "$tag" = '!!str' ] && [ "$safe" = true ] && is_owner_name "$(unquote "$json")"
      ;;
    branch)
      [ "$tag" = '!!str' ] && [ "$safe" = true ] && is_branch_name "$(unquote "$json")"
      ;;
    rulename)
      # A ruleset NAME a later preflight binds into a lookup: a non-empty string that
      # cannot start with `-` (a flag) and carries no quote or escape (the JSON form
      # shows any control character as one). Spaces are legal in a ruleset name.
      [ "$tag" = '!!str' ] && is_rule_name "$(unquote "$json")"
      ;;
    textname)
      # `safe` already holds "a string, non-empty, no control character" (build_rows).
      [ "$tag" = '!!str' ] && [ "$safe" = true ]
      ;;
    ghlogin)
      # No `safe` test: its charset has no brackets, and the suffix needs them. The
      # JSON form is checked instead -- a `"` or `\` (any escape) is outside the stem
      # charset, so it can never pass.
      [ "$tag" = '!!str' ] && is_gh_login "$(unquote "$json")"
      ;;
    enum:*)
      set_str="${shape#enum:}"
      [ "$tag" = '!!str' ] && [ "$safe" = true ] && enum_match "$(unquote "$json")" "$set_str"
      ;;
    pair)
      # A nullable {login, id} pair (`identities.*_app`): a map, never a scalar or list.
      [ "$tag" = '!!map' ]
      ;;
    list)
      # A nullable key whose non-null form is a LIST, never a scalar --
      # `review.ci_gate.triggers_on` (a path-glob list, per `code_paths`'s own shape) and
      # `agents.diff_rule` are the two such keys. A round-2 architect pass caught the
      # shapeless catch-all below rejecting exactly this: `triggers_on: [src/]`,
      # the form `project-schema.md` itself documents, read as `invalid` once
      # the shapeless branch started rejecting `!!seq` generally.
      [ "$tag" = '!!seq' ]
      ;;
    *)
      # No shape: any scalar is fine (str/int/bool/float); map/seq is not --
      # a critic pass found `roadmap: {a: 1}` read as VALID under the old code,
      # which never checked a shapeless `value` key's tag at all.
      case "$tag" in
        '!!map' | '!!seq') return 1 ;;
        *) return 0 ;;
      esac
      ;;
  esac
}

check_row() { # check_row <path> <kind> <shape> <present> <tag> <safe> <json>
  path="$1"; kind="$2"; shape="$3"; present="$4"; tag="$5"; safe="$6"; json="$7"

  if [ "$present" != true ]; then
    case "$kind" in optnelist | optlanemap) return ;; esac   # an absent optional key is not a finding
    case "$kind" in cigate | orchmap | identmap) kind=nullable ;; nelist) kind=list ;; esac   # printed as the interview asks it
    add_finding "missing $path $kind"
    return
  fi

  case "$kind" in
    value)
      if [ "$tag" = '!!null' ]; then
        invalid_finding "$path" "$json"; return
      fi
      check_value_shape "$shape" "$tag" "$safe" "$json" || { invalid_finding "$path" "$json"; return; }
      ;;
    nullable)
      if [ "$tag" = '!!null' ]; then
        :   # valid -- the explicit no-value answer
      else
        check_value_shape "$shape" "$tag" "$safe" "$json" || { invalid_finding "$path" "$json"; return; }
      fi
      ;;
    enum:*)
      set_str="${kind#enum:}"
      if [ "$tag" != '!!str' ] || [ "$safe" != true ]; then invalid_finding "$path" "$json"; return; fi
      enum_match "$(unquote "$json")" "$set_str" || { invalid_finding "$path" "$json"; return; }
      ;;
    list)
      [ "$tag" = '!!seq' ] || { invalid_finding "$path" "$json"; return; }
      ;;
    nelist)
      { [ "$tag" = '!!seq' ] && [ "$json" != '[]' ]; } || { invalid_finding "$path" "$json"; return; }
      ;;
    cigate)
      case "$tag" in
        '!!null') : ;;
        '!!map') cigate_is_map=1 ;;
        *) invalid_finding "$path" "$json" ;;
      esac
      ;;
    orchmap)
      case "$tag" in
        '!!null') : ;;
        '!!map') orch_is_map=1 ;;
        *) invalid_finding "$path" "$json" ;;
      esac
      ;;
    identmap)
      case "$tag" in
        '!!null') : ;;
        '!!map') ident_is_map=1 ;;
        *) invalid_finding "$path" "$json" ;;
      esac
      ;;
    optnelist)
      { [ "$tag" = '!!seq' ] && [ "$json" != '[]' ]; } || invalid_finding "$path" "$json"
      ;;
    optlanemap)
      case "$tag" in
        '!!null') : ;;
        '!!map') lanes_is_map=1 ;;
        *) invalid_finding "$path" "$json" ;;
      esac
      ;;
    int)
      # A quoted "2" is !!str and invalid on purpose: the key is a number, not text.
      { [ "$tag" = "!!int" ] && [ "$safe" = true ] && is_pos_int "$json"; } || invalid_finding "$path" "$json"
      ;;
  esac
}

run_table() { # run_table <table> -- one yq call, then check each row
  # An outright yq failure here (the file already parsed above) is unreadable, not
  # a pile of per-key findings: fail closed rather than guess.
  rows=$(yq eval "$(build_rows "$1")" "$FILE" 2>/dev/null) || { echo unreadable; exit 0; }
  # The output must be exactly one row per table key, in table order -- checked, not
  # assumed. yq evaluates the expression once PER DOCUMENT, so a multi-document file
  # (`---`) yields a second set of rows that each look fine alone while a consumer's
  # `yq '.pr_base'` prints both documents' values; and any field that let a value
  # forge a row would land here as a count or path mismatch. Either is `unreadable`.
  # (The tag field is a closed set inside yq for the same reason: a verbatim tag
  # `!<...%0A...>` is decoded by yq into real separators.)
  want=''
  while IFS=' ' read -r path _kind _shape; do
    [ -n "$path" ] || continue
    want="$want$path
"
  done <<EOF_WANT
$1
EOF_WANT
  # A HEREDOC, never a pipe (`cmd | while read`) -- a pipe forks the loop body
  # into a subshell under some shells even without an explicit `()`, and
  # `findings`/`cigate_is_map` set inside it would not survive to the parent.
  while IFS="$TAB" read -r path kind shape present tag safe json; do
    next="${want%%
*}"
    [ -n "$next" ] && [ "$path" = "$next" ] || { echo unreadable; exit 0; }
    want="${want#*
}"
    check_row "$path" "$kind" "$shape" "$present" "$tag" "$safe" "$json"
  done <<EOF_ROWS
$rows
EOF_ROWS
  [ -z "$want" ] || { echo unreadable; exit 0; }
}

# Each `rulesets` entry is a map with a `name` (the `ruleset.name` rule, #451: a non-empty
# string with no control character), a `source` of exactly `repo` or `org`, and `rule_types`
# as a list (#452). `required_checks` is optional: absent or `null` is "none", anything else
# must be a list (#527; a string there made `pr-checks` drop the entry's checks without a
# word). The elements of both lists stay the reader's to bind. One yq call, one row per
# entry: <index> <is_map> <name_ok> <source_ok> <rule_types_ok> <required_checks_ok>
# <entry-json> <name-json> <source-json> <rule_types-json> <required_checks-json>. The index is yq's
# own integer, the flags are booleans computed inside yq and every json is `to_json(0)`, so a
# value cannot forge a row (no raw tag or scalar text is read back).
check_ruleset_entries() {
  expr='.rulesets | explode(.) | select(tag == "!!seq") | to_entries | .[] | (.key | to_string)
    + "\t" + ((.value | tag == "!!map") | to_string)
    + "\t" + ((((.value | select(tag == "!!map") | .name | select(tag == "!!str") | test("^[^\\p{Cc}]+$")) // false)) | to_string)
    + "\t" + ((((.value | select(tag == "!!map") | .source | select(tag == "!!str") | (. == "repo" or . == "org")) // false)) | to_string)
    + "\t" + ((((.value | select(tag == "!!map") | .rule_types | kind == "seq") // false)) | to_string)
    + "\t" + ((((.value | select(tag == "!!map") | [.required_checks | select(kind != "seq" and tag != "!!null")] | length == 0) // false)) | to_string)
    + "\t" + (.value | to_json(0))
    + "\t" + ((.value | select(tag == "!!map") | .name | to_json(0)) // "null")
    + "\t" + ((.value | select(tag == "!!map") | .source | to_json(0)) // "null")
    + "\t" + ((.value | select(tag == "!!map") | .rule_types | to_json(0)) // "null")
    + "\t" + ((.value | select(tag == "!!map") | .required_checks | to_json(0)) // "null")'
  entry_rows=$(yq eval "$expr" "$FILE" 2>/dev/null) || { echo unreadable; exit 0; }
  [ -n "$entry_rows" ] || return 0
  while IFS="$TAB" read -r idx is_map name_ok src_ok rt_ok rc_ok ejson njson sjson rjson cjson; do
    case "$idx" in '' | *[!0-9]*) echo unreadable; exit 0 ;; esac
    if [ "$is_map" != true ]; then
      invalid_finding "rulesets[$idx]" "$ejson"; continue
    fi
    [ "$name_ok" = true ] || invalid_finding "rulesets[$idx].name" "$njson"
    [ "$src_ok" = true ] || invalid_finding "rulesets[$idx].source" "$sjson"
    [ "$rt_ok" = true ] || invalid_finding "rulesets[$idx].rule_types" "$rjson"
    [ "$rc_ok" = true ] || invalid_finding "rulesets[$idx].required_checks" "$cjson"
  done <<EOF_ENTRIES
$entry_rows
EOF_ENTRIES
}

# Each `identities.maintainer` entry and each non-null App is a map with a positive-integer
# `id` (a bare integer of at most 15 digits, so it is exact in any reader: a quoted one is
# `!!str`, and a reader that matched on a string would trust nothing) and a `login` that
# passes the GitHub-login check (#452). A maintainer is a person, so its login may not end in
# `[bot]` -- that suffix is an App's, and an App declared as a maintainer would hold a
# maintainer's trust. Every entry's rows are read from `explode(.)` of its own list, the value
# the readers bind, so a merge key or alias inside an entry cannot make the checker and a reader
# see different entries (only the subtree is exploded: a whole-document explode would expand
# every alias in the file on each call). The list or map itself is shape-checked above without
# exploding, so an aliased container is `invalid` there. Same row discipline as above: <index> <is_map> <id_ok> <login_is_string> <login-json> <entry-json>.
PAIR_ROW='(.key | to_string)
    + "\t" + ((.value | tag == "!!map") | to_string)
    + "\t" + ((((.value | select(tag == "!!map") | .id | select(tag == "!!int") | to_string | test("^[1-9][0-9]{0,14}$")) // false)) | to_string)
    + "\t" + ((((.value | select(tag == "!!map") | .login | tag == "!!str") // false)) | to_string)
    + "\t" + ((.value | select(tag == "!!map") | .login | to_json(0)) // "null")
    + "\t" + (.value | to_json(0))'

check_pairs() { # check_pairs <yq sequence expression> <label> <indexed: 1 = maintainer[i], 0 = a single App>
  pair_rows=$(yq eval "$1 | explode(.) | select(tag == \"!!seq\") | to_entries | .[] | $PAIR_ROW" "$FILE" 2>/dev/null) || { echo unreadable; exit 0; }
  [ -n "$pair_rows" ] || return 0
  while IFS="$TAB" read -r idx is_map id_ok lstr ljson ejson; do
    case "$idx" in '' | *[!0-9]*) echo unreadable; exit 0 ;; esac
    label="$2"
    [ "$3" = 1 ] && label="$2[$idx]"
    login=$(unquote "$ljson")
    if [ "$is_map" = true ] && [ "$id_ok" = true ] && [ "$lstr" = true ] && is_gh_login "$login" \
      && { [ "$3" != 1 ] || [ "${login%'[bot]'}" = "$login" ]; }; then
      :
    else
      invalid_finding "$label" "$ejson"
    fi
  done <<EOF_PAIRS
$pair_rows
EOF_PAIRS
}

# `identities.dev_app.commit_route` (#601, WB-D36) is an optional sub-key, checked here as
# `rulesets[].required_checks` is in its entry check above: undeclared is not reported (it
# selects `git`), and a present one must be the string `git` or `api`. Anything else, `null`
# included, is an invalid finding with the value as `to_json(0)`. It is not a row of any key
# table, so the `keys` output does not list it.
check_commit_route() {
  route_row=$(yq eval '.identities.dev_app | explode(.) | select(tag == "!!map")
    | (has("commit_route") | to_string)
    + "\t" + ((((.commit_route | select(tag == "!!str") | (. == "git" or . == "api")) // false)) | to_string)
    + "\t" + (.commit_route | to_json(0))' "$FILE" 2>/dev/null) || { echo unreadable; exit 0; }
  [ -n "$route_row" ] || return 0
  IFS="$TAB" read -r route_present route_ok route_json <<EOF_ROUTE
$route_row
EOF_ROUTE
  [ "$route_present" = true ] || return 0
  [ "$route_ok" = true ] || invalid_finding identities.dev_app.commit_route "$route_json"
}

check_identity_entries() {
  check_pairs '.identities.maintainer' identities.maintainer 1
  for app in dev_app reviewer_app loop_app; do
    check_pairs "[.identities.$app | explode(.) | select(tag == \"!!map\")]" "identities.$app" 0
  done
  check_commit_route
}

cigate_is_map=0
orch_is_map=0
ident_is_map=0
lanes_is_map=0
run_table "$MAIN_KEYS"
run_table "$RULESETS_KEYS"
check_ruleset_entries
run_table "$RULESET_KEYS"
run_table "$LANES_TOP"
[ "$lanes_is_map" = 1 ] && run_table "$LANES_KEYS"
[ "$cigate_is_map" = 1 ] && run_table "$CIGATE_KEYS"
[ "$orch_is_map" = 1 ] && run_table "$ORCH_KEYS"
[ "$ident_is_map" = 1 ] && run_table "$IDENT_KEYS"
[ "$ident_is_map" = 1 ] && check_identity_entries

if [ -z "$findings" ]; then
  echo complete
else
  echo incomplete
  printf '%s\n' "$findings"
fi
exit 0
