// fnMonthlyFromDaily — collapse a daily/business-daily series to one row per month
//
// Query name in Excel: fnMonthlyFromDaily     Load: Connection only
//
// Arguments
//   source : a table from fnEcbSeries (Date | Period | Series | Value)
//   method : "last" (last observation in the month) or "avg" (mean of the month)
//
// Returns: Month (date, last calendar day) | Series | Value | AsOf (date of the value
//          used, null for "avg") | ObsCount (observations behind the month)
//
// Keep AsOf and ObsCount. A month is published as soon as it starts, so the newest row of
// a "last" series can be one observation into the month; without AsOf nothing on the sheet
// says so. ObsCount is the cheap check that a month is not built from two stray days.
//
// Note on ECB daily series: FM daily series are published for every calendar day (weekends
// carry the previous value forward), while EXR reference rates exist only on TARGET working
// days. Month-end therefore means a different thing in each, which matters when the two sit
// in the same monthly table.

let
  fn = (source as table, method as text) as table =>
    let
      Valid = if List.Contains({"last", "avg"}, method) then method
              else error Error.Record(
                "Unknown method",
                "method must be ""last"" or ""avg"", got: " & method),
      Added = Table.AddColumn(source, "Month", each Date.EndOfMonth([Date]), type date),
      Grp   = Table.Group(Added, {"Series", "Month"}, {
                {"Value", each if Valid = "avg"
                               then List.Average([Value])
                               else List.Last(Table.Sort(_, {{"Date", Order.Ascending}})[Value]),
                 type number},
                {"AsOf", each if Valid = "avg" then null else List.Max([Date]), type date},
                {"ObsCount", each Table.RowCount(_), Int64.Type}
              }),
      Out   = Table.SelectColumns(Grp, {"Month", "Series", "Value", "AsOf", "ObsCount"}),
      Sorted = Table.Sort(Out, {{"Series", Order.Ascending}, {"Month", Order.Ascending}})
    in
      Sorted
in
  fn
