---
name: park-sprint
description: >-
  Set the live sprint aside: snapshot its cursor as tracked files under .ai/parked/, seed
  the live cursor for the next sprint or swap in a parked one, and open one docs-only
  cursor-sync PR. Mechanical — any model. Never merges.
---

# /way-of-working:park-sprint <next-sprint-id> — set one sprint aside, start another

One live cursor is the design. A parked sprint is a tracked snapshot beside it:
`.ai/parked/<id>-state.json` and `.ai/parked/<id>-next-steps.md`. `.ai/parked/` is
**tracked**, unlike git-ignored `.ai/archive/`, because a parked cursor is the only copy of
in-flight state. `/way-of-working:unpark-sprint` brings it back.

**Read `.ai/project.yml` first** for `{repo}`, `{pr_base}`, `{sprints_dir}`, `{roadmap}`, `{models}`,
`{code_paths}`, `{ruleset.required_checks}`, `{review.ci_gate}`, `{planning.kind}`, and —
under `github_milestones` — `{backlog.repo}` (`null` means `{repo}`).

## Preconditions — fail closed, stop at the first that fails

1. `.ai/state.json` exists and parses. `<id>` is its `current_sprint_id`; null means
   nothing to park — say so and stop. `<next-sprint-id>` must differ from `<id>`.
2. The tree is clean: `git status --short` prints nothing. Dirty state is this session's
   work — surface it; never fold it in, never `git stash` it.
3. The snapshots would be tracked: `git check-ignore .ai/parked/<id>-state.json
   .ai/parked/<id>-next-steps.md` must exit **1** and print nothing. Exit 0 prints the
   path a consumer ignore rule swallows, so the PR would carry nothing — stop and name it.
4. No `.ai/parked/<id>-*` exists — a second park would overwrite the first.

## Steps

1. **Snapshot, on the branch you stand on.** `mkdir -p .ai/parked`. Copy `.ai/state.json`
   to `.ai/parked/<id>-state.json`, writing `"lanes": null` in place of whatever the live
   cursor holds (the array is derived live-session data, `WB-D34`, `#797`, and the snapshot
   is tracked), and adding `parked_at` (ISO date) and `parked_reason` (one
   line — ask the human; never invent it). Copy `.ai/next-steps.md` to
   `.ai/parked/<id>-next-steps.md` **unchanged**.
2. **Stand on a current `{pr_base}`**: `git fetch origin {pr_base} && git checkout
   {pr_base} && git pull`. If a link refuses — a fetch failure, or `{pr_base}` already
   carrying `.ai/parked/<id>-*` from a park elsewhere — stop and say which. Then add `parked_from_commit`
   (`git rev-parse --short HEAD`) to the snapshot. Recorded here, on `{pr_base}`, it is
   normally an ancestor of later HEADs, which the range unpark shows the human relies on.
3. **Seed the live cursor.** If both `.ai/parked/<next-sprint-id>-*` files exist, this is
   a **swap**: seed nothing, run `/way-of-working:unpark-sprint <next-sprint-id>` now, and
   let it open the one PR for both. Otherwise follow `/way-of-working:handoff`'s
   *Determine the new cursor* through *Regenerate `.ai/next-steps.md`* steps by
   reference — same fields, wholesale rewrite, `hitl_gate` always written, `pointers.review_pr: null` (`WB-D22`) — **with two
   deliberate overrides.** First: **this step never writes a `plan_anchor`**, whatever
   `{planning.kind}` is. Anchoring a spec is a judgment call about an approved plan, and
   this skill is mechanical, run by any model; seeding one here would let a non-judgment
   step manufacture the human gate `/way-of-working:handoff`'s own re-anchor rule exists to
   require. Second, **under `{planning.kind}: github_milestones`, this step ensures the new
   cursor carries exactly one `**Milestone close:**` line.** `/way-of-working:handoff`'s own
   carry-forward rule (one of the steps this one follows by reference) already fires here —
   this step's new cursor's `sprint_status` is always `planning` under this kind, exactly the
   condition that rule carries forward under — so **let it**: if the ledger being overwritten
   already has a line, it carries forward **verbatim**, unchanged from that rule. Do not
   replace it. The line names the most recent *Close the sprint's milestone* outcome, and
   parking `<next-sprint-id>`'s predecessor changes nothing about whether that milestone
   actually closed — a blocked, failed-read, or pending outcome recorded there is exactly as
   true after the park as before it, and overwriting it with a placeholder would silently
   drop the one live record of an outstanding close, which is #153's failure again, freshly
   introduced by this very fix. **Only when no line exists yet** does this step write one:
   ```
   **Milestone close:** no milestone to close (previous sprint parked, not archived)
   ```
   — the shape a sprint parked before `/way-of-working:archive-sprint` ever ran against it
   takes: nothing has closed yet, so there is nothing to carry forward. Contrast
   `/way-of-working:archive-sprint`'s own unpark-branch note, which **does** replace
   unconditionally — there, a close genuinely just happened, so the old line is stale by
   definition, never merely unresolved.
   At column 0, never as a list item — the same paragraph shape `**Now:**`/`**Next:**`
   already use in this ledger.

   `sprint_status` branches on `{planning.kind}`, unchanged from before this key existed for
   `files`: `planning` unless `{sprints_dir}/<next-sprint-id>*/sprint_plan.md`
   exists, then `implementing` — a file already on disk is itself the mechanical, no-judgment
   signal this skill is allowed to act on. **Under `github_milestones` there is no file to
   test, so `sprint_status` is always `planning` here** — never auto-detect `implementing`
   from a milestone's mere existence or its issue count, because unlike a file landing via a
   reviewed PR, a milestone or its issues can exist without anyone having approved them as
   *this* sprint's plan, and this mechanical skill does not make that judgment call. Also
   under `github_milestones`: ask the human which milestone number is the next sprint (never
   scan open milestones — that cannot tell the live sprint from a parked one,
   `reference/project-schema.md` § `planning`) and write it as `pointers.sprint_plan:
   https://github.com/{backlog.repo}/milestone/<number>`, or `null` with `plan_anchor: null`
   if none is picked yet — the legal "no milestone picked yet" state the schema names.

   In the ledger, **Just done** is one line, `parked <id>: <parked_reason>`. The directory is
   the authority for what is parked and the session banner derives its `Parked:` line from
   it; never copy the list into the ledger.
4. **Commit as one docs-only cursor-sync PR** per `/way-of-working:handoff`'s *Commit
   `.ai/next-steps.md` as its own docs-only PR against `{pr_base}`* step, with
   three files staged: both snapshots and `.ai/next-steps.md`. That delta is what
   `cursor-drift.sh` classifies as `cursor-sync`, so handoff's "one file" rule reads here
   as "these three and nothing else". In a swap this step does not run —
   unpark-sprint's *Commit as one docs-only cursor-sync PR* step opened the PR. **Never merge.** Report the PR URL and stop.

## Guardrails

- Mechanical: no design decision is made here, so any model may run it.
- Never write secrets into a snapshot — it is tracked.
