# Shared helpers for wow-admin and wow-review-mint (WB-D24, issue #374). Sourced, not run.
#
# Host layout, under $WOW_HOME (default ~/.config/glunk-identity):
#   apps.json              {"admin": {app_id, client_id, installation_id, bot_user_id, key},
#                           "review": {...}, ...}; entries are keyed by role, the suffix after the last
#                           dash of the App's name (<org>-admin, <org>-review, <org>-dev), so any
#                           org's config reads the same; "key" is a PEM filename in this directory
#   admin.enc.pem          the admin App's private key, passphrase-encrypted (name by convention)
#   review.pem             the reviewer App's private key, unencrypted (minted on request)
#   tokens/<repo>/         the only directory of secrets a repo's container mounts, read-only: admin-token
#                          (wow-admin) and dev-token (broker.ps1), each the token then its
#                          expires_at. Admin and dev credentials only.
#   dev.pem, broker.json   broker.ps1's config: the dev App's unencrypted key (name by convention), and {"repos": [...]},
#                          the repos it keeps a dev token for. It also uses staging/<repo>/, a
#                          broker.lock and broker.log, none mounted anywhere, and serves
#                          req/<repo>/reviewer-token requests: req/<repo>/ is the one other
#                          directory a container may mount, writable, and holds no secret.
#   review-tokens/<repo>/  reviewer-token, in the same format. Never mounted into a dev
#                          container: the reviewer is a different identity from the PR's author.
# What these commands write: tokens/ and review-tokens/ directories, a per-repo .lock directory
# and a transient .unlock.* directory (both removed on exit), admin-token (replaced or removed),
# reviewer-token (default review-tokens/<repo>/, or the path --out names), and the .mint.* file
# mint.sh stages beside any token it writes. Nothing else under $WOW_HOME is modified.
#
# The caller sets $prog before sourcing. Toolset: POSIX sh, jq, plus what mint.sh needs.

LC_ALL=C; export LC_ALL

wow_home=${WOW_HOME:-${HOME:-}/.config/glunk-identity}

die() { echo "$prog: $1" >&2; exit "${2:-1}"; }

# app_get <app> <field>: a bare value (letters, digits, . _ -) from apps.json, or empty.
# <app> and <field> are fixed words from the caller, never user input.
app_get() {
  [ -r "$wow_home/apps.json" ] || return 0
  v=$(jq -r --arg a "$1" --arg f "$2" '.[$a][$f] // empty' "$wow_home/apps.json" 2>/dev/null | tr -d '\r') || return 0
  case "$v" in *[!A-Za-z0-9._-]*) return 0 ;; esac
  printf '%s\n' "$v"
}

# app_key <app>: the App's PEM path. Its "key" must be a bare filename in $wow_home.
app_key() {
  k=$(app_get "$1" key)
  case "$k" in ''|.|..|-*) return 0 ;; esac
  printf '%s\n' "$wow_home/$k"
}

# The repo becomes a directory name and a --repos element: plain characters only, no leading
# dash or dot-only name.
check_repo() {
  case "$1" in
    ''|.|..|-*|*[!A-Za-z0-9._-]*) die "repository must be a bare name of letters, digits, . _ -" 2 ;;
  esac
}

# token_dir <tokens|review-tokens> <repo>: create (private) and print that repo's token directory.
token_dir() {
  d="$wow_home/$1/$2"
  (umask 077 && mkdir -p -- "$d") || die "cannot create $d"
  printf '%s\n' "$d"
}
