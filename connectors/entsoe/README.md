# ENTSO-E Transparency Platform

Wholesale electricity market data for European bidding zones: day-ahead prices, load, and
generation by production type.

- Host: `https://web-api.tp.entsoe.eu`, path `api`
- **A free security token is required.** Register on the platform, email
  `transparency@entsoe.eu` with "RESTful API access" as the subject, then generate the token
  under *My Account*.
- Docs: [Transparency Platform](https://transparency.entsoe.eu/) ·
  [how to get a token](https://transparencyplatform.zendesk.com/hc/en-us/articles/12845911031188-How-to-get-security-token) ·
  [RESTful API guide](https://transparency.entsoe.eu/content/static_content/Static%20content/web%20api/Guide.html)

Unlike every other connector here, this one could not be probed by `tools/probe_endpoints.py`,
because a token is needed and tokens do not belong in a repository.

## Files

| File | Query name in Excel | Load |
|---|---|---|
| `fnEntsoeDocument.m` | `fnEntsoeDocument` | Connection only |

## Handling the token

Create a Power Query **parameter** named `EntsoeToken` (Home → Manage Parameters), or read it
from a single workbook cell, and pass it in:

```m
fnEntsoeDocument(EntsoeToken,
  [ documentType = "A44", in_Domain = "10Y1001A1001A59C", out_Domain = "10Y1001A1001A59C" ],
  "202601010000", "202602010000")
```

A token pasted into a query travels with the workbook: into email attachments, into
SharePoint, into any repository the workbook reaches. Keep it out of the query text.

## Document types

| Code | Content | Max period per request |
|---|---|---|
| `A44` | Day-ahead prices | a year is accepted |
| `A65` | Total load, by **bidding zone** | — |
| `A75` | Actual generation per production type, by **control area** | **one month** |

## Gotchas

- **A65 and A75 are different geographies** in markets where the bidding zone and the
  control area do not coincide. Subtracting one from the other produces a number that looks
  like net imports and is not one. Ratios *within* A75 (gas share, wind share) are safe:
  numerator and denominator come from the same document.
- **A75 carries both directions.** Generation is reported `inBiddingZone`, pumped-storage
  consumption `outBiddingZone`. Counting the second as generation biases every share low.
- **Different months contain different production types.** Combining monthly chunks with a
  function that locks the column set to the first chunk silently drops fuel types: the query
  still returns plausible rows. Union the column names across chunks, filling gaps with null.
  A structural check catches it: gas share + wind share + the rest should add up to a
  generation mix you recognise.
- **Recent data is revised** for a week or two, so a live window of three months is safer
  than one.
- **Market design changes are regime breaks**, not outliers. Ireland's I-SEM went live in
  October 2018; the price series before and after are not one series for lead-lag work.
- **Huge responses arrive as ZIP**, and `Xml.Tables` fails on them with an unhelpful error.
  Shorten the period.
