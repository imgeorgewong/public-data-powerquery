# ONS time series (UK)

Office for National Statistics time series by CDID: RPI, CPI, CPIH, producer prices,
average weekly earnings, vacancies. No registration, no API key.

- Host: `https://www.ons.gov.uk`
- Path: the series' full topic path plus `/data`, which returns JSON
- Find a uri: `https://api.beta.ons.gov.uk/v1/search?q=<cdid>&content_type=timeseries`
- Docs: [ONS Developer Hub](https://developer.ons.gov.uk/) ·
  [rate limiting and bot guidance](https://developer.ons.gov.uk/bots/)

## Files

| File | Query name in Excel | Load |
|---|---|---|
| `fnOnsTimeseries.m` | `fnOnsTimeseries` | Connection only |
| `example_ons_fact.m` | `ONS_Fact` | Load to Table |

## Response shape

Checked on 2026-09-20 with `/economy/inflationandpriceindices/timeseries/chaw/mm23/data`.
Top-level keys are `years`, `quarters`, `months`; each element looks like:

```json
{ "date": "1987 JAN", "value": "100.0", "label": "1987 JAN", "year": "1987",
  "month": "January", "quarter": "", "sourceDataset": "MM23",
  "updateDate": "2015-10-12T23:00:00.000Z" }
```

`CHAW` starting at exactly 100.0 in 1987 JAN is a free anchor check: if the first value of a
refresh is not 100.0, the series being read is not the one intended.

Series used in `example_ons_fact.m`, checked the same day:

| Series | Uri | Range | Last value |
|---|---|---|---|
| RPI All Items | `/economy/inflationandpriceindices/timeseries/chaw/mm23` | 1987 JAN .. current | — |
| CPI All Items index | `/economy/inflationandpriceindices/timeseries/d7bt/mm23` | — | — |
| CPIH annual rate | `/economy/inflationandpriceindices/timeseries/l55o/mm23` | — | — |
| PPI input, materials | `/economy/inflationandpriceindices/timeseries/ghik/ppi` | 2008 DEC .. 2026 AUG | 164.0 |
| PPI output, bricks and tiles | `/economy/inflationandpriceindices/timeseries/ew6c/ppi` | — | — |

Run `python3 tools/probe_endpoints.py ons` for current numbers.

## Gotchas

- **The short uri does not exist.** `/timeseries/<cdid>/<dataset>/data` returns 404; the full
  topic path is required. That is why a catalogue stores whole uris, not CDID + dataset pairs
  to be assembled later — they cannot be assembled.
- **The same CDID appears under several datasets.** The values agree; the uris do not. Pick
  one and keep it, or a later "tidy-up" silently changes which dataset a series comes from.
- **A dataset can be retired while its endpoint keeps answering.** The request returns HTTP
  200 and the data simply stops at some past month. Nothing raises. Check `MAX(Date)` per
  series on every refresh and compare it against that series' expected publication lag.
- **Rate limits are per short window** — an order of ten requests in a few seconds is enough
  to earn a 429 — and Power Query issues queries in parallel. Retry with a pause and respect
  `Retry-After`; ignoring it can extend the block.
- **Prices and labour publish on different lags** (weeks versus about six weeks), so the
  newest month differs by series. That is not a gap.
- **Producer prices were restated in 2025** after a chain-linking error, with all figures
  from late 2020 revised. Older copies of the same series will not match, and that is
  expected rather than a fetch bug.
- For anything published only as a spreadsheet, use the `/current/` alias rather than a
  dated file name: file names carry the release month and break every month.
