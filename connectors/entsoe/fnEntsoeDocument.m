// fnEntsoeDocument — one ENTSO-E Transparency Platform document -> XML table
//
// Query name in Excel: fnEntsoeDocument      Load: Connection only
//
// Arguments
//   token        : security token (see the README - it is free, but it is a credential)
//   params       : record of query parameters for this document type, e.g.
//                  [ documentType = "A44", in_Domain = "10Y1001A1001A59C",
//                    out_Domain = "10Y1001A1001A59C" ]
//   periodStart  : "yyyyMMddHHmm" (UTC), e.g. "202601010000"
//   periodEnd    : "yyyyMMddHHmm" (UTC)
//
// Returns the parsed XML as a table of TimeSeries records, unflattened: each document type
// nests differently, so flattening belongs in the query that knows which one it asked for.
//
// Notes that cost time to learn the hard way:
//   * the token is a credential. Pass it in from a parameter or a workbook cell; never
//     type it into a query that gets shared, committed or emailed;
//   * A75 (actual generation per type) is capped at ONE MONTH per request, while A44
//     (day-ahead prices) accepts a year. Asking A75 for a year returns nothing useful;
//   * A65 (load) is published by bidding zone and A75 by control area. For some markets
//     these are different geographies, so figures derived across the two - net imports,
//     for example - are not real numbers;
//   * recent periods are revised for a week or two. Freeze the settled history and fetch
//     only a rolling live window;
//   * a large response comes back as a ZIP rather than XML. If Xml.Tables throws on a
//     wide period, shorten the period rather than fighting the parser.

let
  fn = (token as text, params as record, periodStart as text, periodEnd as text) as table =>
    let
      Query = Record.Combine({
                params,
                [ securityToken = token, periodStart = periodStart, periodEnd = periodEnd ] }),

      Response = Web.Contents("https://web-api.tp.entsoe.eu",
                   [ RelativePath = "api",
                     Query = Query,
                     ManualStatusHandling = {400, 401, 429, 500, 503} ]),
      Body   = Binary.Buffer(Response),
      Status = Value.Metadata(Response)[Response.Status],

      Checked =
        if Status = 200 then Body
        else if Status = 401 then
          error Error.Record("ENTSO-E rejected the token",
            "HTTP 401", "The token is missing, wrong, or not yet activated.")
        else if Status = 400 then
          error Error.Record("ENTSO-E rejected the request",
            "HTTP 400 - usually an empty period or an unsupported parameter combination.",
            "A 400 can also mean 'no data for this period', which is not the same as a "
              & "dead token. Check a period you know has data before changing the parameters.")
        else
          error Error.Record("ENTSO-E request failed", "HTTP " & Text.From(Status)),

      Doc    = Xml.Tables(Checked),
      Series = try Table.SelectRows(Doc, each [Name] = "TimeSeries") otherwise Doc
    in
      Series
in
  fn
