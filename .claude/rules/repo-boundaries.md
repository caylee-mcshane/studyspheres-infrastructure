<!-- SYNCED FILE — identical in content in backend, frontend and
     studyspheres-infrastructure. NOT installed in studyspheres-docs: nothing deploys
     there, so the close-out ordering below has no step 2, and that repo states its own
     write boundary in CLAUDE.md. Canonical copy: manager/rules-canonical/repo-boundaries.md
     Do not edit here. Edit the canonical copy, then propagate to all three.
     Line endings differ by repo git config and are not drift; any difference in
     the text is. Verify with manager/tools/check-rule-sync.py. -->

## Repo boundaries and close-out order

Repo boundaries — read wide, write narrow

Read: any sibling repo. Backend, frontend, infrastructure, docs. Reading another repo to answer a question is expected, not exceptional — a question like "does the client branch on this field" is answerable by reading the repo that owns it, and should be answered rather than left open.

Write: this repo, and the docs repo. Nothing else. A session rooted in one code repo does not edit another code repo, ever, for any reason — not a one-line fix, not a matching change, not a typo. Report it instead; it belongs to a session rooted there.

The docs repo is a shared surface. All three code repos write to it. That means:

Pull before editing docs. Always. Your checkout may be behind another session's commit.
If more than one session is running, only one edits controlled documents. The backlog, the launch checklist, architecture.md, the ADRs and the runbooks are shared mutable state; two sessions editing them produce a conflict or a silent overwrite, and the failure looks like confusion rather than an error. Confirm with the owner, exactly as with staging exclusivity.
Handbacks are per-session files and do not collide. They are exempt from the one-writer rule.
Documentation at close — order matters

1. The handback is written and committed to the docs repo before the deploy. It is a record of the session, not a claim about the system, so it does not depend on the deploy going green. It is also the only record if the session ends unexpectedly, which is why it does not wait.

2. The change is applied to the running system, and verified applied from the system itself — a hash against the deployed artefact, a live query, a resource read back. A green workflow, or a command that exited zero, proves dispatch rather than application.

3. Controlled documents are edited only after that. architecture.md, the backlog, the launch checklist, the ADRs, the runbooks. Not before.

The reason is specific: a red deploy produces fixes, and a document written before it describes a version that never existed. Then either the document is wrong or somebody has to remember to go back — and the thing nobody remembers is the second edit. Documents record what shipped, not what was expected to ship. This is the same principle as the closing claim: written at close, from evidence, not in advance as a prediction.

If you must document ahead of the deploy, say so explicitly and say why.

Every documentation edit is approved by the owner before it is committed

Propose the exact text, not a description of the change. On approval, commit it yourself in the docs repo. Do not commit an unapproved documentation edit, and do not commit an approved one with wording you have since altered.

What still does not change
Findings leave with no home assigned. You hold one subunit and cannot see the campaign sequence; placement happens outside your session. Report what was observed, what was not verified, and what follows if it holds.
A campaign letter may be cited in a controlled document only once that campaign has started. You cannot know which have. Describe later work by what it does, and let the owner substitute a letter if one applies.
The handback is not replaced by the documentation edits. It carries the mechanism of each error, the populations, the standing-rule dispositions and what was verified in neither test nor deployment. Controlled documents carry what is true now. Do not thin the handback because something also appears in a document.
One architecture changelog entry per campaign or Detour, appended to by each subunit. Do not open a second.
