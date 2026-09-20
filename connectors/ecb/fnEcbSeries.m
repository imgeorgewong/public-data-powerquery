// fnEcbSeries — one ECB Data Portal series -> tidy long table
//
// Query name in Excel: fnEcbSeries        Load: Connection only
//
// Arguments
//   flow        : SDMX dataflow, e.g. "FM", "MIR", "EXR", "EST"   (SDMX term; sensitive-scan: allow)
//   key         : series key,    e.g. "D.U2.EUR.4F.KR.MRR_FR.LEV"
//   seriesName  : optional label for the Series column; defaults to "<flow>/<key>"
//   startPeriod : optional "YYYY-MM"; defaults to "2015-01"
//
// Returns: Date (date) | Period (text, as published) | Series (text) | Value (number)
//
// Why one function for daily, monthly and quarterly series:
// TIME_PERIOD is "2026-09-18", "2026-08" or "2026-Q2" depending on the flow. Splitting
// this into a daily and a monthly function makes "which one does this key need?" a
// question the caller has to get right every time, and a wrong answer fails at the type
// conversion, not at the fetch. Detecting the shape here removes that class of mistake.
//
// Dates are built with #date(y, m, d) rather than Date.From(text): Date.From follows the
// machine's locale, so the same workbook parses differently on a machine set to en-US.
//
// The ECB gateway answers 504 (not 429) under a burst of requests, and a different series
// fails each time, so transient 5xx responses are retried rather than reported as errors.

let
  fn = (flow as text, key as text, optional seriesName as text, optional startPeriod as text) as table =>
    let
      Start   = if startPeriod = null then "2015-01" else startPeriod,
      Label   = if seriesName  = null then flow & "/" & key else seriesName,
      Retries = 3,
      Wait    = #duration(0, 0, 0, 5),

      // --- fetch, with retry on transient 5xx -------------------------------------
      Fetch = (attemptsLeft as number) as binary =>
        let
          Response = Web.Contents(
            "https://data-api.ecb.europa.eu",
            [ RelativePath = "service/data/" & flow & "/" & key,
              Query        = [ format = "csvdata", startPeriod = Start ],
              Headers      = [ Accept = "text/csv" ],
              ManualStatusHandling = {500, 502, 503, 504} ]),
          Body   = Binary.Buffer(Response),
          Status = Value.Metadata(Response)[Response.Status],
          Result =
            if Status = 200 then Body
            else if attemptsLeft > 0 then Function.InvokeAfter(() => @Fetch(attemptsLeft - 1), Wait)
            else error Error.Record(
              "ECB request failed",
              "HTTP " & Text.From(Status) & " for " & flow & "/" & key & " after "
                & Text.From(Retries) & " attempts.",
              "A 4xx usually means the series key is wrong; a persistent 5xx means the "
                & "service is unavailable - try again later.")
        in
          Result,

      Raw   = Csv.Document(Fetch(Retries), [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
      Head  = Table.PromoteHeaders(Raw, [PromoteAllScalars = true]),
      Cols  = Table.ColumnNames(Head),
      Check = if List.Contains(Cols, "TIME_PERIOD") and List.Contains(Cols, "OBS_VALUE")
              then Head
              else error Error.Record(
                "Unexpected ECB response",
                "Columns TIME_PERIOD / OBS_VALUE not found for " & flow & "/" & key & ".",
                "Columns returned: " & Text.Combine(Cols, ", ")),

      Kept  = Table.SelectColumns(Check, {"TIME_PERIOD", "OBS_VALUE"}),

      // --- "2026-09-18" | "2026-08" | "2026-Q2" | "2026" -> a date -----------------
      ToDate = (period as text) as date =>
        let
          Parts = Text.Split(Text.Trim(period), "-"),
          Year  = Number.FromText(Parts{0}),
          Rest  = if List.Count(Parts) > 1 then Parts{1} else "01",
          Month = if Text.StartsWith(Rest, "Q")
                  then (Number.FromText(Text.AfterDelimiter(Rest, "Q")) - 1) * 3 + 1
                  else Number.FromText(Rest),
          Day   = if List.Count(Parts) > 2 then Number.FromText(Parts{2}) else 1
        in
          #date(Year, Month, Day),

      Typed = Table.AddColumn(Kept, "Date", each ToDate([TIME_PERIOD]), type date),
      Num   = Table.AddColumn(Typed, "Value",
                each try Number.FromText([OBS_VALUE], "en-US") otherwise null, type number),
      Named = Table.AddColumn(Num, "Series", each Label, type text),
      Ren   = Table.RenameColumns(Named, {{"TIME_PERIOD", "Period"}}),
      Out   = Table.SelectColumns(Ren, {"Date", "Period", "Series", "Value"}),
      Clean = Table.SelectRows(Out, each [Value] <> null),
      Sorted = Table.Sort(Clean, {{"Date", Order.Ascending}})
    in
      Sorted
in
  fn
