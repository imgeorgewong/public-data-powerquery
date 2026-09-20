// fnCsoTable — one CSO PxStat table (matrix) -> flat table, as published
//
// Query name in Excel: fnCsoTable        Load: Connection only
//
// Arguments
//   matrix : PxStat table code, e.g. "BHQ13", "EHQ03", "WPM39"
//
// Returns the CSV exactly as PxStat serves it (STATISTIC, the period code and label, one
// code+label pair per classification, UNIT, VALUE), with VALUE typed as a number and a
// Date column added from the period.
//
// Deliberately not reshaped here. Every PxStat table carries a different set of
// classifications, so a function that forced one shape would have to guess which ones
// matter. Select and filter in the query that uses this one.
//
// Two things to know before summing anything from PxStat:
//   * aggregate rows sit in the same column as detail rows, unlabelled ("State",
//     "All NACE", "All types of construction", "All employees"). Summing without
//     excluding them double counts;
//   * a value marked preliminary will be revised. Keep what you published, or expect
//     last quarter's number to change under you.
//
// Note: a query that returns a table of nested tables (one row per matrix) makes Excel
// download every one of them just to render the preview. A function has no preview,
// so invoking it costs one download.

let
  fn = (matrix as text) as table =>
    let
      Response = Web.Contents("https://ws.cso.ie",
        [ RelativePath = "public/api.restful/PxStat.Data.Cube_API.ReadDataset/"
                         & matrix & "/CSV/1.0/en",
          Headers = [ Accept = "text/csv" ] ]),

      Raw   = Csv.Document(Response, [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
      Head  = Table.PromoteHeaders(Raw, [PromoteAllScalars = true]),
      Cols  = Table.ColumnNames(Head),
      Check = if List.Contains(Cols, "VALUE") then Head
              else error Error.Record(
                "Unexpected PxStat response",
                "No VALUE column for matrix " & matrix & ".",
                "Columns returned: " & Text.Combine(Cols, ", ")),

      // The period column is named after the time dimension: "Quarter", "Month", "Year".
      PeriodCol = List.First(List.Select({"Quarter", "Month", "Year"},
                    each List.Contains(Cols, _)), null),

      // "2018Q1" -> 2018-01-01 ; "2026M07" -> 2026-07-01 ; "2024" -> 2024-01-01
      ToDate = (p as text) as nullable date =>
        let
          T = Text.Trim(p),
          Y = try Number.FromText(Text.Start(T, 4)) otherwise null,
          M = if Y = null then null
              else if Text.Contains(T, "Q") then (Number.FromText(Text.End(T, 1)) - 1) * 3 + 1
              else if Text.Contains(T, "M") then Number.FromText(Text.End(T, 2))
              else 1
        in
          if Y = null then null else #date(Y, M, 1),

      Dated = if PeriodCol = null then Table.AddColumn(Check, "Date", each null, type date)
              else Table.AddColumn(Check, "Date", each ToDate(Record.Field(_, PeriodCol)), type date),
      Typed = Table.TransformColumns(Dated,
                {{"VALUE", each try Number.FromText(_, "en-US") otherwise null, type number}}),
      Ren   = Table.RenameColumns(Typed, {{"VALUE", "Value"}})
    in
      Ren
in
  fn
