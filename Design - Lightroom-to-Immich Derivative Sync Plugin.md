# Design - Lightroom Classic-to-Immich Derivative Sync Plugin

## Goal

Maintain an automatically updated, storage-efficient, browseable Immich library for photos whose final originals, edits, ratings, and keywords live in Lightroom Classic.

The plugin does not sync RAW files or other archival originals to Immich. Instead, it exports Lightroom Classic-rendered derivatives into a folder tree that Immich indexes as an External Library.

The intended result is:

- phone media can appear quickly in Immich through mobile upload
- final phone and camera versions live in Lightroom Classic on a high-capacity machine
- lower-weight Lightroom Classic derivatives are actionable across a wide variety of devices in Immich

## Core idea

Lightroom Classic remains the authority for:

- final camera originals
- final phone originals
- Develop edits
- historical edits
- ratings and keywords, if desired

Immich remains the authority for:

- temporary phone ingest through mobile upload
- browsing
- sharing
- face recognition
- search
- albums

The plugin bridges them by maintaining a rendered derivative cache for Immich.

```text
Phone uploads
    |
Temporary Immich ingest
    |
Import originals into Lightroom Classic
    |
Lightroom Classic final versions
    |
Auto-exported JPEG derivatives
    |
Synced/shared folder
    |
Immich External Library
```

Camera originals skip the temporary Immich ingest path and are imported directly into Lightroom Classic.

## Phone ingest lifecycle

Phone uploads are a convenience and ingest mechanism, not the final archive.

1. Phone photos and videos upload directly to Immich for immediate availability.

2. Originals are later imported into Lightroom Classic on the high-capacity machine.

3. Lightroom Classic becomes the final source for phone originals, edits, metadata, and exported derivatives.

4. The plugin exports lower-weight derivatives from Lightroom Classic to the Immich External Library.

5. Temporary Immich mobile uploads are handled according to policy:

   - leave in place
   - tag as temporary/imported
   - move to an archive album
   - hide from normal browsing if Immich supports the desired workflow
   - delete after the Lightroom Classic derivative is verified

The MVP may leave temporary mobile uploads in place. Cleanup requires explicit policy and probably Immich API integration.

## Main requirements

1. Export Lightroom Classic-rendered JPEGs for selected photos.

2. Detect photos changed in Lightroom Classic and regenerate derivatives.

3. Avoid copying RAWs or archival originals to the Immich server.

4. Preserve visible Lightroom Classic edits in Immich.

5. Require minimal manual workflow after initial configuration.

6. Support large catalogs incrementally.

7. Avoid two-way metadata conflicts by default.

8. Keep derivative paths stable after Immich has indexed them.

## Non-goals

- Do not support cloud Lightroom / Lightroom CC.

- Do not make Immich edit RAW files.

- Do not interpret Lightroom Classic Develop settings outside Lightroom Classic.

- Do not reverse-engineer Lightroom Classic preview caches.

- Do not sync Lightroom Classic virtual copies unless explicitly supported.

- Do not perform full bidirectional metadata reconciliation.

- Do not implement automatic Immich mobile upload cleanup in the MVP.

- Do not use Lightroom Classic Publish Services as the default architecture.

## Architecture

The plugin runs inside Lightroom Classic using the Lightroom Classic SDK.

The MVP should be a Lightroom Classic plugin with its own sync state and export worker. It should not be implemented as a Lightroom Classic Publish Service, because Publish Services are better suited to explicit published collections than automatic whole-library derivative maintenance.

Publish Service support can be evaluated later for curated collection workflows only.

The plugin maintains a local output directory such as:

```text
/Photos/Immich-Derivatives/
    2024/
        2024-06-12/
            IMG_1234__lr-ABCD1234.jpg
    2025/
        2025-09-03/
            IMG_9876__lr-EFGH5678.jpg
```

That directory is then exposed to Immich either by:

- Syncthing
- rsync
- SMB/NFS mount
- Docker bind mount
- another file sync mechanism

Immich indexes the directory as an External Library.

## Asset identity and path stability

Derivative output paths and filenames must be stable after first Immich indexing.

Changing a derivative path, filename, or folder layout can cause Immich to treat the file as a different asset. That can lose Immich-side album membership, sharing state, person assignments, or other metadata associated with the previous asset.

The plugin should therefore:

- derive output paths from stable capture metadata and a stable Lightroom Classic identifier
- avoid changing path layout after initial sync
- update existing derivative files in place when possible
- export through a temporary file and rename into place only after export succeeds
- document that changing the output naming scheme is a migration

## Export policy

The plugin should support several modes:

### All camera and phone originals

Export one derivative for every Lightroom Classic photo matching configured rules.

Useful when the user wants final Lightroom Classic versions visible in Immich regardless of source device.

### Curated only

Export only photos matching criteria such as:

- rating >= 3 stars
- not rejected
- has keyword `Immich`
- belongs to selected collections
- date range
- source folder

Useful when Immich storage is limited.

### Edited only

Export only photos with Develop adjustments or existing historical edits.

Useful for preserving Lightroom Classic edits in Immich without publishing everything.

## Change detection

The plugin should track whether a Lightroom Classic photo needs derivative refresh.

Possible signals:

- Develop settings changed
- crop changed
- metadata changed
- rating changed
- keyword changed
- file path changed
- export preset changed
- derivative file missing
- derivative file older than last Lightroom Classic change timestamp

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

- Lightroom Classic custom metadata fields
- plugin preferences
- a local SQLite database
- sidecar manifest files

A local SQLite database is probably the cleanest choice.

## Export format

Initial recommended format:

- JPEG
- long edge: 2560-3200 px
- quality: 82-88
- sRGB
- include metadata
- preserve capture time
- preserve GPS
- preserve keywords and rating
- filename based on original filename plus Lightroom Classic photo ID or hash

Example:

```text
IMG_1234__lr-ABCD1234.jpg
```

Using a stable Lightroom Classic identifier avoids collisions when different folders contain identical filenames.

This output is a browsing, sharing, and actionability target. It is not an archival-quality copy of the original.

## Phone media scope

MVP scope:

- still images imported into Lightroom Classic
- phone JPEG, HEIC, and DNG files if Lightroom Classic can import and export them through the configured export preset
- one exported derivative per Lightroom Classic catalog photo

Out of MVP scope:

- Live Photo motion pairing
- phone videos
- burst grouping
- automatic cleanup of matching Immich mobile uploads

Videos and Live Photos can be added later, but they need separate decisions because they do not map cleanly to a single Lightroom Classic-rendered JPEG derivative.

## Metadata handling

By default, metadata should be one-way:

```text
Lightroom Classic -> exported JPEG -> Immich
```

Recommended metadata included in exports:

- capture timestamp
- camera metadata
- GPS
- title/caption
- star rating
- hierarchical keywords where possible

The plugin should not attempt to pull Immich edits back into Lightroom Classic by default.

If bidirectional metadata sync is ever added, it should be explicit and field-limited.

## Deletion and orphan policy

The plugin should support configurable behavior when a source photo no longer matches export rules.

Options:

1. Leave derivative in place.

2. Mark derivative as orphaned in the manifest.

3. Move derivative to an archive folder outside the Immich External Library path.

4. Delete derivative.

Default should be conservative: mark as orphaned and leave the file in place until reviewed.

Moving or deleting a derivative causes Immich to stop seeing that external asset after a scan. This may remove Immich-side metadata associated with the asset, depending on Immich retention behavior and server settings.

## Virtual copies

Virtual copies need special handling because they may share the same source original.

Recommended behavior:

- Treat each virtual copy as a separate derivative.
- Include copy name or Lightroom Classic copy ID in filename.
- Export each copy independently if it matches rules.

Example:

```text
IMG_1234__lr-master.jpg
IMG_1234__lr-copy-2.jpg
```

Virtual copy support can be deferred until after the MVP.

## Immich integration

Minimum viable version does not need to call the Immich API.

It only needs to maintain files in a folder that Immich scans as an External Library.

Optional future Immich API integration could:

- trigger library scans
- create albums
- map Lightroom Classic collections to Immich albums
- detect existing Immich mobile-upload assets
- tag or archive temporary phone uploads after Lightroom Classic import
- avoid duplicate phone/camera imports where possible

Direct upload of derivatives to Immich is not the preferred architecture while External Libraries satisfy the browsing use case.

## Duplicate handling

Duplicates between Immich mobile uploads and Lightroom Classic derivatives are expected unless reconciled.

Potential mitigation:

- use a dedicated External Library called `Lightroom Classic Derivatives`
- include source metadata in exported files
- optionally add a keyword such as `Source/LightroomClassic`
- use predictable stable filenames
- do not mix derivatives into phone-upload storage
- keep temporary mobile uploads in a separate Immich library or album where possible

The MVP should tolerate duplicates. A later Immich API integration can reconcile temporary mobile uploads with final Lightroom Classic derivatives by tagging, archiving, hiding, or deleting the temporary upload after the derivative has been exported and indexed.

## User interface

A Lightroom Classic plugin settings panel should allow configuration of:

- output directory
- export preset
- export mode
- rating threshold
- keyword filter
- source folders
- whether to include virtual copies
- orphan/deletion behavior
- sync interval
- manual `Sync Now`
- dry-run mode
- log viewer

Long-running actions such as `Sync Now` should show progress and should not allow concurrent sync runs.

## Background operation

The plugin should run an incremental background task while Lightroom Classic is open.

Suggested behavior:

- scan catalog periodically
- identify changed/missing derivatives
- export in small batches
- avoid blocking Lightroom Classic UI
- pause while user is actively editing, if needed
- resume after restart

For very large catalogs, the first run should be resumable and throttled.

## Failure handling

The plugin should handle:

- missing originals
- offline disks
- export failures
- filename collisions
- output directory unavailable
- Immich sync folder unavailable
- Lightroom Classic shutdown during export
- failed temporary-file rename

Failures should be logged visibly and retried later. Expected user-actionable failures should be shown in the plugin UI.

## MVP

A practical first version could be:

1. Lightroom Classic menu item: `Sync Derivatives to Folder`.

2. User selects output folder and export size/quality.

3. Plugin exports all photos rated >= N stars.

4. Plugin stores last export timestamp and output path in local state.

5. Re-running only exports missing or changed derivatives.

6. Export writes to a temporary file and renames into the stable output path after success.

7. Immich indexes that folder as an External Library.

No Immich API required.

## Later enhancements

- true background sync
- collection-to-folder mapping
- Lightroom Classic collection-to-Immich album sync
- smart collection support
- edited-only export mode
- virtual copy support
- orphan cleanup UI
- Immich API scan trigger
- temporary mobile upload reconciliation
- bidirectional star/keyword sync
- AVIF/WebP output
- video derivative support
- Live Photo handling
- face/person metadata experiments
- Docker-side helper service
- command-line companion for server-side sync

## Recommended default workflow

1. Phone photos upload directly to Immich for temporary mobile ingest.

2. Phone originals are imported into Lightroom Classic on the high-capacity machine.

3. Camera originals import only into Lightroom Classic.

4. Lightroom Classic plugin exports selected rendered JPEG derivatives.

5. Syncthing or rsync mirrors derivatives to the Immich server.

6. Immich indexes the derivative folder as an External Library.

7. Lightroom Classic remains the master for final phone and camera versions.

8. Immich remains the daily browsing, sharing, search, and recognition interface over temporary uploads plus final derivatives.
