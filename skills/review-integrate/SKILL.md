---
name: review-integrate
description: A skill that integrates findings tables from multiple perspectives, decides accept/reject for MUST / NITS / IMO, and consolidates them into findings.md.
---

# Review Integrate Skill

Integrate the findings tables (report-<perspective>.md) from each perspective, decide accept/reject, and
consolidate them into findings.md.

**The deliverable of this skill is findings.md. Do not file tickets. Do not change a single line of code.**

## Steps

1. **Merge duplicates.** If the same finding appears in multiple reports, make it one entry.
   Duplication reflects overlapping perspective design, not quality.

2. **Verify the evidence for MUST.** Read the relevant line of the relevant file yourself, exactly once,
   and drop the ones whose evidence is weak (false positives).

3. **Decide accept/reject.**
   - MUST / NITS: to be filed (handed to the next skill)
   - IMO: accept only those judged to have a large effect on the project
   - **Keep the rejected ones with their reasons.** Make it possible to be asked later
     "why aren't we fixing this?"

4. **Write findings.md.** Write it to `/tmp/review-<label>/findings.md` in the following form.

```markdown
# {{TICKET}} review integration

## Accepted (to be filed)
- [ ] MUST: `app/foo.ts:42` … (source: code / security)
  - Destination: {{new / append to existing ticket uid}}

## Rejected (with reasons)
- IMO: … — rejected because the quality difference is small
- MUST: … — checked the file:line in the evidence, but there is no problem at that location (false positive)
- NITS: … — already being handled in existing ticket `{{uid}}`

## Unconfirmed items
- …
```

## Done conditions

- `/tmp/review-<label>/findings.md` contains accept/reject and a reason for every finding
- **There are no changes in the diff**
