# Shared helpers for wow-admin, wow-review, wow-review-poll and wow-review-mint (WB-D24, issues #374, #635). Sourced, not run.
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
#   dev.pem, broker.json   broker.ps1 config: the dev App's unencrypted key (name by convention), and
#                          {"repos": [...]}, the repos it keeps a dev token for. Also broker.lock,
#                          broker.log and staging/<repo>/, none mounted anywhere.
#   review-tokens/<repo>/  reviewer-token, in the same format. Never mounted into a dev
#                          container: the reviewer is a different identity from the PR's author.
#   bin/                   the installed copies of these scripts (install-host-tools.ps1, from
#                          committed code on origin/main, with a MANIFEST); the broker task and the
#                          human commands run from here, never from a checkout a container can write.
#   bin/review/            the review image's build context (#634), exported with the scripts: the
#                          Dockerfile plus exactly the files it copies.
#   review-sessions/<id>/  only session-token, mounted read-only into a review container (the one directory
#                          the broker sweeps).
#   review-host/<id>/      wow-review's working files, never mounted: the project.yml copy, the outbox
#                          copies, every kept copy of the session token, and its read-token, post-token
#                          and filing-token. Removed by the launcher's trap.
#   review-state/          wow-review's lock and its dedupe ledger (<owner>/<name>/<N>/<sha>/).
#   review-poll.json       {"repos": ["owner/name", ...]}, the repos wow-review-poll polls (the maintainer writes it).
#   review-poll.log        wow-review-poll's decision log, rotated to review-poll.log.1 past 1 MiB.
#   review-state/.poll-lock  wow-review-poll's own lock directory, separate from wow-review's .lock.
#   review-host/poll-<id>/ wow-review-poll's working files and its session token, never mounted. Removed by its trap.
#   claude-credential      the Claude setup-token credential, one line; read only by wow-review and
#                          written only to the injector sidecar's stdin.
#   review-logs/           review run logs; may hold secrets, swept by the broker by age.
# Invariant: no path under $WOW_HOME is container-writable. tokens/<repo>/ is mounted only into a
# dev container, and review-sessions/<id>/ only into a review container, each read-only.
# claude-credential is never mounted into any container and reaches only the injector's stdin.
# What these commands write: tokens/ and review-tokens/ directories, a per-repo .lock directory
# and a transient .unlock.* directory (both removed on exit), admin-token (replaced or removed),
# reviewer-token (default review-tokens/<repo>/, or the path --out names), the session and filing
# tokens (wow-review-mint --read / --file, written only to the path --out names), and the .mint.* file
# mint.sh stages beside any token it writes. wow-review (the launcher) also writes its own review-sessions/,
# review-host/, review-state/ and review-logs/ entries. wow-review-poll writes review-poll.log (and .1),
# review-state/.poll-lock and review-host/poll-<id>/. Nothing else under $WOW_HOME is modified.
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
