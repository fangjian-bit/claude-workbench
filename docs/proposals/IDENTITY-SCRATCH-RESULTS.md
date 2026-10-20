# Identity model proof on wb-ruleset-scratch (#376)

Proof cases a-k from #376, run against `glunk-works/wb-ruleset-scratch` with the three
WB-D24 Apps (`glunk-dev`, `glunk-review`, `glunk-admin`) and the rulesets saved in
[docs/identity/scratch-rulesets/](../identity/scratch-rulesets/). Five sessions. Raw API output
follows the summary, in the order it was run. Each entry names the identity it ran as.

## Summary

| Case | Claim | Result |
|---|---|---|
| a | dev App can't self-approve or self-merge | **Pass.** Approve: 422 "Can not approve your own pull request". Merge: 405 "Waiting on code owner review". |
| b | a push dismisses an approval | **Pass.** After a dev-App push the approval reads `DISMISSED`, `reviewDecision: REVIEW_REQUIRED` (PR 1, PR 8). |
| c | auto-merge fires after the approval | **Pass with one stall, filed as #432.** Fired 16s (PR 4), 10s (PR 7) and 4s (PR 8) after the approval. PR 1 read `CLEAN`/`APPROVED` with auto-merge armed for 3+ minutes and never fired; a direct dev-App merge pinned to the head then succeeded. PR 8 repeated PR 1's exact sequence and fired. Not a clean run: PR 4's head moved after arming (JaredGroves-603's update-branch merge, 962e566), and auto-merge still fired. So `expectedHeadOid` is apparently checked only when auto-merge is enabled, and the approval dismissal is the guard after that. That account then approved its own push and the PR merged under `require_last_push_approval`, so a base-merge apparently isn't a "reviewable push". Both are resolved in session 3 (items 1 and 2). |
| d | a fake status is ignored, a real one counts | **Pass, for a user-posted fake.** With no status: "Required status check is expected". With a `success` posted by a user: "was not set by the expected GitHub app". The Actions-posted status satisfied the rule on every merged PR. Caveat: the combined-status API reads `success` after the fake, so only the ruleset, not that read, tells the sources apart. A fake from another App is refused too (session 3, item 6). The pin is to GitHub Actions itself, so any workflow run counts. The dev App can edit scripts CI runs (not workflow files), so a required check is no integrity barrier against it; the code-owner review is. |
| e | the second code owner's approval merges | **Pass.** JaredGroves-603's approval made PR 5 `CLEAN` and it merged. Precondition: the owner needs write access. Before the invite, the merge message named only Seuss27; after it, "JaredGroves-603 and/or Seuss27". So each repo needs that second login with write, which makes it a full approve, merge and push credential (session 1's void case f is that credential being used by an agent). An owner approving their own content push is blocked (session 3, item 1). |
| f | the reviewer App's COMMENT satisfies a reviewer-ID gate; its approval doesn't count; it can't merge or push | **Partial (re-run).** COMMENT recorded as `glunk-review[bot]`, id 339841158, type Bot. Its APPROVE is accepted but changes nothing (`REVIEW_REQUIRED`, merge still "Waiting on code owner review"). Merge: 403. Push: 403. The scratch repo has no reviewer-ID CI gate, so what is proven is the stable attribution a gate would key on, not the gate itself. "Doesn't count" was measured with CODEOWNERS covering `*`; an uncovered path and the App's other `pull_requests: write` powers were tested in session 3 (items 3 and 4). The session-1 attempt is void (see its note). |
| g | revoking a token kills it | **Consistent, not conclusive.** After `wow-admin --revoke` the same token gets 401 "Bad credentials". No success with that same token just before the revoke is recorded; whether the earlier admin-token calls in case e used the same token is not recorded, and an expired token also gets 401. The end-to-end run is in session 3 (item 5). |
| h | no workflow or release-tag writes | **Pass after a scratch-config fix, filed as #433 for the other repos.** Workflow file: 403. Moving or deleting a `v*` tag: refused by the ruleset. Creating a `v*` tag or a release succeeded until a `creation` rule was added to `wb-tags` (as claude-workbench's `release-tag-creation` already has), after which both were refused: the tag with 422 "Reference update failed", the release with "Cannot create ref due to creations being restricted". Editing, deleting or adding assets to an existing release is not blocked (session 3, item 7); with GitHub's immutable-releases setting on, asset changes are refused and notes edits and release deletion remain (session 4, item 9). |
| i | the App token reaches only its installation | **Pass.** `installation/repositories` lists only the scratch repo. `.permissions` on the repo reads all `false` for an App token, so it is not a reach signal. The installation covers only this repo, so this didn't separate `mint.sh`'s `repositories` narrowing from installation scope; session 3 (item 8) did. |
| j | update-branch works for the dev App | **Pass.** Works with `allow_update_branch: false` (that setting only hides the UI button). 422 "no new commits" when main hasn't moved. |
| k | auto-merge on an already-mergeable PR | **Refused by GitHub, handled by `gh`.** The raw mutation fails with "Pull request is in clean status", as documented. `gh pr merge --auto` merges immediately in that state (`isImmediatelyMergeable`), so `ship` never sees the refusal. Noted on #386, whose "not armed" path won't occur. |

Also observed: the dev App gets 403 on the rule-suites API, so it cannot read why a rule
blocked; the merge error text is the only explanation it sees.

## Session 3 (#435): the questions #376 left open

Eight items, run on 2026-10-09 against the same repo and Apps. The maintainer acted as the
code-owner approver (Seuss27) and minted the admin tokens; JaredGroves-603 was not needed.
None of items 1-3 weakens the merge gate, so no blocking issue was filed.

| Item | Question | Result |
|---|---|---|
| 1 | Does last-push approval apply to a code owner's own push, and to a base merge? | **Owner's content push: blocked.** PR 11: Seuss27 pushed a content commit and approved it; the dev App's merge was refused with "New changes require approval from someone other than Seuss27 because they were the last pusher." **Dev App's merge push with an extra change: approval dismissed.** PR 12: a merge commit with parents (PR head, `main`) and one extra file moved the approval to `DISMISSED` and `reviewDecision` to `REVIEW_REQUIRED`; the merge was refused ("Waiting on code owner review"). **Approver's own pure base merge: not a reviewable push.** On PR 12 Seuss27 used Update branch, then approved the result, and the PR read `CLEAN`, as on PR 4 with the other owner. Not tested: an approver pushing a merge commit that carries extra changes. |
| 2 | After auto-merge is armed, is anything but the approval a guard? | **No.** PR 13: auto-merge armed pinned to commit A (68fb676), then the dev App (a writer) pushed commit B (7748a12). The PR stayed armed and `BLOCKED` on `REVIEW_REQUIRED`; after Seuss27 approved B it merged at B, not A. The pin is checked only when auto-merge is enabled. |
| 3 | Is the reviewer App's approval ignored on a path no CODEOWNERS entry covers? | **Yes.** CODEOWNERS was narrowed to `/owned/` (PR 9). On PR 10 (path `free/`), the reviewer App's APPROVE was recorded as `APPROVED` but `reviewDecision` stayed `REVIEW_REQUIRED` and the merge was refused. After Seuss27's approval the same PR read `CLEAN`, consistent with the count rule wanting a reviewer with write access, which the bot is not. |
| 4 | What else can the reviewer App do with `pull_requests: write`? | **It can:** dismiss a human approval (PR 12 went from `CLEAN` to `BLOCKED`), edit a PR's title, body and base, and close and reopen a PR. **It cannot:** disable auto-merge ("Resource not accessible by integration"). None is a merge path. Dismissal can stall a merge and the edits can mislead a human reader, so they are accepted residuals in WB-D24. |
| 5 | Revoke, end to end | **Pass.** An admin token read the rulesets, `wow-admin --revoke` reported success, and the same token then got 401 "Bad credentials" on two calls, all inside its hour. The first attempt did not keep a copy of the token and could not show the 401; the run listed here is the second. |
| 6 | A fake status from another App | **Refused.** With `glunk-dev` temporarily granted `statuses: write`, it posted `scratch/status=success` on PR 14's head (creator `glunk-dev[bot]`, type Bot). The merge was refused with `Required status check "scratch/status" was not set by the expected GitHub app.` The combined-status API reads `success` regardless. |
| 7 | Release writes besides tag creation | **Not blocked.** As the dev App: creating a draft release for a new `v*` tag, editing an existing `v*` release, uploading an asset to it, deleting the asset and deleting the release all succeeded (the tag stayed). Publishing the draft was refused by the creation rule (422, "Cannot create ref due to creations being restricted"). So the dev App can rewrite or remove release notes and assets of a published release. |
| 8 | Does `repositories` narrowing hold with two repos installed? | **Yes for `glunk-dev` and `glunk-admin`.** With `wb-ruleset-scratch-2` added to the installations, a token minted for one repo lists only that repo in `installation/repositories`, writes to the other get 404 or 403, and a request for a repo outside the installation is refused with 422 at mint. The reviewer App's narrowing was not tested separately there; session 4 (item 12) did. Also found: the admin token created `wb-ruleset-scratch-2` through `POST /orgs/glunk-works/repos`, although it is scoped to one repo and could not read the repo it made. |

Follow-ups this surfaced, none a merge-gate weakening:

- WB-D24's accepted residuals gain the reviewer App's powers (item 4) and an admin token's
  ability to create org repositories (item 8).
- The dev App's release writes (item 7) are an integrity gap for published release assets
  and notes. Filed separately for a restrict-or-accept decision.

## Configuration changes made during session 3

- **CODEOWNERS** on the scratch repo was narrowed from `*` to `/owned/ @Seuss27
  @JaredGroves-603` (PR 9), so that item 3 had a path no entry covers.
- **`wb-ruleset-scratch-2`** was created (private) by an admin token, and added to the
  installations of `glunk-dev`, `glunk-admin` and `glunk-review`.
- **`glunk-dev`** was granted `statuses: write` for item 6 only, then reverted by the
  maintainer.

## Calls made outside the recording helper

The session-3 helper (`rec.sh`) records the identity and the raw output, and refuses an empty
token or one that cannot list its installation repositories. These steps ran without it:

- `mint.sh` for the dev App with `statuses=write`, before the grant: HTTP 422, "The level of
  access for permissions requested are not granted to this installation."
- Item 8 mints (`mint.sh`, dev App, installation 169399440): `--repos wb-ruleset-scratch`
  and `--repos wb-ruleset-scratch-2` minted; `--repos claude-workbench` failed with HTTP 422,
  "There is at least one repository that does not exist or is not accessible to the parent
  installation."
- The reviewer App's first title edit was refused by the helper because its reach probe got a
  502; the retry is recorded below.
- Item 1's Update branch click on PR 12 was the maintainer's, in the browser; its effect is
  read back below (commit a5cd01f, author "Jared Groves", parents `ee6cb40` and `57407c8`).
- The two post-revoke calls in item 5 bypass the helper's reach guard on purpose, because the
  token is expected to fail it; they are labelled in the output.
- Reading "repo 1 is public" explains why a token narrowed to repo 2 could read repo 1's
  README; the write to repo 1 from that token returned 403.

## Configuration changes made during the proof

- **glunk-review** was installed with `pull_requests: write` only, as #372 specified, but `wow-review-mint` (#374) requests `contents`, `checks` and `statuses` read as
  well, so no reviewer token could be minted. The App and its installation now hold
  `contents: read, checks: read, statuses: read, pull_requests: write`. WB-D24 is amended to
  match.
- **glunk-admin** gained `contents: write` and `pull_requests: write` beside the specified
  administration, workflows, environments and actions, because `wow-admin`'s default mint
  requests them. `--perms` replaces that default set for one mint, either way.
- **JaredGroves-603** was invited to the scratch repo with write access (case e).
- **wb-tags** gained a `creation` rule (case h), made through an admin-mode token. The ruleset's
  history records the actor as Bot 339842227, `glunk-admin[bot]`.

## Side effects of the void session-1 case f

Four calls labelled "review App token" ran as JaredGroves-603, a human code owner, not the
reviewer App. They approved and merged PR 6 (`merged_by` JaredGroves-603) and pushed
`f-reviewer.txt` to `case-f` (commit bad72e8, authored by JaredGroves-603). Only the scratch
repo was touched.

How the token got there is not established. The likeliest path: the session-1 helper got its
"refuse an empty token" guard in an edit last saved about 15 seconds after the last case-f call, so the reviewer token
probably came out empty. `gh` treats an empty `GH_TOKEN` as unset and falls back to the
host's stored login. That fail-open is filed as #436. The session-2 helper also refuses any
token that cannot list its installation's repositories, which a user token cannot.

## Session 4 (#439): release writes, an approver's merge commit, the reviewer App's narrowing

Run on 2026-10-09 against the same repo and Apps. The maintainer enabled the setting, added a
temporary bypass, pushed as the approver and minted tokens; I probed as `glunk-dev` and
`glunk-review`.

| Item | Question | Result |
|---|---|---|
| 9 | Does GitHub's immutable-releases setting restrict the dev App's release writes? | **Partly.** With the setting on, a published release reads `immutable: true`. As the dev App, uploading an asset (422 "Cannot upload assets to an immutable release"), deleting an asset (422) and deleting the tag (422, the `wb-tags` ruleset) are refused. **Still allowed:** editing the release's notes and title, and deleting the release itself. Deleting it leaves the tag in place, and the tag name cannot be reused: publishing a draft for it is refused (422 "tag_name was used by an immutable release"). Creating a draft release is still allowed; publishing one for a new tag is refused by the creation rule. Not shown: whether a release edit can retarget the tag, because `main` had not moved and the edit was a no-op. The setting applies only to releases published after it is on. |
| 10 | Does `release.yml`'s shape still publish? | **Yes.** `gh release create v0.0.2 --target <sha> --title --notes-file`, one call and no assets, published as immutable on the scratch repo. `release.yml` attaches no assets, so there is nothing to add after publishing. |
| 11 | An approver pushes a merge commit that carries an extra change | **Blocked.** PR 15: the dev App opened it with one commit and Seuss27 approved. Seuss27 then pushed a merge commit (parents: the PR head and a side branch) that added `free/extra-in-merge.txt`, present in neither parent. The approval moved to `DISMISSED`, `reviewDecision` to `REVIEW_REQUIRED`, and the dev App's merge was refused ("New changes require approval from someone other than the last pusher"). Seuss27's second approval was recorded as `APPROVED` on the new head but did not count: the merge was refused again, now naming Seuss27 as the last pusher. After an approver's push the other code owner has to approve. |
| 12 | Does the reviewer App's `repositories` narrowing hold with two repos installed? | **Yes.** `wb-ruleset-scratch-3` (private) was added to the `glunk-review` installation. A token minted for `wb-ruleset-scratch` lists only that repo, cannot read `-3` (404) and can edit a PR on its own repo. A token minted for `-3` lists only `-3`, reads it, and is refused (403) when it edits a PR on `wb-ruleset-scratch`. The scratch repo is public, so reading it needs no grant. The write probe on `-3` was not run: that repo is empty and has no PR. |

Follow-ups: WB-D24's release residual narrows to notes, title and deletion of a release
(the code, the tag and any assets stay), and immutable releases joins the per-repo cutover
settings.

## Configuration changes made during session 4

- **Immutable releases** enabled on `wb-ruleset-scratch` by the maintainer. `v0.0.1` (one asset)
  stays published as an immutable release; `v0.0.2` was deleted in item 9 and its tag remains.
- **`wb-tags`** had a Repository admin bypass added by the maintainer, so Seuss27 could publish
  the two releases, and removed again before any dev-App probe.
- **`wb-ruleset-scratch-3`** created (private, empty) by the maintainer and added to the
  `glunk-review` installation. It stays until the maintainer deletes it.
- PR 14's title was edited by the reviewer token and restored to `item6`. PR 15 and its two
  branches were closed and deleted. `main` is unchanged at `57407c8`.

## Calls made outside the recording helper (session 4)

The helper refuses an empty token or one that cannot list its installation repositories.
These steps did not go through it:

- Publishing `v0.0.1` (draft, asset, publish) and `v0.0.2` (one `gh release create`) as the
  Seuss27 user token, with the maintainer's bypass in place. `v0.0.1` read `immutable: true`
  from the publish response.
- The maintainer's own steps: enabling the setting, the bypass, Seuss27's approvals and the
  merge-commit push on PR 15 (its effect is read back in item 11), creating the repo and adding
  it to the installation.
- The two minting scripts that ran `mint.sh` (dev App) and `wow-review-mint` (both repos).
- Reading `wb-ruleset-scratch` rulesets and PR state as Seuss27 while designing the case.

## Session 5 (#377): the same cases under a 603-Identity org ruleset

Run on 2026-10-09 against a private scratch repo in 603-Identity, with that org's own three Apps
(`603id-dev`, `603id-review`, `603id-admin`), one org ruleset and two repo rulesets. The ruleset
bodies are the saved ones in [docs/identity/scratch-rulesets/](../identity/scratch-rulesets/); the
org copy adds a `repository_name` include list naming only the scratch repo.

The maintainer registered and installed the Apps, and approved the PRs in the browser. I created
the repo and rulesets, minted the dev and reviewer tokens, and ran the probes through a recording
helper that refuses a token which cannot list its installation repositories (App tokens) or whose
login cannot be read (user tokens).

**No second code owner.** CODEOWNERS names one account, JaredGroves-603. The maintainer chose not
to buy a seat for a second owner that only an emergency would use, so case e (the second owner's
approval merges) was **not run**. Item 16 replaces it, and item 18 checks that the org rule can't
be weakened from inside a container. WB-D24's second-owner text needs a 603 amendment (follow-up
below).

| Item | Question | Result |
|---|---|---|
| 13 | (a) The dev App can't self-approve or self-merge under the org rule | **Pass.** PR 1: approve 422 "Can not approve your own pull request"; merge 405 "Waiting on code owner review from JaredGroves-603". |
| 14 | (b) A push dismisses the approval | **Pass.** PR 3: after the dev App pushed, GraphQL reads the review `DISMISSED` and `reviewDecision` `REVIEW_REQUIRED`. The REST review list still read `APPROVED` for the first seconds, so the dismissal is asynchronous. |
| 15 | (c) Auto-merge fires after the approval | **Pass, late both times.** Armed by the dev App, pinned to the head. PR 1: approved 14:11:22Z, merged 14:13:23Z (2 min 1 s), `clean` and unfired for the first minute. PR 4: approved 14:16:54Z and nothing fired; the maintainer deliberately re-approved at 14:17:19Z and it merged 14:17:37Z (18 s after the second approval, 43 s after the first). `merged_by` is the dev App both times, the approval appears only in the review list. A re-approval is something that happened before the merge, not a proven cause. With the stall in #432 that is three of four first approvals that didn't fire promptly. |
| 16 | (e, replaced) A maintainer-authored PR can't be approved or merged by its author | **Pass.** PR 2: self-approve 422 "Can not approve your own pull request"; merge 405 "New changes require approval from someone other than the last pusher" and the missing `scratch/status`. Without a second owner, a human-authored change in a 603 repo needs the maintainer to route it through the dev App, or to suspend the org ruleset in the browser. |
| 17 | Do App tokens read the org-sourced rules? | **Yes.** Dev and reviewer App tokens: `rules/branches/main` lists the `pull_request`, `deletion` and `non_fast_forward` rules with source "Organization" beside the repo's `required_status_checks`, and `repos/R/rulesets` lists the org ruleset with `source_type: Organization`. The org-path read of the ruleset (`orgs/603-Identity/rulesets/<id>`) is 403 for the dev App. |
| 18 | Can a repo-scoped admin token weaken the org approval rule? | **No.** With `administration=write` scoped to the scratch repo: org path read 403 and edit 403 "Resource not accessible by integration"; the repo path reads it (`source_type` Organization, `active`) but an edit returns 404. It still read `active` afterwards. Contrast: the same token renamed the repo's own `wb-checks` and the name was restored; all three rulesets read back unchanged. So admin mode in a container can weaken repo rulesets but not the org approval rule. |
| 19 | #443/#444: the host config is keyed by role (`dev`, `review`, `admin`) | **Pass.** Under `~/.config/603id-identity` the reviewer and dev tokens minted and listed only the scratch repo; the admin App minted with the passphrase (`contents=read`, then `administration=write`), listed only the scratch repo, and a revoked token got 401 "Bad credentials" (before and after output pasted by the maintainer, not in the raw log). The same checks passed earlier today on the glunk-works host config after its two keys were renamed. |

Follow-ups:
- WB-D24's second-owner text now carries a 603-Identity amendment (one code owner, break glass
  in the browser, human-wanted changes routed through the dev App), made in this PR.
- The item 15 timings are on #432: a second approval was followed by the merge in 18 s.

## Configuration changes made during session 5

- **Repo** `603-Identity/identity-ruleset-scratch`: private, auto-merge on, delete branch on merge on.
  `main` holds `.github/CODEOWNERS` (`* @JaredGroves-603`) and the `scratch-status` workflow. PRs 1
  and 4 merged (`main` is at `50abe9a`); PRs 2 and 3 were closed unmerged. All probe branches are
  deleted. The repo stays until the maintainer deletes it.
- **Rulesets**: org `wb-approval` (include list: this repo only, no bypass), repo `wb-checks` and
  `wb-tags`. `wb-checks` was renamed and restored in item 18.
- **Tokens**: reviewer, dev and two admin tokens minted. Both admin tokens were revoked and each
  got 401 afterwards; the dev and reviewer tokens expire within the hour.

## Calls made outside the recording helper (session 5)

- Creating the repo, its two files and the three rulesets, as JaredGroves-603 through a
  per-process token.
- The Apps' registration and installation, the host config, the passphrase mints and revokes, and
  all review approvals (PR 1, PR 3, PR 4 twice), which were the maintainer's.
- Reading the org's installation list to fill in the host config.

## Raw output, session 1 (2026-10-08 evening, UTC 2026-10-09 00:17-01:41)

#### i: reach probe -- .permissions on the repo as the dev App

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch --jq .permissions

```
{"admin":false,"maintain":false,"pull":false,"push":false,"triage":false}
```
exit: 0

#### i: reach probe -- installation repositories

as: dev App token
$ gh api installation/repositories --jq [.total_count,(.repositories|map(.full_name))]

```
[1,["glunk-works/wb-ruleset-scratch"]]
```
exit: 0

#### a: create branch case-a

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-a -f sha=fe67508bcb741339d974e22bf194a6f421c8ceed --jq .ref

```
refs/heads/case-a
```
exit: 0

#### a: commit a file on case-a

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-a.txt -f message=case a -f branch=case-a -f content=Y2FzZSBhCg== --jq .commit.sha

```
39c8020f8dd646d087adf9721f5b4dea0ad8cbd2
```
exit: 0

#### a: open PR

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case a -f head=case-a -f base=main --jq [.number,.state,.user.login]

```
[1,"open","glunk-dev[bot]"]
```
exit: 0

#### a: dev App approves its own PR

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/1/reviews -f event=APPROVE -f body=self approve

```
{"message":"Unprocessable Entity","errors":["Review Can not approve your own pull request"],"documentation_url":"https://docs.github.com/rest/pulls/reviews#create-a-review-for-a-pull-request","status":"422"}gh: Unprocessable Entity (HTTP 422)
```
exit: 1

#### a: dev App merges its own PR (no approval)

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/1/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from Seuss27.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from Seuss27.

 (HTTP 405)
```
exit: 1

#### a: PR 1 merge state after workflow

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/1 --jq [.mergeable,.mergeable_state,.merged]

```
[true,"blocked",false]
```
exit: 0

#### a: statuses on PR 1 head

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/case-a/status --jq [.state,(.statuses|map([.context,.state,.creator.login]))]

```
["success",[["scratch/status","success",null]]]
```
exit: 0

#### setup: CODEOWNERS location

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/contents/.github/CODEOWNERS --jq .content|@base64d

```
* @Seuss27 @JaredGroves-603
```
exit: 0

#### setup: CODEOWNERS (docs/)

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/contents/docs/CODEOWNERS --jq .path

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/contents#get-repository-content","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### d: required-check pin vs the workflow's status -- rule suites for PR 1 head

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/rulesets/rule-suites?ref=refs/heads/case-a&per_page=5 --jq .[]|[.evaluation_result,.result,.actor_name]

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/repos/rule-suites#list-repository-rule-suites","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### d: combined check state per GraphQL (required contexts)

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:1){mergeStateStatus reviewDecision commits(last:1){nodes{commit{statusCheckRollup{state contexts(first:10){nodes{__typename ... on StatusContext{context state isRequired(pullRequestNumber:1)}}}}}}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS","contexts":{"nodes":[{"__typename":"CheckRun"},{"__typename":"StatusContext","context":"scratch/status","state":"SUCCESS","isRequired":true}]}}}}]}}}}}
```
exit: 0

#### h: create branch case-g

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-g -f sha=fe67508bcb741339d974e22bf194a6f421c8ceed --jq .ref

```
refs/heads/case-g
```
exit: 0

#### h: write a workflow file on a branch

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/.github/workflows/evil.yml -f message=case g workflow -f branch=case-g -f content=bmFtZTogZXZpbApvbjogcHVzaApqb2JzOiB7fQo= --jq .commit.sha

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/repos/contents#create-or-update-file-contents","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### h: create tag v-case-g

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/tags/v-case-g -f sha=fe67508bcb741339d974e22bf194a6f421c8ceed --jq .ref

```
refs/tags/v-case-g
```
exit: 0

#### h: move the tag (force update)

as: dev App token
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/git/refs/tags/v-case-g -f sha=39c8020f8dd646d087adf9721f5b4dea0ad8cbd2 -F force=true --jq .ref

```
{"message":"Repository rule violations found\n\nCannot update this protected ref.\n\n","documentation_url":"https://docs.github.com/rest/git/refs#update-a-reference","status":"422"}gh: Repository rule violations found

Cannot update this protected ref.

 (HTTP 422)
```
exit: 1

#### h: delete the tag

as: dev App token
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/git/refs/tags/v-case-g

```
{"message":"Repository rule violations found\n\nCannot delete this tag\n\n","documentation_url":"https://docs.github.com/rest/git/refs#delete-a-reference","status":"422"}gh: Repository rule violations found

Cannot delete this tag

 (HTTP 422)
```
exit: 1

#### h: create a release (tag write via releases)

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/releases -f tag_name=v-case-g-rel -f target_commitish=main --jq .tag_name

```
v-case-g-rel
```
exit: 0

#### d: create branch case-d

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-d -f sha=fe67508bcb741339d974e22bf194a6f421c8ceed --jq .ref

```
refs/heads/case-d
```
exit: 0

#### d: commit with [skip ci] so no real status is posted

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-d.txt -f message=case d [skip ci] -f branch=case-d -f content=Y2FzZSBkCg== --jq .commit.sha

```
7caa2052adf05715188a5ebda737e5a390dce562
```
exit: 0

#### d: open PR 2

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case d -f head=case-d -f base=main --jq [.number,.head.sha]

```
[2,"7caa2052adf05715188a5ebda737e5a390dce562"]
```
exit: 0

#### d: PR 2 statuses before any fake (expect none)

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/case-d/status --jq [.state,(.statuses|length)]

```
["pending",0]
```
exit: 0

#### d: PR 2 required-check state before fake

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:2){mergeStateStatus commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}}}}
```
exit: 0

#### d: merge PR 2 before fake

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/2/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from Seuss27.\n\nRequired status check \"scratch/status\" is expected.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from Seuss27.

Required status check "scratch/status" is expected.

 (HTTP 405)
```
exit: 1

#### d: post a FAKE scratch/status=success on PR 2's head from a non-Actions source (identity not recorded)

as: none (identity not recorded; superseded by the maintainer-token entry below)
$ gh api repos/glunk-works/wb-ruleset-scratch/statuses/7caa2052adf05715188a5ebda737e5a390dce562 -f state=success -f context=scratch/status -f description=fake, not from Actions --jq [.context,.state,.creator.login]

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/commits/statuses#create-a-commit-status","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### d: statuses after the fake

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/case-d/status --jq [.state,(.statuses|map([.context,.state,.creator.login]))]

```
["pending",[]]
```
exit: 0

#### d: merge PR 2 after the fake

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/2/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from Seuss27.\n\nRequired status check \"scratch/status\" is expected.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from Seuss27.

Required status check "scratch/status" is expected.

 (HTTP 405)
```
exit: 1

#### d: post a FAKE scratch/status=success on PR 2's head from a non-Actions source (the maintainer's user account)

as: maintainer (Seuss27 user token, not an App)
$ gh api repos/glunk-works/wb-ruleset-scratch/statuses/7caa2052adf05715188a5ebda737e5a390dce562 -f state=success -f context=scratch/status -f description=fake, not from Actions --jq [.context,.state,.creator.login]

```
["scratch/status","success","Seuss27"]
```
exit: 0

#### d: statuses after the fake

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/case-d/status --jq [.state,(.statuses|map([.context,.state,.creator.login]))]

```
["success",[["scratch/status","success",null]]]
```
exit: 0

#### d: merge PR 2 after the fake

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/2/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from Seuss27.\n\nRequired status check \"scratch/status\" was not set by the expected GitHub app.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from Seuss27.

Required status check "scratch/status" was not set by the expected GitHub app.

 (HTTP 405)
```
exit: 1

#### b: PR 1 after the human approval

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:1){mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","reviews":{"nodes":[{"author":{"login":"Seuss27"},"state":"APPROVED"}]}}}}}
```
exit: 0

#### b: dev App pushes a second commit to case-a

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-a-2.txt -f message=case b push after approval -f branch=case-a -f content=Y2FzZSBiCg== --jq .commit.sha

```
0e1aa6fcec1e28fea576b0848ee9c8f583ede796
```
exit: 0

#### b: PR 1 after the push (approval stale?)

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:1){mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","reviews":{"nodes":[{"author":{"login":"Seuss27"},"state":"DISMISSED"}]}}}}}
```
exit: 0

#### b: reviews list after the push

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/1/reviews --jq map([.user.login,.state,.commit_id])

```
[["Seuss27","DISMISSED","39c8020f8dd646d087adf9721f5b4dea0ad8cbd2"]]
```
exit: 0

#### c: arm auto-merge (squash, pinned to the head) as the dev App, before any approval

as: dev App token
$ gh api graphql -f query=mutation($id:ID!,$oid:GitObjectID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH,expectedHeadOid:$oid}){pullRequest{autoMergeRequest{enabledBy{login} mergeMethod} state}}} -f id=PR_kwDOVBmbD88AAAABHcddyQ -f oid=0e1aa6fcec1e28fea576b0848ee9c8f583ede796

```
{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"autoMergeRequest":{"enabledBy":{"login":"glunk-dev"},"mergeMethod":"SQUASH"},"state":"OPEN"}}}}
```
exit: 0

#### c: PR 1 state with auto-merge armed

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/1 --jq [.state,.merged,.mergeable_state,.auto_merge.merge_method]

```
["open",false,"blocked","squash"]
```
exit: 0

#### c: PR 1 after the re-approval

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/1 --jq [.state,.merged,.merged_by.login,.merge_commit_sha]

```
["open",false,null,"770885cf2aa8cad606e0656cb725eb5756b204d7"]
```
exit: 0

#### c: main head after the merge

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/main --jq [.sha,.commit.message,.commit.committer.name]

```
["fe67508bcb741339d974e22bf194a6f421c8ceed","chore: add CODEOWNERS and status-posting workflow","Jared Groves"]
```
exit: 0

#### j: PR 2 behind main? mergeable_state

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/2 --jq [.mergeable_state,.head.sha]

```
["blocked","7caa2052adf05715188a5ebda737e5a390dce562"]
```
exit: 0

#### j: update-branch on PR 2 as the dev App (allow_update_branch is false on the repo)

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/2/update-branch -f expected_head_sha=7caa2052adf05715188a5ebda737e5a390dce562

```
{"message":"There are no new commits on the base branch.","documentation_url":"https://docs.github.com/rest/pulls/pulls#update-a-pull-request-branch","status":"422"}gh: There are no new commits on the base branch. (HTTP 422)
```
exit: 1

#### j: PR 2 after update-branch

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/2 --jq [.mergeable_state,.head.sha]

```
["blocked","7caa2052adf05715188a5ebda737e5a390dce562"]
```
exit: 0

#### c: PR 1 state, reviews and auto-merge

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:1){state merged mergeStateStatus reviewDecision autoMergeRequest{enabledBy{login}} headRefOid reviews(first:5){nodes{author{login} state commit{oid}}}}}}

```
{"data":{"repository":{"pullRequest":{"state":"OPEN","merged":false,"mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","autoMergeRequest":{"enabledBy":{"login":"glunk-dev"}},"headRefOid":"0e1aa6fcec1e28fea576b0848ee9c8f583ede796","reviews":{"nodes":[{"author":{"login":"Seuss27"},"state":"DISMISSED","commit":{"oid":"39c8020f8dd646d087adf9721f5b4dea0ad8cbd2"}},{"author":{"login":"Seuss27"},"state":"APPROVED","commit":{"oid":"0e1aa6fcec1e28fea576b0848ee9c8f583ede796"}}]}}}}}
```
exit: 0

#### c: PR 1 a minute later

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/1 --jq [.state,.merged,.merged_by.login,.mergeable_state,.auto_merge.enabled_by.login]

```
["open",false,null,"clean","glunk-dev[bot]"]
```
exit: 0

#### c: PR 1 timeline events

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/issues/1/timeline --jq .[]|[.event,.actor.login,.created_at]|@tsv

```
committed		
review_requested	glunk-dev[bot]	2026-10-09T00:51:55Z
reviewed		
committed		
review_dismissed	glunk-dev[bot]	2026-10-09T00:57:08Z
auto_squash_enabled	glunk-dev[bot]	2026-10-09T00:57:50Z
reviewed		
```
exit: 0

#### c: PR 1 ~3 minutes after the approval

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/1 --jq [.state,.merged,.mergeable_state,.auto_merge.enabled_by.login,.updated_at]

```
["open",false,"clean","glunk-dev[bot]","2026-10-09T00:58:37Z"]
```
exit: 0

#### c: scratch repo workflow runs since the approval

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/actions/runs --jq .workflow_runs[0:4]|map([.id,.event,.conclusion,.created_at])

```
[[37867354304,"pull_request","success","2026-10-09T00:57:11Z"],[37866921372,"pull_request","success","2026-10-09T00:51:58Z"],[37863994513,"push","success","2026-10-09T00:17:15Z"]]
```
exit: 0

#### c: repo merge settings

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch --jq [.allow_auto_merge,.allow_squash_merge,.allow_merge_commit,.allow_rebase_merge]

```
[true,true,true,true]
```
exit: 0

#### c: dev App merges the approved, clean PR 1 directly (auto-merge had not fired)

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/1/merge -f merge_method=squash -f sha=0e1aa6fcec1e28fea576b0848ee9c8f583ede796

```
{"sha":"9fcd24177462ab85a5d479c1b5f0659fb067a451","merged":true,"message":"Pull Request successfully merged"}
```
exit: 0

#### c: PR 1 final

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/1 --jq [.state,.merged,.merged_by.login]

```
["closed",true,"glunk-dev[bot]"]
```
exit: 0

#### j: PR 2 mergeable_state now that main moved

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/2 --jq [.mergeable_state,.head.sha]

```
["unknown","7caa2052adf05715188a5ebda737e5a390dce562"]
```
exit: 0

#### j: update-branch on PR 2, main has moved

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/2/update-branch -f expected_head_sha=7caa2052adf05715188a5ebda737e5a390dce562

```
{"message":"Updating pull request branch.","url":"https://api.github.com/repos/glunk-works/wb-ruleset-scratch/pulls/2"}
```
exit: 0

#### j: PR 2 after update-branch

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/2 --jq [.mergeable_state,.head.sha]

```
["blocked","7a16e2ca993d7a3955d7a531348f473257b0482f"]
```
exit: 0

#### e/k: create branch case-e

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-e -f sha=9fcd24177462ab85a5d479c1b5f0659fb067a451 --jq .ref

```
refs/heads/case-e
```
exit: 0

#### e/k: commit on case-e

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-e.txt -f message=case e and k -f branch=case-e -f content=Y2FzZSBlCg== --jq .commit.sha

```
44ea1b548ec598b4326863dcbb3fe2613e291b92
```
exit: 0

#### e/k: open PR 3

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case e and k -f head=case-e -f base=main --jq [.number,.head.sha]

```
[3,"44ea1b548ec598b4326863dcbb3fe2613e291b92"]
```
exit: 0

#### e/k: PR 3 state before any approval

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:3){mergeStateStatus reviewDecision}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED"}}}}
```
exit: 0

#### e: PR 3 outcome

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/3 --jq [.state,.merged,.merged_by.login,.merge_commit_sha]

```
["open",false,null,"a8a43f0379d61f0d657bdbac8205474a0a356ab2"]
```
exit: 0

#### e: reviews on PR 3

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/3/reviews --jq map([.user.login,.state,.submitted_at])

```
[["Seuss27","APPROVED","2026-10-09T01:04:48Z"]]
```
exit: 0

#### e: PR 3 timeline

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/issues/3/timeline --jq .[]|[.event,.actor.login,.created_at]|@tsv

```
committed		
review_requested	glunk-dev[bot]	2026-10-09T01:02:38Z
reviewed		
```
exit: 0

#### e: PR 3 outcome (re-read)

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/3 --jq [.state,.merged,.merged_by.login,.merge_commit_sha]

```
["open",false,null,"a8a43f0379d61f0d657bdbac8205474a0a356ab2"]
```
exit: 0

#### e: reviews on PR 3 (re-read)

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/3/reviews --jq map([.user.login,.state,.submitted_at])

```
[["Seuss27","APPROVED","2026-10-09T01:04:48Z"]]
```
exit: 0

#### e: main head

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/main --jq [.sha,.commit.message,.author.login]

```
["9fcd24177462ab85a5d479c1b5f0659fb067a451","case a (#1)\n\n* case a\n\n* case b push after approval\n\n---------\n\nCo-authored-by: glunk-dev[bot] \u003c339840170+glunk-dev[bot]@users.noreply.github.com\u003e","glunk-dev[bot]"]
```
exit: 0

#### k: PR 3 state before arming (approved, clean)

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:3){mergeStateStatus reviewDecision headRefOid id}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","headRefOid":"44ea1b548ec598b4326863dcbb3fe2613e291b92","id":"PR_kwDOVBmbD88AAAABHchlZw"}}}}
```
exit: 0

#### k: arm auto-merge on the already-mergeable PR 3

as: dev App token
$ gh api graphql -f query=mutation($id:ID!,$oid:GitObjectID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH,expectedHeadOid:$oid}){pullRequest{autoMergeRequest{enabledBy{login}} state merged}}} -f id=PR_kwDOVBmbD88AAAABHchlZw -f oid=44ea1b548ec598b4326863dcbb3fe2613e291b92

```
{"data":{"enablePullRequestAutoMerge":null},"errors":[{"type":"UNPROCESSABLE","path":["enablePullRequestAutoMerge"],"locations":[{"line":1,"column":37}],"message":"Pull request Pull request is in clean status"}]}gh: Pull request Pull request is in clean status
```
exit: 1

#### k: PR 3 after arming

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/3 --jq [.state,.merged,.merged_by.login,.auto_merge.enabled_by.login]

```
["open",false,null,null]
```
exit: 0

#### e: create branch case-e2

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-e2 -f sha=9fcd24177462ab85a5d479c1b5f0659fb067a451 --jq .ref

```
refs/heads/case-e2
```
exit: 0

#### e: commit on case-e2

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-e2.txt -f message=case e second owner -f branch=case-e2 -f content=Y2FzZSBlMgo= --jq .commit.sha

```
4d3284ee3e95b44d24e72a679947d62a32db07a5
```
exit: 0

#### e: open PR 4

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case e second code owner -f head=case-e2 -f base=main --jq [.number,.head.sha]

```
[4,"4d3284ee3e95b44d24e72a679947d62a32db07a5"]
```
exit: 0

#### e: collaborators on the scratch repo

as: admin App token
$ gh api repos/glunk-works/wb-ruleset-scratch/collaborators?affiliation=all --jq map([.login,.permissions.push,.role_name])

```
[]
```
exit: 0

#### e: is JaredGroves-603 a collaborator

as: admin App token
$ gh api repos/glunk-works/wb-ruleset-scratch/collaborators/JaredGroves-603/permission --jq [.permission,.user.login]

```
["read","JaredGroves-603"]
```
exit: 0

#### e: invitations pending

as: admin App token
$ gh api repos/glunk-works/wb-ruleset-scratch/invitations --jq map([.invitee.login,.permissions])

```
[]
```
exit: 0

#### e: org membership of JaredGroves-603

as: admin App token
$ gh api orgs/glunk-works/members/JaredGroves-603 -i

```
HTTP/2.0 404 Not Found
Access-Control-Allow-Origin: *
Access-Control-Expose-Headers: ETag, Link, Location, Retry-After, X-GitHub-OTP, X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Used, X-RateLimit-Resource, X-RateLimit-Reset, X-OAuth-Scopes, X-Accepted-OAuth-Scopes, X-Poll-Interval, X-GitHub-Media-Type, X-GitHub-SSO, X-GitHub-Request-Id, Deprecation, Sunset, Warning
Content-Security-Policy: default-src 'none'
Content-Type: application/json; charset=utf-8
Date: Fri, 09 Oct 2026 01:08:15 GMT
Referrer-Policy: origin-when-cross-origin, strict-origin-when-cross-origin
Server: github.com
Strict-Transport-Security: max-age=31536000; includeSubdomains; preload
Vary: Accept-Encoding, Accept, X-Requested-With
X-Accepted-Github-Permissions: members=read
X-Content-Type-Options: nosniff
X-Frame-Options: deny
X-Github-Api-Version-Selected: 2022-11-28
X-Github-Edge-Region: iad
X-Github-Media-Type: github.v3; format=json
X-Github-Request-Id: C540:165415:1EAB509:64B0D46:6AC83E7F
X-Ratelimit-Limit: 5000
X-Ratelimit-Remaining: 4995
X-Ratelimit-Reset: 1791511693
X-Ratelimit-Resource: core
X-Ratelimit-Used: 5
X-Xss-Protection: 0

{"message":"User does not exist or is not a public member of the organization","documentation_url":"https://docs.github.com/rest/orgs/members#check-public-organization-membership-for-a-user","status":"404"}gh: User does not exist or is not a public member of the organization (HTTP 404)
```
exit: 1

#### e: invite JaredGroves-603 as a collaborator with write (push)

as: admin App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/collaborators/JaredGroves-603 -f permission=push --jq [.id,.invitee.login,.permissions,.html_url]

```
[336850686,"JaredGroves-603","write","https://github.com/glunk-works/wb-ruleset-scratch/invitations"]
```
exit: 0

#### e: pending invitations

as: admin App token
$ gh api repos/glunk-works/wb-ruleset-scratch/invitations --jq map([.invitee.login,.permissions,.html_url])

```
[["JaredGroves-603","write","https://github.com/glunk-works/wb-ruleset-scratch/invitations"]]
```
exit: 0

#### e: JaredGroves-603 permission after accepting

as: admin App token
$ gh api repos/glunk-works/wb-ruleset-scratch/collaborators/JaredGroves-603/permission --jq [.permission,.user.login]

```
["write","JaredGroves-603"]
```
exit: 0

#### e: merge attempt on PR 4 before approval (message lists who is awaited)

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/4/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from JaredGroves-603 and/or Seuss27.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from JaredGroves-603 and/or Seuss27.

 (HTTP 405)
```
exit: 1

#### e: create branch case-e3

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-e3 -f sha=9fcd24177462ab85a5d479c1b5f0659fb067a451 --jq .ref

```
refs/heads/case-e3
```
exit: 0

#### e: commit on case-e3

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-e3.txt -f message=case e third try -f branch=case-e3 -f content=Y2FzZSBlMwo= --jq .commit.sha

```
eb5cd49b90cdcc5afef400f7f0aded086a36e58d
```
exit: 0

#### e: open PR 5 (opened after JaredGroves-603 had write)

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case e after write access -f head=case-e3 -f base=main --jq [.number,.head.sha]

```
[5,"eb5cd49b90cdcc5afef400f7f0aded086a36e58d"]
```
exit: 0

#### e: PR 5 merge message

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/5/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from JaredGroves-603 and/or Seuss27.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from JaredGroves-603 and/or Seuss27.

 (HTTP 405)
```
exit: 1

#### e: PR 4 reviews so far

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/4/reviews --jq map([.user.login,.state])

```
[]
```
exit: 0

#### e: PR 5 after JaredGroves-603's approval

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:5){mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state authorAssociation}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","reviews":{"nodes":[{"author":{"login":"JaredGroves-603"},"state":"APPROVED","authorAssociation":"COLLABORATOR"}]}}}}}
```
exit: 0

#### e: PR 5 outcome

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/5 --jq [.state,.merged,.merged_by.login,.merge_commit_sha]

```
["closed",true,"JaredGroves-603","558785c2cf4dff6e8882fbc43eb4679e91a67f73"]
```
exit: 0

#### e: main head

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/main --jq [.sha,.commit.message]

```
["558785c2cf4dff6e8882fbc43eb4679e91a67f73","Merge pull request #5 from glunk-works/case-e3\n\ncase e after write access"]
```
exit: 0

#### c (retry): PR 4 state before arming

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:4){mergeStateStatus reviewDecision headRefOid id}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"UNKNOWN","reviewDecision":"REVIEW_REQUIRED","headRefOid":"4d3284ee3e95b44d24e72a679947d62a32db07a5","id":"PR_kwDOVBmbD88AAAABHcjgWg"}}}}
```
exit: 0

#### c (retry): arm auto-merge on PR 4 before approval

as: dev App token
$ gh api graphql -f query=mutation($id:ID!,$oid:GitObjectID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH,expectedHeadOid:$oid}){pullRequest{autoMergeRequest{enabledBy{login} mergeMethod}}}} -f id=PR_kwDOVBmbD88AAAABHcjgWg -f oid=4d3284ee3e95b44d24e72a679947d62a32db07a5

```
{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"autoMergeRequest":{"enabledBy":{"login":"glunk-dev"},"mergeMethod":"SQUASH"}}}}}
```
exit: 0

#### c (retry): PR 4 right after approval

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:4){state merged mergeStateStatus reviewDecision autoMergeRequest{enabledBy{login}} reviews(first:3){nodes{author{login} state}}}}}

```
{"data":{"repository":{"pullRequest":{"state":"OPEN","merged":false,"mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","autoMergeRequest":{"enabledBy":{"login":"glunk-dev"}},"reviews":{"nodes":[{"author":{"login":"JaredGroves-603"},"state":"APPROVED"}]}}}}}
```
exit: 0

#### c (retry): PR 4 ~90s after approval

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:4){state merged mergeStateStatus reviewDecision autoMergeRequest{enabledBy{login}} reviews(first:3){nodes{author{login} state}}}}}

```
{"data":{"repository":{"pullRequest":{"state":"MERGED","merged":true,"mergeStateStatus":"UNKNOWN","reviewDecision":"APPROVED","autoMergeRequest":{"enabledBy":{"login":"glunk-dev"}},"reviews":{"nodes":[{"author":{"login":"JaredGroves-603"},"state":"APPROVED"}]}}}}}
```
exit: 0

#### c (retry): PR 4 who merged and when

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/4 --jq [.merged_by.login,.merged_at,.merge_commit_sha]

```
["glunk-dev[bot]","2026-10-09T01:14:14Z","5932287b4acfb52028a81f0541bc9f2c0601c282"]
```
exit: 0

#### c (retry): PR 4 timeline

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/issues/4/timeline --jq .[]|[.event,.actor.login,.created_at]|@tsv

```
committed		
review_requested	glunk-dev[bot]	2026-10-09T01:07:30Z
auto_squash_enabled	glunk-dev[bot]	2026-10-09T01:13:02Z
committed		
review_requested	JaredGroves-603	2026-10-09T01:13:19Z
reviewed		
merged	glunk-dev[bot]	2026-10-09T01:14:14Z
closed	glunk-dev[bot]	2026-10-09T01:14:15Z
```
exit: 0

#### c: PR 1 timeline (for comparison)

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/issues/1/timeline --jq .[]|[.event,.actor.login,.created_at]|@tsv

```
committed		
review_requested	glunk-dev[bot]	2026-10-09T00:51:55Z
reviewed		
committed		
review_dismissed	glunk-dev[bot]	2026-10-09T00:57:08Z
auto_squash_enabled	glunk-dev[bot]	2026-10-09T00:57:50Z
reviewed		
merged	glunk-dev[bot]	2026-10-09T01:02:01Z
closed	glunk-dev[bot]	2026-10-09T01:02:01Z
```
exit: 0

#### f: create branch case-f

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-f -f sha=5932287b4acfb52028a81f0541bc9f2c0601c282 --jq .ref

```
refs/heads/case-f
```
exit: 0

#### f: commit on case-f

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-f.txt -f message=case f -f branch=case-f -f content=Y2FzZSBmCg== --jq .commit.sha

```
1cc5aa50e9b5a12d5cc583cfe9aaecf0465a6aa5
```
exit: 0

#### f: open PR 6

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case f reviewer -f head=case-f -f base=main --jq [.number,.head.sha]

```
[6,"1cc5aa50e9b5a12d5cc583cfe9aaecf0465a6aa5"]
```
exit: 0

#### g: revoke the admin token, then use it (run by the maintainer, pasted from the terminal)

```
$ T=$(sed -n 1p ~/.config/glunk-identity/tokens/wb-ruleset-scratch/admin-token)
$ sh scripts/identity/wow-admin wb-ruleset-scratch --revoke
revoked the admin token for wb-ruleset-scratch
$ GH_TOKEN=$T gh api repos/glunk-works/wb-ruleset-scratch --jq .full_name
{
  "message": "Bad credentials",
  "documentation_url": "https://docs.github.com/rest",
  "status": "401"
}
gh: Bad credentials (HTTP 401)
```

#### f: reviewer App posts a COMMENT review on PR 6

as: review App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/6/reviews -f event=COMMENT -f body=fresh-session review, comment only --jq [.id,.user.login,.user.id,.state,.commit_id]

```
[5464793688,"JaredGroves-603",281693088,"COMMENTED","1cc5aa50e9b5a12d5cc583cfe9aaecf0465a6aa5"]
```
exit: 0

#### f: reviewer App tries APPROVE on PR 6

as: review App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/6/reviews -f event=APPROVE -f body=should not be allowed --jq [.user.login,.state]

```
["JaredGroves-603","APPROVED"]
```
exit: 0

#### f: PR 6 reviews as read back

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/6/reviews --jq map([.user.login,.user.id,.state,.author_association])

```
[["JaredGroves-603",281693088,"COMMENTED","COLLABORATOR"],["JaredGroves-603",281693088,"APPROVED","COLLABORATOR"]]
```
exit: 0

#### f: PR 6 merge state after the COMMENT

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:6){mergeStateStatus reviewDecision}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"CLEAN","reviewDecision":"APPROVED"}}}}
```
exit: 0

#### f: reviewer App tries to merge

as: review App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/6/merge -f merge_method=squash

```
{"sha":"e228b2420c4889db12d13aac352cda8fbf36136d","merged":true,"message":"Pull Request successfully merged"}
```
exit: 0

#### f: reviewer App tries to push a file

as: review App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/f-reviewer.txt -f message=x -f branch=case-f -f content=eAo= --jq .commit.sha

```
bad72e8fbf455a9443b8d96d3d81f5d7fb53d11f
```
exit: 0

#### f: VOID -- the four "review App token" calls above ran as JaredGroves-603, not glunk-review[bot]

Every call labelled `review App token` returned `user.login` JaredGroves-603 (id 281693088), a
human code owner with write access. So these results show what that user account can do, not
what the reviewer App can do. They also made real changes: an APPROVE on PR 6, the merge of PR 6
(e228b24), and a commit pushed to case-f (bad72e8). On 2026-10-09 the reviewer App, both as
configured and as installed, held only `metadata: read, pull_requests: write`, while
`wow-review-mint` asks for `contents=read,checks=read,statuses=read,pull_requests=write`.
A mint therefore cannot have produced the token on file. Case f is re-run after the
reviewer App is fixed.

## Raw output, session 2 (2026-10-09, UTC 10:15-10:40)

#### f (re-run): reach probe -- installation repositories as the reviewer App

as: review App token
$ gh api installation/repositories --jq [.total_count,(.repositories|map(.full_name))]

```
[1,["glunk-works/wb-ruleset-scratch"]]
```
exit: 0

#### f (re-run): main head

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/main --jq .sha

```
e228b2420c4889db12d13aac352cda8fbf36136d
```
exit: 0

#### f (re-run): create branch case-f2

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-f2 -f sha=e228b2420c4889db12d13aac352cda8fbf36136d --jq .ref

```
refs/heads/case-f2
```
exit: 0

#### f (re-run): commit on case-f2

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-f2.txt -f message=case f re-run -f branch=case-f2 -f content=Y2FzZSBmMgo= --jq .commit.sha

```
2b4bfc179385a9637be07eb275221dccb661a4a7
```
exit: 0

#### f (re-run): open PR

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case f re-run (reviewer App) -f head=case-f2 -f base=main --jq [.number,.head.sha,.user.login]

```
[7,"2b4bfc179385a9637be07eb275221dccb661a4a7","glunk-dev[bot]"]
```
exit: 0

#### f (re-run): reviewer App posts a COMMENT review on PR 7

as: review App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/7/reviews -f event=COMMENT -f body=fresh-session review, comment only --jq [.id,.user.login,.user.id,.user.type,.state,.commit_id]

```
[5468756613,"glunk-review[bot]",339841158,"Bot","COMMENTED","2b4bfc179385a9637be07eb275221dccb661a4a7"]
```
exit: 0

#### f (re-run): PR 7 merge state after the COMMENT

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:7){mergeStateStatus reviewDecision reviews(first:5){nodes{author{login ... on Bot{databaseId}} state}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","reviews":{"nodes":[{"author":{"login":"glunk-review","databaseId":339841158},"state":"COMMENTED"}]}}}}}
```
exit: 0

#### f (re-run): the reviewer App's bot user, by public lookup

as: maintainer (Seuss27 user token, not an App)
$ gh api users/glunk-review[bot] --jq [.login,.id,.type]

```
["glunk-review[bot]",339841158,"Bot"]
```
exit: 0

#### f (re-run): reviewer App tries APPROVE on PR 7

as: review App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/7/reviews -f event=APPROVE -f body=should not count --jq [.user.login,.state]

```
["glunk-review[bot]","APPROVED"]
```
exit: 0

#### f (re-run): PR 7 merge state after the reviewer App's APPROVE

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:7){mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","reviews":{"nodes":[{"author":{"login":"glunk-review"},"state":"COMMENTED"},{"author":{"login":"glunk-review"},"state":"APPROVED"}]}}}}}
```
exit: 0

#### f (re-run): reviewer App tries to merge PR 7

as: review App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/7/merge -f merge_method=squash

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### f (re-run): reviewer App tries to push a file to case-f2

as: review App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/f2-reviewer.txt -f message=x -f branch=case-f2 -f content=eAo= --jq .commit.sha

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/repos/contents#create-or-update-file-contents","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### f (re-run): dev App merge attempt on PR 7 (message lists what is awaited)

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/7/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from JaredGroves-603 and/or Seuss27.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from JaredGroves-603 and/or Seuss27.

 (HTTP 405)
```
exit: 1

#### c1: PR 7 node id, head, state before arming

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:7){id headRefOid mergeStateStatus reviewDecision commits(last:1){nodes{commit{statusCheckRollup{state}}}}}}} --jq .data.repository.pullRequest|[.id,.headRefOid,.mergeStateStatus,.commits.nodes[0].commit.statusCheckRollup.state]|@tsv

```
PR_kwDOVBmbD88AAAABHgxX4Q	2b4bfc179385a9637be07eb275221dccb661a4a7	BLOCKED	SUCCESS
```
exit: 0

#### c1: dev App arms auto-merge on PR 7 (squash, pinned head)

as: dev App token
$ gh api graphql -f query=mutation($id:ID!,$oid:GitObjectID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH,expectedHeadOid:$oid}){pullRequest{autoMergeRequest{enabledBy{login} mergeMethod enabledAt}}}} -f id=PR_kwDOVBmbD88AAAABHgxX4Q -f oid=2b4bfc179385a9637be07eb275221dccb661a4a7

```
{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"autoMergeRequest":{"enabledBy":{"login":"glunk-dev"},"mergeMethod":"SQUASH","enabledAt":"2026-10-09T10:19:34Z"}}}}}
```
exit: 0

#### c1: PR 7 after the Seuss27 approval

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/7 --jq [.state,.merged,.merged_by.login,.merged_at,.auto_merge.enabled_by.login]

```
["closed",true,"glunk-dev[bot]","2026-10-09T10:20:13Z","glunk-dev[bot]"]
```
exit: 0

#### c1: PR 7 reviews

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/7/reviews --jq map([.user.login,.state,.submitted_at])

```
[["glunk-review[bot]","COMMENTED","2026-10-09T10:18:48Z"],["glunk-review[bot]","APPROVED","2026-10-09T10:18:59Z"],["Seuss27","APPROVED","2026-10-09T10:20:03Z"]]
```
exit: 0

#### c2: main head

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/main --jq .sha

```
888bcdd80ebd51011489f4f0089264b2192e1b71
```
exit: 0

#### c2: create branch case-c2

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case-c2 -f sha=888bcdd80ebd51011489f4f0089264b2192e1b71 --jq .ref

```
refs/heads/case-c2
```
exit: 0

#### c2: commit on case-c2

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-c2.txt -f message=case c2 -f branch=case-c2 -f content=Y2FzZSBjMgo= --jq .commit.sha

```
d3b53e2fe873c098e7cd56c4cfb2c6ee0ac3d4a9
```
exit: 0

#### c2: open PR

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case c2 (dismissal then re-approval) -f head=case-c2 -f base=main --jq [.number,.head.sha]

```
[8,"d3b53e2fe873c098e7cd56c4cfb2c6ee0ac3d4a9"]
```
exit: 0

#### c2: PR 8 after the first approval

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:8){mergeStateStatus reviewDecision merged}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","merged":false}}}}
```
exit: 0

#### c2: dev App pushes a second commit to case-c2

as: dev App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/case-c2-2.txt -f message=case c2 push after approval -f branch=case-c2 -f content=YzIgMgo= --jq .commit.sha

```
b4c23de28ff0825248c43b30faf42cc9700ea6f0
```
exit: 0

#### c2: PR 8 after the push (approval dismissed?)

as: dev App token
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:8){id headRefOid mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state}}}}}

```
{"data":{"repository":{"pullRequest":{"id":"PR_kwDOVBmbD88AAAABHgywhQ","headRefOid":"b4c23de28ff0825248c43b30faf42cc9700ea6f0","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","reviews":{"nodes":[{"author":{"login":"Seuss27"},"state":"DISMISSED"}]}}}}}
```
exit: 0

#### c2: dev App arms auto-merge on PR 8 (squash, pinned head)

as: dev App token
$ gh api graphql -f query=mutation($id:ID!,$oid:GitObjectID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH,expectedHeadOid:$oid}){pullRequest{autoMergeRequest{enabledBy{login} enabledAt}}}} -f id=PR_kwDOVBmbD88AAAABHgywhQ -f oid=b4c23de28ff0825248c43b30faf42cc9700ea6f0

```
{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"autoMergeRequest":{"enabledBy":{"login":"glunk-dev"},"enabledAt":"2026-10-09T10:21:50Z"}}}}}
```
exit: 0

#### c2: PR 8 after the re-approval

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/8 --jq [.state,.merged,.merged_by.login,.merged_at]

```
["closed",true,"glunk-dev[bot]","2026-10-09T10:22:55Z"]
```
exit: 0

#### c2: PR 8 reviews

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/8/reviews --jq map([.user.login,.state,.submitted_at,.commit_id[0:7]])

```
[["Seuss27","DISMISSED","2026-10-09T10:21:24Z","d3b53e2"],["Seuss27","APPROVED","2026-10-09T10:22:51Z","b4c23de"]]
```
exit: 0

#### h: add a creation rule to wb-tags (docs/identity/scratch-rulesets/tags.json)

as: admin App token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/rulesets/24758201 --input docs/identity/scratch-rulesets/tags.json --jq [.name,.enforcement,(.rules|map(.type)),.bypass_actors]

```
["wb-tags","active",["deletion","non_fast_forward","update","creation"],[]]
```
exit: 0

#### h (after creation rule): dev App creates tag v-case-h2

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/tags/v-case-h2 -f sha=6a7a2b3fd9fd5be2b1314b40a7875ab4e54a7a6b --jq .ref

```
{"message":"Reference update failed","documentation_url":"https://docs.github.com/rest/git/refs#create-a-reference","status":"422"}gh: Reference update failed (HTTP 422)
```
exit: 1

#### h (after creation rule): dev App creates a release with a new tag

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/releases -f tag_name=v-case-h2-rel -f target_commitish=main --jq [.tag_name,.draft]

```
{"message":"Validation Failed","errors":[{"resource":"Release","code":"custom","field":"pre_receive","message":"pre_receive Repository rule violations found\n\nCannot create ref due to creations being restricted.\n\n"},{"resource":"Release","code":"custom","message":"Published releases must have a valid tag"}],"documentation_url":"https://docs.github.com/rest/releases/releases#create-a-release","status":"422"}gh: Validation Failed (HTTP 422)
```
exit: 1

#### h (after creation rule): dev App creates a non-v tag (outside the pattern; expected allowed)

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/tags/scratch-h2 -f sha=6a7a2b3fd9fd5be2b1314b40a7875ab4e54a7a6b --jq .ref

```
refs/tags/scratch-h2
```
exit: 0

#### h (after creation rule): tags matching v-case-h2*

as: dev App token
$ gh api repos/glunk-works/wb-ruleset-scratch/git/matching-refs/tags/v-case-h2 --jq map(.ref)

```
[]
```
exit: 0

#### c (critic follow-up): PR 4 commits and who pushed them

as: maintainer (Seuss27 user token, not an App)
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/4/commits --jq map([.sha[0:7],.commit.message,.author.login])

```
[["4d3284e","case e second owner","glunk-dev[bot]"],["962e566","Merge branch 'main' into case-e2","JaredGroves-603"]]
```
exit: 0

#### c (critic follow-up): PR 4 reviews with commit and time

as: maintainer (Seuss27 user token, not an App)
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/4/reviews --jq map([.user.login,.state,.submitted_at,.commit_id[0:7]])

```
[["JaredGroves-603","APPROVED","2026-10-09T01:13:58Z","962e566"]]
```
exit: 0

#### h (critic follow-up): wb-tags ruleset history, actor of the creation-rule edit

as: maintainer (Seuss27 user token, not an App)
$ gh api repos/glunk-works/wb-ruleset-scratch/rulesets/24758201/history --jq map([.version_id,.actor.id,.actor.type,.updated_at])

```
[[52554106,339842227,"Bot","2026-10-09T06:29:25.915-04:00"],[52503249,22668449,"User","2026-10-08T20:17:25.439-04:00"]]
```
exit: 0

## Raw output, session 3 (2026-10-09, UTC 11:40-12:30)

#### setup: main head

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/main --jq .sha

```
6a7a2b3fd9fd5be2b1314b40a7875ab4e54a7a6b
```
exit: 0

#### setup: CODEOWNERS

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/contents/.github/CODEOWNERS --jq .content

```
KiBAU2V1c3MyNyBASmFyZWRHcm92ZXMtNjAzCg==
```
exit: 0

#### setup: tree of main

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/trees/main?recursive=1 --jq [.tree[].path]

```
[".github",".github/CODEOWNERS",".github/workflows",".github/workflows/status.yml","README.md","case-a-2.txt","case-a.txt","case-c2-2.txt","case-c2.txt","case-e2.txt","case-e3.txt","case-f.txt","case-f2.txt"]
```
exit: 0

#### setup: rulesets (maintainer)

as: Seuss27 user token
$ gh api repos/glunk-works/wb-ruleset-scratch/rulesets --jq [.[]|[.id,.name,.enforcement]]

```
[[24758199,"wb-approval","active"],[24758197,"wb-checks","active"],[24758201,"wb-tags","active"]]
```
exit: 0

#### 3 setup: branch narrow-codeowners

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/narrow-codeowners -f sha=6a7a2b3fd9fd5be2b1314b40a7875ab4e54a7a6b --jq .ref

```
refs/heads/narrow-codeowners
```
exit: 0

#### 3 setup: narrow CODEOWNERS to /owned/ on branch

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/.github/CODEOWNERS -f message=narrow CODEOWNERS to /owned/ (#435 item 3) -f branch=narrow-codeowners -f sha=8c32525c20e6af1032e2d1ecf5d9e472e12ffa85 -f content=L293bmVkLyBAU2V1c3MyNyBASmFyZWRHcm92ZXMtNjAzCg== --jq .commit.sha

```
3242c0493a13bcde3f9a7313487b2bd6d5d7e06a
```
exit: 0

#### 3 setup: open PR narrowing CODEOWNERS

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=narrow CODEOWNERS to /owned/ (#435 item 3) -f head=narrow-codeowners -f base=main --jq [.number,.head.sha,.user.login]

```
[9,"3242c0493a13bcde3f9a7313487b2bd6d5d7e06a","glunk-dev[bot]"]
```
exit: 0

#### 3 setup: PR 9 reviews (human approval)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/9/reviews --jq [.[]|[.user.login,.state,.commit_id]]

```
[["Seuss27","APPROVED","3242c0493a13bcde3f9a7313487b2bd6d5d7e06a"]]
```
exit: 0

#### 3 setup: dev App merges PR 9

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/9/merge -f merge_method=squash -f sha=3242c0493a13bcde3f9a7313487b2bd6d5d7e06a --jq [.merged,.sha]

```
[true,"28e1d4f9c12599a1d109c98a7b7abd305bd55fc5"]
```
exit: 0

#### 3: main head after CODEOWNERS narrowing

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/contents/.github/CODEOWNERS?ref=main --jq .content|@base64d

```
/owned/ @Seuss27 @JaredGroves-603
```
exit: 0

#### 3: branch item3

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/item3 -f sha=28e1d4f9c12599a1d109c98a7b7abd305bd55fc5 --jq .ref

```
refs/heads/item3
```
exit: 0

#### 3: commit uncovered path free/i3.txt

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/free/i3.txt -f message=item 3: uncovered path -f branch=item3 -f content=aXRlbTMK --jq .commit.sha

```
884a9cee3fe21638fbe302590efdebfe98aa50d3
```
exit: 0

#### 3: open PR

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=item 3 uncovered path -f head=item3 -f base=main --jq [.number,.head.sha,.user.login]

```
[10,"884a9cee3fe21638fbe302590efdebfe98aa50d3","glunk-dev[bot]"]
```
exit: 0

#### 3: PR 10 state before any review

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:10){mergeStateStatus reviewDecision mergeable reviews(first:5){nodes{author{login} state}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","mergeable":"MERGEABLE","reviews":{"nodes":[]}}}}}
```
exit: 0

#### 3: reviewer App APPROVE on PR 10 (path with no CODEOWNERS entry)

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/10/reviews -f event=APPROVE --jq [.id,.user.login,.user.type,.state]

```
[5469538588,"glunk-review[bot]","Bot","APPROVED"]
```
exit: 0

#### 3: PR 10 state after reviewer APPROVE

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:10){mergeStateStatus reviewDecision mergeable reviews(first:5){nodes{author{login} state}}}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","mergeable":"MERGEABLE","reviews":{"nodes":[{"author":{"login":"glunk-review"},"state":"APPROVED"}]}}}}}
```
exit: 0

#### 3: dev App tries merge PR 10

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/10/merge -f merge_method=squash -f sha=884a9cee3fe21638fbe302590efdebfe98aa50d3

```
{"message":"Repository rule violations found\n\nNew changes require approval from someone other than the last pusher.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

New changes require approval from someone other than the last pusher.

 (HTTP 405)
```
exit: 1

#### 4: dev App creates alt-base branch

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/alt-base -f sha=28e1d4f9c12599a1d109c98a7b7abd305bd55fc5 --jq .ref

```
refs/heads/alt-base
```
exit: 0

#### 4: reviewer App edits PR body

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/10 -f body=BODY EDITED BY REVIEWER APP --jq .body

```
BODY EDITED BY REVIEWER APP
```
exit: 0

#### 4: reviewer App changes PR base to alt-base

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/10 -f base=alt-base --jq [.base.ref]

```
["alt-base"]
```
exit: 0

#### 4: reviewer App changes PR base back to main

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/10 -f base=main --jq [.base.ref]

```
["main"]
```
exit: 0

#### 4: dev App arms auto-merge on PR 10

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query=mutation{enablePullRequestAutoMerge(input:{pullRequestId:"PR_kwDOVBmbD88AAAABHhjXwg",mergeMethod:SQUASH,expectedHeadOid:"884a9cee3fe21638fbe302590efdebfe98aa50d3"}){pullRequest{autoMergeRequest{enabledBy{login}}}}}

```
{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"autoMergeRequest":{"enabledBy":{"login":"glunk-dev"}}}}}}
```
exit: 0

#### 4: reviewer App disables auto-merge

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query=mutation{disablePullRequestAutoMerge(input:{pullRequestId:"PR_kwDOVBmbD88AAAABHhjXwg"}){pullRequest{autoMergeRequest{enabledAt}}}}

```
{"data":{"disablePullRequestAutoMerge":null},"errors":[{"type":"FORBIDDEN","path":["disablePullRequestAutoMerge"],"extensions":{"saml_failure":false,"ip_allow_list_failure":false},"locations":[{"line":1,"column":10}],"message":"Resource not accessible by integration"}]}gh: Resource not accessible by integration
```
exit: 1

#### 4: reviewer App closes PR 10

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/10 -f state=closed --jq [.state,.merged]

```
["closed",false]
```
exit: 0

#### 4: reviewer App reopens PR 10

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/10 -f state=open --jq [.state]

```
["open"]
```
exit: 0

#### 4: reviewer App edits PR title (retry after a 502 on the reach probe)

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/10 -f title=TITLE EDITED BY REVIEWER APP --jq [.title,.user.login]

```
["TITLE EDITED BY REVIEWER APP","glunk-dev[bot]"]
```
exit: 0

#### 4: auto-merge still armed on PR 10 after the forbidden disable?

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:10){state autoMergeRequest{enabledBy{login}}}}}

```
{"data":{"repository":{"pullRequest":{"state":"OPEN","autoMergeRequest":null}}}}
```
exit: 0

#### 7: existing releases

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases --jq [.[]|[.id,.tag_name,.draft]]

```
[[407387359,"v-case-g-rel",false]]
```
exit: 0

#### 7: existing tags

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/matching-refs/tags --jq [.[].ref]

```
["refs/tags/scratch-h2","refs/tags/v-case-g","refs/tags/v-case-g-rel"]
```
exit: 0

#### 7: dev App creates a draft release (no tag push)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases -f tag_name=v-draft-i7 -f name=draft i7 -F draft=true -f target_commitish=main --jq [.id,.draft,.tag_name]

```
[407858499,true,"v-draft-i7"]
```
exit: 0

#### 7: dev App edits existing v* release body

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/releases/407387359 -f body=edited by dev App --jq [.id,.body]

```
[407387359,"edited by dev App"]
```
exit: 0

#### 7: dev App uploads an asset to existing v* release

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X POST https://uploads.github.com/repos/glunk-works/wb-ruleset-scratch/releases/407387359/assets?name=i7.txt -H Content-Type: text/plain --input C:/Users/SR116/AppData/Local/Temp/claude/c--Users-SR116-projects-glunk-works-claude-workbench/66b52847-35bd-49e9-ad6f-c1c88379890d/scratchpad/asset.txt --jq [.id,.name,.uploader.login]

```
[624809139,"i7.txt","glunk-dev[bot]"]
```
exit: 0

#### 7: existing tags after draft attempt

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/matching-refs/tags --jq [.[].ref]

```
["refs/tags/scratch-h2","refs/tags/v-case-g","refs/tags/v-case-g-rel"]
```
exit: 0

#### 7: dev App publishes the draft (would create tag v-draft-i7)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/releases/407858499 -F draft=false --jq [.id,.draft,.tag_name]

```
{"message":"Validation Failed","errors":[{"resource":"Release","code":"custom","field":"pre_receive","message":"pre_receive Repository rule violations found\n\nCannot create ref due to creations being restricted.\n\n"},{"resource":"Release","code":"custom","message":"Published releases must have a valid tag"}],"documentation_url":"https://docs.github.com/rest/releases/releases#update-a-release","status":"422"}gh: Validation Failed (HTTP 422)
```
exit: 1

#### 7: tags after publish attempt

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/matching-refs/tags --jq [.[].ref]

```
["refs/tags/scratch-h2","refs/tags/v-case-g","refs/tags/v-case-g-rel"]
```
exit: 0

#### 7: dev App deletes asset from existing v* release

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/releases/assets/624809139

```

```
exit: 0

#### 7: dev App deletes the draft release

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/releases/407858499

```

```
exit: 0

#### 7: dev App deletes existing v* release

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/releases/407387359

```

```
exit: 0

#### 7: releases and tags afterwards

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases --jq [.[]|[.id,.tag_name,.draft]]

```
[]
```
exit: 0

#### 1: branch item1-11

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/item1-11 -f sha=28e1d4f9c12599a1d109c98a7b7abd305bd55fc5 --jq .ref

```
refs/heads/item1-11
```
exit: 0

#### 1: dev App commit owned/i1-11.txt

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/owned/i1-11.txt -f message=item 1: dev App content 11 -f branch=item1-11 -f content=aTEK --jq .commit.sha

```
f12247431c656bcfc5e00441ed9c361597562c41
```
exit: 0

#### 1: open PR item1-11

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=item 1 case 11 -f head=item1-11 -f base=main --jq [.number,.head.sha,.user.login]

```
[11,"f12247431c656bcfc5e00441ed9c361597562c41","glunk-dev[bot]"]
```
exit: 0

#### 1: branch item1-12

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/item1-12 -f sha=28e1d4f9c12599a1d109c98a7b7abd305bd55fc5 --jq .ref

```
refs/heads/item1-12
```
exit: 0

#### 1: dev App commit owned/i1-12.txt

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/owned/i1-12.txt -f message=item 1: dev App content 12 -f branch=item1-12 -f content=aTEK --jq .commit.sha

```
4633f82c9490882f7cd7881f6dfbab766f2bcf59
```
exit: 0

#### 1: open PR item1-12

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=item 1 case 12 -f head=item1-12 -f base=main --jq [.number,.head.sha,.user.login]

```
[12,"4633f82c9490882f7cd7881f6dfbab766f2bcf59","glunk-dev[bot]"]
```
exit: 0

#### 1a: Seuss27 (code owner) pushes a content commit to PR 11's branch

as: Seuss27 user token
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/owned/i1-11-owner.txt -f message=item 1a: code owner content push -f branch=item1-11 -f content=b3duZXIK --jq [.commit.sha,.commit.author.name]

```
["0fe0a04adae5286a510532d29443a2e96fa9794d","Jared Groves"]
```
exit: 0

#### 1a: PR 11 head after the owner push

as: Seuss27 user token
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/11 --jq [.head.sha,.user.login]

```
["f12247431c656bcfc5e00441ed9c361597562c41","glunk-dev[bot]"]
```
exit: 0

#### 1: state of PR 10 after maintainer approvals

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:10){headRefOid mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state commit{oid}}}}}}

```
{"data":{"repository":{"pullRequest":{"headRefOid":"884a9cee3fe21638fbe302590efdebfe98aa50d3","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","reviews":{"nodes":[{"author":{"login":"glunk-review"},"state":"APPROVED","commit":{"oid":"884a9cee3fe21638fbe302590efdebfe98aa50d3"}},{"author":{"login":"Seuss27"},"state":"APPROVED","commit":{"oid":"884a9cee3fe21638fbe302590efdebfe98aa50d3"}}]}}}}}
```
exit: 0

#### 1: state of PR 11 after maintainer approvals

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:11){headRefOid mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state commit{oid}}}}}}

```
{"data":{"repository":{"pullRequest":{"headRefOid":"0fe0a04adae5286a510532d29443a2e96fa9794d","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","reviews":{"nodes":[{"author":{"login":"Seuss27"},"state":"APPROVED","commit":{"oid":"0fe0a04adae5286a510532d29443a2e96fa9794d"}}]}}}}}
```
exit: 0

#### 1: state of PR 12 after maintainer approvals

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:12){headRefOid mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state commit{oid}}}}}}

```
{"data":{"repository":{"pullRequest":{"headRefOid":"4633f82c9490882f7cd7881f6dfbab766f2bcf59","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","reviews":{"nodes":[{"author":{"login":"Seuss27"},"state":"APPROVED","commit":{"oid":"4633f82c9490882f7cd7881f6dfbab766f2bcf59"}}]}}}}}
```
exit: 0

#### 1a: dev App tries merge PR 11 at owner-pushed head

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/11/merge -f merge_method=squash -f sha=0fe0a04adae5286a510532d29443a2e96fa9794d

```
{"message":"Repository rule violations found\n\nNew changes require approval from someone other than Seuss27 because they were the last pusher.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

New changes require approval from someone other than Seuss27 because they were the last pusher.

 (HTTP 405)
```
exit: 1

#### 1b setup: dev App merges PR 10 so main moves

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/10/merge -f merge_method=squash -f sha=884a9cee3fe21638fbe302590efdebfe98aa50d3 --jq [.merged,.sha]

```
[true,"e19fea7f290f3bb74d69eeebb2364ea911b9deef"]
```
exit: 0

#### 1b: PR 12 mergeability before the push (approved, head 4633f82)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/12 --jq [.head.sha,.mergeable_state]

```
["4633f82c9490882f7cd7881f6dfbab766f2bcf59","unknown"]
```
exit: 0

#### 1b: create tree = PR12 head tree + main's free/i3.txt + extra file owned/extra-1b.txt

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/trees -f base_tree=4633f82c9490882f7cd7881f6dfbab766f2bcf59 -f tree[][path]=free/i3.txt -f tree[][mode]=100644 -f tree[][type]=blob -f tree[][sha]=669b399912fc61e1657a70c4e4a836f156c780f6 --jq .sha

```
80ed125c2f5ac474e6371b4fe89ad35dc4123615
```
exit: 0

#### 1b: add the extra change on top (owned/extra-1b.txt)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/trees -f base_tree=80ed125c2f5ac474e6371b4fe89ad35dc4123615 -f tree[][path]=owned/extra-1b.txt -f tree[][mode]=100644 -f tree[][type]=blob -f tree[][content]=extra change smuggled into a merge from main --jq .sha

```
1f00c7bd4c78028a75be57e9ee08f8f1702d969f
```
exit: 0

#### 1b: merge commit [PR12 head, main] with an extra change

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/commits/ee6cb4002fa365305d8974c3d1d831b2b89df209 --jq [.sha,(.parents|map(.sha))]

```
["ee6cb4002fa365305d8974c3d1d831b2b89df209",["4633f82c9490882f7cd7881f6dfbab766f2bcf59","e19fea7f290f3bb74d69eeebb2364ea911b9deef"]]
```
exit: 0

#### 1b: dev App moves item1-12 to the merge commit

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/git/refs/heads/item1-12 -f sha=ee6cb4002fa365305d8974c3d1d831b2b89df209 --jq .object.sha

```
ee6cb4002fa365305d8974c3d1d831b2b89df209
```
exit: 0

#### 1b: PR 12 after the dev App's merge push

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:12){headRefOid mergeStateStatus reviewDecision reviews(first:5){nodes{author{login} state commit{oid}}}}}}

```
{"data":{"repository":{"pullRequest":{"headRefOid":"ee6cb4002fa365305d8974c3d1d831b2b89df209","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","reviews":{"nodes":[{"author":{"login":"Seuss27"},"state":"DISMISSED","commit":{"oid":"4633f82c9490882f7cd7881f6dfbab766f2bcf59"}}]}}}}}
```
exit: 0

#### 1b: dev App tries merge PR 12 at the new head

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/12/merge -f merge_method=squash -f sha=ee6cb4002fa365305d8974c3d1d831b2b89df209

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from JaredGroves-603 and/or Seuss27.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from JaredGroves-603 and/or Seuss27.

 (HTTP 405)
```
exit: 1

#### 2: branch item2

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/item2 -f sha=e19fea7f290f3bb74d69eeebb2364ea911b9deef --jq .ref

```
refs/heads/item2
```
exit: 0

#### 2: open PR

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=item 2 auto-merge pin -f head=item2 -f base=main --jq [.number,.head.sha]

```
[13,"68fb676203cf61014480b3566594fc1e461c3b9b"]
```
exit: 0

#### 2: dev App arms auto-merge pinned to A=68fb676203cf61014480b3566594fc1e461c3b9b

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query=mutation{enablePullRequestAutoMerge(input:{pullRequestId:"PR_kwDOVBmbD88AAAABHhqhqg",mergeMethod:SQUASH,expectedHeadOid:"68fb676203cf61014480b3566594fc1e461c3b9b"}){pullRequest{autoMergeRequest{enabledBy{login}}}}}

```
{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"autoMergeRequest":{"enabledBy":{"login":"glunk-dev"}}}}}}
```
exit: 0

#### 2: dev App (a writer) pushes commit B after arming

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/owned/i2b.txt -f message=item 2: commit B (after arming) -f branch=item2 -f content=Qgo= --jq .commit.sha

```
7748a12883097941511a5a12f8b2752b82ebd87b
```
exit: 0

#### 2: PR state after the push

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:13){headRefOid mergeStateStatus reviewDecision autoMergeRequest{enabledBy{login} commitHeadline}}}}

```
{"data":{"repository":{"pullRequest":{"headRefOid":"7748a12883097941511a5a12f8b2752b82ebd87b","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED","autoMergeRequest":{"enabledBy":{"login":"glunk-dev"},"commitHeadline":null}}}}}
```
exit: 0

#### 2: PR 13 after maintainer approval of head B

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/13 --jq [.state,.merged,.merged_by.login,.merge_commit_sha,.head.sha]

```
["closed",true,"glunk-dev[bot]","57407c86ca2af525f0ba19e9209e8b12eff6f6f5","7748a12883097941511a5a12f8b2752b82ebd87b"]
```
exit: 0

#### 2: commits on main (squash of A+B?)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/commits?per_page=2 --jq [.[]|[.sha,.commit.message]]

```
[["57407c86ca2af525f0ba19e9209e8b12eff6f6f5","item 2 auto-merge pin (#13)\n\n* item 2: commit A\n\n* item 2: commit B (after arming)\n\n---------\n\nCo-authored-by: glunk-dev[bot] \u003c339840170+glunk-dev[bot]@users.noreply.github.com\u003e"],["e19fea7f290f3bb74d69eeebb2364ea911b9deef","item 3: uncovered path (#10)\n\nCo-authored-by: glunk-dev[bot] \u003c339840170+glunk-dev[bot]@users.noreply.github.com\u003e"]]
```
exit: 0

#### 1b: PR 12 reviews now

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/12/reviews --jq [.[]|[.id,.user.login,.state,.commit_id]]

```
[[5469611821,"Seuss27","DISMISSED","4633f82c9490882f7cd7881f6dfbab766f2bcf59"],[5469671494,"Seuss27","APPROVED","a5cd01fafce08f39e526f2c1ba7bc0cc1c2c8f52"]]
```
exit: 0

#### 1b: PR 12 mergeability

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/12 --jq [.mergeable_state,.head.sha]

```
["clean","a5cd01fafce08f39e526f2c1ba7bc0cc1c2c8f52"]
```
exit: 0

#### 1: PR 12 state: approver (Seuss27) pushed a pure base merge a5cd01f then approved it

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:12){headRefOid mergeStateStatus reviewDecision}}}

```
{"data":{"repository":{"pullRequest":{"headRefOid":"a5cd01fafce08f39e526f2c1ba7bc0cc1c2c8f52","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED"}}}}
```
exit: 0

#### 4: reviewer App dismisses Seuss27's live approval 5469671494 on PR 12

as: review App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/12/reviews/5469671494/dismissals -f message=reviewer App dismissal test -f event=DISMISS --jq [.id,.state]

```
[5469671494,"DISMISSED"]
```
exit: 0

#### 4: PR 12 state after the dismissal attempt

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:12){headRefOid mergeStateStatus reviewDecision}}}

```
{"data":{"repository":{"pullRequest":{"headRefOid":"a5cd01fafce08f39e526f2c1ba7bc0cc1c2c8f52","mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED"}}}}
```
exit: 0

#### 5: admin token works before revocation (read ruleset names)

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/rulesets --jq [.[]|.name]

```
["wb-approval","wb-checks","wb-tags"]
```
exit: 0

#### 8 setup: admin App creates second scratch repo

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X POST orgs/glunk-works/repos -f name=wb-ruleset-scratch-2 -F private=true --jq [.full_name,.private]

```
["glunk-works/wb-ruleset-scratch-2",true]
```
exit: 0

#### 8: admin token's installation repositories after creating repo 2

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api installation/repositories --jq [.total_count,(.repositories|map(.full_name))]

```
[1,["glunk-works/wb-ruleset-scratch"]]
```
exit: 0

#### 8: admin token reads repo 2 permissions

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-2 --jq [.full_name,.permissions]

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/repos#get-a-repository","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### 8: admin token reads repo 2 contents

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-2/rulesets --jq length

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/rules#get-all-repository-rulesets","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### 6 setup: branch item6

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/item6 -f sha=57407c86ca2af525f0ba19e9209e8b12eff6f6f5 --jq .ref

```
refs/heads/item6
```
exit: 0

#### 6 setup: open PR (skip ci so no Actions status)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=item 6 fake status from another App -f head=item6 -f base=main --jq [.number,.head.sha]

```
[14,"841538ed1223709df42aa62c05d7e0859879548c"]
```
exit: 0

#### 6: statuses on head before any fake

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/841538ed1223709df42aa62c05d7e0859879548c/status --jq [.state,.total_count]

```
["pending",0]
```
exit: 0

#### 6: dev App (installation now has statuses:write) posts scratch/status=success

as: dev App token (statuses=write) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/statuses/841538ed1223709df42aa62c05d7e0859879548c -f state=success -f context=scratch/status -f description=fake from another App --jq [.context,.state,.creator.login,.creator.type]

```
["scratch/status","success","glunk-dev[bot]","Bot"]
```
exit: 0

#### 6: statuses after the fake

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/841538ed1223709df42aa62c05d7e0859879548c/status --jq [.state,[.statuses[]|[.context,.state,.creator.login]]]

```
["success",[["scratch/status","success",null]]]
```
exit: 0

#### 6: dev App tries merge PR 14 (no approval yet, fake status in place)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/14/merge -f merge_method=squash -f sha=841538ed1223709df42aa62c05d7e0859879548c

```
{"message":"Repository rule violations found\n\nNew changes require approval from someone other than the last pusher.\n\nRequired status check \"scratch/status\" was not set by the expected GitHub app.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

New changes require approval from someone other than the last pusher.

Required status check "scratch/status" was not set by the expected GitHub app.

 (HTTP 405)
```
exit: 1

#### 6: PR 14 required-check state

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"glunk-works",name:"wb-ruleset-scratch"){pullRequest(number:14){mergeStateStatus reviewDecision}}}

```
{"data":{"repository":{"pullRequest":{"mergeStateStatus":"BLOCKED","reviewDecision":"REVIEW_REQUIRED"}}}}
```
exit: 0

#### 8: admin token (minted before repo 2 joined the installation) reads repo 2

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-2 --jq .full_name

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/repos#get-a-repository","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### 8: admin token's installation repositories now

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api installation/repositories --jq [.total_count,(.repositories|map(.full_name))]

```
[1,["glunk-works/wb-ruleset-scratch"]]
```
exit: 0

#### 8: dev token minted with --repos wb-ruleset-scratch, installation covers 2 repos: installation/repositories

as: dev App token (narrowed to repo 1) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api installation/repositories --jq [.total_count,(.repositories|map(.full_name))]

```
[1,["glunk-works/wb-ruleset-scratch"]]
```
exit: 0

#### 8: same token reads repo 2 contents

as: dev App token (narrowed to repo 1) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-2/contents/ --jq length

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/contents#get-repository-content","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### 8: same token writes to repo 2

as: dev App token (narrowed to repo 1) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch-2/contents/x.txt -f message=x -f content=eAo=

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/contents#create-or-update-file-contents","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### 8: token minted with --repos wb-ruleset-scratch-2: installation/repositories

as: dev App token (narrowed to repo 2) (installation repos [1,["glunk-works/wb-ruleset-scratch-2"]])
$ gh api installation/repositories --jq [.total_count,(.repositories|map(.full_name))]

```
[1,["glunk-works/wb-ruleset-scratch-2"]]
```
exit: 0

#### 8: same token reads repo 1

as: dev App token (narrowed to repo 2) (installation repos [1,["glunk-works/wb-ruleset-scratch-2"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/contents/README.md --jq .name

```
README.md
```
exit: 0

#### 8: repo 1 visibility (explains the cross-read above)

as: Seuss27 user token
$ gh api repos/glunk-works/wb-ruleset-scratch --jq [.private,.visibility]

```
[false,"public"]
```
exit: 0

#### 8: token narrowed to repo 2 tries a WRITE to repo 1

as: dev App token (narrowed to repo 2) (installation repos [1,["glunk-works/wb-ruleset-scratch-2"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/x8.txt -f message=x -f branch=item6 -f content=eAo=

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/repos/contents#create-or-update-file-contents","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### 8: admin token (minted --repos wb-ruleset-scratch, installation covers 2 repos): installation/repositories

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api installation/repositories --jq [.total_count,(.repositories|map(.full_name))]

```
[1,["glunk-works/wb-ruleset-scratch"]]
```
exit: 0

#### 8: admin token reads repo 2

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-2/rulesets

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/rules#get-all-repository-rulesets","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### 5: admin token works just before revoke

as: admin App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/rulesets --jq [.[]|.name]

```
["wb-approval","wb-checks","wb-tags"]
```
exit: 0

#### 5: the SAME admin token after wow-admin --revoke (12:25:16Z)

as: admin App token (revoked at 12:25:10Z; the helper reach guard is bypassed on purpose because the token is expected to fail it)
$ gh api repos/glunk-works/wb-ruleset-scratch/rulesets --jq [.[]|.name]

```
{
  "message": "Bad credentials",
  "documentation_url": "https://docs.github.com/rest",
  "status": "401"
}gh: Bad credentials (HTTP 401)
```
exit: 1

#### 5: the SAME admin token after wow-admin --revoke (12:25:17Z)

as: admin App token (revoked at 12:25:10Z; the helper reach guard is bypassed on purpose because the token is expected to fail it)
$ gh api installation/repositories --jq .total_count

```
{
  "message": "Bad credentials",
  "documentation_url": "https://docs.github.com/rest",
  "status": "401"
}gh: Bad credentials (HTTP 401)
```
exit: 1

## Raw output, session 4 (2026-10-09, UTC 12:40-13:20)

#### 1: releases and immutable flag

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases --jq [.[]|[.id,.tag_name,.draft,.immutable]]

```
[[407908295,"v0.0.2",false,true],[407908196,"v0.0.1",false,true]]
```
exit: 0

#### 2: edit release notes of immutable v0.0.1

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/releases/407908196 -f body=edited by dev App --jq [.id,.body]

```
[407908196,"edited by dev App"]
```
exit: 0

#### 3: edit release title of immutable v0.0.1

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/releases/407908196 -f name=renamed by dev App --jq [.id,.name]

```
[407908196,"renamed by dev App"]
```
exit: 0

#### 4: upload asset to immutable v0.0.1

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X POST https://uploads.github.com/repos/glunk-works/wb-ruleset-scratch/releases/407908196/assets?name=a2.txt -H Content-Type: text/plain --input /c/Users/SR116/AppData/Local/Temp/claude/c--Users-SR116-projects-glunk-works-claude-workbench/4f158e7d-5815-41f2-920d-fb934d93e452/scratchpad/a2.txt --jq .id

```
{"message":"Cannot upload assets to an immutable release.","request_id":"C1EF:22DE11:1AB4E:2BD62:6AC8E398","documentation_url":"https://docs.github.com/rest"}gh: Cannot upload assets to an immutable release. (HTTP 422)
```
exit: 1

#### 5: delete asset of immutable v0.0.1

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/releases/assets/624955950

```
{"message":"Validation Failed","errors":[{"resource":"ReleaseAsset","code":"custom","message":"Cannot delete asset from an immutable release"}],"documentation_url":"https://docs.github.com/rest/releases/assets#delete-a-release-asset","status":"422"}gh: Validation Failed (HTTP 422)
```
exit: 1

#### 6: delete tag ref v0.0.1

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/git/refs/tags/v0.0.1

```
{"message":"Repository rule violations found\n\nCannot delete this tag\n\n","documentation_url":"https://docs.github.com/rest/git/refs#delete-a-reference","status":"422"}gh: Repository rule violations found

Cannot delete this tag

 (HTTP 422)
```
exit: 1

#### 7: retarget tag via release PATCH

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/releases/407908196 -f tag_name=v0.0.1 -f target_commitish=main --jq [.id,.tag_name]

```
[407908196,"v0.0.1"]
```
exit: 0

#### 8: assets afterwards

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases/407908196 --jq [.name,.body,[.assets[].name],.immutable]

```
["renamed by dev App","edited by dev App",["a1.txt"],true]
```
exit: 0

#### 9: tags before

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/matching-refs/tags --jq [.[]|[.ref,.object.sha]]

```
[["refs/tags/scratch-h2","6a7a2b3fd9fd5be2b1314b40a7875ab4e54a7a6b"],["refs/tags/v-case-g","fe67508bcb741339d974e22bf194a6f421c8ceed"],["refs/tags/v-case-g-rel","fe67508bcb741339d974e22bf194a6f421c8ceed"],["refs/tags/v0.0.1","57407c86ca2af525f0ba19e9209e8b12eff6f6f5"],["refs/tags/v0.0.2","57407c86ca2af525f0ba19e9209e8b12eff6f6f5"]]
```
exit: 0

#### 10: delete immutable release v0.0.2

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/releases/407908295

```

```
exit: 0

#### 11: releases and tags after the delete

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases --jq [.[]|[.id,.tag_name,.draft,.immutable]]

```
[[407908196,"v0.0.1",false,true]]
```
exit: 0

#### 11b: tags after the delete

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/matching-refs/tags --jq [.[]|[.ref,.object.sha]]

```
[["refs/tags/scratch-h2","6a7a2b3fd9fd5be2b1314b40a7875ab4e54a7a6b"],["refs/tags/v-case-g","fe67508bcb741339d974e22bf194a6f421c8ceed"],["refs/tags/v-case-g-rel","fe67508bcb741339d974e22bf194a6f421c8ceed"],["refs/tags/v0.0.1","57407c86ca2af525f0ba19e9209e8b12eff6f6f5"],["refs/tags/v0.0.2","57407c86ca2af525f0ba19e9209e8b12eff6f6f5"]]
```
exit: 0

#### 12: dev App creates a draft release for the deleted tag name

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases -f tag_name=v0.0.2 -f name=redo -F draft=true -f target_commitish=main --jq [.id,.draft,.tag_name,.immutable]

```
[407912729,true,"v0.0.2",false]
```
exit: 0

#### 13: dev App creates a draft release for a new tag

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases -f tag_name=v-draft-439 -f name=draft439 -F draft=true -f target_commitish=main --jq [.id,.draft,.tag_name]

```
[407912737,true,"v-draft-439"]
```
exit: 0

#### 14: all releases

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases --jq [.[]|[.id,.tag_name,.draft,.immutable]]

```
[[407912729,"v0.0.2",true,false],[407908196,"v0.0.1",false,true]]
```
exit: 0

#### 15: dev App publishes the draft that reuses the deleted release's tag v0.0.2

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/releases/407912729 -F draft=false --jq [.id,.draft,.tag_name]

```
{"message":"Validation Failed","errors":[{"resource":"Release","code":"custom","field":"tag_name","message":"tag_name was used by an immutable release"}],"documentation_url":"https://docs.github.com/rest/releases/releases#update-a-release","status":"422"}gh: Validation Failed (HTTP 422)
```
exit: 1

#### 16: dev App publishes the draft for new tag v-draft-439

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/releases/407912737 -F draft=false --jq [.id,.draft,.tag_name]

```
{"message":"Validation Failed","errors":[{"resource":"Release","code":"custom","field":"pre_receive","message":"pre_receive Repository rule violations found\n\nCannot create ref due to creations being restricted.\n\n"},{"resource":"Release","code":"custom","message":"Published releases must have a valid tag"}],"documentation_url":"https://docs.github.com/rest/releases/releases#update-a-release","status":"422"}gh: Validation Failed (HTTP 422)
```
exit: 1

#### 17: main head, for the v0.0.1 tag target check

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/main --jq .sha

```
57407c86ca2af525f0ba19e9209e8b12eff6f6f5
```
exit: 0

#### 18: tag v0.0.1 target

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/ref/tags/v0.0.1 --jq .object.sha

```
57407c86ca2af525f0ba19e9209e8b12eff6f6f5
```
exit: 0

#### 19: cleanup, delete draft 407912729

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/releases/407912729

```

```
exit: 0

#### 20: cleanup, delete draft 407912737

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/releases/407912737

```

```
exit: 0

#### 21: releases at the end

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/releases --jq [.[]|[.id,.tag_name,.draft,.immutable]]

```
[[407908196,"v0.0.1",false,true]]
```
exit: 0

#### A1: branch case9 (the PR branch)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case9 -f sha=57407c86ca2af525f0ba19e9209e8b12eff6f6f5 --jq .ref

```
refs/heads/case9
```
exit: 0

#### A2: commit on case9

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/free/case9.txt -f message=case 9: reviewed change -f branch=case9 -f content=Y2FzZTkK --jq .commit.sha

```
03ca21081bfbfc1b8039699cf11135af114ca514
```
exit: 0

#### A3: branch case9-side (what the merge commit will merge in)

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/git/refs -f ref=refs/heads/case9-side -f sha=57407c86ca2af525f0ba19e9209e8b12eff6f6f5 --jq .ref

```
refs/heads/case9-side
```
exit: 0

#### A4: commit on case9-side

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/contents/free/case9-side.txt -f message=case 9: side branch change -f branch=case9-side -f content=c2lkZQo= --jq .commit.sha

```
fd315f1868a8a0e630a290624c91ae63c459570f
```
exit: 0

#### A5: open the PR

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls -f title=case 9: approver pushes a merge commit with extra changes -f head=case9 -f base=main --jq [.number,.head.sha,.user.login]

```
[15,"03ca21081bfbfc1b8039699cf11135af114ca514","glunk-dev[bot]"]
```
exit: 0

#### B1: PR 15 head, mergeable state

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/15 --jq [.head.sha,.mergeable_state,.merged]

```
["0823d241bbcf325868fdb81f669245ad44912497","blocked",false]
```
exit: 0

#### B2: PR 15 commits

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/15/commits --jq [.[]|[.sha[0:7],.commit.author.name,.commit.committer.name,(.parents|length),.commit.message]]

```
[["03ca210","glunk-dev[bot]","GitHub",1,"case 9: reviewed change"],["fd315f1","glunk-dev[bot]","GitHub",1,"case 9: side branch change"],["0823d24","Jared Groves","Jared Groves",2,"Merge case9-side into case9"]]
```
exit: 0

#### B3: merge commit changed files vs first parent

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/0823d241bbcf325868fdb81f669245ad44912497 --jq [.parents[].sha[0:7],[.files[]|[.filename,.status]]]

```
["03ca210","fd315f1",[["free/case9-side.txt","added"],["free/extra-in-merge.txt","added"]]]
```
exit: 0

#### B4: PR 15 reviews

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/15/reviews --jq [.[]|[.user.login,.state,.commit_id[0:7]]]

```
[["Seuss27","DISMISSED","03ca210"]]
```
exit: 0

#### B5: dev App merge attempt

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/15/merge -f merge_method=squash -f sha=0823d241bbcf325868fdb81f669245ad44912497 --jq [.merged,.sha]

```
{"message":"Repository rule violations found\n\nNew changes require approval from someone other than the last pusher.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

New changes require approval from someone other than the last pusher.

 (HTTP 405)
```
exit: 1

#### C1: PR 15 reviews after the re-approve

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/15/reviews --jq [.[]|[.user.login,.state,.commit_id[0:7],.submitted_at]]

```
[["Seuss27","DISMISSED","03ca210","2026-10-09T12:57:55Z"],["Seuss27","APPROVED","0823d24","2026-10-09T13:00:00Z"]]
```
exit: 0

#### C2: PR 15 state

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/15 --jq [.head.sha[0:7],.mergeable_state,.merged]

```
["0823d24","blocked",false]
```
exit: 0

#### C3: dev App merge attempt after the re-approve

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PUT repos/glunk-works/wb-ruleset-scratch/pulls/15/merge -f merge_method=squash -f sha=0823d241bbcf325868fdb81f669245ad44912497 --jq [.merged,.sha]

```
{"message":"Repository rule violations found\n\nNew changes require approval from someone other than Seuss27 because they were the last pusher.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

New changes require approval from someone other than Seuss27 because they were the last pusher.

 (HTTP 405)
```
exit: 1

#### D1: close PR 15

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/15 -f state=closed --jq [.number,.state,.merged]

```
[15,"closed",false]
```
exit: 0

#### D2: delete branch case9

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/git/refs/heads/case9

```

```
exit: 0

#### D3: delete branch case9-side

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X DELETE repos/glunk-works/wb-ruleset-scratch/git/refs/heads/case9-side

```

```
exit: 0

#### D4: main head unchanged

as: dev App token (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/commits/main --jq .sha

```
57407c86ca2af525f0ba19e9209e8b12eff6f6f5
```
exit: 0

#### 2A(scratch): installation permissions

as: glunk-review App token A(scratch) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api installation/repositories --jq [.repositories[]|[.full_name,.private]]

```
[["glunk-works/wb-ruleset-scratch",false]]
```
exit: 0

#### 2A(scratch): read scratch repo

as: glunk-review App token A(scratch) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch --jq [.full_name,.private]

```
["glunk-works/wb-ruleset-scratch",false]
```
exit: 0

#### 2A(scratch): read scratch-3 repo (private)

as: glunk-review App token A(scratch) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-3 --jq [.full_name,.private]

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/repos#get-a-repository","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### 2A(scratch): read scratch-3 README

as: glunk-review App token A(scratch) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-3/contents/README.md --jq .path

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/contents#get-repository-content","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### 2A(scratch): read scratch PR 14

as: glunk-review App token A(scratch) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/14 --jq [.number,.title]

```
[14,"item 6 fake status from another App"]
```
exit: 0

#### 2A(scratch): write: retitle scratch PR 14

as: glunk-review App token A(scratch) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/14 -f title=item6 (touched by reviewer token A(scratch)) --jq [.number,.title]

```
[14,"item6 (touched by reviewer token A(scratch))"]
```
exit: 0

#### 2A(scratch): write: restore title of scratch PR 14, if it changed

as: glunk-review App token A(scratch) (installation repos [1,["glunk-works/wb-ruleset-scratch"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/14 -f title=item6 --jq [.number,.title]

```
[14,"item6"]
```
exit: 0

#### 2B(scratch-3): installation permissions

as: glunk-review App token B(scratch-3) (installation repos [1,["glunk-works/wb-ruleset-scratch-3"]])
$ gh api installation/repositories --jq [.repositories[]|[.full_name,.private]]

```
[["glunk-works/wb-ruleset-scratch-3",true]]
```
exit: 0

#### 2B(scratch-3): read scratch repo

as: glunk-review App token B(scratch-3) (installation repos [1,["glunk-works/wb-ruleset-scratch-3"]])
$ gh api repos/glunk-works/wb-ruleset-scratch --jq [.full_name,.private]

```
["glunk-works/wb-ruleset-scratch",false]
```
exit: 0

#### 2B(scratch-3): read scratch-3 repo (private)

as: glunk-review App token B(scratch-3) (installation repos [1,["glunk-works/wb-ruleset-scratch-3"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-3 --jq [.full_name,.private]

```
["glunk-works/wb-ruleset-scratch-3",true]
```
exit: 0

#### 2B(scratch-3): read scratch-3 README

as: glunk-review App token B(scratch-3) (installation repos [1,["glunk-works/wb-ruleset-scratch-3"]])
$ gh api repos/glunk-works/wb-ruleset-scratch-3/contents/README.md --jq .path

```
{"message":"This repository is empty.","documentation_url":"https://docs.github.com/v3/repos/contents/#get-contents","status":"404"}gh: This repository is empty. (HTTP 404)
```
exit: 1

#### 2B(scratch-3): read scratch PR 14

as: glunk-review App token B(scratch-3) (installation repos [1,["glunk-works/wb-ruleset-scratch-3"]])
$ gh api repos/glunk-works/wb-ruleset-scratch/pulls/14 --jq [.number,.title]

```
[14,"item6"]
```
exit: 0

#### 2B(scratch-3): write: retitle scratch PR 14

as: glunk-review App token B(scratch-3) (installation repos [1,["glunk-works/wb-ruleset-scratch-3"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/14 -f title=item6 (touched by reviewer token B(scratch-3)) --jq [.number,.title]

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/pulls/pulls#update-a-pull-request","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### 2B(scratch-3): write: restore title of scratch PR 14, if it changed

as: glunk-review App token B(scratch-3) (installation repos [1,["glunk-works/wb-ruleset-scratch-3"]])
$ gh api -X PATCH repos/glunk-works/wb-ruleset-scratch/pulls/14 -f title=item6 --jq [.number,.title]

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/pulls/pulls#update-a-pull-request","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1


## Raw output, session 5 (2026-10-09, UTC 14:05-14:25)

#### a1: dev App creates a branch

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/git/refs -f ref=refs/heads/s5-a -f sha=5bc45e5d01d08722391d17a9fc8c16f6f568a20f --jq [.ref,.object.sha[0:7]]

```
["refs/heads/s5-a","5bc45e5"]
```
exit: 0

#### a2: dev App commits a file to the branch

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/contents/s5/a.txt -f message=s5: case a file -f branch=s5-a -f content=Y2FzZSBhCg== --jq [.commit.sha[0:7],.commit.author.name]

```
["ed71faa","603id-dev[bot]"]
```
exit: 0

#### a3: dev App opens a PR

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/pulls -f title=s5 case a -f head=s5-a -f base=main -f body=case a: dev App PR --jq [.number,.user.login,.mergeable_state]

```
[1,"603id-dev[bot]","unknown"]
```
exit: 0

#### a4: dev App tries to approve its own PR

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/pulls/1/reviews -f event=APPROVE -f body=self

```
{"message":"Unprocessable Entity","errors":["Review Can not approve your own pull request"],"documentation_url":"https://docs.github.com/rest/pulls/reviews#create-a-review-for-a-pull-request","status":"422"}gh: Unprocessable Entity (HTTP 422)
```
exit: 1

#### a5: dev App tries to merge PR 1

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/pulls/1/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from JaredGroves-603.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from JaredGroves-603.

 (HTTP 405)
```
exit: 1

#### r1: dev App reads rules/branches/main

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/rules/branches/main --jq map([.ruleset_source_type,.ruleset_source,.ruleset_id,.type])

```
[["Organization","603-Identity",24792211,"pull_request"],["Organization","603-Identity",24792211,"deletion"],["Organization","603-Identity",24792211,"non_fast_forward"],["Repository","603-Identity/identity-ruleset-scratch",24792209,"required_status_checks"]]
```
exit: 0

#### r2: dev App reads repo rulesets

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/rulesets --jq map([.id,.name,.source_type])

```
[[24792211,"wb-approval","Organization"],[24792209,"wb-checks","Repository"],[24792210,"wb-tags","Repository"]]
```
exit: 0

#### r3: reviewer App reads rules/branches/main

as: reviewer App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/rules/branches/main --jq map([.ruleset_source_type,.ruleset_id,.type])

```
[["Organization",24792211,"pull_request"],["Organization",24792211,"deletion"],["Organization",24792211,"non_fast_forward"],["Repository",24792209,"required_status_checks"]]
```
exit: 0

#### r4: reviewer App reads repo rulesets

as: reviewer App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/rulesets --jq map([.id,.name])

```
[[24792211,"wb-approval"],[24792209,"wb-checks"],[24792210,"wb-tags"]]
```
exit: 0

#### r5: dev App reads the org ruleset

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api orgs/603-Identity/rulesets/24792211 --jq [.id,.name]

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/orgs/rules#get-an-organization-repository-ruleset","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### h1: maintainer creates a branch

as: JaredGroves-603 user token (user.login JaredGroves-603)
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/git/refs -f ref=refs/heads/s5-human -f sha=5bc45e5d01d08722391d17a9fc8c16f6f568a20f --jq [.ref]

```
["refs/heads/s5-human"]
```
exit: 0

#### h2: maintainer commits a file

as: JaredGroves-603 user token (user.login JaredGroves-603)
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/contents/s5/human.txt -f message=s5: maintainer-authored change -f branch=s5-human -f content=aHVtYW4K --jq [.commit.sha[0:7],.commit.author.name]

```
["abf9786","JaredGroves-603"]
```
exit: 0

#### h3: maintainer opens a PR

as: JaredGroves-603 user token (user.login JaredGroves-603)
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/pulls -f title=s5 maintainer-authored -f head=s5-human -f base=main -f body=human-authored PR --jq [.number,.user.login]

```
[2,"JaredGroves-603"]
```
exit: 0

#### h4: maintainer tries to approve their own PR

as: JaredGroves-603 user token (user.login JaredGroves-603)
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/pulls/2/reviews -f event=APPROVE -f body=self

```
{"message":"Unprocessable Entity","errors":["Review Can not approve your own pull request"],"documentation_url":"https://docs.github.com/rest/pulls/reviews#create-a-review-for-a-pull-request","status":"422"}gh: Unprocessable Entity (HTTP 422)
```
exit: 1

#### h5: maintainer tries to merge their own PR

as: JaredGroves-603 user token (user.login JaredGroves-603)
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/pulls/2/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nNew changes require approval from someone other than the last pusher.\n\nRequired status check \"scratch/status\" is expected.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

New changes require approval from someone other than the last pusher.

Required status check "scratch/status" is expected.

 (HTTP 405)
```
exit: 1

#### c1: PR 1 head status

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/commits/ed71faa/status --jq [.state,[.statuses[]|[.context,.state,.creator.login]]]

```
["success",[["scratch/status","success",null]]]
```
exit: 0

#### c2: dev App arms auto-merge on PR 1 (pinned to the head)

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api graphql -f query=mutation($id:ID!,$oid:GitObjectID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH,expectedHeadOid:$oid}){pullRequest{number autoMergeRequest{enabledBy{login} mergeMethod}}}} -f id=PR_kwDOVCgNa88AAAABHjI3HQ -f oid=ed71faa8c5bcd007677943bb4634ac2e8cd3d8f5

```
{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"number":1,"autoMergeRequest":{"enabledBy":{"login":"603id-dev"},"mergeMethod":"SQUASH"}}}}}
```
exit: 0

#### b1: dev App branch for the dismissal case

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/git/refs -f ref=refs/heads/s5-b -f sha=5bc45e5d01d08722391d17a9fc8c16f6f568a20f --jq [.ref]

```
["refs/heads/s5-b"]
```
exit: 0

#### b2: dev App commits to s5-b

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/contents/s5/b.txt -f message=s5: case b file -f branch=s5-b -f content=Y2FzZSBiCg== --jq [.commit.sha[0:7]]

```
["e356d9d"]
```
exit: 0

#### b3: dev App opens PR 3

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/pulls -f title=s5 case b -f head=s5-b -f base=main -f body=case b: approve, then push --jq [.number,.user.login]

```
[3,"603id-dev[bot]"]
```
exit: 0

#### c3: PR 1 after the approval

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/pulls/1 --jq [.merged,.merged_by.login,.merged_at,.merge_commit_sha[0:7]]

```
[false,null,null,"3b2cdc2"]
```
exit: 0

#### c4: PR 1 reviews

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/pulls/1/reviews --jq map([.user.login,.state,.submitted_at])

```
[["JaredGroves-603","APPROVED","2026-10-09T14:11:22Z"]]
```
exit: 0

#### b4: PR 3 reviews before the push

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/pulls/3/reviews --jq map([.user.login,.state,.commit_id[0:7]])

```
[["JaredGroves-603","APPROVED","e356d9d"]]
```
exit: 0

#### b5: dev App pushes a second commit to s5-b

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/contents/s5/b2.txt -f message=s5: case b second push -f branch=s5-b -f content=YWdhaW4K --jq [.commit.sha[0:7]]

```
["8f63d20"]
```
exit: 0

#### b6: PR 3 reviews and decision after the push

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/pulls/3/reviews --jq map([.user.login,.state,.commit_id[0:7]])

```
[["JaredGroves-603","APPROVED","e356d9d"]]
```
exit: 0

#### b7: PR 3 merge attempt after the push

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/pulls/3/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from JaredGroves-603.\n\nRequired status check \"scratch/status\" is expected.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from JaredGroves-603.

Required status check "scratch/status" is expected.

 (HTTP 405)
```
exit: 1

#### c5: PR 1 merged state and time

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/pulls/1 --jq [.merged,.merged_by.login,.merged_at,.merge_commit_sha[0:7]]

```
[true,"603id-dev[bot]","2026-10-09T14:13:23Z","f0fe9a2"]
```
exit: 0

#### b8: PR 3 reviewDecision and reviews after the push

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api graphql -f query={repository(owner:"603-Identity",name:"identity-ruleset-scratch"){pullRequest(number:3){reviewDecision mergeStateStatus headRefOid reviews(first:5){nodes{author{login} state commit{oid}}}}}}

```
{"data":{"repository":{"pullRequest":{"reviewDecision":"REVIEW_REQUIRED","mergeStateStatus":"UNKNOWN","headRefOid":"8f63d20555fdf7f0423bb76c288c7c5e350d371a","reviews":{"nodes":[{"author":{"login":"JaredGroves-603"},"state":"DISMISSED","commit":{"oid":"e356d9d04b66e255e7f0df1ecd875a8c7ff53efb"}}]}}}}}
```
exit: 0

#### b9: PR 3 merge attempt, full message

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/pulls/3/merge -f merge_method=squash

```
{"message":"Repository rule violations found\n\nWaiting on code owner review from JaredGroves-603.\n\nRequired status check \"scratch/status\" is expected.\n\n","documentation_url":"https://docs.github.com/rest/pulls/pulls#merge-a-pull-request","status":"405"}gh: Repository rule violations found

Waiting on code owner review from JaredGroves-603.

Required status check "scratch/status" is expected.

 (HTTP 405)
```
exit: 1

#### c6: dev App branch for the second auto-merge run

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/git/refs -f ref=refs/heads/s5-c2 -f sha=f0fe9a280646132333ff71ece9bc0527058d77f1 --jq [.ref]

```
["refs/heads/s5-c2"]
```
exit: 0

#### c7: dev App commits to s5-c2

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/contents/s5/c2.txt -f message=s5: second auto-merge run -f branch=s5-c2 -f content=YzIK --jq [.commit.sha[0:7]]

```
["4295829"]
```
exit: 0

#### c8: dev App opens PR 4

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X POST repos/603-Identity/identity-ruleset-scratch/pulls -f title=s5 second auto-merge run -f head=s5-c2 -f base=main -f body=case c, second run --jq [.number,.user.login]

```
[4,"603id-dev[bot]"]
```
exit: 0

#### c9: dev App arms auto-merge on PR 4

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api graphql -f query=mutation($id:ID!,$oid:GitObjectID!){enablePullRequestAutoMerge(input:{pullRequestId:$id,mergeMethod:SQUASH,expectedHeadOid:$oid}){pullRequest{number autoMergeRequest{enabledBy{login}}}}} -f id=PR_kwDOVCgNa88AAAABHjNXLQ -f oid=42958290dabc125a37889178542a4ebcccac840b

```
{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"number":4,"autoMergeRequest":{"enabledBy":{"login":"603id-dev"}}}}}}
```
exit: 0

#### c10: PR 4 reviews

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/pulls/4/reviews --jq map([.user.login,.state,.submitted_at])

```
[["JaredGroves-603","APPROVED","2026-10-09T14:16:54Z"],["JaredGroves-603","APPROVED","2026-10-09T14:17:19Z"]]
```
exit: 0

#### c11: PR 4 merged state and time

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/pulls/4 --jq [.merged,.merged_by.login,.merged_at]

```
[true,"603id-dev[bot]","2026-10-09T14:17:37Z"]
```
exit: 0

#### o1: admin token reads the org ruleset through the org path

as: admin App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api orgs/603-Identity/rulesets/24792211 --jq [.id,.name,.enforcement]

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/orgs/rules#get-an-organization-repository-ruleset","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### o2: admin token reads the org ruleset through the repo path

as: admin App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/rulesets/24792211 --jq [.id,.name,.source_type,.enforcement]

```
[24792211,"wb-approval","Organization","active"]
```
exit: 0

#### o3: admin token tries to disable the org ruleset (org path)

as: admin App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT orgs/603-Identity/rulesets/24792211 -f enforcement=disabled

```
{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest/orgs/rules#update-an-organization-repository-ruleset","status":"403"}gh: Resource not accessible by integration (HTTP 403)
```
exit: 1

#### o4: admin token tries to disable the org ruleset (repo path)

as: admin App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/rulesets/24792211 -f enforcement=disabled

```
{"message":"Not Found","documentation_url":"https://docs.github.com/rest/repos/rules#update-a-repository-ruleset","status":"404"}gh: Not Found (HTTP 404)
```
exit: 1

#### o5: org ruleset enforcement afterwards (read back)

as: admin App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/rulesets/24792211 --jq [.enforcement]

```
["active"]
```
exit: 0

#### o6: admin token renames the repo ruleset wb-checks (contrast)

as: admin App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/rulesets/24792209 -f name=wb-checks-s5 --jq [.id,.name,.enforcement,.source_type]

```
[24792209,"wb-checks-s5","active","Repository"]
```
exit: 0

#### o7: admin token restores the name

as: admin App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PUT repos/603-Identity/identity-ruleset-scratch/rulesets/24792209 -f name=wb-checks --jq [.id,.name,.enforcement]

```
[24792209,"wb-checks","active"]
```
exit: 0

#### o8: admin token reads rulesets after the restore

as: admin App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/rulesets --jq map([.id,.name,.enforcement,.source_type])

```
[[24792211,"wb-approval","active","Organization"],[24792209,"wb-checks","active","Repository"],[24792210,"wb-tags","active","Repository"]]
```
exit: 0

#### z2: dev App closes PR 2

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PATCH repos/603-Identity/identity-ruleset-scratch/pulls/2 -f state=closed --jq [.number,.state]

```
[2,"closed"]
```
exit: 0

#### z3: dev App closes PR 3

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X PATCH repos/603-Identity/identity-ruleset-scratch/pulls/3 -f state=closed --jq [.number,.state]

```
[3,"closed"]
```
exit: 0

#### z-s5-human: delete branch

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X DELETE repos/603-Identity/identity-ruleset-scratch/git/refs/heads/s5-human

```

```
exit: 0

#### z-s5-b: delete branch

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X DELETE repos/603-Identity/identity-ruleset-scratch/git/refs/heads/s5-b

```

```
exit: 0

#### z-s5-a: delete branch

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X DELETE repos/603-Identity/identity-ruleset-scratch/git/refs/heads/s5-a

```
{"message":"Reference does not exist","documentation_url":"https://docs.github.com/rest/git/refs#delete-a-reference","status":"422"}gh: Reference does not exist (HTTP 422)
```
exit: 1

#### z-s5-c2: delete branch

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api -X DELETE repos/603-Identity/identity-ruleset-scratch/git/refs/heads/s5-c2

```
{"message":"Reference does not exist","documentation_url":"https://docs.github.com/rest/git/refs#delete-a-reference","status":"422"}gh: Reference does not exist (HTTP 422)
```
exit: 1

#### z9: final state of the repo

as: dev App token (installation repos [1,["603-Identity/identity-ruleset-scratch"]])
$ gh api repos/603-Identity/identity-ruleset-scratch/branches --jq map(.name)

```
["main"]
```
exit: 0


## Session 6 (#380): the plugin's identity reads under a dev App token

Run on 2026-10-09 against `603-Identity/identity-ruleset-scratch`, with tokens minted from the
dev App by `scripts/identity/mint.sh` (host config, key `dev.pem`), tokens kept in the session
scratchpad, never printed. Read-only except one `git push --dry-run`, which creates nothing
(confirmed: no `wow-380-probe` branch afterwards). Not a recorded-helper run: results below are
what the commands returned, not a raw log.

| Probe (token) | Result |
|---|---|
| `gh api user` (`contents:write, pull_requests:write`) | **403** "Resource not accessible by integration". The skills' bare `gh api user` fails under a dev App token; this is the first measurement of it. |
| `gh api repos/R --jq .permissions` (same) | `{"admin":false,"maintain":false,"pull":false,"push":false,"triage":false}`, exit 0. Confirms case i. |
| `installation/repositories` then `gh-identity.sh reach R` | `reached` (one repo listed). |
| `token-check.sh verify any R …` | `installation`. |
| milestones, rulesets, `rules/branches/main` (same token) | readable: `0` milestones, rulesets `wb-approval, wb-checks, wb-tags`, rule types `pull_request, deletion, non_fast_forward, required_status_checks`. |
| open issues, token with `contents`+`pull_requests` only | **403**. `reached` is not read access to Issues. |
| open issues, token with `issues: read, contents: read` | `0`, exit 0. The backlog reads work when the token carries `issues`. |
| `git push --dry-run` of a new branch, `contents: write` | succeeds (`[new branch] HEAD -> wow-380-probe`), nothing created. |
| same, `contents: read` | **403** "Write access to repository not granted", rc 128. |
| skill command sequences as the App, in a clone with a scratch `.ai/project.yml` | `schema-complete.sh` `complete`; `cursor-sync-pr.sh` `none`; `rulesets` and `rules/branches/main` readable (`pull_request, deletion, non_fast_forward`); prune's `gh pr list --state merged` works; `plan-gather.sh unmilestoned/milestones` exit 0; resume's review-step first link (`gh api user`) fails rc 1, so nothing derives. |
| retro/archive-sprint style writes: `gh issue create`, `comment`, `close` (`issues: write`) | all succeed. The created issue's `user` is `603id-dev[bot]`, id 340163647, `author_association` **NONE** (viewer-relative, as WB-D24 says). |
| ship end to end: branch, commit, `git push`, `gh pr create` (`contents`+`pull_requests` write) | all succeed. The PR's `user` is the same `[bot]` login and id; `mergeable_state` `blocked` (approval gate). The probe PR (#6) was closed and its branch deleted. ship's own preflight (`.permissions.push`) reads `false` here and would have stopped it. |
| `gh-identity.sh classify` / `role` / `author` with that `{login, id}` against an `identities` map declaring it as `dev_app` | `app` / `dev_app` / `untrusted`. So an App's `{login, id}` **is** obtainable: from the `user` of a write response, after a first write. |

Consequences recorded in `conventions.md` § *Acting identity and reach*: the `reached` probe is
read reach only; a backlog read needs a token minted with `issues`; `git push --dry-run` is a
working write probe for the credential `git` holds but does not say which App holds it; an App's
`{login, id}` comes from the `user` of a write response, so it can report who acted after the
first write but cannot gate it, which is why ship's push preflight still stops in App mode.
Not measured: the skills run as interactive Claude Code sessions (the command sequences above
were run by hand in a scratch clone), and resume's review-step derivation, which needs a user
login.


## Session 7 (#464 PR 2): the skills as interactive sessions under a dev-App token

Run on 2026-10-11 against `603-Identity/identity-ruleset-scratch`, following
[docs/identity/APP-MODE-RUN-SHEET.md](../identity/APP-MODE-RUN-SHEET.md). Each skill ran as a
`claude` CLI session in a VS Code terminal started with `GH_TOKEN` set from a token minted by
`scripts/identity/mint.sh`, with the plugin loaded by `--plugin-dir plugins/way-of-working` (the
0.17.0 source at `84ba6fc`; the scratch clone does not enable the plugin). Before each launch,
`gh api user` returned 403 and `installation/repositories` listed only the scratch repo. Results
below are the sessions' own summaries plus what GitHub shows afterwards, not a raw log. All seven
skills have now run; where a result rests only on a session's own report and was not read back
from GitHub, the row says so.

Setup, all by the dev App (`603id-dev[bot]`, id 340163647) unless noted: PR #7 added
`.ai/project.yml` (`identities.maintainer` JaredGroves-603 id 281693088, `dev_app`, `reviewer_app`
`603id-review[bot]` id 340164886 taken from `apps.json`, not yet seen in a write response);
the maintainer approved it and it merged by auto-merge. Milestones 1 and 2, issues #8 (milestone 1,
the task), #9 (milestone 1, closed) and #10 (no milestone). A local `.ai/state.json` and
`.ai/next-steps.md`, git-excluded, with `plan-anchor.sh verify` printing `match`.

| Skill | Result |
|---|---|
| resume | **Waited, for a reason the sheet did not expect.** The author-trust check on #8 came back untrusted: the dev App wrote the issue and `identities.maintainer` lists only the human. That is the fixture, not a plugin defect; auto-start under App mode needs a maintainer-authored task. `Ruleset check` healthy, read through an installation token. The review step read `none`: no PR existed yet, so `show <M> app-mode` was **not exercised**. After the human's `go` it read #8 once (`updated_at` matched the anchor) and made the edit. |
| ship | **Matched the sheet.** PR #11, author `603id-dev[bot]` id 340163647, `pr-actor` printed `match`, `git push --dry-run` passed, push pinned to `gh`'s token, `mergeable_state` `blocked`. `review.ci_gate` is `null`. **New:** the commit inside the PR is authored and committed by `Jared Groves <jared.groves@603identity.com>`, GPG-verified, because the clone uses the human's git config with `commit.gpgsign=true`; the session asked for the human's passphrase. The PR is the App's, the commit is the human's. |
| ship, wrong credential | **Stopped, but not at the designed check.** Token from the reviewer App (`contents: read`, `pull_requests: write`; `contents: write` was refused at mint, 422 "not granted to this installation"). The session stopped before commit, push or any probe, because `gh auth status` showed `603id-review[bot]` against the declared `603id-dev[bot]`. `ship/SKILL.md` has no such pre-push check; its designed catch is `pr-actor` after the PR exists. No other App here can push, so `mismatch` was **not reached live** (fixtures in `tests/gh-identity.test.sh` only). Filed as #476. |
| pr-checks, token without `statuses`/`checks` | **COULD NOT TELL.** `gh pr checks` (GraphQL), `commits/{sha}/status` and `commits/{sha}/check-runs` all returned 403. It gave no verdict and named the missing permissions. The run sheet's mint recommendation does not include them. |
| pr-checks, token with `statuses: read`, `checks: read` | **NOT READY, correct.** `scratch/status` green on `28cad25`; `BLOCKED`, `reviewDecision` `REVIEW_REQUIRED`; passed `green=0` to `blocked-state.sh`, as its header says to for `REVIEW_REQUIRED`. Fell back to REST because `gh pr checks` fails under an App token. Noted, without verifying, that the check is pinned to an app. **Block (c) was not reached:** the only `update` rule is in `wb-tags`, which targets `refs/tags/v*`, not `main` (`wb-approval` and `wb-checks` carry none), so the admin-merge path does not exist for this repo's branch. |
| merge | After the maintainer's approval and a green `scratch/status`, `gh pr merge 11 --auto --squash` run as the dev App merged PR #11 at once, 17:35:11 UTC, `merged_by` `603id-dev[bot]`. This is case k again. ship arms nothing, so the merge was a manual command; already tracked as #386 (a duplicate, #475, was filed and closed). |
| archive-sprint, first run | **Stopped at preconditions, and two defects.** (1) It read `backlog.repo: null` as "no repo" and stopped (#479). (2) It took the maintainer's "yes" to "do you want me to open the PRs?" as approval of the HITL gate, which precondition 1 says never to assume; when the approval was stated outright on the later run it respected it. The rest was the fixture: the README had no roadmap row and `.ai/archive/` was not ignored, so it opened two PRs, #12 and #13, with plain `git push`. The PRs' author was the dev App; the pusher was the maintainer's own credential. The maintainer's approval of #12 showed as "1 approval" but the merge stayed blocked: "New changes require approval from someone other than JaredGroves-603 because they were the last pusher." #14 and #15, the same changes pushed by the dev App through the contents API, merged on the first approval (`merged_by` `603id-dev[bot]`, 17:56:48 and 19:22:43 UTC). That the pusher is what GitHub counted is inferred from this contrast and the commit authors; the events API returned no push record. #12 and #13 were closed. Filed as #478. |
| archive-sprint, second run | **Worked up to the milestone close.** With the gate approved outright and a pinned-push instruction, it wrote the snapshot to `.ai/archive/` (ignored), advanced the cursor to scratch-2 (`planning`, `plan_anchor` null), pruned the one local branch whose merged PR tip matched, and left two it could not match. It pushed nothing and opened no PR. It did not check precondition 4 explicitly, and said so. The milestone close was **skipped**: #8 was still open, because PR #11's body had no `Closes #8` (the fixture). |
| milestone close, direct | **Succeeded, but not through the skill.** After the maintainer's yes, `PATCH` on issue #8 (`state=closed`) and on milestone 1 (`state=closed`) with the dev App token (`contents`, `pull_requests`, `issues` write; `statuses`, `checks` read) both returned success; the milestone closed at 19:27:50 UTC with 0 open and 2 closed issues. So `issues: write` covers closing a milestone. The skill's own close step was not exercised. |
| plan-sprint | **Matched the sheet where it ran.** The read-only gather worked, and the maintainer accepted placing #10 in milestone 2. Read back from GitHub: #10 is on milestone 2, and the triage comment (id 6112836920) is by `603id-dev[bot]`, `author_association` `NONE`. No milestone-description edit was needed, so the policy refusal and the staged script were **not exercised**. Its closing note said milestone 1 and #8 were still open; both had been closed minutes earlier, so that note was stale. |
| handoff, first run | **No PR.** `.ai/next-steps.md` was git-excluded in the fixture, so there was nothing to commit; it wrote the cursor, opened a gate (first anchor for milestone 2) and said so. It carried forward a `Milestone close:` line saying milestone 1 and #8 were open, already false. |
| handoff, second run | **Matched the sheet.** After the ledger was tracked (PR #16, App-authored, merged by the App after approval), it opened PR #17 with the cursor sync: author `603id-dev[bot]` id 340163647, one file changed, not merged, auto-merge not armed. The push was pinned because the maintainer said so, not because the skill does it (#478). The commit is again authored and committed by Jared Groves (verified). Read from GitHub: the PR's patch **removes** the stale `Milestone close:` line. It ran on Sonnet against an assigned opus and said so. This run chose the ledger PR; the no-op handoff was not exercised. |
| retro | **Found nothing, filed nothing.** Run in the dev-App session, it read the scratch backlog and judged that no friction met its signal bar (a model mismatch, a hand-written `sed`, the all-`false` `.permissions`, an untouched ledger on `main`, a CRLF warning), so it wrote nothing. The sheet's expected issue or comment under the dev App's login was therefore **not produced by retro**; that write path is shown by plan-sprint's comment above. |

| ship, declared `dev_app` wrong | **The designed `mismatch` stop, seen live.** A second probe, run after the rows above, because no other App here can push. PR #18 (dev App, approved and auto-merged) set `identities.dev_app` on `main` to `603id-mismatch[bot]`, id 999999999. ship was run with the real dev token and no extra instruction. Its preflight cleared (including the pinned `git push --dry-run`), it pushed the branch and opened PR #19 as `603id-dev[bot]`, and the actor check read `mismatch`: it stopped, added no label or comment, and left the PR for the maintainer. Read back from GitHub: #19 has 0 labels, 0 comments, auto-merge not armed. The stop came **after** the push and the PR, as #476 says. This stands in for a wrong credential with a wrong declaration; from ship's check the two are the same. PR #19 was closed and its branch deleted, and PR #20 restored the real `dev_app` (merged 19:54:16 UTC). |
| pr-checks, block (c) with an `update` rule | **Not reached, and not reachable here.** The maintainer's admin credential created a temporary branch ruleset `wow-464-update-probe` (an `update` rule on the default branch, repo admin role as the only bypass), so `main`'s rules read `deletion, non_fast_forward, pull_request, required_status_checks, update`. PR #21 (dev App) had `scratch/status` green and the maintainer's approval; GitHub showed "Merging is blocked: Cannot update this protected ref." pr-checks read `BLOCKED`, `reviewDecision` `APPROVED`, and returned **COULD NOT TELL**: `blocked-state.sh` refused to judge, naming three rules it cannot evaluate (the approval requirement, the code-owner review, the check pinned to an app). That refusal is its design (#248). Block (c) is only reached on the admin-merge path, which the approval gate removes; #384 replaces that verdict with `awaiting-approval`. The ruleset was deleted, #21 closed and its branch deleted. |

Follow-ups from this session: #476 (ship checks the acting App against `dev_app` before the push),
#478 (handoff and archive-sprint push as the human in App mode), #479 (archive-sprint reads a null
`backlog.repo` as no repo), and a comment on #386 (ship arms auto-merge). #478, #479 and the #386
comment came from a retro run in the maintainer's own session, not from the dev-App retro above;
#475 was filed as a duplicate of #386 and closed.

## Status against the run sheet's closing criteria

- Every skill has an entry above, including those that stopped. Met.
- ship's actor check seen to `match` for the dev App: met (#11). Seen to stop for a different
  credential: **met with a substitute.** With a reviewer-App token the stop was the session's own
  judgement before any write; the designed `mismatch` stop was then seen live with a wrong
  `dev_app` declaration standing in for the wrong credential (PR #19). A real wrong-App token that
  can push was never available.
- `pr-checks` block (c) seen under the dev App token: **not met, and not reachable on this
  repo.** With an `update` rule applied, `blocked-state.sh` returns `could not tell` on the
  approval and pinned-check rules, so block (c) is never printed. The path is the admin-merge
  verdict the approval gate retires (#384).

The first criterion is met; the second is met with the substitute described; the third is not
met as written and cannot be on a repo under the approval ruleset. The maintainer decides whether
to close #464 with the third criterion recorded as superseded by #384.

## Configuration changes made during session 7

- `603-Identity/identity-ruleset-scratch`: PRs #7 (`.ai/project.yml`), #11 (`s5/a.txt`), #14 and #15
  (README roadmap row, `.gitignore` and `backlog.repo`), #16 (tracks `.ai/next-steps.md`), all merged;
  #12 and #13 closed unmerged (replaced by #14 and #15); #17 (cursor sync) merged by the maintainer;
  #18 (a wrong `dev_app`) and #20 (restoring it) merged; #19 (ship's probe PR) and #21 (the block (c)
  probe) closed unmerged with their branches deleted. Milestones 1 (closed by a direct write at 19:27:50 UTC) and 2; issues #8 (closed by the same
  direct write), #9 (closed fixture) and #10 (placed in milestone 2).
- The clone's `.git/info/exclude` held `.ai/state.json` and, until #16 merged, `.ai/next-steps.md`.
- Tokens: dev App, `contents`/`pull_requests`/`issues` write, with `statuses`/`checks` read from the
  second token on; reviewer App, `contents: read` and `pull_requests: write`. All under an hour,
  minted to files outside any repo, never printed; the expired and reviewer files were deleted.
- Auto-merge was armed by hand as the dev App on #7, #11, #12, #13, #14, #15 and #16. On #11 it merged the PR
  at once, as described above.
- A temporary repo ruleset, `wow-464-update-probe`, was created with an admin-App token the
  maintainer minted (`administration: write`, passphrase entered by them) and deleted afterwards;
  the repo's rulesets are `wb-approval`, `wb-checks` and `wb-tags` again, and `main`'s rule types
  are as before. While it existed nothing could merge into `main`. No App or org setting was
  changed.

## Session 8 (#636): the App-mode review live run, first pass

Run on 2026-10-17 against `603-Identity/identity-ruleset-scratch`, following
[docs/identity/REVIEW-LIVE-RUN.md](../identity/REVIEW-LIVE-RUN.md). The host tools were installed
by `install-host-tools.ps1` into a separate `WOW_HOME`, `~/.config/603id-identity` (the 603 org's
App config; the default `~/.config/glunk-identity` holds the glunk-works Apps), from `ea6dbd8`,
with that `bin/` first on Git Bash's PATH. Docker Desktop 29.8.2, default log driver `local`. The
reviewed repo pins way-of-working `v0.19.0` (scratch PR #25) and sets `review.ci_gate` to
infrastructure-core's check name and wire strings, with `architect-review` added to `wb-checks`
as a required check from GitHub Actions (PR #26, then a ruleset edit). The PR under review is #27:
one line added to `s5/a.txt`, authored by `603id-dev[bot]` (id 340163647), head `46d6c4f`.

This first pass covers items 9 and 10 and part of item 1. The launcher's run log keeps only the
session's final message, not its init output, so items 2 to 8 need a run that records the
session's `system/init` and its own probes. Items 11 and 12 need deliberate setups (a push
mid-run, a second shell) that this pass did not make. Rows below say which.

**First attempt failed before the session started.** `wow-review … 27` printed `docker start
failed (1) and the session never started` (exit 1; both session tokens revoked; no ledger entry
kept). The launcher discards `docker start`'s stderr, so the start was reproduced with no
credentials (same image and flags, an empty bind source): `failed to initialize logging driver:
compression cannot be enabled when max file count is 1`. The `local` driver compresses unless told
not to, and refuses `max-file=1` with compression on, at start, after create succeeds. Fixed by
#695 (`--log-opt compress=false`), merged as `ea6dbd8`; the host tools were reinstalled from it
before the second attempt.

| Item | Result |
|---|---|
| 1. The skill loaded | **Partly recorded.** The session's final message names PR #27 and the pinned head `46d6c4f5…`, says it ran in container mode, and says it wrote the launcher's outbox through `review-outbox.sh`, consistent with `WOW_REVIEW_PR`/`WOW_REVIEW_SHA` reaching it. A `review-outbox.sh where` result was not captured. The run log held no token-shaped string. |
| 2. Plugin skills and agents load | **Not recorded.** The skill evidently ran (item 10); the agent list was not captured. |
| 3. `system/init` path | **Not recorded.** |
| 4. A managed `env` value reaches the session | **Not recorded.** |
| 5. Managed settings load under `--setting-sources user` | **Not recorded.** |
| 6. A mid-session project settings file is not loaded | **Not run.** |
| 7. Root `CLAUDE.md` under `--setting-sources user` | **Not recorded.** |
| 8. Output styles | **Not recorded.** |
| 9. Tag rulesets on the marketplace repo | **Pass**, read as an admin (Seuss27, `.permissions.admin` true). `protected-release-tags` (20554576): `active`, target `tag`, include `refs/tags/v*`, rules `deletion`, `non_fast_forward`, `update`, `bypass_actors` an empty array. `release-tag-creation` (23936220): `active`, target `tag`, include `refs/tags/v*`, rule `creation`, one bypass actor, Integration 5051322 (`claude-workbench-release`), mode `always`. |
| 10. One review through `wow-review` as the reviewer App | **Pass.** Launcher exit `0 (reviewed)`, 16:33:19 to 16:36:00 UTC. Review 5558811678 by `603id-review[bot]` (id 340164886), state `COMMENTED`, `commit_id` `46d6c4f`, submitted 16:35:56. Gate on the head afterwards: `architect-review` `success`, "Fresh-session review found (2026-10-17T16:35:56Z)". No findings filed; the review's one minor note (the `#636` in the added line resolves to the scratch repo's own #636) stayed in the body. **But the launcher's own gate poll logged `gate poll 1: failure`** two seconds after the post and stopped: it took the pre-review `failure` as final before the gate workflow re-ran (#699). The exit code does not depend on the poll. |
| 11. A moved head posts nothing | **Not run.** |
| 12. Session-token revocation | **Not measured.** The launcher logged `revoked a session token` for `review-sessions/<id>/session-token` and `review-host/<id>/copy-m0` at 16:35:43, before the post; no second-shell test of either copy was made. |

**Found by the session itself, in its final message.**

- The plugin's scripts can't be run by name in the container: `/home/app` is a Docker tmpfs, which
  Docker mounts `noexec` unless told otherwise, and the plugin is installed under it. The session
  ran each script as `bash <path>`. Filed as #697.
- The container-mode exempt-PR check at `architect-review/SKILL.md:543` fails as written: the
  `--jq` filter treats the `pulls/<N>/files` array as an object. Read literally, the skill then
  stops `needs-human` on every PR. **The session repaired the filter on its own initiative** (added
  `.[] |`), got `review`, and reported the departure. The outcome was right (the PR touches the
  gated `s5/`), but a reviewer repairing a fail-closed step unprompted is a finding in itself.
  Filed as #698.

**Found by the `security-critic` pass on #695**, not caused by it: the proxy, injector and holder
containers get no `--log-opt`, so under `json-file` their logs are unbounded, and the session
drives the proxy's (#696).

## Status against the live-run sheet

Items 9 and 10 pass. Items 1 to 8 are partly or not recorded, and 11 and 12 were not run. #636
stays open, and the poller (#626) is not registered: the sheet registers it only after every item
has passed. #697 and #698 change what the skill does in the container, so the remaining items are
best run after they land. #699 changes only the launcher's log.

## Configuration changes made during session 8

- `glunk-works/claude-workbench`: v0.19.0 released (#693) and pinned here (#694); #695 merged.
- `603-Identity/identity-ruleset-scratch`: PRs #25 (`.claude/settings.json` pinning v0.19.0, by
  `603id-dev[bot]`) and #26 (`review.ci_gate`, `architect-review` in `required_checks`, the ported
  `architect-review-gate.yml`, by `603id-admin[bot]`, since the dev App has no Workflows
  permission) merged. The `wb-checks` ruleset (24792209) gained a required `architect-review`
  context from integration 15368, applied with the maintainer's token after #26 merged. PR #27
  (the reviewed PR) is open and not to be merged.
- Tokens: two dev-App tokens (`contents`/`pull_requests` write, for #25 and #27; a third request
  adding `workflows: write` was refused at mint, 422), one admin-App token the maintainer minted
  (`contents`, `pull_requests`, `workflows` write), all scoped to the scratch repo, minted to files,
  never printed, and revoked when done (HTTP 204, or `wow-admin --revoke`).
- Host: tools installed into `~/.config/603id-identity/bin` from `ea6dbd8`; a Claude credential
  stored in `~/.config/603id-identity/claude-credential`. No App or org setting was changed.

## Session 9 (#636): the App-mode review live run, second pass

Run on 2026-10-20 against `603-Identity/identity-ruleset-scratch`, following
[docs/identity/REVIEW-LIVE-RUN.md](../identity/REVIEW-LIVE-RUN.md) as of `9229287` (#803). The host tools were
reinstalled into `~/.config/603id-identity` from `9229287` at 21:19:00 UTC, so the review image
ran the session with `--output-format stream-json --verbose` and the managed-only
`WOW_MANAGED_PROBE`. The reviewed repo pins way-of-working `v0.21.0` (scratch #29, after #28's `v0.20.0`), and
both probes were planted on its default branch by #30, byte for byte from the sheet; after
planting, `git grep -n WOW_MANAGED_PROBE` printed one line, probe (a)'s call 2. The PR under
review is #31, opened after #30 merged: one file added under `s5/`, authored by `603id-dev[bot]`
(id 340163647).

Three `wow-review` runs, each on Claude Code 2.1.289 in the container:

- **Run 1** (`1792531646-2327579`), head `858ddbd`, 21:27:26 to 21:30:00 UTC: `exit 0 (reviewed)`.
- **Run 2** (`1792532031-2329134`), `--rerun` on `858ddbd`, 21:33:52 to 21:35:04: `exit 1
  (head-moved)`. A helper watching the log pushed `f9c44e4` to #31, as `603id-dev[bot]`, at
  21:34:43, 46 seconds after the pin line.
- **Run 3** (`1792532180-2330041`), head `f9c44e4`, 21:36:20 to 21:38:46: `exit 0 (reviewed)`.

Each log's token-shape count (the sheet's scan) was 0 before anything was read from it. The logs
were read with the sheet's `awk` and `jq` recipes, named fields only. As the sheet's one limit
says, every answer below is what the stream shows; a process in the session could have forged
any of it.

| Item | Result |
|---|---|
| 1. The skill loaded | **Pass.** In all three runs the session part's first event is `system/init`, and the first tool call is the skill's `review-outbox.sh where`, which printed `container`. In run 1 that same call printed the `WOW_REVIEW_*` variables, `WOW_REVIEW_PR=31` and `WOW_REVIEW_SHA` among them. |
| 2. Plugin skills and agents load | **Pass.** `system/init` lists all twelve `way-of-working:` skills (29 skills in all) and the four `way-of-working:` agents (`architect`, `coder`, `docs-consistency`, `security-critic`) beside the built-ins. |
| 3. `system/init` path | **Answered in part.** way-of-working's path is `/home/app/.claude/plugins/cache/claude-workbench/way-of-working/0.21.0`, version `0.21.0`, under the plugin cache the entrypoint requires. Probe (a)'s calls 3 and 4 never ran, and the entrypoint does not log the `installPath` it checked, so the equality the sheet asks for is not shown. Other plugins listed: three with path `builtin`, `cc-plugin-sec-default`, `cc-plugin-agents-md` and `cc-plugin-plugin-authoring`; what they load was not examined. |
| 4. A managed `env` value reaches the session | **Unanswered.** Probe (a) never ran (see item 7). |
| 5. Managed settings load under `--setting-sources user` | **Unanswered**, since item 4 is. `system/init` shows `analytics_disabled: true`, but the entrypoint sets `DISABLE_TELEMETRY` too, so that does not isolate the managed file. |
| 6. A mid-session project settings file is not loaded | **Unanswered.** Probe (a)'s calls 5 to 9 never ran. |
| 7. Root `CLAUDE.md` under `--setting-sources user` | **Unanswered: not loaded, or loaded and not followed.** None of the 13, 7 and 13 tool calls of the three runs is a probe call, and none names `CLAUDE.md`; no tool result holds the probe's first line. |
| 8. Output styles | **Answered: not active under these flags.** `system/init`'s `output_style` is `default` in all three runs, and no final message starts with `WOWSTYLE` (each run has its `result` event). The selecting settings file is the project's, which `--setting-sources user` does not read, so this does not isolate `strictPluginOnlyCustomization`. |
| 9. Tag rulesets on the marketplace repo | **Pass**, re-read on 2026-10-20 as an admin (Seuss27, `.permissions.admin` true), unchanged from session 8: `protected-release-tags` (20554576) `active`, target `tag`, include `refs/tags/v*`, rules `deletion`, `non_fast_forward`, `update`, `bypass_actors` empty; `release-tag-creation` (23936220) `active`, target `tag`, include `refs/tags/v*`, rule `creation`, one bypass actor, Integration 5051322, mode `always`. |
| 10. One review through `wow-review` as the reviewer App | **Pass, twice.** Run 1: review 5591976826 by `603id-review[bot]` (id 340164886), `COMMENTED`, `commit_id` `858ddbd`, submitted 21:29:39. Run 3: review 5592085482, same author and state, `commit_id` `f9c44e4`, submitted 21:38:26. `architect-review` was `success` on each head afterwards. No findings were filed. Each run's gate poll logged `failure, not posted after the review` once, then `success`: #718's wait on the pre-review state, not a fault. |
| 11. A moved head posts nothing | **Pass.** Run 2's session wrote `review-outbox.sh outcome stopped "$WOW_REVIEW_PR" "$WOW_REVIEW_SHA" head-moved`, carrying the pinned SHA. The launcher logged `the head moved (f9c44e4…); nothing posted, entry kept` and exited 1; #31 still had only run 1's review. Run 3 then reviewed the new head (item 10). |
| 12. Session-token revocation | **Pass.** In run 3 the launcher logged `revoked a session token (…/copy-m0)` at 21:38:11. A helper in a second shell then called `repos/603-Identity/identity-ruleset-scratch` once with that copy, in place, at 21:38:12: `HTTP/2.0 401 Unauthorized`. The revoked token was refused at once, so it had no lifetime after the revoke to measure. Afterwards `review-host/` and `review-sessions/` were empty. |

**Why probe (a) never ran.** It depends on the session acting on the root `CLAUDE.md`, and in
three sessions it did not. The stream cannot tell "not loaded" from "loaded and not followed".
The fallback that does not depend on `CLAUDE.md`, a scripted probe session (#799), was declined.

## Status against the live-run sheet

Items 1, 2 and 9 to 12 pass, item 8 is answered, item 3 is answered in part, and items 4 to 7
are unanswered. On 2026-10-20 the maintainer accepted item 3's missing comparison and items 4 to
7 as unanswered, and declined #799. The reasons:

- **Item 6:** the session already runs with `bypassPermissions`, so a settings file it writes
  gains it nothing (the entrypoint's `--setting-sources user` residual).
- **Item 7:** the `WB-D24` instruction-file residual already assumes the root `CLAUDE.md` loads.
- **Items 4 and 5:** if the managed file does not load, `strictPluginOnlyCustomization` is absent.
  What that would let in sits on the same default branch, behind the same code-owner rule, as
  `CLAUDE.md`. `WB-D24` now carries that as its own residual.

`WB-D24` item 7 is marked live-verified, and #636 closes. The poller (#626) may be registered once
the probe cleanup (scratch #32) merges.

## Configuration changes made during session 9

- `glunk-works/claude-workbench`: v0.21.0 released (#801) and pinned here (#802); #803 (#798)
  merged.
- `603-Identity/identity-ruleset-scratch`: #28 (pin `v0.20.0`), #29 (pin `v0.21.0`) and #30 (the
  probes) merged, all by `603id-dev[bot]`. #31 (the reviewed PR) is open and not to be merged.
  #32, which removes both probes and the `outputStyle` key, is open for the maintainer's approval.
  The contents API's `DELETE` gave unverified commits for the App, unlike its `PUT`, so #32's
  branch was remade as one `createCommitOnBranch` commit, which GitHub signed.
- Tokens: six dev-App tokens (`contents`/`pull_requests` write, scoped to the scratch repo), for
  #28, #29, #30, #31, the item 11 push and #32. Each was minted to a file, never printed, its
  viewer checked as `603id-dev[bot]`, and revoked when done (HTTP 204).
- Host: tools reinstalled into `~/.config/603id-identity/bin` from `9229287`. No App or org
  setting was changed.
