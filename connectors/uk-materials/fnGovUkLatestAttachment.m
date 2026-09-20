// fnGovUkLatestAttachment — newest statistical release in a GOV.UK collection -> file URL
//
// Query name in Excel: fnGovUkLatestAttachment      Load: Connection only
//
// Arguments
//   collectionPath : e.g. "/government/collections/building-materials-and-components-monthly-statistics-2012"
//   extension      : file extension to pick, e.g. "xlsx" or "ods"
//   titleContains  : optional text the attachment title must contain, e.g. "tables"
//
// Returns a record: [Url, Title, ReleaseTitle, ReleasePath, PublishedAt]
//
// Why this exists: the file name changes every month ("..._July_2026.xlsx") and carries a
// media hash in the path, so the download URL cannot be built by hand or hard-coded. The
// GOV.UK Content API is the stable part:
//   /api/content/<collection>            -> links.documents  (newest first)
//   /api/content/<document>              -> details.attachments[].url
//
// Each monthly file contains only the last 13 months. Building a long history means
// fetching several vintages, not just the newest one - see example_dbt_materials.m.

let
  fn = (collectionPath as text, extension as text, optional titleContains as text) as record =>
    let
      Path = if Text.StartsWith(collectionPath, "/") then Text.Middle(collectionPath, 1) else collectionPath,

      Collection = Json.Document(Web.Contents("https://www.gov.uk",
                     [ RelativePath = "api/content/" & Path,
                       Headers = [ Accept = "application/json" ] ])),
      Documents  = try Collection[links][documents] otherwise
                   error Error.Record("Unexpected GOV.UK response",
                     "links.documents not found for " & Path),
      Newest     = if List.Count(Documents) = 0
                   then error Error.Record("Empty collection", "No documents in " & Path)
                   else Documents{0},

      DocPath    = Text.Middle(Newest[base_path], 1),
      Document   = Json.Document(Web.Contents("https://www.gov.uk",
                     [ RelativePath = "api/content/" & DocPath,
                       Headers = [ Accept = "application/json" ] ])),
      Attach     = try Document[details][attachments] otherwise
                   error Error.Record("Unexpected GOV.UK response",
                     "details.attachments not found for " & DocPath),

      Wanted = List.Select(Attach, each
                 Text.EndsWith(Text.Lower(Record.FieldOrDefault(_, "url", "")), "." & Text.Lower(extension))
                 and (titleContains = null
                      or Text.Contains(Text.Lower(Record.FieldOrDefault(_, "title", "")),
                                       Text.Lower(titleContains)))),
      Picked = if List.Count(Wanted) = 0
               then error Error.Record(
                 "No matching attachment",
                 "No ." & extension & " attachment"
                   & (if titleContains = null then "" else " whose title contains """ & titleContains & """")
                   & " in " & DocPath,
                 "Attachment titles: "
                   & Text.Combine(List.Transform(Attach, each Record.FieldOrDefault(_, "title", "?")), " | "))
               else Wanted{0}
    in
      [ Url          = Picked[url],
        Title        = Record.FieldOrDefault(Picked, "title", ""),
        ReleaseTitle = Record.FieldOrDefault(Newest, "title", ""),
        ReleasePath  = Newest[base_path],
        PublishedAt  = Record.FieldOrDefault(Newest, "public_updated_at", "") ]
in
  fn
