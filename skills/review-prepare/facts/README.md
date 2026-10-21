# Standing fact profiles

A standing fact profile is a place to write down behaviour that **every review in one repository
would otherwise rediscover with a tool call** — framework semantics, library defaults, how the test
runner isolates state. It is pasted into `evidence.md` §3.2 by `collect-evidence.sh`.

Profiles live here as `<repository-name>.md` (the directory name of the repository root) and are
picked up automatically; `--facts <file>` overrides the lookup.

**The skill ships the mechanism; each repository ships its own facts.** Nothing project-specific
belongs in this directory as distributed — a profile naming a particular product, route file or
component makes the skill wrong for every other repository.

## What to write

Only facts that are (a) stable across tickets, (b) non-obvious, and (c) expensive to confirm —
each one costs a reviewer a tool call plus a context re-read:

- Framework or library behaviour where a reasonable guess is wrong
  (does a non-2xx response still populate the data hook? is a thrown error re-thrown or converted?
  which lifecycle does a retry hit?)
- The semantics of a shared utility the codebase wraps around that library
- How the test harness loads the code under test, when that changes what a test can prove
- Measured defaults and magic values that are not visible at the call site

What does **not** belong: this ticket's diff, file inventories, requirements for one feature, or
anything a `git grep` answers in one call.

## Shape

State the fact, then the evidence that makes it a fact, then the consequence for a reviewer.

```markdown
### <the behaviour, as a claim>

<What happens, and the mechanism, in one or two sentences. Cite the implementation with
`node_modules/pkg/file:line` or `path:line` — a fact without a location is a rumour.>

- Consequence: <what a reviewer should conclude, e.g. "an unguarded access throws at runtime on a
  non-2xx response">
- Source: `path:line`, `path:line`
```

Keep each entry to a few lines. A profile that grows past about one screen stops being read; if it
does, most of it belongs in the repository's own documentation instead.

## Lifecycle

- Add an entry when `review-integrate` classifies an `Unconfirmed items` line as "a gap that is true
  of the whole repository". Fixing it in one ticket's `evidence.md` only means the next ticket pays
  for it again.
- Delete or correct an entry the moment it stops being true — a stale profile is worse than none,
  because reviewers are told not to verify it.
