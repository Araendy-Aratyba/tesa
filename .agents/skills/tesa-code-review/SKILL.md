---
name: tesa-code-review
description: Review Tesa pull requests, branches, commits, or local diffs as a senior Ruby on Rails developer, applying the repository's AGENTS.md architecture, data semantics, persistence, and testing rules. Use for code-review requests in Tesa; do not use it to implement fixes unless the user separately asks for changes.
---

# Tesa Code Review

Review changes as a senior Ruby on Rails developer experienced with modular monoliths,
PostgreSQL, background jobs, external-data ingestion, and long-lived production systems.
Be pragmatic and evidence-driven: protect correctness and architectural boundaries without
turning the repository's patterns into ceremony or proposing broad rewrites for local issues.

## Authority and scope

Before reviewing, read the repository-root `AGENTS.md` completely. Also find and read every
applicable descendant `AGENTS.md` for the changed files. Treat those files as the normative
source for architecture, implementation, data semantics, persistence, tests, and definition
of done. If the requested change conflicts with them, report the conflict instead of silently
accepting it.

Use other repository files only as evidence of the intended behavior or established local
conventions. Do not import rules from unrelated projects.

Review the requested PR, branch, commit, staged changes, or working-tree diff. If the user
does not identify the comparison, inspect the current branch and working tree and choose the
narrowest comparison that represents the current work. Preserve unrelated checkout changes.

Code review is read-only by default. Do not edit files, commit, push, submit a review, or add
GitHub comments unless the user explicitly asks for that separate action.

## Review method

1. Establish the change's stated objective and enumerate the changed files. Read surrounding
   code, migrations, schema, tests, call sites, and documentation when needed to evaluate a
   changed behavior; do not expand into an unrelated audit of untouched code.
2. Identify the owning Tesa module for each behavior and classify its flow as command/write
   or query/read before judging its component placement.
3. Trace observable behavior through the real Rails path affected by the change. Evaluate
   correctness, failure behavior, data integrity, security, authorization, concurrency,
   retries, idempotency, and operational impact in proportion to the diff.
4. Apply the architecture, dependency direction, component responsibilities, Câmara data
   semantics, database rules, and mandatory testing policy from the applicable `AGENTS.md`.
5. Inspect whether tests exercise real internal components and persisted FactoryBot domain
   records. Treat mocks or stubs of internal application collaborators as violations; accept
   substitution only at the exact external boundary allowed by `AGENTS.md`.
6. When useful, run the smallest safe checks that can confirm or reject a suspected finding.
   Never make real Câmara calls in the standard suite. Use repository-pinned commands, start
   with focused checks, and run `bin/ci` only when its cost is proportionate and viable.
   Report every validation limitation explicitly.
7. Distinguish a demonstrated defect from a conditional risk or an unverified hypothesis.
   Do not manufacture findings to fill a checklist. If no actionable problem remains, say so
   and state residual risks or validation gaps.

Pay particular attention to changes that:

- cross module boundaries without a `PublicApi` or an authorized Reporting projection;
- place commands outside Services, complex reads outside Query Objects, presentation outside
  Presenters, or business rules inside controllers, jobs, callbacks, or views;
- perform HTTP inside a database transaction, duplicate `congrega_plenum` responsibilities,
  or obscure external contract failures;
- weaken external identities, unique indexes, idempotent writes, checkpoint ordering,
  resumability, rollback, UTC handling, monetary precision, or `raw_payload` provenance;
- conflate legislative budget, CEAP, and financial execution, or infer facts that the Câmara
  source does not establish;
- mishandle alphanumeric voting IDs, tri-state approval, symbolic votes, empty vote lists,
  historical representative context, voting-proposition relations, or year-bounded backfills;
- introduce N+1 queries, unbounded work, unsafe SQL, mass-assignment, authorization gaps,
  unsanitized external content, or retry loops for permanent failures;
- add abstractions without sufficient responsibility or bypass Rails/Zeitwerk conventions;
- omit tests for success, failure, reexecution, unknown states, transaction boundaries, or
  other cases proportional to the change's risk.

## Findings

Classify every actionable finding with exactly one severity:

- 🔴 **Blocking** — correctness, security, authorization, or data-risk.
- 🟡 **Suggestion** — design, naming, responsibility, maintainability, or a material
  risk that should be addressed but does not presently demonstrate blocking impact.
- 🟢 **Nit** — minor and optional improvement.

Choose severity from demonstrated impact; do not inflate uncertain concerns. For each finding:

- give a concise title prefixed by its severity;
- cite the tightest changed `path:line` that causes the problem;
- explain what is wrong, why it matters specifically in Tesa, and the concrete change that
  would resolve it;
- cite the relevant `AGENTS.md` rule when the finding is architectural or normative;
- state the conditions required for a conditional problem instead of presenting it as certain;
- keep the proposed fix scoped to the reviewed objective.

Present findings first, ordered by severity and then by impact. After the findings, include
brief sections for open questions or assumptions and for validation performed. End with a
neutral summary containing the count by severity and the main themes. Do not add praise
padding or restate the entire diff.
