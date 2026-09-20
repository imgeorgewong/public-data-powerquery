// example_dbt_materials — the newest DBT building-materials tables workbook, as a table
//
// Query name in Excel: DBT_Materials        Load: Load to Table
// Depends on: fnGovUkLatestAttachment
//
// What it does: finds the current release in the GOV.UK collection, downloads the .xlsx
// attachment whose title contains "tables", and returns the sheet named "2" as published.
//
// Reshaping is left to the caller because the layout of that sheet is the publisher's, not
// ours: it changes occasionally, and a rigid parser turns a layout change into wrong
// numbers instead of an error. Locate columns by header text, never by position.
//
// Each release holds only the last 13 months. For a longer history, call
// fnGovUkLatestAttachment for older releases too (their base_path is in links.documents)
// and stack the vintages - otherwise months silently drop out of the series each year.

let
  Latest = fnGovUkLatestAttachment(
             "/government/collections/building-materials-and-components-monthly-statistics-2012",
             "xlsx", "tables"),
  File   = Excel.Workbook(Web.Contents(Latest[Url]), null, true),
  Sheet  = try File{[Item = "2", Kind = "Sheet"]}[Data] otherwise
           error Error.Record(
             "Sheet 2 not found",
             "The workbook at " & Latest[Url] & " has no sheet named ""2"".",
             "Sheets present: " & Text.Combine(File[Item], ", ")),
  Tagged = Table.AddColumn(Sheet, "SourceRelease", each Latest[ReleaseTitle], type text),
  Dated  = Table.AddColumn(Tagged, "RetrievedAt", each DateTime.FixedLocalNow(), type datetime)
in
  Dated
