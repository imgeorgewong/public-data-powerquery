# public-data-powerquery

**English** | [中文](README.zh-CN.md)

Excel Power Query (M) connectors for free, official economic and statistical data sources:
central-bank rates and FX, national statistics, construction material price indices, weather and electricity market data.

Each connector is plain `.m` text: paste it into Power Query's Advanced Editor and refresh.
The repository contains code and documentation only — **no data**. Data copyright belongs to each publisher.

> Status: work in progress. Connectors are added one at a time and marked below once tested.

## Connectors

| Source | Folder | What it returns | Key needed | Status |
|---|---|---|---|---|
| ECB Data Portal | `connectors/ecb/` | Policy and market rates, euro-area lending rates, FX reference rates | No | planned |
| Bank of England IADB | `connectors/boe/` | Bank Rate, SONIA, corporate lending rates | No | planned |
| CSO PxStat (Ireland) | `connectors/cso/` | Earnings, labour costs, vacancies, planning permissions | No | planned |
| ONS time series (UK) | `connectors/ons/` | RPI, CPI, CPIH, PPI, earnings, vacancies | No | planned |
| ONS PPI dataset + DBT/BIST building materials | `connectors/uk-materials/` | Construction material price indices, with proxy extension of discontinued series | No | planned |
| Met Éireann | `connectors/met-eireann/` | Monthly station climate data | No | planned |
| ENTSO-E Transparency Platform | `connectors/entsoe/` | Irish SEM day-ahead prices, load, generation mix | **Yes (free token)** | planned |

## Documentation

- `docs/gotchas.md` — behaviours of these APIs and of Power Query that silently produce wrong numbers
- `docs/methodology.md` — chain-linking, rebasing, vintage stacking, proxy splicing
- `docs/patterns.md` — tidy long format, frozen history + live window, zero-cost QA queries, hub-and-spoke workbook layout

## Requirements

Excel for Windows (Microsoft 365). Excel for Mac's Power Query does not support web data sources.

## Install

```
git clone https://github.com/imgeorgewong/public-data-powerquery.git
cd public-data-powerquery
git config core.hooksPath .githooks
```

## Development

Enable the sensitive-content check once per clone:

```
git config core.hooksPath .githooks
```

Every commit then runs `tools/check_sensitive.py`, which blocks office/data files,
employer-internal URLs and paths, GUIDs and credential-looking strings.
Before making the repository public, also run the full scan:

```
python3 tools/check_sensitive.py --all
```

A second script checks that the endpoints behind the connectors still answer, and prints
row counts, real first/last observation dates and the last value:

```
python3 tools/probe_endpoints.py          # all sources
python3 tools/probe_endpoints.py ecb      # one source group
```

It flags series that answer HTTP 200 while their data has stopped updating — something a
status code alone never shows.

## Related

[report-collector](https://github.com/imgeorgewong/report-collector) — Python framework for collecting publicly available reports.

## Author

Jingbo Wang ([@imgeorgewong](https://github.com/imgeorgewong)) · [imgeorgewong.github.io](https://imgeorgewong.github.io)

## License

MIT — see `LICENSE`.
