# Bulk JPEG Sync Lightroom Plugin

This directory contains a Lightroom Classic SDK plugin that exports stable JPEG
derivatives for filesystems, galleries, sync tools, and external photo
libraries.

The plugin is intentionally folder-based. It does not call any photo service API
and it does not upload files into managed storage. Point downstream tooling at
the exported JPEG folder.

## Install

1. Open Lightroom Classic.
2. Go to `File > Plug-in Manager`.
3. Click `Add`.
4. Select `lr-plugin/BulkJpegSync.lrdevplugin`.
5. Configure the plugin in the Plug-in Manager.

## Use

Run `Library > Plug-in Extras > Sync JPEGs to Folder`.

The same command is also available from `File > Plug-in Extras` and as `Sync
Now` in the plugin settings panel. The plugin exports matching photos into the
configured output directory.

Use `Sync Changes` in the plugin settings panel for a faster incremental sync.
It exports recent Lightroom edits after the previous successful sync, ignoring
edits from the last five minutes so Lightroom has time to settle metadata. It
does not delete derivatives for removed files or photos that stopped matching;
use `Sync Now` for cleanup.

Sync shows Lightroom progress captions while loading state, searching the
catalog, planning JPEGs, deleting orphaned files, exporting, and saving state.
Canceling the progress dialog stops before later phases when possible.

## Current behavior

- Exports one JPEG derivative per matching catalog photo.
- Includes starred photos at or above the selected star threshold.
- Can include unstarred photos independently from the star threshold.
- Can include virtual copies when enabled.
- Skips rejected photos.
- Queries Lightroom for matching rating candidates instead of scanning the full
  catalog.
- Writes derivatives under `YYYY/YYYY-MM-DD/`.
- Treats JPEG long edge as a maximum and does not enlarge smaller originals.
- Uses stable filenames shaped like `IMG_1234__lr-<lightroom-id>.jpg`.
- Uses filenames shaped like
  `IMG_1234__copy-BlackWhite__lr-<lightroom-id>.jpg` for virtual copies when
  Lightroom exposes a copy name.
- Reuses the recorded output path for already-seen photos so downstream asset
  paths remain stable.
- Stores sync state in a plugin-owned Lua manifest file.
- Exports Lightroom metadata into JPEGs, including hierarchical keywords and
  location metadata when Lightroom provides them.
- Deletes derivative files and marks state records orphaned when photos stop
  matching the configured rules.
- Shows compact last-run status in the Plug-in Manager and stores a full
  diagnostic string in plugin preferences and the Lightroom plugin log.
- Prevents concurrent manual sync runs while a run is already active.
- Can run background sync every hour or every day. The default is never.
- Background hourly sync exports recent changes and performs at most one full
  cleanup pass per day. Background daily sync performs a full cleanup pass.

## Settings

Configure the plugin in Lightroom Classic Plug-in Manager:

- Output folder.
- `Include unstarred` button, default off.
- Clickable fixed-title star threshold buttons from one through five stars,
  default `3+`; clicking the selected threshold again clears starred-photo
  selection. The selected state is shown in a summary line.
- Virtual copy inclusion toggle, default off.
- JPEG long edge, default `3200`.
- JPEG quality, default `85`.
- Background sync interval, default `Never`.
- `Sync Now`, enabled when an output folder and at least one rating selection
  are configured. This is the full cleanup sync.
- `Sync Changes`, enabled with the same configuration. This is incremental and
  does not detect deletions.

## Development

From the repository root:

```sh
make lint
make test
make build
```

The local tests cover pure Lua planning, path, manifest, and configuration
behavior. Lightroom export behavior still needs manual validation inside
Lightroom Classic.

## Troubleshooting

See [LIGHTROOM_GOTCHAS.md](LIGHTROOM_GOTCHAS.md) for Lightroom Classic SDK
runtime notes, including toolkit script loading, settings persistence, yielding,
and filesystem limitations.

To inspect metadata in an exported JPEG, run:

```sh
exiftool -Rating -Subject -HierarchicalSubject -GPSLatitude -GPSLongitude exported.jpg
```

For lower-resolution originals, confirm the exported image dimensions do not
exceed the source dimensions; the configured long edge is an upper bound.

## Known MVP limits

- No video or Live Photo support.
- No bidirectional metadata sync.
- No orphan review UI before automatic deletion.
