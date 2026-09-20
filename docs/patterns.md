# Design patterns

Seven patterns that keep a refreshable public-data workbook from turning into a set of
hand-maintained sheets, plus a checklist for deciding whether a refresh actually worked.

They compose: tidy long storage makes the catalogue pattern possible, the catalogue pattern
makes staging queries cheap, cheap staging makes hub-and-spoke practical, and the QA query
only works because everything ends up in one table with one shape.

---

## 1. Tidy long format over wide sheets

**One observation per row.** The minimum shape is:

```
Period | SeriesId | Value
```

with everything else — unit, method, vintage, retrieval timestamp — as further columns on the
same row, and everything descriptive about the series in a separate dimension table joined on
`SeriesId`.

The rule that follows: **a new series is a new row. Never a new column, never a new sheet.**

A wide layout puts each series in its own column, which seems natural until it is refreshed.
Then: adding a series shifts every formula anchored to a column letter; a series that starts
later than the others leaves ragged blanks that break averages; a series that is discontinued
leaves a column that must be kept forever or deleted with consequences; and a chart range has
to be extended by hand each time. Every one of those is a manual step that a person can forget,
and forgetting is silent.

Long format costs one thing: it is not readable at a glance. That is what a PivotTable is for.
Pivot for the eye, store long for the machine — and never let the pivoted copy become the place
edits are made.

A useful test for whether a layout is really tidy: can you add a whole new source, with a
frequency you have never handled before, without altering the schema? If not, something that
should be data is currently structure.

---

## 2. Catalogue table → function → single fact table

The pattern has three parts:

**A catalogue**, one record per series, holding everything that varies between series: the
identifier, the endpoint fragment or parameters, a display name, the unit, the aggregation rule.
No logic.

**A function**, taking one catalogue record's worth of parameters and returning a tidy table for
that one series. All the logic — request, retry, status handling, type conversion, shaping —
lives here, once.

**A fact query** that maps the function over the catalogue and combines:

```m
Fetched = List.Transform(Catalogue, each fnSource([Uri], [Name])),
All     = Table.Combine(Fetched)
```

Adding a series is then one record in the catalogue. Nothing else changes: no new query, no new
sheet, no code edit, no chart range.

Three things make this work in Power Query specifically:

- **The middle layer must be a function, not a query that returns nested tables.** A query whose
  result contains table-valued columns evaluates every source just to draw its preview. A
  function has no previewable result, so nothing runs until it is called. This is the difference
  between a catalogue that costs nothing and one that re-downloads everything whenever the
  editor opens.
- **Keep the catalogue in its own query.** If the catalogue is an Excel table read with
  `Excel.CurrentWorkbook` and the function makes a web call, putting both in one evaluation
  chain triggers `Formula.Firewall`. Two queries, one reference between them.
- **The function should raise, not swallow.** It is the only place that knows the difference
  between "this series is legitimately empty for this window" and "the identifier is wrong".
  A `try ... otherwise null` at this layer converts every distinct failure into the same empty
  table, and the fact query combines it without complaint.

Keeping the catalogue as an Excel table rather than inline in M means a colleague can add a
series without opening the Advanced Editor. That is usually worth the extra query.

---

## 3. Connection-only staging, one loaded table

**Exactly one query loads to a sheet or to the Data Model: the final fact table.** Everything
else — functions, catalogues, per-source staging — is *Connection only* (Home → Close & Load
To… → Only Create Connection).

Why, specifically:

- Each loaded query is a sheet that somebody can type into. A staging query loaded to a sheet
  will eventually be edited by hand and overwritten on the next refresh, and the two facts will
  not be connected in anyone's mind.
- Loading intermediates does not save work. Power Query has no cross-query cache, so a loaded
  staging table is not reused by the queries that reference it — they re-evaluate it. You pay
  for the sheet and get nothing back.
- One loaded table is one thing to validate, one row count to predict, one place for downstream
  formulas to point.

A naming convention makes the layering legible in the Queries pane, which sorts alphabetically:

| Prefix | Meaning | Load |
|---|---|---|
| `fn…` | Function — one source, one call | Connection only |
| `cat_…` | Catalogue of series to fetch | Connection only |
| `stg_…` | Staging, one per source, shaped but not combined | Connection only |
| `fct_…` | The fact table | **Load to Table** |
| `dim_…` | Series metadata | Load to Table (small) |
| `qa_…` | Checks over the loaded output | Load to Table (small) |

---

## 4. Frozen history plus a live window

Some history cannot be re-fetched: an API that serves a rolling window, a series the publisher
has withdrawn, a legacy history that was keyed in by hand or recovered from a chart. If a
refresh rewrites the whole table, one bad refresh destroys it permanently, and no error is
raised when it happens.

Split the series in two:

- **Frozen** — everything before a cut-off date, held as values, never touched by a refresh, and
  backed up somewhere with version history.
- **Live** — everything from `LiveFrom` forward, re-fetched every time.

The loaded table is the union, with one explicit rule for periods that appear in both. Usually
live wins, because it carries revisions; where the frozen copy is known to be better — a source
that has since lost history, for instance — say so in a comment, because the opposite choice
will look like a bug to the next reader.

Two details decide whether this works:

- **`LiveFrom` must be longer than the source's revision window.** If a publisher revises the
  last two months and your live window is one month, revisions to the month before the window
  never reach you. Months, not weeks, and set it from the publisher's stated behaviour rather
  than from how far back you feel like fetching.
- **Frozen rows carry their own provenance flag.** Trust in a frozen row is not the same as
  trust in a live one. A history keyed in by hand, or digitised from a picture of a chart, may
  be fine for the shape of a decade and useless for a month-on-month calculation: timestamps
  land on the wrong day, values carry invented precision, and the same month can appear twice
  with different values. Mark it, and say in the metadata what it may and may not be used for.
  An unusable history is much less dangerous than an unmarked one.

---

## 5. A zero-cost QA query

Build one query that reads the **already-loaded** output sheets with `Excel.CurrentWorkbook` and
computes checks. It touches no network, so it costs nothing to run and can be part of every
refresh rather than an occasional exercise.

One row per series, with roughly these columns:

| Column | What it catches |
|---|---|
| `Rows` | Combined with the next column, an identity that can fail |
| `ExpectedRows` | `DATEDIF(MIN, MAX, "m") + 1` for a monthly series |
| `Gaps` | Missing periods in the middle, which a row count alone hides |
| `MinPeriod` | History silently shortening at the start — a rolling window eating the past |
| `MaxPeriod` | A series that stopped updating while still answering HTTP 200 |
| `DaysSinceLast` | Compared with that series' expected publication lag |
| `LastValue` | Magnitude and sign, for an eyeball plausibility check |
| `Duplicates` | Key collisions, especially in a classification overlap window |
| `MethodMix` | Count by `ACTUAL` / `PROXY` / `LINKED` — a jump means the splice moved |
| `Status` | `OK` or a reason, so the eye goes to one column |

Keep it out of the data chain. It reads outputs, nothing reads it, and it lives in its own
query — which also avoids the `Excel.CurrentWorkbook`-plus-web-source firewall problem, because
it makes no web call at all.

The discipline that makes it valuable: **write down the expected numbers before the refresh**,
not after. A check whose expected value is filled in from the result it just produced is not a
check.

---

## 6. Hub-and-spoke workbook layout

**One workbook per source. One hub that combines them. Source files are never edited.**

Each spoke workbook holds the functions, the catalogue and the staging query for exactly one
publisher, and loads one tidy table. The hub reads the spokes' loaded tables, stacks them into a
single `fct_` table, and joins `dim_series` for metadata.

What this buys:

- **Refresh isolation.** One publisher being down, rate-limited or mid-migration does not block
  everything else. A monolith refreshes as a unit: one broken source and you have no numbers at
  all.
- **Credentials and privacy per source.** Anonymous, organisational, key-based — each spoke
  answers for itself once, instead of one workbook accumulating every prompt.
- **Proportionate refresh.** A daily source refreshes daily; a quarterly one does not need to be
  re-pulled because something else changed.
- **A clear ownership boundary.** "Who broke it" has a one-workbook answer.

The costs, both real:

- **A spoke must be saved after refreshing.** `Excel.Workbook` reads the last saved state of a
  file, so refresh-then-save is one step in the written procedure, not two.
- **Two hops of staleness.** Carry a retrieval timestamp per row so the hub can show the age of
  each source instead of implying they are all current.

Conventions that keep the hub simple:

- **`SeriesId` as `<SOURCE>_<ITEM>_<QUALIFIER>`.** Stable, readable, greppable. Put anything that
  makes two otherwise identical series different into the qualifier — above all the
  classification vintage, without which the two vintages of a migrating series collide and every
  total in the overlap doubles.
- **Store daily data daily.** Aggregation to month is a model-layer decision held per series in
  `dim_series` (`avg`, `last`, `none`), not hard-coded in the staging query. Some series are
  monthly averages by nature, some are month-end observations, and the right rule differs
  between two series from the same publisher. Storing the collapse throws away the ability to
  change your mind.
- **Manual inputs are files in a folder, not paste targets.** Where a source can only be
  exported by hand, drop each export into a folder and read the folder with a query that stacks
  every file, tagging each row with its filename. Pasting into a master sheet destroys the
  previous month's evidence and makes the refresh unrepeatable; a folder keeps every vintage and
  costs nothing.

---

## 7. How to validate a refresh

Run these in order. The first three cost seconds and catch most breakage.

**Row-count identities.** Per series, `rows = periods between MIN and MAX + 1`. Compare against
what you predicted *before* the refresh. Then check gaps separately: a missing month plus a
duplicate leaves the total unchanged.

**Gap and boundary checks.** No missing periods in the middle. `MinPeriod` is where it was last
time or earlier — never later, which means history has been silently lost. `MaxPeriod` moved
forward by the amount the publication calendar implies, and matches the expected lag for that
series.

**Key uniqueness.** `(SeriesId, Period, Vintage)` is unique within a retrieval. A duplicate is a
join that multiplied, or a classification overlap that was not filtered.

**Physical plausibility.** Magnitude, sign, unit and the direction of the recent move, per
series. An index at its own base period is exactly `100.0` — an arithmetic identity that can
genuinely fail. Shares within one document sum to 100. Sub-totals add to the published total.
"It returned rows" is not a result.

**Composition check.** The count by `Method` — published, linked, proxy-derived — should be what
it was last month plus the new periods. A jump means a splice moved or an anchor changed, which
is a decision, not a refresh.

**Run it twice.** The second run must be a no-op: zero new rows, zero new files, an unchanged
checksum of the output. If it is not, something in your key is unstable — a timestamp inside an
identifier, a URL parameter that varies per request, a hash taken over content that includes the
fetch time. Until the second run is clean, you do not know what your key is.

**Read one number you can check by hand.** Pick a single figure from the output and find it in
the publisher's own release. Everything above verifies internal consistency; only this verifies
that the pipeline is pointed at what you think it is.
