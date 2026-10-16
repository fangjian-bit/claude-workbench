# App-mode review live run: `wow-review` and the review container

For #636 (WB-D24 item 7). The launcher (`scripts/identity/wow-review`, #635), the review image
(#634) and the skill's container mode (#636) are each tested against stubs only. No real session
has written an outbox, and no review has been posted through this flow. This sheet is the
maintainer's one-time run that closes that gap. A session cannot start itself in the container,
so the maintainer launches it.

Record results in `docs/proposals/IDENTITY-SCRATCH-RESULTS.md` as a new session, in the same
shape as the earlier ones: what was run, what came back, what it means. If an item does not do
what this sheet expects, that is the finding. Write down what happened; do not adjust the sheet
to match. When every item has an entry, a small follow-up marks `WB-D24` item 7 live-verified and
closes #636.

## Prerequisites

- **A way-of-working release containing #634 and #636,** pinned by the reviewed repo
  (`.claude/settings.json`'s `extraKnownMarketplaces` ref is a `v*` tag; the entrypoint refuses
  anything else, and refuses an installed plugin without `bin/review-outbox.sh`).
- **The reviewer App granted Issues write and Actions read,** and each installation's owner has
  accepted the new permissions in the browser. Until then a strict `--read` or `--file` mint is
  refused. That change is the maintainer's; nothing in the repo makes it.
- **Host tools installed** from committed code on `origin/main` (`install-host-tools.ps1`), with
  `$WOW_HOME/bin` on Git Bash's PATH, a Claude credential in `$WOW_HOME/claude-credential`, and
  Docker running.
- **The scratch repository** `603-Identity/identity-ruleset-scratch` (private; the approval
  ruleset applies), with `.ai/project.yml` declaring `identities` as a map including
  `reviewer_app`, `review.ci_gate` set, and the plugin pinned. Open one small PR in it that
  touches a path under the gate's triggers.

## Items

For each: run it, and record what happened, including the output that shows it.

1. **The skill loaded.** The review runs under `claude -p`, and the session's Bash tool sees
   `WOW_REVIEW_PR` and `WOW_REVIEW_SHA`. Record the session log's first lines and one
   `review-outbox.sh where` result (`container`). The log may hold secrets or private content
   (the launcher says so): scan it for token shapes before copying any of it into the results.
2. **Plugin skills and agents load** under the managed settings file and `--setting-sources user`.
3. **`system/init`'s path for way-of-working** equals the `installPath` the entrypoint checked.
   Note the other plugins that load.
4. **A managed `env` value reaches the session.**
5. **Managed settings load** under `--setting-sources user` at all.
6. **A project settings file written mid-session is not loaded.** Have the session write
   `.claude/settings.json` in the clone, then show that nothing in it took effect.
7. **Whether the reviewed repo's root `CLAUDE.md` loads** under `--setting-sources user`.
   Either answer is a result; record which.
8. **Whether the base's output styles load.** `strictPluginOnlyCustomization`'s coverage of them
   is unverified.
9. **The marketplace repository's `v*` tag rulesets** still hold. `protected-release-tags` blocks
   update, non-fast-forward and deletion with no bypass actors, and `release-tag-creation` blocks
   creation except for the release workflow's App (the two the entrypoint's header names). This is
   a read of its rulesets, not a test push. Read them as an admin: a ruleset read without admin
   rights may omit `bypass_actors`, and an absent field means unknown, not none. Also check each
   has enforcement `active`, targets tags, and includes `refs/tags/v*`.
10. **One review posted on the PR head through `wow-review`, as the reviewer App,** with the review
    gate green on that head. Record the launcher's exit code (0), the review's author and
    `commit_id`, the gate's state, and any findings filed and their labels.
11. **A moved head posts nothing.** Push to the PR branch while a session runs (or between the
    session's pin and its outcome), and show the launcher exits 1 with `head-moved`, posts no
    review, and the old head's ledger entry is kept. The new head has no entry until
    `wow-review` is run for it; run it once more and record that review too.
12. **Session-token revocation, measured for the stateless token format.** The launcher keeps
    copies of the session token in `review-host/<id>/copy-m*` and `copy-r*` and deletes that
    directory when it exits. The window to use one is after the launcher logs
    `revoked a session token (<file>)` for that copy and before it exits (the post, the gate poll
    and any filing). Test only a copy whose path appears on such a line: a copy it skipped as
    expired or not a `ghs_` token proves nothing, and a `revocation FAILED` line is a different
    cause from the token format. Leave `read-token`, `post-token` and `revoked` alone; they sit in
    the same directory and give a misleading result. Test in place from a second shell, without
    copying the token anywhere or echoing it, for example
    `GH_TOKEN="$(sed -n 1p <copy>)" gh api --hostname github.com repos/<scratch> -i`, and record
    only the HTTP status and the time. Never paste a token into the results doc or a command that
    reaches shell history. A call still accepted after the revoke is the finding; record how long
    the token lived. Afterwards confirm `review-host/<id>/` is gone, and delete it if it is not.
