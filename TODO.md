# TODO

Remaining work for the Lightroom Classic-to-Bulk JPEG sync plugin.

See `lr-plugin/LIGHTROOM_GOTCHAS.md` for Lightroom SDK behavior discovered while
building this plugin.

## Before trusting the plugin with a real catalog

- Confirm sync progress captions appear quickly on large catalogs and canceling
  the progress dialog stops cleanly before export/state save phases.
- Confirm virtual-copy exports get unique filenames for named and unnamed copies.
- Confirm downgraded, rejected, or otherwise no-longer-matching photos have
  derivative files deleted from the output folder.
- Confirm failures for offline originals, missing output directories, and export
  errors are visible to the user and recorded in state.

## Known issues

- LrExportSession has no API to suppress its progress dialog. Exports grouped by
  date cause the dialog to flash between date groups. Tracked in
  `LIGHTROOM_GOTCHAS.md`.

## Feature backlog

- Option to use smart collection filter with OR logic vs. the current union with star rating.
- Support for regular (non-smart) collections.
- Orphan review UI with archive, delete, and keep actions.
- Video derivative support.
- Live Photo pairing support.
- Optional WebP or AVIF derivative formats if Lightroom export support and
  downstream tooling behavior make them practical.
