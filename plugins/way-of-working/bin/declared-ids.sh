#!/bin/sh
# Which user ids does a project.yml's `identities` map declare? One implementation of the config read that
# spec-find.sh, spec-comment.sh, spec-answer.sh, spec-issue.sh and spec-post.sh each carried a copy of (#1079),
# so a tightening is made once and the readers cannot disagree.
#
# Usage: declared-ids.sh <project.yml>
#
#   <project.yml>  the DEFAULT branch's committed copy (the callers' $DEF_YML_FILE), never the working
#                  tree's, which a branch under review can edit
#
# Read with yq, aliases expanded: `identities` (a map), `identities.maintainer` (a sequence of at least one
# entry, each a map with an !!int `id` above 0 and a string `login`) and `identities.dev_app`,
# `identities.reviewer_app` and `identities.loop_app` (each null or missing, or a map of the same shape whose
# id is canonical decimal -- digits, no leading zero, no sign or prefix, so `+2001`, `0x7D1` and `02001` are
# refused (#707) -- and is not on the maintainer list (#708, #759)). A maintainer id is held to the same
# canonical-decimal rule (#1096): yq tags `0x3E9`, `1_001` and `01001` as !!int and prints them as written, and
# the readers compare the list as text with GitHub's decimal ids, so such an entry would match nobody.
#
# Each of the five callers holds the output line below to its shape with its own copy of the same parser (the
# newline case, the `ok ` prefix, the three-field pattern, the dev-id gate), so a change to the output line is a
# five-way edit (#1105); that is accepted. tests/declared-ids.test.sh checks that the five caller suites feed the
# same malformed-line stubs (#1106).
#
# Prints exactly one line to stdout and exits 0:
#   ok <maintainer-ids> <dev-app-id>  -- the maintainer ids comma-joined in list order, and the dev App's id,
#                                        or `-` when `identities.dev_app` is null or missing
#   unreadable                        -- any value above failed its shape
#
# Exits 2, printing nothing to stdout, for a wrong argument count or a <project.yml> that is missing or not
# YAML. It makes no `gh` call and reads no other file.
#
# Permitted toolset: POSIX sh, yq (mikefarah v4) and awk. Runs under LC_ALL=C.
set -eu
LC_ALL=C
export LC_ALL

[ "$#" -eq 1 ] || { echo "usage: declared-ids.sh <project.yml>" >&2; exit 2; }
yml="$1"
if [ ! -f "$yml" ] || ! yq -o=yaml '.' "$yml" >/dev/null 2>&1; then
  echo "declared-ids.sh: unreadable project.yml" >&2
  exit 2
fi

out() {
  printf '%s\n' "$*"
  exit 0
}

[ "$(yq -r 'explode(.) | .identities | tag' "$yml" 2>/dev/null)" = '!!map' ] || out unreadable
m_total="$(yq -r 'explode(.) | .identities.maintainer | select(tag == "!!seq") | length' "$yml" 2>/dev/null)" || out unreadable
maint_ids="$(yq -r 'explode(.) | .identities.maintainer | select(tag == "!!seq") | [.[] | select(tag == "!!map" and ((.id | tag) == "!!int") and .id > 0 and ((.login | tag) == "!!str")) | .id] | join(",")' "$yml" 2>/dev/null)" || out unreadable
[ -n "$maint_ids" ] || out unreadable
m_good="$(printf '%s' "$maint_ids" | awk -F, '{print NF}')"
[ "$m_good" = "$m_total" ] || out unreadable
case ",$maint_ids," in *[!0-9,]* | *,0*) out unreadable ;; esac

# The dev App feeds the callers' author filter and role check; the reviewer and loop Apps are read for the
# collision check only. Each key is checked the same way.
dev_id=-
for app_key in dev_app reviewer_app loop_app; do
  app_tag="$(APP_KEY="$app_key" yq -r 'explode(.) | .identities[strenv(APP_KEY)] | tag' "$yml" 2>/dev/null)" || out unreadable
  case "$app_tag" in
    '!!null') : ;;
    '!!map')
      app_id="$(APP_KEY="$app_key" yq -r 'explode(.) | .identities[strenv(APP_KEY)] | select(tag == "!!map" and ((.id | tag) == "!!int") and .id > 0 and ((.login | tag) == "!!str")) | .id' "$yml" 2>/dev/null)" || out unreadable
      case "$app_id" in '' | 0* | *[!0-9]*) out unreadable ;; esac
      case ",$maint_ids," in *",$app_id,"*) out unreadable ;; esac
      if [ "$app_key" = dev_app ]; then dev_id="$app_id"; fi
      ;;
    *) out unreadable ;;
  esac
done
out "ok $maint_ids $dev_id"
