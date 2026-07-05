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

## MVP hardening

- Make state writes safe if Lightroom exits during a long run.
- Add a visible error/status viewer instead of relying on the Lightroom log and
  manifest file.
- Add a dry-run command that reports planned exports and orphans without writing
  derivatives.
- Add a user-facing way to locate the manifest file.
- Add tests for failed export state transitions.
- Add tests for output path collisions.
- Add tests for photos without capture dates or source filenames.
- Add tests for Lightroom-specific settings control behavior after SDK runtime
  validation.

## Feature backlog

- Background interval sync while Lightroom Classic is open.
- Configurable export modes beyond rating threshold:
  - all catalog photos matching rules
  - keyword-based curated exports
  - edited-only exports
  - source-folder and date-range filters
- Option to use smart collection filter with OR logic vs. the current union with star rating.
- Support for regular (non-smart) collections.
- Orphan review UI with archive, delete, and keep actions.
- Video derivative support.
- Live Photo pairing support.
- Optional WebP or AVIF derivative formats if Lightroom export support and
  downstream tooling behavior make them practical.
