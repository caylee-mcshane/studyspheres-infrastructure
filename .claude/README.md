# `.claude/` — agent configuration for this repo

`CLAUDE.md` and everything in `.claude/rules/` load automatically into every session
rooted here, with no tool call.

## settings.json is INERT until this workspace is trusted

Measured, 2026-08-28. In an untrusted workspace Claude Code prints

    Ignoring N permissions.allow entry from .claude/settings.json: this workspace has not been trusted.

and discards the **entire** permissions block — deny rules included. A deny rule that does
not fire reads as protection, so trust is a precondition for treating anything here as a guard.

Trust is granted by opening Claude Code interactively in this directory once and accepting
the dialog, or by setting `projects["<abs path>"].hasTrustDialogAccepted: true` in
`~/.claude.json`. Verify before relying on these rules.

## What enforces what

The permission **mode** is what refuses (`--permission-mode dontAsk` denies anything not
pre-approved). An `--allowedTools` list does **not** withhold a tool: Write and Edit stay in
the schema and callable. The one thing a tool list genuinely constrains is Bash command
patterns — which is why the deny rules below are written as `Bash(...)`/`PowerShell(...)`
patterns, and why both spellings appear. Rules match the literal command string, so
`git push`, `git -C <path> push` and a PowerShell invocation are three different strings.
