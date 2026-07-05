local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local LrPathUtils = import "LrPathUtils"
local LrPrefs = import "LrPrefs"
local LrProgressScope = import "LrProgressScope"

local Config = require "ImmichDerivativeSyncConfig"
local Exporter = require "ImmichDerivativeSyncExporter"
local Logger = require "ImmichDerivativeSyncLogger"
local Path = require "ImmichDerivativeSyncPath"
local Scanner = require "ImmichDerivativeSyncScanner"
local State = require "ImmichDerivativeSyncState"

local Sync = {}

local running = false

local function statePath()
	return LrPathUtils.child(Config.pluginDataDirectory(), Config.stateFileName)
end

local function catalogPhotos(catalog)
	local photos
	catalog:withReadAccessDo("ImmichDerivativeSyncScan", function()
		photos = catalog:getAllPhotos()
	end)
	return photos or {}
end

local function now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function updateLastRun(properties, exportedCount, skippedCount, orphanCount, failedCount)
	properties.lastRunSummary = string.format(
		"%s exported=%d skipped=%d orphaned=%d failed=%d",
		now(),
		exportedCount,
		skippedCount,
		orphanCount,
		failedCount
	)
end

function Sync.run()
	if running then
		return nil, "sync is already running"
	end
	running = true

	local properties = LrPrefs.prefsForPlugin()
	local config, configErr = Config.fromProperties(properties)
	if not config then
		running = false
		return nil, configErr
	end

	local progressScope = LrProgressScope({ title = "Immich Derivative Sync" })
	local ok, err = pcall(function()
		local state, stateErr = State.load(statePath())
		if not state then
			error(stateErr)
		end

		local catalog = LrApplication.activeCatalog()
		local photos = catalogPhotos(catalog)
		local plan = Scanner.plan(photos, state, config, Path.derivativePath, Exporter.fileExists)
		local exportedCount = 0
		local failedCount = 0

		for _, orphan in ipairs(plan.orphans) do
			State.markOrphaned(state, orphan, now())
		end

		for _, item in ipairs(plan.exports) do
			item.configExportSettingsVersion = config.exportSettingsVersion
			local exportOk, exportErr = Exporter.exportItems({ item }, config, progressScope)
			if exportOk then
				State.markExported(state, item, item.outputPath, now())
				exportedCount = exportedCount + 1
			else
				State.markFailed(state, item, exportErr)
				failedCount = failedCount + 1
				Logger.error("photo_export_failed", {
					photo = item.photo.identifier,
					output = item.outputPath,
					error = exportErr,
				})
			end
		end

		local saveOk, saveErr = State.save(statePath(), state)
		if not saveOk then
			error(saveErr)
		end

		local skippedCount = #photos - #plan.exports - #plan.orphans
		updateLastRun(properties, exportedCount, skippedCount, #plan.orphans, failedCount)
		if failedCount > 0 then
			LrDialogs.message(
				"Immich Derivative Sync completed with failures",
				"Some photos failed to export. Check the Lightroom plugin log and state file.",
				"warning"
			)
		end
	end)

	progressScope:done()
	running = false

	if not ok then
		return nil, err
	end

	return true
end

return Sync
