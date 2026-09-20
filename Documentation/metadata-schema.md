# Metadata report schema v1

`ukigumu-squeeze-metadata.json` is a UTF-8 JSON object with these top-level keys:

- `schemaVersion`: integer, currently `1`
- `applicationVersion`: semantic version string
- `date`: ISO-8601 timestamp
- `quality`: number from 0 through 1
- `selectedFormat`: `original`, `webp`, `jpeg`, `png`, `avif`, `heic`, `tiff`, `mp4`, or `mov`
- `videoPreset`: `smallerFile`, `fast1080p`, or `highQuality`
- `metadataPolicy`: `preserve-compatible` or `remove`
- `usesDestination`: boolean
- `summary`: total/status counts and byte totals
- `images`: records ordered by `originalRelativePath`

Image and video records contain relative paths, names, formats, dimensions, byte
counts, metadata availability, final status, and an optional error. Photo formats
stay `webp`, `jpeg`, `png`, `avif`, `heic`, and `tiff`. Video formats are `mp4`,
`mov`, `m4v`, `avi`, and `mpeg`. Computed savings are derived from
`originalBytes - finalBytes`; negative values represent growth. Absolute paths
and user names are never serialized.
