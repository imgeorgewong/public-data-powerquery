// example_rates — several ECB series in one tidy long table
//
// Query name in Excel: ECB_Rates          Load: Load to Table
// Depends on: fnEcbSeries, fnMonthlyFromDaily
//
// Adding a series is one more line in Daily or Monthly - not a new column, not a new sheet.

let
  Daily = Table.Combine({
    fnEcbSeries("FM",  "D.U2.EUR.4F.KR.MRR_FR.LEV",        "MRO policy rate"),
    fnEcbSeries("FM",  "D.U2.EUR.4F.KR.DFR.LEV",           "Deposit facility rate"),
    fnEcbSeries("EST", "B.EU000A2X2A25.WT",                "EUR short-term rate")
  }),
  DailyMonthly = fnMonthlyFromDaily(Daily, "last"),

  Monthly = Table.Combine({
    fnEcbSeries("FM",  "M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA",  "Euribor 3M (monthly average)"),
    fnEcbSeries("MIR", "M.U2.B.A2I.AM.R.A.2240.EUR.N",     "Euro area NFC lending rate"),
    fnEcbSeries("MIR", "M.IE.B.A2I.AM.R.A.2240.EUR.N",     "Ireland NFC lending rate")
  }),
  MonthlyShaped = Table.SelectColumns(
    Table.AddColumn(
      Table.AddColumn(
        Table.AddColumn(Monthly, "Month", each Date.EndOfMonth([Date]), type date),
        "AsOf", each null, type date),
      "ObsCount", each 1, Int64.Type),
    {"Month", "Series", "Value", "AsOf", "ObsCount"}),

  All    = Table.Combine({DailyMonthly, MonthlyShaped}),
  Sorted = Table.Sort(All, {{"Series", Order.Ascending}, {"Month", Order.Ascending}})
in
  Sorted
