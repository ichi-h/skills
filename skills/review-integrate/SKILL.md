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
   and drop the ones whose evidence is weak (false positives). Do not extend this into a second review.

3. **Decide accept/reject.**
   - MUST / NITS: to be filed (handed to the next skill)
   - IMO: accept only those judged to have a large effect on the project
   - **Keep the rejected ones with their reasons.** Make it possible to be asked later
     "why aren't we fixing this?"

4. **Harvest the `Unconfirmed items`.** Every line a reviewer put there is a gap in
   `evidence.md`, not noise. A reviewer that wrote "the interaction with the scheduler is not
   visible in the pack" has told you exactly which fact, if it had been present, would have saved
   it a tool call. Classify each line:

   | Kind                                          | What to do                                                                                            |
   | --------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
   | Covered by the fact pack, reviewer missed it  | Nothing; the pack was right, the prompt can name the section                                          |
   | Out of scope for this ticket                  | Move it to the "Rejected" list with the reason, so it is not re-derived next time                     |
   | A real gap in the fact pack                   | Add it to `evidence.md` **before** the next wave; it will be rediscovered by every reviewer otherwise |
   | A real finding the reviewer could not confirm | Carry it into findings.md as "needs confirmation", with what would confirm it                         |

   **This is the feedback loop that keeps a fact pack from staying expensive.** Anything not
   written down between waves is rediscovered and re-requested by every reviewer.

5. **Write findings.md.** Write it to `/tmp/review-<label>/findings.md` in the following form.

**Do not restate the reports.** The reports stay on disk next to `findings.md`; copying their
paragraphs into findings.md pays for the same text twice and makes the two copies drift. Record the
decision and the pointer: the claim in one line, the severity, the file:line, and which report it came
from. The narrative (why it is a problem, suggested fix) stays in the report.

```markdown
# {{TICKET}} review integration

## Accepted (to be filed)

- [ ] MUST: `app/foo.ts:42` … (source: code / security, from `report-code.md`)
  - Destination: {{new / append to existing ticket uid}}

## Rejected (with reasons)

- IMO: … — rejected because the quality difference is small (from `report-design.md`)
- MUST: … — checked the file:line in the evidence, but there is no problem at that location (false positive)
- NITS: … — already being handled in existing ticket `{{uid}}`

## Unconfirmed items

- {{the line as the reviewer wrote it}} — {{covered in the pack / out of scope / added to evidence.md / needs confirmation}}
```

`file-ticket` opens the source report when it needs the detail. Write the pointer as
`report-<perspective>.md` and, when a report has many entries, the finding's heading so the next
skill can jump straight to it.

## Done conditions

- `/tmp/review-<label>/findings.md` contains accept/reject and a reason for every finding
- No report paragraph is copied into findings.md; each entry carries a pointer to its report
- Every `Unconfirmed items` line is classified, with fact-pack gaps written back into `evidence.md`
- **There are no changes in the diff**
