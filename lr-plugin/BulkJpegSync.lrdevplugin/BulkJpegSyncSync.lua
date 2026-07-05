local LrApplication = import "LrApplication"
local LrDialogs = import "LrDialogs"
local LrPathUtils = import "LrPathUtils"
local LrPrefs = import "LrPrefs"
local LrProgressScope = import "LrProgressScope"

local Catalog = require "BulkJpegSyncCatalog"
local Config = require "BulkJpegSyncConfig"
local Exporter = require "BulkJpegSyncExporter"
local FileUtils = require "BulkJpegSyncFileUtils"
local Logger = require "BulkJpegSyncLogger"
local Path = require "BulkJpegSyncPath"
local Scanner = require "BulkJpegSyncScanner"
local State = require "BulkJpegSyncState"

local Sync = {}

local running = false

local function statePath()
	return LrPathUtils.child(Config.pluginDataDirectory(), Config.stateFileName)
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

local function updateLastRun(properties, stats, exportedCount, deletedCount, failedCount)
	local timestamp = now()
	properties.lastRunAt = timestamp
	properties.lastRunResults = Config.lastRunResults(stats, exportedCount)
	properties.lastRunCleanup = Config.lastRunCleanup(stats, deletedCount, failedCount)
	properties.lastRunDiagnostic = Config.lastRunDiagnostic(timestamp, stats, exportedCount, deletedCount, failedCount)
	Logger.info("sync_completed", {
		diagnostic = properties.lastRunDiagnostic,
		candidates = stats.candidates,
		selected = stats.selected,
		exported = exportedCount,
		skipped = stats.skipped,
		orphaned = stats.orphaned,
		deleted = deletedCount,
		failed = failedCount,
		ignored = stats.ignored,
	})
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

	local progressScope = LrProgressScope({ title = "Bulk JPEG Sync" })

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

	progressScope:setCaption("Searching Lightroom catalog")
	local catalog = LrApplication.activeCatalog()
	local photos, photosErr = Catalog.findCandidates(catalog, config)
	if not photos then
		finish(progressScope)
		return nil, photosErr
	end
	if canceled(progressScope) then
		finish(progressScope)
		return nil, "sync canceled"
	end

	progressScope:setCaption("Planning JPEGs")
	local plan, planErr = Scanner.plan(photos, state, config, Path.derivativePath, Exporter.fileExists, progressScope)
	if not plan then
		finish(progressScope)
		return nil, planErr
	end
	local exportedCount = 0
	local failedCount = 0
	local deletedCount = 0

	progressScope:setCaption("Deleting orphans")
	for index, orphan in ipairs(plan.orphans) do
		if canceled(progressScope) then
			finish(progressScope)
			return nil, "sync canceled"
		end
		if index % 100 == 0 then
			progressScope:setCaption("Deleting orphans " .. tostring(index) .. " of " .. tostring(#plan.orphans))
		end
		local outputPath = orphan.record and orphan.record.outputPath
		local deleteFailed = false
		if outputPath and outputPath ~= "" and FileUtils.fileExists(outputPath) then
			local deleted, deleteErr = FileUtils.deleteFile(outputPath)
			if deleted then
				deletedCount = deletedCount + 1
			else
				deleteFailed = true
				failedCount = failedCount + 1
				Logger.error("orphan_delete_failed", {
					photo = orphan.identifier or "unknown",
					output = outputPath,
					error = deleteErr,
				})
			end
		end
		if not deleteFailed then
			State.markOrphaned(state, orphan, now())
		end
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

	updateLastRun(properties, plan.stats, exportedCount, deletedCount, failedCount)
	if failedCount > 0 then
		LrDialogs.message(
			"Bulk JPEG Sync completed with failures",
			"Some photos failed to export or clean up. Check the Lightroom plugin log and state file.",
			"warning"
		)
	end

	finish(progressScope)

	return true
end

return Sync
