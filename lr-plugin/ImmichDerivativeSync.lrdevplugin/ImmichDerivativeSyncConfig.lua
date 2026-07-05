local Config = {}

Config.stateFileName = "sync-state.lua"
Config.exportSettingsVersion = 1
Config.defaultMinRating = 3
Config.defaultLongEdgePixels = 3200
Config.defaultJpegQuality = 85

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

	return "fi.lehteni.immich-derivative-sync"
end

function Config.pluginDataDirectory()
	local LrPathUtils = maybeImport("LrPathUtils")
	if LrPathUtils and LrPathUtils.getStandardFilePath then
		return LrPathUtils.child(LrPathUtils.getStandardFilePath("appData"), pluginId())
	end

	return "."
end

function Config.ensureDefaults(properties)
	if properties.outputDirectory == nil then
		properties.outputDirectory = ""
	end
	if properties.minRating == nil then
		properties.minRating = Config.defaultMinRating
	end
	if properties.longEdgePixels == nil then
		properties.longEdgePixels = Config.defaultLongEdgePixels
	end
	if properties.jpegQuality == nil then
		properties.jpegQuality = Config.defaultJpegQuality
	end
	if properties.lastRunSummary == nil then
		properties.lastRunSummary = "Never"
	end
end

function Config.fromProperties(properties)
	Config.ensureDefaults(properties)

	local minRating = tonumber(properties.minRating) or Config.defaultMinRating
	local longEdgePixels = tonumber(properties.longEdgePixels) or Config.defaultLongEdgePixels
	local jpegQuality = tonumber(properties.jpegQuality) or Config.defaultJpegQuality

	if minRating < 0 or minRating > 5 then
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

	return {
		outputDirectory = properties.outputDirectory,
		minRating = minRating,
		longEdgePixels = longEdgePixels,
		jpegQuality = jpegQuality,
		exportSettingsVersion = Config.exportSettingsVersion,
	}
end

return Config
