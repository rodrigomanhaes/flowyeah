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
Source:     <who found it>

┌─────────────────────────────────────────────────────────
│ **<label> (<decoration>):** <subject>
│
│ <discussion — context, justification, suggested code>
└─────────────────────────────────────────────────────────
```

Render every finding as its own card, in order, one after another — even when there is only one finding.

## Fields

| Field | Value |
|-------|-------|
| Title line | `Finding <n>` when the whole set is on screen at once (review step 5). `Finding <i> of <N>` when findings are presented one at a time (respond step 4). |
| `Label:` | Conventional Comments label — `praise`, `issue`, `suggestion`, `todo`, `question`, `thought`, `nitpick`, `chore`, `note` — with its decoration: `(blocking)`, `(non-blocking)`, `(if-minor)`. |
| `Confidence:` | `<0-100>/100`. Render `—` when the item carries no confidence: praise, and normal-mode reviewer comments, which have none. Invent nothing. |
| `File:` | `<path>:<line>`, or `(general)` for a finding with no precise anchor. |
| `Source:` | Where it came from — the agent or analysis that produced it, `previous review`, `own review`, or the comment author's name. |

The box body is the Conventional Comments block verbatim — what would actually be posted as the inline comment, so the user can see at a glance what they are approving.

## Variants

**Previously raised.** Append `  ⟳ PREVIOUSLY RAISED` to the title line, set `Source: previous review`, keep the original label and confidence, and open the discussion with a `⟳ Previously flagged, still unresolved.` line:

```
═══════════════════════════════════════════════════════════
Finding <n>  ⟳ PREVIOUSLY RAISED
═══════════════════════════════════════════════════════════
Label:      <original label> (<original decoration>)
Confidence: <original score>/100
File:       <path>:<line>
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
