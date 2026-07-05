# Done

These manual steps have been done (moved in from TODO). Note that they
may break at some point in the future - if that happens, open an
issue.

- Validate the plugin in Lightroom Classic on macOS.
- Confirm `Info.lua` metadata and menu registration load without SDK warnings.
- Confirm the root-level toolkit script layout fixes `Could not load toolkit
  script` errors after a full Lightroom restart.
- Confirm the Plug-in Manager settings panel persists values correctly.
- Confirm changed settings survive closing and reopening the Plug-in Manager and
  restarting Lightroom Classic.
- Confirm `Sync Now` is enabled and disabled based on output folder and rating
  selection state.
- Confirm sync command appears under both Library and File Plug-in Extras after
  plugin reload or Lightroom restart.
- Confirm the output folder setting is picker-only and cannot be edited as
  arbitrary text.
- Confirm fixed-title star rating controls select and clear thresholds and
  update the rating summary correctly.
- Confirm the unstarred button and virtual-copy checkbox persist correctly.
- Confirm `catalog:findPhotos()` rating searches and the metadata keys used in
  `Photo.snapshot` return the expected identifiers, capture timestamps, ratings,
  rejected state, and virtual-copy state.
- Confirm Lightroom export settings produce JPEGs with intended dimensions,
  quality, color space, and embedded metadata.
- Confirm exported rendition paths returned by Lightroom are moved into the
  stable derivative path correctly.
- Confirm re-running a sync skips unchanged files and replaces changed
  derivatives in place.
