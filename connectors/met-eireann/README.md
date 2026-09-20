# Met Éireann — monthly station data

Monthly climate data for Irish synoptic stations: rainfall, mean temperature, soil
temperature, solar radiation, evaporation, and heating degree days. No key.

- Host: `https://prodapi.metweb.ie`, path `monthly-data/{station}`
- Docs: [Met Éireann available data](https://www.met.ie/climate/available-data)

## Files

| File | Query name in Excel | Load |
|---|---|---|
| `fnMetStation.m` | `fnMetStation` | Connection only |

## Response shape

Checked on 2026-09-20 with `monthly-data/Dublin Airport`. Top-level keys:

```
station, up_to, total_rainfall, mean_temperature, soil_temperature, solar_radiation,
potential_evapotranspiration, evaporation, degree_days_below_fiften_point_five_degrees_celsius
```

Each metric nests `report` → year → month, e.g. `total_rainfall.report.2026.january`.

**Heating degree days are published, not derived.** The key
`degree_days_below_fiften_point_five_degrees_celsius` is HDD to a 15.5 °C base (the spelling
of "fifteen" is the publisher's). Anyone computing degree days from monthly mean temperature
should use this instead: a mean-based calculation understates degree days, because the daily
variation around the mean is where they accumulate.

## Gotchas

- **The API serves a rolling window of recent years only.** Older data disappears from the
  source. Without an archive of your own the long history is gone for good, and no error is
  raised when it goes - the series simply starts later than it used to.
- **`LTA` is a year key holding long-term averages**, mixed in with the real years. Left in,
  it forces the year column to text and quietly pollutes any average.
- **`up_to` marks how far the current month has run** (e.g. `19-09-2026`). Drop that month,
  or a partial month enters the series looking like a complete one - the classic silent
  error, because the value is plausible.
- **Station slugs are not uniform.** Some use spaces, some hyphens (`Cork-Airport`). Build
  the list from what the API accepts, not from the station names on the website.
- **Credentials anchor to the host, not the URL**, so `Web.Contents` is called with
  `RelativePath`. Without it, 25 stations mean 25 separate credential prompts.
