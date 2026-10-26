#!/bin/sh
# Derive the review step from GitHub state, and decide whether it may auto-start (WB-D22,
# `#230`; plan v9 § 8.4b).
#
# After a no-op handoff (`/way-of-working:handoff`, *The no-op handoff*) `main`'s ledger no
# longer carries "review or merge PR N next": the only record is `.ai/state.json`, which is
# git-ignored and local. So `/way-of-working:resume` derives that step from GitHub, and lets
# `state.json` only VOTE on it. This script is both halves, as a tested predicate with a
# correctness argument rather than prose a session re-derives (WB-D10).
#
# Two modes, both pure: every fact arrives as an argument or on stdin, nothing here calls
# `gh` or `git`, so the fixtures in tests/review-step.test.sh cover every verdict.
#
# --- derive -----------------------------------------------------------------------------
#
#   <records> | review-step.sh derive <login> <repo> <backlog-repo> <N> <limit>
#
# <login> is the ACTING login: in user mode the running login from a fresh `gh api user --jq
# .login`, in App mode the declared `identities.dev_app.login` -- either way the output of the
# `login` mode below, never a value the caller typed; <repo> is `{repo}`;
# <backlog-repo> is `{backlog.repo}` or `-` when it is null; <N> is `plan_anchor.task_issue`; <limit> is
# the `--limit` the caller gave `gh pr list`.
# stdin is one open-PR record per line, TAB-separated, from:
#
#   gh pr list --repo {repo} --state open --limit 200 \
#     --json number,state,isCrossRepository,author,headRefOid,title,body \
#     --jq '.[] | [.number, .state, .isCrossRepository, .author.login, .headRefOid, .title, .body] | @tsv'
#
# A PR qualifies when ALL hold: state is OPEN; isCrossRepository is false; its author's
# login equals <login> (case-insensitively -- GitHub logins are); and its title or body
# names task #<N>. The task is named `#N` or `<repo>#N` when <backlog-repo> is `-` or
# equals <repo>, else `<backlog-repo>#N` -- never the bare `#N`, which would then mean an
# issue in THIS repo. A mention counts only when it is not preceded by a word character or
# `/` (so `foo#230`, `xyz/foo#230` and `x/230` do not name it) and not followed by a digit
# (`#2301` is another issue). The `<repo>#N` form is anchored at the start of `<repo>`
# itself, for the same reason.
#
# `@tsv` escapes a tab, newline, carriage return and backslash in a value as `\t`, `\n`,
# `\r`, `\\`. A body line that BEGINS with `#230` would then read as `\n#230`, preceded by
# the word character `n`, and a real mention would be missed. So each escape is decoded
# left to right (the three whitespace ones to a space, `\\` to a backslash) before matching.
#
# Prints exactly one line to stdout and exits 0:
#   none               -- no PR qualifies
#   one <M> <oid>      -- exactly one qualifies; <oid> is its headRefOid, 40 hex
#   many <M> <M>...    -- two or more qualify, ascending by number
# Exits 2, printing NOTHING to stdout, when the question cannot be answered: a malformed
# argument, a record with the wrong field count, a number or head that is not what GitHub
# prints, or a state/isCrossRepository outside the vocabulary. The caller treats 2 as "derived
# nothing, auto-starts nothing" -- never as `none`.
#
# The caller must not let a failed `gh` call reach this script (chain with `&&`, redirect
# from a file): a document that never arrived reads as `none`, the fail-open that
# review-gate-state.sh's own header describes. A list of <limit> or more records may have been
# truncated (newest first, so an older qualifying PR is the one dropped, which could turn `many`
# into `one`): that exits 2, never an answer.
#
# An App's PR author: when <login> ends `[bot]` (the REST form a declared `dev_app` takes), the
# author also qualifies as `app/<stem>`, the form `gh pr list --json author` can report for a bot.
# Only that one spelling is added, and only for a `[bot]` <login>: the bare `<stem>` never
# matches, so a USER account that happens to share an App's slug does not read as the App.
#
# --- login ------------------------------------------------------------------------------
#
#   review-step.sh login <mode> <user-login> <dev-app-login>
#
# Which login the derivation runs as. The caller (resume's derive chain, handoff's no-op
# handoff) establishes <mode> by `reference/conventions.md` § *Acting identity and reach*, not by a
# new probe: `user` when `gh api user` answered, `app` when it was refused (or failed) and the token is an
# installation token that reaches {repo} (`gh-identity.sh reach`). Under an installation token
# `gh api user` is refused (403, measured in `#380`), so there is no login to read; the identity is
# the one the repo DECLARES for the dev flow, `identities.dev_app.login` from the default branch's
# copy. Which App holds the token is NOT proven here, so `decide` never lets App mode reach `auto`
# (its `mode` key): a reviewer or loop App token would otherwise run as the dev App.
#   user  -- prints <user-login>. <dev-app-login> is ignored (pass `-`).
#   app   -- prints <dev-app-login>. <user-login> is ignored (pass `-`).
# Prints one login and exits 0, or exits 2 printing NOTHING: an unknown mode, an empty identity for the
# mode chosen (the other mode's argument is not read), a
# login that is not an account name (letters, digits and `-`, no leading, trailing or doubled `-`),
# an App login without the `[bot]` suffix, a user-mode login WITH it, or the identity the mode needs
# being `-`. That last case
# is the fail-closed one: `app` with `dev_app` null (or undeclared, or malformed -- the caller maps
# all three to `-`) derives NOTHING, and never falls back to the user login or to a guess.
# The caller treats 2 as "derived nothing, auto-starts nothing", as for `derive`.
#
# --- decide -----------------------------------------------------------------------------
#
#   review-step.sh decide key=value ...
#
# Keys (all required; an unknown key, a missing key or an empty value exits 2):
#   derived      the whole `derive` line, as one argument (`derived='one 12 <oid>'`)
#   gate         `set` | `null` | `unreadable` -- `review.ci_gate` from the DEFAULT branch's
#                copy, never the working tree's
#   gate_state   the review-gate-state.sh word on the derived head (`success | pending |
#                failure | absent`), or `-` whenever no gate state was read: the gate is not `set`,
#                or derived is none or many
#   state        `present` | `absent` -- whether .ai/state.json exists
#   sr_number    pointers.review_pr.number, or `null` / `-` when missing
#   sr_head      pointers.review_pr.head_oid, or `null` / `-` when missing
#   next_action  the cursor's next_action, verbatim
#   task_issue   plan_anchor.task_issue
#   backlog_repo `{backlog.repo}` from the default branch's copy, or `-` when null
#   repo         `{repo}`
#   head         this checkout's `git rev-parse HEAD`, 40 hex
#   branch       this checkout's branch (`git branch --show-current`), or `-` when HEAD is detached
#   base         `pr_base` from the DEFAULT branch's copy, never the working tree's
#   base_head    `git rev-parse origin/<base>` after a fetch of it, 40 hex, or `-` when unreadable
#   last_commit  state.json's `last_commit` resolved to a full oid (`cursor-drift.sh oid
#                "<last_commit>"`), or `-` when it does not resolve or is missing
#   tree         `clean` | `dirty`
#   model        assigned_model from state.json
#   architect    `{models.architect}` from the default branch's copy
#   fresh        `yes` | `no` -- `yes` only when the conversation had no assistant turn and no work
#                before the resume (harness commands such as /clear and /model do not count)
#   login        the acting login, the same `login`-mode output `derive` took
#   mode         `user` | `app`: the mode `login` ran in. `app` never reaches `auto`: an installation
#                token's App is not proven by this derivation (conventions.md § *Acting identity and reach*, *Name the
#                mode*), so a would-be `auto` reads `show <M> app-mode` and waits for a human "go"
#   loop_identity  `orchestration.loop_identity` from the DEFAULT branch's copy, or `-` when it
#                is null or the whole `orchestration` block is
#
# Prints exactly one line and exits 0:
#   none                    -- derived none, or <login> equals <loop_identity> (the loop-identity
#                              guard below: nothing is derived, whatever `derived` says)
#   unreadable              -- one PR was derived but the gate could not be read (gate=unreadable);
#                              nothing is derived. (none and many print as themselves.) A derived
#                              value that is not none|one|many exits 2 instead (unless the loop-identity
#                              guard fires first), as does a failed derive
#   many <M> <M>...         -- several qualify; show all, wait
#   merge <M>               -- gate is null: "PR #M awaits your merge"; a report, nothing to start
#   reviewed <M>            -- gate is set and already reads success on the head: a report (unless
#                              state.json pins a different head for this PR: show ... head-moved)
#   auto <M> <oid>          -- the review step may start: /way-of-working:architect-review
#                              <M> --pin <oid>
#   show <M> <reason,...>   -- the review step is derived but must not start; show it, wait.
#                              Reasons, in this order: no-state, review-pr, head-moved,
#                              token, checkout, last-commit, model, app-mode, not-fresh
#
# What `auto` requires beyond the derivation, and why each is here (WB-D22, § 8.4b):
#   no-state    .ai/state.json must exist. A fresh machine derives the step and waits: one
#               "go" from the human runs it.
#   review-pr   pointers.review_pr.number must be the derived PR. A different PR, or none, is
#               the disagreement case.
#   head-moved  review_pr.head_oid must be the derived PR's CURRENT head. A fix pushed since
#               the pin re-arms the gate on a commit nobody pinned.
#   token       next_action begins `review PR #M — ` and then `task #N — ` (or
#               `task <backlog-repo>#N — `), M the derived number and N task_issue. The
#               ledger's Next: is NOT compared; during a review it still names the task.
#   checkout    the checkout is the BASE, synced: <branch> equals <base>, HEAD equals <base_head>
#               (origin/<base>'s tip), and the tree is clean (WB-D22, `#283`). Never the work
#               branch: a session that starts there loads the PR's own `.claude/settings.json`
#               hooks, `CLAUDE.md` and `.mcp.json`, and the author's `CLAUDE.md` would sit in the
#               reviewer's context as authority. /way-of-working:architect-review needs nothing from the PR's
#               working tree (it syncs to the base, pins from GitHub, and runs PR code only in a
#               review-sandbox.sh checkout). <base> is the default branch's copy of `pr_base`:
#               the working tree's could name the work branch itself. state.json is git-ignored,
#               so the pin survives the switch to the base.
#   last-commit state.json's `last_commit` (resolved) equals the pin, `review_pr.head_oid`. The
#               review-shape drift rule: `last_commit` is the work branch's HEAD, which is the
#               pin, so on the base cursor-drift.sh reads `drift` by construction and is NOT
#               consulted for this shape. Nothing here runs `next_action` (what starts is built
#               from the derived PR), so the base moving past the work is not what drift
#               guards; a cursor whose own two fields disagree is, and reads `show`.
#   model       assigned_model equals {models.architect} from the default branch. Not merely
#               "matches the running model": a state.json naming another model must not start
#               the review on it. resume checks the running model separately.
#   app-mode    `mode=app`: the session holds an installation token, whose App this derivation does not prove (the
#               loop-identity guard sees only the declared dev App), so the step is shown and a
#               human's "go" starts it. Never `auto` in App mode (`#381`).
#   not-fresh   a /model switch inside the conversation that wrote the PR is not a fresh
#               session, and the gate's premise is a fresh one.
# The reasons are evaluated only when the step is a review (gate set, not yet success):
# for `null` there is nothing to start, so it is a report whatever state.json says; an
# already-reviewed head is a report too, unless state.json pins a different head for that PR.
#
# The loop-identity guard (WB-D22, `#295`): a session running AS the loop's own identity derives
# nothing -- `none`, ahead of every other verdict, `derived` and `gate` included (so a malformed
# `derived` under the guard prints `none`, not exit 2). Both sides are folded the way
# `plan-anchor.sh` and `review-sandbox.sh trust` fold them: case-insensitively (GitHub logins are)
# and with one trailing `[bot]` ignored, so a bare-slug `loop_identity` (the schema's shape check
# allows both) still matches an App's REST login `<slug>[bot]`. Folding can only turn a verdict into
# `none`, the safe direction. A non-null `loop_identity` outside the schema's shape (a stem of
# letters, digits and `-`, no leading or trailing `-`, at most 39 characters, optional `[bot]`, judged
# case-insensitively)
# exits 2: the default branch's copy is not the one `schema-complete.sh` checked. `-` (null) means
# no identity is declared, so the guard never fires; an empty value is refused above, so it can
# never be read as an empty login matching. (Under an installation token the login is the declared
# `dev_app`, via the `login` mode, so the guard compares the DECLARED dev App, not the token held: a
# loop-App token is not caught here, which is why App mode never reaches `auto`.) The caller passes the DEFAULT branch's value, never the working
# tree's: a branch under resume could otherwise blank it. This does not close the stale-value case
# (a stale value does not equal the acting login); that stays with the driver's preflight.
#
# next_action is DATA. It is compared, never executed or interpreted: what runs is built from
# the GitHub-derived number, so a harmful next_action can at worst make this answer `show`.
#
# Permitted toolset: POSIX sh + awk. No jq, no yq, no python.
set -eu

die() { echo "review-step.sh: $*" >&2; exit 2; }

mode="${1:-}"
[ -n "$mode" ] || die "usage: review-step.sh derive|decide|login ..."
shift

is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
is_oid() { [ "${#1}" -eq 40 ] || return 1; case "$1" in *[!0-9a-f]*) return 1 ;; *) return 0 ;; esac; }
is_repo() {
  case "$1" in */*/*|/*|*/|*[!A-Za-z0-9._/-]*) return 1 ;; */*) return 0 ;; *) return 1 ;; esac
}

derive() {
  [ "$#" -eq 5 ] || die "usage: <records> | review-step.sh derive <login> <repo> <backlog-repo> <N> <limit>"
  login="$1"; repo="$2"; brepo="$3"; n="$4"; limit="$5"
  is_uint "$limit" || die "limit is not a plain number: $limit"
  [ "$limit" -gt 0 ] || die "limit is not a plain number: $limit"
  [ -n "$login" ] || die "empty login"
  is_repo "$repo" || die "malformed repo: $repo"
  if [ "$brepo" != "-" ]; then is_repo "$brepo" || die "malformed backlog-repo: $brepo"; fi
  is_uint "$n" || die "task issue is not a plain number: $n"
  [ "$n" -gt 0 ] || die "task issue is not a plain number: $n"
  # The backlog repo is `repo` itself when it is null or equal: then the bare `#N` names the task.
  if [ "$brepo" = "-" ] || [ "$brepo" = "$repo" ]; then
    bare=1; full="$repo"
  else
    bare=0; full="$brepo"
  fi
  # login, repo and N travel through ENVIRON, not `-v`: `-v` runs escape processing on its
  # value, so a backslash would arrive as something else.
  RS_LOGIN="$login" RS_FULL="$full" RS_BARE="$bare" RS_N="$n" RS_LIMIT="$limit" awk -F '\t' '
    BEGIN {
      login = tolower(ENVIRON["RS_LOGIN"]); full = tolower(ENVIRON["RS_FULL"])
      # An App login (`<stem>[bot]`) also matches the `app/<stem>` spelling of a bot author.
      alt = ""
      if (login ~ /\[bot\]$/) alt = "app/" substr(login, 1, length(login) - 5)
      bare = ENVIRON["RS_BARE"]; n = ENVIRON["RS_N"]
      cnt = 0; bad = ""; total = 0; lim = ENVIRON["RS_LIMIT"] + 0
    }
    # Decode the four escapes @tsv produces, left to right, so `\\n` (an escaped backslash
    # then the letter n) is not mistaken for a newline.
    function decode(s,    out, i, c, d) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\" && i < length(s)) {
          d = substr(s, i + 1, 1)
          if (d == "n" || d == "t" || d == "r") { out = out " "; i++; continue }
          if (d == "\\") { out = out "\\"; i++; continue }
        }
        out = out c
      }
      return out
    }
    # names(text, target): does `target` occur at a position not preceded by a word char or
    # `/`, and not followed by a digit?
    # strict (the owner/repo form): `-` and `.` also count as a preceding name character, since
    # owner and repo names may contain them (`evil-owner/repo#N` is another repo).
    function names(text, target, strict,    tl, pos, p, before, after, bad_before) {
      text = tolower(text); tl = length(target); pos = 1
      while ((p = index(substr(text, pos), target)) > 0) {
        p += pos - 1
        before = (p > 1) ? substr(text, p - 1, 1) : ""
        after = substr(text, p + tl, 1)
        bad_before = (before == "/" || before ~ /[A-Za-z0-9_]/ || (strict && (before == "-" || before == ".")))
        if (!bad_before && after !~ /[0-9]/) return 1
        pos = p + 1
      }
      return 0
    }
    { sub(/\r$/, "") }
    /^$/ { next }
    {
      total++
      if (NF != 7) { bad = "malformed record (fields=" NF "): " $0; exit }
      if ($1 !~ /^[0-9]+$/ || $1 + 0 == 0) { bad = "malformed PR number: " $1; exit }
      if ($2 != "OPEN" && $2 != "CLOSED" && $2 != "MERGED") { bad = "unknown PR state: " $2; exit }
      if ($3 != "true" && $3 != "false") { bad = "unknown isCrossRepository: " $3; exit }
      if ($5 !~ /^[0-9a-f]+$/ || length($5) != 40) { bad = "malformed head oid: " $5; exit }
      if ($2 != "OPEN" || $3 != "false") next
      if (tolower($4) != login && (alt == "" || tolower($4) != alt)) next
      text = decode($6) " " decode($7)
      if (bare == "1" && (names(text, "#" n, 0) || names(text, full "#" n, 1))) hit = 1
      else if (bare != "1" && names(text, full "#" n, 1)) hit = 1
      else hit = 0
      if (!hit) next
      num[cnt] = $1 + 0; oid[cnt] = $5; cnt++
    }
    END {
      if (bad != "") { print "review-step.sh: " bad " -- cannot answer" > "/dev/stderr"; exit 2 }
      if (total >= lim) { print "review-step.sh: " total " records, the --limit: the list may be truncated -- cannot answer" > "/dev/stderr"; exit 2 }
      if (cnt == 0) { print "none"; exit 0 }
      if (cnt == 1) { print "one " num[0] " " oid[0]; exit 0 }
      for (i = 0; i < cnt; i++) for (j = i + 1; j < cnt; j++) if (num[j] < num[i]) {
        t = num[i]; num[i] = num[j]; num[j] = t
      }
      line = "many"
      for (i = 0; i < cnt; i++) line = line " " num[i]
      print line
    }
  '
}

login_mode() {
  [ "$#" -eq 3 ] || die "usage: review-step.sh login user|app <user-login> <dev-app-login>"
  lmode="$1"; ulogin="$2"; alogin="$3"
  case "$lmode" in
    user) who="$ulogin"; app=0 ;;
    app) who="$alogin"; app=1 ;;
    *) die "login mode must be user|app: $lmode" ;;
  esac
  [ -n "$who" ] && [ "$who" != "-" ] || die "no identity for mode $lmode"
  stem="${who%\[bot\]}"
  case "$stem" in ''|-*|*-|*--*|*[!A-Za-z0-9-]*) die "not an account name: $who" ;; esac
  # An App login is the REST `<slug>[bot]` form; a bare name would match a USER of that name.
  if [ "$app" = 1 ] && [ "$stem" = "$who" ]; then die "dev_app login is not a [bot] login: $who"; fi
  if [ "$app" = 0 ] && [ "$stem" != "$who" ]; then die "a user-mode login is not a [bot] login: $who"; fi
  printf '%s\n' "$who"
}

decide() {
  derived=; gate=; gate_state=; state=; sr_number=; sr_head=; next_action=; task_issue=
  backlog_repo=; repo=; head=; branch=; base=; base_head=; last_commit=; tree=; model=; architect=
  fresh=; login=; loop_identity=
  seen=
  for kv in "$@"; do
    case "$kv" in *=*) ;; *) die "not key=value: $kv" ;; esac
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      derived) derived="$v" ;; gate) gate="$v" ;; gate_state) gate_state="$v" ;;
      state) state="$v" ;; sr_number) sr_number="$v" ;; sr_head) sr_head="$v" ;;
      next_action) next_action="$v" ;; task_issue) task_issue="$v" ;;
      backlog_repo) backlog_repo="$v" ;; repo) repo="$v" ;; head) head="$v" ;;
      branch) branch="$v" ;; base) base="$v" ;; base_head) base_head="$v" ;;
      last_commit) last_commit="$v" ;;
      tree) tree="$v" ;; model) model="$v" ;; architect) architect="$v" ;; fresh) fresh="$v" ;;
      login) login="$v" ;; loop_identity) loop_identity="$v" ;; mode) mode="$v" ;;
      *) die "unknown key: $k" ;;
    esac
    case "$seen " in *" $k "*) die "repeated key: $k" ;; esac
    seen="$seen $k"
  done
  for k in derived gate gate_state state sr_number sr_head next_action task_issue \
           backlog_repo repo head branch base base_head last_commit tree model architect fresh \
           login loop_identity mode; do
    case "$seen " in *" $k "*) ;; *) die "missing key: $k" ;; esac
    eval "val=\${$k}"
    [ -n "$val" ] || die "empty value for $k"
  done

  case "$gate" in set|null|unreadable) ;; *) die "gate must be set|null|unreadable: $gate" ;; esac
  case "$gate_state" in success|pending|failure|absent|-) ;; *) die "bad gate_state: $gate_state" ;; esac
  case "$state" in present|absent) ;; *) die "state must be present|absent: $state" ;; esac
  case "$tree" in clean|dirty) ;; *) die "tree must be clean|dirty: $tree" ;; esac
  case "$mode" in user|app) ;; *) die "mode must be user|app: $mode" ;; esac
  case "$fresh" in yes|no) ;; *) die "fresh must be yes|no: $fresh" ;; esac
  is_oid "$head" || die "head is not a 40-hex oid: $head"
  if [ "$base_head" != "-" ]; then is_oid "$base_head" || die "base_head is not a 40-hex oid: $base_head"; fi
  if [ "$last_commit" != "-" ]; then is_oid "$last_commit" || die "last_commit is not a 40-hex oid: $last_commit"; fi
  is_uint "$task_issue" || die "task_issue is not a plain number: $task_issue"

  if [ "$loop_identity" != "-" ]; then
    # Case-folded, then one trailing `[bot]` dropped, on both sides (as plan-anchor.sh's `fold`).
    lc_login="$(printf '%s' "$login" | tr 'A-Z' 'a-z')"; lc_login="${lc_login%\[bot\]}"
    lc_loop="$(printf '%s' "$loop_identity" | tr 'A-Z' 'a-z')"; lc_loop="${lc_loop%\[bot\]}"
    # The stem must be the schema's shape (plan-anchor.sh: anything else is a caller bug).
    case "$lc_loop" in ''|-*|*-|*[!a-z0-9-]*) die "malformed loop_identity: $loop_identity" ;; esac
    [ "${#lc_loop}" -le 39 ] || die "malformed loop_identity: $loop_identity"
    if [ "$lc_login" = "$lc_loop" ]; then echo none; return 0; fi
  fi

  set -- $derived
  kind="${1:-}"
  case "$kind" in
    none)
      [ "$#" -eq 1 ] || die "malformed derived: $derived"
      echo none; return 0 ;;
    many)
      [ "$#" -ge 3 ] || die "malformed derived: $derived"
      shift
      for m in "$@"; do is_uint "$m" || die "malformed derived: $derived"; done
      echo "many $*"; return 0 ;;
    one)
      [ "$#" -eq 3 ] || die "malformed derived: $derived"
      m="$2"; oid="$3"
      is_uint "$m" || die "malformed derived: $derived"
      is_oid "$oid" || die "malformed derived: $derived" ;;
    *) die "malformed derived: $derived" ;;
  esac

  # A gate read from anywhere but the default branch would let the PR under review blank it,
  # or name a check that is always green; the caller reports `unreadable` instead of guessing.
  if [ "$gate" = unreadable ]; then echo unreadable; return 0; fi
  if [ "$gate" = null ]; then echo "merge $m"; return 0; fi
  [ "$gate_state" != "-" ] || die "gate is set but gate_state is -"
  # A green gate is a review of the derived head, but "reviewed" is only honest when no vote
  # names a different head: a push in the window before the post goes green on a commit nobody
  # pinned, which must read as head-moved, not as reviewed.
  if [ "$gate_state" = success ]; then
    if [ "$state" = present ] && [ "$sr_number" = "$m" ] && [ "$sr_head" != "$oid" ]; then
      echo "show $m head-moved"; return 0
    fi
    echo "reviewed $m"; return 0
  fi

  reasons=
  add() { reasons="${reasons:+$reasons,}$1"; }

  if [ "$state" = absent ]; then
    add no-state
  else
    [ "$sr_number" = "$m" ] || add review-pr
    # Only meaningful once the number agrees: a head compared against a different PR proves nothing.
    if [ "$sr_number" = "$m" ] && [ "$sr_head" != "$oid" ]; then add head-moved; fi
    if [ "$backlog_repo" = "-" ] || [ "$backlog_repo" = "$repo" ]; then
      want="review PR #$m — task #$task_issue — "
    else
      want="review PR #$m — task $backlog_repo#$task_issue — "
    fi
    # The token must be the line's very first characters. A bare token with nothing after it
    # is not a next action either, so the trailing ` — ` is part of what is matched.
    case "$next_action" in "$want"*) ;; *) add token ;; esac
    # The base, synced and clean -- never the work branch (`#283`). `base` and `base_head` come
    # from the default branch's copy and a fetch of it; `-` for either never equals a real value.
    if [ "$base" = "-" ] || [ "$base_head" = "-" ] || [ "$branch" != "$base" ] \
       || [ "$head" != "$base_head" ] || [ "$tree" != clean ]; then add checkout; fi
    # The review-shape drift rule: the cursor's two fields agree on the pinned commit.
    [ "$last_commit" != "-" ] && [ "$last_commit" = "$sr_head" ] || add last-commit
    [ "$model" = "$architect" ] || add model
  fi
  [ "$mode" = user ] || add app-mode
  [ "$fresh" = yes ] || add not-fresh

  if [ -n "$reasons" ]; then echo "show $m $reasons"; else echo "auto $m $oid"; fi
}

case "$mode" in
  derive) derive "$@" ;;
  decide) decide "$@" ;;
  login) login_mode "$@" ;;
  *) die "unknown mode: $mode" ;;
esac
