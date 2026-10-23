#!/bin/sh
# Fixture tests for scripts/pr-title-check.sh (#839).
#
# The check must never pass a title it could not judge: an unreadable area list fails
# closed, and a malformed title fails rather than slipping past the scope test. Each
# fixture is a throwaway tree holding at most a CLAUDE.md; the script is run with that tree
# as cwd, which is how CI runs it. The last two cases run against the real CLAUDE.md, so a
# reformat of its `## Areas` section that the parser no longer reads fails here.
#
# Permitted toolset: POSIX sh. No jq, no yq, no python.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/pr-title-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail=0

# assert DESC EXPECTED_STATUS FRAGMENT DIR ARGS...  (FRAGMENT empty: status only)
assert() {
  desc="$1"; expected="$2"; frag="$3"; dir="$4"; shift 4
  actual=0
  out="$( cd "$dir" && bash "$script" "$@" 2>&1 )" || actual=$?
  if [ "$expected" != "$actual" ]; then
    echo "FAIL - $desc: expected exit [$expected], got [$actual]" >&2
    fail=1
  elif [ -n "$frag" ] && ! printf '%s' "$out" | grep -qF -- "$frag"; then
    echo "FAIL - $desc: output lacks [$frag]: $out" >&2
    fail=1
  else
    echo "ok - $desc"
  fi
}

fixture="$tmp/fixture"
mkdir -p "$fixture"
cat >"$fixture/CLAUDE.md" <<'MD'
# fixture

## Areas

A commit scope is one of these.

- `alpha` — `a/`, also `zeta`
  - `nested` — an indented bullet, not top-level
- `beta` — `b/`

Prose after the list.

## Other

- `gamma` — not an area
MD

# --- the declared list ------------------------------------------------------
assert "declared scope passes" 0 "" "$fixture" 'x(alpha): s'
assert "scope past the next heading fails" 1 "gamma" "$fixture" 'x(gamma): s'
assert "undeclared scope fails and names every area" 1 "alpha beta" "$fixture" 'x(other): s'
assert "undeclared scope is named" 1 "'other'" "$fixture" 'x(other): s'
assert "second span on a bullet is not an area" 1 "not a declared area" "$fixture" 'x(zeta): s'
assert "nested bullet is not an area" 1 "not a declared area" "$fixture" 'x(nested): s'
assert "prefix of an area fails" 1 "not a declared area" "$fixture" 'x(alph): s'
assert "area plus suffix fails" 1 "not a declared area" "$fixture" 'x(alphabeta): s'

# --- scope optional, breaking mark, Dependabot ------------------------------
assert "no scope passes" 0 "" "$fixture" 'x: s'
assert "breaking mark without scope passes" 0 "" "$fixture" 'x!: s'
assert "breaking mark with scope passes" 0 "" "$fixture" 'x(alpha)!: s'
assert "ci(deps) passes" 0 "" "$fixture" 'ci(deps): s'
assert "other type with deps fails" 1 "'deps'" "$fixture" 'docs(deps): s'

# --- malformed --------------------------------------------------------------
M="malformed title"
assert "malformed: no colon" 1 "$M" "$fixture" 'x alpha'
assert "malformed: empty scope" 1 "$M" "$fixture" 'x(): s'
assert "malformed: space in scope" 1 "$M" "$fixture" 'x(alpha beta): s'
assert "malformed: LF in subject" 1 "$M" "$fixture" "$(printf 'x(alpha): a\nb')"
assert "malformed: CR in subject" 1 "$M" "$fixture" "$(printf 'x(alpha): a\rb')"
assert "malformed: no space after colon" 1 "$M" "$fixture" 'x(alpha):s'
assert "malformed: uppercase type" 1 "$M" "$fixture" 'X(alpha): s'
assert "malformed: empty subject" 1 "$M" "$fixture" 'x(alpha): '

# --- fail closed ------------------------------------------------------------
none="$tmp/none"; mkdir -p "$none"
nohead="$tmp/nohead"; mkdir -p "$nohead"
printf '# t\n\n- `alpha` — a\n' >"$nohead/CLAUDE.md"
nobullet="$tmp/nobullet"; mkdir -p "$nobullet"
printf '# t\n\n## Areas\n\nprose only\n\n## Next\n' >"$nobullet/CLAUDE.md"
for d in none nohead nobullet; do
  assert "$d: no scope fails closed" 1 "area list" "$tmp/$d" 'x: s'
  assert "$d: scope fails closed" 1 "area list" "$tmp/$d" 'x(alpha): s'
done

# --- an area outside the scope grammar fails closed ------------------------
# Each bad name carries the token zqxw, which no message of the script contains, so the
# no-echo check greps for it and survives a rewording. The e-acute name pins that a
# non-ASCII area fails closed.
eacute="$(printf '\303\251')"
for shape_name in zqxwA zqxw_a zqxw.a zqxw/a "zqxw a" "zqxw$eacute"; do
  d="$tmp/bad-$(printf '%s' "$shape_name" | od -An -tx1 | tr -d ' \n')"
  mkdir -p "$d"
  printf '# t\n\n## Areas\n\n- `alpha` — a\n- `%s` — b\n' "$shape_name" >"$d/CLAUDE.md"
  assert "bad area [$shape_name]: no scope fails closed" 1 "not a valid scope" "$d" 'x: s'
  assert "bad area [$shape_name]: scope fails closed" 1 "not a valid scope" "$d" 'x(alpha): s'
  out="$( cd "$d" && bash "$script" 'x(alpha): s' 2>&1 )" || true
  if printf '%s' "$out" | grep -qF -- zqxw; then
    echo "FAIL - bad area [$shape_name]: output echoes the area: $out" >&2
    fail=1
  else
    echo "ok - bad area [$shape_name]: output does not echo the area"
  fi
done

# --- subject bytes ----------------------------------------------------------
assert "non-ASCII subject passes" 0 "" "$fixture" 'x(alpha): a — b'
assert "malformed: DEL in subject" 1 "$M" "$fixture" "$(printf 'x(alpha): a\177b')"

# --- usage ------------------------------------------------------------------
assert "usage: no argument" 2 "usage" "$fixture"
assert "usage: two arguments" 2 "usage" "$fixture" 'x: s' 'y: t'

# --- control against the real file ------------------------------------------
assert "real CLAUDE.md: declared area passes" 0 "" "$root_dir" 'docs(ci): s'
assert "real CLAUDE.md: undeclared scope fails" 1 "not a declared area" "$root_dir" 'docs(scripts): s'

exit "$fail"
