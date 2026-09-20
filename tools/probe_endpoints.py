#!/usr/bin/env python3
"""Check that every endpoint a connector depends on still answers, and report its shape.

Run it before trusting a connector, and again whenever a refresh looks wrong:

    python3 tools/probe_endpoints.py             # all sources
    python3 tools/probe_endpoints.py ecb         # one source group

For each series it prints HTTP status, retries used, row count, the real first and last
observation dates, the last value, and a STALE flag.

Two things this catches that a status code alone does not:
  * an endpoint that answers HTTP 200 with data frozen months or years ago;
  * a publisher that returns 5xx under a burst of requests - hence the pacing and retries
    below, which every automated pull against these APIs needs as well.

Standard library only. No API keys are used or needed by any source here.
"""
import csv
import io
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime

START = "2015-01"
TIMEOUT = 60
ATTEMPTS = 3            # 1 try + 2 retries
BACKOFF = (2, 5)        # seconds to wait before retry 1 and retry 2
PACE = 1.0              # seconds between requests to the same host
UA = "public-data-powerquery/0.1 (endpoint probe; https://github.com/imgeorgewong/public-data-powerquery)"

# How old the newest observation may be before it is suspicious. This is the series'
# publication lag plus a margin, not just its frequency: ECB MIR lending rates are
# published about five weeks after the reference month, so in mid-September the newest
# figure is legitimately July.
MAX_AGE_DAYS = {"daily": 10, "business": 10, "monthly": 60, "monthly_lagged": 100}

ECB_SERIES = [
    ("MRO policy rate", "FM", "D.U2.EUR.4F.KR.MRR_FR.LEV", "daily"),
    ("Deposit facility rate", "FM", "D.U2.EUR.4F.KR.DFR.LEV", "daily"),
    ("EUR short-term rate", "EST", "B.EU000A2X2A25.WT", "business"),
    ("Euribor 3M, monthly avg", "FM", "M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA", "monthly"),
    ("Euro area NFC lending rate", "MIR", "M.U2.B.A2I.AM.R.A.2240.EUR.N", "monthly_lagged"),
    ("Ireland NFC lending rate", "MIR", "M.IE.B.A2I.AM.R.A.2240.EUR.N", "monthly_lagged"),
] + [(f"EUR/{c} reference rate", "EXR", f"D.{c}.EUR.SP00.A", "business")
     for c in ("GBP", "USD", "CNY", "TRY", "DKK", "SEK")]

BOE_SERIES = [
    ("Bank Rate", "IUDBEDR", "business"),
    ("SONIA", "IUDSOIA", "business"),
    ("PNFC new lending rate", "CFMBJ82", "monthly_lagged"),
]


def fetch(url):
    """GET with retries on 5xx and network errors. Returns (status, body, tries)."""
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/csv,*/*"})
    status = "ERR"
    for attempt in range(1, ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.status, resp.read().decode("utf-8-sig", errors="replace"), attempt
        except urllib.error.HTTPError as exc:
            status = exc.code
            if exc.code < 500:
                return status, "", attempt
        except Exception as exc:
            status = f"ERR {type(exc).__name__}"
        if attempt < ATTEMPTS:
            time.sleep(BACKOFF[attempt - 1])
    return status, "", ATTEMPTS


def parse_date(text, fmts):
    for fmt in fmts:
        try:
            return datetime.strptime(text.strip(), fmt).date()
        except ValueError:
            continue
    return None


def summarise(text, date_col, value_col, fmts):
    """Return (rows, first date, last date, last value) using real dates, not string order."""
    rows = list(csv.DictReader(io.StringIO(text)))
    if not rows:
        return 0, None, None, "-"
    header = list(rows[0].keys())
    dcol = date_col if date_col in header else header[0]
    vcol = value_col if value_col in header else header[1]
    dated = []
    for r in rows:
        d = parse_date(r.get(dcol) or "", fmts)
        if d:
            dated.append((d, (r.get(vcol) or "").strip()))
    if not dated:
        return len(rows), None, None, "-"
    dated.sort(key=lambda t: t[0])
    last_value = next((v for d, v in reversed(dated) if v), "-")
    return len(rows), dated[0][0], dated[-1][0], last_value


def report(label, status, tries, body, freq, date_col, value_col, fmts):
    retry_note = "" if tries == 1 else f" (after {tries - 1} retr{'y' if tries == 2 else 'ies'})"
    if status != 200 or not body.strip():
        print(f"  {label:<30} {status}  <no data>{retry_note}")
        return False
    n, first, last, last_value = summarise(body, date_col, value_col, fmts)
    if last is None:
        print(f"  {label:<30} {status}  rows={n:<6} <no parsable dates>{retry_note}")
        return False
    age = (date.today() - last).days
    flag = f"  STALE ({age}d old)" if age > MAX_AGE_DAYS[freq] else ""
    print(f"  {label:<30} {status}  rows={n:<6} {first} .. {last}  last={last_value}{flag}{retry_note}")
    return not flag


def probe_ecb():
    print("\nECB Data Portal - https://data-api.ecb.europa.eu (no key)")
    ok = True
    for label, flow, key, freq in ECB_SERIES:
        query = urllib.parse.urlencode({"format": "csvdata", "startPeriod": START})
        url = f"https://data-api.ecb.europa.eu/service/data/{flow}/{key}?{query}"
        status, body, tries = fetch(url)
        ok &= report(label, status, tries, body, freq, "TIME_PERIOD", "OBS_VALUE",
                     ("%Y-%m-%d", "%Y-%m"))
        time.sleep(PACE)
    return ok


def probe_boe():
    print("\nBank of England IADB - https://www.bankofengland.co.uk (no key)")
    ok = True
    for label, code, freq in BOE_SERIES:
        query = urllib.parse.urlencode({
            "csv.x": "yes", "Datefrom": "01/Jan/2015", "Dateto": "01/Jan/2035",
            "SeriesCodes": code, "CSVF": "TN", "UsingCodes": "Y", "VPD": "Y", "VFD": "N",
        })
        url = f"https://www.bankofengland.co.uk/boeapps/database/_iadb-fromshowcolumns.asp?{query}"
        status, body, tries = fetch(url)
        ok &= report(label, status, tries, body, freq, "DATE", code, ("%d %b %Y", "%d %B %Y"))
        time.sleep(PACE)
    return ok


# --- sources whose responses are not a simple two-column CSV --------------------------

ONS_SERIES = [
    ("RPI All Items", "/economy/inflationandpriceindices/timeseries/chaw/mm23", 45),
    ("CPI All Items index", "/economy/inflationandpriceindices/timeseries/d7bt/mm23", 45),
    ("CPIH annual rate", "/economy/inflationandpriceindices/timeseries/l55o/mm23", 45),
    ("PPI input, materials", "/economy/inflationandpriceindices/timeseries/ghik/ppi", 60),
    ("PPI output, bricks/tiles", "/economy/inflationandpriceindices/timeseries/ew6c/ppi", 60),
]

ONS_MONTHS = {"JAN": 1, "FEB": 2, "MAR": 3, "APR": 4, "MAY": 5, "JUN": 6,
              "JUL": 7, "AUG": 8, "SEP": 9, "OCT": 10, "NOV": 11, "DEC": 12}


def probe_ons():
    """ONS time series API: JSON with years/quarters/months arrays."""
    import json
    print("\nONS time series - https://www.ons.gov.uk (no key)")
    ok = True
    for label, uri, max_age in ONS_SERIES:
        status, body, tries = fetch(f"https://www.ons.gov.uk{uri}/data")
        retry_note = "" if tries == 1 else f" (after {tries - 1} retries)"
        if status != 200 or not body.strip():
            print(f"  {label:<30} {status}  <no data>{retry_note}")
            ok = False
        else:
            months = json.loads(body).get("months", [])
            dates = []
            for m in months:
                parts = (m.get("date") or "").split()
                if len(parts) == 2 and parts[1].upper()[:3] in ONS_MONTHS:
                    dates.append(date(int(parts[0]), ONS_MONTHS[parts[1].upper()[:3]], 1))
            if not dates:
                print(f"  {label:<30} {status}  rows={len(months)} <no parsable dates>")
                ok = False
            else:
                last, age = max(dates), (date.today() - max(dates)).days
                flag = f"  STALE ({age}d old)" if age > max_age else ""
                last_value = months[-1].get("value", "-")
                print(f"  {label:<30} {status}  rows={len(months):<6} {min(dates)} .. {last}"
                      f"  last={last_value}{flag}{retry_note}")
                ok &= not flag
        time.sleep(PACE)
    return ok


def probe_cso():
    """CSO PxStat: flat CSV, one row per cell, period column named after the time dimension."""
    print("\nCSO PxStat - https://ws.cso.ie (no key)")
    ok = True
    for matrix in ("BHQ13",):
        url = ("https://ws.cso.ie/public/api.restful/PxStat.Data.Cube_API.ReadDataset/"
               f"{matrix}/CSV/1.0/en")
        status, body, tries = fetch(url)
        if status != 200 or not body.strip():
            print(f"  {matrix:<30} {status}  <no data>")
            ok = False
        else:
            rows = list(csv.DictReader(io.StringIO(body)))
            period_col = next((c for c in ("Quarter", "Month", "Year") if rows and c in rows[0]), None)
            periods = sorted({r[period_col] for r in rows}) if period_col else []
            print(f"  {matrix:<30} {status}  rows={len(rows):<6} "
                  f"{periods[0] if periods else '?'} .. {periods[-1] if periods else '?'}  "
                  f"cols={len(rows[0]) if rows else 0}")
        time.sleep(PACE)
    return ok


def probe_govuk():
    """GOV.UK Content API: collection -> newest document -> its spreadsheet attachment."""
    import json
    print("\nGOV.UK Content API - https://www.gov.uk (no key)")
    collection = ("government/collections/"
                  "building-materials-and-components-monthly-statistics-2012")
    status, body, _ = fetch(f"https://www.gov.uk/api/content/{collection}")
    if status != 200:
        print(f"  {'collection':<30} {status}  <no data>")
        return False
    docs = json.loads(body).get("links", {}).get("documents", [])
    if not docs:
        print(f"  {'collection':<30} {status}  <no documents>")
        return False
    newest = docs[0]
    print(f"  {'newest release':<30} {status}  {newest.get('title', '?')}"
          f"  published={newest.get('public_updated_at', '?')[:10]}")
    time.sleep(PACE)
    status, body, _ = fetch(f"https://www.gov.uk/api/content{newest['base_path']}")
    if status != 200:
        print(f"  {'attachments':<30} {status}  <no data>")
        return False
    attachments = json.loads(body).get("details", {}).get("attachments", [])
    xlsx = [a for a in attachments if str(a.get("url", "")).lower().endswith(".xlsx")]
    print(f"  {'attachments':<30} {status}  total={len(attachments)}  xlsx={len(xlsx)}"
          + (f"  -> {xlsx[0]['url'].rsplit('/', 1)[-1]}" if xlsx else "  NO XLSX"))
    return bool(xlsx)


def probe_met():
    """Met Eireann monthly station data: metric -> report -> year -> month."""
    import json
    print("\nMet Eireann - https://prodapi.metweb.ie (no key)")
    station = "Dublin Airport"
    status, body, _ = fetch("https://prodapi.metweb.ie/monthly-data/"
                            + urllib.parse.quote(station))
    if status != 200 or not body.strip():
        print(f"  {station:<30} {status}  <no data>")
        return False
    doc = json.loads(body)
    metrics = [k for k in doc if k not in ("station", "up_to")]
    years = set()
    for m in metrics:
        report = doc.get(m, {}).get("report", {})
        years |= {y for y in report if y.isdigit()}
    hdd = [m for m in metrics if "degree_days" in m]
    print(f"  {station:<30} {status}  metrics={len(metrics):<6} "
          f"years {min(years, default='?')} .. {max(years, default='?')}  "
          f"up_to={doc.get('up_to', '?')}  hdd={'yes' if hdd else 'no'}")
    return True


GROUPS = {"ecb": probe_ecb, "boe": probe_boe, "ons": probe_ons,
          "cso": probe_cso, "govuk": probe_govuk, "met": probe_met}


def main():
    wanted = [a.lower() for a in sys.argv[1:]] or list(GROUPS)
    unknown = [w for w in wanted if w not in GROUPS]
    if unknown:
        print(f"Unknown source group(s): {', '.join(unknown)}. Known: {', '.join(GROUPS)}")
        return 2
    ok = True
    for name in wanted:
        ok &= GROUPS[name]()
    print("\nAll endpoints answered and look current." if ok else
          "\nSome endpoints failed or look stale - see the lines above.")
    print("ENTSO-E is not probed here: it needs a security token, and tokens do not belong"
          " in a repository.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
