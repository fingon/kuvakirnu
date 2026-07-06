# TODO

Remaining work for the Lightroom Classic-to-Bulk JPEG sync plugin.

See `lr-plugin/LIGHTROOM_GOTCHAS.md` for Lightroom SDK behavior discovered while
building this plugin.

## Known issues

- LrExportSession has no API to suppress its progress dialog. Exports grouped by
  date cause the dialog to flash between date groups. Tracked in
  `LIGHTROOM_GOTCHAS.md`.

## Feature backlog

- Option to use smart collection filter with OR logic vs. the current union with star rating.

- Support for regular (non-smart) collections.
