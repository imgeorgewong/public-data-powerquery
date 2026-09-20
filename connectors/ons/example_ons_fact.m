// example_ons_fact — a catalogue of ONS series in one tidy long table
//
// Query name in Excel: ONS_Fact          Load: Load to Table
// Depends on: fnOnsTimeseries
//
// Adding a series is one more record in Catalogue. Nothing else changes.
//
// In a workbook you would normally keep Catalogue as an Excel table and read it with
// Excel.CurrentWorkbook, so that adding a series needs no code edit. It is inline here so
// the file stands alone - and note that mixing Excel.CurrentWorkbook with a web source in
// one chain is what triggers Formula.Firewall; keep the catalogue in its own query.

let
  Catalogue = {
    [ Name = "RPI All Items",                 Uri = "/economy/inflationandpriceindices/timeseries/chaw/mm23" ],
    [ Name = "CPI All Items index",           Uri = "/economy/inflationandpriceindices/timeseries/d7bt/mm23" ],
    [ Name = "CPIH annual rate",              Uri = "/economy/inflationandpriceindices/timeseries/l55o/mm23" ],
    [ Name = "PPI input, materials",          Uri = "/economy/inflationandpriceindices/timeseries/ghik/ppi" ],
    [ Name = "PPI output, bricks and tiles",  Uri = "/economy/inflationandpriceindices/timeseries/ew6c/ppi" ]
  },

  Fetched = List.Transform(Catalogue, each fnOnsTimeseries([Uri], [Name])),
  All     = Table.Combine(Fetched),
  Sorted  = Table.Sort(All, {{"Series", Order.Ascending}, {"Date", Order.Ascending}})
in
  Sorted
