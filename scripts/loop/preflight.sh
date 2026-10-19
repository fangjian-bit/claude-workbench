#!/usr/bin/env bash
# Driver preflight evaluators: pure checks over captured JSON, so each can be fixture-tested.
#
# Issue #320, plan v9 § 7.3 ("The driver's preflight") and decision 9 of
# docs/proposals/orchestrator-m2-decisions.md. Nothing here runs docker or gh: the driver
# captures the JSON and hands it over as files, and this script only judges it. That is what
# makes the live run (M2b) a separate piece of work from the rules.
#
# Usage:
#   preflight.sh container --session FILE --network FILE --expect-network NAME --proxy FILE...
#       FILE for --session   `docker inspect <session container>` (created, not started, is fine)
#       FILE for --network   `docker network inspect <the internal network>`
#       FILE for --proxy     `docker inspect <a proxy container>`; repeatable, at least one
#
#   preflight.sh github-dispatch --rules FILE --identities FILE \
#       --issue FILE --issue-number N (--spec-comment FILE --spec-comment-id N | --no-spec-comment) \
#       [--spec-reactions FILE]
#       Run at dispatch, with the maintainer's view (a pre-cutover author check reads
#       author_association, which is viewer-relative; the rules read needs no admin).
#       FILE for --rules     `GET /repos/R/rules/branches/{pr_base}` (the rules that apply)
#       --issue/--spec-comment  the task issue and the spec comment, as fetched: under a map the one
#                            `spec-find.sh find` prints `found` for, under null the anchored one
#       FILE for --identities  the `identities` value of .ai/project.yml on the DEFAULT branch,
#                            as one JSON document: null before the repo cuts over, a map
#                            after. Produce it with `yq -o=json 'select(has("identities")) |
#                            .identities'`, NOT a bare `.identities`: an ABSENT key is the
#                            unanswered question, and that form prints nothing for it (an
#                            empty file, unreadable) where the bare form prints `null` and
#                            would read as "not cut over". Required: a driver that does not
#                            say which model it trusts by is not asked to guess one.
#       FILE for --spec-reactions  the spec comment's reactions, one per line as `user.id`,
#                            `content`, `created_at`, tab-separated (the projection spec-reaction.sh
#                            reads), captured to a file with the fetch's exit status checked:
#                            gh api "repos/R/issues/comments/<id>/reactions" --paginate \
#                              --jq '.[] | [(.user.id|tostring), .content, .created_at] | @tsv'
#                            A file from a failed fetch is never passed. Optional; needed under a map
#                            whenever a spec comment is supplied, whoever wrote it. Excluded with
#                            --no-spec-comment.
#
#   preflight.sh github-push --installation FILE --repo OWNER/NAME --rules FILE --rulesets FILE \
#       --app FILE --loop-identity LOGIN
#       Run after the token is minted, with the token's own view.
#       FILE for --installation  `GET /installation/repositories`
#       FILE for --rules         `GET /repos/R/rules/branches/{pr_base}`, fetched with the minted
#                                token; each rule must carry its ruleset_id
#       FILE for --rulesets      a JSON array of `GET /repos/R/rulesets/{id}` for every ruleset id
#                                in --rules, fetched with the minted token (that is what makes
#                                current_user_can_bypass describe the App)
#       FILE for --app           `GET /app` (the slug; the bot login is slug + "[bot]")
#       --loop-identity          orchestration.loop_identity; "-" for null, which refuses
#
# Output, on stdout, one line per finding:
#   pass                          exit 0, only when nothing was found
#   refused <rule>: <detail>      exit 3, the input says the check fails
#   unreadable <rule>: <detail>   exit 3, the input cannot say (missing field, a file that does
#                                 not parse, a truncated list); unknown is never a pass
#   (a usage fault is a message on stderr and exit 2)
#
# Rules:
#   container       User (and its group) non-root; ReadonlyRootfs; CapDrop has ALL and CapAdd is
#                   empty; not privileged; no host PID/IPC/UTS/user namespace, no Devices, no
#                   unconfined SecurityOpt; NetworkMode is --expect-network and the session is
#                   attached to no other network; every mount is a named volume or a tmpfs (a
#                   bind of any host path is refused, as launch.sh does) and none names /mnt,
#                   Docker Desktop's mount roots, a drive letter or a docker socket or pipe, and
#                   HostConfig.Binds is empty; the network is that name, Internal, IPv6 off,
#                   gateway_mode_ipv4=isolated and has no IPAM Gateway on any entry; every
#                   --proxy is running and attached to it. A gateway address is never derived
#                   from a subnet: an isolated network has none, and the subnet's .1 belongs to
#                   a container.
#   approval-rule   the rules on pr_base include the approval gate (WB-D24, replacing decision 9's
#                   `update` rule): across the `pull_request` rules that apply, at least one
#                   has required_approving_review_count >= 1, at least one has
#                   require_code_owner_review true and at least one has
#                   require_last_push_approval true (GitHub combines overlapping rulesets by
#                   taking the strictest of each). Having no `pull_request` rule is refused; a rule
#                   whose parameters lack one of the three fields, or hold the wrong type for
#                   it, is unreadable. An `update` rule is neither required nor enough.
#   author          the task issue is --issue-number (and not a pull request), and its author,
#                   and the spec comment's (id --spec-comment-id, issue_url ending
#                   /issues/<number>), are trusted. With --identities null that is
#                   author_association OWNER, MEMBER or COLLABORATOR; with a map it is the
#                   author's user.login and user.id matching an identities.maintainer entry
#                   (WB-D24, #382: association is viewer-relative and reads CONTRIBUTOR for the
#                   maintainer through an App token). The id decides; a login is compared
#                   case-folded and only alongside its id; an id declared twice, or under
#                   another login, is unreadable, and a malformed entry matches nothing (here a
#                   non-positive or non-numeric id; unlike gh-identity.sh, which wants a YAML
#                   !!int, a declared `1001.0` reads as 1001 to jq's numeric ==, and a
#                   fractional id can never equal GitHub's integer author id). For a spec
#                   comment the review and loop Apps are not maintainers and stay refused (see
#                   below). For the TASK ISSUE only (WB-D32, #664) the declared dev_app and
#                   reviewer_app also pass, with no reaction consulted: the dispatched work is
#                   built from the spec comment alone, which needs a declared maintainer's
#                   reaction, so the issue's author does not approve its content. The loop_app and
#                   an undeclared author are still refused. This jq is the one reader that does not
#                   call `gh-identity.sh task-author`; it mirrors that verb's table (trusted and
#                   agent pass, loop_app and undeclared are refused) and is held to it by fixtures.
#                   One rule, for the spec comment only (#666, #682, matching #660 and WB-D30): under a
#                   map a comment by the declared dev_app or by a declared maintainer passes when a declared
#                   maintainer reacted to it (+1, heart, hooray, rocket) strictly after its last edit
#                   (`updated_at`), the author's own reaction included. The rule is
#                   spec-reaction.sh, called, not restated. As in spec-comment.sh, one malformed
#                   maintainer entry (anything but a string login and an id whose exact JSON value is
#                   an integer in 1..2^53-1: `1001.0` and a literal that only rounds to an integer,
#                   as 2001.0000000000000001 does, are malformed; a JSON-side check cannot see
#                   the YAML tag, so an exponent spelling of an exact integer such as `3.001e3`
#                   is accepted here, where spec-comment.sh sees a !!float; the literal-exact part
#                   needs jq 1.7 or later, which keeps number literals, and on older jq the
#                   collision cases still end unreadable) means
#                   no spec comment under a map is approved, and no declared App is an approver (#708):
#                   as in spec-find.sh, the first key, in the order dev_app, reviewer_app, loop_app,
#                   that fails either way (neither null nor a well-formed entry: unreadable; id on the
#                   maintainer list: refused) decides a spec comment by a maintainer or by the dev App; that is
#                   the only line, and no reaction is judged. A malformed maintainer list is reported
#                   first. A dev-App-authored comment whose own id is on the maintainer list ends
#                   earlier, at the duplicate-id check (declared more than once), as unreadable. The preflight
#                   cannot see how an integer App id is written (`+2001`, `0x7D1`, `02001`): `yq -o=json` (v4.54.1, measured)
#                   normalizes it and the comparison is numeric, so spelling cannot hide a collision
#                   here. Dropping the maintainer-only guard makes the dev_app U line reachable for a
#                   dev-App author whose dev_app id is written as a non-exact number equal to its own
#                   (for example 2001.0), deliberately. Under a map, a spec comment with no --spec-reactions, or with no
#                   well-formed `updated_at`, is unreadable, and --no-spec-comment is refused (the
#                   issue body is never the spec, #496). The task issue's author is a
#                   maintainer or, per WB-D32, the dev or reviewer App, and needs no reaction; the
#                   review and loop Apps stay refused as spec authors. A pass covers only the text in the
#                   --spec-comment file: the driver builds the task prompt from that same captured
#                   file, never from a second fetch, and any re-read means re-running this
#                   preflight on a new capture after a new reactions read.
#   installation    /installation/repositories lists exactly --repo (case-folded) and its
#                   total_count equals the list it shows.
#   can-bypass      at least one ruleset applies to pr_base and every one reads
#                   current_user_can_bypass: never. This is the only bypass read: it is the App's
#                   own view, so it needs no admin (bypass_actors is hidden from a non-admin).
#                   UNMEASURED: the field read `never` for an App that is not a bypass actor
#                   (GITHUB-APP-EVALUATION.md T2d); it has not been observed for an App that is
#                   one, so that it then reads something other than `never` is an assumption.
#   identity        the App's slug + "[bot]" equals --loop-identity, case-folded.
#
# The driver's captures: a paginated read must be one complete document. `gh api --paginate`
# concatenates pages into several top-level values, which this script reads as unreadable, and a
# first page captured alone is indistinguishable from the whole list (only
# /installation/repositories carries a total_count to check). Use `--paginate --slurp` and
# flatten, or `per_page=100`, and refuse a response of 100.
# The reactions file is the one non-JSON capture. It is line-oriented, so concatenated pages are
# fine, and a missing page can only drop an approval, which fails closed. This script cannot see
# capture order: the driver fetches the reactions BEFORE the comment, by the same comment id, so
# an edit after the reactions read moves `updated_at` past every captured reaction and the comment
# is refused.
# GET /app takes the App's JWT, not the installation token; the other github-push reads take the
# minted token.
#
# Not checked here: that the spec comment carries the `spec-task:` marker, and that it is the comment
# spec-find.sh selects (the driver is expected to take the id from its `found` line); that --spec-reactions was fetched for --spec-comment-id (the TSV carries no comment
# id), and anything about spec-reaction.sh beyond trusting the checkout this script runs from; a non-root name that /etc/passwd or /etc/group maps to id 0 inside the image
# (inspect cannot show it); which ruleset the approval rule comes from (the task asks only that
# the rules on pr_base carry it); that stale approvals are dismissed (dismiss_stale_reviews_on_push:
# #388 names count, code owner and last push only; adding it is a small, local change); that CODEOWNERS
# on pr_base exists and covers the changed paths (require_code_owner_review does nothing without it,
# leaving only the approval count); that every rule /rules/branches returns is from an active ruleset
# (it carries no enforcement field; the docs say evaluate- or disabled-mode rulesets are not returned); that the
# approval rule also holds on the push-time --rules capture; a named volume backed by a host path
# (`--opt o=bind`, which needs `docker volume inspect`); how many containers sit on the network, and
# that the credential is absent from `docker inspect` (launch.sh checks both and is not moved onto
# this script).
set -euo pipefail

die() { echo "preflight.sh: $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || die "jq not on PATH"

# Findings arrive as "R rule: detail" / "U rule: detail" lines from jq. Print them, sanitised
# (details quote input-chosen strings), and exit 3 unless there were none.
report() {
  local out=$1 line
  if [ -z "$out" ]; then echo pass; exit 0; fi
  while IFS= read -r line; do
    case "$line" in
      "R "*) printf 'refused %s\n' "$(printf '%s' "${line#R }" | tr '\000-\037\177' '?' | cut -c1-300)" ;;
      "U "*) printf 'unreadable %s\n' "$(printf '%s' "${line#U }" | tr '\000-\037\177' '?' | cut -c1-300)" ;;
      *)     printf 'unreadable preflight: evaluator emitted an unclassified line\n' ;;
    esac
  done <<<"$out"
  exit 3
}

# A file must hold exactly one JSON value.
one_doc() { # file -> 0 when it parses to exactly one value
  [ -f "$1" ] && [ -r "$1" ] && [ "$(jq -c . -- "$1" 2>/dev/null | wc -l)" = 1 ]
}

[ $# -ge 1 ] || die "usage: preflight.sh container|github-dispatch|github-push ... (see the header)"
mode=$1; shift

session= network= expect_net= rules= rulesets= app_id= issue= issue_no= comment= comment_id=
no_comment= install= repo= appf= loopid= identf= reactions= sr=
proxies=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-spec-comment) no_comment=1; shift; continue ;;
  esac
  [ $# -ge 2 ] || die "$1 needs a value"
  case "$1" in
    --session)         session=$2 ;;
    --network)         network=$2 ;;
    --expect-network)  expect_net=$2 ;;
    --proxy)           proxies+=("$2") ;;
    --rules)           rules=$2 ;;
    --rulesets)        rulesets=$2 ;;
    --app-id)          app_id=$2 ;;
    --issue)           issue=$2 ;;
    --issue-number)    issue_no=$2 ;;
    --spec-comment)    comment=$2 ;;
    --spec-comment-id) comment_id=$2 ;;
    --installation)    install=$2 ;;
    --repo)            repo=$2 ;;
    --app)             appf=$2 ;;
    --loop-identity)   loopid=$2 ;;
    --identities)      identf=$2 ;;
    --spec-reactions)  reactions=$2 ;;
    *)               die "unknown option: $1" ;;
  esac
  shift 2
done

need() { local v n; for n in "$@"; do v=${!n}; [ -n "$v" ] || die "--${n//_/-} is required"; done; }
digits() { case "$2" in ''|*[!0-9]*|0*) die "--$1 must be a positive decimal number" ;; esac; }

# Every named file must parse before any rule runs: a read that failed upstream arrives here
# as an empty or truncated file, and that is "unreadable", not "nothing found".
unreadable_files=
check_files() {
  local f
  for f in "$@"; do
    if ! one_doc "$f"; then
      unreadable_files="${unreadable_files}U input: $(printf '%s' "${f##*/}" | tr '\000-\037\177' '?') is missing, empty or not exactly one JSON value
"
    fi
  done
}

case "$mode" in
  container)
    need session network expect_net
    [ ${#proxies[@]} -gt 0 ] || die "at least one --proxy is required"
    case "$expect_net" in *[!A-Za-z0-9._-]*) die "--expect-network has characters outside [A-Za-z0-9._-]" ;; esac
    check_files "$session" "$network" "${proxies[@]}"
    [ -z "$unreadable_files" ] || report "${unreadable_files%$'\n'}"
    out=$(jq -n -r --slurpfile s "$session" --slurpfile n "$network" --arg net "$expect_net" '
      # A rule is unreadable when its field is absent, refused when present and wrong.
      def need(rule; v; ok; msg):
        if v == null then "U \(rule): field missing"
        elif (try (v | ok) catch false) then empty
        else "R \(rule): \(msg)" end;
      def bad_src: test("^/mnt(/|$)|^/host_mnt|^/run/desktop/mnt|^[A-Za-z]:|^//./pipe|docker\\.sock|docker_engine"; "i");
      # Docker parses ids with ParseInt, which takes a sign: "+0" and "-0" are root.
      def rootish: . == "root" or test("^[+-]?0+$");
      [inputs] as $p | ($s[0]) as $S | ($n[0]) as $N |
      if ($S | type) != "array" or ($S | length) != 1 or ($S[0] | type) != "object" then "U container: session inspect is not a one-element array"
      elif ($N | type) != "array" or ($N | length) != 1 or ($N[0] | type) != "object" then "U network: network inspect is not a one-element array"
      elif ([$p[] | select(type != "array" or length != 1 or (.[0] | type) != "object")] | length) > 0 then "U proxy: a proxy inspect is not a one-element array"
      else
        $S[0] as $c | $N[0] as $nw |
        need("user"; $c.Config.User; type == "string" and (split(":") | (.[0] // "") != "" and all(.[]; rootish | not)); "User or its group is root, or User is empty"),
        need("readonly-rootfs"; $c.HostConfig.ReadonlyRootfs; . == true; "root filesystem is writable"),
        need("cap-drop"; $c.HostConfig.CapDrop; type == "array" and index("ALL") != null; "capabilities not all dropped"),
        # CapAdd is applied after CapDrop: a re-grant leaves the capability on. Docker reports none as null or [].
        ( if ($c.HostConfig | has("CapAdd")) and $c.HostConfig.CapAdd != null and $c.HostConfig.CapAdd != [] then "R cap-add: capabilities added back (\($c.HostConfig.CapAdd | tostring))" else empty end ),
        need("privileged"; $c.HostConfig.Privileged; . == false; "container is privileged"),
        # Host namespaces, devices and disabled confinement are privilege by another name.
        # A namespace shared with another container (`container:<proxy>`) is as bad as the host: the
        # credential-holding proxy runs as the same uid. Only the private forms are accepted.
        ( [ ({"PidMode":["","private"],"IpcMode":["","private","shareable","none"],"UsernsMode":[""],"UTSMode":[""],"CgroupnsMode":["","private"]} | to_entries[]) as $e
            | select($c.HostConfig[$e.key] != null and (($c.HostConfig[$e.key] | tostring) as $v | $e.value | index($v) == null))
            | "\($e.key)=\($c.HostConfig[$e.key])" ]
          + [ select(($c.HostConfig.Devices // []) != []) | "Devices" ]
          + [ select(($c.HostConfig.DeviceRequests // []) != []) | "DeviceRequests" ]
          + [ select(any(($c.HostConfig.GroupAdd // [])[]; tostring | rootish)) | "GroupAdd root" ]
          # SecurityOpt is an allow-list: launch.sh sets no-new-privileges and nothing else, so a
          # seccomp/apparmor/label option of any kind is a change to the confinement.
          + [ select((($c.HostConfig.SecurityOpt // []) | if type == "array" then any(.[]; tostring | test("^no-new-privileges([=:]true)?$") | not) else true end)) | "SecurityOpt other than no-new-privileges" ]
          + [ select((($c.HostConfig.Mounts // []) | if type == "array" then any(.[]; (.Type // "") != "volume" and (.Type // "") != "tmpfs") else true end)) | "HostConfig.Mounts has a bind or is not a list" ]
          | if length > 0 then "R privilege: \(join(", "))" else empty end ),
        need("network-mode"; $c.HostConfig.NetworkMode; . == $net; "NetworkMode is not \($net)"),
        # NetworkMode names one network; `docker network connect` can still add a second, routable one.
        need("session-networks"; $c.NetworkSettings.Networks; type == "object" and (keys == [$net]); "session is attached to networks other than \($net)"),
        need("mounts"; $c.Mounts; type == "array" and all(.[]; type == "object");
          "mounts are not a list of objects"),
        # Only a named local volume or a tmpfs is allowed: a bind of any host path (/var/run and / hold
        # the socket, /run reaches the drive) is refused outright, as launch.sh does. bad_src stays as a second net.
        ( if ($c.Mounts | type) == "array" then
            ([$c.Mounts[] | select(type == "object") | select(((.Type // "") != "volume" and (.Type // "") != "tmpfs") or ((.Source // "") | tostring | bad_src) or ((.Destination // "") | tostring | test("docker\\.sock|docker_engine"; "i"))) | "\(.Type // "?"): \(.Source // "?") -> \(.Destination // "?")"] | if length > 0 then "R mounts: forbidden mount \(join("; "))" else empty end)
          else empty end ),
        ( if ($c.HostConfig | has("Binds")) and $c.HostConfig.Binds != null and $c.HostConfig.Binds != [] then
            ( if ($c.HostConfig.Binds | type) != "array" then "U binds: Binds is not a list"
              else ([$c.HostConfig.Binds[] | tostring | select(test("^[A-Za-z0-9][A-Za-z0-9_.-]+:[^:]") | not)] | if length > 0 then "R binds: bind mounts are not allowed (\(join("; ")))" else empty end) end )
          else empty end ),
        need("network-name"; $nw.Name; . == $net; "network is not \($net)"),
        need("internal"; $nw.Internal; . == true; "network is not Internal"),
        need("ipv6"; $nw.EnableIPv6; . == false; "IPv6 is enabled on the network"),
        need("gateway-mode"; $nw.Options["com.docker.network.bridge.gateway_mode_ipv4"]; . == "isolated"; "gateway_mode_ipv4 is not isolated"),
        ( if ($nw.IPAM.Config | type) == "array" and ($nw.IPAM.Config | length) == 0 then "U ipam: IPAM.Config is empty" else empty end ),
        need("ipam"; $nw.IPAM.Config; type == "array" and all(.[]; type == "object");
          "IPAM.Config is not a list of entries"),
        ( if ($nw.IPAM.Config | type) == "array" then
            ([$nw.IPAM.Config[] | select(type == "object") | select((.Gateway // "") != "") | .Gateway] | if length > 0 then "R ipam: IPAM has a Gateway (\(join(", ")))" else empty end)
          else empty end ),
        ( $p[] | .[0] as $x | ($x.Name // "?") as $nm |
          need("proxy-running"; $x.State.Running; . == true; "proxy \($nm) is not running"),
          need("proxy-network"; $x.NetworkSettings.Networks; type == "object" and has($net); "proxy \($nm) is not on \($net)") )
      end | explode | map(if . < 32 or . == 127 then 63 else . end) | implode' "${proxies[@]}" 2>/dev/null | tr -d '\r') || report "U container: evaluator failed on the input"
    report "$out"
    ;;

  github-dispatch)
    need rules issue issue_no identf
    [ -z "$rulesets" ] && [ -z "$app_id" ] || die "github-dispatch takes no --rulesets or --app-id (the bypass read is github-push's, with the App's own token)"
    digits issue-number "$issue_no"
    if [ -n "$no_comment" ]; then
      [ -z "$comment" ] && [ -z "$comment_id" ] || die "--no-spec-comment excludes --spec-comment and --spec-comment-id"
    else
      need comment comment_id
      digits spec-comment-id "$comment_id"
    fi
    if [ -n "$reactions" ]; then
      [ -z "$no_comment" ] || die "--spec-reactions excludes --no-spec-comment"
      # The reaction rule is looked for beside this script's own checkout, never on PATH or in the
      # current directory: a broken checkout is not a finding about the input.
      case "${BASH_SOURCE[0]}" in
        */*) ;;
        *) die "cannot locate spec-reaction.sh: this script was run by a path with no directory" ;;
      esac
      sr="${BASH_SOURCE[0]%/*}/../../plugins/way-of-working/bin/spec-reaction.sh"
      [ -f "$sr" ] || die "spec-reaction.sh not found at $sr"
    fi
    files=("$rules" "$issue" "$identf"); [ -z "$comment" ] || files+=("$comment")
    check_files "${files[@]}"
    # The reactions file is TSV, the one capture that is not a JSON value, so it is checked on its
    # own; an empty file is valid and means no reactions.
    if [ -n "$reactions" ] && ! { [ -f "$reactions" ] && [ -r "$reactions" ]; }; then
      unreadable_files="${unreadable_files}U input: $(printf '%s' "${reactions##*/}" | tr '\000-\037\177' '?') is missing or not a readable file
"
    fi
    [ -z "$unreadable_files" ] || report "${unreadable_files%$'\n'}"
    cf=${comment:-/dev/null}
    out=$(jq -n -r --slurpfile r "$rules" --slurpfile i "$issue" --slurpfile ids "$identf" \
      --argjson inum "$issue_no" --arg haveC "${comment:+1}" --argjson cid "${comment_id:-0}" \
      --slurpfile c "$cf" '
      def trusted: . == "OWNER" or . == "MEMBER" or . == "COLLABORATOR";
      ($ids[0]) as $ID |
      def lc: ascii_downcase;
      # Every well-formed identities entry with its role; a malformed one matches nothing.
      def declared: [ ( ($ID.maintainer // []) | if type == "array" then .[] else empty end | {role: "maintainer", e: .} ),
                      ( ["dev_app", "reviewer_app", "loop_app"][] as $k | {role: $k, e: $ID[$k]} ) ]
        | map(select((.e | type) == "object" and ((.e.id | type) == "number") and .e.id > 0 and ((.e.login | type) == "string")));
      # An id spec-comment.sh accepts: an exact JSON integer in 1..2^53-1.
      def exactid: type == "number" and . > 0 and . == floor and . <= 9007199254740991
        and ((tojson) == (floor | tostring)) and ((floor | tostring) | test("^[1-9][0-9]*$"));
      def wellformed: type == "object" and ((.login | type) == "string") and ((.id | type) == "number") and (.id | exactid);
      # A spec comment under a map (#666, #682), by the declared dev_app or by a declared maintainer: the
      # all-or-nothing maintainer list of spec-comment.sh, the declared-App-id checks of spec-find.sh, then the
      # updated_at of the comment itself. The reaction itself is judged by the shell, through spec-reaction.sh;
      # this emits one "D <role> <updated_at> <ids>" marker for it, which no input-chosen text can start. The
      # role is a literal from the two keys below, and only the wording of the output depends on it.
      def approvable(rule; o; role):
        ($ID.maintainer) as $m |
        (if role == "dev_app" then "the declared dev_app" else "a declared maintainer" end) as $who |
        # No declared App is an approver (#708): the first of dev_app, reviewer_app and loop_app that is
        # neither null nor well formed (U), or whose id is on the maintainer list (R), is the only line.
        # $m may be malformed here (the guard below reports it), so only its object entries are compared.
        ( ($m | if type == "array" then map(select(type == "object")) else [] end) ) as $mo |
        ( [ ("dev_app", "reviewer_app", "loop_app") as $k | $ID[$k] as $A
            | if $A == null then empty
              elif ($A | wellformed | not)
                then "U \(rule): spec comment \(o.id) is by \($who) and the declared \($k) is neither null nor a well-formed entry"
              elif any($mo[]; .id == $A.id)
                then "R \(rule): spec comment \(o.id) is by \($who) and the id of the declared \($k) is on the maintainer list"
              else empty end ] | first // null ) as $AC |
        if ($m | type) != "array" or ($m | length) == 0 or (all($m[]; wellformed) | not)
          then "R \(rule): spec comment \(o.id) is by \($who) and the maintainer list has a malformed entry, so no maintainer can approve it"
        elif role == "dev_app" and any($m[]; .id == o.user.id)
          then "R \(rule): spec comment \(o.id) is by the declared dev_app, whose id is on the maintainer list"
        elif $AC != null then $AC
        elif ((o.updated_at | type) != "string") or ((o.updated_at | length) != 20)
             or ((o.updated_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) | not)
          then "U \(rule): spec comment \(o.id) has no well-formed updated_at"
        else "D \(role) \(o.updated_at) \([$m[].id | floor | tostring] | join(","))" end;
      def author(rule; o; what; devok; agentok):
        if $ID == null then
          if (o.author_association // null) == null then "U \(rule): \(what) has no author_association"
          elif (o.author_association | type) == "string" and (o.author_association | trusted) then empty
          else "R \(rule): \(what) author_association is \(o.author_association) (not OWNER, MEMBER or COLLABORATOR)" end
        elif ($ID | type) != "object" then "U \(rule): identities is neither null nor a map"
        elif ((o.user | type) != "object") or ((o.user.login | type) != "string") or ((o.user.id | type) != "number")
          then "U \(rule): \(what) has no author login and id"
        else
          ([declared[] | select(.e.id == o.user.id)]) as $hit |
          if ($hit | length) > 1 then "U \(rule): author id \(o.user.id) is declared more than once"
          elif ($hit | length) == 0 then "R \(rule): \(what) author \(o.user.login) is not a declared maintainer"
          elif ($hit[0].e.login | lc) != (o.user.login | lc) then "U \(rule): \(what) author id \(o.user.id) is declared under a different login"
          elif devok and ($hit[0].role == "dev_app" or $hit[0].role == "maintainer") then approvable(rule; o; $hit[0].role)
          elif agentok and ($hit[0].role == "dev_app" or $hit[0].role == "reviewer_app") then empty
          elif $hit[0].role != "maintainer" then "R \(rule): \(what) author \(o.user.login) is the declared \($hit[0].role), not a maintainer"
          else empty end
        end;
      ($r[0]) as $R | ($i[0]) as $I | ($c[0]) as $c |
      # Under a map the issue body is never the spec (#496), so no spec comment means no spec. This line
      # depends only on those two facts, never on the findings below.
      ( if $haveC == "" and ($ID | type) == "object"
          then "R author: no spec comment was supplied, and under an identities map the issue body is never the spec"
          else empty end ),
      ( if ($R | type) != "array" or any($R[]; type != "object")
        then "U approval-rule: rules are not a list of rule objects"
      elif ($I | type) != "object" then "U author: issue is not an object"
      else
        ([$R[] | select(.type == "pull_request")]) as $P |
        ( if ($P | length) == 0 then "R approval-rule: no `pull_request` rule applies to pr_base"
          elif any($P[]; (.parameters | type) != "object"
                         or (.parameters.required_approving_review_count | type) != "number"
                         or (.parameters.require_code_owner_review | type) != "boolean"
                         or (.parameters.require_last_push_approval | type) != "boolean")
            then "U approval-rule: a pull_request rule has no parameters, or one of the three approval fields is missing or the wrong type"
          else
            ( if any($P[]; .parameters.required_approving_review_count >= 1) then empty else "R approval-rule: required_approving_review_count is below 1" end ),
            ( if any($P[]; .parameters.require_code_owner_review) then empty else "R approval-rule: require_code_owner_review is not set" end ),
            ( if any($P[]; .parameters.require_last_push_approval) then empty else "R approval-rule: require_last_push_approval is not set" end )
          end ),
        ( if ($I.number // null) != $inum then "U author: issue number is not \($inum)"
          elif ($I | has("pull_request")) then "U author: #\($inum) is a pull request, not an issue"
          else empty end ),
        author("author"; $I; "task issue #\($inum)"; false; true),
        ( if $haveC == "" then empty
          elif ($c | type) != "object" then "U author: spec comment is not an object"
          elif ($c.id // null) != $cid then "U author: spec comment id is not \($cid)"
          elif ((($c.issue_url // null) | type) != "string") or (($c.issue_url | test("/issues/\($inum)$")) | not) then "U author: spec comment \($cid) is not shown to belong to issue #\($inum)"
          else author("author"; $c; "spec comment \($cid)"; true; false) end )
      end ) | explode | map(if . < 32 or . == 127 then 63 else . end) | implode' 2>/dev/null | tr -d '\r') || report "U github-dispatch: evaluator failed on the input"
    # Resolve the spec-comment marker (#666, #682), for either role. Every other jq line starts "R " or
    # "U ", so input-chosen text never begins a line and a marker is only ever a line starting "D ".
    markers=0 mline= rebuilt=
    while IFS= read -r line; do
      case "$line" in
        "D "*) markers=$((markers + 1)); mline=$line ;;
        '')    ;;
        *)     rebuilt="${rebuilt}${line}"$'\n' ;;
      esac
    done <<<"$out"
    if [ "$markers" -gt 0 ]; then
      # With no readable role the line names none; the role only ever chooses wording.
      judged="U author: spec comment $comment_id's reactions could not be judged"
      extra=
      tag= role= c_updated= maint_ids= rest= who=
      if [ "$markers" -gt 1 ]; then
        extra=$judged
      else
        read -r tag role c_updated maint_ids rest <<<"$mline"
        ok=1
        case "$role" in
          dev_app)    who="the declared dev_app" ;;
          maintainer) who="a declared maintainer" ;;
          *)          ok= ;;
        esac
        [ -z "$who" ] || judged="U author: spec comment $comment_id is by $who and its reactions could not be judged"
        # Load-bearing: this is what keeps anything but the two validated fields out of the call.
        case "$c_updated" in
          [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
          *) ok= ;;
        esac
        case "$maint_ids" in
          '' | *[!0-9,]* | ,* | *, | *,,*) ok= ;;
        esac
        [ -z "$rest" ] || ok=
        if [ -z "$ok" ]; then
          extra=$judged
        elif [ -z "$reactions" ]; then
          extra="U author: spec comment $comment_id is by $who and no reactions were supplied to judge it"
        elif res=$(sh "$sr" "$c_updated" "$maint_ids" <"$reactions" 2>/dev/null); then
          case "$res" in
            approved)  ;;
            unreacted) extra="R author: spec comment $comment_id is by $who and no declared maintainer approved it after its last edit" ;;
            *)         extra=$judged ;;
          esac
        else
          extra=$judged
        fi
      fi
      out=${rebuilt%$'\n'}
      if [ -n "$extra" ]; then out="${out:+$out$'\n'}$extra"; fi
    fi
    report "$out"
    ;;

  github-push)
    need install repo rules rulesets appf loopid
    case "$repo" in */*) ;; *) die "--repo must be OWNER/NAME" ;; esac
    check_files "$install" "$rules" "$rulesets" "$appf"
    [ -z "$unreadable_files" ] || report "${unreadable_files%$'\n'}"
    out=$(jq -n -r --slurpfile ins "$install" --slurpfile r "$rules" --slurpfile rs "$rulesets" --slurpfile a "$appf" \
      --arg repo "$repo" --arg li "$loopid" '
      ($ins[0]) as $I | ($r[0]) as $R | ($rs[0]) as $RS | ($a[0]) as $A |
      ( if ($I | type) != "object" or ($I.repositories | type) != "array" or ($I.total_count | type) != "number" then "U installation: /installation/repositories is not the expected shape"
        elif $I.total_count != ($I.repositories | length) then "U installation: total_count \($I.total_count) differs from the \($I.repositories | length) repositories shown (truncated?)"
        elif ([$I.repositories[] | select((.full_name // null) | type != "string")] | length) > 0 then "U installation: a repository has no full_name"
        elif ($I.repositories | length) != 1 or (($I.repositories[0].full_name | ascii_downcase) != ($repo | ascii_downcase))
          then "R installation: the token reaches \([$I.repositories[].full_name] | join(", ")), not exactly \($repo)"
        else empty end ),
      ( if ($R | type) != "array" or ([$R[] | select(type != "object" or (.ruleset_id | type) != "number")] | length) > 0 then "U can-bypass: rules are not a list of rule objects carrying ruleset_id"
        elif ($RS | type) != "array" or ([$RS[] | select(type != "object")] | length) > 0 then "U can-bypass: rulesets are not a list of ruleset objects"
        elif ($R | length) == 0 then "R can-bypass: no ruleset applies to pr_base"
        else
          ( [$R[].ruleset_id] | unique[] ) as $id |
          [$RS[] | select(.id == $id)] as $m | ($m[0] // null) as $rsd |
          if ($m | length) == 0 then "U can-bypass: ruleset \($id) applies to pr_base but its document was not supplied"
          elif ($m | length) > 1 then "U can-bypass: ruleset \($id) was supplied \($m | length) times"
          elif ($rsd.current_user_can_bypass // null) == null then "U can-bypass: ruleset \($id) has no current_user_can_bypass"
          elif $rsd.current_user_can_bypass == "never" then empty
          else "R can-bypass: ruleset \($id) reads current_user_can_bypass: \($rsd.current_user_can_bypass)" end
        end ),
      ( if ($A | type) != "object" or (($A.slug // null) | type) != "string" or $A.slug == "" then "U identity: /app has no slug"
        elif $li == "" or $li == "-" then "R identity: no orchestration.loop_identity is configured"
        elif (($A.slug + "[bot]") | ascii_downcase) != ($li | ascii_downcase) then "R identity: the App is \($A.slug)[bot], loop_identity is \($li)"
        else empty end ) | explode | map(if . < 32 or . == 127 then 63 else . end) | implode' 2>/dev/null | tr -d '\r') || report "U github-push: evaluator failed on the input"
    report "$out"
    ;;

  *) die "unknown mode: $mode (container, github-dispatch or github-push)" ;;
esac
