local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")
local LrPathUtils = import("LrPathUtils")
local LrPrefs = import("LrPrefs")
local LrProgressScope = import("LrProgressScope")

local Catalog = require("BulkJpegSyncCatalog")
local Config = require("BulkJpegSyncConfig")
local Exporter = require("BulkJpegSyncExporter")
local FileUtils = require("BulkJpegSyncFileUtils")
local Logger = require("BulkJpegSyncLogger")
local Path = require("BulkJpegSyncPath")
local Photo = require("BulkJpegSyncPhoto")
local Scanner = require("BulkJpegSyncScanner")
local State = require("BulkJpegSyncState")

local Sync = {}

local running = false
local syncCanceledMessage = "sync canceled"
local trustedCatalogSelectionOption = "trustedCatalogSelection"
local progressTotal = 1000
local loadProgressDone = 20
local searchProgressDone = 80
local metadataProgressDone = 160
local planProgressStart = 240
local planProgressEnd = 360
local cleanupProgressEnd = 470
local exportProgressEnd = 940
local saveProgressDone = 970

local function statePath()
	return LrPathUtils.child(Config.pluginDataDirectory(), Config.stateFileName)
end

local function now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function canceled(progressScope)
	return progressScope
		and progressScope.isCanceled
		and progressScope:isCanceled()
end

local function finish(progressScope)
	progressScope:done()
	running = false
end

local function setProgress(progressScope, caption, done)
	progressScope:setCaption(caption)
	progressScope:setPortionComplete(done, progressTotal)
end

local function phaseProgress(startDone, endDone, index, total)
	if total <= 0 then
		return endDone
	end

	return startDone + math.floor((endDone - startDone) * index / total)
end

local function metadataPresentCount(photos, metadata, key)
	local count = 0
	for _, photo in ipairs(photos) do
		local values = metadata.raw[photo] or {}
		if values[key] ~= nil and values[key] ~= "" then
			count = count + 1
		end
	end

	return count
end

local function captureDatePresentCount(photos, metadata)
	local count = 0
	for _, photo in ipairs(photos) do
		local snapshot = Photo.snapshotFromMetadata(
			photo,
			metadata.raw[photo],
			metadata.formatted[photo]
		)
		if not snapshot.captureDateMissing then
			count = count + 1
		end
	end

	return count
end

local function snapshotsFromMetadata(photos, metadata)
	local snapshots = {}
	for index, photo in ipairs(photos) do
		snapshots[index] = Photo.snapshotFromMetadata(
			photo,
			metadata.raw[photo],
			metadata.formatted[photo]
		)
	end

	return snapshots
end

local function updateLastRun(
	activeProperties,
	prefs,
	stats,
	exportedCount,
	deletedCount,
	failedCount
)
	local timestamp = now()
	Config.updateLastRunProperties(
		prefs,
		timestamp,
		stats,
		exportedCount,
		deletedCount,
		failedCount
	)
	if activeProperties and activeProperties ~= prefs then
		Config.updateLastRunProperties(
			activeProperties,
			timestamp,
			stats,
			exportedCount,
			deletedCount,
			failedCount
		)
	end
	Logger.info("sync_completed", {
		diagnostic = prefs.lastRunDiagnostic,
		candidates = stats.candidates,
		selected = stats.selected,
		exported = exportedCount,
		skipped = stats.skipped,
		orphaned = stats.orphaned,
		deleted = deletedCount,
		failed = failedCount,
		ignored = stats.ignored,
		metadata_missing = stats.metadataMissing or 0,
		metadata_mismatched = stats.metadataMismatched or 0,
		capture_date_missing = stats.captureDateMissing or 0,
	})
end

function Sync.run(activeProperties)
	if running then
		return nil, "sync is already running"
	end
	running = true

	local prefs = LrPrefs.prefsForPlugin()
	local properties = activeProperties or prefs
	local config, configErr = Config.fromProperties(properties)
	if not config then
		running = false
		return nil, configErr
	end
	Logger.info("sync_started", {
		output = config.outputDirectory,
		min_rating = config.minRating or 0,
		include_unstarred = config.includeUnstarred,
		include_virtual_copies = config.includeVirtualCopies,
		long_edge_pixels = config.longEdgePixels,
		jpeg_quality = config.jpegQuality,
	})

	local progressScope = LrProgressScope({ title = "Bulk JPEG Sync" })

	setProgress(progressScope, "Loading sync state", loadProgressDone)
	local state, stateErr = State.load(statePath())
	if not state then
		finish(progressScope)
		return nil, stateErr
	end

	if canceled(progressScope) then
		finish(progressScope)
		Logger.info("sync_canceled", { phase = "loading_state" })
		return nil, syncCanceledMessage
	end

	setProgress(
		progressScope,
		"Searching Lightroom catalog",
		searchProgressDone
	)
	local catalog = LrApplication.activeCatalog()
	local photos, photosErr = Catalog.findCandidates(catalog, config)
	if not photos then
		finish(progressScope)
		return nil, photosErr
	end
	Logger.info("catalog_search_completed", {
		candidates = #photos,
		min_rating = config.minRating or 0,
		include_unstarred = config.includeUnstarred,
	})
	if canceled(progressScope) then
		finish(progressScope)
		Logger.info("sync_canceled", { phase = "catalog_search" })
		return nil, syncCanceledMessage
	end

	setProgress(
		progressScope,
		"Reading metadata for " .. tostring(#photos) .. " photos",
		metadataProgressDone
	)
	local metadata, metadataErr = Catalog.batchMetadata(catalog, photos)
	if not metadata then
		finish(progressScope)
		return nil, metadataErr
	end
	Logger.info("metadata_read_completed", {
		candidates = #photos,
		rating_present = metadataPresentCount(photos, metadata, "rating"),
		capture_date_present = captureDatePresentCount(photos, metadata),
		path_present = metadataPresentCount(photos, metadata, "path"),
	})
	if canceled(progressScope) then
		finish(progressScope)
		Logger.info("sync_canceled", { phase = "metadata_read" })
		return nil, syncCanceledMessage
	end

	setProgress(progressScope, "Planning JPEGs", planProgressStart)
	local plan, planErr = Scanner.plan(
		snapshotsFromMetadata(photos, metadata),
		state,
		config,
		Path.derivativePath,
		Exporter.fileExists,
		progressScope,
		{
			[trustedCatalogSelectionOption] = true,
			progressStart = planProgressStart,
			progressEnd = planProgressEnd,
			progressTotal = progressTotal,
		}
	)
	if not plan then
		finish(progressScope)
		return nil, planErr
	end
	Logger.info("planning_completed", {
		candidates = plan.stats.candidates,
		selected = plan.stats.selected,
		exports = #plan.exports,
		orphans = #plan.orphans,
		skipped = plan.stats.skipped,
		ignored = plan.stats.ignored,
		metadata_missing = plan.stats.metadataMissing or 0,
		metadata_mismatched = plan.stats.metadataMismatched or 0,
		capture_date_missing = plan.stats.captureDateMissing or 0,
	})
	local exportedCount = 0
	local failedCount = 0
	local deletedCount = 0

	setProgress(
		progressScope,
		"Deleting orphans 0 of " .. tostring(#plan.orphans),
		planProgressEnd
	)
	for index, orphan in ipairs(plan.orphans) do
		if canceled(progressScope) then
			finish(progressScope)
			Logger.info("sync_canceled", { phase = "deleting_orphans" })
			return nil, syncCanceledMessage
		end
		setProgress(
			progressScope,
			"Deleting orphan "
				.. tostring(index)
				.. " of "
				.. tostring(#plan.orphans),
			phaseProgress(
				planProgressEnd,
				cleanupProgressEnd,
				index - 1,
				#plan.orphans
			)
		)
		local outputPath = orphan.record and orphan.record.outputPath
		local deleteFailed = false
		if
			outputPath
			and outputPath ~= ""
			and FileUtils.fileExists(outputPath)
		then
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
	Logger.info("cleanup_completed", {
		orphaned = plan.stats.orphaned,
		deleted = deletedCount,
		failed = failedCount,
	})

	setProgress(
		progressScope,
		"Exporting 0 of " .. tostring(#plan.exports),
		cleanupProgressEnd
	)
	for index, item in ipairs(plan.exports) do
		if canceled(progressScope) then
			finish(progressScope)
			Logger.info("sync_canceled", { phase = "exporting" })
			return nil, syncCanceledMessage
		end
		setProgress(
			progressScope,
			"Exporting "
				.. tostring(index)
				.. " of "
				.. tostring(#plan.exports)
				.. ": "
				.. tostring(item.photo.fileName),
			phaseProgress(
				cleanupProgressEnd,
				exportProgressEnd,
				index - 1,
				#plan.exports
			)
		)
		item.configExportSettingsVersion = config.exportSettingsVersion
		item.configPluginVersionTimestamp = config.pluginVersionTimestamp
		item.configOutputSettingsChangedAt = config.outputSettingsChangedAt
		item.configOutputSettingsFingerprint = config.outputSettingsFingerprint
		local exportOk, exportErr = Exporter.exportItems({ item }, config, nil)
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
		progressScope:setPortionComplete(
			phaseProgress(
				cleanupProgressEnd,
				exportProgressEnd,
				index,
				#plan.exports
			),
			progressTotal
		)
	end
	Logger.info("export_completed", {
		planned = #plan.exports,
		exported = exportedCount,
		failed = failedCount,
	})

	setProgress(progressScope, "Saving sync state", saveProgressDone)
	local saveOk, saveErr = State.save(statePath(), state)
	if not saveOk then
		finish(progressScope)
		return nil, saveErr
	end

	updateLastRun(
		activeProperties,
		prefs,
		plan.stats,
		exportedCount,
		deletedCount,
		failedCount
	)
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
