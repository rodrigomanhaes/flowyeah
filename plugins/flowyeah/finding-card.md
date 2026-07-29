# Finding Card

The canonical way a finding is shown to the user. `flowyeah:review` uses it at steps 5 and 5b; `flowyeah:respond` uses it at step 4. Both render the same card so a finding looks identical wherever the user meets it.

The card is not decoration; it is the contract. Never substitute a prose paragraph, a compressed bullet list, or a table for it.

## The card

```
═══════════════════════════════════════════════════════════
Finding <n>
═══════════════════════════════════════════════════════════
Label:      <label> (<decoration>)
Confidence: <0-100>/100
File:       <path>:<line>
Scope:      <scope>
Source:     <who found it>

┌─────────────────────────────────────────────────────────
│ **<label> (<decoration>):** <subject>
│
│ <body — see "The body" below>
└─────────────────────────────────────────────────────────
```

Render every finding as its own card, in order, one after another — even when there is only one finding.

**Emit the cards inside a fenced code block.** Open a bare ```` ``` ```` fence at column 0 before the first card and close it after the last one, so the whole run renders literally. Every body line starts with `│`, so a fence written inside a box never begins its line and cannot close the outer one — code snippets nest safely.

Without the outer fence the box body is parsed as Markdown: an inner ```` ```ruby ```` block becomes an inline code span, its fences disappear, and every newline collapses to a space. The snippet lands on a single line, strung together by the `│` prefixes.

## Fields

| Field | Value |
|-------|-------|
| Title line | `Finding <n>` when the whole set is on screen at once (review step 5). `Finding <i> of <N>` when findings are presented one at a time (respond step 4). |
| `Label:` | Conventional Comments label — `praise`, `issue`, `suggestion`, `todo`, `question`, `thought`, `nitpick`, `chore`, `note` — with its decoration: `(blocking)`, `(non-blocking)`, `(if-minor)`. |
| `Confidence:` | `<0-100>/100`. Render `—` when the item carries no confidence: praise, and normal-mode reviewer comments, which have none. Invent nothing. |
| `File:` | `<path>:<line>`, or `(general)` for a finding with no precise anchor. |
| `Scope:` | Where the finding sits relative to the change under review: `in-diff`, or `pre-existing — outside the diff`, either one optionally followed by `— does not block this <PR\|MR>`. Everything about the finding's standing lives in this field and is never restated in the body. |
| `Source:` | Where it came from — the agent or analysis that produced it, `previous review`, `own review`, or the comment author's name. |

The box body is the Conventional Comments block verbatim — what would actually be posted as the inline comment, so the user can see at a glance what they are approving.

## The body

State the finding. Do not defend it.

**Budget: 80 words of prose.** Code snippets and command output are evidence, not prose, and do not count against it. A body that runs past the budget is almost always defending itself rather than explaining more.

The fields already carry the defense. `Confidence: 70` says you might be wrong. `Label` and `Scope` say what the finding costs the reader. Prose that repeats them spends the budget twice and tells the reader nothing new.

Three moves do most of the damage. None of them belong in the body:

| Move | What it looks like | Write this instead |
|------|--------------------|--------------------|
| Explanatory parenthetical, 4+ words | `... (observability is intact — Sidekiq still records it server-side)` | Cut it. If the point matters, it is a sentence; if it does not, it is not in the card. |
| Concessive against an objection nobody raised | `Literally true about the link, but the table shows Sigla, Nome, Vigência …` | State what is true. The concession answers a reader who is not there. |
| `not X` / `I'm not saying` | `This is a UX gap, not a hang` · `I'm not saying this blocks` | The label and `Scope:` already said it. |

Across 2531 rendered cards, a body carrying none of these moves runs 76 words at the median; one carrying five or more runs 180. The length is the argument, not the analysis.

## Variants

**Previously raised.** Append `  ⟳ PREVIOUSLY RAISED` to the title line, set `Source: previous review`, keep the original label and confidence, and open the discussion with a `⟳ Previously flagged, still unresolved.` line. `Scope:` is the exception to "keep the original": it is re-derived against the diff under review now, since a finding that was outside the previous diff may be inside this one.

```
═══════════════════════════════════════════════════════════
Finding <n>  ⟳ PREVIOUSLY RAISED
═══════════════════════════════════════════════════════════
Label:      <original label> (<original decoration>)
Confidence: <original score>/100
File:       <path>:<line>
Scope:      <re-derived against the current diff>
Source:     previous review

┌─────────────────────────────────────────────────────────
│ **<label> (<decoration>):** <subject>
│
│ ⟳ Previously flagged, still unresolved.
│ <original discussion body>
└─────────────────────────────────────────────────────────
```

**Praise.** The same card with `Confidence: —` and no decoration after the label.

## Anti-pattern (do not do this)

```
✗ WRONG — prose summary instead of cards

Finding 1 — issue (non-blocking) · confidence 80
app/models/.../access_token.rb:11

The new .timeout(...) makes the token request fail fast, but the resulting
error is not normalized anywhere in the chain...

---
Finding 2 — suggestion (non-blocking) · confidence 75
...
```

This shape is forbidden because it:

- Drops the `═══` header and `┌─│└` comment box, collapsing the scannable `Label`/`Confidence`/`File`/`Source` fields into a run-on header line.
- Buries the conventional-comment body in a prose paragraph, so the user can't see at a glance what would actually be posted as the inline comment.
- Produces the "wall of text" the card format exists to prevent.
