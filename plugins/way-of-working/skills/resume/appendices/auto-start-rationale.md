# Resume appendix — why auto-start is not a lost approval

Loaded on demand; nothing in the auto-start decision depends on reading it.

   **Why auto-start is not a lost approval:** the `next_action` was written by the
   previous session's `/way-of-working:handoff` — which the human approved by merging its
   cursor-sync PR. A merge on GitHub approves the ledger's **Next:**, which `next_action`
   should match but which nothing compares (`WB-D24` removed the `/resume` merge that once
   showed `next_action` beside it, `WB-D20`). A cursor whose PR is still open was never
   approved, which is why the *Report a forgotten cursor-sync PR* step's other outcomes wait.
   Re-approving it at the start of the next session approves the same decision twice, and
   in practice that second approval is a content-free "go" the overwhelming majority of the
   time. The approval that carries real signal is the **`hitl_gate`**, and it is still
   absolutely enforced. Auto-start removes a rubber stamp, not a gate. It also never
   crosses a merge boundary: `/way-of-working:critic-gate` still proposes and the human still
   picks (said of its diff mode; its spec mode runs inside the drafting step, selects by rule and
   escalates to a human instead of asking), and the human still merges. One derived step is the exception to "nothing here posts
   a review" (`WB-D22`): after a no-op handoff, the *Derive the review step from GitHub*
   step's `auto` verdict starts `/way-of-working:architect-review <M> --pin <oid>` — the first
   review this plugin posts without a human approving that step. It rests on the derivation
   (GitHub state the session cannot shape, the default branch's gate, a fresh session, the
   pin), not on `next_action`, which nobody approves in that shape; the review is still never
   an approval or a merge. Since `WB-D24` nothing shows `next_action` beside a merged ledger; in
   this shape it never reaches `main` at all.
