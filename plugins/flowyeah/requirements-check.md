# Requirements check

How `flowyeah:build` (step 6a) and `flowyeah:review` (step 2b) compare a diff with what was asked for. Each skill names its reference: the criteria in `mission.md`, the source issue, or the `## Criteria` section of the PR/MR description.

Judge from the diff. A checked box in a PR/MR description is the author's claim, and passing tests prove only what they assert.

**Completeness:** Does the implementation cover everything the reference asks for? For each requirement or acceptance criterion, find the code that implements it. A requirement with no corresponding code is unmet.

**Scope:** Is there code unrelated to what the reference asks for? Compare changed files and logic against its scope. Refactoring the feature needs is pertinent.

**Coherence:** Does the implementation approach make sense for the described problem? Flag an implementation that seems to solve a different problem than the one described.
