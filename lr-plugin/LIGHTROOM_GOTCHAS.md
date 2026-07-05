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
- `LrView` bound `static_text` widgets auto-size to the initial title string and
  do **not** resize when the bound value changes. A longer bound string renders
  as empty (clipped) rather than truncating visibly. Always set
  `fill_horizontal = 1` or `width_in_chars` on bound `static_text` labels whose
  content can grow.
- On Mac OS, clicking outside an `edit_field` does **not** cause it to lose
  focus; only Tab or Enter commits the value. The Plugin Manager's
  `LrPropertyTable.addObserver` is known to be unreliable in
  `LrPluginInfoProvider` contexts — [confirmed in the community since
  2011](https://community.adobe.com/questions-675/propertytable-in-plugin-info-provider-949330).
  The robust pattern for Plugin Manager settings is:
  - Use `value = bind("myKey")` with `bind_to_object = properties` on a parent
    view (standard two-way binding, keeps the property table in sync).
  - Use `immediate = true` + `validate(view, value)` for **all** `edit_field`
    controls. `validate` is a documented `edit_field` callback that fires on
    every keystroke when `immediate = true`. Inside it, set the property
    explicitly, save to prefs, and return `true, value`. This works for both
    text and numeric fields.
  - `action()` alone on an `edit_field` inside the Plugin Manager is
    unreliable — it may never fire. Always pair with `validate` and use
    `validate` as the primary persistence mechanism.
  - Avoid `addObserver` for Plugin Manager edit fields entirely.
  - Catalog APIs (`activeCatalog()`, `getChildCollections()`, `getPhotos()`,
    etc.) **require an async task context** (`LrTasks.startAsyncTask`). The
    Plugin Manager's `action` and `validate` callbacks run in LR's main task,
    which does not support yielding. Wrap catalog queries in an async task:
    ```lua
    action = function()
        LrTasks.startAsyncTask(function()
            local catalog = LrApplication.activeCatalog()
            -- query collections, get photos, etc.
            properties.result = value  -- update bindings from async task
        end)
    end
    ```
  - `catalog:getChildCollections()` returns **only** collection objects (smart
    + regular) at the given level. Use **`source:getChildCollectionSets()`** to
    get nested collection sets, then recurse into each set with the same pair
    of methods. Without this, smart collections inside nested sets are silently
    missed.

## Yielding and async work

- Lightroom catalog and export APIs may yield.
- Do not wrap yielding Lightroom APIs in `pcall`; Lua reports
  `Yielding is not allowed within a C or metamethod call`.
- Run long work from `LrTasks.startAsyncTask`.
- `LrView` callbacks (`action`, `validate`, `key_up`, etc.) run in Lightroom's
  main task and **do not support yielding**. Catalog methods
  (`LrApplication.activeCatalog()`, `catalog:getChildCollections()`,
  `collection:getPhotos()`) must be called inside `LrTasks.startAsyncTask`, not
  directly from view callbacks.
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
