# UK construction material price indices (DBT via GOV.UK)

Monthly price indices for construction materials, published by the UK Department for
Business and Trade (compiled from ONS producer-price inputs) as spreadsheet attachments to a
GOV.UK statistical release. No registration, no API key.

- Collection: `/government/collections/building-materials-and-components-monthly-statistics-2012`
- Content API: `https://www.gov.uk/api/content/<path>`
- Docs: [GOV.UK Content API](https://content-api.publishing.service.gov.uk/) ·
  [the collection page](https://www.gov.uk/government/collections/building-materials-and-components-monthly-statistics-2012)

## Files

| File | Query name in Excel | Load |
|---|---|---|
| `fnGovUkLatestAttachment.m` | `fnGovUkLatestAttachment` | Connection only |
| `example_dbt_materials.m` | `DBT_Materials` | Load to Table |

Proxy series for discontinued materials come from the ONS connector in `../ons/`.

## How the file is located

The download URL changes every month and carries a content hash, so it cannot be built by
hand. Two Content API calls resolve it, both checked on 2026-09-20:

1. `GET /api/content/government/collections/building-materials-and-components-monthly-statistics-2012`
   → `links.documents`, newest first. Newest at the time of checking:
   *"Building materials and components statistics: July 2026"*, `public_updated_at`
   `2026-08-05T08:30:01Z`.
2. `GET /api/content/<that document's base_path>` → `details.attachments`, each with
   `title`, `url` and `content_type`. The tables workbook is the `.xlsx` whose title contains
   "tables"; its URL is an `assets.publishing.service.gov.uk/media/<hash>/...` link.

## Gotchas

- **Each release contains only the last 13 months.** Reading the newest file alone gives a
  13-month history, and a year later the months in between are gone from every published
  file. Build history by stacking vintages: the older releases stay reachable through
  `links.documents`.
- **Revisions are published as a separate back-data file**, not by amending the monthly
  workbooks. An index rebuilt from monthly files alone will disagree with the publisher's
  own revised history.
- **Some series are discontinued and some are suppressed** (a disclosure marker instead of a
  number, sometimes from a particular month onward). A discontinued series can be kept moving
  with a proxy index, but the substitute is a broader, industry-level series — flag the
  derived rows and say so wherever the number is shown. See `../../docs/methodology.md`.
- **A suppressed value in the base month makes that base unusable**; the series has to be
  based on a later month, and then it is not comparable with its neighbours without care.
- **The same material can be published by two bodies with slightly different values and
  different lags.** Choose one and stay with it; do not fill a gap from the other.
- **The sheet layout is the publisher's.** Locate columns by header text, never by position,
  and let a layout change raise an error rather than silently shift a column.
- **`Excel.Workbook` reads what was last saved.** When a source workbook is refreshed but not
  saved, the model keeps reading the old values.
