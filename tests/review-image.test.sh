#!/bin/sh
# Fixture tests for the App-mode review image (#634): scripts/identity/review/ (entrypoint.sh,
# outbox-read, Dockerfile, managed-settings.json) and its build context.
#
#   outbox-read     each subcommand, its refusals and exit codes, on a sed-substituted copy whose outbox
#                   directory is a temp directory
#   entrypoint.sh   a sed-substituted copy (the fixed directories and HOME point at temp directories, the
#                   PATH= line becomes the stub directory followed by this test's own PATH); stub dev-token,
#                   token-check.sh, gh, git and claude record their argv and environment and answer from
#                   per-fixture files; stdin is closed
#   Dockerfile      static checks: the FROM line, the claude pin against scripts/loop/Dockerfile's, the
#                   dev-token rewrite, the marker, the ENV lines against the managed file (less the managed-only
#                   WOW_MANAGED_PROBE, which no Dockerfile or entrypoint line may name), the last USER, and
#                   the COPY sources against install-host-tools.ps1's bin/review/ destinations
#   managed file    parses, and holds exactly the keys the spec names (env: the four variables plus
#                   WOW_MANAGED_PROBE)
#
# Permitted toolset: POSIX sh and its standard utilities, jq and yq (skipped, loudly, if either is absent).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
rdir="$root_dir/scripts/identity/review"

for t in jq yq; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "SKIP - $t not on PATH; review-image fixtures not run" >&2
    exit 0
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
ok() { printf 'ok - %s\n' "$1"; }
bad() { printf 'FAIL - %s\n' "$1" >&2; fail=1; }
check() { # check <label> <command...>
  l=$1; shift
  if "$@"; then ok "$l"; else bad "$l"; fi
}
assert_eq() { # assert_eq <label> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1: expected [$2], got [$3]"; fi
}
sed_esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# substituted_copy <source> <dest> <NAME> <value>...: replace each single-quoted NAME='...' line, and check each took.
substituted_copy() {
  src=$1; dst=$2; shift 2
  cp "$src" "$dst"
  while [ "$#" -ge 2 ]; do
    sed "s|^$1='.*'\$|$1='$(sed_esc "$2")'|" "$dst" >"$dst.new" && mv "$dst.new" "$dst"
    grep -qF "$1='$2'" "$dst" || { bad "could not substitute $1 in $(basename "$dst")"; return 1; }
    shift 2
  done
}

# =========================================================================================
# --- outbox-read ------------------------------------------------------------------------
# =========================================================================================
obx="$tmp/obx" otmp="$tmp/otmp"
mkdir "$obx" "$otmp"
substituted_copy "$rdir/outbox-read" "$tmp/outbox-read" outbox "$obx"

# ordinary: run the copy with a private TMPDIR so a leftover temp file is visible.
orun() { # orun <args...> -> $orc, $oout, $oerr
  orc=0
  TMPDIR="$otmp" sh "$tmp/outbox-read" "$@" >"$tmp/o.out" 2>"$tmp/o.err" </dev/null || orc=$?
  oout=$(cat "$tmp/o.out"); oerr=$(cat "$tmp/o.err")
}
no_leftover() { [ -z "$(ls -A "$otmp")" ]; }
refused() { # refused <label> <subcommand>: exit 1, nothing on stdout, one reason word on stderr
  orun "$2"
  assert_eq "outbox-read: $1: exit 1" 1 "$orc"
  assert_eq "outbox-read: $1: nothing on stdout" "" "$oout"
  case $oerr in ''|*[!a-z-]*) bad "outbox-read: $1: stderr is not one reason word: [$oerr]" ;; *) ok "outbox-read: $1: reason [$oerr]" ;; esac
  check "outbox-read: $1: no temp file left" no_leftover
}
clear_obx() { rm -rf "$obx"; mkdir "$obx"; }

clear_obx
printf 'stopped 12 %s entry-env\n' "$(printf 'a%.0s' $(seq 1 40))" >"$obx/outcome"
printf '# Review\n\tindented h\303\251llo \342\200\256 lone \233 byte\n' >"$obx/review.md"
printf '{"findings": []}\n' >"$obx/findings.json"
printf 'changes-needed\n' >"$obx/verdict"
for pair in outcome:outcome body:review.md findings:findings.json verdict:verdict; do
  sub=${pair%%:*}; file=${pair#*:}
  orun "$sub"
  assert_eq "outbox-read: $sub prints its file: exit 0" 0 "$orc"
  check "outbox-read: $sub prints its file: bytes equal" cmp -s "$tmp/o.out" "$obx/$file"
  check "outbox-read: $sub leaves no temp file" no_leftover
done
ok "outbox-read: the stated residuals pass (U+202E and a lone 0x9b byte are in review.md above)"

clear_obx
for sub in outcome body findings verdict; do
  orun "$sub"
  assert_eq "outbox-read: a missing $sub exits 3" 3 "$orc"
  assert_eq "outbox-read: a missing $sub prints nothing" "" "$oout"
done

clear_obx; mkdir "$obx/outcome" "$obx/review.md"
refused "a directory (outcome)" outcome
refused "a directory (body)" body
clear_obx; printf 'a\000b\n' >"$obx/outcome"; refused "a NUL byte (outcome)" outcome
clear_obx; printf 'a\000b\n' >"$obx/review.md"; refused "a NUL byte (body)" body
clear_obx; { head -c 600 /dev/zero | tr '\000' 'a'; echo; } >"$obx/outcome"; refused "an over-cap outcome" outcome
clear_obx; head -c 65537 /dev/zero | tr '\000' 'a' >"$obx/review.md"; refused "an over-cap body" body
clear_obx; head -c 32769 /dev/zero | tr '\000' 'a' >"$obx/findings.json"; refused "an over-cap findings" findings
clear_obx; head -c 65536 /dev/zero | tr '\000' 'a' >"$obx/review.md"
orun body; assert_eq "outbox-read: a body of exactly the cap passes" 0 "$orc"
clear_obx; printf 'one\ntwo\n' >"$obx/outcome"; refused "a two-line outcome" outcome
clear_obx; printf 'no final newline' >"$obx/outcome"; refused "an outcome with no final newline" outcome
clear_obx; printf 'bad \303\251 byte\n' >"$obx/outcome"; refused "an outcome with a byte above 0x7e" outcome
clear_obx; printf 'bad\ttab\n' >"$obx/outcome"; refused "an outcome with a tab" outcome
clear_obx; printf '' >"$obx/outcome"; refused "an empty outcome" outcome
clear_obx; printf 'pass\n' >"$obx/verdict"
orun verdict; assert_eq "outbox-read: a one-line verdict exits 0" 0 "$orc"
assert_eq "outbox-read: a one-line verdict prints the word" pass "$oout"
clear_obx; printf 'pass\nchanges-needed\n' >"$obx/verdict"; refused "a two-line verdict" verdict
assert_eq "outbox-read: a two-line verdict names its own word" bad-verdict "$oerr"
clear_obx; { head -c 64 /dev/zero | tr '\000' 'a'; echo; } >"$obx/verdict"; refused "an over-cap verdict" verdict
clear_obx; printf 'pass\033\n' >"$obx/verdict"; refused "a verdict with an ESC byte" verdict
assert_eq "outbox-read: a verdict with an ESC byte names bad-verdict" bad-verdict "$oerr"
clear_obx; printf 'pa\000ss\n' >"$obx/verdict"; refused "a verdict with a NUL byte" verdict
clear_obx; printf 'pass' >"$obx/verdict"; refused "a verdict with no final newline" verdict
clear_obx; printf '' >"$obx/verdict"; refused "an empty verdict" verdict
clear_obx; printf 'pass \303\251\n' >"$obx/verdict"; refused "a verdict with a byte above 0x7e" verdict
clear_obx; mkdir "$obx/verdict"; refused "a directory (verdict)" verdict
clear_obx; printf 'a\033[31mred\n' >"$obx/review.md"; refused "a body with an ESC byte" body
clear_obx; printf 'a\rb\n' >"$obx/review.md"; refused "a body with a carriage return" body
clear_obx; printf 'a\302\233b\n' >"$obx/review.md"; refused "a body with the bytes 0xc2 0x9b" body
clear_obx; printf '{"a":"\177"}\n' >"$obx/findings.json"; refused "a findings file with DEL" findings
clear_obx; printf '{"a":"\302\200"}\n' >"$obx/findings.json"; refused "a findings file with 0xc2 0x80" findings

clear_obx
if ln -s "$tmp/target" "$obx/outcome" 2>/dev/null && [ -L "$obx/outcome" ]; then
  printf 'stopped 1 x entry-env\n' >"$tmp/target"
  refused "a symlink (outcome)" outcome
  rm -f "$obx/outcome"
else
  echo "SKIP - a symlink cannot be made here; the outbox-read symlink fixture did not run" >&2
fi

orun; assert_eq "outbox-read: no argument exits 2" 2 "$orc"
orun bogus; assert_eq "outbox-read: an unknown subcommand exits 2" 2 "$orc"
orun outcome body; assert_eq "outbox-read: a second argument exits 2" 2 "$orc"
assert_eq "outbox-read: usage prints nothing on stdout" "" "$oout"

# =========================================================================================
# --- entrypoint.sh ----------------------------------------------------------------------
# =========================================================================================
REC="$tmp/rec" LX="$tmp/libexec" STUB="$tmp/stub" W="$tmp/work" OB="$tmp/review-out" H="$tmp/home" TD="$tmp/tokdir"
mkdir -p "$STUB"
FAKE_TOKEN=ghs_FAKEfakeFAKEfakeFAKEfakeFAKEfake0001
SHA=1111111111111111111111111111111111111111
COMMIT=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
TAGSHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
REPO=glunk-works/target
EP="$tmp/entrypoint.sh"
mkdir -p "$W" "$OB" "$H" "$TD" "$LX"
substituted_copy "$rdir/entrypoint.sh" "$EP" \
  LIBEXEC "$LX" OUTBOX "$OB" WORK "$W" TOKDIR "$TD" HOME "$H" PATH "$STUB:$PATH" || exit 1

stub() { sed "s|@REC@|$REC|g; s|@TOKEN@|$FAKE_TOKEN|g" >"$1"; chmod +x "$1"; }

stub "$STUB/gh" <<'STUB'
#!/bin/sh
REC='@REC@'
{ printf 'gh'; for a in "$@"; do printf ' [%s]' "$a"; done; echo; } >>"$REC/gh.argv"
env | sort >>"$REC/gh.env"
case "$*" in
  'api --hostname github.com --paginate installation/repositories --jq .repositories[].full_name')
    [ ! -e "$REC/fail.gh" ] || exit 1
    cat "$REC/ans.inst" ;;
  'api --hostname github.com graphql -f query={ viewer { login databaseId } } --jq [.data.viewer.login, .data.viewer.databaseId] | @tsv')
    [ ! -e "$REC/fail.gh" ] || exit 1
    cat "$REC/ans.viewer" ;;
  *) echo "stub gh: unexpected arguments" >&2; exit 1 ;;
esac
STUB

stub "$STUB/git" <<'STUB'
#!/bin/sh
REC='@REC@'
{ printf 'git'; for a in "$@"; do printf ' [%s]' "$a"; done; echo; } >>"$REC/git.argv"
env | sort >>"$REC/git.env"
case "${1:-}" in
  clone)
    [ ! -e "$REC/fail.clone" ] || exit 1
    for a in "$@"; do dest=$a; done
    mkdir -p "$dest" && cp -R "$REC/clonesrc/." "$dest/" ;;
  ls-remote)
    pwd >>"$REC/git.lsremote.cwd"
    [ ! -e "$REC/fail.lsremote" ] || exit 1
    cat "$REC/ans.lsremote" ;;
  *) echo "stub git: unexpected arguments" >&2; exit 1 ;;
esac
STUB

stub "$STUB/claude" <<'STUB'
#!/bin/sh
REC='@REC@'
if [ "${1:-}" = -p ]; then
  for a in "$@"; do printf '[%s]\n' "$a"; done >"$REC/claude.run.argv"
  env | sort >"$REC/claude.run.env"
  pwd >"$REC/claude.run.cwd"
  exit "$(cat "$REC/claude.rc" 2>/dev/null || echo 0)"
fi
{ printf 'claude'; for a in "$@"; do printf ' [%s]' "$a"; done; echo; } >>"$REC/claude.plugin.argv"
pwd >>"$REC/claude.plugin.cwd"
env | sort >>"$REC/claude.plugin.env"
case "${1:-} ${2:-}" in
  'plugin install')
    [ ! -e "$REC/fail.install" ] || exit 1
    sh "$REC/on-install.sh" ;;
  'plugin marketplace')
    [ ! -e "$REC/fail.mkt" ] || exit 1 ;;
esac
exit 0
STUB

# on-install.sh: what `claude plugin install` leaves in $HOME; install.env varies it per fixture.
cat >"$tmp/on-install.sh" <<'SCRIPT'
#!/bin/sh
set -e
. "@REC@/install.env"
chome=$(cd "$HOME" && pwd -P)
mkdir -p "$chome/.claude/plugins/cache"
ipath="$chome/.claude/plugins/cache/${IPREL:-claude-workbench/way-of-working/0.1.0}"
[ -z "${IPABS:-}" ] || ipath=$IPABS
real=$ipath
if [ "${LINK:-no}" = yes ]; then real="$chome/realdir"; fi
mkdir -p "$real/bin"
if [ "${MARKER:-yes}" = yes ]; then
  printf '#!/bin/sh\n# a stand-in\nREVIEW_CONTAINER_MARKER=/etc/way-of-working/review-container\nset -eu\n' >"$real/bin/review-sandbox.sh"
else
  printf '#!/bin/sh\n# an older release\nset -eu\n' >"$real/bin/review-sandbox.sh"
fi
case "${WRITER:-yes}" in
  yes) printf '#!/bin/sh\n# a stand-in\nREVIEW_OUTBOX=/review-out\nset -eu\n' >"$real/bin/review-outbox.sh"; chmod 755 "$real/bin/review-outbox.sh" ;;
  wrongline) printf '#!/bin/sh\n# an older release\nREVIEW_OUTBOX=/elsewhere\nset -eu\n' >"$real/bin/review-outbox.sh"; chmod 755 "$real/bin/review-outbox.sh" ;;
  noexec) printf '# no shebang\nREVIEW_OUTBOX=/review-out\n' >"$real/bin/review-outbox.sh"; chmod 644 "$real/bin/review-outbox.sh" ;;
  link) ln -s review-sandbox.sh "$real/bin/review-outbox.sh" ;;
  missing) ;;
esac
if [ "${LINK:-no}" = yes ]; then mkdir -p "$(dirname "$ipath")"; ln -s "$real" "$ipath"; fi
entry=$(printf '{"scope": "%s", "installPath": "%s", "gitCommitSha": "%s"}' "${SCOPE:-user}" "$ipath" "${SHA:-@COMMIT@}")
if [ "${ENTRIES:-1}" = 2 ]; then arr="[$entry, $entry]"; else arr="[$entry]"; fi
printf '{"version": 2, "plugins": {"way-of-working@claude-workbench": %s}}
' "$arr" >"$chome/.claude/plugins/installed_plugins.json"
SCRIPT

# fresh: a clean world and the default (succeeding) answers.
fresh() {
  rm -rf "$REC" "$LX" "$W" "$OB" "$H" "$TD"
  mkdir -p "$REC" "$LX" "$W" "$OB" "$H" "$TD" "$REC/clonesrc/.ai" "$REC/clonesrc/.claude"
  stub "$LX/dev-token" <<'STUB'
#!/bin/sh
REC='@REC@'
echo called >>"$REC/devtoken.calls"
[ ! -e "$REC/fail.devtoken" ] || { echo "dev-token: no live token" >&2; exit 2; }
printf '%s\n' '@TOKEN@'
STUB
  stub "$LX/token-check.sh" <<'STUB'
#!/bin/sh
REC='@REC@'
{ printf 'token-check.sh'; for a in "$@"; do printf ' [%s]' "$a"; done; echo; } >>"$REC/tc.argv"
printf '%s\n' "$5" >"$REC/tc.inst"
[ ! -e "$REC/fail.tc" ] || exit 2
exit 0
STUB
  sed "s|@REC@|$REC|g; s|@COMMIT@|$COMMIT|g" "$tmp/on-install.sh" >"$REC/on-install.sh"
  : >"$REC/install.env"
  printf '%s\n' "$REPO" >"$REC/ans.inst"
  printf 'example-review[bot]\t2002\n' >"$REC/ans.viewer"
  printf '%s\trefs/tags/v1.2.3\n%s\trefs/tags/v1.2.3^{}\n' "$TAGSHA" "$COMMIT" >"$REC/ans.lsremote"
  printf 'identities:\n  reviewer_app: { login: "example-review[bot]", id: 2002 }\n' >"$REC/clonesrc/.ai/project.yml"
  cat >"$REC/clonesrc/.claude/settings.json" <<'JSON'
{"enabledPlugins": {"way-of-working@claude-workbench": true},
 "extraKnownMarketplaces": {"claude-workbench": {"source": {"source": "github", "repo": "glunk-works/claude-workbench", "ref": "v1.2.3"}}}}
JSON
}

case_env() {
  unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_AUTH_TOKEN HTTPS_PROXY HTTP_PROXY NO_PROXY no_proxy \
    GIT_CONFIG_COUNT CLAUDE_CONFIG_DIR GH_TOKEN GH_HOST CLAUDE_CODE_PLUGIN_CACHE_DIR
  WOW_REVIEW_PR=12; WOW_REVIEW_SHA=$SHA; WOW_REVIEW_REPO=$REPO; WOW_REVIEW_MODEL=claude-test-5
  ANTHROPIC_BASE_URL=http://llm-sidecar:8080; ANTHROPIC_API_KEY=placeholder-key
  export WOW_REVIEW_PR WOW_REVIEW_SHA WOW_REVIEW_REPO WOW_REVIEW_MODEL ANTHROPIC_BASE_URL ANTHROPIC_API_KEY
}

leaks=0
# ep <modifier...>: a fresh world, the default environment, then the modifier (run in the same subshell
# as the entrypoint, so it may export, unset and prepare files); leaves $rc and $REC/{stdout,stderr}.
ep() {
  fresh
  ( case_env; "$@"; r=0; sh "$EP" </dev/null >"$REC/stdout" 2>"$REC/stderr" || r=$?; echo "$r" >"$REC/rc" )
  rc=$(cat "$REC/rc")
  if grep -rqF "$FAKE_TOKEN" "$REC" "$OB" 2>/dev/null; then leaks=$((leaks + 1)); bad "token secrecy: the token text leaked in a fixture ($*)"; fi
}
nothing() { :; }
no_claude_run() { [ ! -e "$REC/claude.run.argv" ]; }
no_calls() { [ -z "$(ls "$REC" | grep '\.argv$' || true)" ] && [ ! -e "$REC/devtoken.calls" ]; }
outcome_is() { [ -f "$OB/outcome" ] && [ "$(cat "$OB/outcome")" = "$1" ]; }
no_outcome() { [ ! -e "$OB/outcome" ]; }
tmpd_gone() { [ -f "$REC/tc.inst" ] && [ ! -e "$(dirname "$(cat "$REC/tc.inst")")" ]; }
set_var() { export "$1=$2"; }
not() { ! "$@"; }

stop_case() { # stop_case <label> <reason> <modifier...>: exit 1, the label line, no claude run
  l=$1; reason=$2; shift 2
  ep "$@"
  assert_eq "$l: exit 1" 1 "$rc"
  check "$l: writes entry-$reason" outcome_is "stopped 12 $SHA entry-$reason"
  check "$l: never runs claude" no_claude_run
}

# --- exit 2: writes nothing, calls nothing ---------------------------------------------------
for v in 0 012 1a ''; do
  ep set_var WOW_REVIEW_PR "$v"
  assert_eq "invalid PR [$v]: exit 2" 2 "$rc"; check "invalid PR [$v]: no outcome" no_outcome; check "invalid PR [$v]: nothing called" no_calls
done
for v in AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 111111111111111111111111111111111111111 11111111111111111111111111111111111111111 zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz ''; do
  ep set_var WOW_REVIEW_SHA "$v"
  assert_eq "invalid SHA [$v]: exit 2" 2 "$rc"; check "invalid SHA [$v]: no outcome" no_outcome; check "invalid SHA [$v]: nothing called" no_calls
done
ep rm -rf "$OB"
assert_eq "an absent outbox: exit 2" 2 "$rc"; check "an absent outbox: nothing called" no_calls
ep touch "$OB/.hidden"
assert_eq "an outbox holding a dotfile: exit 2" 2 "$rc"; check "an outbox holding a dotfile: nothing called" no_calls
check "an outbox holding a dotfile: nothing written" test "$(ls -A "$OB")" = ".hidden"
ep touch "$OB/anything"
assert_eq "an outbox holding a file: exit 2" 2 "$rc"; check "an outbox holding a file: nothing called" no_calls
ep sh -c 'rm -rf "$0" && : >"$0"' "$OB"
assert_eq "an outbox that is a file: exit 2" 2 "$rc"

# --- step 1: environment ----------------------------------------------------------------------
for v in evil a/b/c -x/y ../y a/.. 'a b/c' /y x/ ; do
  stop_case "bad repo [$v]" env set_var WOW_REVIEW_REPO "$v"
done
for v in 'a b' 'x;y' ''; do stop_case "bad model [$v]" env set_var WOW_REVIEW_MODEL "$v"; done
for v in https://h:1 http://h http://h:x 'http://h/:1' http://:80 'http://h:80/' ''; do
  stop_case "bad base URL [$v]" env set_var ANTHROPIC_BASE_URL "$v"
done
stop_case "a real-looking API key" env set_var ANTHROPIC_API_KEY sk-ant-SECRETVALUE
check "...the refusal does not echo the value" not grep -q SECRETVALUE "$REC/stderr"
check "...the refusal names the variable" grep -q ANTHROPIC_API_KEY "$REC/stderr"
stop_case "a real-looking API key after leading spaces" env set_var ANTHROPIC_API_KEY '  sk-ant-SECRETVALUE'
check "...the refusal does not echo the value" not grep -q SECRETVALUE "$REC/stderr"
oauth_real() { unset ANTHROPIC_API_KEY; export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-SECRETVALUE; }
stop_case "a real-looking OAuth token" env oauth_real
check "...the refusal does not echo the value" not grep -q SECRETVALUE "$REC/stderr"
both() { export CLAUDE_CODE_OAUTH_TOKEN=placeholder-oauth; }
stop_case "both placeholder variables" env both
neither() { unset ANTHROPIC_API_KEY; }
stop_case "no placeholder variable" env neither
stop_case "ANTHROPIC_AUTH_TOKEN set" env set_var ANTHROPIC_AUTH_TOKEN anything
proxy_ok() { export HTTPS_PROXY=http://egress:3128 HTTP_PROXY=http://egress:3128 NO_PROXY=llm-sidecar,localhost no_proxy=llm-sidecar,localhost; }
proxy_no_upper() { proxy_ok; unset NO_PROXY; }
proxy_no_lower() { proxy_ok; unset no_proxy; }
proxy_not_listing() { proxy_ok; export NO_PROXY=localhost; }
proxy_star() { proxy_ok; export no_proxy='llm-sidecar,*'; }
proxy_empty_entry() { proxy_ok; export NO_PROXY='llm-sidecar,,localhost'; }
proxy_trailing() { proxy_ok; export no_proxy='llm-sidecar,'; }
proxy_substring() { proxy_ok; export NO_PROXY='sidecar'; }
proxy_bad_url() { proxy_ok; export HTTPS_PROXY=egress:3128; }
only_no_proxy() { export NO_PROXY=localhost; }
for m in proxy_no_upper proxy_no_lower proxy_not_listing proxy_star proxy_empty_entry proxy_trailing proxy_substring proxy_bad_url only_no_proxy; do
  stop_case "proxy variables: $m" env "$m"
done
for m in .claude .claude.json x; do
  stop_case "a non-empty HOME ($m)" env touch "$H/$m"
done

# --- step 2: token, step 3: clone, step 4: identity --------------------------------------------
stop_case "a failing dev-token" token touch "$REC/fail.devtoken"
check "...and no clone was attempted" test ! -e "$REC/git.argv"
stop_case "a failing git clone" clone touch "$REC/fail.clone"
stop_case "a failing token-check.sh" identity touch "$REC/fail.tc"
check "...and the temp directory is gone" tmpd_gone
stop_case "a failing installation read" identity touch "$REC/fail.gh"
no_yq_map() { printf 'identities: null\n' >"$REC/clonesrc/.ai/project.yml"; }
stop_case "a null reviewer_app" identity no_yq_map
check "...and gh was never asked" test ! -e "$REC/gh.argv"
not_map() { printf 'identities:\n  reviewer_app: null\n' >"$REC/clonesrc/.ai/project.yml"; }
stop_case "a null reviewer_app under identities" identity not_map

# --- step 5: plugin ---------------------------------------------------------------------------
settings_edit() { jq "$1" "$REC/clonesrc/.claude/settings.json" >"$REC/s.tmp" && mv "$REC/s.tmp" "$REC/clonesrc/.claude/settings.json"; }
no_plugin_calls() { [ ! -e "$REC/git.lsremote.cwd" ] && [ ! -e "$REC/claude.plugin.argv" ]; }
M='.extraKnownMarketplaces["claude-workbench"].source'
for f in \
  '.enabledPlugins["way-of-working@claude-workbench"] = false' \
  'del(.enabledPlugins)' \
  "$M = {\"source\": \"directory\", \"path\": \"/tmp/x\"}" \
  "$M.repo = \"evil/claude-workbench\"" \
  "$M.path = \"/x\"" \
  "del($M.ref)" \
  "$M.ref = \"main\"" \
  "$M.ref = \"v1.2\"" \
  "$M.ref = \"v1.2.3\\n\"" \
  "$M.ref = \"v1.2.3-rc1\"" \
  'del(.extraKnownMarketplaces)' ; do
  stop_case "a wrong pin [$f]" plugin settings_edit "$f"
  check "...with no ls-remote or claude plugin call" no_plugin_calls
done
stop_case "a missing settings file" plugin rm -f "$REC/clonesrc/.claude/settings.json"
heads_line() { printf '%s\trefs/heads/v1.2.3\n' "$TAGSHA" >>"$REC/ans.lsremote"; }
stop_case "a branch named like the tag" plugin heads_line
tail_only() { printf '%s\trefs/tags/x/refs/tags/v1.2.3\n' "$TAGSHA" >"$REC/ans.lsremote"; }
stop_case "only a tail-matching tag line" plugin tail_only
check "...and claude plugin was not run" test ! -e "$REC/claude.plugin.argv"
two_tags() { printf '%s\trefs/tags/v1.2.3\n' "$TAGSHA" >>"$REC/ans.lsremote"; }
stop_case "a tag listed twice" plugin two_tags
stop_case "a failing ls-remote" plugin touch "$REC/fail.lsremote"
stop_case "a failing marketplace add" plugin touch "$REC/fail.mkt"
stop_case "a failing install" plugin touch "$REC/fail.install"
inst() { for kv in "$@"; do printf '%s\n' "$kv"; done >"$REC/install.env"; }
stop_case "an installed sha that differs" plugin inst "SHA=$TAGSHA"
stop_case "two installed entries" plugin inst ENTRIES=2
stop_case "a scope other than user" plugin inst SCOPE=project
stop_case "an installPath outside the cache" plugin inst "IPABS=$tmp/outside"
check "...(the cache floor check, not a missing directory)" grep -q 'outside the plugin cache' "$REC/stderr"
stop_case "an installed review-sandbox.sh without the marker line" plugin inst MARKER=no
check "...names the floor" grep -q 'predates the review-container marker' "$REC/stderr"
stop_case "an installed plugin with no review-outbox.sh" plugin inst WRITER=missing
check "...names the writer" grep -q 'has no review-outbox.sh' "$REC/stderr"
stop_case "an installed review-outbox.sh that is not executable" plugin inst WRITER=noexec
check "...names the mount" grep -q 'cannot be executed' "$REC/stderr"
stop_case "an installed review-outbox.sh without the outbox line" plugin inst WRITER=wrongline
check "...names the floor" grep -q 'predates the outbox writer' "$REC/stderr"
if ln -s "$tmp/linktarget" "$tmp/linkprobe" 2>/dev/null && [ -L "$tmp/linkprobe" ]; then
  stop_case "an installPath through a link" plugin inst LINK=yes
  check "...for the link" grep -q 'runs through a link' "$REC/stderr"
  stop_case "a linked review-outbox.sh" plugin inst WRITER=link
  check "...is not accepted as the writer" grep -q 'has no review-outbox.sh' "$REC/stderr"
else
  echo "SKIP - a symlink cannot be made here; the installPath link fixture did not run" >&2
fi

# --- success, and what it shows ----------------------------------------------------------------
cleaned() { export GIT_CONFIG_COUNT=1 CLAUDE_CONFIG_DIR=/leak GH_TOKEN=leak CLAUDE_CODE_PLUGIN_CACHE_DIR=/leak WOW_MANAGED_PROBE=leak; }
ep cleaned
assert_eq "success: claude's status by exec" 0 "$rc"
check "success: no outcome written" no_outcome
check "success: the temp directory is gone" tmpd_gone
for n in GIT_CONFIG_COUNT CLAUDE_CONFIG_DIR GH_TOKEN CLAUDE_CODE_PLUGIN_CACHE_DIR WOW_MANAGED_PROBE; do
  if cat "$REC"/*.env 2>/dev/null | grep -q "^$n="; then bad "cleaned environment: $n reached a child"; else ok "cleaned environment: $n reached no child"; fi
done
for line in DISABLE_AUTOUPDATER=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  GIT_TERMINAL_PROMPT=0 SHELL=/bin/bash "HOME=$H" ANTHROPIC_API_KEY=placeholder-key ANTHROPIC_BASE_URL=http://llm-sidecar:8080 \
  "WOW_REVIEW_REPO=$REPO" WOW_REVIEW_PR=12 "WOW_REVIEW_SHA=$SHA" WOW_REVIEW_MODEL=claude-test-5; do
  check "claude's environment holds $line" grep -qxF "$line" "$REC/claude.run.env"
done
check "claude's environment holds no proxy variable when none was set" test -z "$(grep -i '_proxy=' "$REC/claude.run.env" || true)"
want="[-p]
[/way-of-working:architect-review 12 --pin $SHA]
[--model]
[claude-test-5]
[--setting-sources]
[user]
[--permission-mode]
[bypassPermissions]
[--output-format]
[stream-json]
[--verbose]"
assert_eq "claude's argv is exactly the specified list" "$want" "$(cat "$REC/claude.run.argv")"
assert_eq "claude runs in the clone" "$W" "$(cat "$REC/claude.run.cwd")"
assert_eq "claude plugin calls run from HOME" "$H" "$(sort -u "$REC/claude.plugin.cwd")"
assert_eq "git ls-remote runs from HOME, never the clone" "$H" "$(cat "$REC/git.lsremote.cwd")"
want_mkt="claude [plugin] [marketplace] [add] [glunk-works/claude-workbench@v1.2.3] [--scope] [user]"
check "the marketplace add names the fixed repository at the ref, user scope" grep -qxF "$want_mkt" "$REC/claude.plugin.argv"
check "the plugin install is user scope, with no -y" grep -qxF "claude [plugin] [install] [way-of-working@claude-workbench] [--scope] [user]" "$REC/claude.plugin.argv"
check "the clone takes the default branch of the review repo only" grep -qxF "git [clone] [--quiet] [--single-branch] [https://github.com/$REPO] [$W]" "$REC/git.argv"
check "ls-remote names the fixed marketplace repository and the three refs" grep -qxF "git [ls-remote] [https://github.com/glunk-works/claude-workbench] [refs/heads/v1.2.3] [refs/tags/v1.2.3] [refs/tags/v1.2.3^{}]" "$REC/git.argv"
check "token-check.sh gets the fixed verify argv" grep -q "^token-check.sh \[verify\] \[reviewer_app\] \[$REPO\] \[$TD/session-token\] \[.*\] \[$W/.ai/project.yml\] \[example-review\[bot\]\] \[2002\]\$" "$REC/tc.argv"
check "no claude call carries -y or --yes" test -z "$(grep -e ' \[-y\]' -e '--yes' "$REC/claude.plugin.argv" || true)"

claude_rc7() { echo 7 >"$REC/claude.rc"; }
ep claude_rc7
assert_eq "claude's own exit status is the entrypoint's" 7 "$rc"

ep proxy_ok
assert_eq "proxy variables: a valid set runs" 0 "$rc"
for line in HTTPS_PROXY=http://egress:3128 HTTP_PROXY=http://egress:3128 NO_PROXY=llm-sidecar,localhost no_proxy=llm-sidecar,localhost; do
  check "proxy variables: claude's environment holds $line" grep -qxF "$line" "$REC/claude.run.env"
done
oauth_ok() { unset ANTHROPIC_API_KEY; export CLAUDE_CODE_OAUTH_TOKEN=placeholder-oauth; }
ep oauth_ok
assert_eq "an OAuth placeholder runs" 0 "$rc"
check "...and reaches claude as the one credential" grep -qxF CLAUDE_CODE_OAUTH_TOKEN=placeholder-oauth "$REC/claude.run.env"
check "...and no API key variable" test -z "$(grep '^ANTHROPIC_API_KEY=' "$REC/claude.run.env" || true)"

# Ignored settings: env, hooks and a second plugin in the project file are never read.
extra_settings() {
  settings_edit '. + {env: {EVIL: "1"}, hooks: {SessionStart: [{hooks: [{type: "command", command: "touch /tmp/evil"}]}]}} | .enabledPlugins["other@thing"] = true | .extraKnownMarketplaces.thing = {source: {source: "directory", path: "/x"}}'
}
ep extra_settings
assert_eq "other settings keys are ignored: success" 0 "$rc"
check "...and EVIL reached no child" test -z "$(cat "$REC"/*.env | grep '^EVIL=' || true)"

# Identity, end to end: the real token-check.sh and gh-identity.sh, a token file in mint.sh's format, and
# a gh stub that answers only to the two exact --jq expressions.
if ! date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  echo "SKIP - GNU date -d not available; the end-to-end identity fixture did not run" >&2
else
  e2e() {
    cp "$root_dir/plugins/way-of-working/bin/token-check.sh" "$root_dir/plugins/way-of-working/bin/gh-identity.sh" "$LX/"
    printf '%s\n%s\n' "$FAKE_TOKEN" "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" >"$TD/session-token"
  }
  ep e2e
  assert_eq "identity end to end: the real checks pass" 0 "$rc"
  check "identity end to end: claude ran" test -e "$REC/claude.run.argv"
  wrong_actor() { e2e; printf 'someone-else[bot]\t9999\n' >"$REC/ans.viewer"; }
  stop_case "identity end to end: a different actor" identity wrong_actor
  wrong_repo() { e2e; printf 'glunk-works/other\n' >"$REC/ans.inst"; }
  stop_case "identity end to end: a repository the token cannot reach" identity wrong_repo
  user_token() { e2e; printf 'ghp_%s\n%s\n' "$(printf 'a%.0s' $(seq 1 36))" "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" >"$TD/session-token"; }
  stop_case "identity end to end: a user token" identity user_token
fi

assert_eq "token secrecy: the fake token appeared in no recorded argv, environment, outbox or stderr" 0 "$leaks"

# =========================================================================================
# --- Dockerfile and build context, static ------------------------------------------------
# =========================================================================================
df="$rdir/Dockerfile"
first_instr=$(grep -n '^[A-Za-z]' "$df" | head -1)
case $first_instr in *:FROM\ *) ok "Dockerfile: FROM is the first instruction (no ARG or directive before it)" ;; *) bad "Dockerfile: the first instruction is [$first_instr]" ;; esac
from=$(grep '^FROM ' "$df")
case $from in *'$'*|*' AS '*|*--platform*) bad "Dockerfile: the FROM line is not literal: $from" ;; *) ok "Dockerfile: the FROM line is literal" ;; esac
printf '%s\n' "$from" | grep -Eq '^FROM [a-z0-9./-]+:[A-Za-z0-9._-]+@sha256:[0-9a-f]{64}$' && ok "Dockerfile: the FROM line is tag-and-digest pinned" || bad "Dockerfile: FROM is not tag-and-digest pinned: $from"
check "Dockerfile: exactly one FROM" test "$(grep -c '^FROM ' "$df")" -eq 1
check "Dockerfile: no # syntax= line" test -z "$(grep -i '^# *syntax=' "$df" || true)"
before_from=$(sed -n '1,/^FROM /p' "$df" | grep -c '^ARG ' || true)
assert_eq "Dockerfile: no ARG before FROM" 0 "$before_from"
arg() { sed -n "s/^ARG $2=//p" "$1"; }
for a in CLAUDE_VERSION CLAUDE_SHA256; do
  v=$(arg "$df" $a); w=$(arg "$root_dir/scripts/loop/Dockerfile" $a)
  if [ -n "$v" ] && [ "$v" = "$w" ]; then ok "Dockerfile: $a equals scripts/loop/Dockerfile's"; else bad "Dockerfile: $a [$v] differs from the loop's [$w]"; fi
done
check "Dockerfile: the dev-token dir rewrite is present" grep -qF "s|^dir=/run/glunk-identity/dev\$|dir=/run/glunk-identity/review|" "$df"
check "Dockerfile: the dev-token file rewrite is present" grep -qF "s|^file=\$dir/dev-token\$|file=\$dir/session-token|" "$df"
check "Dockerfile: the grep check for the dir rewrite is present" grep -qF "grep -q '^dir=/run/glunk-identity/review\$' /usr/local/libexec/dev-token" "$df"
check "Dockerfile: the grep check for the file rewrite is present" grep -qF "grep -q '^file=\$dir/session-token\$' /usr/local/libexec/dev-token" "$df"
# The rewrite really matches the committed dev-token's two lines.
sed -e 's|^dir=/run/glunk-identity/dev$|dir=/run/glunk-identity/review|' -e 's|^file=$dir/dev-token$|file=$dir/session-token|' \
  "$root_dir/.devcontainer/dev-token" >"$tmp/dev-token.rewritten"
check "Dockerfile: the rewrite takes on the committed dev-token (dir)" grep -q '^dir=/run/glunk-identity/review$' "$tmp/dev-token.rewritten"
check "Dockerfile: the rewrite takes on the committed dev-token (file)" grep -q '^file=$dir/session-token$' "$tmp/dev-token.rewritten"
check "Dockerfile: the rewrite changes exactly those two lines" test "$(diff "$root_dir/.devcontainer/dev-token" "$tmp/dev-token.rewritten" | grep -c '^>')" -eq 2
check "Dockerfile: the marker is created, root-owned, 0444" grep -q 'chmod 0444 /etc/way-of-working/review-container' "$df"
check "Dockerfile: the managed settings are copied root-owned, 0444" grep -qF 'COPY --chown=root:root --chmod=0444 managed-settings.json /etc/claude-code/managed-settings.json' "$df"
check "Dockerfile: the build requires allowManagedHooksOnly" grep -qF '.allowManagedHooksOnly == true' "$df"
check "Dockerfile: no /review-out is created" test -z "$(grep -v '^#' "$df" | grep -e 'mkdir.*review-out' -e 'WORKDIR /review-out' || true)"
env_names=$(awk '/^ENV /{e=1} e{print} e && !/\\$/{e=0}' "$df" | tr -s ' \\' '\n\n' | sed -n 's/^\([A-Z_][A-Z0-9_]*\)=.*/\1/p' | sort | tr '\n' ' ')
json_names=$(jq -r '.env | keys[] | select(. != "WOW_MANAGED_PROBE")' "$rdir/managed-settings.json" | tr -d '\r' | sort | tr '\n' ' ')
assert_eq "Dockerfile: the ENV variable names equal the managed file's env keys less WOW_MANAGED_PROBE" "$json_names" "$env_names"
check "WOW_MANAGED_PROBE is named nowhere in the Dockerfile or the entrypoint" test -z "$(grep -l WOW_MANAGED_PROBE "$df" "$rdir/entrypoint.sh" || true)"
assert_eq "Dockerfile: USER 1000:1000 is the last USER" "USER 1000:1000" "$(grep '^USER ' "$df" | tail -1)"
check "Dockerfile: the entrypoint is the libexec copy" grep -qxF 'ENTRYPOINT ["/usr/local/libexec/entrypoint.sh"]' "$df"
copy_sources=$(grep '^COPY ' "$df" | sed -e 's/^COPY //' -e 's/--[a-z]*=[^ ]* //g' | awk '{for (i = 1; i < NF; i++) print $i}' | sort)
ctx=$(sed -n "s/^  ,@('[^']*', 'review\\/\\([^']*\\)')\$/\\1/p" "$root_dir/scripts/identity/install-host-tools.ps1" | sort)
copy_plus_df=$( { printf '%s\n' "$copy_sources"; echo Dockerfile; } | sort)
assert_eq "build context: the COPY sources plus Dockerfile are exactly install-host-tools.ps1's bin/review/ destinations" "$ctx" "$copy_plus_df"
check "build context: ten files" test "$(printf '%s\n' "$ctx" | wc -l | tr -d ' ')" -eq 10

# =========================================================================================
# --- managed-settings.json ---------------------------------------------------------------
# =========================================================================================
ms="$rdir/managed-settings.json"
check "managed settings: parse" jq -e . "$ms" >/dev/null
check "managed settings: the only keys are allowManagedHooksOnly, env and strictPluginOnlyCustomization" jq -e 'keys == ["allowManagedHooksOnly", "env", "strictPluginOnlyCustomization"]' "$ms" >/dev/null
check "managed settings: strictPluginOnlyCustomization is true" jq -e '.strictPluginOnlyCustomization == true' "$ms" >/dev/null
check "managed settings: allowManagedHooksOnly is true" jq -e '.allowManagedHooksOnly == true' "$ms" >/dev/null
check "managed settings: env holds exactly five entries, the four variables each \"1\" and WOW_MANAGED_PROBE managed-only" jq -e \
  '.env == {DISABLE_AUTOUPDATER: "1", DISABLE_TELEMETRY: "1", DISABLE_ERROR_REPORTING: "1", CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1", WOW_MANAGED_PROBE: "managed-only"}' "$ms" >/dev/null

[ "$fail" -eq 0 ] || exit 1
echo "all review-image fixtures passed"
