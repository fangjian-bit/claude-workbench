#!/bin/sh
# Fixture tests for scripts/loop/preflight.sh (issue #320).
#
# Hermetic: the evaluators read JSON files, so there is no docker, no gh and no network here.
# Each check gets a pass, a fail and an unreadable case. Fixtures are built from one good
# document per input with jq, then broken one field at a time.
#
# Permitted toolset: POSIX sh, its standard utilities, bash (the script is bash), jq.
set -eu

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
script="$root_dir/scripts/loop/preflight.sh"

for tool in jq bash; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "SKIP - $tool not on PATH; preflight fixtures not run" >&2
    exit 0
  fi
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
NET=wow-loop-net-1

assert_eq() {
  if [ "$2" = "$3" ]; then echo "ok - $1"; else echo "FAIL - $1: expected [$2], got [$3]" >&2; fail=1; fi
}
assert_has() { # desc, haystack, needle
  case "$2" in *"$3"*) echo "ok - $1" ;; *) echo "FAIL - $1: [$2] lacks [$3]" >&2; fail=1 ;; esac
}

# run <args...>: stdout and exit code in $out and $rc
run() { set +e; out=$(bash "$script" "$@" 2>"$tmp/err"); rc=$?; set -e; }

# --- container fixtures ----------------------------------------------------------------------
cat >"$tmp/session.json" <<EOF
[{"Config":{"User":"loop"},
  "HostConfig":{"ReadonlyRootfs":true,"CapDrop":["ALL"],"CapAdd":null,"Privileged":false,"NetworkMode":"$NET","Binds":["wow-loop-vol-1:/work"]},
  "NetworkSettings":{"Networks":{"$NET":{}}},
  "Mounts":[{"Type":"volume","Source":"/var/lib/docker/volumes/work/_data","Destination":"/work"}]}]
EOF
cat >"$tmp/network.json" <<EOF
[{"Name":"$NET","Internal":true,"EnableIPv6":false,
  "Options":{"com.docker.network.bridge.gateway_mode_ipv4":"isolated"},
  "IPAM":{"Config":[{"Subnet":"172.30.0.0/24"}]}}]
EOF
cat >"$tmp/proxy.json" <<EOF
[{"Name":"/proxy","State":{"Running":true},"NetworkSettings":{"Networks":{"$NET":{}}}}]
EOF
cat >"$tmp/inject.json" <<EOF
[{"Name":"/inject","State":{"Running":true},"NetworkSettings":{"Networks":{"$NET":{}}}}]
EOF

cont() { # session network [proxy...]
  s=$1; n=$2; shift 2
  [ $# -gt 0 ] || set -- "$tmp/proxy.json" "$tmp/inject.json"
  pargs=; for p in "$@"; do pargs="$pargs --proxy $p"; done
  # shellcheck disable=SC2086
  run container --session "$s" --network "$n" --expect-network "$NET" $pargs
}

cont "$tmp/session.json" "$tmp/network.json"
assert_eq "container: good inputs pass" "pass/0" "$out/$rc"

mut() { # name file jq-filter: write a mutated copy to $tmp/name
  jq -c "$3" "$2" >"$tmp/$1"
}

for case_ in \
  'user-group-root|.[0].Config.User="loop:0"|refused user' \
  'user-group-name|.[0].Config.User="loop:root"|refused user' \
  'cap-add|.[0].HostConfig.CapAdd=["SYS_ADMIN"]|refused cap-add' \
  'cap-drop-unset|del(.[0].HostConfig.CapDrop)|unreadable cap-drop' \
  'privileged-unset|del(.[0].HostConfig.Privileged)|unreadable privileged' \
  'netmode-unset|del(.[0].HostConfig.NetworkMode)|unreadable network-mode' \
  'pid-host|.[0].HostConfig.PidMode="host"|refused privilege' \
  'userns-host|.[0].HostConfig.UsernsMode="host"|refused privilege' \
  'devices|.[0].HostConfig.Devices=[{"PathOnHost":"/dev/sda"}]|refused privilege' \
  'unconfined|.[0].HostConfig.SecurityOpt=["seccomp=unconfined"]|refused privilege' \
  'second-network|.[0].NetworkSettings.Networks={"wow-loop-net-1":{},"bridge":{}}|refused session-networks' \
  'other-network|.[0].NetworkSettings.Networks={"bridge":{}}|refused session-networks' \
  'networks-unset|del(.[0].NetworkSettings)|unreadable session-networks' \
  'bind-var-run|.[0].Mounts+=[{"Type":"bind","Source":"/var/run","Destination":"/h"}]|refused mounts' \
  'bind-root|.[0].Mounts+=[{"Type":"bind","Source":"/","Destination":"/h"}]|refused mounts' \
  'bind-untyped|.[0].Mounts+=[{"Source":"/srv","Destination":"/h"}]|refused mounts' \
  'binds-var-run|.[0].HostConfig.Binds=["/var/run:/h"]|refused binds' \
  'pid-container|.[0].HostConfig.PidMode="container:proxy"|refused privilege' \
  'ipc-container|.[0].HostConfig.IpcMode="container:proxy"|refused privilege' \
  'ipc-host|.[0].HostConfig.IpcMode="host"|refused privilege' \
  'uts-host|.[0].HostConfig.UTSMode="host"|refused privilege' \
  'cgroupns-host|.[0].HostConfig.CgroupnsMode="host"|refused privilege' \
  'group-add-root|.[0].HostConfig.GroupAdd=["0"]|refused privilege' \
  'device-requests|.[0].HostConfig.DeviceRequests=[{"Count":-1}]|refused privilege' \
  'hc-mounts-bind|.[0].HostConfig.Mounts=[{"Type":"bind","Source":"/","Target":"/h"}]|refused privilege' \
  'binds-drive|.[0].HostConfig.Binds=["C:/x:/x"]|refused binds' \
  'binds-volume-plus-host|.[0].HostConfig.Binds=["wow-loop-vol-1:/work","/srv:/x"]|refused binds' \
  'user-plus0|.[0].Config.User="+0"|refused user' \
  'user-group-plus0|.[0].Config.User="loop:+0"|refused user' \
  'user-group-minus0|.[0].Config.User="loop:-0"|refused user' \
  'group-add-plus0|.[0].HostConfig.GroupAdd=["+0"]|refused privilege' \
  'group-add-minus0|.[0].HostConfig.GroupAdd=["-0"]|refused privilege' \
  'group-add-root-name|.[0].HostConfig.GroupAdd=["root"]|refused privilege' \
  'seccomp-inline|.[0].HostConfig.SecurityOpt=["seccomp={\"defaultAction\":\"SCMP_ACT_ALLOW\"}"]|refused privilege' \
  'secopt-spc|.[0].HostConfig.SecurityOpt=["no-new-privileges","label=type:spc_t"]|refused privilege' \
  'secopt-string|.[0].HostConfig.SecurityOpt="no-new-privileges"|refused privilege' \
  'hc-mounts-string|.[0].HostConfig.Mounts="x"|refused privilege' \
  'user-root|.[0].Config.User="root"|refused user' \
  'user-uid0|.[0].Config.User="0:0"|refused user' \
  'user-empty|.[0].Config.User=""|refused user' \
  'user-unset|del(.[0].Config.User)|unreadable user' \
  'rofs-off|.[0].HostConfig.ReadonlyRootfs=false|refused readonly-rootfs' \
  'rofs-unset|del(.[0].HostConfig.ReadonlyRootfs)|unreadable readonly-rootfs' \
  'caps-kept|.[0].HostConfig.CapDrop=[]|refused cap-drop' \
  'privileged|.[0].HostConfig.Privileged=true|refused privileged' \
  'netmode|.[0].HostConfig.NetworkMode="bridge"|refused network-mode' \
  'mnt|.[0].Mounts+=[{"Type":"volume","Source":"/mnt/c/Users","Destination":"/x"}]|refused mounts' \
  'mnt-upper|.[0].Mounts+=[{"Type":"volume","Source":"/MNT/c","Destination":"/x"}]|refused mounts' \
  'drive|.[0].Mounts+=[{"Type":"volume","Source":"C:/Users/x","Destination":"/x"}]|refused mounts' \
  'drive-lower|.[0].Mounts+=[{"Type":"volume","Source":"d:/x","Destination":"/x"}]|refused mounts' \
  'sock|.[0].Mounts+=[{"Type":"volume","Source":"/var/run/docker.sock","Destination":"/var/run/docker.sock"}]|refused mounts' \
  'sock-dest|.[0].Mounts+=[{"Type":"volume","Source":"/some/where","Destination":"/run/docker.sock"}]|refused mounts' \
  'pipe|.[0].Mounts+=[{"Type":"volume","Source":"//./pipe/docker_engine","Destination":"/x"}]|refused mounts' \
  'bind-sock|.[0].HostConfig.Binds=["/var/run/docker.sock:/s"]|refused binds' \
  'bind-mnt|.[0].HostConfig.Binds=["/mnt/c/x:/x:ro"]|refused binds' \
  'binds-shape|.[0].HostConfig.Binds="x"|unreadable binds' \
  'mounts-unset|del(.[0].Mounts)|unreadable mounts' \
  'two-containers|. + .|unreadable container'
do
  name=${case_%%|*}; rest=${case_#*|}; filt=${rest%|*}; want=${rest##*|}
  mut "s-$name.json" "$tmp/session.json" "$filt"
  cont "$tmp/s-$name.json" "$tmp/network.json"
  assert_eq "container session $name exits 3" 3 "$rc"
  assert_has "container session $name says [$want]" "$out" "$want"
done

for case_ in \
  'ipv6-unset|del(.[0].EnableIPv6)|unreadable ipv6' \
  'name-unset|del(.[0].Name)|unreadable network-name' \
  'not-internal|.[0].Internal=false|refused internal' \
  'internal-unset|del(.[0].Internal)|unreadable internal' \
  'ipv6-on|.[0].EnableIPv6=true|refused ipv6' \
  'mode-bridge|.[0].Options["com.docker.network.bridge.gateway_mode_ipv4"]="nat"|refused gateway-mode' \
  'mode-unset|del(.[0].Options)|unreadable gateway-mode' \
  'gateway|.[0].IPAM.Config[0].Gateway="172.30.0.1"|refused ipam' \
  'gateway-second|.[0].IPAM.Config+=[{"Subnet":"fd00::/64","Gateway":"fd00::1"}]|refused ipam' \
  'ipam-null|.[0].IPAM.Config=null|unreadable ipam' \
  'ipam-empty|.[0].IPAM.Config=[]|unreadable ipam' \
  'wrong-name|.[0].Name="other"|refused network-name'
do
  name=${case_%%|*}; rest=${case_#*|}; filt=${rest%|*}; want=${rest##*|}
  mut "n-$name.json" "$tmp/network.json" "$filt"
  cont "$tmp/session.json" "$tmp/n-$name.json"
  assert_eq "container network $name exits 3" 3 "$rc"
  assert_has "container network $name says [$want]" "$out" "$want"
done

# a gateway is never derived: a subnet whose .1 is unused still passes
cont "$tmp/session.json" "$tmp/network.json"
assert_eq "container: no Gateway is derived from a Subnet" "pass/0" "$out/$rc"

mut p-down.json "$tmp/proxy.json" '.[0].State.Running=false'
cont "$tmp/session.json" "$tmp/network.json" "$tmp/p-down.json" "$tmp/inject.json"
assert_has "container: a stopped proxy is refused" "$out" "refused proxy-running"
mut p-off.json "$tmp/proxy.json" '.[0].NetworkSettings.Networks={"bridge":{}}'
cont "$tmp/session.json" "$tmp/network.json" "$tmp/p-off.json"
assert_has "container: a proxy off the network is refused" "$out" "refused proxy-network"
mut p-state.json "$tmp/proxy.json" 'del(.[0].State)'
cont "$tmp/session.json" "$tmp/network.json" "$tmp/p-state.json"
assert_has "container: a proxy with no State is unreadable" "$out" "unreadable proxy-running"

: >"$tmp/empty.json"
cont "$tmp/empty.json" "$tmp/network.json"
assert_eq "container: an empty session file is unreadable" 3 "$rc"
assert_has "container: empty file named" "$out" "unreadable input"
printf '{not json' >"$tmp/garbage.json"
cont "$tmp/session.json" "$tmp/garbage.json"
assert_has "container: garbage network file is unreadable" "$out" "unreadable input"
cont "$tmp/nope.json" "$tmp/network.json"
assert_has "container: a missing file is unreadable" "$out" "unreadable input"
printf '{}' >"$tmp/obj.json"
cont "$tmp/obj.json" "$tmp/network.json"
assert_has "container: a non-array session is unreadable" "$out" "unreadable container"

# several findings at once all print
mut s-multi.json "$tmp/session.json" '.[0].Config.User="root"|.[0].HostConfig.ReadonlyRootfs=false'
cont "$tmp/s-multi.json" "$tmp/network.json"
assert_eq "container: two findings, two lines" 2 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

# a control character in a quoted path cannot forge a line
mut s-nl.json "$tmp/session.json" '.[0].Mounts+=[{"Source":"/mnt/x\npass","Destination":"/x"}]'
cont "$tmp/s-nl.json" "$tmp/network.json"
assert_eq "container: a newline in a mount source stays on one line" 1 "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

# --- github-dispatch fixtures ------------------------------------------------------------------
APP=424242
printf null >"$tmp/ident-null.json"
cat >"$tmp/rules.json" <<EOF
[{"type":"deletion","ruleset_id":1},
 {"type":"pull_request","ruleset_id":1,"parameters":{"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true,"require_code_owner_review":true,"require_last_push_approval":true}},
 {"type":"non_fast_forward","ruleset_id":2}]
EOF
cat >"$tmp/issue.json" <<EOF
{"number":320,"author_association":"MEMBER"}
EOF
cat >"$tmp/comment.json" <<EOF
{"id":777,"author_association":"OWNER","issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}
EOF

disp() { # rules issue [comment|-]
  c=$3
  if [ "$c" = - ]; then
    run github-dispatch --rules "$1" --identities "${IDENT:-$tmp/ident-null.json}" --issue "$2" --issue-number 320 --no-spec-comment
  else
    run github-dispatch --rules "$1" --identities "${IDENT:-$tmp/ident-null.json}" --issue "$2" --issue-number 320 --spec-comment "$c" --spec-comment-id 777
  fi
}

disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/comment.json"
assert_eq "dispatch: good inputs pass" "pass/0" "$out/$rc"
disp "$tmp/rules.json" "$tmp/issue.json" -
assert_eq "dispatch: good inputs pass with no spec comment" "pass/0" "$out/$rc"

# --- the approval rule (WB-D24, #388): count >= 1, code owner, last push, summed across rules ---
jq -c 'map(select(.type!="pull_request"))' "$tmp/rules.json" >"$tmp/r-nopr.json"
disp "$tmp/r-nopr.json" "$tmp/issue.json" -
assert_has "dispatch: no pull_request rule is refused" "$out" "refused approval-rule"
printf '[]' >"$tmp/r-none.json"
disp "$tmp/r-none.json" "$tmp/issue.json" -
assert_has "dispatch: no rules at all is refused" "$out" "refused approval-rule"
jq -c 'map(select(.type!="pull_request"))+[{"type":"update","ruleset_id":2}]' "$tmp/rules.json" >"$tmp/r-upd.json"
disp "$tmp/r-upd.json" "$tmp/issue.json" -
assert_has "dispatch: an update rule is no longer the gate" "$out" "refused approval-rule"
jq -c '(.[]|select(.type=="pull_request")).type="pull_request_x"' "$tmp/rules.json" >"$tmp/r-near.json"
disp "$tmp/r-near.json" "$tmp/issue.json" -
assert_has "dispatch: a lookalike rule type is refused" "$out" "refused approval-rule"
jq -c '(.[]|select(.type=="pull_request")).parameters.required_approving_review_count=0' "$tmp/rules.json" >"$tmp/r-c0.json"
disp "$tmp/r-c0.json" "$tmp/issue.json" -
assert_has "dispatch: zero required approvals is refused" "$out" "refused approval-rule: required_approving_review_count"
jq -c '(.[]|select(.type=="pull_request")).parameters.required_approving_review_count=2' "$tmp/rules.json" >"$tmp/r-c2.json"
disp "$tmp/r-c2.json" "$tmp/issue.json" -
assert_eq "dispatch: two required approvals pass" "pass/0" "$out/$rc"
jq -c '(.[]|select(.type=="pull_request")).parameters.require_code_owner_review=false' "$tmp/rules.json" >"$tmp/r-co.json"
disp "$tmp/r-co.json" "$tmp/issue.json" -
assert_has "dispatch: no code-owner review is refused" "$out" "refused approval-rule: require_code_owner_review"
jq -c '(.[]|select(.type=="pull_request")).parameters.require_last_push_approval=false' "$tmp/rules.json" >"$tmp/r-lp.json"
disp "$tmp/r-lp.json" "$tmp/issue.json" -
assert_has "dispatch: no last-push approval is refused" "$out" "refused approval-rule: require_last_push_approval"
jq -c '(.[]|select(.type=="pull_request")).parameters|=(.required_approving_review_count=0|.require_code_owner_review=false|.require_last_push_approval=false)' "$tmp/rules.json" >"$tmp/r-all.json"
disp "$tmp/r-all.json" "$tmp/issue.json" -
assert_eq "dispatch: all three missing is three findings" 3 "$(printf '%s\n' "$out" | grep -c '^refused approval-rule')"
# overlapping rulesets: GitHub applies the strictest of each, so the three need not share a rule
jq -c '. + [{"type":"pull_request","ruleset_id":3,"parameters":{"required_approving_review_count":0,"require_code_owner_review":false,"require_last_push_approval":false}}]' "$tmp/rules.json" >"$tmp/r-weak-extra.json"
disp "$tmp/r-weak-extra.json" "$tmp/issue.json" -
assert_eq "dispatch: a weaker pull_request rule beside the approval one still passes" "pass/0" "$out/$rc"
jq -c '(.[]|select(.type=="pull_request")).parameters|=(.require_code_owner_review=false|.require_last_push_approval=false)
       | . + [{"type":"pull_request","ruleset_id":3,"parameters":{"required_approving_review_count":0,"require_code_owner_review":true,"require_last_push_approval":true}}]' "$tmp/rules.json" >"$tmp/r-split.json"
disp "$tmp/r-split.json" "$tmp/issue.json" -
assert_eq "dispatch: the three properties may come from different rulesets" "pass/0" "$out/$rc"
jq -c '(.[]|select(.type=="pull_request")).parameters|=del(.require_last_push_approval)' "$tmp/rules.json" >"$tmp/r-nolp.json"
disp "$tmp/r-nolp.json" "$tmp/issue.json" -
assert_has "dispatch: a missing approval field is unreadable" "$out" "unreadable approval-rule"
jq -c '(.[]|select(.type=="pull_request")).parameters.require_code_owner_review="true"' "$tmp/rules.json" >"$tmp/r-str.json"
disp "$tmp/r-str.json" "$tmp/issue.json" -
assert_has "dispatch: a string where a boolean belongs is unreadable" "$out" "unreadable approval-rule"
jq -c '(.[]|select(.type=="pull_request"))|=del(.parameters)' "$tmp/rules.json" >"$tmp/r-nop.json"
disp "$tmp/r-nop.json" "$tmp/issue.json" -
assert_has "dispatch: a pull_request rule with no parameters is unreadable" "$out" "unreadable approval-rule"
jq -c '. + [{"type":"pull_request","ruleset_id":3,"parameters":{"required_approving_review_count":1}}]' "$tmp/rules.json" >"$tmp/r-bad-extra.json"
disp "$tmp/r-bad-extra.json" "$tmp/issue.json" -
assert_has "dispatch: one malformed pull_request rule is unreadable even beside a good one" "$out" "unreadable approval-rule"
printf '{"message":"Not Found"}' >"$tmp/r-err.json"
disp "$tmp/r-err.json" "$tmp/issue.json" -
assert_has "dispatch: an API error body is unreadable" "$out" "unreadable approval-rule"
jq -c '. + ["x"]' "$tmp/rules.json" >"$tmp/r-nonobj.json"
disp "$tmp/r-nonobj.json" "$tmp/issue.json" -
assert_has "dispatch: a rule that is not an object is unreadable" "$out" "unreadable approval-rule"

for assoc in OWNER MEMBER COLLABORATOR; do
  jq -c ".author_association=\"$assoc\"" "$tmp/issue.json" >"$tmp/i-ok.json"
  disp "$tmp/rules.json" "$tmp/i-ok.json" -
  assert_eq "dispatch: issue author $assoc is trusted" "pass/0" "$out/$rc"
done
for assoc in NONE CONTRIBUTOR FIRST_TIME_CONTRIBUTOR FIRST_TIMER MANNEQUIN ""; do
  jq -c ".author_association=\"$assoc\"" "$tmp/issue.json" >"$tmp/i-bad.json"
  disp "$tmp/rules.json" "$tmp/i-bad.json" -
  assert_has "dispatch: issue author [$assoc] is refused" "$out" "refused author"
done
jq -c 'del(.author_association)' "$tmp/issue.json" >"$tmp/i-unset.json"
disp "$tmp/rules.json" "$tmp/i-unset.json" -
assert_has "dispatch: no author_association is unreadable" "$out" "unreadable author"
jq -c '.number=321' "$tmp/issue.json" >"$tmp/i-num.json"
disp "$tmp/rules.json" "$tmp/i-num.json" -
assert_has "dispatch: the wrong issue number is unreadable" "$out" "unreadable author"
jq -c '.author_association="NONE"' "$tmp/comment.json" >"$tmp/c-bad.json"
disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/c-bad.json"
assert_has "dispatch: an untrusted spec comment is refused" "$out" "refused author"
jq -c '.id=1' "$tmp/comment.json" >"$tmp/c-id.json"
disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/c-id.json"
assert_has "dispatch: a spec comment with another id is unreadable" "$out" "unreadable author"
jq -c 'del(.author_association)' "$tmp/comment.json" >"$tmp/c-unset.json"
disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/c-unset.json"
assert_has "dispatch: a spec comment with no author_association is unreadable" "$out" "unreadable author"

: >"$tmp/empty.json"
disp "$tmp/empty.json" "$tmp/issue.json" -
assert_has "dispatch: an empty rules file is unreadable" "$out" "unreadable input"
disp "$tmp/rules.json" "$tmp/empty.json" -
assert_has "dispatch: an empty issue file is unreadable" "$out" "unreadable input"
disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/empty.json"
assert_has "dispatch: an empty comment file is unreadable" "$out" "unreadable input"

# --- trust by declared identity (#382): --identities a map, so {login, id} decides and ------
# --- author_association does not. An App token reads the maintainer as CONTRIBUTOR. --------
cat >"$tmp/ident-map.json" <<EOF
{"maintainer":[{"login":"Alice-Dev","id":1001},{"login":"bob","id":1002}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":{"login":"acme-loop[bot]","id":2003}}
EOF
cat >"$tmp/ident-bad.json" <<EOF
{"maintainer":["alice-dev",{"login":"alice-dev","id":"1001"},{"login":"alice-dev","id":0},{"id":1001}],
 "dev_app":"acme-dev[bot]","reviewer_app":null,"loop_app":null}
EOF
cat >"$tmp/ident-dup.json" <<EOF
{"maintainer":[{"login":"alice-dev","id":1001}],"dev_app":{"login":"alice-dev","id":1001},"reviewer_app":null,"loop_app":null}
EOF
UPD=2026-10-01T12:00:00Z
rx() { # file uid content created_at  (appends one TSV row)
  printf '%s\t%s\t%s\n' "$2" "$3" "$4" >>"$1"
}
rdisp() { # rules identities issue comment reactions
  run github-dispatch --rules "$1" --identities "$2" --issue "$3" --issue-number 320 --spec-comment "$4" --spec-comment-id 777 --spec-reactions "$5"
}
idisp() { # identities-file issue [comment|-]
  IDENT=$1 disp "$tmp/rules.json" "$2" "$3"
}
mkissue() { # file assoc login id
  printf '{"number":320,"author_association":"%s","user":{"login":"%s","id":%s}}' "$2" "$3" "$4" >"$1"
}
mkissue "$tmp/i-app-view.json" CONTRIBUTOR alice-dev 1001
# bob (1002, a declared maintainer) wrote this spec comment; a fresh +1 by 1001 approves it, so a fixture
# that moves to it is judged on its issue author alone (#682).
printf '{"id":777,"author_association":"CONTRIBUTOR","user":{"login":"bob","id":1002},"updated_at":"%s","issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}' "$UPD" >"$tmp/c-ok.json"
: >"$tmp/rx-fresh.tsv"; rx "$tmp/rx-fresh.tsv" 1001 '+1' 2026-10-01T12:00:01Z
mdisp() { # identities-file issue
  rdisp "$tmp/rules.json" "$1" "$2" "$tmp/c-ok.json" "$tmp/rx-fresh.tsv"
}
mdisp "$tmp/ident-map.json" "$tmp/i-app-view.json"
assert_eq "dispatch (identities): the maintainer passes though an App token reads CONTRIBUTOR" "pass/0" "$out/$rc"
mkissue "$tmp/i-case.json" NONE ALICE-DEV 1001
mdisp "$tmp/ident-map.json" "$tmp/i-case.json"
assert_eq "dispatch (identities): login compared case-folded" "pass/0" "$out/$rc"
mkissue "$tmp/i-stranger.json" OWNER stranger 9999
mdisp "$tmp/ident-map.json" "$tmp/i-stranger.json"
assert_eq "dispatch (identities): an OWNER association no longer trusts an undeclared author" "refused author: task issue #320 author stranger is not a declared maintainer/3" "$out/$rc"
mkissue "$tmp/i-dev.json" MEMBER 'acme-dev[bot]' 2001
mdisp "$tmp/ident-map.json" "$tmp/i-dev.json"
assert_eq "dispatch (identities): the dev App's own issue passes the author rule (WB-D32)" "pass/0" "$out/$rc"
# These cases mirror gh-identity.sh task-author: trusted and agent pass, loop_app and undeclared are
# refused, a login that does not match its id and an id declared twice are unreadable.
cat >"$tmp/ident-rev2.json" <<EOF
{"maintainer":[{"login":"Alice-Dev","id":1001},{"login":"bob","id":1002}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":{"login":"acme-review[bot]","id":2002},"loop_app":{"login":"acme-loop[bot]","id":2003}}
EOF
mkissue "$tmp/i-rev.json" NONE 'acme-review[bot]' 2002
mdisp "$tmp/ident-rev2.json" "$tmp/i-rev.json"
assert_eq "dispatch (identities): a reviewer-App task issue passes the author rule (WB-D32)" "pass/0" "$out/$rc"
mkissue "$tmp/i-rev-renamed.json" NONE 'acme-other[bot]' 2002
mdisp "$tmp/ident-rev2.json" "$tmp/i-rev-renamed.json"
assert_eq "dispatch (identities): an App id under another login is unreadable, not passed" "unreadable author: task issue #320 author id 2002 is declared under a different login/3" "$out/$rc"
cat >"$tmp/ident-appdup.json" <<EOF
{"maintainer":[{"login":"Alice-Dev","id":1001},{"login":"bob","id":1002}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":{"login":"acme-dev[bot]","id":2001},"loop_app":null}
EOF
mdisp "$tmp/ident-appdup.json" "$tmp/i-dev.json"
assert_eq "dispatch (identities): an App id declared twice is unreadable, not passed" "unreadable author: author id 2001 is declared more than once/3" "$out/$rc"
mkissue "$tmp/i-app-stranger.json" NONE 'acme-stranger[bot]' 9997
mdisp "$tmp/ident-rev2.json" "$tmp/i-app-stranger.json"
assert_eq "dispatch (identities): an undeclared App is still refused as a task issue author" "refused author: task issue #320 author acme-stranger[bot] is not a declared maintainer/3" "$out/$rc"
rdisp "$tmp/rules.json" "$tmp/ident-rev2.json" "$tmp/i-rev.json" "$tmp/c-ok.json" "$tmp/rx-fresh.tsv"
assert_eq "dispatch (identities): no reaction is read for the task issue (only the spec comment's approving row)" "pass/0" "$out/$rc"
mkissue "$tmp/i-loop.json" MEMBER 'acme-loop[bot]' 2003
mdisp "$tmp/ident-map.json" "$tmp/i-loop.json"
assert_eq "dispatch (identities): the loop App's issue is refused" "refused author: task issue #320 author acme-loop[bot] is the declared loop_app, not a maintainer/3" "$out/$rc"
mkissue "$tmp/i-other-id.json" MEMBER alice-dev 9999
mdisp "$tmp/ident-map.json" "$tmp/i-other-id.json"
assert_eq "dispatch (identities): a maintainer's login on another id is refused" "refused author: task issue #320 author alice-dev is not a declared maintainer/3" "$out/$rc"
mkissue "$tmp/i-renamed.json" MEMBER alice-renamed 1001
mdisp "$tmp/ident-map.json" "$tmp/i-renamed.json"
assert_eq "dispatch (identities): a declared id under another login is unreadable, not guessed" "unreadable author: task issue #320 author id 1001 is declared under a different login/3" "$out/$rc"
idisp "$tmp/ident-dup.json" "$tmp/i-app-view.json" -
assert_has "dispatch (identities): an id declared twice is unreadable" "$out" "unreadable author: author id 1001 is declared more than once"
idisp "$tmp/ident-bad.json" "$tmp/i-app-view.json" -
assert_has "dispatch (identities): only malformed entries match nothing, so the author is refused" "$out" "refused author: task issue #320 author alice-dev is not a declared maintainer"
printf '{"number":320,"author_association":"OWNER"}' >"$tmp/i-nouser.json"
mdisp "$tmp/ident-map.json" "$tmp/i-nouser.json"
assert_eq "dispatch (identities): an issue with no author login and id is unreadable" "unreadable author: task issue #320 has no author login and id/3" "$out/$rc"
printf '"yes"' >"$tmp/ident-str.json"
idisp "$tmp/ident-str.json" "$tmp/i-app-view.json" -
assert_eq "dispatch (identities): identities neither null nor a map is unreadable" "unreadable author: identities is neither null nor a map/3" "$out/$rc"
mdisp "$tmp/ident-map.json" "$tmp/i-app-view.json"
assert_eq "dispatch (identities): a second maintainer's spec comment passes with a fresh reaction" "pass/0" "$out/$rc"
printf '{"id":777,"author_association":"OWNER","user":{"login":"stranger","id":9999},"issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}' >"$tmp/c-bad2.json"
idisp "$tmp/ident-map.json" "$tmp/i-app-view.json" "$tmp/c-bad2.json"
assert_has "dispatch (identities): an undeclared spec comment author is refused" "$out" "refused author"
# An ABSENT identities key reaches the driver as an empty file (the documented yq form prints
# nothing for it): unreadable, never read as "not cut over" and the association fallback.
: >"$tmp/ident-absent.json"
idisp "$tmp/ident-absent.json" "$tmp/i-stranger.json" -
assert_eq "dispatch (identities): an absent key (empty file) is unreadable, not the association fallback" "unreadable input: ident-absent.json is missing, empty or not exactly one JSON value/3" "$out/$rc"
run github-dispatch --rules "$tmp/rules.json" --issue "$tmp/issue.json" --issue-number 320 --no-spec-comment
assert_eq "dispatch: --identities is required" "2" "$rc"

# --- dev-App spec comment (#666): accepted only with a declared maintainer's reaction after its -
# --- last edit, judged by spec-reaction.sh. The reactions file is TSV, one reaction per line. ---
mkdev() { # file [updated_at-json-fragment, default the fixed one]
  printf '{"id":777,"author_association":"NONE","user":{"login":"acme-dev[bot]","id":2001},%s"issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}' "${2-\"updated_at\":\"$UPD\",}" >"$1"
}
mkdev "$tmp/c-dev.json"
mkissue "$tmp/i-maint.json" CONTRIBUTOR alice-dev 1001
DEVREF="refused author: spec comment 777 is by the declared dev_app and no declared maintainer approved it after its last edit"
UNJ="unreadable author: spec comment 777 is by the declared dev_app and its reactions could not be judged"
MREF="refused author: spec comment 777 is by a declared maintainer and no declared maintainer approved it after its last edit"
MUNJ="unreadable author: spec comment 777 is by a declared maintainer and its reactions could not be judged"

for content in '+1' heart hooray rocket; do
  : >"$tmp/rx-ok.tsv"; rx "$tmp/rx-ok.tsv" 1001 "$content" 2026-10-01T12:00:01Z
  rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-ok.tsv"
  assert_eq "dev-App spec: a maintainer $content after updated_at passes" "pass/0" "$out/$rc"
done
: >"$tmp/rx-empty.tsv"
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-empty.tsv"
assert_eq "dev-App spec: an empty reactions file is refused" "$DEVREF/3" "$out/$rc"
: >"$tmp/rx-own.tsv"; rx "$tmp/rx-own.tsv" 2001 rocket 2026-10-01T12:00:01Z
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-own.tsv"
assert_eq "dev-App spec: only the dev App's own reaction is refused" "$DEVREF/3" "$out/$rc"
: >"$tmp/rx-eq.tsv"; rx "$tmp/rx-eq.tsv" 1001 heart "$UPD"
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-eq.tsv"
assert_eq "dev-App spec: a reaction at exactly updated_at is refused" "$DEVREF/3" "$out/$rc"
: >"$tmp/rx-old.tsv"; rx "$tmp/rx-old.tsv" 1001 heart 2026-10-01T11:59:59Z
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-old.tsv"
assert_eq "dev-App spec: a reaction before updated_at is refused" "$DEVREF/3" "$out/$rc"
: >"$tmp/rx-eyes.tsv"; rx "$tmp/rx-eyes.tsv" 1001 eyes 2026-10-01T12:00:01Z
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-eyes.tsv"
assert_eq "dev-App spec: a content outside the four is refused" "$DEVREF/3" "$out/$rc"

MALF="refused author: spec comment 777 is by the declared dev_app and the maintainer list has a malformed entry, so no maintainer can approve it"
cat >"$tmp/ident-malf.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"id":1003},{"login":"x","id":"1004"}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":null}
EOT
: >"$tmp/rx-malf.tsv"; rx "$tmp/rx-malf.tsv" 1003 '+1' 2026-10-01T12:00:01Z; rx "$tmp/rx-malf.tsv" 1004 '+1' 2026-10-01T12:00:01Z
rdisp "$tmp/rules.json" "$tmp/ident-malf.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-malf.tsv"
assert_eq "dev-App spec: malformed maintainer entries refuse even with their reactions" "$MALF/3" "$out/$rc"
cat >"$tmp/ident-frac.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"login":"carol","id":1003.5}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":null}
EOT
: >"$tmp/rx-frac.tsv"; rx "$tmp/rx-frac.tsv" 1003 '+1' 2026-10-01T12:00:01Z
rdisp "$tmp/rules.json" "$tmp/ident-frac.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-frac.tsv"
assert_eq "dev-App spec: a fractional maintainer id refuses" "$MALF/3" "$out/$rc"
cat >"$tmp/ident-malf2001.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"id":2001}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":null}
EOT
rdisp "$tmp/rules.json" "$tmp/ident-malf2001.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-own.tsv"
assert_eq "dev-App spec: a malformed entry carrying the dev App's id refuses" "$MALF/3" "$out/$rc"
cat >"$tmp/ident-dev-maint.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"login":"acme-dev[bot]","id":2001}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":null}
EOT
rdisp "$tmp/rules.json" "$tmp/ident-dev-maint.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-own.tsv"
assert_eq "dev-App spec: the dev App id as a well-formed maintainer is declared twice" "unreadable author: author id 2001 is declared more than once/3" "$out/$rc"

cat >"$tmp/ident-prec.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"login":"zz","id":2001.0000000000000001}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":null}
EOT
rdisp "$tmp/rules.json" "$tmp/ident-prec.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-own.tsv"
assert_eq "dev-App spec: a high-precision id that rounds to the dev App's cannot make it an approver" "3" "$rc"
case "$out" in pass*) echo "FAIL - high-precision maintainer id passed" >&2; fail=1 ;; *) echo "ok - high-precision maintainer id did not pass" ;; esac
cat >"$tmp/ident-float.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001.0}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":null}
EOT
rdisp "$tmp/rules.json" "$tmp/ident-float.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-ok.tsv"
# jq before 1.7 does not keep number literals, so 1001.0 reads as 1001 there.
if [ "$(jq -nc '1001.0 | tojson')" = '"1001.0"' ]; then
  assert_eq "dev-App spec: a maintainer id written 1001.0 is malformed, as a YAML float is to spec-comment.sh" "$MALF/3" "$out/$rc"
else
  echo "SKIP - this jq does not keep number literals; the 1001.0 fixture needs jq 1.7 or later" >&2
fi
mkdev "$tmp/c-dev-noupd.json" ''
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev-noupd.json" "$tmp/rx-ok.tsv"
assert_eq "dev-App spec: no updated_at is unreadable" "unreadable author: spec comment 777 has no well-formed updated_at/3" "$out/$rc"
mkdev "$tmp/c-dev-ms.json" '"updated_at":"2026-10-01T12:00:00.000Z",'
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev-ms.json" "$tmp/rx-ok.tsv"
assert_eq "dev-App spec: a fractional-second updated_at is unreadable" "unreadable author: spec comment 777 has no well-formed updated_at/3" "$out/$rc"
IDENT="$tmp/ident-map.json" disp "$tmp/rules.json" "$tmp/i-maint.json" "$tmp/c-dev.json"
assert_eq "dev-App spec: no --spec-reactions is unreadable" "unreadable author: spec comment 777 is by the declared dev_app and no reactions were supplied to judge it/3" "$out/$rc"
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-ok.json" "$tmp/nope.tsv"
assert_eq "a missing reactions file is unreadable input, whatever the author" "unreadable input: nope.tsv is missing or not a readable file/3" "$out/$rc"
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-ok.json" "$tmp/rx-empty.tsv"
assert_eq "a maintainer's spec comment is refused with an empty reactions file" "$MREF/3" "$out/$rc"
printf '{"id":777,"author_association":"MEMBER","issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}' >"$tmp/c-assoc.json"
rdisp "$tmp/rules.json" "$tmp/ident-null.json" "$tmp/issue.json" "$tmp/c-assoc.json" "$tmp/rx-empty.tsv"
assert_eq "--identities null: an association-trusted comment passes with a reactions file" "pass/0" "$out/$rc"
printf '{"id":777,"author_association":"NONE","user":{"login":"acme-loop[bot]","id":2003},"updated_at":"%s","issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}' "$UPD" >"$tmp/c-loopapp.json"
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-loopapp.json" "$tmp/rx-ok.tsv"
assert_eq "a loop-App spec comment is refused despite an approving reaction" "refused author: spec comment 777 author acme-loop[bot] is the declared loop_app, not a maintainer/3" "$out/$rc"
cat >"$tmp/ident-rev.json" <<EOT
{"maintainer":[{"login":"Alice-Dev","id":1001},{"login":"bob","id":1002}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":{"login":"acme-review[bot]","id":2002},"loop_app":null}
EOT
printf '{"id":777,"author_association":"NONE","user":{"login":"acme-review[bot]","id":2002},"updated_at":"%s","issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}' "$UPD" >"$tmp/c-revapp.json"
rdisp "$tmp/rules.json" "$tmp/ident-rev.json" "$tmp/i-maint.json" "$tmp/c-revapp.json" "$tmp/rx-ok.tsv"
assert_eq "a reviewer-App spec comment is refused despite an approving reaction" "refused author: spec comment 777 author acme-review[bot] is the declared reviewer_app, not a maintainer/3" "$out/$rc"
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-dev.json" "$tmp/c-ok.json" "$tmp/rx-ok.tsv"
assert_eq "a dev-App task issue passes the author rule with an approving reactions file (WB-D32)" "pass/0" "$out/$rc"
rdisp "$tmp/r-co.json" "$tmp/ident-map.json" "$tmp/i-maint.json" "$tmp/c-dev.json" "$tmp/rx-ok.tsv"
assert_eq "an approved dev-App comment leaves other findings alone" "refused approval-rule: require_code_owner_review is not set/3" "$out/$rc"
mkissue "$tmp/i-evil.json" NONE evilD 9998
rdisp "$tmp/rules.json" "$tmp/ident-map.json" "$tmp/i-evil.json" "$tmp/c-dev.json" "$tmp/rx-ok.tsv"
assert_eq "a refusal line containing D  is not read as the marker" "refused author: task issue #320 author evilD is not a declared maintainer/3" "$out/$rc"

run github-dispatch --rules "$tmp/rules.json" --identities "$tmp/ident-map.json" --issue "$tmp/i-maint.json" --issue-number 320 --no-spec-comment --spec-reactions "$tmp/rx-ok.tsv"
assert_eq "--spec-reactions with --no-spec-comment is a usage fault" "/2" "$out/$rc"

# --- a maintainer-authored spec comment needs the same reaction (#682) ---------------------------
mrd() { # identities reactions [comment, default bob's c-ok.json]
  rdisp "$tmp/rules.json" "$1" "$tmp/i-maint.json" "${3:-$tmp/c-ok.json}" "$2"
}
IDENT="$tmp/ident-map.json" disp "$tmp/rules.json" "$tmp/i-maint.json" "$tmp/c-ok.json"
assert_eq "maintainer spec: no --spec-reactions is unreadable" "unreadable author: spec comment 777 is by a declared maintainer and no reactions were supplied to judge it/3" "$out/$rc"
mrd "$tmp/ident-map.json" "$tmp/rx-empty.tsv"
assert_eq "maintainer spec: an empty reactions file is refused" "$MREF/3" "$out/$rc"
mrd "$tmp/ident-map.json" "$tmp/rx-old.tsv"
assert_eq "maintainer spec: a reaction before updated_at is refused" "$MREF/3" "$out/$rc"
mrd "$tmp/ident-map.json" "$tmp/rx-eq.tsv"
assert_eq "maintainer spec: a reaction at exactly updated_at is refused" "$MREF/3" "$out/$rc"
for content in '+1' heart hooray rocket; do
  : >"$tmp/rx-m.tsv"; rx "$tmp/rx-m.tsv" 1001 "$content" 2026-10-01T12:00:01Z
  mrd "$tmp/ident-map.json" "$tmp/rx-m.tsv"
  assert_eq "maintainer spec: another maintainer's $content after updated_at passes" "pass/0" "$out/$rc"
done
: >"$tmp/rx-m.tsv"; rx "$tmp/rx-m.tsv" 1002 heart 2026-10-01T12:00:01Z
mrd "$tmp/ident-map.json" "$tmp/rx-m.tsv"
assert_eq "maintainer spec: the author's own reaction approves their own comment" "pass/0" "$out/$rc"
mrd "$tmp/ident-map.json" "$tmp/rx-own.tsv"
assert_eq "maintainer spec: only the dev App's reaction is refused" "$MREF/3" "$out/$rc"
: >"$tmp/rx-m.tsv"; rx "$tmp/rx-m.tsv" 9999 '+1' 2026-10-01T12:00:01Z
mrd "$tmp/ident-map.json" "$tmp/rx-m.tsv"
assert_eq "maintainer spec: an undeclared id's reaction is refused" "$MREF/3" "$out/$rc"
mrd "$tmp/ident-map.json" "$tmp/rx-eyes.tsv"
assert_eq "maintainer spec: a content outside the four is refused" "$MREF/3" "$out/$rc"

printf '{"id":777,"author_association":"CONTRIBUTOR","user":{"login":"alice-dev","id":1001},"updated_at":"%s","issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}' "$UPD" >"$tmp/c-alice.json"
mrd "$tmp/ident-malf.json" "$tmp/rx-fresh.tsv" "$tmp/c-alice.json"
assert_eq "maintainer spec: a malformed maintainer entry refuses even with a fresh reaction" "refused author: spec comment 777 is by a declared maintainer and the maintainer list has a malformed entry, so no maintainer can approve it/3" "$out/$rc"

cat >"$tmp/ident-devlist.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"login":"bob","id":1002},{"login":"acme-dev[bot]","id":2001}],
 "dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":null}
EOT
: >"$tmp/rx-m.tsv"; rx "$tmp/rx-m.tsv" 2001 '+1' 2026-10-01T12:00:01Z
mrd "$tmp/ident-devlist.json" "$tmp/rx-m.tsv"
assert_eq "maintainer spec: the dev App's id on the maintainer list refuses, even with its own fresh reaction" "refused author: spec comment 777 is by a declared maintainer and the id of the declared dev_app is on the maintainer list/3" "$out/$rc"
cat >"$tmp/ident-devstr.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"login":"bob","id":1002}],
 "dev_app":"acme-dev[bot]","reviewer_app":null,"loop_app":null}
EOT
mrd "$tmp/ident-devstr.json" "$tmp/rx-fresh.tsv"
assert_eq "maintainer spec: a dev_app that is a bare string is unreadable" "unreadable author: spec comment 777 is by a declared maintainer and the declared dev_app is neither null nor a well-formed entry/3" "$out/$rc"
cat >"$tmp/ident-devfrac.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"login":"bob","id":1002}],
 "dev_app":{"login":"acme-dev[bot]","id":2001.5},"reviewer_app":null,"loop_app":null}
EOT
mrd "$tmp/ident-devfrac.json" "$tmp/rx-fresh.tsv"
assert_eq "maintainer spec: a dev_app with a fractional id is unreadable" "unreadable author: spec comment 777 is by a declared maintainer and the declared dev_app is neither null nor a well-formed entry/3" "$out/$rc"
cat >"$tmp/ident-devexp.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"login":"bob","id":1002},{"login":"carol","id":2001}],
 "dev_app":{"login":"acme-dev[bot]","id":2.001e3},"reviewer_app":null,"loop_app":null}
EOT
mrd "$tmp/ident-devexp.json" "$tmp/rx-fresh.tsv"
assert_eq "maintainer spec: an exponent-spelled dev_app id is compared like any other id" "refused author: spec comment 777 is by a declared maintainer and the id of the declared dev_app is on the maintainer list/3" "$out/$rc"
cat >"$tmp/ident-nodev.json" <<EOT
{"maintainer":[{"login":"alice-dev","id":1001},{"login":"bob","id":1002}],
 "dev_app":null,"reviewer_app":null,"loop_app":null}
EOT
mrd "$tmp/ident-nodev.json" "$tmp/rx-fresh.tsv"
assert_eq "maintainer spec: a null dev_app means no dev App and passes with a fresh reaction" "pass/0" "$out/$rc"

# --- no declared App is an approver, the reviewer and loop Apps too (#708) ---------------------
# idapp <name> <dev> <reviewer> <loop>: write $tmp/ident-<name>.json; each App argument is a JSON value.
idapp() {
  printf '{"maintainer":[{"login":"alice-dev","id":1001},{"login":"bob","id":1002},{"login":"carol","id":2002},{"login":"dave","id":2003}],"dev_app":%s,"reviewer_app":%s,"loop_app":%s}\n' "$2" "$3" "$4" >"$tmp/ident-$1.json"
}
DEVJ='{"login":"acme-dev[bot]","id":2001}'
REVJ='{"login":"acme-review[bot]","id":2002}'
LOOPJ='{"login":"acme-loop[bot]","id":2003}'
for who in maint:"$tmp/c-ok.json":"a declared maintainer" dev:"$tmp/c-dev.json":"the declared dev_app"; do
  wname="${who%%:*}"; wrest="${who#*:}"; wfile="${wrest%%:*}"; wtxt="${wrest#*:}"
  for key in reviewer_app loop_app; do
    case "$key" in reviewer_app) KJ="$REVJ" ;; *) KJ="$LOOPJ" ;; esac
    case "$key" in
      reviewer_app) idapp listed "$DEVJ" "$KJ" null ;;
      *) idapp listed "$DEVJ" null "$KJ" ;;
    esac
    # carol (2002) and dave (2003) are on the maintainer list in these identities.
    mrd "$tmp/ident-listed.json" "$tmp/rx-fresh.tsv" "$wfile"
    assert_eq "$wname spec: the $key id on the maintainer list refuses, with a fresh reaction" "refused author: spec comment 777 is by $wtxt and the id of the declared $key is on the maintainer list/3" "$out/$rc"
    case "$key" in
      reviewer_app) idapp strapp "$DEVJ" '"acme-review[bot]"' null; idapp fracapp "$DEVJ" '{"login":"acme-review[bot]","id":2002.5}' null; idapp expapp "$DEVJ" '{"login":"acme-review[bot]","id":2.002e3}' null ;;
      *) idapp strapp "$DEVJ" null '"acme-loop[bot]"'; idapp fracapp "$DEVJ" null '{"login":"acme-loop[bot]","id":2003.5}'; idapp expapp "$DEVJ" null '{"login":"acme-loop[bot]","id":2.003e3}' ;;
    esac
    mrd "$tmp/ident-strapp.json" "$tmp/rx-fresh.tsv" "$wfile"
    assert_eq "$wname spec: a $key that is a bare string is unreadable" "unreadable author: spec comment 777 is by $wtxt and the declared $key is neither null nor a well-formed entry/3" "$out/$rc"
    mrd "$tmp/ident-fracapp.json" "$tmp/rx-fresh.tsv" "$wfile"
    assert_eq "$wname spec: a $key with a fractional id is unreadable" "unreadable author: spec comment 777 is by $wtxt and the declared $key is neither null nor a well-formed entry/3" "$out/$rc"
    mrd "$tmp/ident-expapp.json" "$tmp/rx-fresh.tsv" "$wfile"
    assert_eq "$wname spec: an exponent-spelled $key id on the maintainer list is refused by the numeric comparison" "refused author: spec comment 777 is by $wtxt and the id of the declared $key is on the maintainer list/3" "$out/$rc"
  done
  idapp both "$DEVJ" "$REVJ" "$LOOPJ"
  mrd "$tmp/ident-both.json" "$tmp/rx-fresh.tsv" "$wfile"
  assert_eq "$wname spec: both Apps on the list is still one line, naming reviewer_app" "refused author: spec comment 777 is by $wtxt and the id of the declared reviewer_app is on the maintainer list/3" "$out/$rc"
  idapp apps_off '{"login":"acme-dev[bot]","id":2001}' '{"login":"acme-review[bot]","id":3002}' '{"login":"acme-loop[bot]","id":3003}'
  mrd "$tmp/ident-apps_off.json" "$tmp/rx-fresh.tsv" "$wfile"
  assert_eq "$wname spec: all three Apps off the list pass with a fresh reaction" "pass/0" "$out/$rc"
  if [ "$wname" = maint ]; then
    idapp apps_null null null null
    mrd "$tmp/ident-apps_null.json" "$tmp/rx-fresh.tsv" "$wfile"
    assert_eq "$wname spec: all three Apps null pass with a fresh reaction" "pass/0" "$out/$rc"
  fi
done
# A malformed maintainer list is still reported, not an evaluator failure, when an App is well formed.
printf '{"maintainer":[{"login":"alice-dev","id":1001},"bob"],"dev_app":{"login":"acme-dev[bot]","id":2001},"reviewer_app":null,"loop_app":null}\n' >"$tmp/ident-malfm.json"
mrd "$tmp/ident-malfm.json" "$tmp/rx-fresh.tsv" "$tmp/c-alice.json"
assert_eq "maintainer spec: a malformed maintainer list with a well-formed dev_app is reported, not an evaluator failure" "refused author: spec comment 777 is by a declared maintainer and the maintainer list has a malformed entry, so no maintainer can approve it/3" "$out/$rc"
# reviewer_app written 2002.0 is not an exact integer: unreadable (jq 1.7 keeps the literal).
idapp revflt "$DEVJ" '{"login":"acme-review[bot]","id":2002.0}' null
mrd "$tmp/ident-revflt.json" "$tmp/rx-fresh.tsv"
if [ "$(jq -nc '1001.0 | tojson')" = '"1001.0"' ]; then
  assert_eq "maintainer spec: a reviewer_app id written 2002.0 is unreadable" "unreadable author: spec comment 777 is by a declared maintainer and the declared reviewer_app is neither null nor a well-formed entry/3" "$out/$rc"
else
  echo "SKIP - this jq does not keep number literals; the 2002.0 fixture needs jq 1.7 or later" >&2
fi
# A dev-App author whose dev_app id is written 2001.0 (the author's id 2001) now reaches the dev_app U line.
printf '{"maintainer":[{"login":"alice-dev","id":1001},{"login":"bob","id":1002}],"dev_app":{"login":"acme-dev[bot]","id":2001.0},"reviewer_app":null,"loop_app":null}\n' >"$tmp/ident-dev20010.json"
mrd "$tmp/ident-dev20010.json" "$tmp/rx-fresh.tsv" "$tmp/c-dev.json"
if [ "$(jq -nc '1001.0 | tojson')" = '"1001.0"' ]; then
  assert_eq "dev-App spec: a dev_app id written 2001.0 is unreadable" "unreadable author: spec comment 777 is by the declared dev_app and the declared dev_app is neither null nor a well-formed entry/3" "$out/$rc"
else
  echo "SKIP - this jq does not keep number literals; the 2001.0 fixture needs jq 1.7 or later" >&2
fi

printf '{"id":777,"author_association":"CONTRIBUTOR","user":{"login":"bob","id":1002},"issue_url":"https://api.github.com/repos/glunk-works/claude-workbench/issues/320"}' >"$tmp/c-ok-noupd.json"
mrd "$tmp/ident-map.json" "$tmp/rx-fresh.tsv" "$tmp/c-ok-noupd.json"
assert_eq "maintainer spec: no updated_at is unreadable, with the role-free line" "unreadable author: spec comment 777 has no well-formed updated_at/3" "$out/$rc"

IDENT="$tmp/ident-map.json" disp "$tmp/rules.json" "$tmp/i-maint.json" -
assert_eq "no spec comment under a map is refused" "refused author: no spec comment was supplied, and under an identities map the issue body is never the spec/3" "$out/$rc"

# preflight.sh resolves spec-reaction.sh from its own location only.
mkdir -p "$tmp/lone/scripts/loop"
cp "$script" "$tmp/lone/scripts/loop/preflight.sh"
lone() { set +e; out=$(bash "$tmp/lone/scripts/loop/preflight.sh" github-dispatch --rules "$tmp/rules.json" --identities "$tmp/ident-map.json" --issue "$tmp/i-maint.json" --issue-number 320 --spec-comment "$tmp/c-dev.json" --spec-comment-id 777 --spec-reactions "$tmp/rx-ok.tsv" 2>"$tmp/err"); rc=$?; set -e; }
lone
assert_eq "no spec-reaction.sh beside the script is a usage fault" "/2" "$out/$rc"
mkdir -p "$tmp/lone/plugins/way-of-working/bin"
printf '#!/bin/sh\nexit 2\n' >"$tmp/lone/plugins/way-of-working/bin/spec-reaction.sh"
lone
assert_eq "a spec-reaction.sh that exits non-zero is unreadable" "$UNJ/3" "$out/$rc"
printf '#!/bin/sh\necho maybe\n' >"$tmp/lone/plugins/way-of-working/bin/spec-reaction.sh"
lone
assert_eq "a spec-reaction.sh that prints another word is unreadable" "$UNJ/3" "$out/$rc"
printf '#!/bin/sh\necho approved\n' >"$tmp/lone/plugins/way-of-working/bin/spec-reaction.sh"
lone
assert_eq "the stub that prints approved passes (the call is the only judge)" "pass/0" "$out/$rc"
lonem() { set +e; out=$(bash "$tmp/lone/scripts/loop/preflight.sh" github-dispatch --rules "$tmp/rules.json" --identities "$tmp/ident-map.json" --issue "$tmp/i-maint.json" --issue-number 320 --spec-comment "$tmp/c-ok.json" --spec-comment-id 777 --spec-reactions "$tmp/rx-empty.tsv" 2>"$tmp/err"); rc=$?; set -e; }
lonem
assert_eq "maintainer spec: the stub that prints approved passes (the call is the only judge)" "pass/0" "$out/$rc"
printf '#!/bin/sh\nexit 2\n' >"$tmp/lone/plugins/way-of-working/bin/spec-reaction.sh"
lonem
assert_eq "maintainer spec: a spec-reaction.sh that exits non-zero is unreadable" "$MUNJ/3" "$out/$rc"

set +e; out=$(cd "$root_dir/scripts/loop" && bash preflight.sh github-dispatch --rules "$tmp/rules.json" --identities "$tmp/ident-map.json" --issue "$tmp/i-maint.json" --issue-number 320 --spec-comment "$tmp/c-dev.json" --spec-comment-id 777 --spec-reactions "$tmp/rx-ok.tsv" 2>"$tmp/err"); rc=$?; set -e
assert_eq "a slash-less BASH_SOURCE[0] is a usage fault" "/2" "$out/$rc"

# --- github-push fixtures ----------------------------------------------------------------------
REPO=glunk-works/claude-workbench
cat >"$tmp/inst.json" <<EOF
{"total_count":1,"repositories":[{"full_name":"glunk-works/claude-workbench"}]}
EOF
cat >"$tmp/rs-push.json" <<EOF
[{"id":1,"current_user_can_bypass":"never"},{"id":2,"current_user_can_bypass":"never"}]
EOF
cat >"$tmp/app.json" <<EOF
{"slug":"glunk-loop"}
EOF

push() { # installation rulesets app loopid [rules]
  run github-push --installation "$1" --repo "$REPO" --rules "${5:-$tmp/rules.json}" --rulesets "$2" --app "$3" --loop-identity "$4"
}

push "$tmp/inst.json" "$tmp/rs-push.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_eq "push: good inputs pass" "pass/0" "$out/$rc"
push "$tmp/inst.json" "$tmp/rs-push.json" "$tmp/app.json" 'Glunk-Loop[BOT]'
assert_eq "push: the identity compares case-insensitively" "pass/0" "$out/$rc"
run github-push --installation "$tmp/inst.json" --repo GLUNK-WORKS/Claude-Workbench --rules "$tmp/rules.json" --rulesets "$tmp/rs-push.json" --app "$tmp/app.json" --loop-identity 'glunk-loop[bot]'
assert_eq "push: the repo compares case-insensitively" "pass/0" "$out/$rc"

jq -c '.total_count=2|.repositories+=[{"full_name":"glunk-works/other"}]' "$tmp/inst.json" >"$tmp/inst-two.json"
push "$tmp/inst-two.json" "$tmp/rs-push.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_has "push: a second repository is refused" "$out" "refused installation"
jq -c '.repositories[0].full_name="glunk-works/other"' "$tmp/inst.json" >"$tmp/inst-other.json"
push "$tmp/inst-other.json" "$tmp/rs-push.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_has "push: another single repository is refused" "$out" "refused installation"
jq -c '.total_count=0|.repositories=[]' "$tmp/inst.json" >"$tmp/inst-zero.json"
push "$tmp/inst-zero.json" "$tmp/rs-push.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_has "push: no repository is refused" "$out" "refused installation"
jq -c '.total_count=2' "$tmp/inst.json" >"$tmp/inst-trunc.json"
push "$tmp/inst-trunc.json" "$tmp/rs-push.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_has "push: a truncated list is unreadable" "$out" "unreadable installation"
printf '{"message":"Bad credentials"}' >"$tmp/inst-err.json"
push "$tmp/inst-err.json" "$tmp/rs-push.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_has "push: an API error body is unreadable" "$out" "unreadable installation"

for v in always pull_requests_only exempt; do
  jq -c ".[1].current_user_can_bypass=\"$v\"" "$tmp/rs-push.json" >"$tmp/rs-v.json"
  push "$tmp/inst.json" "$tmp/rs-v.json" "$tmp/app.json" 'glunk-loop[bot]'
  assert_has "push: current_user_can_bypass $v is refused" "$out" "refused can-bypass"
done
jq -c 'del(.[0].current_user_can_bypass)' "$tmp/rs-push.json" >"$tmp/rs-v.json"
push "$tmp/inst.json" "$tmp/rs-v.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_has "push: no current_user_can_bypass is unreadable" "$out" "unreadable can-bypass"
jq -c 'del(.[1])' "$tmp/rs-push.json" >"$tmp/rs-v.json"
push "$tmp/inst.json" "$tmp/rs-v.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_has "push: an applicable ruleset with no document is unreadable" "$out" "unreadable can-bypass"
push "$tmp/inst.json" "$tmp/rs-push.json" "$tmp/app.json" 'glunk-loop[bot]' "$tmp/r-none.json"
assert_has "push: no applicable ruleset is refused" "$out" "refused can-bypass"

push "$tmp/inst.json" "$tmp/rs-push.json" "$tmp/app.json" 'someone-else[bot]'
assert_has "push: a different bot login is refused" "$out" "refused identity"
push "$tmp/inst.json" "$tmp/rs-push.json" "$tmp/app.json" 'glunk-loop'
assert_has "push: a login without [bot] is refused" "$out" "refused identity"
push "$tmp/inst.json" "$tmp/rs-push.json" "$tmp/app.json" '-'
assert_has "push: a null loop_identity is refused" "$out" "refused identity"
printf '{"message":"A JSON web token could not be decoded"}' >"$tmp/app-err.json"
push "$tmp/inst.json" "$tmp/rs-push.json" "$tmp/app-err.json" 'glunk-loop[bot]'
assert_has "push: an /app error body is unreadable" "$out" "unreadable identity"

# --- round-1 additions: shapes that must still pass, duplicates, size ----------------------------
for okcase in \
  'group-ok|.[0].Config.User="loop:loop"' \
  'cap-add-empty|.[0].HostConfig.CapAdd=[]' \
  'cap-add-absent|del(.[0].HostConfig.CapAdd)' \
  'tmpfs|.[0].Mounts+=[{"Type":"tmpfs","Destination":"/tmp"}]' \
  'binds-empty|.[0].HostConfig.Binds=[]'
do
  name=${okcase%%|*}; filt=${okcase#*|}
  mut "ok-$name.json" "$tmp/session.json" "$filt"
  cont "$tmp/ok-$name.json" "$tmp/network.json"
  assert_eq "container: $name still passes" "pass/0" "$out/$rc"
done

mut p-nonet.json "$tmp/proxy.json" 'del(.[0].NetworkSettings)'
cont "$tmp/session.json" "$tmp/network.json" "$tmp/p-nonet.json"
assert_has "container: a proxy with no Networks is unreadable" "$out" "unreadable proxy-network"

# argv size: many proxies and a big session must not hit the command-line limit
jq -c '.[0].Config.Labels={"k":("x"*40000)}' "$tmp/proxy.json" >"$tmp/p-big.json"
cont "$tmp/session.json" "$tmp/network.json" "$tmp/p-big.json" "$tmp/p-big.json"
assert_eq "container: 80 KB of proxy inspect still evaluates" "pass/0" "$out/$rc"

jq -c '.pull_request={"url":"x"}' "$tmp/issue.json" >"$tmp/i-pr.json"
disp "$tmp/rules.json" "$tmp/i-pr.json" -
assert_has "dispatch: a pull request is not a task issue" "$out" "unreadable author"
jq -c '.issue_url="https://api.github.com/repos/glunk-works/claude-workbench/issues/321"' "$tmp/comment.json" >"$tmp/c-other.json"
disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/c-other.json"
assert_has "dispatch: a spec comment on another issue is unreadable" "$out" "unreadable author"
jq -c '.issue_url="https://api.github.com/repos/glunk-works/claude-workbench/issues/3200"' "$tmp/comment.json" >"$tmp/c-prefix.json"
disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/c-prefix.json"
assert_has "dispatch: issue 3200 is not issue 320" "$out" "unreadable author"
jq -c 'del(.issue_url)' "$tmp/comment.json" >"$tmp/c-nourl.json"
disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/c-nourl.json"
assert_has "dispatch: a spec comment with no issue_url is unreadable" "$out" "unreadable author"
jq -c '.body=("x"*60000)' "$tmp/comment.json" >"$tmp/c-big.json"
disp "$tmp/rules.json" "$tmp/issue.json" "$tmp/c-big.json"
assert_eq "dispatch: a 60 KB spec comment still evaluates" "pass/0" "$out/$rc"

jq -c '. + [{"id":2,"current_user_can_bypass":"always"}]' "$tmp/rs-push.json" >"$tmp/rs-pdup.json"
push "$tmp/inst.json" "$tmp/rs-pdup.json" "$tmp/app.json" 'glunk-loop[bot]'
assert_has "push: a ruleset supplied twice is unreadable" "$out" "unreadable can-bypass"

printf '{}' >"$tmp/with space.json"
run github-push --installation "$tmp/nope
x.json" --repo "$REPO" --rules "$tmp/rules.json" --rulesets "$tmp/rs-push.json" --app "$tmp/app.json" --loop-identity x
assert_has "a missing file is named without a stray character" "$out" "unreadable input: nope?x.json is missing"

# --- usage faults ------------------------------------------------------------------------------
run
assert_eq "no mode is a usage fault" 2 "$rc"
run bogus
assert_eq "an unknown mode is a usage fault" 2 "$rc"
run container --session "$tmp/session.json" --network "$tmp/network.json" --expect-network "$NET"
assert_eq "container with no proxy is a usage fault" 2 "$rc"
run github-dispatch --rules "$tmp/rules.json" --identities "$tmp/ident-null.json" --issue "$tmp/issue.json" --issue-number 320
assert_eq "dispatch with neither a spec comment nor --no-spec-comment is a usage fault" 2 "$rc"
run github-dispatch --rules "$tmp/rules.json" --rulesets "$tmp/rs-push.json" --identities "$tmp/ident-null.json" --issue "$tmp/issue.json" --issue-number 320 --no-spec-comment
assert_eq "dispatch with --rulesets is a usage fault (the bypass read is github-push's)" 2 "$rc"
run github-dispatch --rules "$tmp/rules.json" --app-id $APP --identities "$tmp/ident-null.json" --issue "$tmp/issue.json" --issue-number 320 --no-spec-comment
assert_eq "dispatch with --app-id is a usage fault" 2 "$rc"
run github-push --installation "$tmp/inst.json" --repo noslash --rules "$tmp/rules.json" --rulesets "$tmp/rs-push.json" --app "$tmp/app.json" --loop-identity x
assert_eq "a repo with no slash is a usage fault" 2 "$rc"

if [ "$fail" -ne 0 ]; then exit 1; fi
echo "all preflight fixtures passed"
