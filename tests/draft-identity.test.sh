#!/bin/sh
# Fixture tests for plugins/way-of-working/bin/draft-identity.sh: may this environment draft a
# spec unattended, as the declared dev App with no stored login behind it (#663, WB-D31).
#
# Each case copies draft-identity.sh into its own fixture bin/ directory beside the real
# gh-identity.sh and runs it by path. A stub `gh`, first on PATH, answers a viewer read
# differently with and without GH_TOKEN, and with and without GH_CONFIG_DIR, in its environment,
# and logs its argv. The test fails on any call that is not exactly the viewer read: the call
# log is the only control on what the script asks `gh` for. A sentinel token never appears on
# stdout or stderr.
# Needs yq (mikefarah v4); skips, loudly, without it.
# Permitted toolset: POSIX sh, plus yq, grep and cat as the cases need.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
bindir="$root_dir/plugins/way-of-working/bin"
script="$bindir/draft-identity.sh"

if ! command -v yq >/dev/null 2>&1; then
  echo "SKIP - yq not on PATH; draft-identity.test.sh needs it" >&2
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0
assert_eq() { # <desc> <want> <got>
  if [ "$2" = "$3" ]; then
    echo "ok - $1"
  else
    echo "FAIL - $1: expected [$2], got [$3]" >&2
    fail=1
  fi
}

SENT="SENTINEL-3e90b7a2"
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/gh" <<'FAKE_GH'
#!/bin/sh
printf '%s\n' "$*" >>"$FX_DIR/gh.log"
case "$*" in
  'api --hostname github.com graphql -f query={ viewer { login databaseId } } --jq [.data.viewer.login, .data.viewer.databaseId] | @tsv') : ;;
  *) echo "$FX_MARK gh failure text"; echo "$FX_MARK gh failure text" >&2; exit 1 ;;
esac
dev() { printf 'dev-app[bot]\t201\n'; }
maint() { printf 'maint1\t101\n'; }
tok="${GH_TOKEN:-}"
cfg="${GH_CONFIG_DIR:-}"
case "$FX_SCEN" in
  wrapper) dev ;;
  stored) if [ -n "$tok" ]; then dev; else maint; fi ;;
  nostored) if [ -n "$tok" ]; then dev; else exit 1; fi ;;
  emptycfg) if [ -n "$tok" ]; then dev; elif [ -n "$cfg" ]; then exit 1; else maint; fi ;;
  cfgstored) if [ -n "$tok" ]; then dev; elif [ -n "$cfg" ]; then maint; else exit 1; fi ;;
  maint) maint ;;
  fail) exit 1 ;;
  garbage) if [ -n "$tok" ]; then dev; else printf 'not a tsv\n'; fi ;;
  *) exit 1 ;;
esac
FAKE_GH
chmod +x "$fakebin/gh"

VIEWER='api --hostname github.com graphql -f query={ viewer { login databaseId } } --jq [.data.viewer.login, .data.viewer.databaseId] | @tsv'
cn=0

writeyml() {
  {
    printf 'repo: acme/app\npr_base: main\n'
    printf 'identities:\n%s\n' "$Y_IDENT"
  } >"$cd_/project.yml"
}
nc() {
  cn=$((cn + 1))
  cd_="$tmp/c$cn"
  mkdir -p "$cd_/bin" "$cd_/cfg"
  cp "$script" "$cd_/bin/draft-identity.sh"
  cp "$bindir/gh-identity.sh" "$cd_/bin/"
  : >"$cd_/gh.log"
  Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
  dev_app: {login: "dev-app[bot]", id: 201}'
  writeyml
  TOKEN="tok-$SENT"
  CFG=
}

run() { # <scenario>
  rc=0
  out="$(cd "$cd_" && { if [ -n "$CFG" ]; then GH_CONFIG_DIR="$CFG"; export GH_CONFIG_DIR; else unset GH_CONFIG_DIR; fi; } && PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_MARK="$SENT" FX_SCEN="$1" GH_TOKEN="$TOKEN" GITHUB_TOKEN="$TOKEN" sh "$cd_/bin/draft-identity.sh" check "$cd_/project.yml" 2>"$cd_/err" </dev/null)" || rc=$?
  err="$(cat "$cd_/err")"
}

# expect <desc> <want-stdout> [want-rc]
expect() {
  want_rc="${3:-0}"
  assert_eq "$1" "$2|$want_rc" "$out|$rc"
  case "$out$err" in
    *"$SENT"*) echo "FAIL - $1: the sentinel reached an output stream" >&2; fail=1 ;;
  esac
  # Every call the stub saw must be exactly the viewer read.
  bad="$(grep -vxF "$VIEWER" "$cd_/gh.log" || true)"
  if [ -n "$bad" ]; then
    echo "FAIL - $1: gh was called with something other than the viewer read" >&2
    fail=1
  fi
}

nc; run wrapper
expect "a dev-App token with a wrapper that re-supplies it" "dev_app"
assert_eq "the wrapper case reads the viewer three times" "3" "$(grep -c . "$cd_/gh.log")"

nc; run stored
expect "a dev-App token with a stored maintainer login behind it" "stored-login"

nc; run nostored
expect "a dev-App token with no stored login (the fallback read fails)" "dev_app"

nc; CFG="$cd_/cfg"; run emptycfg
expect "an empty configured GH_CONFIG_DIR with a maintainer login in the default store" "stored-login"

nc; CFG="$cd_/cfg"; run cfgstored
expect "a maintainer login in the configured store only" "stored-login"

nc; run garbage
expect "a fallback read that succeeds with an unparseable viewer" "stored-login"

nc; TOKEN="maint-$SENT"; run maint
expect "a maintainer token" "not-dev-app"
assert_eq "a maintainer token stops after the first viewer read" "1" "$(grep -c . "$cd_/gh.log")"

nc; Y_IDENT=' null'; writeyml; run wrapper
expect "identities: null" "not-dev-app"
assert_eq "identities: null makes no gh call" "0" "$(grep -c . "$cd_/gh.log")"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}
  dev_app: null'; writeyml; run wrapper
expect "dev_app: null" "not-dev-app"

nc; Y_IDENT='  maintainer:
    - {login: maint1, id: 101}'; writeyml; run wrapper
expect "no dev_app key" "not-dev-app"

nc; run fail
expect "a failed first read" "unreadable"
assert_eq "a failed first read stops there" "1" "$(grep -c . "$cd_/gh.log")"

# --- exit 2, nothing on stdout -----------------------------------------------------------
nc
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_SCEN=wrapper sh "$cd_/bin/draft-identity.sh" check 2>/dev/null)" || rc=$?
assert_eq "exit 2: a missing argument" "|2" "$out|$rc"
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_SCEN=wrapper sh "$cd_/bin/draft-identity.sh" show "$cd_/project.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: an unknown mode" "|2" "$out|$rc"
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_SCEN=wrapper sh "$cd_/bin/draft-identity.sh" check "$cd_/no-such.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a missing project file" "|2" "$out|$rc"
rc=0; out="$(cd "$cd_/bin" && PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_SCEN=wrapper sh draft-identity.sh check ../project.yml 2>/dev/null)" || rc=$?
assert_eq "exit 2: a slash-less \$0" "|2" "$out|$rc"
rm "$cd_/bin/gh-identity.sh"
rc=0; out="$(PATH="$fakebin:$PATH" FX_DIR="$cd_" FX_SCEN=wrapper sh "$cd_/bin/draft-identity.sh" check "$cd_/project.yml" 2>/dev/null)" || rc=$?
assert_eq "exit 2: a missing gh-identity.sh" "|2" "$out|$rc"
assert_eq "exit 2: no gh call was made" "0" "$(grep -c . "$cd_/gh.log")"

[ "$fail" -eq 0 ]
