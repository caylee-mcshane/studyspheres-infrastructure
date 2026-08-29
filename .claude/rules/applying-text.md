<!-- SYNCED FILE — identical in content in backend, frontend, studyspheres-infrastructure
     and studyspheres-docs. Canonical copy: manager/rules-canonical/applying-text.md
     Do not edit here. Edit the canonical copy, then propagate to all four.
     Line endings differ by repo git config and are not drift; any difference in
     the text is. Verify with manager/tools/check-rule-sync.py. -->

## Standing rule — applying text to a file

Two rules about the mechanics of putting text into a file. Both were learned by
doing the thing they now forbid.

### Owner-approved prose is applied, never composed

Where the owner supplies text, it is **applied verbatim.** Do not paraphrase,
reflow, shorten, improve, or write a sentence to join two supplied blocks
together. If a supplied block reads oddly in its destination, **report that; do
not adjust it.**

Supplied text arrives **as a file, with a path. Read it from disk.** Terminal
output is a lossy rendering of a file — transmissions have lost whole spans at
line boundaries and silently dropped indentation the file carried correctly.
**Only fenced blocks in a supplied file are text to apply**; everything around
them is reasoning written for the owner, not instruction for you.

Where a supplied block needs formatting to sit correctly in its destination —
heading level, list continuation, indentation, numbering — **apply the formatting
and report that you did**, with the content verified byte-identical once the
added prefix is stripped.

⚠ **Assembly describes where the words came from, not whether the result is
correct in its new home.** A block applied unchanged can be correctly copied and
render wrong. A back-reference that is true in the source can be false in the
destination. This holds for the owner's text as much as for text you assembled:
approval establishes that the words are the owner's, never that they are true
where they land. **Read the result as a whole thing, in place, before reporting
it applied.**

### Verify the staged blob against HEAD's blob, not the working file against itself

Before committing any file edit, check what is **staged** against what is in
**HEAD** — not the working file against your own intent.

⚠ **The signal is a whole-file diff on a small edit.** If a one-line change
reports fifty insertions and forty-nine deletions whose visible text is
identical, stop. That is a line-ending conversion, and it is invisible in every
instrument otherwise in use here: text-mode tools silently strip carriage
returns, `git diff` normalises line endings away, and **a content digest cannot
see line-ending state at all** — it is computed on normalised content and passes
throughout.

The fix is to **match the blob's convention, not the checkout's.** Preserving the
working tree's line endings is not sufficient on its own; that was tried and
produced the whole-file diff described above.

**The mechanism is unexplained** — two repositories with identical resolved
configuration, from a single shared origin, staged an identical write
differently. **The rule does not depend on the mechanism**, which is what makes
it usable in a repository nobody has examined.
