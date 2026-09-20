// fnBoeSeries — one Bank of England IADB series -> tidy long table
//
// Query name in Excel: fnBoeSeries        Load: Connection only
//
// Arguments
//   code       : IADB series code, e.g. "IUDBEDR" (Bank Rate), "IUDSOIA" (SONIA)
//   seriesName : optional label for the Series column; defaults to the code
//   dateFrom   : optional "dd/MMM/yyyy"; defaults to "01/Jan/2015"
//
// Returns: Date (date) | Period (text, as published) | Series (text) | Value (number)
//
// The IADB returns CSV from a query string; there is no key and no registration.
// Dates arrive as "17 Sep 2026". They are parsed here by mapping the month name, not by
// Date.From: on a machine whose locale is not English, Date.From either fails or - worse -
// silently reads a different date.

let
  fn = (code as text, optional seriesName as text, optional dateFrom as text) as table =>
    let
      From  = if dateFrom = null then "01/Jan/2015" else dateFrom,
      Label = if seriesName = null then code else seriesName,

      Response = Web.Contents(
        "https://www.bankofengland.co.uk",
        [ RelativePath = "boeapps/database/_iadb-fromshowcolumns.asp",
          Query = [ #"csv.x"    = "yes",
                    Datefrom    = From,
                    Dateto      = "01/Jan/2035",   // far future = "everything published"
                    SeriesCodes = code,
                    CSVF        = "TN",            // T = dates down the rows, N = codes as headers
                    UsingCodes  = "Y",
                    VPD         = "Y",
                    VFD         = "N" ] ]),

      Raw   = Csv.Document(Response, [Delimiter = ",", Encoding = 1252, QuoteStyle = QuoteStyle.Csv]),
      Head  = Table.PromoteHeaders(Raw, [PromoteAllScalars = true]),
      Cols  = Table.ColumnNames(Head),
      Check = if List.Count(Cols) >= 2 then Head
              else error Error.Record(
                "Unexpected IADB response",
                "Fewer than two columns returned for " & code & ".",
                "A wrong series code returns a page, not a CSV. Check the code on the IADB site."),
      Ren   = Table.RenameColumns(Check, {{Cols{0}, "Period"}, {Cols{1}, "Raw"}}),

      Months = ["Jan" = 1, "Feb" = 2, "Mar" = 3, "Apr" = 4, "May" = 5, "Jun" = 6,
                "Jul" = 7, "Aug" = 8, "Sep" = 9, "Oct" = 10, "Nov" = 11, "Dec" = 12],
      ToDate = (period as text) as nullable date =>
        let
          Parts = Text.Split(Text.Trim(period), " "),
          Ok    = List.Count(Parts) = 3 and Record.HasFields(Months, Text.Start(Parts{1}, 3))
        in
          if Ok
          then #date(Number.FromText(Parts{2}),
                     Record.Field(Months, Text.Start(Parts{1}, 3)),
                     Number.FromText(Parts{0}))
          else null,

      Dated  = Table.AddColumn(Ren, "Date", each ToDate([Period]), type date),
      Valued = Table.AddColumn(Dated, "Value",
                 each try Number.FromText([Raw], "en-GB") otherwise null, type number),
      Named  = Table.AddColumn(Valued, "Series", each Label, type text),
      Out    = Table.SelectColumns(Named, {"Date", "Period", "Series", "Value"}),
      Clean  = Table.SelectRows(Out, each [Date] <> null and [Value] <> null),
      Sorted = Table.Sort(Clean, {{"Date", Order.Ascending}})
    in
      Sorted
in
  fn
