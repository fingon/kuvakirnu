package.path = "lr-plugin/ImmichDerivativeSync.lrdevplugin/?.lua;tests/?.lua;" .. package.path

local Config = require "ImmichDerivativeSyncConfig"
local Path = require "ImmichDerivativeSyncPath"
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

function tests.path_generation_is_stable_and_sanitized()
	local path = Path.derivativePath("/out", {
		identifier = "abc:123",
		fileName = "IMG/1234.CR3",
		captureTime = "2025-09-03 10:11:12",
	})

	assertEqual(path, "/out/2025/2025-09-03/IMG-1234__lr-abc-123.jpg")
end

function tests.scanner_filters_rating_rejected_and_virtual_copy()
	local config = { outputDirectory = "/out", minRating = 3, exportSettingsVersion = 1 }
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
end

function tests.scanner_reuses_existing_output_path()
	local config = { outputDirectory = "/new", minRating = 3, exportSettingsVersion = 1 }
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
	local config = { outputDirectory = "/out", minRating = 3, exportSettingsVersion = 1 }
	local state = State.empty()
	state.photos.a = { outputPath = "/out/a.jpg", status = "exported" }

	local planned = Scanner.plan({
		{ identifier = "a", fileName = "a.jpg", rating = 1, isRejected = false, isVirtualCopy = false },
	}, state, config, Path.derivativePath, function()
		return true
	end)

	assertEqual(#planned.orphans, 1)
	assertEqual(planned.orphans[1].photo.identifier, "a")
end

function tests.scanner_skips_when_unchanged_and_file_exists()
	local config = { outputDirectory = "/out", minRating = 3, exportSettingsVersion = 1 }
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
		fingerprint = "a.raw|5|false|2025-01-01|same",
		exportSettingsVersion = 1,
	}

	local planned = Scanner.plan({ photo }, state, config, Path.derivativePath, function()
		return true
	end)

	assertEqual(#planned.exports, 0)
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
