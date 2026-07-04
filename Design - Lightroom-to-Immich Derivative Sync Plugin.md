---
date created: 2026-07-04T16:59:21+03:00
date modified: 2026-07-04T17:05:34+03:00
---

# Design - Lightroom-to-Immich Derivative Sync Plugin

## Goal

Maintain an automatically updated, storage-efficient, browseable Immich library for photos whose originals and edits live in Lightroom Classic.

The plugin does not sync RAW files to Immich. Instead, it exports rendered JPEG derivatives from Lightroom into a folder tree that Immich indexes as an External Library.

## Core idea

Lightroom remains the authority for:

- RAW originals (camera, phone)
- Develop edits
- Historical edits
- Ratings and keywords, if desired

Immich remains the authority for:

- phone uploads (which might not be of full quality)
- browsing
- sharing
- face recognition
- search
- albums


The plugin bridges them by maintaining a rendered derivative cache.

```text
Camera/Phone RAWs
    ↓
Lightroom Classic
    ↓
Auto-exported JPEG derivatives
    ↓
Synced/shared folder
    ↓
Immich External Library
```

## Main requirements

1. Export Lightroom-rendered JPEGs for selected photos.
    
2. Detect photos changed in Lightroom and regenerate derivatives.
    
3. Avoid copying RAWs to the Immich server.
    
4. Preserve visible Lightroom edits in Immich.
    
5. Require minimal manual workflow.
    
6. Support large catalogs incrementally.
    
7. Avoid two-way metadata conflicts by default.
    

## Non-goals

- Do not make Immich edit RAW files.
    
- Do not interpret Lightroom Develop settings outside Lightroom.
    
- Do not reverse-engineer Lightroom preview caches.
    
- Do not sync Lightroom virtual copies unless explicitly supported.
    
- Do not perform full bidirectional metadata reconciliation.
    
- Do not replace Lightroom Publish Services unless useful internally.
    

## Architecture

The plugin runs inside Lightroom Classic using the Lightroom SDK.

It maintains a local output directory such as:

```text
/Photos/Immich-Derivatives/
    2024/
        2024-06-12/
            IMG_1234.jpg
    2025/
        2025-09-03/
            IMG_9876.jpg
```

That directory is then exposed to Immich either by:

- Syncthing
    
- rsync
    
- SMB/NFS mount
    
- Docker bind mount
    
- another file sync mechanism
    

Immich indexes the directory as an External Library.

## Export policy

The plugin should support several modes:

### All camera RAWs

Export one derivative for every Lightroom photo matching configured rules.

Useful when the user wants all camera photos visible in Immich.

### Curated only

Export only photos matching criteria such as:

- rating ≥ 3 stars
    
- not rejected
    
- has keyword `Immich`
    
- belongs to selected collections
    
- date range
    
- camera source folder
    

Useful when Immich storage is limited.

### Edited only

Export only photos with Develop adjustments or existing historical edits.

Useful for preserving Lightroom edits in Immich without publishing everything.

## Change detection

The plugin should track whether a Lightroom photo needs derivative refresh.

Possible signals:

- Develop settings changed
    
- crop changed
    
- metadata changed
    
- rating changed
    
- keyword changed
    
- file path changed
    
- export preset changed
    
- derivative file missing
    
- derivative file older than last Lightroom change timestamp
    

The plugin maintains its own sync state, for example:

```text
photo_uuid
source_path
last_export_time
last_known_edit_time
output_path
export_hash
status
```

State can be stored in:

- Lightroom custom metadata fields
    
- plugin preferences
    
- a local SQLite database
    
- sidecar manifest files
    

A local SQLite database is probably the cleanest choice.

## Export format

Initial recommended format:

- JPEG
    
- long edge: 2560–3840 px
    
- quality: 85–90
    
- sRGB
    
- include metadata
    
- preserve capture time
    
- preserve GPS
    
- preserve keywords and rating
    
- filename based on original filename plus Lightroom photo ID or hash
    

Example:

```text
IMG_1234__lr-ABCD1234.jpg
```

Using a stable Lightroom identifier avoids collisions when different folders contain identical filenames.

## Metadata handling

By default, metadata should be one-way:

```text
Lightroom → exported JPEG → Immich
```

Recommended metadata included in exports:

- capture timestamp
    
- camera metadata
    
- GPS
    
- title/caption
    
- star rating
    
- hierarchical keywords where possible
    

The plugin should not attempt to pull Immich edits back into Lightroom by default.

If bidirectional metadata sync is ever added, it should be explicit and field-limited.

## Deletion policy

The plugin should support configurable behavior when a source photo no longer matches export rules.

Options:

1. Leave derivative in place.
    
2. Move derivative to trash/archive folder.
    
3. Delete derivative.
    
4. Mark derivative as orphaned in manifest.
    

Default should be conservative: move to an archive/trash folder rather than delete immediately.

## Virtual copies

Virtual copies need special handling because they may share the same source RAW.

Recommended behavior:

- Treat each virtual copy as a separate derivative.
    
- Include copy name or Lightroom copy ID in filename.
    
- Export each copy independently if it matches rules.
    

Example:

```text
IMG_1234__lr-master.jpg
IMG_1234__lr-copy-2.jpg
```

## Immich integration

Minimum viable version does not need to call the Immich API.

It only needs to maintain files in a folder that Immich scans as an External Library.

Optional future Immich API integration could:

- trigger library scans
    
- create albums
    
- upload assets directly
    
- map Lightroom collections to Immich albums
    
- detect existing Immich assets
    
- avoid duplicate phone/camera imports
    

## Duplicate handling

The plugin should avoid creating duplicates where possible, but Immich will still see exported derivatives as separate image assets.

Potential mitigation:

- use a dedicated External Library called `Lightroom Derivatives`
    
- include source metadata in exported files
    
- optionally add a keyword such as `Source/Lightroom`
    
- use predictable filenames
    
- do not mix derivatives into phone-upload storage
    

## User interface

A Lightroom plugin settings panel should allow configuration of:

- output directory
    
- export preset
    
- export mode
    
- rating threshold
    
- keyword filter
    
- source folders
    
- whether to include virtual copies
    
- deletion behavior
    
- sync interval
    
- manual “sync now”
    
- dry-run mode
    
- log viewer
    

## Background operation

The plugin should run an incremental background task while Lightroom is open.

Suggested behavior:

- scan catalog periodically
    
- identify changed/missing derivatives
    
- export in small batches
    
- avoid blocking Lightroom UI
    
- pause while user is actively editing, if needed
    
- resume after restart
    

For very large catalogs, the first run should be resumable and throttled.

## Failure handling

The plugin should handle:

- missing RAW originals
    
- offline disks
    
- export failures
    
- filename collisions
    
- output directory unavailable
    
- Immich sync folder unavailable
    
- Lightroom shutdown during export
    

Failures should be logged and retried later.

## MVP

A practical first version could be:

1. Lightroom menu item: `Sync Derivatives to Folder`.
    
2. User selects output folder and export size/quality.
    
3. Plugin exports all photos rated ≥ N stars.
    
4. Plugin stores last export timestamp in local state.
    
5. Re-running only exports missing or changed derivatives.
    
6. Immich indexes that folder as an External Library.
    

No Immich API required.

## Later enhancements

- true background sync
    
- collection-to-folder mapping
    
- Lightroom collection-to-Immich album sync
    
- smart collection support
    
- edited-only export mode
    
- virtual copy support
    
- orphan cleanup UI
    
- Immich API scan trigger
    
- bidirectional star/keyword sync
    
- AVIF/WebP output
    
- face/person metadata experiments
    
- Docker-side helper service
    
- command-line companion for server-side sync
    

## Recommended default workflow

1. Phone photos upload directly to Immich.
    
2. Camera RAWs import only into Lightroom.
    
3. Lightroom plugin exports selected rendered JPEG derivatives.
    
4. Syncthing or rsync mirrors derivatives to the Immich server.
    
5. Immich indexes the derivative folder as an External Library.
    
6. Lightroom remains the master for camera edits.
    
7. Immich remains the daily browsing and sharing interface.
