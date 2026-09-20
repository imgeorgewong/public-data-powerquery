// fnOnsTimeseries — one ONS time series (CDID) -> tidy long table
//
// Query name in Excel: fnOnsTimeseries        Load: Connection only
//
// Arguments
//   uri        : the series path WITHOUT the host and WITHOUT "/data", e.g.
//                "/economy/inflationandpriceindices/timeseries/chaw/mm23"
//   seriesName : optional label; defaults to the CDID taken from the uri
//   frequency  : optional "months" (default), "quarters" or "years"
//
// Returns: Date (date) | Period (text, as published) | Series (text) | Value (number)
//
// Two things about ONS uris:
//   * the short form "/timeseries/<cdid>/<dataset>/data" returns 404. The full topic path
//     is required, which is why the caller passes a uri rather than a CDID + dataset pair;
//   * the same CDID can live under several datasets (JP9L under lms and unem, K5CD under
//     emp and lms). Pick one and keep it - the numbers are the same, the uri is not.
// Find a uri with: https://api.beta.ons.gov.uk/v1/search?q=<cdid>&content_type=timeseries
//
// ONS rate-limits: roughly 15 requests per 10 seconds for high-demand assets, and Power
// Query fires queries in parallel, so 429 is easy to hit. Transient 429/5xx are retried
// here with a pause; anything else is raised.
//
// A live endpoint says nothing about whether the series is still being updated: a
// discontinued series answers HTTP 200 with data that stops years ago. Check MAX(Date)
// per series after every refresh.

let
  fn = (uri as text, optional seriesName as text, optional frequency as text) as table =>
    let
      Freq    = if frequency = null then "months" else frequency,
      Path    = (if Text.StartsWith(uri, "/") then Text.Middle(uri, 1) else uri),
      Trimmed = if Text.EndsWith(Path, "/data") then Text.Start(Path, Text.Length(Path) - 5) else Path,
      Cdid    = Text.Upper(List.Last(List.RemoveLastN(Text.Split(Trimmed, "/"), 1))),
      Label   = if seriesName = null then Cdid else seriesName,
      Retries = 3,
      Wait    = #duration(0, 0, 0, 10),

      Fetch = (attemptsLeft as number) as binary =>
        let
          Response = Web.Contents("https://www.ons.gov.uk",
            [ RelativePath = Trimmed & "/data",
              Headers = [ Accept = "application/json" ],
              ManualStatusHandling = {429, 500, 502, 503, 504} ]),
          Body   = Binary.Buffer(Response),
          Status = Value.Metadata(Response)[Response.Status],
          Result =
            if Status = 200 then Body
            else if attemptsLeft > 0 then Function.InvokeAfter(() => @Fetch(attemptsLeft - 1), Wait)
            else error Error.Record(
              "ONS request failed",
              "HTTP " & Text.From(Status) & " for " & Trimmed,
              "429 = rate limited, slow the refresh down. 404 = wrong uri; the short "
                & "/timeseries/<cdid>/<dataset> form does not exist.")
        in
          Result,

      Json  = Json.Document(Fetch(Retries)),
      Obs   = try Record.Field(Json, Freq) otherwise
              error Error.Record("Unexpected ONS response",
                "No """ & Freq & """ array in the response for " & Trimmed),
      Empty = if List.Count(Obs) = 0
              then error Error.Record("Empty ONS series",
                     "The " & Freq & " array is empty for " & Trimmed,
                     "The series may publish at a different frequency.")
              else Obs,

      Months = ["JAN" = 1, "FEB" = 2, "MAR" = 3, "APR" = 4, "MAY" = 5, "JUN" = 6,
                "JUL" = 7, "AUG" = 8, "SEP" = 9, "OCT" = 10, "NOV" = 11, "DEC" = 12],

      // "2026 AUG" (months) | "2026 Q2" (quarters) | "2026" (years)
      ToDate = (d as text) as nullable date =>
        let
          Parts = Text.Split(Text.Trim(d), " "),
          Year  = try Number.FromText(Parts{0}) otherwise null,
          Tail  = if List.Count(Parts) > 1 then Text.Upper(Parts{1}) else "",
          Month = if Tail = "" then 1
                  else if Text.StartsWith(Tail, "Q")
                  then (Number.FromText(Text.End(Tail, 1)) - 1) * 3 + 1
                  else Record.FieldOrDefault(Months, Text.Start(Tail, 3), null)
        in
          if Year = null or Month = null then null else #date(Year, Month, 1),

      Rows = List.Transform(Empty, (r) =>
               [ Date   = ToDate(Record.FieldOrDefault(r, "date", "")),
                 Period = Record.FieldOrDefault(r, "date", ""),
                 Series = Label,
                 Value  = try Number.FromText(Record.FieldOrDefault(r, "value", ""), "en-US")
                          otherwise null ]),
      Out    = Table.FromRecords(Rows,
                 type table [Date = date, Period = text, Series = text, Value = number]),
      Clean  = Table.SelectRows(Out, each [Date] <> null and [Value] <> null),
      Sorted = Table.Sort(Clean, {{"Date", Order.Ascending}})
    in
      Sorted
in
  fn
