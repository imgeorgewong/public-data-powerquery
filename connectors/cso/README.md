# CSO PxStat (Ireland)

Irish official statistics: earnings, labour costs, vacancies, planning permissions,
wholesale price indices. No registration, no API key.

- Host: `https://ws.cso.ie`
- Path: `public/api.restful/PxStat.Data.Cube_API.ReadDataset/{matrix}/CSV/1.0/en`
- Docs: [CSO databases](https://www.cso.ie/en/databases/) ·
  [PxStat API wiki](https://github.com/CSOIreland/PxStat/wiki/API) ·
  [Cube RESTful](https://github.com/CSOIreland/PxStat/wiki/API-Cube-RESTful)

## Files

| File | Query name in Excel | Load |
|---|---|---|
| `fnCsoTable.m` | `fnCsoTable` | Connection only |

## Response shape

Checked on 2026-09-20 with matrix `BHQ13`:

```
"STATISTIC","STATISTIC Label","TLIST(Q1)","Quarter","C01921V02511","Type of Development",
"C02074V02506","Functional Category","C02196V04140","Region","UNIT","VALUE"
"BHQ13","Planning Permissions Granted","20181","2018Q1","-","All types of construction",
"-","All functional categories","-","State","Number","6010"
```

Every classification arrives as a code column plus a label column. The period column is
named after the time dimension (`Quarter`, `Month`, `Year`), which is why `fnCsoTable`
looks for it by name rather than by position.

## Gotchas

- **Aggregate rows sit beside detail rows, unlabelled.** `State`, `All NACE`,
  `All types of construction`, `All employees` are all totals in the same column as the
  breakdowns. Sum without excluding them and every figure doubles. Check the distinct values
  of each classification before aggregating - not after the numbers look wrong.
- **Preliminary values are revised**, and scheduled revisions can restate an entire series
  (dates for these are published in advance). If a number has been reported externally, keep
  a dated copy of it; a table that overwrites on refresh cannot answer "what did we publish
  last quarter, and has it changed since?".
- **Classification migrations move boundaries, not just labels.** When a statistics office
  moves between two versions of an industry classification, matching sectors by code is
  wrong even where the code is unchanged. Keep both vintages, stacked with a vintage column,
  and compute link ratios per sector over the overlap window - never one global factor.
- **Not every statistic has a seasonally adjusted variant**, and a withdrawn one can vanish
  from the API while still existing in an old extract. Check what the API serves before
  relying on a series being reproducible.
- **Surveys and administrative registers are not interchangeable** even when their levels
  look similar: different definitions, different frequencies, different revision behaviour.
- **CSV generation happens on request.** A large matrix takes tens of seconds before the
  first byte, and a refresh that pulls several is minutes, not seconds. Referencing a query
  twice runs it twice - Power Query has no cross-query cache - so pull once into a
  connection-only query and branch from there.
