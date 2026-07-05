# TODO

Remaining work for the Lightroom Classic-to-Immich derivative sync plugin.

## Before trusting the plugin with a real catalog

- Validate the plugin in Lightroom Classic on macOS.
- Confirm `Info.lua` metadata and menu registration load without SDK warnings.
- Confirm the root-level toolkit script layout fixes `Could not load toolkit
  script` errors after a full Lightroom restart.
- Confirm the Plug-in Manager settings panel persists values correctly.
- Confirm `catalog:getAllPhotos()` and the metadata keys used in
  `Photo.snapshot` return the expected identifiers, capture timestamps, ratings,
  rejected state, and virtual-copy state.
- Confirm Lightroom export settings produce JPEGs with intended dimensions,
  quality, color space, and embedded metadata.
- Confirm exported rendition paths returned by Lightroom are moved into the
  stable derivative path correctly.
- Confirm re-running a sync skips unchanged files and replaces changed
  derivatives in place.
- Confirm failures for offline originals, missing output directories, and export
  errors are visible to the user and recorded in state.

## MVP hardening

- Replace per-photo export sessions with batched export sessions once Lightroom
  runtime behavior is confirmed.
- Make state writes safe if Lightroom exits during a long run.
- Add a visible error/status viewer instead of relying on the Lightroom log and
  manifest file.
- Add a dry-run command that reports planned exports and orphans without writing
  derivatives.
- Add a user-facing way to locate the manifest file.
- Add tests for failed export state transitions.
- Add tests for output path collisions.
- Add tests for photos without capture dates or source filenames.
- Add repository pre-commit configuration so `prek run --all-files` is useful.

## Feature backlog

- Background interval sync while Lightroom Classic is open.
- Configurable export modes beyond rating threshold:
  - all catalog photos matching rules
  - keyword-based curated exports
  - collection-based curated exports
  - edited-only exports
  - source-folder and date-range filters
- Virtual copy support with stable copy-specific filenames.
- Orphan review UI with archive, delete, and keep actions.
- Immich API integration to trigger External Library scans.
- Optional Lightroom collection to Immich album mapping.
- Temporary Immich mobile-upload reconciliation after derivatives are verified.
- Video derivative support.
- Live Photo pairing support.
- Optional WebP or AVIF derivative formats if Lightroom export support and
  Immich behavior make them practical.
