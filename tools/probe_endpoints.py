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


GROUPS = {"ecb": probe_ecb, "boe": probe_boe}


def main():
    wanted = [a.lower() for a in sys.argv[1:]] or list(GROUPS)
    unknown = [w for w in wanted if w not in GROUPS]
    if unknown:
        print(f"Unknown source group(s): {', '.join(unknown)}. Known: {', '.join(GROUPS)}")
        return 2
    ok = True
    for name in wanted:
        ok &= GROUPS[name]()
    print("\nAll series answered and are current." if ok else
          "\nSome series failed or look stale - see the lines above.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
