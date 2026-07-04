# kuvakameli

Lightroom Classic-to-Immich derivative sync tooling.

The current implementation is a Lightroom Classic SDK plugin that exports JPEG
derivatives from Lightroom Classic into a stable folder tree. Immich should index
that folder as an External Library. RAW files and other archival originals stay
in Lightroom Classic storage.

## Repository layout

- `doc/Design - Lightroom-to-Immich Derivative Sync Plugin.md`: product and
  architecture design.
- `lr-plugin/ImmichDerivativeSync.lrdevplugin`: Lightroom Classic plugin.
- `tests`: pure-Lua tests for plugin logic that can run outside Lightroom.
- `TODO.md`: remaining plugin work and known validation gaps.

## Build and test

Use the Makefile targets:

```sh
make lint
make test
make build
```

`make build` creates `dist/ImmichDerivativeSync.lrplugin.zip`.

`prek run --all-files` is expected for repositories with pre-commit
configuration, but this repository currently has no `prek.toml` or
`.pre-commit-config.yaml`.

## Lightroom install

1. Open Lightroom Classic.
2. Open `File > Plug-in Manager`.
3. Click `Add`.
4. Select `lr-plugin/ImmichDerivativeSync.lrdevplugin`.
5. Configure the output directory and export settings.
6. Run `Library > Plug-in Extras > Sync Derivatives to Folder`.

Point Immich External Library scanning at the configured output directory or at a
synced copy of it.
