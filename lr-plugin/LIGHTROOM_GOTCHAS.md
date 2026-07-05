# Lightroom Classic Plug-in Development Gotchas

Notes from building and testing this plugin against Lightroom Classic.

## Toolkit script loading

- Lightroom may cache plugin script layout. After adding, removing, or renaming
  Lua files, fully restart Lightroom Classic or remove/re-add the plugin.
- Keep helper modules as root-level toolkit scripts inside the `.lrdevplugin`
  directory. Dotted module names such as `Plugin.Module` did not load reliably.
- New menu registrations in `Info.lua` may also require plugin reload or
  Lightroom restart before they appear.

## Settings persistence

- The Plug-in Manager settings provider receives a transient property table.
  Values edited there do not automatically persist to `LrPrefs.prefsForPlugin()`.
- Load durable values from `LrPrefs.prefsForPlugin()` into the property table
  when rendering settings.
- Save changed durable settings back to `LrPrefs.prefsForPlugin()` from button
  actions and property observers.
- Keep derived UI fields, such as display labels and status summaries, out of
  persisted preferences.

## Settings controls

- A parent view with `bind_to_object = propertyTable` is required for
  `LrView.bind(...)` controls to resolve correctly.
- Bound push-button titles rendered poorly in practice. Fixed button titles with
  a separate bound summary label were more reliable.
- Checkbox observer updates may lag for derived labels. For state that must
  update immediately, use an explicit button action or accept that the checkbox
  itself is the source of visible state.
- `LrView` does not provide a native directory picker control. Use a static path
  label plus a `Choose...` button backed by `LrDialogs.runOpenPanel`.

## Yielding and async work

- Lightroom catalog and export APIs may yield.
- Do not wrap yielding Lightroom APIs in `pcall`; Lua reports
  `Yielding is not allowed within a C or metamethod call`.
- Run long work from `LrTasks.startAsyncTask`.
- Add `LrTasks.yield()` in large Lua loops, update progress captions, and honor
  progress cancellation.
- Prefer `catalog:findPhotos()` search descriptors for rating-filtered syncs.
  A full-catalog `catalog:getAllPhotos()` call can be expensive before plugin
  code can report detailed per-photo progress.

## Filesystem behavior

- Lightroom's Lua environment may not expose `os.execute`; do not shell out for
  `mkdir -p` or other filesystem operations.
- Prefer `LrFileUtils.createAllDirectories` inside Lightroom.
- Return clear errors when directory creation cannot be performed.

## Metadata edge cases

- Lightroom metadata fields can be nil for offline files, missing originals, or
  unexpected catalog states.
- Lua varargs/table construction can drop fallback values after nil gaps. Use
  `select("#", ...)` when implementing nil-tolerant fallback helpers.
- Treat missing source paths and filenames as expected input. Derive a filename
  from path when possible, otherwise use a stable fallback such as `photo`.
