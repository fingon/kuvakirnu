local Config = {}

Config.stateFileName = "sync-state.lua"
Config.logFileName = "bulk-jpeg-sync.log"
Config.exportSettingsVersion = 1
Config.defaultMinRating = 3
Config.defaultLongEdgePixels = 3200
Config.defaultJpegQuality = 85
Config.defaultIncludeUnstarred = false
Config.defaultIncludeVirtualCopies = false
Config.preferenceKeys = {
	"outputDirectory",
	"minRating",
	"longEdgePixels",
	"jpegQuality",
	"includeUnstarred",
	"includeVirtualCopies",
	"lastRunAt",
	"lastRunResults",
	"lastRunCleanup",
	"lastRunDiagnostic",
}

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
		return LrPathUtils.child(LrPathUtils.getStandardFilePath("appData"), pluginId())
	end

	return "."
end

function Config.logFilePath()
	local LrPathUtils = maybeImport("LrPathUtils")
	if LrPathUtils and LrPathUtils.child then
		return LrPathUtils.child(Config.pluginDataDirectory(), Config.logFileName)
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
	properties.includeUnstarred = normalizeBoolean(properties.includeUnstarred, Config.defaultIncludeUnstarred)
	properties.includeVirtualCopies = normalizeBoolean(properties.includeVirtualCopies, Config.defaultIncludeVirtualCopies)
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
	if properties.outputDirectory == nil or properties.outputDirectory == "" then
		properties.outputDirectoryDisplay = "Not selected"
	else
		properties.outputDirectoryDisplay = properties.outputDirectory
	end
	properties.ratingSummary = Config.ratingSummary(properties)
	properties.canSync = Config.canSync(properties)
	properties.syncAvailabilitySummary = Config.syncAvailabilitySummary(properties)
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
		"orphaned %d, deleted %d, failed %d",
		stats.orphaned,
		deletedCount,
		failedCount
	)
end

function Config.lastRunDiagnostic(timestamp, stats, exportedCount, deletedCount, failedCount)
	return string.format(
		"%s candidates=%d selected=%d exported=%d skipped=%d orphaned=%d deleted=%d failed=%d ignored=%d metadata_missing=%d metadata_mismatched=%d capture_date_missing=%d",
		timestamp,
		stats.candidates,
		stats.selected,
		exportedCount,
		stats.skipped,
		stats.orphaned,
		deletedCount,
		failedCount,
		stats.ignored,
		stats.metadataMissing or 0,
		stats.metadataMismatched or 0,
		stats.captureDateMissing or 0
	)
end

function Config.updateLastRunProperties(properties, timestamp, stats, exportedCount, deletedCount, failedCount)
	properties.lastRunAt = timestamp
	properties.lastRunResults = Config.lastRunResults(stats, exportedCount)
	properties.lastRunCleanup = Config.lastRunCleanup(stats, deletedCount, failedCount)
	properties.lastRunDiagnostic = Config.lastRunDiagnostic(timestamp, stats, exportedCount, deletedCount, failedCount)
	Config.refreshDerivedProperties(properties)
end

function Config.loadPreferencesIntoProperties(prefs, properties)
	Config.ensureDefaults(prefs)
	for _, key in ipairs(Config.preferenceKeys) do
		properties[key] = prefs[key]
	end
	Config.ensureDefaults(properties)
	Config.refreshDerivedProperties(properties)
end

function Config.savePropertiesToPreferences(properties, prefs)
	Config.ensureDefaults(properties)
	for _, key in ipairs(Config.preferenceKeys) do
		prefs[key] = properties[key]
	end
	Config.refreshDerivedProperties(properties)
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

	if minRating == noStarThreshold and includeUnstarred then
		return "Selected: unstarred only"
	end
	if minRating == noStarThreshold then
		return "Selected: none"
	end
	if includeUnstarred then
		return "Selected: unstarred, " .. tostring(minRating) .. "+"
	end

	return "Selected: " .. tostring(minRating) .. "+"
end

function Config.canSync(properties)
	Config.ensureDefaults(properties)
	if properties.outputDirectory == nil or properties.outputDirectory == "" then
		return false
	end

	local minRating = tonumber(properties.minRating) or noStarThreshold
	return properties.includeUnstarred == true or (minRating >= 1 and minRating <= 5)
end

function Config.syncAvailabilitySummary(properties)
	if Config.canSync(properties) then
		return "Ready to sync."
	end
	if properties.outputDirectory == nil or properties.outputDirectory == "" then
		return "Select an output folder."
	end

	return "Select unstarred or a star threshold."
end

function Config.fromProperties(properties)
	Config.ensureDefaults(properties)

	local minRating = tonumber(properties.minRating)
	local longEdgePixels = tonumber(properties.longEdgePixels) or Config.defaultLongEdgePixels
	local jpegQuality = tonumber(properties.jpegQuality) or Config.defaultJpegQuality

	if minRating == nil then
		minRating = Config.defaultMinRating
	end
	if minRating < noStarThreshold or minRating > 5 then
		return nil, "minimum rating must be between 0 and 5"
	end
	if longEdgePixels < 1 then
		return nil, "long edge pixels must be greater than zero"
	end
	if jpegQuality < 1 or jpegQuality > 100 then
		return nil, "JPEG quality must be between 1 and 100"
	end
	if properties.outputDirectory == nil or properties.outputDirectory == "" then
		return nil, "output directory is not configured"
	end

	local config = {
		outputDirectory = properties.outputDirectory,
		includeUnstarred = properties.includeUnstarred == true,
		includeVirtualCopies = properties.includeVirtualCopies == true,
		longEdgePixels = longEdgePixels,
		jpegQuality = jpegQuality,
		exportSettingsVersion = Config.exportSettingsVersion,
	}
	if minRating ~= noStarThreshold then
		config.minRating = minRating
	end

	return config
end

return Config
