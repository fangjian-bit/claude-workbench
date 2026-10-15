#!/bin/sh
# Mint a scoped GitHub App installation token (WB-D24, issue #373).
#
#   mint.sh --client-id ID --installation-id ID --key PEM_FILE \
#           --repos name[,name...] --perms perm=level[,perm=level...] \
#           --out FILE [--strict]
#
# --client-id is the App's Client ID (Iv...), which GitHub uses as the JWT `iss` in place of the
# numeric App ID.
#
# Signs a short-lived App JWT (RS256, via openssl) and POSTs
# https://api.github.com/app/installations/{id}/access_tokens with a `repositories` and
# `permissions` subset, so the token is never the installation's full grant. Both lists are
# required and non-empty. The API host is fixed: the JWT is as good as the App key for its
# nine minutes, so no argument may choose where it is sent.
#
# Output: FILE holds two lines -- the token, then its `expires_at`. The token is never printed
# to stdout or stderr, and neither it nor the JWT appears on a command line: curl reads its
# headers and body from a config on stdin and answers on stdout, so no temp file or path
# reaches curl (a native Windows curl cannot open an MSYS /tmp path named inside a config).
# The only file the token touches is a temp file beside FILE, created under umask 077 and
# renamed into place. NTFS has no POSIX modes: there, FILE's confidentiality is its directory's ACL.
#
# --strict refuses a token that differs from what was requested. After the token and expires_at
# are validated, and before anything is staged, the response must report `permissions` equal to
# the requested map (same names, same levels; a `metadata: read` entry GitHub adds is tolerated
# only when metadata was not requested) and `repositories` naming exactly the requested set. A
# refusal exits 1 with a message that appends nothing from the response, and the token is never
# staged, written or printed. This relies on GitHub reporting back what it granted, which is not
# yet verified live. Repository names compare case-sensitively, so they must be in GitHub's
# canonical case. A refused token still exists on GitHub until it expires, although it was never
# written to a file, printed or placed on a command line. Any failed mint, strict or not, leaves
# an existing --out file as it was, so a caller treats a non-zero exit as "no token".
#
# Run on the host, where the App key lives; no key is ever copied into a container. Exit 0 on
# success, 1 on a failed mint (API error, bad response, strict refusal), 2 on bad usage.
#
# Toolset: POSIX sh, openssl, curl, jq.
set -eu
set -f # --repos / --perms are split unquoted below; never let a `*` glob into file names
LC_ALL=C; export LC_ALL # so [!A-Za-z0-9] means ASCII only in every shell and locale

die() { echo "mint.sh: $1" >&2; exit "${2:-1}"; }
usage() { die "usage: mint.sh --client-id ID --installation-id ID --key PEM --repos a,b --perms p=l,... --out FILE [--strict]" 2; }

# --strict is a bare flag, anywhere. Every other flag takes one value, which may not begin with
# `-` (so `--out --strict` is a usage error, never a file named --strict); a repeat keeps the last.
client_id= inst_id= key= repos= perms= out= strict=0
while [ $# -gt 0 ]; do
  if [ "$1" = --strict ]; then strict=1; shift; continue; fi
  [ $# -ge 2 ] || usage
  case "$2" in -*) usage ;; esac
  case "$1" in
    --client-id) client_id=$2 ;;
    --installation-id) inst_id=$2 ;;
    --key) key=$2 ;;
    --repos) repos=$2 ;;
    --perms) perms=$2 ;;
    --out) out=$2 ;;
    *) usage ;;
  esac
  shift 2
done

is_num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

case "$client_id" in ""|*[!A-Za-z0-9]*) die "--client-id must be the App's Client ID (letters and digits)" 2 ;; esac
is_num "$inst_id" || die "--installation-id must be a number" 2
[ -n "$key" ] && [ -r "$key" ] || die "--key must name a readable PEM file" 2
[ -n "$out" ] || die "--out is required" 2
[ ! -d "$out" ] && [ ! -L "$out" ] || die "--out must not be a directory or a symlink" 2
outdir=$(dirname -- "$out")
[ -d "$outdir" ] || die "--out: directory $outdir does not exist" 2

# Every element is validated against a closed character set before it is spliced into JSON.
repos_json= perms_json= seen=,
old_ifs=$IFS
IFS=,
for r in $repos; do
  case "$r" in ''|*[!A-Za-z0-9._-]*) IFS=$old_ifs; die "--repos: bad repository name '$r'" 2 ;; esac
  repos_json="${repos_json:+$repos_json,}\"$r\""
done
for p in $perms; do
  name=${p%%=*} level=${p#*=}
  case "$name" in ''|*[!a-z_]*) IFS=$old_ifs; die "--perms: bad permission name in '$p'" 2 ;; esac
  case "$level" in read|write|admin) ;; *) IFS=$old_ifs; die "--perms: level must be read, write or admin in '$p'" 2 ;; esac
  [ "$name=$level" = "$p" ] || { IFS=$old_ifs; die "--perms: expected name=level, got '$p'" 2; }
  case "$seen" in *",$name,"*) IFS=$old_ifs; die "--perms: '$name' given twice" 2 ;; esac
  seen="$seen$name,"
  perms_json="${perms_json:+$perms_json,}\"$name\":\"$level\""
done
IFS=$old_ifs
[ -n "$repos_json" ] || die "--repos must name at least one repository" 2
[ -n "$perms_json" ] || die "--perms must name at least one permission" 2

for tool in jq openssl curl; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not on PATH"
done

staged=
trap '[ -z "$staged" ] || rm -f "$staged"' EXIT
trap 'exit 1' INT TERM HUP

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
# iat is back-dated 60s for clock skew; exp stays inside GitHub's 10-minute ceiling.
claims=$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$client_id" | b64url)
sig=$(printf '%s.%s' "$header" "$claims" | openssl dgst -sha256 -sign "$key" -binary | b64url) \
  || die "openssl could not sign with $key"
[ -n "$sig" ] || die "openssl produced no signature"
jwt="$header.$claims.$sig"

# The body is a quoted config string: its only special characters are the double quotes.
body=$(printf '{"repositories":[%s],"permissions":{%s}}' "$repos_json" "$perms_json" | sed 's/"/\\"/g')
[ -n "$body" ] || die "empty request body"

# JWT and body go in a stdin config, not argv, so neither shows in a process listing. The
# response comes back on stdout, status last. -q first: without it curl also reads
# ~/.curlrc / $CURL_HOME, whose trace or output lines would write the JWT and token to disk.
reply=$(
  {
    printf 'url = "https://api.github.com/app/installations/%s/access_tokens"\n' "$inst_id"
    printf 'request = "POST"\n'
    printf 'header = "Authorization: Bearer %s"\n' "$jwt"
    printf 'header = "Accept: application/vnd.github+json"\n'
    printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n'
    printf 'header = "Content-Type: application/json"\n'
    printf 'data-binary = "%s"\n' "$body"
  } | curl -q -sS --max-time 30 -K - -w '\n%{http_code}'
) || die "curl failed"

code=${reply##*
}
resp=${reply%
*}

if [ "$code" != 201 ]; then
  msg=$(printf '%s' "$resp" | jq -r '.message // empty' 2>/dev/null | tr -d '[:cntrl:]' | cut -c1-200 || true)
  die "GitHub answered HTTP $code${msg:+: $msg}"
fi

token=$(printf '%s' "$resp" | jq -r '.token // empty') || die "response is not JSON"
expires=$(printf '%s' "$resp" | jq -r '.expires_at // empty') || die "response is not JSON"
[ -n "$token" ] && [ -n "$expires" ] || die "response lacks a token or expires_at"
# The file is a credential file other tools read: only token- and timestamp-shaped content.
# GitHub's installation tokens are ghs_ + 36 or more of [A-Za-z0-9._-]: the stateless ghs_APPID_JWT
# format (2026-04-27 rollout) is ~520 characters of variable length with dots and dashes.
case "$token" in ghs_*) tok_body=${token#ghs_} ;; *) tok_body= ;; esac
case "$tok_body" in *[!A-Za-z0-9._-]*) tok_body= ;; esac
[ "${#tok_body}" -ge 36 ] || die "response token is not token-shaped"
case "$expires" in *[!0-9TZ:-]*) die "response expires_at is not a timestamp" ;; esac

# --strict: the response reaches jq on stdin only; the requested sets go in as --argjson, built
# from the validated --perms / --repos elements. Each predicate is a parenthesised `== true`, so
# its only outputs are true and false and jq -e's exit status is the verdict. stderr is dropped
# because a jq runtime error prints a truncated copy of the value it failed on.
if [ "$strict" -eq 1 ]; then
# The response is slurped and must be exactly one JSON value: jq -e judges the last output
# only, so a second document could otherwise decide for a first that carried the token.
  printf '%s' "$resp" | jq -e -s --argjson want "{$perms_json}" '
    (  (length == 1)
       and (.[0] | (  (.permissions | type == "object")
                      and ((.permissions
                            | if has("metadata") and .metadata == "read" and ($want | has("metadata") | not)
                              then del(.metadata) else . end) == $want)  ))  ) == true' >/dev/null 2>&1 \
    || die "--strict: GitHub granted permissions other than requested"
  printf '%s' "$resp" | jq -e -s --argjson want "[$repos_json]" '
    (  (length == 1)
       and (.[0] | (  (.repositories | type == "array")
                      and (.repositories | all(.[]; type == "object" and (.name | type == "string")))
                      and ((.repositories | map(.name) | unique) == ($want | unique))  ))  ) == true' >/dev/null 2>&1 \
    || die "--strict: GitHub granted repositories other than requested"
fi

staged=$(umask 077 && mktemp -- "$outdir/.mint.XXXXXX") || die "cannot stage the token beside $out"
printf '%s\n%s\n' "$token" "$expires" >"$staged" || die "cannot write the token"
# Re-check just before the rename: if $out became a directory (or a link to one) during the
# round-trip, mv would move the token inside it. A private --out directory is what closes it.
[ ! -d "$out" ] && [ ! -L "$out" ] || die "$out became a directory or symlink"
mv -f -- "$staged" "$out" || die "cannot write $out"
staged=
echo "minted token for installation $inst_id, expires $expires"
