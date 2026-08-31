<!-- SYNCED FILE — identical in content in backend, frontend, studyspheres-infrastructure
     and studyspheres-docs. Canonical copy: manager/rules-canonical/derived-facts.md
     Do not edit here. Edit the canonical copy, then propagate to all four.
     Line endings differ by repo git config and are not drift; any difference in
     the text is. Verify with manager/tools/check-rule-sync.py. -->

## Standing rule — where a fact belongs

Adopted 2026-08-31. It reaches every repo's `CLAUDE.md`, every rules file, and every spec.

Three kinds of fact, three homes. Filing one in the wrong drawer is how a document goes quietly
wrong while still reading as authoritative.

### DF-1. A fact derivable from the code carries its DERIVATION, not its result

Counts, line numbers, file sizes, "how many call sites" — anything a command can answer. Write
the command. Do not write the answer.

`grep -n "^def .*prompt" prompts.py` is durable. `10` is wrong the moment someone adds a prompt.

**This is measured, not theoretical.** In one `CLAUDE.md`, **8 of 20 count claims had drifted —
40%.** In one controlled document, **15 of 23 line-number citations had drifted — 65%.** Nobody
was careless: each was true when written, each was nearly free to write, and **nothing existed
that would notice when it stopped being true.**

⚠ **A stale derived fact is worse than no fact**, because it still reads as authoritative. A
missing number sends a reader to the code. A wrong one sends them nowhere and they do not know it.

**Correcting one replaces it with its derivation — never with a fresher result.** A refreshed
number drifts again on the same schedule, and the correction will have bought nothing.

### DF-2. A fact about what changed, and when, belongs in the CHANGELOG

Not in `CLAUDE.md`, and not in a dated snapshot embedded in prose. The changelog is append-only,
dated, attributed to a unit, and designed for exactly this. A count carrying a date duplicates it
badly: the changelog says *what* was added and *why*, which is what a reader actually needs.

If you find yourself dating a number so a future reader can tell what moved, the changelog
already answers that question better. Write the changelog entry instead.

### DF-3. `CLAUDE.md` and the rules carry only what is NEITHER

Decisions and the reasoning behind them · constraints that are not visible in the code ·
"do not do X, because otherwise Y silently produces a plausible wrong answer" · which of two
apparently-equivalent paths is the one that works · anything an agent cannot reconstruct by
reading and cannot find in the record.

That is what these files are for, and it is the half that cannot be regenerated. Everything else
competes with a better source and loses to it over time.

### DF-4. Where a count must actually hold, put it in a test

A number in prose is not a guard. It goes stale in silence and nothing fires. A number in a
guardrail test **fires** when the thing it counts changes, which is the behaviour prose was
attempting and never had.

⚠ Guardrails ship only after being observed failing against a deliberate violation. Adding one is
a unit with a done-when, not a line added in passing.

### DF-5. Applying this

**When writing:** ask whether a command could answer this. If it could, write the command.

**When correcting:** remove the derived fact and leave the derivation. Do not update it.

**When you find a stale one:** it is a finding, and the class matters more than the instance —
a document carrying one stale count usually carries others, and they went stale for the same
reason. Sweep before fixing, and state the population you swept.
