// fnMetStation — Met Éireann monthly climate data for one station -> tidy long table
//
// Query name in Excel: fnMetStation        Load: Connection only
//
// Arguments
//   station : station name as it appears in the API path, e.g. "Dublin Airport",
//             "Cork-Airport" (note the hyphen - see the gotchas in the README)
//
// Returns: Station | Metric | Year (number) | MonthName | Date (date, 1st of month) | Value
//
// The JSON nests four levels: metric -> "report" -> year -> month. Each metric also carries
// an "LTA" pseudo-year holding long-term averages; it is dropped here, because leaving it in
// forces the Year column to text and it is not an observation.
//
// The current month is incomplete. The payload's "up_to" field says how far the data runs
// (e.g. "19-09-2026"), and that month is dropped, so a half month never enters a series as
// if it were a whole one.

let
  fn = (station as text) as table =>
    let
      Source = Json.Document(
        Web.Contents("https://prodapi.metweb.ie",
          [ RelativePath = "monthly-data/" & station,
            Headers = [ Accept = "application/json" ] ])),

      UpTo = try
               let P = Text.Split(Record.FieldOrDefault(Source, "up_to", ""), "-")
               in #date(Number.FromText(P{2}), Number.FromText(P{1}), Number.FromText(P{0}))
             otherwise null,

      Metrics = List.Select(Record.FieldNames(Source),
                  each not List.Contains({"station", "up_to"}, _)),

      MonthNo = ["january" = 1, "february" = 2, "march" = 3, "april" = 4, "may" = 5,
                 "june" = 6, "july" = 7, "august" = 8, "september" = 9, "october" = 10,
                 "november" = 11, "december" = 12],

      Rows = List.Combine(List.Transform(Metrics, (metric) =>
        let
          Report = Record.FieldOrDefault(Record.Field(Source, metric), "report", []),
          Years  = List.Select(Record.FieldNames(Report),
                     each try Number.FromText(_) >= 1900 otherwise false)
        in
          List.Combine(List.Transform(Years, (year) =>
            let
              MonthRec = Record.Field(Report, year),
              Months   = List.Select(Record.FieldNames(MonthRec),
                           each Record.HasFields(MonthNo, Text.Lower(_)))
            in
              List.Transform(Months, (month) =>
                [ Station   = station,
                  Metric    = metric,
                  Year      = Number.FromText(year),
                  MonthName = month,
                  Date      = #date(Number.FromText(year),
                                    Record.Field(MonthNo, Text.Lower(month)), 1),
                  Value     = try Number.FromText(Record.Field(MonthRec, month), "en-US")
                              otherwise null ])))
      )),

      Out     = Table.FromRecords(Rows,
                  type table [Station = text, Metric = text, Year = number,
                              MonthName = text, Date = date, Value = number]),
      Dropped = if UpTo = null then Out
                else Table.SelectRows(Out, each [Date] < Date.StartOfMonth(UpTo)),
      Clean   = Table.SelectRows(Dropped, each [Value] <> null),
      Sorted  = Table.Sort(Clean, {{"Metric", Order.Ascending}, {"Date", Order.Ascending}})
    in
      Sorted
in
  fn
