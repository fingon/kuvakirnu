# kuvakameli

Bulk JPEG export sync tooling for Lightroom Classic.

The current implementation is a Lightroom Classic SDK plugin that exports
selected JPEG derivatives from Lightroom Classic into a stable folder tree. RAW
files and other archival originals stay in Lightroom Classic storage.

## Repository layout

- `doc/Design - Bulk JPEG Sync Lightroom Plugin.md`: product and
  architecture design.
- `lr-plugin/BulkJpegSync.lrdevplugin`: Lightroom Classic plugin.
- `tests`: pure-Lua tests for plugin logic that can run outside Lightroom.
- `TODO.md`: remaining plugin work and known validation gaps.

## Build and test

Use the Makefile targets:

```sh
make lint
make test
make build
```

`make build` creates `dist/BulkJpegSync.lrplugin.zip`.

Run `prek run --all-files` for the repository pre-commit checks.

## Lightroom install

1. Open Lightroom Classic.
2. Open `File > Plug-in Manager`.
3. Click `Add`.
4. Select `lr-plugin/BulkJpegSync.lrdevplugin`.
5. Configure the output directory and export settings.
6. Run `Library > Plug-in Extras > Sync JPEGs to Folder`.

Point a downstream tool, gallery, file sync, or photo service at the configured
output directory or at a synced copy of it.
