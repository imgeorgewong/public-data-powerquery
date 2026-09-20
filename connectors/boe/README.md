# Bank of England — Interactive Database (IADB)

UK policy, money-market and lending rates. No registration, no API key.

- Host: `https://www.bankofengland.co.uk`, path `boeapps/database/_iadb-fromshowcolumns.asp`
- The query string carries the series codes and the date range; the response is CSV.
- Docs: [IADB](https://www.bankofengland.co.uk/boeapps/database/) ·
  [IADB help](https://www.bankofengland.co.uk/boeapps/database/help.asp)

## Files

| File | Query name in Excel | Load |
|---|---|---|
| `fnBoeSeries.m` | `fnBoeSeries` | Connection only |

`fnMonthlyFromDaily` from `../ecb/` collapses these to one row per month.

## Series used in testing

Measured on 2026-09-20 with `tools/probe_endpoints.py`, `Datefrom = 01/Jan/2015`.

| Series | Code | Freq | Rows | Range | Last value |
|---|---|---|---|---|---|
| Bank Rate | `IUDBEDR` | business daily | 2,959 | 2015-01-02 .. 2026-09-17 | 3.75 |
| SONIA | `IUDSOIA` | business daily | 2,958 | 2015-01-02 .. 2026-09-16 | 3.7303 |
| PNFC new lending rate | `CFMBJ82` | monthly | 139 | 2015-01-31 .. 2026-07-31 | 5.62 |

## Gotchas

- **Dates come as `17 Sep 2026`.** Sorting or comparing that text gives the wrong answer:
  `"31 Oct 2025"` is greater than `"30 Sep 2026"` alphabetically. `fnBoeSeries` maps the
  month name explicitly. The same trap applies to any check of "is this series current?".
- **A wrong series code returns a page, not an error.** The function raises when fewer than
  two columns come back, which is what that failure looks like.
- **SONIA was reformed on 23 April 2018.** The series runs continuously across that date,
  but the definition changed; treat it as two regimes for anything sensitive to level.
- **Monthly series are reported at month end** (`31 Jul 2026`), daily series on the day.
  Mixing them in one monthly table means deciding what "the value for July" is.
- Encoding is Windows-1252, not UTF-8, and the CSV has a preamble row that
  `Table.PromoteHeaders` handles - do not skip rows by position.
