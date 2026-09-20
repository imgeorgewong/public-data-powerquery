# Index-number method

Notes for building a price index out of published public data: joining broken series, moving a
base period, extending a series the publisher has stopped, and storing the result so revisions
do not destroy what you reported last month.

The arithmetic is small. The difficulty is in the ordering of the steps and in recording what
you did, because every operation below is invisible in the output — a spliced series and a real
one look identical in a chart.

---

## 1. An index is not a price level

A **price level** has a unit: currency per tonne, currency per litre. It can be added, averaged
and converted.

An **index** is a ratio to a reference period, scaled so that the reference period equals 100.
It is dimensionless. It carries *change*, not *amount*. Two indices cannot be added, and their
difference in points means nothing unless they share a base.

Mixing the two in one store is the most expensive mistake available here: both are "numbers
around 100–200" and nothing in the value says which it is. Either the store holds indices only
and every price level is converted on the way in, or every row carries a `Measure` column that
must be filtered on before anything is aggregated.

**Converting a price level to an index** needs a chosen base period, recorded rather than
implied. Pick a period that is complete, not revised, not unusually volatile, and present in
every series you intend to compare.

**The specification of the underlying price is part of the index.** For a traded commodity, a
cash price, a three-month forward, a fifteen-month forward and a monthly average of any of them
are similar in magnitude and quite different in behaviour. Picking the wrong one is invisible on
the surface and puts an unmarked break in the series wherever the choice changed. Store the
contract or specification in the metadata, and treat a change of specification as a new series.

---

## 2. Currency denomination

An index built from prices quoted in a currency carries that currency's movement inside it.
A metal index built from dollar prices and a materials index built from euro prices are not
comparable as "material inflation": part of the difference between them is the exchange rate.

Two consequences:

- **Record the currency of the underlying price in metadata**, even though the index itself has
  no unit. "Dimensionless" is not the same as "currency-neutral".
- **If a common currency is wanted, convert the price level, then index it.** Converting an
  index after the fact does not give the index you would have got: the base period would have
  been converted at its own rate too, and that rescaling is not a currency translation. Do the
  FX on the levels, at the frequency the FX is published, before the base is applied.
- **Do not mix FX sources within one series.** Different publishers use different fixing times
  and holiday calendars, so a series stitched from two of them has steps that are not price
  movements.

---

## 3. Chain-linking

A published series breaks when its definition changes: a classification is revised, a sample
replaced, a base year moved, a product dropped from the basket. The publisher usually gives an
**overlap** — a window where both old and new exist for the same periods. Chain-linking uses
that overlap to put both on one scale.

### The link factor

Over an overlap window *W* covering the same periods in both segments:

```
f = mean(Old(t) for t in W) / mean(New(t) for t in W)
```

Then the joined series is the new segment scaled by `f`, appended to the old segment as
published:

```
Linked(t) = Old(t)                for t before the link point
Linked(t) = f × New(t)            for t at and after the link point
```

Equivalently, carry the old segment onto the new scale by dividing instead. The direction does
not matter; what matters is that **one and only one** scalar is applied and that you record
which segment was left untouched.

Use the whole overlap rather than a single adjacent period: a one-period ratio inherits that
period's noise, and if either value is preliminary you have built the noise into every
subsequent observation. Where only one overlapping period exists, say so in the metadata.

### Per-sector, never global

When the break is a **classification change**, category boundaries moved — not just their names.
One sector gained a sub-activity, another lost one, a third is a merger of two old ones. A
single global link factor computed on the total is wrong for every sector individually,
sometimes by a lot, and wrong in a way that preserves the total — so the check most people run
will pass.

Compute the link ratio **per sector**, on that sector's own overlap, and match sectors by
definition from the publisher's correspondence table, never by code — codes are reused across
classification versions with different boundaries behind them, so a code-to-code join is a
silent mis-assignment.

### Chain-link first, rebase second

This ordering is not a style preference.

1. **The link factor has to be computed on the numbers as published**, each segment in its own
   base — the only form in which the two segments' relationship is a fact about the published
   data rather than about your arithmetic. Rebase first and you have applied a *different*
   scalar to each segment, since they have different bases; the overlap ratio then reconstructs
   the published relationship times the ratio of your two rebasing factors, and reproducing the
   work means remembering both.

2. **Chained-then-rebased, every published figure survives.** The chained series is related to
   each published segment by exactly one multiplicative constant. Divide by it and the
   publisher's numbers come back, so any figure in your output reconciles to a specific
   published value. That property disappears as soon as the scalars are applied in the other
   order, or more than once.

So: link on the published scale, then apply a single rebasing scalar to the finished series.
Store both factors as data, not in a comment.

---

## 4. Rebasing

Rebasing moves the reference period without changing the information:

```
Index_new(t) = Index_old(t) × 100 / Index_old(base_new)
```

It is a single multiplicative constant per series: growth rates, ratios between periods and
every year-on-year change are untouched, only levels move. Two series rebased to different
periods cannot be compared on levels at all — rebase both to the same period, or compare growth
rates instead.

- **Check the identity.** After rebasing, the new base period must be exactly `100.0`. This is a
  test that can genuinely fail, and it catches the wrong-row and wrong-series errors that are
  otherwise invisible.
- **Do not add precision.** If the publisher issues one decimal place, a rebased series is still
  a one-decimal series however many digits the division produces. Extra precision invents a
  false level of agreement between series.
- **Keep the publisher's own base**, in metadata rather than overwritten. Someone will need to
  reconcile a number to a press release, and the published base is the only route back.

Also note that choosing a base is choosing the period at which every series you rebase agrees
with every other by construction. If that period is anomalous, the whole comparison inherits the
anomaly with no visible symptom.

---

## 5. Extending a discontinued series with a proxy

Publishers stop series: a detailed product index is folded into a broader one, a survey is
retired, a category becomes too small to publish. What remains is a history that ends and a
requirement that does not. A proxy splice extends the dead series using the *growth* of a related live one, anchored at the
last real value:

```
Index(t) = AnchorIndex × Proxy(t) / Proxy(anchor)      for t after the anchor
Index(t) = published value                             for t up to the anchor
```

`anchor` is the latest period at which both the discontinued series and the proxy have a real
published value. `AnchorIndex` is the discontinued series' own value there.

### What it gives you

Continuity of level — by construction there is no jump at the splice — and, after the anchor, the
proxy's period-to-period change. That is usable for "roughly how much has this moved since",
which is usually the actual question.

### What it costs

**Definitional accuracy, in exact proportion to how far the proxy sits from the original.** A
proxy is normally at a coarser level of classification than the series it replaces — an industry
aggregate standing in for a specific product — so after the anchor the series answers a different
question than it does before. Its weighting, coverage and revision behaviour are the proxy's.
The number is a plausible estimate of the discontinued concept, never a measurement of it.

Two further costs that are easy to miss:

- **The frozen part can be stale in a way the live part is not.** If the publisher restated
  history for its live series but not for the discontinued one, the pre-anchor segment keeps
  pre-revision values forever. Those cannot be repaired, only labelled.
- **The proxy may start after the anchor**, leaving no common period and so no splice. Choose a
  different proxy, or let the series end where the publisher ended it.

### Choosing the anchor

The natural anchor is the last published period of the dead series, but it is not always usable:
a final value may be suppressed for confidentiality, or flagged preliminary and never finalised.
Move the anchor back to the nearest period where both series have a solid published value, and
record which period you used — the anchor determines every extended value.

### Flag every derived row

Each observation needs a `Method` column distinguishing published values from derived ones —
`ACTUAL` versus `PROXY`, or the same distinction under whatever names you prefer. Three reasons,
in increasing order of importance:

1. Nobody can tell by looking: the spliced segment is smooth and plausible, which is the point
   of the method and also its hazard.
2. The flag is what lets you recompute. When the proxy is revised, or a better proxy appears,
   you need to know which rows to rebuild — and which must never be touched because they are
   published values.
3. **The flag has to reach the output, not just sit in the warehouse.** A chart or a table that
   shows a spliced series without saying so is a claim you did not mean to make. Carry the
   caveat onto the artefact: which periods are derived, from which proxy, and at what level of
   classification.

### Validate the splice

The first proxy-derived period should sit close to where the dead series was heading — a small
tolerance band around the anchor, agreed in advance. A large first step means a bad anchor, a
mismatched proxy, or a unit or base mismatch. It does not mean the market moved.

### When not to splice at all

Do not splice across a genuine definitional gulf, however convenient. An administrative register
and a sample survey measuring nominally the same thing are different instruments with different
populations and different revision behaviour; two futures contracts with different pricing bases
are different prices. Similar magnitudes are not evidence of the same concept. A spliced series
there is a fabricated one and no `Method` flag redeems it — keep two series, show two lines.

---

## 6. Vintage stacking across a classification change

During a classification migration the publisher issues the same periods twice — once on the old
version, once on the new — for an overlap of several years. You need both: the old because your
own published history was built on it, the new because it is what continues.

- **Store both, never overwrite.** Every observation carries a `Vintage` column naming the
  classification version it was published under.
- **Put the vintage in the series identifier**, not only in an attribute column. A key that
  ignores the classification version collides in the overlap, and whatever aggregates that key
  doubles.
- **Filter on vintage before aggregating, always.** This is the single failure mode of the
  pattern and it is silent in exactly the overlap window. See `docs/gotchas.md`.
- **Compute link ratios per sector from the stacked table**, over the overlap, as in section 3.
  Having both vintages side by side is what makes those ratios computable — the reason to stack
  rather than choose.
- **Expect the old vintage to be withdrawn from the API.** Once migration completes it can
  return nothing, and your stacked copy becomes the only copy — so it belongs in the frozen half
  of the store (`docs/patterns.md`), not in anything a refresh rewrites.

---

## 7. Append-only observation storage

The store is a fact table of observations. One row is:

```
Period · SeriesId · Value · Method · Vintage · RetrievedAt
```

Rows are **inserted, never updated**: a refresh that finds a different value for a period you
already hold adds a second row with a later `RetrievedAt`. The current view of a series is the
row with the greatest `RetrievedAt` per (SeriesId, Period). This costs a little space and
answers the questions overwriting cannot:

- *What did we report last quarter, and has the source changed it since?* — an overwriting table
  cannot answer this, and the question arrives as somebody comparing two of your own outputs.
- *Which periods moved in this month's revision round, and by how much?* — the diff between the
  two most recent retrievals per period, which is also the only way to detect an unannounced
  restatement (see `docs/gotchas.md`).
- *Reproduce the report as it stood on a date* — filter to `RetrievedAt <= that date` and take
  the latest per key.

Practical points:

- **Timestamp per row, not per refresh.** A refresh can partially fail, and a run-level
  timestamp then claims freshness the data does not have.
- **`RetrievedAt` is a retrieval time, not a publication time.** Keep the publisher's release
  date as a separate column; they answer different questions.
- **The key is (SeriesId, Period, Vintage, RetrievedAt).** Anything less collides.
- **Do not prune inside the revision window.** Beyond it, collapsing a period to its final row
  is safe and is the right place for any size limit you need.

---

## 8. The minimum metadata

Every method decision above is invisible in the values, so it has to live in columns. A
workable minimum, one row per series:

| Column | Why it exists |
|---|---|
| `SeriesId` | Stable key; encodes source, item, and qualifier including classification vintage |
| `Measure` | `INDEX` or `LEVEL` — the filter that stops the two being summed together |
| `Unit` | Meaningless for an index, essential for a level |
| `Currency` | The currency of the underlying price, even for an index |
| `BasePeriod` | Publisher's base; plus your own if you rebased |
| `Aggregation` | How daily or weekly observations become a month: average, last, or not at all |
| `Method` | `ACTUAL` / `PROXY` / `LINKED`, per observation rather than per series |
| `ProxyOf`, `AnchorPeriod` | Only populated for spliced series; what was spliced to what, where |
| `LinkFactor`, `RebaseFactor` | The scalars applied, as data — so the work can be undone |

If one of these is missing, the corresponding mistake is available and nothing will warn you.
