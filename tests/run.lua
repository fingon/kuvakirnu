package.path = "lr-plugin/ImmichDerivativeSync.lrdevplugin/?.lua;tests/?.lua;" .. package.path

local Config = require "ImmichDerivativeSyncConfig"
local Path = require "ImmichDerivativeSyncPath"
local Photo = require "ImmichDerivativeSyncPhoto"
local Scanner = require "ImmichDerivativeSyncScanner"
local State = require "ImmichDerivativeSyncState"

local tests = {}

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
	end
end

local function assertTrue(value, message)
	if not value then
		error(message or "expected truthy value", 2)
	end
end

local function assertNil(value, message)
	if value ~= nil then
		error((message or "expected nil") .. ": got " .. tostring(value), 2)
	end
end

local function assertPlanStats(actual, expected)
	assertEqual(actual.scanned, expected.scanned, "scanned count differs")
	assertEqual(actual.selected, expected.selected, "selected count differs")
	assertEqual(actual.skipped, expected.skipped, "skipped count differs")
	assertEqual(actual.ignored, expected.ignored, "ignored count differs")
end

local function fakeLightroomPhoto(rawMetadata, formattedMetadata)
	return {
		localIdentifier = rawMetadata and rawMetadata.localIdentifier,
		getRawMetadata = function(_, key)
			return rawMetadata and rawMetadata[key] or nil
		end,
		getFormattedMetadata = function(_, key)
			return formattedMetadata and formattedMetadata[key] or nil
		end,
	}
end

function tests.path_generation_is_stable_and_sanitized()
	local path = Path.derivativePath("/out", {
		identifier = "abc:123",
		fileName = "IMG/1234.CR3",
		captureTime = "2025-09-03 10:11:12",
	})

	assertEqual(path, "/out/2025/2025-09-03/IMG-1234__lr-abc-123.jpg")
end

function tests.path_generation_marks_named_virtual_copies()
	local path = Path.derivativePath("/out", {
		identifier = "copy:123",
		fileName = "IMG_1234.CR3",
		captureTime = "2025-09-03 10:11:12",
		isVirtualCopy = true,
		copyName = "Black/White",
	})

	assertEqual(path, "/out/2025/2025-09-03/IMG_1234__copy-Black-White__lr-copy-123.jpg")
end

function tests.path_generation_marks_numbered_virtual_copies()
	local path = Path.derivativePath("/out", {
		identifier = "copy:123",
		fileName = "IMG_1234.CR3",
		captureTime = "2025-09-03 10:11:12",
		isVirtualCopy = true,
		copyNumber = 2,
	})

	assertEqual(path, "/out/2025/2025-09-03/IMG_1234__copy-2__lr-copy-123.jpg")
end

function tests.path_generation_marks_fallback_virtual_copies()
	local path = Path.derivativePath("/out", {
		identifier = "copy:123",
		fileName = "IMG_1234.CR3",
		captureTime = "2025-09-03 10:11:12",
		isVirtualCopy = true,
	})

	assertEqual(path, "/out/2025/2025-09-03/IMG_1234__copy__lr-copy-123.jpg")
end

function tests.photo_snapshot_handles_missing_path_and_filename_metadata()
	local snapshot = Photo.snapshot(fakeLightroomPhoto({
		localIdentifier = "local-1",
		rating = 0,
	}, {}))

	assertEqual(snapshot.identifier, "local-1")
	assertEqual(snapshot.sourcePath, "")
	assertEqual(snapshot.fileName, "photo")
end

function tests.photo_snapshot_derives_filename_from_source_path()
	local snapshot = Photo.snapshot(fakeLightroomPhoto({
		localIdentifier = "local-1",
		path = "/photos/IMG_1234.CR3",
		rating = 0,
	}, {}))

	assertEqual(snapshot.sourcePath, "/photos/IMG_1234.CR3")
	assertEqual(snapshot.fileName, "IMG_1234.CR3")
end

function tests.scanner_filters_rating_rejected_and_virtual_copy()
	local config = { outputDirectory = "/out", minRating = 3, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local planned = Scanner.plan({
		{ identifier = "a", fileName = "a.jpg", rating = 3, isRejected = false, isVirtualCopy = false },
		{ identifier = "b", fileName = "b.jpg", rating = 2, isRejected = false, isVirtualCopy = false },
		{ identifier = "c", fileName = "c.jpg", rating = 5, isRejected = true, isVirtualCopy = false },
		{ identifier = "d", fileName = "d.jpg", rating = 5, isRejected = false, isVirtualCopy = true },
	}, state, config, Path.derivativePath, function()
		return false
	end)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(planned.stats, { scanned = 4, selected = 1, skipped = 0, ignored = 3 })
end

function tests.scanner_includes_unstarred_when_enabled()
	local config = { outputDirectory = "/out", minRating = 3, includeUnstarred = true, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local planned = Scanner.plan({
		{ identifier = "a", fileName = "a.jpg", rating = 0, isRejected = false, isVirtualCopy = false },
		{ identifier = "b", fileName = "b.jpg", rating = 2, isRejected = false, isVirtualCopy = false },
	}, state, config, Path.derivativePath, function()
		return false
	end)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(planned.stats, { scanned = 2, selected = 1, skipped = 0, ignored = 1 })
end

function tests.scanner_includes_only_unstarred_without_star_threshold()
	local config = { outputDirectory = "/out", minRating = nil, includeUnstarred = true, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local planned = Scanner.plan({
		{ identifier = "a", fileName = "a.jpg", rating = 0, isRejected = false, isVirtualCopy = false },
		{ identifier = "b", fileName = "b.jpg", rating = 5, isRejected = false, isVirtualCopy = false },
	}, state, config, Path.derivativePath, function()
		return false
	end)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(planned.stats, { scanned = 2, selected = 1, skipped = 0, ignored = 1 })
end

function tests.scanner_includes_nothing_without_any_rating_selection()
	local config = { outputDirectory = "/out", minRating = nil, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local planned = Scanner.plan({
		{ identifier = "a", fileName = "a.jpg", rating = 0, isRejected = false, isVirtualCopy = false },
		{ identifier = "b", fileName = "b.jpg", rating = 5, isRejected = false, isVirtualCopy = false },
	}, state, config, Path.derivativePath, function()
		return false
	end)

	assertEqual(#planned.exports, 0)
	assertPlanStats(planned.stats, { scanned = 2, selected = 0, skipped = 0, ignored = 2 })
end

function tests.scanner_includes_virtual_copies_when_enabled()
	local config = { outputDirectory = "/out", minRating = 3, includeUnstarred = false, includeVirtualCopies = true, exportSettingsVersion = 1 }
	local state = State.empty()
	local planned = Scanner.plan({
		{ identifier = "a", fileName = "a.jpg", rating = 5, isRejected = false, isVirtualCopy = true },
	}, state, config, Path.derivativePath, function()
		return false
	end)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(planned.stats, { scanned = 1, selected = 1, skipped = 0, ignored = 0 })
end

function tests.scanner_plan_can_be_canceled()
	local config = { outputDirectory = "/out", minRating = 3, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local progressScope = {
		isCanceled = function()
			return true
		end,
	}

	local planned, err = Scanner.plan({
		{ identifier = "a", fileName = "a.jpg", rating = 3, isRejected = false, isVirtualCopy = false },
	}, state, config, Path.derivativePath, function()
		return false
	end, progressScope)

	assertNil(planned)
	assertEqual(err, "sync canceled")
end

function tests.scanner_plan_updates_progress_scope()
	local config = { outputDirectory = "/out", minRating = 3, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local captions = {}
	local progressScope = {
		isCanceled = function()
			return false
		end,
		setCaption = function(_, caption)
			captions[#captions + 1] = caption
		end,
		setPortionComplete = function()
		end,
	}

	local photos = {}
	for index = 1, 100 do
		photos[index] = { identifier = "a" .. tostring(index), fileName = "a.jpg", rating = 3, isRejected = false, isVirtualCopy = false }
	end

	local planned, err = Scanner.plan(photos, state, config, Path.derivativePath, function()
		return false
	end, progressScope)

	assertTrue(planned, err)
	assertTrue(#captions >= 1)
end

function tests.scanner_reuses_existing_output_path()
	local config = { outputDirectory = "/new", minRating = 3, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	state.photos.a = {
		outputPath = "/old/kept.jpg",
		status = "exported",
		fingerprint = "old",
		exportSettingsVersion = 1,
	}

	local planned = Scanner.plan({
		{ identifier = "a", sourcePath = "a.raw", fileName = "renamed.raw", rating = 5, isRejected = false, isVirtualCopy = false },
	}, state, config, Path.derivativePath, function()
		return true
	end)

	assertEqual(planned.exports[1].outputPath, "/old/kept.jpg")
end

function tests.scanner_marks_existing_below_threshold_as_orphan()
	local config = { outputDirectory = "/out", minRating = 3, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	state.photos.a = { outputPath = "/out/a.jpg", status = "exported" }

	local planned = Scanner.plan({
		{ identifier = "a", fileName = "a.jpg", rating = 1, isRejected = false, isVirtualCopy = false },
	}, state, config, Path.derivativePath, function()
		return true
	end)

	assertEqual(#planned.orphans, 1)
	assertEqual(planned.orphans[1].photo.identifier, "a")
	assertPlanStats(planned.stats, { scanned = 1, selected = 0, skipped = 0, ignored = 0 })
end

function tests.scanner_skips_when_unchanged_and_file_exists()
	local config = { outputDirectory = "/out", minRating = 3, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local photo = {
		identifier = "a",
		sourcePath = "a.raw",
		fileName = "a.raw",
		rating = 5,
		isRejected = false,
		isVirtualCopy = false,
		captureTime = "2025-01-01",
		lastEditTime = "same",
	}
	state.photos.a = {
		outputPath = "/out/a.jpg",
		status = "exported",
		fingerprint = "a.raw|5|false|false|||2025-01-01|same",
		exportSettingsVersion = 1,
	}

	local planned = Scanner.plan({ photo }, state, config, Path.derivativePath, function()
		return true
	end)

	assertEqual(#planned.exports, 0)
	assertPlanStats(planned.stats, { scanned = 1, selected = 1, skipped = 1, ignored = 0 })
end

function tests.scanner_stats_separate_selected_skips_from_ignored_catalog_photos()
	local config = { outputDirectory = "/out", minRating = 5, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local photos = {}

	for index = 1, 5 do
		local identifier = "selected-" .. tostring(index)
		local photo = {
			identifier = identifier,
			sourcePath = identifier .. ".raw",
			fileName = identifier .. ".raw",
			rating = 5,
			isRejected = false,
			isVirtualCopy = false,
			captureTime = "2025-01-01",
			lastEditTime = "same",
		}
		photos[#photos + 1] = photo
		state.photos[identifier] = {
			outputPath = "/out/" .. identifier .. ".jpg",
			status = "exported",
			fingerprint = Photo.fingerprint(photo),
			exportSettingsVersion = 1,
		}
	end

	for index = 1, 95 do
		photos[#photos + 1] = {
			identifier = "ignored-" .. tostring(index),
			fileName = "ignored.raw",
			rating = 4,
			isRejected = false,
			isVirtualCopy = false,
		}
	end

	local planned = Scanner.plan(photos, state, config, Path.derivativePath, function()
		return true
	end)

	assertEqual(#planned.exports, 0)
	assertEqual(#planned.orphans, 0)
	assertPlanStats(planned.stats, { scanned = 100, selected = 5, skipped = 5, ignored = 95 })
end

function tests.scanner_stats_count_selected_exports_without_skipping()
	local config = { outputDirectory = "/out", minRating = 5, includeUnstarred = false, includeVirtualCopies = false, exportSettingsVersion = 1 }
	local state = State.empty()
	local planned = Scanner.plan({
		{ identifier = "a", sourcePath = "a.raw", fileName = "a.raw", rating = 5, isRejected = false, isVirtualCopy = false },
	}, state, config, Path.derivativePath, function()
		return false
	end)

	assertEqual(#planned.exports, 1)
	assertPlanStats(planned.stats, { scanned = 1, selected = 1, skipped = 0, ignored = 0 })
end

function tests.config_defaults_are_visible()
	local properties = {}
	Config.ensureDefaults(properties)

	assertEqual(properties.minRating, 3)
	assertEqual(properties.longEdgePixels, 3200)
	assertEqual(properties.jpegQuality, 85)
	assertEqual(properties.includeUnstarred, false)
	assertEqual(properties.includeVirtualCopies, false)
end

function tests.config_defaults_repair_blank_persisted_values()
	local properties = {
		minRating = "",
		longEdgePixels = "",
		jpegQuality = "",
		includeUnstarred = "",
		includeVirtualCopies = "",
	}
	Config.ensureDefaults(properties)

	assertEqual(properties.minRating, 3)
	assertEqual(properties.longEdgePixels, 3200)
	assertEqual(properties.jpegQuality, 85)
	assertEqual(properties.includeUnstarred, false)
	assertEqual(properties.includeVirtualCopies, false)
end

function tests.config_toggle_same_rating_clears_threshold()
	assertEqual(Config.toggleMinRating(4, 4), 0)
	assertEqual(Config.toggleMinRating(3, 4), 4)
end

function tests.config_rating_summary_describes_default_threshold()
	assertEqual(Config.ratingSummary({ minRating = 3, includeUnstarred = false }), "Selected: 3+")
end

function tests.config_rating_summary_describes_unstarred_and_threshold()
	assertEqual(Config.ratingSummary({ minRating = 3, includeUnstarred = true }), "Selected: unstarred, 3+")
end

function tests.config_rating_summary_describes_unstarred_only()
	assertEqual(Config.ratingSummary({ minRating = 0, includeUnstarred = true }), "Selected: unstarred only")
end

function tests.config_rating_summary_describes_empty_selection()
	assertEqual(Config.ratingSummary({ minRating = 0, includeUnstarred = false }), "Selected: none")
end

function tests.config_can_sync_requires_output_folder()
	assertEqual(Config.canSync({ outputDirectory = "", minRating = 3, includeUnstarred = false }), false)
	assertEqual(Config.syncAvailabilitySummary({ outputDirectory = "", minRating = 3, includeUnstarred = false }), "Select an output folder.")
end

function tests.config_can_sync_with_default_star_threshold()
	assertEqual(Config.canSync({ outputDirectory = "/out", minRating = 3, includeUnstarred = false }), true)
	assertEqual(Config.syncAvailabilitySummary({ outputDirectory = "/out", minRating = 3, includeUnstarred = false }), "Ready to sync.")
end

function tests.config_can_sync_with_unstarred_only()
	assertEqual(Config.canSync({ outputDirectory = "/out", minRating = 0, includeUnstarred = true }), true)
end

function tests.config_can_sync_rejects_empty_rating_selection()
	local properties = { outputDirectory = "/out", minRating = 0, includeUnstarred = false }
	assertEqual(Config.canSync(properties), false)
	assertEqual(Config.syncAvailabilitySummary(properties), "Select unstarred or a star threshold.")
end

function tests.state_round_trips()
	local path = os.tmpname()
	local state = State.empty()
	state.photos.a = {
		outputPath = "/out/a.jpg",
		status = "exported",
	}

	local ok, saveErr = State.save(path, state)
	assertTrue(ok, saveErr)

	local loaded, loadErr = State.load(path)
	assertTrue(loaded, loadErr)
	assertEqual(loaded.photos.a.outputPath, "/out/a.jpg")
	assertEqual(loaded.photos.a.status, "exported")

	os.remove(path)
end

function tests.state_save_requires_existing_or_lightroom_directory_creation()
	local state = State.empty()
	local path = "missing-test-dir/state.lua"

	local ok, err = State.save(path, state)

	assertNil(ok)
	assertTrue(tostring(err):match("failed to create state directory") ~= nil)
end

function tests.state_reports_corruption()
	local path = os.tmpname()
	local file = io.open(path, "w")
	file:write("return { photos = ")
	file:close()

	local loaded, err = State.load(path)
	assertNil(loaded)
	assertTrue(tostring(err):match("failed to parse state file") ~= nil)

	os.remove(path)
end

function tests.config_validates_bounds()
	local config, err = Config.fromProperties({
		outputDirectory = "/out",
		minRating = 7,
		longEdgePixels = 3200,
		jpegQuality = 85,
	})

	assertNil(config)
	assertTrue(tostring(err):match("minimum rating") ~= nil)
end

function tests.config_normalizes_zero_threshold_to_nil()
	local config, err = Config.fromProperties({
		outputDirectory = "/out",
		minRating = 0,
		longEdgePixels = 3200,
		jpegQuality = 85,
		includeUnstarred = true,
		includeVirtualCopies = true,
	})

	assertTrue(config, err)
	assertNil(config.minRating)
	assertEqual(config.includeUnstarred, true)
	assertEqual(config.includeVirtualCopies, true)
end

function tests.config_from_properties_repairs_blank_persisted_values()
	local config, err = Config.fromProperties({
		outputDirectory = "/out",
		minRating = "",
		longEdgePixels = "",
		jpegQuality = "",
		includeUnstarred = "",
		includeVirtualCopies = "",
	})

	assertTrue(config, err)
	assertEqual(config.minRating, 3)
	assertEqual(config.longEdgePixels, 3200)
	assertEqual(config.jpegQuality, 85)
	assertEqual(config.includeUnstarred, false)
	assertEqual(config.includeVirtualCopies, false)
end

function tests.config_loads_preferences_into_properties()
	local prefs = {
		outputDirectory = "/chosen",
		minRating = 4,
		longEdgePixels = 2048,
		jpegQuality = 75,
		includeUnstarred = true,
		includeVirtualCopies = true,
		lastRunSummary = "done",
	}
	local properties = {}

	Config.loadPreferencesIntoProperties(prefs, properties)

	assertEqual(properties.outputDirectory, "/chosen")
	assertEqual(properties.minRating, 4)
	assertEqual(properties.longEdgePixels, 2048)
	assertEqual(properties.jpegQuality, 75)
	assertEqual(properties.includeUnstarred, true)
	assertEqual(properties.includeVirtualCopies, true)
	assertEqual(properties.lastRunSummary, "done")
	assertEqual(properties.outputDirectoryDisplay, "/chosen")
	assertEqual(properties.ratingSummary, "Selected: unstarred, 4+")
end

function tests.config_loads_empty_preferences_as_defaults()
	local prefs = {}
	local properties = {}

	Config.loadPreferencesIntoProperties(prefs, properties)

	assertEqual(properties.outputDirectory, "")
	assertEqual(properties.minRating, 3)
	assertEqual(properties.longEdgePixels, 3200)
	assertEqual(properties.jpegQuality, 85)
	assertEqual(properties.includeUnstarred, false)
	assertEqual(properties.includeVirtualCopies, false)
	assertEqual(properties.outputDirectoryDisplay, "Not selected")
	assertEqual(properties.ratingSummary, "Selected: 3+")
end

function tests.config_saves_properties_to_preferences()
	local properties = {
		outputDirectory = "/out",
		minRating = 5,
		longEdgePixels = 1600,
		jpegQuality = 70,
		includeUnstarred = true,
		includeVirtualCopies = false,
		lastRunSummary = "old",
		outputDirectoryDisplay = "derived",
		ratingSummary = "derived",
	}
	local prefs = {}

	Config.savePropertiesToPreferences(properties, prefs)

	assertEqual(prefs.outputDirectory, "/out")
	assertEqual(prefs.minRating, 5)
	assertEqual(prefs.longEdgePixels, 1600)
	assertEqual(prefs.jpegQuality, 70)
	assertEqual(prefs.includeUnstarred, true)
	assertEqual(prefs.includeVirtualCopies, false)
	assertEqual(prefs.lastRunSummary, "old")
	assertNil(prefs.outputDirectoryDisplay)
	assertNil(prefs.ratingSummary)
	assertEqual(properties.outputDirectoryDisplay, "/out")
	assertEqual(properties.ratingSummary, "Selected: unstarred, 5+")
end

function tests.config_saves_normalized_blank_properties()
	local properties = {
		outputDirectory = "",
		minRating = "",
		longEdgePixels = "",
		jpegQuality = "",
		includeUnstarred = "",
		includeVirtualCopies = "",
	}
	local prefs = {}

	Config.savePropertiesToPreferences(properties, prefs)

	assertEqual(prefs.minRating, 3)
	assertEqual(prefs.longEdgePixels, 3200)
	assertEqual(prefs.jpegQuality, 85)
	assertEqual(prefs.includeUnstarred, false)
	assertEqual(prefs.includeVirtualCopies, false)
end

local names = {}
for name in pairs(tests) do
	names[#names + 1] = name
end
table.sort(names)

local failed = 0
for _, name in ipairs(names) do
	local ok, err = pcall(tests[name])
	if ok then
		io.stdout:write("ok ", name, "\n")
	else
		failed = failed + 1
		io.stderr:write("not ok ", name, ": ", tostring(err), "\n")
	end
end

if failed > 0 then
	os.exit(1)
end
