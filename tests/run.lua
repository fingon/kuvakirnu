package.path = "lr-plugin/BulkJpegSync.lrdevplugin/?.lua;tests/?.lua;"
	.. package.path

local Catalog = require("BulkJpegSyncCatalog")
local Config = require("BulkJpegSyncConfig")
local Exporter = require("BulkJpegSyncExporter")
local FileUtils = require("BulkJpegSyncFileUtils")
local Logger = require("BulkJpegSyncLogger")
local Path = require("BulkJpegSyncPath")
local Photo = require("BulkJpegSyncPhoto")
local Scanner = require("BulkJpegSyncScanner")
local State = require("BulkJpegSyncState")

local tests = {}

local function assertEqual(actual, expected, message)
	if actual ~= expected then
		error(
			(message or "values differ")
				.. ": expected "
				.. tostring(expected)
				.. ", got "
				.. tostring(actual),
			2
		)
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
	assertEqual(
		actual.candidates,
		expected.candidates,
		"candidate count differs"
	)
	assertEqual(actual.selected, expected.selected, "selected count differs")
	assertEqual(actual.skipped, expected.skipped, "skipped count differs")
	assertEqual(actual.orphaned, expected.orphaned, "orphaned count differs")
	assertEqual(actual.ignored, expected.ignored, "ignored count differs")
	if expected.metadataMissing ~= nil then
		assertEqual(
			actual.metadataMissing,
			expected.metadataMissing,
			"metadata missing count differs"
		)
	end
	if expected.metadataMismatched ~= nil then
		assertEqual(
			actual.metadataMismatched,
			expected.metadataMismatched,
			"metadata mismatch count differs"
		)
	end
	if expected.captureDateMissing ~= nil then
		assertEqual(
			actual.captureDateMissing,
			expected.captureDateMissing,
			"capture date missing count differs"
		)
	end
end

local function withFakeImport(moduleName, module, fn)
	local previousImport = _G.import
	_G.import = function(name)
		if name == moduleName then
			return module
		end
		error("unexpected import: " .. tostring(name))
	end

	local results = { pcall(fn) }
	_G.import = previousImport
	if not results[1] then
		error(results[2], 2)
	end

	return results[2], results[3]
end

local function withFakeImports(modules, fn)
	local previousImport = _G.import
	_G.import = function(name)
		if modules[name] then
			return modules[name]
		end
		error("unexpected import: " .. tostring(name))
	end

	local results = { pcall(fn) }
	_G.import = previousImport
	if not results[1] then
		error(results[2], 2)
	end

	return results[2], results[3]
end

local function fakeFileUtils(files, failMove)
	return {
		exists = function(path)
			if files[path] ~= nil then
				return "file"
			end
			return false
		end,
		delete = function(path)
			files[path] = nil
			return true
		end,
		move = function(sourcePath, targetPath)
			if failMove and failMove(sourcePath, targetPath) then
				return false, nil
			end
			if files[sourcePath] == nil then
				return false, "missing source"
			end
			if files[targetPath] ~= nil then
				return false, "target exists"
			end

			files[targetPath] = files[sourcePath]
			files[sourcePath] = nil
			return true
		end,
	}
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

local function syncConfig(overrides)
	local config = {
		outputDirectory = "/out",
		minRating = 3,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
		pluginVersionTimestamp = "2026-07-05T07:20:00Z",
		outputSettingsChangedAt = "2026-07-05T07:20:00Z",
		outputSettingsFingerprint = "exportSettingsVersion=1|longEdgePixels=3200|jpegQuality=85",
	}
	if overrides then
		for key, value in pairs(overrides) do
			config[key] = value
		end
	end

	return config
end

local function containsValue(values, expected)
	for _, value in ipairs(values) do
		if value == expected then
			return true
		end
	end

	return false
end

function tests.catalog_search_description_filters_threshold_and_rejected()
	local desc =
		Catalog.searchDescription({ minRating = 4, includeUnstarred = false })

	assertEqual(desc.combine, "intersect")
	assertEqual(desc[1].criteria, "pick")
	assertEqual(desc[1].operation, "!=")
	assertEqual(desc[1].value, -1)
	assertEqual(desc[2].criteria, "rating")
	assertEqual(desc[2].operation, ">=")
	assertEqual(desc[2].value, 4)
end

function tests.catalog_search_description_filters_unstarred_only()
	local desc =
		Catalog.searchDescription({ minRating = nil, includeUnstarred = true })

	assertEqual(desc.combine, "intersect")
	assertEqual(desc[2].criteria, "rating")
	assertEqual(desc[2].operation, "==")
	assertEqual(desc[2].value, 0)
end

function tests.catalog_search_description_unions_unstarred_and_threshold()
	local desc =
		Catalog.searchDescription({ minRating = 3, includeUnstarred = true })

	assertEqual(desc.combine, "intersect")
	assertEqual(desc[2].combine, "union")
	assertEqual(desc[2][1].criteria, "rating")
	assertEqual(desc[2][1].operation, "==")
	assertEqual(desc[2][1].value, 0)
	assertEqual(desc[2][2].criteria, "rating")
	assertEqual(desc[2][2].operation, ">=")
	assertEqual(desc[2][2].value, 3)
end

function tests.catalog_find_candidates_uses_find_photos()
	local received = nil
	local catalog = {
		findPhotos = function(_, params)
			received = params.searchDesc
			return { "photo" }
		end,
	}

	local photos, err = Catalog.findCandidates(
		catalog,
		{ minRating = 5, includeUnstarred = false }
	)

	assertTrue(photos, err)
	assertEqual(photos[1], "photo")
	assertEqual(received[2].criteria, "rating")
	assertEqual(received[2].value, 5)
end

function tests.catalog_batch_metadata_uses_documented_key_sets()
	local rawKeys = nil
	local formattedKeys = nil
	local photos = { "photo" }
	local catalog = {
		batchGetRawMetadata = function(_, receivedPhotos, keys)
			assertEqual(receivedPhotos, photos)
			rawKeys = keys
			return { photo = { rating = 5 } }
		end,
		batchGetFormattedMetadata = function(_, receivedPhotos, keys)
			assertEqual(receivedPhotos, photos)
			formattedKeys = keys
			return { photo = { fileName = "a.raw" } }
		end,
	}

	local metadata, err = Catalog.batchMetadata(catalog, photos)

	assertTrue(metadata, err)
	assertEqual(metadata.raw.photo.rating, 5)
	assertEqual(metadata.formatted.photo.fileName, "a.raw")
	assertTrue(containsValue(rawKeys, "rating"))
	assertTrue(containsValue(rawKeys, "dateTimeOriginalISO8601"))
	assertTrue(not containsValue(rawKeys, "copyName"))
	assertTrue(not containsValue(rawKeys, "copyNumber"))
	assertTrue(not containsValue(rawKeys, "lastUpdated"))
	assertTrue(not containsValue(rawKeys, "lastImportTime"))
	assertTrue(containsValue(formattedKeys, "fileName"))
	assertTrue(containsValue(formattedKeys, "copyName"))
	assertTrue(not containsValue(formattedKeys, "dateTimeOriginal"))
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

	assertEqual(
		path,
		"/out/2025/2025-09-03/IMG_1234__copy-Black-White__lr-copy-123.jpg"
	)
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
	assertEqual(snapshot.ratingMissing, false)
end

function tests.photo_snapshot_marks_missing_rating_metadata()
	local snapshot = Photo.snapshot(fakeLightroomPhoto({
		localIdentifier = "local-1",
	}, {}))

	assertEqual(snapshot.rating, 0)
	assertEqual(snapshot.ratingMissing, true)
end

function tests.photo_snapshot_prefers_iso8601_capture_date()
	local snapshot = Photo.snapshotFromMetadata(fakeLightroomPhoto({}), {
		localIdentifier = "local-1",
		dateTimeOriginalISO8601 = "2025-09-03T10:11:12",
		dateTimeOriginal = 123,
	}, {})

	assertEqual(snapshot.captureTime, "2025-09-03")
	assertEqual(snapshot.captureDateMissing, false)
	assertEqual(snapshot.captureDateSource, "dateTimeOriginalISO8601")
end

function tests.photo_snapshot_converts_lightroom_timestamp_with_lrdate()
	withFakeImport("LrDate", {
		timeToIsoDate = function(value)
			assertEqual(value, 123)
			return "2024-08-02T03:04:05"
		end,
	}, function()
		local snapshot = Photo.snapshotFromMetadata(fakeLightroomPhoto({}), {
			localIdentifier = "local-1",
			dateTimeOriginal = 123,
		}, {})

		assertEqual(snapshot.captureTime, "2024-08-02")
		assertEqual(snapshot.captureDateMissing, false)
		assertEqual(snapshot.captureDateSource, "dateTimeOriginal")
	end)
end

function tests.photo_snapshot_ignores_undocumented_capture_time_key()
	local snapshot = Photo.snapshotFromMetadata(fakeLightroomPhoto({}), {
		localIdentifier = "local-1",
		captureTime = "2025-09-03T10:11:12",
	}, {})

	assertNil(snapshot.captureTime)
	assertEqual(snapshot.captureDateMissing, true)
end

function tests.photo_snapshot_from_metadata_does_not_call_per_photo_getters()
	local photo = {
		localIdentifier = "local-1",
		getRawMetadata = function()
			error("unexpected raw metadata call")
		end,
		getFormattedMetadata = function()
			error("unexpected formatted metadata call")
		end,
	}

	local snapshot = Photo.snapshotFromMetadata(photo, {
		uuid = "uuid-1",
		path = "/photos/a.raw",
		rating = 5,
		dateTimeOriginalISO8601 = "2025-09-03T10:11:12",
	}, {
		fileName = "a.raw",
	})

	assertEqual(snapshot.identifier, "uuid-1")
	assertEqual(snapshot.fileName, "a.raw")
	assertEqual(snapshot.rating, 5)
	assertEqual(snapshot.captureTime, "2025-09-03")
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
	local config = {
		outputDirectory = "/out",
		minRating = 3,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				fileName = "a.jpg",
				rating = 3,
				isRejected = false,
				isVirtualCopy = false,
			},
			{
				identifier = "b",
				fileName = "b.jpg",
				rating = 2,
				isRejected = false,
				isVirtualCopy = false,
			},
			{
				identifier = "c",
				fileName = "c.jpg",
				rating = 5,
				isRejected = true,
				isVirtualCopy = false,
			},
			{
				identifier = "d",
				fileName = "d.jpg",
				rating = 5,
				isRejected = false,
				isVirtualCopy = true,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end
	)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(
		planned.stats,
		{ candidates = 4, selected = 1, skipped = 0, orphaned = 0, ignored = 3 }
	)
end

function tests.scanner_includes_unstarred_when_enabled()
	local config = {
		outputDirectory = "/out",
		minRating = 3,
		includeUnstarred = true,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				fileName = "a.jpg",
				rating = 0,
				isRejected = false,
				isVirtualCopy = false,
			},
			{
				identifier = "b",
				fileName = "b.jpg",
				rating = 2,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end
	)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(
		planned.stats,
		{ candidates = 2, selected = 1, skipped = 0, orphaned = 0, ignored = 1 }
	)
end

function tests.scanner_includes_only_unstarred_without_star_threshold()
	local config = {
		outputDirectory = "/out",
		minRating = nil,
		includeUnstarred = true,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				fileName = "a.jpg",
				rating = 0,
				isRejected = false,
				isVirtualCopy = false,
			},
			{
				identifier = "b",
				fileName = "b.jpg",
				rating = 5,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end
	)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(
		planned.stats,
		{ candidates = 2, selected = 1, skipped = 0, orphaned = 0, ignored = 1 }
	)
end

function tests.scanner_includes_nothing_without_any_rating_selection()
	local config = {
		outputDirectory = "/out",
		minRating = nil,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				fileName = "a.jpg",
				rating = 0,
				isRejected = false,
				isVirtualCopy = false,
			},
			{
				identifier = "b",
				fileName = "b.jpg",
				rating = 5,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end
	)

	assertEqual(#planned.exports, 0)
	assertPlanStats(
		planned.stats,
		{ candidates = 2, selected = 0, skipped = 0, orphaned = 0, ignored = 2 }
	)
end

function tests.scanner_includes_virtual_copies_when_enabled()
	local config = {
		outputDirectory = "/out",
		minRating = 3,
		includeUnstarred = false,
		includeVirtualCopies = true,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				fileName = "a.jpg",
				rating = 5,
				isRejected = false,
				isVirtualCopy = true,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end
	)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 0, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_plan_can_be_canceled()
	local config = {
		outputDirectory = "/out",
		minRating = 3,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local progressScope = {
		isCanceled = function()
			return true
		end,
	}

	local planned, err = Scanner.plan(
		{
			{
				identifier = "a",
				fileName = "a.jpg",
				rating = 3,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end,
		progressScope
	)

	assertNil(planned)
	assertEqual(err, "sync canceled")
end

function tests.scanner_plan_updates_progress_scope()
	local config = {
		outputDirectory = "/out",
		minRating = 3,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local captions = {}
	local progressScope = {
		isCanceled = function()
			return false
		end,
		setCaption = function(_, caption)
			captions[#captions + 1] = caption
		end,
		setPortionComplete = function() end,
	}

	local photos = {}
	for index = 1, 100 do
		photos[index] = {
			identifier = "a" .. tostring(index),
			fileName = "a.jpg",
			rating = 3,
			isRejected = false,
			isVirtualCopy = false,
		}
	end

	local planned, err = Scanner.plan(
		photos,
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end,
		progressScope
	)

	assertTrue(planned, err)
	assertTrue(#captions >= 1)
end

function tests.scanner_reuses_existing_output_path()
	local config = {
		outputDirectory = "/new",
		minRating = 3,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	state.photos.a = {
		outputPath = "/old/kept.jpg",
		status = "exported",
		fingerprint = "old",
		exportSettingsVersion = 1,
	}

	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				sourcePath = "a.raw",
				fileName = "renamed.raw",
				rating = 5,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(planned.exports[1].outputPath, "/old/kept.jpg")
end

function tests.scanner_marks_existing_below_threshold_as_orphan()
	local config = {
		outputDirectory = "/out",
		minRating = 3,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	state.photos.a = { outputPath = "/out/a.jpg", status = "exported" }

	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				fileName = "a.jpg",
				rating = 1,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.orphans, 1)
	assertEqual(planned.orphans[1].photo.identifier, "a")
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 0, skipped = 0, orphaned = 1, ignored = 0 }
	)
end

function tests.scanner_skips_when_unchanged_and_file_exists()
	local config = syncConfig()
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
		pluginVersionTimestamp = config.pluginVersionTimestamp,
		outputSettingsChangedAt = config.outputSettingsChangedAt,
		outputSettingsFingerprint = "exportSettingsVersion=1|longEdgePixels=3200|jpegQuality=85",
		lastExportTime = "2026-07-05T07:21:00Z",
	}

	local planned = Scanner.plan(
		{ photo },
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.exports, 0)
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 1, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_skips_when_matching_epochs_are_newer_than_last_export_time()
	local config = syncConfig()
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
		fingerprint = Photo.fingerprint(photo),
		exportSettingsVersion = 1,
		pluginVersionTimestamp = config.pluginVersionTimestamp,
		outputSettingsChangedAt = config.outputSettingsChangedAt,
		outputSettingsFingerprint = config.outputSettingsFingerprint,
		lastExportTime = "2026-07-05T07:19:59Z",
	}

	local planned = Scanner.plan(
		{ photo },
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.exports, 0)
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 1, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_exports_legacy_record_older_than_plugin_version()
	local config = syncConfig()
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
		fingerprint = Photo.fingerprint(photo),
		exportSettingsVersion = 1,
		outputSettingsFingerprint = config.outputSettingsFingerprint,
		lastExportTime = "2026-07-05T07:19:59Z",
	}

	local planned = Scanner.plan(
		{ photo },
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.exports, 1)
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 0, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_exports_legacy_record_older_than_output_settings()
	local config =
		syncConfig({ pluginVersionTimestamp = "2026-07-05T07:00:00Z" })
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
		fingerprint = Photo.fingerprint(photo),
		exportSettingsVersion = 1,
		outputSettingsFingerprint = config.outputSettingsFingerprint,
		lastExportTime = "2026-07-05T07:19:59Z",
	}

	local planned = Scanner.plan(
		{ photo },
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.exports, 1)
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 0, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_exports_when_plugin_epoch_differs()
	local config = syncConfig()
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
		fingerprint = Photo.fingerprint(photo),
		exportSettingsVersion = 1,
		pluginVersionTimestamp = "2026-07-05T06:00:00Z",
		outputSettingsChangedAt = config.outputSettingsChangedAt,
		outputSettingsFingerprint = config.outputSettingsFingerprint,
		lastExportTime = "2026-07-05T07:21:00Z",
	}

	local planned = Scanner.plan(
		{ photo },
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.exports, 1)
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 0, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_exports_when_output_settings_epoch_differs()
	local config = syncConfig()
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
		fingerprint = Photo.fingerprint(photo),
		exportSettingsVersion = 1,
		pluginVersionTimestamp = config.pluginVersionTimestamp,
		outputSettingsChangedAt = "2026-07-05T06:00:00Z",
		outputSettingsFingerprint = config.outputSettingsFingerprint,
		lastExportTime = "2026-07-05T07:21:00Z",
	}

	local planned = Scanner.plan(
		{ photo },
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.exports, 1)
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 0, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_exports_when_output_settings_fingerprint_differs()
	local config = syncConfig()
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
		fingerprint = Photo.fingerprint(photo),
		exportSettingsVersion = 1,
		outputSettingsFingerprint = "exportSettingsVersion=1|longEdgePixels=1600|jpegQuality=85",
		lastExportTime = "2026-07-05T07:21:00Z",
	}

	local planned = Scanner.plan(
		{ photo },
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.exports, 1)
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 0, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_marks_exported_records_absent_from_candidates_as_orphans()
	local config = {
		outputDirectory = "/out",
		minRating = 5,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
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

	state.photos.absent = {
		outputPath = "/out/absent.jpg",
		status = "exported",
		fingerprint = "old",
		exportSettingsVersion = 1,
	}

	local planned = Scanner.plan(
		photos,
		state,
		config,
		Path.derivativePath,
		function()
			return true
		end
	)

	assertEqual(#planned.exports, 0)
	assertEqual(#planned.orphans, 1)
	assertEqual(planned.orphans[1].identifier, "absent")
	assertPlanStats(
		planned.stats,
		{ candidates = 5, selected = 5, skipped = 5, orphaned = 1, ignored = 0 }
	)
end

function tests.scanner_stats_count_selected_exports_without_skipping()
	local config = {
		outputDirectory = "/out",
		minRating = 5,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				sourcePath = "a.raw",
				fileName = "a.raw",
				rating = 5,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end
	)

	assertEqual(#planned.exports, 1)
	assertPlanStats(
		planned.stats,
		{ candidates = 1, selected = 1, skipped = 0, orphaned = 0, ignored = 0 }
	)
end

function tests.scanner_trusts_catalog_selection_when_rating_metadata_is_missing()
	local config = {
		outputDirectory = "/out",
		minRating = 5,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local photo = Photo.snapshot(fakeLightroomPhoto({
		localIdentifier = "a",
		path = "/photos/a.raw",
	}, {}))
	local planned = Scanner.plan(
		{ photo },
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end,
		nil,
		{ trustedCatalogSelection = true }
	)

	assertEqual(#planned.exports, 1)
	assertEqual(planned.exports[1].photo.identifier, "a")
	assertPlanStats(planned.stats, {
		candidates = 1,
		selected = 1,
		skipped = 0,
		orphaned = 0,
		ignored = 0,
		metadataMissing = 1,
		metadataMismatched = 0,
		captureDateMissing = 1,
	})
end

function tests.scanner_trusted_catalog_selection_still_excludes_virtual_copies()
	local config = {
		outputDirectory = "/out",
		minRating = 5,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				sourcePath = "a.raw",
				fileName = "a.raw",
				rating = 5,
				isRejected = false,
				isVirtualCopy = true,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end,
		nil,
		{ trustedCatalogSelection = true }
	)

	assertEqual(#planned.exports, 0)
	assertPlanStats(planned.stats, {
		candidates = 1,
		selected = 0,
		skipped = 0,
		orphaned = 0,
		ignored = 1,
		metadataMissing = 0,
		metadataMismatched = 0,
		captureDateMissing = 0,
	})
end

function tests.scanner_trusted_catalog_selection_counts_metadata_mismatches()
	local config = {
		outputDirectory = "/out",
		minRating = 5,
		includeUnstarred = false,
		includeVirtualCopies = false,
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				sourcePath = "a.raw",
				fileName = "a.raw",
				rating = 1,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end,
		nil,
		{ trustedCatalogSelection = true }
	)

	assertEqual(#planned.exports, 1)
	assertPlanStats(planned.stats, {
		candidates = 1,
		selected = 1,
		skipped = 0,
		orphaned = 0,
		ignored = 0,
		metadataMissing = 0,
		metadataMismatched = 1,
		captureDateMissing = 0,
	})
end

function tests.config_defaults_are_visible()
	local properties = {}
	Config.ensureDefaults(properties)

	assertEqual(properties.minRating, 3)
	assertEqual(properties.longEdgePixels, 3200)
	assertEqual(properties.jpegQuality, 85)
	assertEqual(properties.includeUnstarred, false)
	assertEqual(properties.includeVirtualCopies, false)
	assertEqual(properties.lastRunAt, "Never")
	assertEqual(properties.lastRunResults, "Not run")
	assertEqual(properties.lastRunCleanup, "Not run")
	assertEqual(properties.lastRunDiagnostic, "Never")
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

function tests.config_export_settings_version_tracks_export_behavior()
	assertEqual(Config.exportSettingsVersion, 2)
end

function tests.config_output_settings_fingerprint_tracks_rendering_settings()
	local fingerprint = Config.outputSettingsFingerprint({
		exportSettingsVersion = 2,
		longEdgePixels = 3200,
		jpegQuality = 85,
	})

	assertEqual(
		fingerprint,
		"exportSettingsVersion=2|longEdgePixels=3200|jpegQuality=85"
	)
end

function tests.config_toggle_same_rating_clears_threshold()
	assertEqual(Config.toggleMinRating(4, 4), 0)
	assertEqual(Config.toggleMinRating(3, 4), 4)
end

function tests.config_rating_summary_describes_default_threshold()
	assertEqual(
		Config.ratingSummary({ minRating = 3, includeUnstarred = false }),
		"Selected: 3+"
	)
end

function tests.config_rating_summary_describes_unstarred_and_threshold()
	assertEqual(
		Config.ratingSummary({ minRating = 3, includeUnstarred = true }),
		"Selected: unstarred, 3+"
	)
end

function tests.config_rating_summary_describes_unstarred_only()
	assertEqual(
		Config.ratingSummary({ minRating = 0, includeUnstarred = true }),
		"Selected: unstarred only"
	)
end

function tests.config_rating_summary_describes_empty_selection()
	assertEqual(
		Config.ratingSummary({ minRating = 0, includeUnstarred = false }),
		"Selected: none"
	)
end

function tests.config_can_sync_requires_output_folder()
	assertEqual(
		Config.canSync({
			outputDirectory = "",
			minRating = 3,
			includeUnstarred = false,
		}),
		false
	)
	assertEqual(
		Config.syncAvailabilitySummary({
			outputDirectory = "",
			minRating = 3,
			includeUnstarred = false,
		}),
		"Select an output folder."
	)
end

function tests.config_can_sync_with_default_star_threshold()
	assertEqual(
		Config.canSync({
			outputDirectory = "/out",
			minRating = 3,
			includeUnstarred = false,
		}),
		true
	)
	assertEqual(
		Config.syncAvailabilitySummary({
			outputDirectory = "/out",
			minRating = 0,
			includeUnstarred = false,
		}),
		"Select unstarred, a star threshold, or a smart collection filter."
	)
end

function tests.config_can_sync_with_unstarred_only()
	assertEqual(
		Config.canSync({
			outputDirectory = "/out",
			minRating = 0,
			includeUnstarred = true,
		}),
		true
	)
end

function tests.config_can_sync_rejects_empty_rating_selection()
	local properties =
		{ outputDirectory = "/out", minRating = 0, includeUnstarred = false }
	assertEqual(Config.canSync(properties), false)
	assertEqual(
		Config.syncAvailabilitySummary(properties),
		"Select unstarred, a star threshold, or a smart collection filter."
	)
end

function tests.config_formats_last_run_fields()
	local stats =
		{ candidates = 5, selected = 5, skipped = 4, orphaned = 2, ignored = 1 }

	assertEqual(
		Config.lastRunResults(stats, 1),
		"candidates 5, selected 5, exported 1, skipped 4"
	)
	assertEqual(
		Config.lastRunCleanup(stats, 2, 1),
		"orphaned 2, deleted 2, failed 1"
	)
	assertEqual(
		Config.lastRunDiagnostic("2026-07-05T10:11:12Z", stats, 1, 2, 1),
		"2026-07-05T10:11:12Z candidates=5 selected=5 exported=1 skipped=4 orphaned=2 deleted=2 failed=1 ignored=1 videos_skipped=0 metadata_missing=0 metadata_mismatched=0 capture_date_missing=0"
	)
end

function tests.config_updates_last_run_properties()
	local stats = {
		candidates = 5,
		selected = 4,
		skipped = 3,
		orphaned = 2,
		ignored = 1,
		metadataMissing = 6,
		metadataMismatched = 7,
		captureDateMissing = 8,
	}
	local properties =
		{ outputDirectory = "/out", minRating = 3, includeUnstarred = false }

	Config.updateLastRunProperties(
		properties,
		"2026-07-05T10:11:12Z",
		stats,
		1,
		2,
		3
	)

	assertEqual(properties.lastRunAt, "2026-07-05T10:11:12Z")
	assertEqual(
		properties.lastRunResults,
		"candidates 5, selected 4, exported 1, skipped 3"
	)
	assertEqual(properties.lastRunCleanup, "orphaned 2, deleted 2, failed 3")
	assertEqual(
		properties.lastRunDiagnostic,
		"2026-07-05T10:11:12Z candidates=5 selected=4 exported=1 skipped=3 orphaned=2 deleted=2 failed=3 ignored=1 videos_skipped=0 metadata_missing=6 metadata_mismatched=7 capture_date_missing=8"
	)
	assertEqual(properties.canSync, true)
end

function tests.export_settings_prevent_upscaling_and_include_metadata()
	local settings = Exporter.exportSettings({
		longEdgePixels = 3200,
		jpegQuality = 85,
	}, "/tmp/export")

	assertEqual(settings.LR_export_destinationPathPrefix, "/tmp/export")
	assertEqual(settings.LR_format, "JPEG")
	assertEqual(settings.LR_jpeg_quality, 0.85)
	assertEqual(settings.LR_size_doConstrain, true)
	assertEqual(settings.LR_size_doNotEnlarge, true)
	assertEqual(settings.LR_size_maxHeight, 3200)
	assertEqual(settings.LR_size_maxWidth, 3200)
	assertEqual(settings.LR_embeddedMetadataOption, "all")
	assertEqual(settings.LR_minimizeEmbeddedMetadata, false)
	assertEqual(settings.LR_metadata_keywordOptions, "lightroomHierarchical")
	assertEqual(settings.LR_removeLocationMetadata, false)
end

function tests.logger_writes_plugin_owned_log_file()
	local path = os.tmpname()
	os.remove(path)
	withFakeImports({
		LrFileUtils = {
			createAllDirectories = function(directory)
				return os.execute("mkdir -p " .. directory)
			end,
		},
		LrPathUtils = {
			getStandardFilePath = function()
				return path
			end,
			child = function(parent, child)
				return parent .. "/" .. child
			end,
		},
		LrLogger = function()
			return {
				enable = function() end,
				info = function() end,
			}
		end,
	}, function()
		Logger.info("test_event", { photo = "abc" })
	end)

	local file =
		io.open(path .. "/fi.iki.fingon.bulk-jpeg-sync/bulk-jpeg-sync.log", "r")
	assertTrue(file, "expected plugin log file")
	local contents = file:read("*a")
	file:close()

	assertTrue(contents:match("test_event") ~= nil)
	assertTrue(contents:match("photo=abc") ~= nil)
	os.remove(path .. "/fi.iki.fingon.bulk-jpeg-sync/bulk-jpeg-sync.log")
	os.remove(path .. "/fi.iki.fingon.bulk-jpeg-sync")
	os.remove(path)
end

function tests.file_utils_move_reports_missing_lightroom_error()
	local files = { ["/source"] = "new" }
	local fake = fakeFileUtils(files, function()
		return true
	end)

	withFakeImport("LrFileUtils", fake, function()
		local ok, err = FileUtils.moveFile("/source", "/target")

		assertNil(ok)
		assertTrue(tostring(err):match("source=/source") ~= nil)
		assertTrue(tostring(err):match("target=/target") ~= nil)
		assertTrue(tostring(err):match("unknown error") ~= nil)
	end)
end

function tests.file_utils_replace_moves_new_file_without_existing_target()
	local files = { ["/source"] = "new" }
	local fake = fakeFileUtils(files)

	withFakeImport("LrFileUtils", fake, function()
		local ok, err = FileUtils.replaceFile("/source", "/target")

		assertTrue(ok, err)
		assertEqual(files["/target"], "new")
		assertNil(files["/source"])
	end)
end

function tests.file_utils_replace_backs_up_existing_target()
	local files = {
		["/source"] = "new",
		["/target"] = "old",
		["/target.bak"] = "stale",
	}
	local fake = fakeFileUtils(files)

	withFakeImport("LrFileUtils", fake, function()
		local ok, err = FileUtils.replaceFile(
			"/source",
			"/target",
			{ backupPath = "/target.bak" }
		)

		assertTrue(ok, err)
		assertEqual(files["/target"], "new")
		assertEqual(files["/target.bak"], "old")
		assertNil(files["/source"])
	end)
end

function tests.file_utils_replace_restores_backup_when_final_move_fails()
	local files = {
		["/source"] = "new",
		["/target"] = "old",
	}
	local fake = fakeFileUtils(files, function(sourcePath, targetPath)
		return sourcePath == "/source" and targetPath == "/target"
	end)

	withFakeImport("LrFileUtils", fake, function()
		local ok, err = FileUtils.replaceFile(
			"/source",
			"/target",
			{ backupPath = "/target.bak" }
		)

		assertNil(ok)
		assertTrue(tostring(err):match("unknown error") ~= nil)
		assertEqual(files["/target"], "old")
		assertNil(files["/target.bak"])
	end)
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
	os.remove(path .. ".bak")
	os.remove(path .. ".tmp")
end

function tests.state_save_can_replace_existing_state_file()
	local path = os.tmpname()
	local state = State.empty()
	state.photos.a = {
		outputPath = "/out/a.jpg",
		status = "exported",
	}

	local ok, saveErr = State.save(path, state)
	assertTrue(ok, saveErr)

	state.photos.a.status = "orphaned"
	local secondOk, secondSaveErr = State.save(path, state)
	assertTrue(secondOk, secondSaveErr)

	local loaded, loadErr = State.load(path)
	assertTrue(loaded, loadErr)
	assertEqual(loaded.photos.a.status, "orphaned")

	os.remove(path)
	os.remove(path .. ".bak")
	os.remove(path .. ".tmp")
end

function tests.state_mark_exported_records_version_and_output_settings()
	local state = State.empty()
	local item = {
		photo = {
			identifier = "a",
			sourcePath = "a.raw",
		},
		fingerprint = "fingerprint",
		configExportSettingsVersion = 2,
		configPluginVersionTimestamp = "2026-07-05T07:20:00Z",
		configOutputSettingsChangedAt = "2026-07-05T07:20:00Z",
		configOutputSettingsFingerprint = "exportSettingsVersion=2|longEdgePixels=3200|jpegQuality=85",
	}

	State.markExported(state, item, "/out/a.jpg", "2026-07-05T07:21:00Z")

	assertEqual(state.photos.a.exportSettingsVersion, 2)
	assertEqual(state.photos.a.pluginVersionTimestamp, "2026-07-05T07:20:00Z")
	assertEqual(state.photos.a.outputSettingsChangedAt, "2026-07-05T07:20:00Z")
	assertEqual(
		state.photos.a.outputSettingsFingerprint,
		"exportSettingsVersion=2|longEdgePixels=3200|jpegQuality=85"
	)
	assertEqual(state.photos.a.lastExportTime, "2026-07-05T07:21:00Z")
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
	assertEqual(config.exportSettingsVersion, Config.exportSettingsVersion)
	assertEqual(config.pluginVersionTimestamp, Config.pluginVersionTimestamp)
	assertEqual(config.outputSettingsChangedAt, Config.outputSettingsChangedAt)
	assertEqual(
		config.outputSettingsFingerprint,
		Config.outputSettingsFingerprint(config)
	)
end

function tests.config_loads_preferences_into_properties()
	local prefs = {
		outputDirectory = "/chosen",
		minRating = 4,
		longEdgePixels = 2048,
		jpegQuality = 75,
		includeUnstarred = true,
		includeVirtualCopies = true,
		lastRunAt = "2026-07-05T10:11:12Z",
		lastRunResults = "candidates 4",
		lastRunCleanup = "orphaned 0",
		lastRunDiagnostic = "full diagnostic",
	}
	local properties = {}

	Config.loadPreferencesIntoProperties(prefs, properties)

	assertEqual(properties.outputDirectory, "/chosen")
	assertEqual(properties.minRating, 4)
	assertEqual(properties.longEdgePixels, 2048)
	assertEqual(properties.jpegQuality, 75)
	assertEqual(properties.includeUnstarred, true)
	assertEqual(properties.includeVirtualCopies, true)
	assertEqual(properties.lastRunAt, "2026-07-05T10:11:12Z")
	assertEqual(properties.lastRunResults, "candidates 4")
	assertEqual(properties.lastRunCleanup, "orphaned 0")
	assertEqual(properties.lastRunDiagnostic, "full diagnostic")
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
	assertEqual(properties.lastRunAt, "Never")
	assertEqual(properties.lastRunResults, "Not run")
	assertEqual(properties.lastRunCleanup, "Not run")
end

function tests.config_saves_properties_to_preferences()
	local properties = {
		outputDirectory = "/out",
		minRating = 5,
		longEdgePixels = 1600,
		jpegQuality = 70,
		includeUnstarred = true,
		includeVirtualCopies = false,
		lastRunAt = "2026-07-05T10:11:12Z",
		lastRunResults = "candidates 5",
		lastRunCleanup = "orphaned 0",
		lastRunDiagnostic = "full diagnostic",
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
	assertEqual(prefs.lastRunAt, "2026-07-05T10:11:12Z")
	assertEqual(prefs.lastRunResults, "candidates 5")
	assertEqual(prefs.lastRunCleanup, "orphaned 0")
	assertEqual(prefs.lastRunDiagnostic, "full diagnostic")
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

function tests.catalog_get_matching_smart_collections()
	local sc = {
		{
			getName = function()
				return "Five Stars"
			end,
			isSmartCollection = function()
				return true
			end,
		},
		{
			getName = function()
				return "Recently Modified"
			end,
			isSmartCollection = function()
				return true
			end,
		},
		{
			getName = function()
				return "Past Month"
			end,
			isSmartCollection = function()
				return true
			end,
		},
		{
			getName = function()
				return "Video Files"
			end,
			isSmartCollection = function()
				return true
			end,
		},
		{
			getName = function()
				return "five stars"
			end,
			isSmartCollection = function()
				return true
			end,
		},
	}
	local catalog = {
		getChildCollections = function()
			return sc
		end,
		getChildCollectionSets = function()
			return {}
		end,
	}

	local matching = Catalog.getMatchingSmartCollections(catalog, "Five")
	assertEqual(#matching, 1)
	assertEqual(matching[1]:getName(), "Five Stars")
	matching = Catalog.getMatchingSmartCollections(catalog, "five")
	assertEqual(#matching, 1)
	assertEqual(matching[1]:getName(), "five stars")
	matching = Catalog.getMatchingSmartCollections(catalog, "NothingHere")
	assertEqual(#matching, 0)
end

function tests.catalog_get_matching_smart_collections_empty_filter()
	local sc = {
		{
			getName = function()
				return "Five Stars"
			end,
			isSmartCollection = function()
				return true
			end,
		},
		{
			getName = function()
				return "Recently Modified"
			end,
			isSmartCollection = function()
				return true
			end,
		},
	}
	local catalog = {
		getChildCollections = function()
			return sc
		end,
		getChildCollectionSets = function()
			return {}
		end,
	}

	local matching = Catalog.getMatchingSmartCollections(catalog, "")
	assertEqual(#matching, 2)
end

function tests.catalog_get_matching_smart_collections_no_match()
	local sc = {
		{
			getName = function()
				return "Five Stars"
			end,
			isSmartCollection = function()
				return true
			end,
		},
		{
			getName = function()
				return "Recently Modified"
			end,
			isSmartCollection = function()
				return true
			end,
		},
	}
	local catalog = {
		getChildCollections = function()
			return sc
		end,
		getChildCollectionSets = function()
			return {}
		end,
	}

	local matching = Catalog.getMatchingSmartCollections(catalog, "XYZ")
	assertEqual(#matching, 0)
end

function tests.catalog_get_matching_smart_collections_no_catalog()
	local matching = Catalog.getMatchingSmartCollections(nil, "test")
	assertEqual(#matching, 0)
end

function tests.catalog_get_matching_smart_collections_nested()
	local nestedSetSc = {
		{
			getName = function()
				return "Nested In Set"
			end,
			isSmartCollection = function()
				return true
			end,
		},
	}
	local nestedSet = {
		getChildCollections = function()
			return nestedSetSc
		end,
		getChildCollectionSets = function()
			return {}
		end,
	}
	local catalog = {
		getChildCollections = function()
			return {
				{
					getName = function()
						return "Top Level"
					end,
					isSmartCollection = function()
						return true
					end,
				},
			}
		end,
		getChildCollectionSets = function()
			return { nestedSet }
		end,
	}

	local matching = Catalog.getMatchingSmartCollections(catalog, "")
	assertEqual(#matching, 2)
end

function tests.catalog_photos_from_smart_collections_dedup()
	local collections = {
		{
			getPhotos = function()
				return {
					{ localIdentifier = "photo-1" },
					{ localIdentifier = "photo-2" },
				}
			end,
		},
		{
			getPhotos = function()
				return {
					{ localIdentifier = "photo-2" },
					{ localIdentifier = "photo-3" },
				}
			end,
		},
	}

	local photos = Catalog.photosFromSmartCollections(nil, collections)
	assertEqual(#photos, 3)
	assertEqual(photos[1].localIdentifier, "photo-1")
	assertEqual(photos[2].localIdentifier, "photo-2")
	assertEqual(photos[3].localIdentifier, "photo-3")
end

function tests.catalog_photos_from_smart_collections_no_catalog()
	local photos = Catalog.photosFromSmartCollections(nil, {})
	assertEqual(#photos, 0)
end

function tests.catalog_union_photo_lists_dedup()
	local list1 = {
		{ localIdentifier = "a" },
		{ localIdentifier = "b" },
	}
	local list2 = {
		{ localIdentifier = "b" },
		{ localIdentifier = "c" },
	}

	local unioned = Catalog.unionPhotoLists(list1, list2)
	assertEqual(#unioned, 3)
	assertEqual(unioned[1].localIdentifier, "a")
	assertEqual(unioned[2].localIdentifier, "b")
	assertEqual(unioned[3].localIdentifier, "c")
end

function tests.catalog_union_photo_lists_empty_first()
	local list1 = {}
	local list2 = { { localIdentifier = "a" } }
	local unioned = Catalog.unionPhotoLists(list1, list2)
	assertEqual(#unioned, 1)
end

function tests.catalog_union_photo_lists_empty_second()
	local list1 = { { localIdentifier = "a" } }
	local list2 = {}
	local unioned = Catalog.unionPhotoLists(list1, list2)
	assertEqual(#unioned, 1)
end

function tests.catalog_union_photo_lists_both_empty()
	assertEqual(#Catalog.unionPhotoLists({}, {}), 0)
end

function tests.config_can_sync_with_smart_collection_filter()
	assertEqual(
		Config.canSync({
			outputDirectory = "/out",
			minRating = 0,
			includeUnstarred = false,
			smartCollectionFilter = "Vacation",
		}),
		true
	)
end

function tests.config_can_sync_rejects_smart_collection_filter_without_output()
	assertEqual(
		Config.canSync({
			outputDirectory = "",
			minRating = 0,
			includeUnstarred = false,
			smartCollectionFilter = "Vacation",
		}),
		false
	)
end

function tests.config_can_sync_rejects_smart_collection_filter_with_empty_string()
	assertEqual(
		Config.canSync({
			outputDirectory = "/out",
			minRating = 0,
			includeUnstarred = false,
			smartCollectionFilter = "",
		}),
		false
	)
end

function tests.config_rating_summary_smart_collection_only()
	local summary = Config.ratingSummary({
		minRating = 0,
		includeUnstarred = false,
		smartCollectionFilter = "Vacation",
		smartCollectionMatchCount = 3,
	})
	assertEqual(summary, "Selected: smart collection 'Vacation' (3 matching)")
end

function tests.config_rating_summary_smart_collection_and_stars()
	local summary = Config.ratingSummary({
		minRating = 3,
		includeUnstarred = false,
		smartCollectionFilter = "Vacation",
		smartCollectionMatchCount = 2,
	})
	assertEqual(
		summary,
		"Selected: 3+ + smart collection 'Vacation' (2 matching)"
	)
end

function tests.config_rating_summary_smart_collection_unstarred_and_stars()
	local summary = Config.ratingSummary({
		minRating = 3,
		includeUnstarred = true,
		smartCollectionFilter = "Edited",
		smartCollectionMatchCount = 1,
	})
	assertEqual(
		summary,
		"Selected: unstarred, 3+ + smart collection 'Edited' (1 matching)"
	)
end

function tests.config_rating_summary_smart_collection_without_match_count()
	local summary = Config.ratingSummary({
		minRating = 0,
		includeUnstarred = false,
		smartCollectionFilter = "Vacation",
	})
	assertEqual(summary, "Selected: smart collection 'Vacation'")
end

function tests.config_smart_collection_summary_with_filter()
	assertEqual(
		Config.smartCollectionSummary({
			smartCollectionFilter = "Test",
		}),
		"Smart collection filter: 'Test'"
	)
end

function tests.config_smart_collection_summary_with_match_count()
	assertEqual(
		Config.smartCollectionSummary({
			smartCollectionFilter = "Test",
			smartCollectionMatchCount = 4,
		}),
		"Smart collection filter: 'Test' (4 matching)"
	)
end

function tests.config_smart_collection_summary_no_filter()
	assertEqual(
		Config.smartCollectionSummary({
			smartCollectionFilter = "",
		}),
		"Type name to filter by smart collection"
	)
end

function tests.config_ensure_defaults_smart_collection_filter()
	local properties = {}
	Config.ensureDefaults(properties)
	assertEqual(properties.smartCollectionFilter, "")
end

function tests.config_loads_preferences_into_properties_with_smart_collection()
	local prefs = {
		outputDirectory = "/chosen",
		minRating = 4,
		smartCollectionFilter = "Vacation",
		includeVirtualCopies = true,
	}
	local properties = {}
	Config.loadPreferencesIntoProperties(prefs, properties)
	assertEqual(properties.smartCollectionFilter, "Vacation")
end

function tests.scanner_plan_with_smart_collection_mode()
	local config = {
		outputDirectory = "/out",
		minRating = nil,
		includeUnstarred = false,
		includeVirtualCopies = false,
		smartCollectionFilter = "Test",
		exportSettingsVersion = 1,
	}
	local state = State.empty()
	local planned = Scanner.plan(
		{
			{
				identifier = "a",
				fileName = "a.jpg",
				rating = 5,
				isRejected = false,
				isVirtualCopy = false,
			},
			{
				identifier = "b",
				fileName = "b.jpg",
				rating = 1,
				isRejected = false,
				isVirtualCopy = false,
			},
		},
		state,
		config,
		Path.derivativePath,
		function()
			return false
		end,
		nil,
		{ trustedCatalogSelection = true }
	)

	assertEqual(#planned.exports, 2)
	assertPlanStats(
		planned.stats,
		{ candidates = 2, selected = 2, skipped = 0, orphaned = 0, ignored = 0 }
	)
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
