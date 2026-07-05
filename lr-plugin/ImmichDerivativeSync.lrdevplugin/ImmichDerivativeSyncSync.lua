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
	return catalog:getAllPhotos() or {}
end

local function now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function canceled(progressScope)
	return progressScope and progressScope.isCanceled and progressScope:isCanceled()
end

local function finish(progressScope)
	progressScope:done()
	running = false
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

	progressScope:setCaption("Loading sync state")
	local state, stateErr = State.load(statePath())
	if not state then
		finish(progressScope)
		return nil, stateErr
	end

	if canceled(progressScope) then
		finish(progressScope)
		return nil, "sync canceled"
	end

	progressScope:setCaption("Reading Lightroom catalog")
	local catalog = LrApplication.activeCatalog()
	local photos = catalogPhotos(catalog)
	if canceled(progressScope) then
		finish(progressScope)
		return nil, "sync canceled"
	end

	progressScope:setCaption("Planning derivatives")
	local plan, planErr = Scanner.plan(photos, state, config, Path.derivativePath, Exporter.fileExists, progressScope)
	if not plan then
		finish(progressScope)
		return nil, planErr
	end
	local exportedCount = 0
	local failedCount = 0

	progressScope:setCaption("Marking orphans")
	for index, orphan in ipairs(plan.orphans) do
		if canceled(progressScope) then
			finish(progressScope)
			return nil, "sync canceled"
		end
		if index % 100 == 0 then
			progressScope:setCaption("Marking orphans " .. tostring(index) .. " of " .. tostring(#plan.orphans))
		end
		State.markOrphaned(state, orphan, now())
	end

	progressScope:setCaption("Exporting 0 of " .. tostring(#plan.exports))
	for index, item in ipairs(plan.exports) do
		if canceled(progressScope) then
			finish(progressScope)
			return nil, "sync canceled"
		end
		progressScope:setCaption("Exporting " .. tostring(index) .. " of " .. tostring(#plan.exports))
		progressScope:setPortionComplete(index - 1, #plan.exports)
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

	progressScope:setCaption("Saving sync state")
	local saveOk, saveErr = State.save(statePath(), state)
	if not saveOk then
		finish(progressScope)
		return nil, saveErr
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

	finish(progressScope)

	return true
end

return Sync
