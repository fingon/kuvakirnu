# Immich Derivative Sync Lightroom Plugin

This directory contains a Lightroom Classic SDK plugin that exports stable JPEG
derivatives for Immich External Libraries.

The plugin is intentionally folder-based. It does not call the Immich API and it
does not upload files into Immich storage. Immich should index the derivative
folder as an External Library.

## Install

1. Open Lightroom Classic.
2. Go to `File > Plug-in Manager`.
3. Click `Add`.
4. Select `lr-plugin/ImmichDerivativeSync.lrdevplugin`.
5. Configure the plugin in the Plug-in Manager.

## Use

Run `Library > Plug-in Extras > Sync Derivatives to Folder`.

The plugin exports matching photos into the configured output directory. Point
an Immich External Library at that directory or at a synced copy of it.

## Current behavior

- Exports one JPEG derivative per matching catalog photo.
- Includes starred photos at or above the selected star threshold.
- Can include unstarred photos independently from the star threshold.
- Can include virtual copies when enabled.
- Skips rejected photos.
- Writes derivatives under `YYYY/YYYY-MM-DD/`.
- Uses stable filenames shaped like `IMG_1234__lr-<lightroom-id>.jpg`.
- Uses filenames shaped like
  `IMG_1234__copy-BlackWhite__lr-<lightroom-id>.jpg` for virtual copies when
  Lightroom exposes a copy name.
- Reuses the recorded output path for already-seen photos so Immich asset paths
  remain stable.
- Stores sync state in a plugin-owned Lua manifest file.
- Marks photos as orphaned in state when they stop matching rules, but leaves
  derivative files in place.
- Prevents concurrent manual sync runs while a run is already active.

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

If Lightroom reports `Could not load toolkit script`, quit Lightroom Classic
completely and reopen it after changing plugin files. Lightroom can cache plugin
script layout between reloads.

If settings appear blank after upgrading from an older development build, reopen
the Plug-in Manager page. The plugin normalizes blank persisted values back to
its defaults when the settings page loads.

Settings are stored in Lightroom plugin preferences. If a setting does not
survive closing and reopening the Plug-in Manager, that is a bug in the settings
sync layer rather than expected behavior.

The plugin keeps its Lua modules as root-level toolkit scripts with names such
as `ImmichDerivativeSyncConfig.lua`. Do not move them into a subdirectory unless
the Lightroom loader setup is changed at the same time.

## Known MVP limits

- No Immich API integration.
- No background interval sync.
- No video or Live Photo support.
- No automatic cleanup of temporary mobile uploads.
- No bidirectional metadata sync.
- No UI for reviewing or deleting orphaned derivatives.
