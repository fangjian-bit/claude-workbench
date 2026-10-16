#!/bin/sh
# The review container's entrypoint (#623 child b, #634): run
# `/way-of-working:architect-review <N> --pin <sha>` unattended, after checking its
# environment, the session token, that the token is the declared reviewer App, and the
# plugin pin. The host launcher, `wow-review` (#635), starts this image.
#
# Inputs (from the launcher, validated in step 1): WOW_REVIEW_PR, WOW_REVIEW_SHA,
# WOW_REVIEW_REPO, WOW_REVIEW_MODEL, ANTHROPIC_BASE_URL, exactly one placeholder credential
# (ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN) and, optionally, the four proxy variables.
# The real Claude credential never enters this container: ANTHROPIC_BASE_URL points at the
# inject.py sidecar, which holds it. This script refuses a real-looking one (`sk-ant-`); that
# is an accident guard, not a boundary (#635's preflight is the check that counts).
#
# Mounts #635 must provide: a writable, empty /work (the clone target), a writable, empty
# /review-out, a writable /tmp, and a writable, empty /home/app.
#
# Writes only: /review-out/outcome, /work (the clone), $HOME (Claude's config and the plugin
# install) and one `mktemp -d` under /tmp. An explicit rm -rf removes that directory just
# before the exec, and a trap removes it on every failure path (an EXIT trap does not run
# across exec).
#
# Every fixed value is a single-quoted line below and is never read from the environment;
# tests/review-image.test.sh runs a sed-substituted copy. After step 1 every command runs
# under `env -i` with an allowlist (cenv), so nothing else reaches git, gh or claude: no
# GIT_CONFIG_*, GH_*, CLAUDE_CONFIG_DIR, CLAUDE_CODE_PLUGIN_CACHE_DIR or LD_PRELOAD.
#
# Exit codes:
#   2  writing nothing: WOW_REVIEW_PR (digits, no leading zero) or WOW_REVIEW_SHA (40 lowercase
#      hex) is invalid, or /review-out is absent, cannot be listed, or already holds any entry
#      (dotfiles included), since nothing can name the review or the outbox is not this run's.
#   1  any later failure, after trying to write `stopped <N> <sha> <reason>` as the single line
#      of /review-out/outcome (a failed write still exits 1). <reason> is entry-env,
#      entry-token, entry-clone, entry-identity or entry-plugin. That line is a label, not
#      evidence: a session can write /review-out/outcome too, so the launcher must not treat an
#      entry-* reason as proof that this script stopped.
#   otherwise claude's own status, by exec.
#
# Timeouts: gh calls 60 s, git clone and git ls-remote 120 s, each `claude plugin` call 300 s.
# A timeout is that step's failure.
#
# Identity (step 4) is token-check.sh's verify chain, with one difference.
# token-check.sh asks its caller to make both gh calls with the same token value it acts with.
# Here the gh shim reads the token file on every call, so a refresh between the calls can swap
# the token. That is accepted because only the host's minter writes the file, always for the
# same App: the identity is proven once, and later re-mints are trusted to the host.
# scripts/identity/review checks `identities.reviewer_app` is a map with its own yq read
# (reference/project-schema.md).
#
# What the plugin pin (step 5) rests on. The pin and the floor bind the code that runs only
# while the marketplace repository's `v*` tags cannot be moved. Today two tag rulesets hold
# that: `protected-release-tags` (update, non-fast-forward and deletion, no bypass actors) and
# `release-tag-creation` (creation, bypassed only by the release workflow's App). Without
# them, any holder of Contents write on that repository, the dev App included, could re-point
# a tag, and every review pinned to it would run that code. A related residual: anyone with
# Contents write can stop every review pinned to a tag by pushing a branch of the same name,
# because step 5 refuses it. That fails closed.
#
# Residual of `--setting-sources user` (step 6): the user settings file lives in the session's
# writable home and is re-read live, so a session that writes its own settings can set `env` or
# a helper. That gives it nothing beyond what bypassPermissions already does. The flag keeps
# the PR's settings files from being applied; it does not constrain the session itself.
set -u
set -f

LIBEXEC='/usr/local/libexec'
OUTBOX='/review-out'
WORK='/work'
TOKDIR='/run/glunk-identity/review'
HOME='/home/app'
PATH='/usr/local/bin:/usr/bin:/bin'
SHELL='/bin/bash'
MKT_REPO='glunk-works/claude-workbench'
MKT_NAME='claude-workbench'
export PATH

PR=${WOW_REVIEW_PR:-}
SHA=${WOW_REVIEW_SHA:-}
TMPD=

# --- exit 2: nothing can be written ----------------------------------------------------------
case $PR in ''|0*|*[!0-9]*) echo "entrypoint: WOW_REVIEW_PR is invalid" >&2; exit 2 ;; esac
case $SHA in *[!0-9a-f]*) echo "entrypoint: WOW_REVIEW_SHA is invalid" >&2; exit 2 ;; esac
[ "${#SHA}" -eq 40 ] || { echo "entrypoint: WOW_REVIEW_SHA is invalid" >&2; exit 2; }

# has_entry <dir>: 0 when the directory holds anything, dotfiles included.
has_entry() {
  set +f
  for e in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if [ -e "$e" ] || [ -L "$e" ]; then set -f; return 0; fi
  done
  set -f
  return 1
}

[ -d "$OUTBOX" ] && [ -r "$OUTBOX" ] && [ -x "$OUTBOX" ] || { echo "entrypoint: $OUTBOX is absent or unreadable" >&2; exit 2; }
if has_entry "$OUTBOX"; then echo "entrypoint: $OUTBOX is not empty" >&2; exit 2; fi

# --- failure paths -----------------------------------------------------------------------------
cleanup() { if [ -n "$TMPD" ]; then rm -rf "$TMPD"; fi; TMPD=; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

stop() { # stop <reason> [<message>]
  [ -z "${2:-}" ] || printf 'entrypoint: %s\n' "$2" >&2
  printf 'entrypoint: stopped (%s)\n' "$1" >&2
  printf 'stopped %s %s %s\n' "$PR" "$SHA" "$1" >"$OUTBOX/outcome" 2>/dev/null || :
  exit 1
}

# --- step 1: environment ------------------------------------------------------------------------
valid_name() { # one repo part
  case $1 in ''|.|..|-*|*[!A-Za-z0-9._-]*) return 1 ;; esac
  return 0
}
URL_HOST=
valid_url() { # http://<host>:<port>; sets URL_HOST
  case $1 in http://*:*) ;; *) return 1 ;; esac
  rest=${1#http://}
  h=${rest%:*}
  p=${rest##*:}
  case $h in ''|*[!A-Za-z0-9.-]*) return 1 ;; esac
  case $p in ''|*[!0-9]*) return 1 ;; esac
  URL_HOST=$h
  return 0
}

repo=${WOW_REVIEW_REPO:-}
case $repo in */*) ;; *) stop entry-env "WOW_REVIEW_REPO is invalid" ;; esac
valid_name "${repo%%/*}" && valid_name "${repo#*/}" || stop entry-env "WOW_REVIEW_REPO is invalid"

model=${WOW_REVIEW_MODEL:-}
case $model in ''|-*|*[!A-Za-z0-9._-]*) stop entry-env "WOW_REVIEW_MODEL is invalid" ;; esac

base_url=${ANTHROPIC_BASE_URL:-}
valid_url "$base_url" || stop entry-env "ANTHROPIC_BASE_URL is invalid"
BASE_HOST=$URL_HOST

n=0
cred_name=
cred_val=
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then n=$((n + 1)); cred_name=ANTHROPIC_API_KEY; cred_val=$ANTHROPIC_API_KEY; fi
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then n=$((n + 1)); cred_name=CLAUDE_CODE_OAUTH_TOKEN; cred_val=$CLAUDE_CODE_OAUTH_TOKEN; fi
[ "$n" -eq 1 ] || stop entry-env "exactly one of ANTHROPIC_API_KEY and CLAUDE_CODE_OAUTH_TOKEN must be set"
trimmed=${cred_val#"${cred_val%%[![:space:]]*}"}
case $trimmed in sk-ant-*) stop entry-env "$cred_name looks like a real credential" ;; esac
[ -z "${ANTHROPIC_AUTH_TOKEN+x}" ] || stop entry-env "ANTHROPIC_AUTH_TOKEN must be unset"

PROXY_ARGS=
if [ -n "${HTTPS_PROXY+x}${HTTP_PROXY+x}${NO_PROXY+x}${no_proxy+x}" ]; then
  if [ -n "${HTTPS_PROXY+x}" ]; then
    valid_url "$HTTPS_PROXY" || stop entry-env "HTTPS_PROXY is invalid"
    PROXY_ARGS="$PROXY_ARGS HTTPS_PROXY=$HTTPS_PROXY"
  fi
  if [ -n "${HTTP_PROXY+x}" ]; then
    valid_url "$HTTP_PROXY" || stop entry-env "HTTP_PROXY is invalid"
    PROXY_ARGS="$PROXY_ARGS HTTP_PROXY=$HTTP_PROXY"
  fi
  # NO_PROXY and no_proxy: both set, each a comma list of plain host names holding the base-URL host.
  for pv in NO_PROXY no_proxy; do
    eval "isset=\${$pv+x}; list=\${$pv:-}"
    [ -n "$isset" ] || stop entry-env "$pv must be set with the proxy variables"
    case $list in ''|,*|*,|*,,*) stop entry-env "$pv is invalid" ;; esac
    found=0
    oldifs=$IFS
    IFS=,
    for item in $list; do
      case $item in ''|*[!A-Za-z0-9.-]*) IFS=$oldifs; stop entry-env "$pv is invalid" ;; esac
      [ "$item" != "$BASE_HOST" ] || found=1
    done
    IFS=$oldifs
    [ "$found" -eq 1 ] || stop entry-env "$pv does not list the ANTHROPIC_BASE_URL host"
    PROXY_ARGS="$PROXY_ARGS $pv=$list"
  done
fi

[ -d "$HOME" ] && [ -r "$HOME" ] && [ -x "$HOME" ] || stop entry-env "HOME is not a directory"
if has_entry "$HOME"; then stop entry-env "HOME is not empty"; fi

# cenv <cmd...>: run under a cleaned environment with exactly the allowlist.
cenv() {
  # shellcheck disable=SC2086
  env -i HOME="$HOME" PATH="$PATH" SHELL="$SHELL" LANG=C.UTF-8 GIT_TERMINAL_PROMPT=0 \
    DISABLE_AUTOUPDATER=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    WOW_REVIEW_PR="$PR" WOW_REVIEW_SHA="$SHA" WOW_REVIEW_REPO="$repo" WOW_REVIEW_MODEL="$model" \
    ANTHROPIC_BASE_URL="$base_url" "$cred_name=$cred_val" $PROXY_ARGS "$@"
}

TMPD=$(cenv mktemp -d) && [ -n "$TMPD" ] && [ -d "$TMPD" ] || { TMPD=; stop entry-env "cannot create a temp directory"; }

# --- step 2: token ------------------------------------------------------------------------------
# The token is never read into a variable here; gh and git read it per call.
cenv "$LIBEXEC/dev-token" >/dev/null 2>&1 || stop entry-token "no live session token"

# --- step 3: clone (the default branch only, never the PR head) ---------------------------------
cenv timeout 120 git clone --quiet --single-branch "https://github.com/$repo" "$WORK" >/dev/null || stop entry-clone "clone failed"

# --- step 4: identity ----------------------------------------------------------------------------
yml=$WORK/.ai/project.yml
cenv yq -e '.identities.reviewer_app | tag == "!!map"' "$yml" >/dev/null 2>&1 || stop entry-identity "identities.reviewer_app is not a map"
cenv timeout 60 gh api --hostname github.com --paginate installation/repositories \
  --jq '.repositories[].full_name' >"$TMPD/inst.txt" || stop entry-identity "installation read failed"
V=$(cenv timeout 60 gh api --hostname github.com graphql -f query='{ viewer { login databaseId } }' \
  --jq '[.data.viewer.login, .data.viewer.databaseId] | @tsv') || stop entry-identity "viewer read failed"
login=$(printf '%s' "$V" | cenv cut -f1) || stop entry-identity "viewer read failed"
actor_id=$(printf '%s' "$V" | cenv cut -f2) || stop entry-identity "viewer read failed"
cenv "$LIBEXEC/token-check.sh" verify reviewer_app "$repo" "$TOKDIR/session-token" "$TMPD/inst.txt" \
  "$yml" "$login" "$actor_id" >/dev/null || stop entry-identity "token is not the declared reviewer App"

# --- step 5: plugin ------------------------------------------------------------------------------
settings=$WORK/.claude/settings.json
cenv jq -e --arg n "$MKT_NAME" --arg r "$MKT_REPO" '
  (.enabledPlugins[("way-of-working@" + $n)] == true)
  and (.extraKnownMarketplaces[$n].source
       | type == "object"
         and (keys == ["ref", "repo", "source"])
         and .source == "github"
         and .repo == $r
         and (.ref | type == "string" and test("\\Av[0-9]+[.][0-9]+[.][0-9]+\\z")))
' "$settings" >/dev/null 2>&1 || stop entry-plugin "the plugin pin is missing or wrong"
ref=$(cenv jq -r --arg n "$MKT_NAME" '.extraKnownMarketplaces[$n].source.ref' "$settings") || stop entry-plugin "the plugin pin is unreadable"
case $ref in v*.*.*) ;; *) stop entry-plugin "the plugin pin is wrong" ;; esac
case $ref in *[!0-9v.]*) stop entry-plugin "the plugin pin is wrong" ;; esac

(cd "$HOME" && cenv timeout 120 git ls-remote "https://github.com/$MKT_REPO" \
  "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}") >"$TMPD/lsr.txt" || stop entry-plugin "ls-remote failed"
heads=0; tags=0; peels=0; tag_sha=; peel_sha=
tab=$(printf '\t')
while IFS=$tab read -r lsha lref || [ -n "$lsha" ]; do
  case $lref in
    "refs/heads/$ref") heads=$((heads + 1)) ;;
    "refs/tags/$ref") tags=$((tags + 1)); tag_sha=$lsha ;;
    "refs/tags/$ref^{}") peels=$((peels + 1)); peel_sha=$lsha ;;
  esac
done <"$TMPD/lsr.txt"
[ "$heads" -eq 0 ] || stop entry-plugin "a branch is named like the tag"
[ "$tags" -eq 1 ] && [ "$peels" -le 1 ] || stop entry-plugin "the tag does not resolve to exactly one ref"
commit=${peel_sha:-$tag_sha}
case $commit in *[!0-9a-f]*|'') stop entry-plugin "the tag commit is malformed" ;; esac
[ "${#commit}" -eq 40 ] || stop entry-plugin "the tag commit is malformed"

(cd "$HOME" && cenv timeout 300 claude plugin marketplace add "$MKT_REPO@$ref" --scope user) >/dev/null || stop entry-plugin "marketplace add failed"
(cd "$HOME" && cenv timeout 300 claude plugin install "way-of-working@$MKT_NAME" --scope user) >/dev/null || stop entry-plugin "plugin install failed"

key="way-of-working@$MKT_NAME"
installed=$HOME/.claude/plugins/installed_plugins.json
cenv jq -e --arg k "$key" --arg c "$commit" '
  (.plugins[$k] | type == "array" and length == 1 and (.[0].scope == "user") and (.[0].gitCommitSha == $c))
' "$installed" >/dev/null 2>&1 || stop entry-plugin "the installed entry is wrong"
ipath=$(cenv jq -r --arg k "$key" '.plugins[$k][0].installPath // empty' "$installed") || stop entry-plugin "the installed entry is wrong"
chome=$(cd "$HOME" && pwd -P) || stop entry-plugin "HOME is unreadable"
croot=$chome/.claude/plugins/cache
case $ipath in "$croot"/?*) ;; *) stop entry-plugin "installPath is outside the plugin cache" ;; esac
rel=${ipath#"$croot"/}
case "/$rel/" in */../*|*/./*|*//*) stop entry-plugin "installPath is not canonical" ;; esac
cur=$chome
for seg in .claude plugins cache; do
  cur=$cur/$seg
  { [ -d "$cur" ] && [ ! -L "$cur" ]; } || stop entry-plugin "installPath runs through a link"
done
oldifs=$IFS
IFS=/
for seg in $rel; do
  cur=$cur/$seg
  { [ -d "$cur" ] && [ ! -L "$cur" ]; } || { IFS=$oldifs; stop entry-plugin "installPath runs through a link"; }
done
IFS=$oldifs
floor=$ipath/bin/review-sandbox.sh
{ [ -f "$floor" ] && [ ! -L "$floor" ]; } || stop entry-plugin "the installed plugin has no review-sandbox.sh"
cenv grep -qxF 'REVIEW_CONTAINER_MARKER=/etc/way-of-working/review-container' "$floor" \
  || stop entry-plugin "the installed plugin predates the review-container marker"
outbox_writer=$ipath/bin/review-outbox.sh
{ [ -f "$outbox_writer" ] && [ ! -L "$outbox_writer" ]; } || stop entry-plugin "the installed plugin has no review-outbox.sh"
cenv grep -qxF 'REVIEW_OUTBOX=/review-out' "$outbox_writer" \
  || stop entry-plugin "the installed plugin predates the outbox writer"

# --- step 6: run ---------------------------------------------------------------------------------
cd "$WORK" || stop entry-clone "cannot enter the clone"
cleanup
trap - EXIT
exec env -i HOME="$HOME" PATH="$PATH" SHELL="$SHELL" LANG=C.UTF-8 GIT_TERMINAL_PROMPT=0 \
  DISABLE_AUTOUPDATER=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 \
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
  WOW_REVIEW_PR="$PR" WOW_REVIEW_SHA="$SHA" WOW_REVIEW_REPO="$repo" WOW_REVIEW_MODEL="$model" \
  ANTHROPIC_BASE_URL="$base_url" "$cred_name=$cred_val" $PROXY_ARGS \
  claude -p "/way-of-working:architect-review $PR --pin $SHA" --model "$model" \
  --setting-sources user --permission-mode bypassPermissions </dev/null
