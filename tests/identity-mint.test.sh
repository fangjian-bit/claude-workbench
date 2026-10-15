#!/bin/sh
# Fixture tests for scripts/identity/mint.sh (issue #373).
#
# A stub `curl` stands in for GitHub: it records its argv and the config piped to it on stdin,
# prints a canned body and status on stdout as `curl -w` would (or exits non-zero, as on a
# transport failure). A throwaway RSA key signs the
# JWT, and the public half verifies it, so the signature is checked and not just its shape.
#
#   success          token + expires_at land in --out (two lines), mode 600
#   request          POST to /app/installations/<id>/access_tokens with the repositories and
#                    permissions subset, and the JWT in the config, never in argv
#   jwt              RS256, verifies against the public key, iss = client id, exp - iat <= 10 min
#   secrecy          neither the token nor the JWT reaches stdout, stderr or argv
#   API failure      non-201, and a 201 with no token: exit 1, no --out file left behind
#   --strict         a response that is exactly the requested permissions (plus metadata: read) and
#                    repositories is written; every other shape (extra, missing or changed permission,
#                    extra, missing or re-cased repository, absent or malformed keys, metadata: write)
#                    exits 1 with an exact message, no --out file, no staging file, no token anywhere
#                    on stdout, stderr or any jq argv; a refusal keeps an existing --out; --strict works
#                    in any position; without it an extra permission still exits 0; the type check is
#                    not fooled by a bare string beside a valid name; a response of more than one JSON
#                    document is refused, whichever document is good
#   jq argv          a wrapper records every jq call per run: each strict run made a `-e` call, and no
#                    token is ever in any recorded argv
#   usage            missing/odd arguments exit 2 before curl is ever called
#
# Permitted toolset: POSIX sh, its standard utilities, openssl and jq (the script's own
# dependencies).
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/identity/mint.sh"

for tool in openssl jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP - $tool not on PATH; identity-mint fixtures not run" >&2
    exit 0
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"

openssl genrsa -out "$tmp/key.pem" 2048 >/dev/null 2>&1
openssl rsa -in "$tmp/key.pem" -pubout -out "$tmp/pub.pem" >/dev/null 2>&1

cat >"$tmp/bin/curl" <<'STUB'
#!/bin/sh
# Records what mint.sh sent; answers on stdout as curl -w does: body, newline, status.
printf '%s\n' "$@" >"$STUB_DIR/argv"
cat >"$STUB_DIR/stdin"
echo called >>"$STUB_DIR/calls"
sed -n 's/^data-binary = "\(.*\)"$/\1/p' "$STUB_DIR/stdin" | sed 's/\\"/"/g' >"$STUB_DIR/sent-body"
[ -z "${STUB_MKDIR:-}" ] || mkdir "$STUB_MKDIR" # --out turns into a directory mid-request
[ "${STUB_RC:-0}" -eq 0 ] || exit "$STUB_RC" # a transport failure: curl exits non-zero, prints nothing
printf '%s\n%s' "$STUB_BODY" "$STUB_STATUS"
STUB
chmod +x "$tmp/bin/curl"
# A jq wrapper that records each call's argv, then runs the real jq. The real jq is resolved
# here, before run() puts $tmp/bin first on PATH.
REAL_JQ=$(command -v jq); export REAL_JQ
cat >"$tmp/bin/jq" <<'STUB'
#!/bin/sh
{ echo '--call--'; printf '%s\n' "$@"; } >>"$STUB_DIR/jq-argv"
exec "$REAL_JQ" "$@"
STUB
chmod +x "$tmp/bin/jq"

fail=0
pass_count=0

ok() { pass_count=$((pass_count + 1)); }
bad() { echo "FAIL: $1 -- $2" >&2; fail=1; }

assert_eq() {
  if [ "$2" = "$3" ]; then ok; else bad "$1" "expected '$2', got '$3'"; fi
}

assert_contains() { # desc haystack needle
  case "$2" in *"$3"*) ok ;; *) bad "$1" "'$3' not found in: $2" ;; esac
}

assert_absent() { # desc haystack needle
  case "$2" in *"$3"*) bad "$1" "'$3' leaked into: $2" ;; *) ok ;; esac
}

TOKEN=ghs_faketoken0123456789abcdefghijklmnopqrstuv
EXPIRES=2026-10-09T01:00:00Z
GOOD_BODY="{\"token\":\"$TOKEN\",\"expires_at\":\"$EXPIRES\"}"

# run <status> <body> <args...> -> sets rc, so, se; resets the stub's recordings
run() {
  STUB_STATUS=$1 STUB_BODY=$2
  shift 2
  rm -f "$tmp/argv" "$tmp/stdin" "$tmp/calls" "$tmp/jq-argv"
  rc=0
  STUB_DIR=$tmp STUB_STATUS=$STUB_STATUS STUB_BODY=$STUB_BODY STUB_RC=${STUB_RC:-0} \
  STUB_MKDIR=${STUB_MKDIR:-} PATH="$tmp/bin:$PATH" \
    sh "$script" "$@" >"$tmp/so" 2>"$tmp/se" || rc=$?
  so=$(cat "$tmp/so")
  se=$(cat "$tmp/se")
  # The response reaches jq on stdin only: whatever token the body carried is in no jq argv.
  body_tok=$(printf '%s' "$STUB_BODY" | jq -r '.token? // empty' 2>/dev/null || true)
  if [ "${#body_tok}" -ge 20 ] && [ -f "$tmp/jq-argv" ]; then
    if grep -qF -- "$body_tok" "$tmp/jq-argv"; then bad "token in jq argv" "recorded in $tmp/jq-argv"; else ok; fi
  fi
}

good_args() {
  echo --client-id Iv23liTestClient0001 --installation-id 678 --key "$tmp/key.pem" \
       --repos claude-workbench,devcontainers --perms contents=write,pull_requests=write \
       --out "$tmp/token"
}

# --- success ---------------------------------------------------------------------------------
rm -f "$tmp/token"
t_before=$(date +%s)
# shellcheck disable=SC2046
run 201 "$GOOD_BODY" $(good_args)
t_after=$(date +%s)
assert_eq "success exits 0" 0 "$rc"
assert_eq "token file line 1" "$TOKEN" "$(sed -n 1p "$tmp/token")"
assert_eq "token file line 2" "$EXPIRES" "$(sed -n 2p "$tmp/token")"
assert_eq "token file has exactly two lines" 2 "$(wc -l <"$tmp/token" | tr -d ' ')"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ok ;; # NTFS has no POSIX modes; the umask is still set in the script
  *) assert_eq "token file mode" "-rw-------" "$(ls -l "$tmp/token" | cut -c1-10)" ;;
esac
# the staged temp file is renamed away, not left beside the output
assert_eq "no staging file left behind" "" "$(ls -A "$tmp" | grep '^\.mint\.' || true)"

# --- request shape ---------------------------------------------------------------------------
cfg=$(cat "$tmp/stdin")
assert_contains "POSTs to the installation's token endpoint" "$cfg" \
  'url = "https://api.github.com/app/installations/678/access_tokens"'
assert_contains "request is POST" "$cfg" 'request = "POST"'
assert_contains "sends a bearer header" "$cfg" 'header = "Authorization: Bearer '
assert_contains "body is inline in the config" "$cfg" 'data-binary = "{'
assert_absent "config names no file for curl to open (native Windows curl cannot read /tmp)" "$cfg" '"@'
assert_absent "curl is given no -o file" "$(cat "$tmp/argv")" '-o'
assert_eq "curl ignores ambient ~/.curlrc (-q first)" "-q" "$(sed -n 1p "$tmp/argv")"
# The exact line: the stub's greedy capture would still yield valid JSON if the quote
# escaping were dropped, but real curl would then read the value as a bare `{`.
assert_contains "body line is quote-escaped for curl's config parser" "$cfg" \
  'data-binary = "{\"repositories\":[\"claude-workbench\",\"devcontainers\"],\"permissions\":{\"contents\":\"write\",\"pull_requests\":\"write\"}}"'
assert_eq "body repositories" '["claude-workbench","devcontainers"]' \
  "$(jq -c .repositories "$tmp/sent-body")"
assert_eq "body permissions" '{"contents":"write","pull_requests":"write"}' \
  "$(jq -c .permissions "$tmp/sent-body")"

# --- JWT -------------------------------------------------------------------------------------
jwt=$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p' "$tmp/stdin")
h=${jwt%%.*}; rest=${jwt#*.}; c=${rest%%.*}; s=${rest#*.}

unb64() { # base64url on stdin -> bytes on stdout
  v=$(cat | tr '_-' '/+')
  case $((${#v} % 4)) in 2) v="$v==" ;; 3) v="$v=" ;; esac
  printf '%s' "$v" | openssl base64 -d -A
}

assert_eq "JWT header" '{"alg":"RS256","typ":"JWT"}' "$(printf '%s' "$h" | unb64)"
claims=$(printf '%s' "$c" | unb64)
assert_eq "JWT iss is the client id" Iv23liTestClient0001 "$(printf '%s' "$claims" | jq -r .iss)"
iat=$(printf '%s' "$claims" | jq '.iat')
exp=$(printf '%s' "$claims" | jq '.exp')
# GitHub's rules: iat not in the future, exp at most ten minutes ahead of the request.
if [ "$iat" -le "$t_after" ] && [ "$exp" -le "$((t_after + 600))" ] && [ "$exp" -gt "$t_before" ]
then ok; else bad "JWT lifetime" "iat=$iat exp=$exp, run was between $t_before and $t_after"; fi
printf '%s' "$s" | unb64 >"$tmp/sig.bin"
if printf '%s.%s' "$h" "$c" | openssl dgst -sha256 -verify "$tmp/pub.pem" -signature "$tmp/sig.bin" >/dev/null 2>&1
then ok; else bad "JWT signature" "does not verify against the public key"; fi

# --- secrecy ---------------------------------------------------------------------------------
argv=$(cat "$tmp/argv")
assert_absent "JWT not in curl argv" "$argv" "$jwt"
assert_absent "token not in stdout" "$so" "$TOKEN"
assert_absent "token not in stderr" "$se" "$TOKEN"
assert_absent "JWT not in stdout" "$so" "$jwt"
assert_absent "JWT not in stderr" "$se" "$jwt"

# --- API failures leave nothing behind -------------------------------------------------------
rm -f "$tmp/token"
# shellcheck disable=SC2046
run 401 '{"message":"A JSON web token could not be decoded"}' $(good_args)
assert_eq "401 exits 1" 1 "$rc"
assert_contains "401 reports the status" "$se" "HTTP 401"
assert_contains "401 reports the message" "$se" "could not be decoded"
[ ! -e "$tmp/token" ] && ok || bad "401 leaves no out file" "$tmp/token exists"

# shellcheck disable=SC2046
run 201 '{"expires_at":"2026-10-09T01:00:00Z"}' $(good_args)
assert_eq "201 without a token exits 1" 1 "$rc"
[ ! -e "$tmp/token" ] && ok || bad "tokenless 201 leaves no out file" "$tmp/token exists"

# shellcheck disable=SC2046
run 201 'not json' $(good_args)
assert_eq "non-JSON 201 exits 1" 1 "$rc"
[ ! -e "$tmp/token" ] && ok || bad "non-JSON 201 leaves no out file" "$tmp/token exists"

# A response is never trusted to shape a credential file the host may later source.
# shellcheck disable=SC2046
run 201 '{"token":"x\nrm -rf ~","expires_at":"2026-10-09T01:00:00Z"}' $(good_args)
assert_eq "non-token-shaped token exits 1" 1 "$rc"
[ ! -e "$tmp/token" ] && ok || bad "non-token-shaped token leaves no out file" "$tmp/token exists"

# GitHub's stateless ghs_APPID_JWT format: long, with dots and dashes (changelog 2026-04-24).
JWT_TOKEN=ghs_12345_eyJhbGciOiJSUzI1NiJ9.eyJpYXQiOjE3NjAwMDAwMDB9-abc_DEF.c2lnbmF0dXJlLXNpZ25hdHVyZS1zaWduYXR1cmU
rm -f "$tmp/token"
# shellcheck disable=SC2046
run 201 "{\"token\":\"$JWT_TOKEN\",\"expires_at\":\"$EXPIRES\"}" $(good_args)
assert_eq "JWT-format token exits 0" 0 "$rc"
assert_eq "JWT-format token written" "$JWT_TOKEN" "$(sed -n 1p "$tmp/token")"

# Short, unprefixed and over-wide-charset tokens are still refused.
for bad_tok in ghs_short ghp_faketoken0123456789abcdefghijklmnopqrstuv faketoken0123456789abcdefghijklmnopqrstuvwxyz ghs_faketoken0123456789abcdefghijklmnopqrstuv+/= ; do
  rm -f "$tmp/token"
  # shellcheck disable=SC2046
  run 201 "{\"token\":\"$bad_tok\",\"expires_at\":\"$EXPIRES\"}" $(good_args)
  assert_eq "token '$bad_tok' exits 1" 1 "$rc"
  [ ! -e "$tmp/token" ] && ok || bad "token '$bad_tok' leaves no out file" "$tmp/token exists"
done

# shellcheck disable=SC2046
run 201 '{"token":"'"$TOKEN"'","expires_at":"soon; reboot"}' $(good_args)
assert_eq "non-timestamp expires_at exits 1" 1 "$rc"
[ ! -e "$tmp/token" ] && ok || bad "non-timestamp expires_at leaves no out file" "$tmp/token exists"

# Terminal escapes in an error message are stripped before they reach stderr. The escape is
# sent as a JSON \u001b so jq decodes it; a raw ESC byte is invalid JSON and would be dropped
# before the stripping ever mattered.
# shellcheck disable=SC2046
run 500 '{"message":"bad\u001b[31mred"}' $(good_args)
assert_contains "the message still reaches stderr" "$se" "red"
assert_absent "control characters stripped from the API message" "$se" "$(printf '\033')"

# The status is split from the last line only: multi-line replies must not move it.
# shellcheck disable=SC2046
run 201 "{
  \"token\": \"$TOKEN\",
  \"expires_at\": \"$EXPIRES\"
}" $(good_args)
assert_eq "pretty-printed 201 exits 0" 0 "$rc"
assert_eq "pretty-printed 201 token lands in the file" "$TOKEN" "$(sed -n 1p "$tmp/token")"
rm -f "$tmp/token"
# shellcheck disable=SC2046
run 401 '{
  "message": "Bad credentials",
  "status": "401"
}' $(good_args)
assert_eq "pretty-printed 401 exits 1" 1 "$rc"
assert_contains "pretty-printed 401 reports status and message" "$se" "HTTP 401: Bad credentials"

# If --out becomes a directory during the round-trip, mv would drop the token inside it.
mkdir "$tmp/racedir"
STUB_MKDIR=$tmp/racedir/token
run 201 "$GOOD_BODY" --client-id 1 --installation-id 2 --key "$tmp/key.pem" --repos a \
  --perms contents=read --out "$tmp/racedir/token"
unset STUB_MKDIR
assert_eq "out turning into a directory exits 1" 1 "$rc"
assert_contains "out race is reported" "$se" "became a directory"
assert_eq "nothing left inside the raced directory" "" "$(ls -A "$tmp/racedir/token")"
assert_eq "no staging file left beside it" "" "$(ls -A "$tmp/racedir" | grep '^\.mint\.' || true)"

# A transport failure (curl exits non-zero) is a failed mint, not a parsed reply.
STUB_RC=7
# shellcheck disable=SC2046
run 000 '' $(good_args)
unset STUB_RC
assert_eq "curl failure exits 1" 1 "$rc"
assert_contains "curl failure is reported" "$se" "curl failed"
[ ! -e "$tmp/token" ] && ok || bad "curl failure leaves no out file" "$tmp/token exists"

# A failed mint leaves the previous token in place rather than a partial one.
printf 'old\n2026-01-01T00:00:00Z\n' >"$tmp/token"
# shellcheck disable=SC2046
run 401 '{"message":"nope"}' $(good_args)
assert_eq "failed mint keeps the old out file" "old" "$(sed -n 1p "$tmp/token")"
rm -f "$tmp/token"

# --- usage messages read cleanly (no stray exit code appended) -------------------------------
run 201 "$GOOD_BODY" --client-id "a b" --installation-id 1 --key "$tmp/key.pem" --repos a --perms contents=read --out "$tmp/token"
assert_eq "usage message has no stray exit code" "mint.sh: --client-id must be the App's Client ID (letters and digits)" "$se"

# --- a glob in --repos is a bad name, never expanded against the working directory -----------
mkdir "$tmp/globdir" && : >"$tmp/globdir/other-repo"
(cd "$tmp/globdir" && STUB_DIR=$tmp STUB_STATUS=201 STUB_BODY=$GOOD_BODY PATH="$tmp/bin:$PATH" \
  sh "$script" --client-id 1 --installation-id 2 --key "$tmp/key.pem" --repos '*' \
    --perms contents=read --out "$tmp/token" >/dev/null 2>&1) && globrc=0 || globrc=$?
assert_eq "--repos '*' exits 2" 2 "$globrc"

# --- --strict --------------------------------------------------------------------------------
# good_args asks for contents=write,pull_requests=write on claude-workbench and devcontainers.
P_OK='{"contents":"write","pull_requests":"write","metadata":"read"}'
R_OK='[{"name":"claude-workbench"},{"name":"devcontainers"}]'
PERM_MSG='mint.sh: --strict: GitHub granted permissions other than requested'
REPO_MSG='mint.sh: --strict: GitHub granted repositories other than requested'

# sbody <permissions-json|-> <repositories-json|-> : a 201 body; "-" leaves the key out
sbody() {
  printf '{"token":"%s","expires_at":"%s"' "$TOKEN" "$EXPIRES"
  [ "$1" = - ] || printf ',"permissions":%s' "$1"
  [ "$2" = - ] || printf ',"repositories":%s' "$2"
  printf '}'
}

assert_strict_ran() { # desc: the recorded jq argv holds a `-e` call
  if grep -qx -- '-e' "$tmp/jq-argv" 2>/dev/null; then ok; else bad "$1" "no jq -e call recorded"; fi
}

# strict_refuses <desc> <message> <body> [args...]: exit 1, exact message, nothing written or leaked
strict_refuses() {
  desc=$1 msg=$2 body=$3; shift 3
  rm -f "$tmp/token"
  if [ $# -eq 0 ]; then
    # shellcheck disable=SC2046
    run 201 "$body" --strict $(good_args)
  else
    run 201 "$body" "$@"
  fi
  assert_eq "strict: $desc exits 1" 1 "$rc"
  assert_eq "strict: $desc message" "$msg" "$se"
  [ ! -e "$tmp/token" ] && ok || bad "strict: $desc leaves no out file" "$tmp/token exists"
  assert_eq "strict: $desc leaves no staging file" "" "$(ls -A "$tmp" | grep '^\.mint\.' || true)"
  assert_absent "strict: $desc token not on stdout" "$so" "$TOKEN"
  assert_absent "strict: $desc token not on stderr" "$se" "$TOKEN"
  assert_strict_ran "strict: $desc ran through the jq wrapper"
}

# exact response, plus metadata: read
rm -f "$tmp/token"
# shellcheck disable=SC2046
run 201 "$(sbody "$P_OK" "$R_OK")" --strict $(good_args)
assert_eq "strict: exact response exits 0" 0 "$rc"
assert_eq "strict: exact response writes the token" "$TOKEN" "$(sed -n 1p "$tmp/token")"
assert_strict_ran "strict: exact response ran through the jq wrapper"
# key order and a repeated --strict do not matter
rm -f "$tmp/token"
# shellcheck disable=SC2046
run 201 "$(sbody '{"metadata":"read","pull_requests":"write","contents":"write"}' '[{"name":"devcontainers"},{"name":"claude-workbench"}]')" --strict --strict $(good_args)
assert_eq "strict: reordered response and repeated flag exit 0" 0 "$rc"
assert_strict_ran "strict: reordered response ran through the jq wrapper"
# a requested metadata permission is compared like any other
rm -f "$tmp/token"
run 201 "$(sbody '{"metadata":"read","contents":"read"}' '[{"name":"a"}]')" --strict --client-id 1 --installation-id 2 \
  --key "$tmp/key.pem" --repos a --perms metadata=read,contents=read --out "$tmp/token"
assert_eq "strict: requested metadata=read exits 0" 0 "$rc"
assert_strict_ran "strict: requested metadata ran through the jq wrapper"
# a repeated --repos element is compared as a set
rm -f "$tmp/token"
run 201 "$(sbody '{"contents":"read"}' '[{"name":"a"}]')" --strict --client-id 1 --installation-id 2 \
  --key "$tmp/key.pem" --repos a,a --perms contents=read --out "$tmp/token"
assert_eq "strict: repeated --repos element exits 0" 0 "$rc"
assert_strict_ran "strict: repeated --repos ran through the jq wrapper"

strict_refuses "extra permission" "$PERM_MSG" \
  "$(sbody '{"contents":"write","pull_requests":"write","issues":"read","metadata":"read"}' "$R_OK")"
strict_refuses "missing permission" "$PERM_MSG" "$(sbody '{"contents":"write","metadata":"read"}' "$R_OK")"
strict_refuses "changed level" "$PERM_MSG" \
  "$(sbody '{"contents":"read","pull_requests":"write","metadata":"read"}' "$R_OK")"
strict_refuses "metadata: write" "$PERM_MSG" \
  "$(sbody '{"contents":"write","pull_requests":"write","metadata":"write"}' "$R_OK")"
strict_refuses "no permissions key" "$PERM_MSG" "$(sbody - "$R_OK")"
strict_refuses "permissions not an object" "$PERM_MSG" "$(sbody '"contents"' "$R_OK")"
strict_refuses "permissions an array" "$PERM_MSG" "$(sbody '[]' "$R_OK")"
strict_refuses "extra repository" "$REPO_MSG" \
  "$(sbody "$P_OK" '[{"name":"claude-workbench"},{"name":"devcontainers"},{"name":"extra"}]')"
strict_refuses "missing repository" "$REPO_MSG" "$(sbody "$P_OK" '[{"name":"claude-workbench"}]')"
strict_refuses "repository differing in case" "$REPO_MSG" \
  "$(sbody "$P_OK" '[{"name":"Claude-Workbench"},{"name":"devcontainers"}]')"
strict_refuses "no repositories key" "$REPO_MSG" "$(sbody "$P_OK" -)"
strict_refuses "repositories not an array" "$REPO_MSG" "$(sbody "$P_OK" '{"name":"claude-workbench"}')"
strict_refuses "empty repositories" "$REPO_MSG" "$(sbody "$P_OK" '[]')"
strict_refuses "repository element not an object" "$REPO_MSG" \
  "$(sbody "$P_OK" '[{"name":"claude-workbench"},{"name":"devcontainers"},7]')"
strict_refuses "repository name not a string" "$REPO_MSG" \
  "$(sbody "$P_OK" '[{"name":"claude-workbench"},{"name":5}]')"
strict_refuses "repository element without a name" "$REPO_MSG" \
  "$(sbody "$P_OK" '[{"name":"claude-workbench"},{"id":5}]')"
# permissions are checked first: both wrong reports the permissions line only
strict_refuses "both wrong" "$PERM_MSG" "$(sbody '{}' '[]')"
# a bare string beside a valid name leaves the name set unchanged: a lenient name gatherer
# (.name?, select(type=="object")) would accept it
strict_refuses "stream order: bare string among objects" "$REPO_MSG" \
  "$(sbody "$P_OK" '["claude-workbench",{"name":"claude-workbench"},{"name":"devcontainers"}]')"

# two JSON documents: jq -e would judge the last only, so the first (with the token) must not pass
TWO_DOCS="$(sbody '{"contents":"write","pull_requests":"write","admin":"write"}' '[{"name":"claude-workbench"},{"name":"devcontainers"},{"name":"x"}]') {\"permissions\":$P_OK,\"repositories\":$R_OK}"
strict_refuses "two documents, the last one good" "$PERM_MSG" "$TWO_DOCS"
TWO_DOCS="$(sbody "$P_OK" "$R_OK") {\"permissions\":{},\"repositories\":[]}"
strict_refuses "two documents, the first one good" "$PERM_MSG" "$TWO_DOCS"
# both pass the predicate: only the exactly-one-document rule refuses this
TWO_DOCS="$(sbody "$P_OK" "$R_OK") {\"permissions\":$P_OK,\"repositories\":$R_OK}"
strict_refuses "two documents, both good" "$PERM_MSG" "$TWO_DOCS"

# a refusal leaves an existing --out byte for byte
printf 'old\n2026-01-01T00:00:00Z\n' >"$tmp/token"
cp "$tmp/token" "$tmp/token.orig"
# shellcheck disable=SC2046
run 201 "$(sbody '{"contents":"write"}' "$R_OK")" --strict $(good_args)
assert_eq "strict: refusal exits 1 with an existing out file" 1 "$rc"
assert_strict_ran "strict: existing-out refusal ran through the jq wrapper"
if cmp -s "$tmp/token" "$tmp/token.orig"; then ok; else bad "strict: refusal keeps an existing out file" "bytes differ"; fi
rm -f "$tmp/token" "$tmp/token.orig"

# --strict in any position, each against a refusing response
REFUSE=$(sbody '{"contents":"write"}' "$R_OK")
rm -f "$tmp/token"
run 201 "$REFUSE" --strict --client-id Iv23liTestClient0001 --installation-id 678 --key "$tmp/key.pem" \
  --repos claude-workbench,devcontainers --perms contents=write,pull_requests=write --out "$tmp/token"
assert_eq "strict: flag first exits 1" 1 "$rc"
assert_strict_ran "strict: flag first ran through the jq wrapper"
run 201 "$REFUSE" --client-id Iv23liTestClient0001 --installation-id 678 --key "$tmp/key.pem" --strict \
  --repos claude-workbench,devcontainers --perms contents=write,pull_requests=write --out "$tmp/token"
assert_eq "strict: flag in the middle exits 1" 1 "$rc"
assert_strict_ran "strict: flag in the middle ran through the jq wrapper"
# shellcheck disable=SC2046
run 201 "$REFUSE" $(good_args) --strict
assert_eq "strict: flag last exits 1" 1 "$rc"
assert_strict_ran "strict: flag last ran through the jq wrapper"
[ ! -e "$tmp/token" ] && ok || bad "strict: positioned flags leave no out file" "$tmp/token exists"

# without --strict an extra permission is still accepted, as before
rm -f "$tmp/token"
# shellcheck disable=SC2046
run 201 "$(sbody '{"contents":"write","pull_requests":"write","issues":"write"}' "$R_OK")" $(good_args)
assert_eq "no --strict: an extra permission still exits 0" 0 "$rc"
assert_eq "no --strict: token written" "$TOKEN" "$(sed -n 1p "$tmp/token")"
rm -f "$tmp/token"

# --- usage errors exit 2 and never call curl -------------------------------------------------
usage_case() { # desc <args...>
  desc=$1; shift
  run 201 "$GOOD_BODY" "$@"
  assert_eq "$desc exits 2" 2 "$rc"
  [ ! -e "$tmp/calls" ] && ok || bad "$desc never calls curl" "curl was called"
}

base="--client-id Iv23liTestClient0001 --installation-id 678 --key $tmp/key.pem --out $tmp/token"
# shellcheck disable=SC2086
{
  usage_case "no repos"            $base --perms contents=write
  usage_case "no perms"            $base --repos a
  usage_case "empty repos"         $base --repos "" --perms contents=write
  usage_case "repo with a slash"   $base --repos "o/r" --perms contents=write
  usage_case "repo with a quote"   $base --repos 'a"b' --perms contents=write
  usage_case "perm without level"  $base --repos a --perms contents
  usage_case "perm bad level"      $base --repos a --perms contents=owner
  usage_case "perm bad name"       $base --repos a --perms 'Contents=write'
  usage_case "client id with a symbol" --client-id "Iv23li-x" --installation-id 678 --key "$tmp/key.pem" --repos a --perms contents=read --out "$tmp/token"
  usage_case "client id with a non-ASCII letter" --client-id "Iv23liCaf$(printf '\303\251')" --installation-id 678 --key "$tmp/key.pem" --repos a --perms contents=read --out "$tmp/token"
  usage_case "non-numeric install" --client-id 1 --installation-id x --key "$tmp/key.pem" --repos a --perms contents=read --out "$tmp/token"
  usage_case "missing key file"    --client-id 1 --installation-id 2 --key "$tmp/nope.pem" --repos a --perms contents=read --out "$tmp/token"
  usage_case "--api-url is gone"   $base --repos a --perms contents=read --api-url https://attacker.example
  usage_case "unknown flag"        $base --repos a --perms contents=read --bogus x
  usage_case "dangling flag"       $base --repos a --perms contents=read --out
  usage_case "duplicate perm"      $base --repos a --perms contents=read,contents=admin
  usage_case "out is a directory"  --client-id 1 --installation-id 2 --key "$tmp/key.pem" --repos a --perms contents=read --out "$tmp"
  usage_case "--out then --strict"  --client-id 1 --installation-id 2 --key "$tmp/key.pem" --repos a --perms contents=read --out --strict
  usage_case "--repos then --strict" --client-id 1 --installation-id 2 --key "$tmp/key.pem" --perms contents=read --out "$tmp/token" --repos --strict
  usage_case "strict, then a flag missing its value" --strict $base --repos a --perms
  usage_case "value beginning with a dash" $base --repos a --perms -contents=read
  usage_case "out dir is missing" --client-id 1 --installation-id 2 --key "$tmp/key.pem" --repos a --perms contents=read --out "$tmp/nodir/token"
}

if [ "$fail" -eq 0 ]; then
  echo "identity-mint: $pass_count assertions passed"
else
  echo "identity-mint: FAILED" >&2
  exit 1
fi
