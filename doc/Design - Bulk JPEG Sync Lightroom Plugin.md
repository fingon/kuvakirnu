# Design - Bulk JPEG Sync Lightroom Plugin

## Goal

Maintain an automatically updated folder of Lightroom Classic-rendered JPEGs for
selected catalog photos. Lightroom Classic remains the source of truth for
original files, Develop edits, ratings, and metadata; the output folder is a
derived cache for galleries, file sync tools, backup jobs, and external photo
libraries.

The plugin does not sync RAW files or other archival originals. It exports JPEGs
into a stable folder tree that downstream tools can index or copy.

## Core Behavior

- Query Lightroom Classic for photos matching the configured rating selection.
- Export one JPEG derivative for each matching, non-rejected photo.
- Preserve stable output paths for already-seen photos.
- Re-export missing or changed JPEGs.
- Delete exported JPEGs when the source photo no longer matches configured
  rules, then mark the state record orphaned.
- Store sync state in a plugin-owned Lua manifest file.

The current MVP is intentionally folder-based. It does not call downstream
service APIs or upload files into managed storage.

## Selection Policy

The initial selection controls are:

- star rating threshold
- optional unstarred inclusion
- rejected-photo exclusion
- optional virtual-copy inclusion

Sync uses Lightroom `catalog:findPhotos()` search descriptors for rating
candidate discovery instead of scanning the full catalog. The scanner still
validates each returned candidate defensively before export planning.

Future selection modes can add keyword, collection, date range, source folder,
or edited-only filters.

## Output And State

Derivative paths are stable after first export:

```text
/Photos/Bulk-JPEG-Sync/
    2024/
        2024-06-12/
            IMG_1234__lr-ABCD1234.jpg
```

Changing path layout is a migration because downstream tools may treat renamed
files as different assets.

The state manifest records source path, output path, fingerprint, export
settings version, last export time, status, and last error. State writes use a
temporary file plus backup replacement so a failed save does not silently lose
the previous manifest.

## UI And Diagnostics

The Plug-in Manager panel exposes output folder, rating selection, virtual-copy
inclusion, JPEG size, JPEG quality, manual sync, state file path, and compact
last-run status.

Last-run status is split into short rows:

- timestamp
- candidate/export/skip results
- orphan/delete/failure cleanup counts

The full run diagnostic is persisted in plugin preferences and logged through
the Lightroom plugin logger.

## Implementation Status

Implemented:

- Lightroom Classic SDK plugin scaffold with Plug-in Extras menu items.
- Plugin Manager settings for output folder, rating selection, JPEG long edge,
  JPEG quality, and virtual-copy inclusion.
- Manual `Sync JPEGs to Folder` command.
- `catalog:findPhotos()` candidate querying for rating-based sync.
- Stable JPEG path generation using capture date, original base filename, and
  Lightroom identifier.
- Manifest-file sync state.
- Automatic deletion and orphan marking for no-longer-matching JPEGs.
- Compact last-run UI plus full diagnostic logging.
- Pure-Lua tests for path generation, filtering, catalog query descriptors,
  state handling, file replacement, and change detection planning.
- Makefile targets for linting, testing, and packaging.

Still pending:

- Manual runtime validation inside Lightroom Classic.
- Hardening export behavior against Lightroom SDK edge cases.
- Background sync, richer filtering, orphan review UI, and downstream service
  integrations.

See `TODO.md` for the current implementation backlog.
