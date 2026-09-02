# Metadata report schema v1

`ukigumu-squeeze-metadata.json` is a UTF-8 JSON object with these top-level keys:

- `schemaVersion`: integer, currently `1`
- `applicationVersion`: semantic version string
- `date`: ISO-8601 timestamp
- `quality`: number from 0 through 1
- `selectedFormat`: `original`, `webp`, `jpeg`, `png`, `avif`, `heic`, or `tiff`
- `metadataPolicy`: `preserve-compatible` or `remove`
- `usesDestination`: boolean
- `summary`: total/status counts and byte totals
- `images`: records ordered by `originalRelativePath`

Image records contain relative paths, names, formats, dimensions, byte counts,
metadata availability, final status, and an optional error. Computed savings are
derived from `originalBytes - finalBytes`; negative values represent growth.
Absolute paths and user names are never serialized.
