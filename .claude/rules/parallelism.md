## Parallel sessions and worktrees

**PL-1. Worktrees isolate checkouts. They do not isolate staging.** Only one test suite or probe
touches staging at a time, regardless of which checkout it runs from. Test identities' balances
and tiers are shared mutable state, and a second concurrent run does not fail loudly — it corrupts
the run already going, and the corruption presents as flakiness.

**PL-2. Parallelism is for read-only recon and for authoring that touches no staging resource.**
Anything that runs a test suite, a probe, or a staging read serialises, worktree or not. A spec
that dispatches into a worktree says which of the two it is; a session that finds itself about to
touch staging from a worktree stops and reports rather than assuming it is alone.

**PL-3. A session in a worktree states its worktree in its handback**, in the state-and-branch
section, by absolute path. Two concurrent sessions' handbacks are otherwise unattributable, and
attribution is what makes a variance traceable.