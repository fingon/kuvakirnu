local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")
local LrFunctionContext = import("LrFunctionContext")
local LrPrefs = import("LrPrefs")
local LrProgressScope = import("LrProgressScope")

local Catalog = require("BulkJpegSyncCatalog")
local Config = require("BulkJpegSyncConfig")
local Exporter = require("BulkJpegSyncExporter")
local FileUtils = require("BulkJpegSyncFileUtils")
local Incremental = require("BulkJpegSyncIncremental")
local Logger = require("BulkJpegSyncLogger")
local Path = require("BulkJpegSyncPath")
local Photo = require("BulkJpegSyncPhoto")
local Profile = require("BulkJpegSyncProfile")
local Scanner = require("BulkJpegSyncScanner")
local State = require("BulkJpegSyncState")

local Sync = {}

local running = false
local activeProgressScope = nil
local syncCanceledMessage = "sync canceled"
local trustedCatalogSelectionOption = "trustedCatalogSelection"
local skipAbsentOrphansOption = "skipAbsentOrphans"
local fullMode = "full"
local incrementalMode = "incremental"
local progressTotal = 1000
local loadProgressDone = 20
local searchProgressDone = 80
local metadataProgressDone = 160
local planProgressStart = 240
local planProgressEnd = 360
local cleanupProgressEnd = 470
local exportProgressEnd = 940
local saveProgressDone = 970

local function now()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function nowSec()
	return os.time()
end

local function canceled(progressScope)
	return progressScope
		and progressScope.isCanceled
		and progressScope:isCanceled()
end

local function finish(progressScope)
	if progressScope then
		progressScope:done()
	end
	if activeProgressScope == progressScope then
		activeProgressScope = nil
	end
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

local function loadCatalogState(profile, config, legacyCursorSec)
	local profileStatePath = Profile.statePath(profile)
	local state
	local stateErr
	local stateLoadInfo
	local loadedProfileState = false
	if
		FileUtils.fileExists(profileStatePath)
		or FileUtils.fileExists(profileStatePath .. ".bak")
	then
		loadedProfileState = true
		state, stateErr, stateLoadInfo = State.load(profileStatePath)
	else
		local legacyStatePath = Profile.legacyStatePath()
		if FileUtils.fileExists(legacyStatePath) then
			state, stateErr, stateLoadInfo = State.load(legacyStatePath)
			if state then
				state.version = 2
				state.catalogId = profile.id
				state.catalogPath = profile.catalogPath
				state.ownedOutputRoots = {
					[config.outputDirectory] = true,
				}
				state.incrementalProcessedThroughSec = legacyCursorSec or 0
				local saved, saveErr = State.save(profileStatePath, state)
				if not saved then
					return nil,
						nil,
						"failed to migrate legacy state: " .. tostring(saveErr)
				end
				local migratedPath = legacyStatePath .. ".catalog-migration.bak"
				if FileUtils.fileExists(migratedPath) then
					local deleted, deleteErr =
						FileUtils.deleteFile(migratedPath)
					if not deleted then
						return nil, nil, deleteErr
					end
				end
				local moved, moveErr =
					FileUtils.moveFile(legacyStatePath, migratedPath)
				if not moved then
					return nil, nil, moveErr
				end
				Logger.info("state_migrated_to_catalog_profile", {
					catalog = profile.catalogPath,
					profile = profile.id,
				})
			end
		else
			state = State.empty(profile)
		end
	end
	if not state then
		return nil, nil, stateErr
	end
	if state.catalogId and state.catalogId ~= profile.id then
		return nil, nil, "sync state belongs to another Lightroom catalog"
	end
	local profileStateNeedsUpgrade = loadedProfileState
		and (
			state.version == 1
			or (stateLoadInfo and stateLoadInfo.legacyOrphanedRecordsMigrated)
		)
	state.version = 2
	state.catalogId = profile.id
	state.catalogPath = profile.catalogPath
	state.ownedOutputRoots = state.ownedOutputRoots or {}
	state.ownedOutputRoots[config.outputDirectory] = true
	state.incrementalProcessedThroughSec = tonumber(
		state.incrementalProcessedThroughSec
	) or legacyCursorSec or 0
	if profileStateNeedsUpgrade then
		local saved, saveErr = State.save(profileStatePath, state)
		if not saved then
			return nil,
				nil,
				"failed to persist upgraded catalog state: " .. tostring(
					saveErr
				)
		end
	end

	return state, profileStatePath, nil, stateLoadInfo
end

local function updateLastRun(
	activeProperties,
	prefs,
	profileId,
	startedAtSec,
	processedThroughSec,
	stats,
	exportedCount,
	deletedCount,
	failedCount
)
	local timestamp = now()
	local persistedProperties = {}
	Config.loadPreferencesIntoProperties(prefs, persistedProperties, profileId)
	if processedThroughSec ~= nil then
		persistedProperties.incrementalProcessedThroughSec = processedThroughSec
	end
	Config.updateLastRunProperties(
		persistedProperties,
		timestamp,
		startedAtSec,
		stats,
		exportedCount,
		deletedCount,
		failedCount
	)
	Config.saveRuntimeToPreferences(persistedProperties, prefs, profileId)
	if activeProperties then
		if processedThroughSec ~= nil then
			activeProperties.incrementalProcessedThroughSec =
				processedThroughSec
		end
		Config.updateLastRunProperties(
			activeProperties,
			timestamp,
			startedAtSec,
			stats,
			exportedCount,
			deletedCount,
			failedCount
		)
	end
	Logger.info("sync_completed", {
		diagnostic = persistedProperties.lastRunDiagnostic,
		candidates = stats.candidates,
		selected = stats.selected,
		exported = exportedCount,
		skipped = stats.skipped,
		cleaned = stats.orphaned,
		deleted = deletedCount,
		failed = failedCount,
		ignored = stats.ignored,
		metadata_missing = stats.metadataMissing or 0,
		metadata_mismatched = stats.metadataMismatched or 0,
		capture_date_missing = stats.captureDateMissing or 0,
		videos_skipped = stats.videosSkipped or 0,
	})
end

function Sync.isRunning()
	return running
end

function Sync.requestCancel()
	if activeProgressScope and activeProgressScope.cancel then
		activeProgressScope:cancel()
	end
end

local function runCore(activeProperties, options)
	if running then
		return nil, "sync is already running"
	end
	running = true
	options = options or {}
	local mode = options.mode or fullMode
	local incremental = mode == incrementalMode
	local startedAtSec = options.startedAtSec or nowSec()

	local prefs = LrPrefs.prefsForPlugin()
	local catalog = LrApplication.activeCatalog()
	local profile, profileErr = Profile.forCatalog(catalog)
	if not profile then
		running = false
		return nil, profileErr
	end
	local properties = activeProperties
	if not properties then
		properties = {}
		Config.loadPreferencesIntoProperties(prefs, properties, profile.id)
	end
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
		smart_collection_filter = config.smartCollectionFilter,
		long_edge_pixels = config.longEdgePixels,
		jpeg_quality = config.jpegQuality,
		mode = mode,
	})

	local progressScope = LrProgressScope({ title = "Bulk JPEG Sync" })
	activeProgressScope = progressScope
	setProgress(progressScope, "Loading sync state", loadProgressDone)
	local state, runStatePath, stateErr, stateLoadInfo = loadCatalogState(
		profile,
		config,
		tonumber(properties.incrementalProcessedThroughSec)
			or tonumber(properties.lastSuccessfulSyncStartedAtSec)
			or 0
	)
	if not state then
		finish(progressScope)
		return nil, stateErr
	end
	if stateLoadInfo and stateLoadInfo.recoveredFromBackup then
		Logger.warn("state_recovered_from_backup", {
			catalog = profile.catalogPath,
			error = stateLoadInfo.primaryError,
		})
	end
	if stateLoadInfo and stateLoadInfo.legacyOrphanedRecordsMigrated then
		Logger.info("legacy_orphaned_state_records_migrated", {
			catalog = profile.catalogPath,
			count = stateLoadInfo.legacyOrphanedRecordsMigrated,
			profile = profile.id,
		})
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
	local photos = {}
	local incrementalLowerBoundSec = state.incrementalProcessedThroughSec
	local incrementalWindow = Incremental.window(
		incrementalLowerBoundSec,
		startedAtSec,
		Config.incrementalEditCooldownSec
	)
	local incrementalUpperBoundSec = incrementalWindow.upperBoundSec
	local incrementalWindowReady = not incremental or incrementalWindow.ready
	local candidateSearchOptions = nil
	if incremental and incrementalWindowReady then
		candidateSearchOptions = {
			editedAfterSec = incrementalLowerBoundSec,
			editedBeforeSec = incrementalUpperBoundSec,
		}
	end
	if
		incrementalWindowReady
		and (config.minRating ~= nil or config.includeUnstarred)
	then
		local ratingPhotos, photosErr =
			Catalog.findCandidates(catalog, config, candidateSearchOptions)
		if not ratingPhotos then
			finish(progressScope)
			return nil, photosErr
		end
		photos = ratingPhotos
	end
	if
		incrementalWindowReady
		and config.smartCollectionFilter ~= nil
		and config.smartCollectionFilter ~= ""
	then
		local matchingCollections = Catalog.getMatchingSmartCollections(
			catalog,
			config.smartCollectionFilter
		)
		if
			#matchingCollections == 0
			and config.minRating == nil
			and not config.includeUnstarred
		then
			finish(progressScope)
			return nil,
				"no smart collections match filter: "
					.. config.smartCollectionFilter
		end
		local scPhotos =
			Catalog.photosFromSmartCollections(catalog, matchingCollections)
		photos = Catalog.unionPhotoLists(photos, scPhotos)
	end
	Logger.info("catalog_search_completed", {
		candidates = #photos,
		min_rating = config.minRating or 0,
		include_unstarred = config.includeUnstarred,
		smart_collection_filter = config.smartCollectionFilter,
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

	local snapshots = snapshotsFromMetadata(photos, metadata)
	if incremental then
		snapshots = Incremental.filter(snapshots, incrementalWindow)
		Logger.info("incremental_filter_completed", {
			input = #photos,
			selected = #snapshots,
			lower_bound_sec = incrementalLowerBoundSec,
			upper_bound_sec = incrementalUpperBoundSec,
		})
	end

	setProgress(progressScope, "Planning JPEGs", planProgressStart)
	local plan, planErr = Scanner.plan(
		snapshots,
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
			[skipAbsentOrphansOption] = incremental,
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
		videos_skipped = plan.stats.videosSkipped or 0,
	})
	local exportedCount = 0
	local failedCount = 0
	local deletedCount = 0

	if incremental then
		setProgress(
			progressScope,
			"Skipping cleanup in incremental sync",
			cleanupProgressEnd
		)
	else
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
			local ownedOutputPath = false
			for outputRoot in pairs(state.ownedOutputRoots) do
				if Path.isWithin(outputPath, outputRoot) then
					ownedOutputPath = true
					break
				end
			end
			if
				outputPath
				and outputPath ~= ""
				and FileUtils.fileExists(outputPath)
			then
				if ownedOutputPath then
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
				else
					deleteFailed = true
					failedCount = failedCount + 1
					Logger.error("orphan_delete_refused", {
						photo = orphan.identifier or "unknown",
						output = outputPath,
						error = "output is outside catalog-owned roots",
					})
				end
			end
			if not deleteFailed then
				local identifier = orphan.identifier or orphan.photo.identifier
				State.deleteRecord(state, identifier)
			end
		end
	end
	Logger.info("cleanup_completed", {
		cleaned = plan.stats.orphaned,
		deleted = deletedCount,
		failed = failedCount,
	})

	setProgress(
		progressScope,
		"Exporting 0 of " .. tostring(#plan.exports),
		cleanupProgressEnd
	)
	local dateGroups = {}
	local dateOrder = {}
	for _, item in ipairs(plan.exports) do
		local date = item.photo.captureTime or ""
		if not dateGroups[date] then
			dateGroups[date] = {}
			dateOrder[#dateOrder + 1] = date
		end
		dateGroups[date][#dateGroups[date] + 1] = item
	end
	local overallIndex = 0
	for _, date in ipairs(dateOrder) do
		local items = dateGroups[date]
		if canceled(progressScope) then
			finish(progressScope)
			Logger.info("sync_canceled", { phase = "exporting" })
			return nil, syncCanceledMessage
		end
		local rangeEnd = overallIndex + #items
		local dateLabel = ""
		if date ~= "" then
			dateLabel = " (" .. date .. ")"
		end
		setProgress(
			progressScope,
			"Exporting "
				.. tostring(overallIndex + 1)
				.. "-"
				.. tostring(rangeEnd)
				.. " of "
				.. tostring(#plan.exports)
				.. dateLabel,
			phaseProgress(
				cleanupProgressEnd,
				exportProgressEnd,
				overallIndex,
				#plan.exports
			)
		)
		for _, item in ipairs(items) do
			item.configExportSettingsVersion = config.exportSettingsVersion
			item.configPluginVersionTimestamp = config.pluginVersionTimestamp
			item.configOutputSettingsChangedAt = config.outputSettingsChangedAt
			item.configOutputSettingsFingerprint =
				config.outputSettingsFingerprint
		end
		local outcomes, exportErr =
			Exporter.exportItems(items, config, progressScope)
		local exportCanceled = false
		if outcomes then
			for _, item in ipairs(items) do
				local outcome = outcomes[item]
				if outcome and outcome.status == "exported" then
					State.markExported(state, item, item.outputPath, now())
					exportedCount = exportedCount + 1
				elseif outcome and outcome.status == "canceled" then
					exportCanceled = true
				else
					local itemErr = outcome and outcome.error
						or "export outcome is missing"
					State.markFailed(state, item, itemErr)
					failedCount = failedCount + 1
					Logger.error("photo_export_failed", {
						photo = item.photo.identifier,
						output = item.outputPath,
						error = itemErr,
					})
				end
			end
		else
			for _, item in ipairs(items) do
				State.markFailed(state, item, exportErr)
				failedCount = failedCount + 1
				Logger.error("photo_export_failed", {
					photo = item.photo.identifier,
					output = item.outputPath,
					error = exportErr,
				})
			end
		end
		if exportCanceled then
			local partialSaveOk, partialSaveErr =
				State.save(runStatePath, state)
			finish(progressScope)
			Logger.info("sync_canceled", { phase = "exporting" })
			if not partialSaveOk then
				return nil,
					syncCanceledMessage
						.. "; failed to save partial state: "
						.. tostring(partialSaveErr)
			end
			return nil, syncCanceledMessage
		end
		overallIndex = rangeEnd
		progressScope:setPortionComplete(
			phaseProgress(
				cleanupProgressEnd,
				exportProgressEnd,
				overallIndex,
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
	local processedThroughSec = failedCount == 0
			and (incremental and incrementalUpperBoundSec or startedAtSec)
		or nil
	if processedThroughSec ~= nil then
		state.incrementalProcessedThroughSec = processedThroughSec
	end
	local saveOk, saveErr = State.save(runStatePath, state)
	if not saveOk then
		finish(progressScope)
		return nil, saveErr
	end

	updateLastRun(
		activeProperties,
		prefs,
		profile.id,
		startedAtSec,
		processedThroughSec,
		plan.stats,
		exportedCount,
		deletedCount,
		failedCount
	)
	if failedCount > 0 and not options.suppressDialogs then
		LrDialogs.message(
			"Bulk JPEG Sync completed with failures",
			"Some photos failed to export or clean up. Check the Lightroom plugin log and state file.",
			"warning"
		)
	end

	finish(progressScope)

	return true
end

function Sync.run(activeProperties, options)
	local callOk, runOk, runErr = LrFunctionContext.pcallWithContext(
		"BulkJpegSyncRun",
		function(context)
			context:addCleanupHandler(function()
				if activeProgressScope then
					activeProgressScope:done()
					activeProgressScope = nil
				end
				running = false
			end)
			return runCore(activeProperties, options)
		end
	)
	if not callOk then
		return nil, "unexpected sync failure: " .. tostring(runOk)
	end

	return runOk, runErr
end

function Sync.runIncremental(activeProperties, options)
	options = options or {}
	options.mode = incrementalMode
	return Sync.run(activeProperties, options)
end

return Sync
