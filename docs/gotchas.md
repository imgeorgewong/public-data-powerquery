# Things that silently produce wrong numbers

Every item here shares one property: **nothing fails.** The query refreshes, the table has rows,
the values look plausible, and the number is wrong.

This page is cross-cutting — behaviours of Power Query / M itself, and of public statistical
APIs in general. Traps specific to one publisher live in that connector's README.

---

## 1. Silent data loss

**`Table.Combine` locks the column set to the first input.** Columns that exist only in later
tables are dropped, without a warning. This bites whenever the response shape varies over time:
a month with no wind generation has no wind column, an older release has fewer categories. The
chunk you happened to fetch first decides what the whole series contains. Union the column names
first, fill the gaps with null, then combine:

```m
AllCols = List.Distinct(List.Combine(List.Transform(Chunks, Table.ColumnNames))),
Padded  = List.Transform(Chunks, (t) => Table.SelectColumns(t, AllCols, MissingField.UseNull)),
Result  = Table.Combine(Padded)
```

**`Table.Combine({})` throws instead of returning an empty table.** An empty list is not an
empty table, so careful per-chunk error handling that can legitimately return nothing blows up
at the combine — far from the cause. Seed the list with a typed empty table of the expected
shape: `Table.Combine({EmptySchema} & Chunks)`.

**Totals sit beside detail rows, unlabelled.** Statistical APIs routinely return aggregate rows
in the same column, at the same nesting level, as the breakdowns they summarise: an "all
sectors" row next to each sector, a national row next to each region. No flag column marks them.
Sum the column and every figure doubles — unevenly, because not every dimension has a total.
Before loading any new table, list the distinct values of every classification column and exclude
the totals explicitly by value. Do it the first time, not after the numbers look wrong.

**De-duplicate before a left outer join, not after.** A join against duplicate keys multiplies
rows, and `Table.Distinct` on the wide result does not undo it — it keeps every distinct
combination. Dedupe the right-hand key first, then assert the left row count is unchanged.

**Overlapping vintages double everything in the overlap.** When a publisher changes a
classification it republishes several years under both versions. Stack them — which you should —
and each period in the overlap holds two rows for the same thing. Any aggregation that does not
filter on the vintage column first is exactly twice the truth *in the overlap only*: the recent
end and the far end are right, which is the worst shape a silent error can have. Put the
classification version in the series identifier, not only in an attribute column. See
`docs/methodology.md`.

**The current period is not finished.** Ten days of a month land in the series looking like a
whole month: low, but not absurd, so nothing rings — and every year-on-year comparison that
touches it is poisoned. Find the field that says how far the current period has run and drop the
incomplete period; if there is none, drop the last period unless the publication calendar says
it is complete.

**`Excel.Workbook` reads the last *saved* state of a source file.** A workbook refreshed but not
saved gives its consumer yesterday's numbers, with nothing to indicate the two disagree. Make
refresh-then-save one step in the written procedure, and carry a retrieval timestamp in the data
so a consumer can see how old each source is.

---

## 2. Types and locale

**`Date.From` on text follows the machine's regional settings.** `Date.From("03/04/2026")` is
3 April on one machine and 4 March on another: same workbook, same code, different answer per
colleague, and both are valid dates so nothing raises. This is the commonest cause of "it works
on my machine" in Power Query. Never parse a date from text without saying how — either
construct it with `#date(Y, M, D)` from parts you split yourself, or pass an explicit culture:
`Table.TransformColumnTypes(Src, {{"Date", type date}}, "en-GB")`.

**One culture per query, not one per workbook.** Sources inside a single workbook disagree about
date order: one file writes `M/D/YYYY`, another `D/M/Y` with a time component, a third an ISO
date. No workbook-wide setting makes all three right. Set the culture on the type step of *each*
staging query, next to the source it belongs to, with a comment naming the format that source
emits.

**Period columns change shape with frequency.** The same publisher gives `2026-09-18` for a
daily series, `2026-08` for a monthly one and `2026-Q2` for a quarterly one, in a column with
the same name. A single parser guesses; guessing wrong on the quarterly one yields either an
error (good) or a date in the wrong quarter (bad). Branch on the text pattern and build the date
explicitly per shape.

**A period held as text sorts alphabetically.** `"31 Oct 2025"` is greater than `"30 Sep 2026"`
as text, so an "is this series current?" check over an untyped period column is wrong in a way
that depends on which month names are involved — meaning it works most of the year.

**Loose and strict matching in the same chain.** `COUNTIF` coerces types and matches the text
`"1042"` against the number `1042`; `XLOOKUP` does not. Store an identifier as text in one table
and as a number in the other and the same row carries two flags saying opposite things. Use one
matching function per chain, and normalise the key type where the data enters, not where it is
used.

**PivotTable distinct count must be chosen at creation.** "Distinct Count" only appears as a
summary option when the PivotTable was created with **Add this data to the Data Model** ticked.
It cannot be added later; the pivot has to be rebuilt.

---

## 3. Query structure and refresh cost

**Power Query has no cross-query cache.** Referencing a query from two places runs it twice.
Two sheets built on the same web source download it twice; "Connection only" does not mean
"computed once". The cost of a refresh is the number of *evaluations*, not the number of
queries. Where one source feeds several outputs, land it once and branch, or accept the repeat
cost knowingly.

**A catalogue query that returns tables downloads everything to draw its preview.** The classic
"one row per series, data nested in a column" catalogue fetches every source just to render the
preview pane — every time the editor opens or the query is touched. This is what "the editor
keeps spinning" usually is. Make it a **function** instead: a function query has no previewable
result, so nothing evaluates until something calls it. That one change turns an expensive object
into a free one.

**Turn off background data previews.** Query Options → Global → Data Load → *Allow data previews
to download in the background*. Left on, Excel re-fetches sources while you are doing something
else; most mystery network traffic and unexplained slowness is this.

**`Formula.Firewall` cannot be fixed by rewriting the chain.** Combining `Excel.CurrentWorkbook`
(a lookup table, a parameter sheet) with a web source in one evaluation chain raises it, and
restructuring the M usually does not clear it. Two fixes do work: keep the local table in its own
query and the web call in its own query, so neither chain spans both privacy levels; or set
Query Options → Current Workbook → Privacy → *Ignore the Privacy Levels* — a per-workbook
setting that must be applied again on every machine the workbook opens on.

**Anchor credentials to the host with `RelativePath`.** `Web.Contents("https://host/path/" &
item)` creates a credential entry per URL: twenty-five stations, twenty-five prompts. Put the
host in the first argument and everything variable in `RelativePath` and `Query`:

```m
Web.Contents("https://host", [ RelativePath = "api/" & item, Query = [ format = "csv" ] ])
```

**Some endpoints generate the extract on request.** A large table is built when you ask, not
served from a cache: tens of seconds before the first byte is normal, and a refresh pulling
several is minutes, not seconds. Combined with the absence of a cross-query cache, an
innocent-looking dependency graph becomes a twenty-minute refresh.

---

## 4. API limits and error handling

**HTTP 200 does not mean the series is still maintained.** A discontinued series keeps
answering: 200, valid CSV, stable row count, data that stopped eighteen months ago. Series get
retired, renamed, superseded or moved under a different dataset, and the old address commonly
keeps serving the frozen copy. Check `MAX(period)` per series on every refresh and compare it
with that series' expected publication lag. This single check catches more real breakage than
any other.

**Rate limits arrive disguised.** Published limits are per short window — per ten seconds as
well as per minute — and "high demand" resources often carry a much tighter limit than the
documented general one. Two things make this hard to recognise:

- *The status code may not be 429.* A gateway in front of the API can answer `503` or `504`
  under a burst, which reads as an outage rather than as your own pacing.
- *A different series fails each time*, because the failure lands on whichever request was
  unlucky. It looks like bad data in one series, not a systemic limit.

Power Query issues requests in parallel, so pacing cannot live in the loop that calls your
function — it must be inside the function. Retry transient 5xx with a delay, honour
`Retry-After` when sent, and do **not** retry a 4xx, which means the request itself is wrong.
Ignoring `Retry-After` can escalate a throttle into an hour-long block.

**`try ... otherwise null` destroys the information you need.** It turns an expired credential
(401), a bad parameter (400), a legitimately empty period and a network blip into the same
value, and you then spend an hour trying to tell them apart from the outside. Handle the status
explicitly and raise a described error for anything that is not legitimately empty:

```m
Raw     = Web.Contents(Host, [ RelativePath = Path, ManualStatusHandling = {400, 401, 404, 429} ]),
Status  = Value.Metadata(Raw)[Response.Status],
Checked = if Status = 200 then Raw
          else if Status = 404 then EmptySchema
          else error Error.Record("Fetch failed", Text.From(Status) & " for " & Path)
```

**Assert on shape, not on status.** A wrong identifier frequently returns a human-readable HTML
page with a 200; a binary download can return an error page with the right content type; a ZIP
can arrive where XML was expected. Check the thing itself — column count and expected header
names for a CSV, the `%PDF-` magic bytes for a PDF, the first bytes for an archive. A
status-code-only check passes on all three failures.

**A misspelled parameter name returns zero rows, not an error.** Query-string APIs generally
ignore parameters they do not recognise, so a subtly wrong filter name answers 200 with an empty
result set, which tolerant code combines cheerfully with everything else. Treat zero rows as a
failure by default, with an explicit opt-in for series that can legitimately be empty.

**Per-request span limits differ by endpoint.** One document type on an API may accept a year
per request while another accepts one month. A chunking loop sized for the permissive one
returns nothing for the strict one — again with no error. Encode the limit next to the endpoint,
not as a global constant.

**Oversized responses arrive compressed.** Past some size, APIs switch to returning an archive.
The XML or CSV parser then fails with a message about the *parser*, sending you to the wrong
place. Detect the archive, or reduce the requested span until responses stay under the
threshold.

**Short URL forms and legacy aliases.** An obvious shorter version of a documented URL often
404s while the full path works, and a path that worked last year can be retired without a
redirect. Where a publisher offers a "current" alias for a downloadable file, use it: a dated
filename is a guaranteed 404 next month.

**The same identifier under two datasets.** A series code can be reachable through more than one
dataset path, and those are not always the same data — they differ in revision timing, in the
vintage served, or in how far the history runs. Pick one path per series, record it, and do not
switch casually. Switching is a silent restatement of your own history.

**Second-hand aggregators.** A convenience wrapper around an official source adds a failure mode
and removes provenance; an unexpected status from one is a reason to go to the publisher, not to
debug the wrapper. Where a re-publisher is genuinely the only automatable route, record its
status and any re-distribution limits in the source register, and spot-check its values against
the publisher's own release.

**Keys and tokens travel with the workbook.** A credential pasted into query text goes wherever
the file goes — mail attachments, shared drives, any repository it reaches. Keep it in a Power
Query parameter or a single cell, and keep that out of what you share.

**Never turn off TLS verification.** If a certificate chain fails, fix the chain (an up-to-date
trust store, the publisher's intermediate certificate). Disabling verification replaces a visible
failure with an invisible one.

---

## 5. Revisions, restatements, and history that disappears

**Preliminary is not final, and scheduled revisions restate history.** Values flagged
preliminary change later; separately, most statistical offices run revision rounds that rewrite
years of a series at once. Neither shows up as an error on refresh — the numbers simply differ
from the ones you reported last month.

**Some revisions are never announced.** No marker, no note, no version number. Change detection
that looks for markers finds nothing, every time. Detect change by comparing the full retrieved
series against what you already hold, value by value, and report the count and span of
differences — which is only possible if you kept the earlier values.

**Rolling windows delete the past at the source.** Some APIs serve only the last few years, or
only the last thirteen months per release. What falls out is gone from the source; nothing
errors, the series just starts later than it used to — and if your table overwrites on refresh,
your copy starts later too. Archive on first retrieval into a frozen table the refresh never
rewrites, and check the **start** date of every series each refresh, not only the end date.

**A withdrawn series can vanish from the API while it still exists in your workbook.** When a
publisher retires a variant — a seasonally adjusted version, an older classification —
re-fetching returns zero rows, and if the only remaining copy of that history is the workbook,
the next refresh destroys it. Back up before re-running anything that touches a series you
cannot re-download, and make that a deliberate documented decision rather than an assumption
about what the storage layer keeps.

---

## 6. Validation

**Expect a row count before you refresh, and check gaps rather than totals.** For a complete
monthly series the count is an identity: `rows = DATEDIF(MIN(period), MAX(period), "m") + 1`. A
total alone hides a hole in the middle, because a missing month and a duplicate cancel out.
Compute the identity per series and report the gap count.

**"It returned rows" is not "it worked".** Check magnitude, sign, unit and the direction of the
recent move before building on a result. Almost every failure on this page produces rows.

**Use arithmetic identities that can actually fail.** Good ones: an index equals exactly 100.0 at
its own base period; shares within one document sum to 100; sub-totals add to the published
total; a floor rate never exceeds a ceiling rate. Beware identities that hold at one frequency
but not another — the reciprocal of a monthly average is not the monthly average of the
reciprocal, so a cross-rate check must run on daily data, before aggregation.

**Run it twice.** The second run of an idempotent refresh should add nothing: zero new rows,
zero new files, an unchanged checksum. This is the only reliable way to find which dimension of
your key is unstable — a timestamp inside an identifier, a URL parameter that changes per
request, a hash taken over content that includes the retrieval time. If the second run is not a
no-op, you do not yet know what your key is.

**Make sure the test could have failed.**

- A suite that passes on a fallback path proves the fallback works. Assert which path ran.
- An assertion containing `and` / `or` may be vacuously true. Read it again.
- A field declared in configuration but never read by the engine fails silently. Pin that
  contract with a structural test.
- A green summary means nothing threw. It does not mean the output is right.

**Two sources that look independent may not be.** Where one index is derived from another
publisher's inputs, loading both is double counting dressed as corroboration and their agreement
tells you nothing. Establish the lineage of a series before using it as a cross-check — and
before loading both into the same store.
