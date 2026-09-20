# ECB Data Portal

Policy and market rates, euro-area and national lending rates, and euro foreign-exchange
reference rates, straight from the publisher. No registration, no API key.

- Host: `https://data-api.ecb.europa.eu`
- Path: `service/data/{flow}/{key}` with `?format=csvdata&startPeriod=YYYY-MM`
- Docs: [API overview](https://data.ecb.europa.eu/help/api/overview) ·
  [data queries](https://data.ecb.europa.eu/help/api/data) ·
  [EXR dataset](https://data.ecb.europa.eu/data/datasets/EXR)

## Files

| File | Query name in Excel | Load |
|---|---|---|
| `fnEcbSeries.m` | `fnEcbSeries` | Connection only |
| `fnMonthlyFromDaily.m` | `fnMonthlyFromDaily` | Connection only |
| `example_rates.m` | `ECB_Rates` | Load to Table |

Paste each file into Power Query → Home → **Advanced Editor** of a blank query, and name the
query exactly as above. When asked for credentials for `data-api.ecb.europa.eu`, choose
**Anonymous** and privacy level **Public**.

## Series used in the example

Measured on 2026-09-20 with `tools/probe_endpoints.py`, `startPeriod=2015-01`.

| Series | Flow | Key | Freq | Rows | Range | Last value |
|---|---|---|---|---|---|---|
| MRO policy rate | `FM` | `D.U2.EUR.4F.KR.MRR_FR.LEV` | calendar daily | 4,281 | 2015-01-01 .. 2026-09-20 | 2.65 |
| Deposit facility rate | `FM` | `D.U2.EUR.4F.KR.DFR.LEV` | calendar daily | 4,281 | 2015-01-01 .. 2026-09-20 | 2.5 |
| EUR short-term rate (€STR) | `EST` | `B.EU000A2X2A25.WT` | business daily | 1,784 | 2019-10-01 .. 2026-09-17 | 2.44 |
| Euribor 3M, monthly average | `FM` | `M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA` | monthly | 140 | 2015-01 .. 2026-08 | 2.5131429 |
| Euro area NFC lending rate | `MIR` | `M.U2.B.A2I.AM.R.A.2240.EUR.N` | monthly | 139 | 2015-01 .. 2026-07 | 3.8 |
| Ireland NFC lending rate | `MIR` | `M.IE.B.A2I.AM.R.A.2240.EUR.N` | monthly | 139 | 2015-01 .. 2026-07 | 5.25 |
| EUR/GBP, USD, CNY, TRY, DKK, SEK | `EXR` | `D.{CCY}.EUR.SP00.A` | business daily | 2,999 each | 2015-01-02 .. 2026-09-18 | — |

Self-checks that hold for any refresh:

- monthly series: `rows = months between first and last + 1`, with no gaps
  (140 rows over 2015-01..2026-08 = 140 months);
- the six EXR series must return the **same** row count and the same date range as each
  other — they are published together;
- `MRO ≥ DFR` on every date, and both are constant between policy decisions.

## Publication timing

| Series | Published | Lag |
|---|---|---|
| EXR reference rates | ~16:00 CET on TARGET working days | same day |
| FM / EST rates | daily | same or next day |
| MIR lending rates | monthly | about 5 weeks after the reference month |

So in mid-September the newest MIR figure is July. That is not a stale series.

## Gotchas

- **The gateway answers 504, not 429, under a burst of requests**, and a different series
  fails each time. `fnEcbSeries` retries transient 5xx three times, five seconds apart; a
  4xx is not retried, because that means the key is wrong. Probing 15 series back to back
  without pacing produced three to four 504s on every run.
- **`TIME_PERIOD` has a different shape per flow**: `2026-09-18`, `2026-08`, `2026-Q2`.
  `fnEcbSeries` detects the shape; do not feed the text to `Date.From`, which follows the
  machine locale and silently parses differently on another machine.
- **FM daily series are calendar-daily** (weekends carry the previous value), **EXR is
  business-daily only**. Taking "the last value of the month" therefore means a slightly
  different thing in each, which matters when they meet in one monthly table.
- **A monthly average is not the average of a monthly series**: `EURIBOR3MD_.HSTA` is
  already a monthly mean, so do not pass it through `fnMonthlyFromDaily` with `"avg"`.
- **The reciprocal of a monthly average is not the monthly average of the reciprocal.**
  Cross rates hold on daily data, not on monthly aggregates, so derive them before
  collapsing to months.
- The ECB states its reference rates are published for information only and discourages
  using them to settle transactions. Fine for monitoring and reporting.
