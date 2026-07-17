local Config = {}

Config.stateFileName = "sync-state.lua"
Config.logFileName = "bulk-jpeg-sync.log"
Config.exportSettingsVersion = 2
Config.pluginVersionTimestamp = "2026-07-05T07:00:00Z"
Config.outputSettingsChangedAt = "2026-07-05T07:00:00Z"
Config.defaultMinRating = 3
Config.defaultLongEdgePixels = 3200
Config.defaultJpegQuality = 85
Config.defaultIncludeUnstarred = false
Config.defaultIncludeVirtualCopies = false
Config.defaultSmartCollectionFilter = ""
Config.backgroundSyncNever = "never"
Config.backgroundSyncHourly = "hourly"
Config.backgroundSyncDaily = "daily"
Config.defaultBackgroundSyncInterval = Config.backgroundSyncNever
Config.backgroundSyncHourlySec = 60 * 60
Config.backgroundSyncDailySec = 24 * 60 * 60
Config.incrementalEditCooldownSec = 5 * 60
Config.editablePreferenceKeys = {
	"outputDirectory",
	"minRating",
	"longEdgePixels",
	"jpegQuality",
	"includeUnstarred",
	"includeVirtualCopies",
	"smartCollectionFilter",
	"backgroundSyncInterval",
}
Config.runtimePreferenceKeys = {
	"lastSuccessfulSyncStartedAtSec",
	"incrementalProcessedThroughSec",
	"lastBackgroundAttemptAtSec",
	"lastBackgroundFullSyncAtSec",
	"lastRunAt",
	"lastRunResults",
	"lastRunCleanup",
	"lastRunDiagnostic",
}
Config.preferenceKeys = {}
for _, key in ipairs(Config.editablePreferenceKeys) do
	Config.preferenceKeys[#Config.preferenceKeys + 1] = key
end

local catalogPreferencesMigratedKey = "catalog.preferences.migrated"

local function profilePreferenceKey(profileId, key)
	return "catalog." .. tostring(profileId) .. "." .. key
end
for _, key in ipairs(Config.runtimePreferenceKeys) do
	Config.preferenceKeys[#Config.preferenceKeys + 1] = key
end

local noStarThreshold = 0

local function blank(value)
	return value == nil or value == ""
end

local function normalizeBoolean(value, defaultValue)
	if value == true then
		return true
	end
	if value == false then
		return false
	end

	return defaultValue
end

local function normalizeBackgroundSyncInterval(value)
	if
		value == Config.backgroundSyncHourly
		or value == Config.backgroundSyncDaily
		or value == Config.backgroundSyncNever
	then
		return value
	end

	return Config.defaultBackgroundSyncInterval
end

local function normalizeNumber(value, defaultValue)
	local number = tonumber(value)
	if number == nil then
		return defaultValue
	end

	return number
end

local function maybeImport(name)
	if type(import) ~= "function" then
		return nil
	end

	local ok, module = pcall(import, name)
	if ok then
		return module
	end

	return nil
end

local function pluginId()
	local LrPrefs = maybeImport("LrPrefs")
	if LrPrefs and LrPrefs.prefsForPlugin then
		local prefs = LrPrefs.prefsForPlugin()
		if prefs and prefs._PLUGIN then
			return prefs._PLUGIN.id
		end
	end

	return "fi.iki.fingon.bulk-jpeg-sync"
end

function Config.pluginDataDirectory()
	local LrPathUtils = maybeImport("LrPathUtils")
	if LrPathUtils and LrPathUtils.getStandardFilePath then
		return LrPathUtils.child(
			LrPathUtils.getStandardFilePath("appData"),
			pluginId()
		)
	end

	return "."
end

function Config.logFilePath()
	local LrPathUtils = maybeImport("LrPathUtils")
	if LrPathUtils and LrPathUtils.child then
		return LrPathUtils.child(
			Config.pluginDataDirectory(),
			Config.logFileName
		)
	end

	return Config.pluginDataDirectory() .. "/" .. Config.logFileName
end

function Config.ensureDefaults(properties)
	if properties.outputDirectory == nil then
		properties.outputDirectory = ""
	end
	if blank(properties.minRating) then
		properties.minRating = Config.defaultMinRating
	end
	if blank(properties.longEdgePixels) then
		properties.longEdgePixels = Config.defaultLongEdgePixels
	end
	if blank(properties.jpegQuality) then
		properties.jpegQuality = Config.defaultJpegQuality
	end
	properties.includeUnstarred = normalizeBoolean(
		properties.includeUnstarred,
		Config.defaultIncludeUnstarred
	)
	properties.includeVirtualCopies = normalizeBoolean(
		properties.includeVirtualCopies,
		Config.defaultIncludeVirtualCopies
	)
	if blank(properties.smartCollectionFilter) then
		properties.smartCollectionFilter = Config.defaultSmartCollectionFilter
	end
	properties.backgroundSyncInterval =
		normalizeBackgroundSyncInterval(properties.backgroundSyncInterval)
	properties.lastSuccessfulSyncStartedAtSec =
		normalizeNumber(properties.lastSuccessfulSyncStartedAtSec, 0)
	properties.incrementalProcessedThroughSec =
		normalizeNumber(properties.incrementalProcessedThroughSec, 0)
	properties.lastBackgroundAttemptAtSec =
		normalizeNumber(properties.lastBackgroundAttemptAtSec, 0)
	properties.lastBackgroundFullSyncAtSec =
		normalizeNumber(properties.lastBackgroundFullSyncAtSec, 0)
	if properties.lastRunAt == nil then
		properties.lastRunAt = "Never"
	end
	if properties.lastRunResults == nil then
		properties.lastRunResults = "Not run"
	end
	if properties.lastRunCleanup == nil then
		properties.lastRunCleanup = "Not run"
	end
	if properties.lastRunDiagnostic == nil then
		properties.lastRunDiagnostic = "Never"
	end
end

function Config.refreshDerivedProperties(properties)
	if
		properties.outputDirectory == nil
		or properties.outputDirectory == ""
	then
		properties.outputDirectoryDisplay = "Not selected"
	else
		properties.outputDirectoryDisplay = properties.outputDirectory
	end
	properties.ratingSummary = Config.ratingSummary(properties)
	properties.smartCollectionSummary =
		Config.smartCollectionSummary(properties)
	properties.canSync = Config.canSync(properties)
	properties.syncAvailabilitySummary =
		Config.syncAvailabilitySummary(properties)
	properties.backgroundSyncSummary =
		Config.backgroundSyncSummary(properties.backgroundSyncInterval)
	properties.logFilePath = Config.logFilePath()
end

function Config.lastRunResults(stats, exportedCount)
	return string.format(
		"candidates %d, selected %d, exported %d, skipped %d",
		stats.candidates,
		stats.selected,
		exportedCount,
		stats.skipped
	)
end

function Config.lastRunCleanup(stats, deletedCount, failedCount)
	return string.format(
		"cleaned %d, deleted %d, failed %d",
		stats.orphaned,
		deletedCount,
		failedCount
	)
end

function Config.lastRunDiagnostic(
	timestamp,
	stats,
	exportedCount,
	deletedCount,
	failedCount
)
	return string.format(
		"%s candidates=%d selected=%d exported=%d skipped=%d cleaned=%d deleted=%d failed=%d ignored=%d videos_skipped=%d metadata_missing=%d metadata_mismatched=%d capture_date_missing=%d",
		timestamp,
		stats.candidates,
		stats.selected,
		exportedCount,
		stats.skipped,
		stats.orphaned,
		deletedCount,
		failedCount,
		stats.ignored,
		stats.videosSkipped or 0,
		stats.metadataMissing or 0,
		stats.metadataMismatched or 0,
		stats.captureDateMissing or 0
	)
end

function Config.updateLastRunProperties(
	properties,
	timestamp,
	startedAtSec,
	stats,
	exportedCount,
	deletedCount,
	failedCount
)
	properties.lastRunAt = timestamp
	properties.lastSuccessfulSyncStartedAtSec = startedAtSec
	properties.lastRunResults = Config.lastRunResults(stats, exportedCount)
	properties.lastRunCleanup =
		Config.lastRunCleanup(stats, deletedCount, failedCount)
	properties.lastRunDiagnostic = Config.lastRunDiagnostic(
		timestamp,
		stats,
		exportedCount,
		deletedCount,
		failedCount
	)
	Config.refreshDerivedProperties(properties)
end

function Config.loadPreferencesIntoProperties(prefs, properties, profileId)
	if profileId == nil then
		Config.ensureDefaults(prefs)
		for _, key in ipairs(Config.preferenceKeys) do
			properties[key] = prefs[key]
		end
	else
		local initializedKey = profilePreferenceKey(profileId, "initialized")
		local adoptLegacy = prefs[initializedKey] ~= true
			and prefs[catalogPreferencesMigratedKey] ~= true
		if adoptLegacy then
			Config.ensureDefaults(prefs)
		end
		for _, key in ipairs(Config.preferenceKeys) do
			local scopedKey = profilePreferenceKey(profileId, key)
			local value = prefs[scopedKey]
			if value == nil and adoptLegacy then
				value = prefs[key]
			end
			properties[key] = value
			if value ~= nil then
				prefs[scopedKey] = value
			end
		end
		prefs[initializedKey] = true
		if adoptLegacy then
			prefs[catalogPreferencesMigratedKey] = true
		end
	end
	Config.ensureDefaults(properties)
	Config.refreshDerivedProperties(properties)
end

function Config.savePropertiesToPreferences(properties, prefs, profileId)
	Config.ensureDefaults(properties)
	for _, key in ipairs(Config.editablePreferenceKeys) do
		local targetKey = profileId and profilePreferenceKey(profileId, key)
			or key
		prefs[targetKey] = properties[key]
	end
	Config.refreshDerivedProperties(properties)
end

function Config.saveRuntimeToPreferences(properties, prefs, profileId)
	Config.ensureDefaults(properties)
	for _, key in ipairs(Config.runtimePreferenceKeys) do
		local targetKey = profileId and profilePreferenceKey(profileId, key)
			or key
		prefs[targetKey] = properties[key]
	end
end

function Config.profilePreferenceKey(profileId, key)
	return profilePreferenceKey(profileId, key)
end

function Config.toggleMinRating(currentMinRating, selectedRating)
	local current = tonumber(currentMinRating) or noStarThreshold
	local selected = tonumber(selectedRating)
	if selected == nil or selected < 1 or selected > 5 then
		return current
	end
	if current == selected then
		return noStarThreshold
	end

	return selected
end

function Config.ratingSummary(properties)
	local minRating = tonumber(properties.minRating) or noStarThreshold
	local includeUnstarred = properties.includeUnstarred == true
	local hasSmartCollection = not blank(properties.smartCollectionFilter)

	local starParts = {}
	if minRating == noStarThreshold and includeUnstarred then
		starParts[#starParts + 1] = "unstarred only"
	elseif minRating ~= noStarThreshold then
		if includeUnstarred then
			starParts[#starParts + 1] = "unstarred"
		end
		starParts[#starParts + 1] = tostring(minRating) .. "+"
	end

	local parts = {}
	if #starParts > 0 then
		parts[#parts + 1] = table.concat(starParts, ", ")
	end
	if hasSmartCollection then
		local matchCount = properties.smartCollectionMatchCount
		if matchCount then
			parts[#parts + 1] = "smart collection '"
				.. properties.smartCollectionFilter
				.. "' ("
				.. tostring(matchCount)
				.. " matching)"
		else
			parts[#parts + 1] = "smart collection '"
				.. properties.smartCollectionFilter
				.. "'"
		end
	end

	if #parts == 0 then
		return "Selected: none"
	end

	return "Selected: " .. table.concat(parts, " + ")
end

function Config.backgroundSyncSummary(interval)
	interval = normalizeBackgroundSyncInterval(interval)
	if interval == Config.backgroundSyncHourly then
		return "Background sync: every hour"
	end
	if interval == Config.backgroundSyncDaily then
		return "Background sync: every day"
	end

	return "Background sync: never"
end

function Config.backgroundSyncIntervalSec(interval)
	interval = normalizeBackgroundSyncInterval(interval)
	if interval == Config.backgroundSyncHourly then
		return Config.backgroundSyncHourlySec
	end
	if interval == Config.backgroundSyncDaily then
		return Config.backgroundSyncDailySec
	end

	return nil
end

function Config.smartCollectionSummary(properties)
	local filter = properties.smartCollectionFilter or ""
	local matchCount = properties.smartCollectionMatchCount
	if properties.smartCollectionLookupError then
		return "Smart collection lookup failed: "
			.. tostring(properties.smartCollectionLookupError)
	end
	if properties.smartCollectionLookupPending then
		return "Searching for smart collections..."
	end
	if filter == "" then
		return "Type name to filter by smart collection"
	end
	if matchCount == nil then
		return "Smart collection filter: '" .. filter .. "'"
	end
	return "Smart collection filter: '"
		.. filter
		.. "' ("
		.. tostring(matchCount)
		.. " matching)"
end

function Config.canSync(properties)
	Config.ensureDefaults(properties)
	if
		properties.outputDirectory == nil
		or properties.outputDirectory == ""
	then
		return false
	end

	local minRating = tonumber(properties.minRating) or noStarThreshold
	local hasStarConfig = properties.includeUnstarred == true
		or (minRating >= 1 and minRating <= 5)
	local hasSmartCollectionConfig = not blank(properties.smartCollectionFilter)
	return hasStarConfig or hasSmartCollectionConfig
end

function Config.syncAvailabilitySummary(properties)
	if Config.canSync(properties) then
		return "Ready to sync."
	end
	if
		properties.outputDirectory == nil
		or properties.outputDirectory == ""
	then
		return "Select an output folder."
	end

	return "Select unstarred, a star threshold, or a smart collection filter."
end

function Config.outputSettingsFingerprint(config)
	return table.concat({
		"exportSettingsVersion=" .. tostring(
			config.exportSettingsVersion or Config.exportSettingsVersion
		),
		"longEdgePixels=" .. tostring(config.longEdgePixels),
		"jpegQuality=" .. tostring(config.jpegQuality),
	}, "|")
end

function Config.fromProperties(properties)
	Config.ensureDefaults(properties)

	local minRating = tonumber(properties.minRating)
	local longEdgePixels = tonumber(properties.longEdgePixels)
	local jpegQuality = tonumber(properties.jpegQuality)

	if minRating == nil then
		return nil, "minimum rating must be a number between 0 and 5"
	end
	if longEdgePixels == nil then
		return nil, "long edge pixels must be a positive whole number"
	end
	if jpegQuality == nil then
		return nil, "JPEG quality must be a whole number between 1 and 100"
	end
	if minRating < noStarThreshold or minRating > 5 then
		return nil, "minimum rating must be between 0 and 5"
	end
	if minRating % 1 ~= 0 then
		return nil, "minimum rating must be a whole number between 0 and 5"
	end
	if longEdgePixels < 1 then
		return nil, "long edge pixels must be greater than zero"
	end
	if longEdgePixels % 1 ~= 0 then
		return nil, "long edge pixels must be a positive whole number"
	end
	if jpegQuality < 1 or jpegQuality > 100 then
		return nil, "JPEG quality must be between 1 and 100"
	end
	if jpegQuality % 1 ~= 0 then
		return nil, "JPEG quality must be a whole number between 1 and 100"
	end
	if
		properties.outputDirectory == nil
		or properties.outputDirectory == ""
	then
		return nil, "output directory is not configured"
	end
	local hasStarSelection = properties.includeUnstarred == true
		or (minRating >= 1 and minRating <= 5)
	local hasSmartCollectionSelection =
		not blank(properties.smartCollectionFilter)
	if not hasStarSelection and not hasSmartCollectionSelection then
		return nil,
			"select unstarred, a star threshold, or a smart collection filter"
	end

	local config = {
		outputDirectory = properties.outputDirectory,
		includeUnstarred = properties.includeUnstarred == true,
		includeVirtualCopies = properties.includeVirtualCopies == true,
		smartCollectionFilter = properties.smartCollectionFilter or "",
		longEdgePixels = longEdgePixels,
		jpegQuality = jpegQuality,
		exportSettingsVersion = Config.exportSettingsVersion,
		pluginVersionTimestamp = Config.pluginVersionTimestamp,
		outputSettingsChangedAt = Config.outputSettingsChangedAt,
	}
	config.outputSettingsFingerprint = Config.outputSettingsFingerprint(config)
	if minRating ~= noStarThreshold then
		config.minRating = minRating
	end

	return config
end

return Config
