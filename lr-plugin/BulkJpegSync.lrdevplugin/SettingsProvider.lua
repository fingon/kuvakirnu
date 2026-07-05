local LrDialogs = import "LrDialogs"
local LrFunctionContext = import "LrFunctionContext"
local LrPathUtils = import "LrPathUtils"
local LrPrefs = import "LrPrefs"
local LrView = import "LrView"

local Config = require "BulkJpegSyncConfig"
local SyncLauncher = require "BulkJpegSyncSyncLauncher"

local includeUnstarredTitle = "Include unstarred"
local includeVirtualCopiesTitle = "Include virtual copies"

local function refreshDerivedProperties(properties)
	Config.refreshDerivedProperties(properties)
end

local function saveProperties(properties)
	Config.savePropertiesToPreferences(properties, LrPrefs.prefsForPlugin())
end

local function syncNow(properties)
	saveProperties(properties)
	refreshDerivedProperties(properties)
	if properties.canSync then
		SyncLauncher.runAsync(properties)
	end
end

local function browseForOutputDirectory(properties)
	local path = LrDialogs.runOpenPanel({
		title = "Choose Bulk JPEG output folder",
		canChooseFiles = false,
		canChooseDirectories = true,
		allowsMultipleSelection = false,
	})

	if path and path[1] then
		properties.outputDirectory = path[1]
		saveProperties(properties)
		refreshDerivedProperties(properties)
	end
end

local function clearOutputDirectory(properties)
	properties.outputDirectory = ""
	saveProperties(properties)
	refreshDerivedProperties(properties)
end

local function toggleMinRating(properties, rating)
	properties.minRating = Config.toggleMinRating(properties.minRating, rating)
	saveProperties(properties)
	refreshDerivedProperties(properties)
end

local function toggleUnstarred(properties)
	properties.includeUnstarred = not properties.includeUnstarred
	saveProperties(properties)
	refreshDerivedProperties(properties)
end

local function observeProperty(context, properties, key)
	local observer = function()
		saveProperties(properties)
		refreshDerivedProperties(properties)
	end
	properties:addObserver(key, observer)
	context:addCleanupHandler(function()
		properties:removeObserver(key, observer)
	end)
end

local function observePreferences(context, properties)
	observeProperty(context, properties, "includeVirtualCopies")
	observeProperty(context, properties, "longEdgePixels")
	observeProperty(context, properties, "jpegQuality")
end

local function sectionsForTopOfDialog(viewFactory, properties)
	local bind = LrView.bind

	return {
		{
			title = "Bulk JPEG Sync",
			viewFactory:column {
				bind_to_object = properties,
				spacing = viewFactory:control_spacing(),
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Output folder",
						width = LrView.share "labelWidth",
					},
					viewFactory:push_button {
						title = "Choose...",
						action = function()
							browseForOutputDirectory(properties)
						end,
					},
					viewFactory:push_button {
						title = "Clear",
						action = function()
							clearOutputDirectory(properties)
						end,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "",
						width = LrView.share "labelWidth",
					},
					viewFactory:static_text {
						title = bind "outputDirectoryDisplay",
						width_in_chars = 34,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Ratings",
						width = LrView.share "labelWidth",
					},
					viewFactory:push_button {
						title = includeUnstarredTitle,
						action = function()
							toggleUnstarred(properties)
						end,
					},
					viewFactory:push_button {
						title = "★",
						action = function()
							toggleMinRating(properties, 1)
						end,
					},
					viewFactory:push_button {
						title = "★★",
						action = function()
							toggleMinRating(properties, 2)
						end,
					},
					viewFactory:push_button {
						title = "★★★",
						action = function()
							toggleMinRating(properties, 3)
						end,
					},
					viewFactory:push_button {
						title = "★★★★",
						action = function()
							toggleMinRating(properties, 4)
						end,
					},
					viewFactory:push_button {
						title = "★★★★★",
						action = function()
							toggleMinRating(properties, 5)
						end,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "",
						width = LrView.share "labelWidth",
					},
					viewFactory:static_text {
						title = bind "ratingSummary",
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Virtual copies",
						width = LrView.share "labelWidth",
					},
					viewFactory:checkbox {
						title = includeVirtualCopiesTitle,
						value = bind "includeVirtualCopies",
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Long edge pixels",
						width = LrView.share "labelWidth",
					},
					viewFactory:edit_field {
						value = bind "longEdgePixels",
						width_in_digits = 5,
						immediate = true,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "JPEG quality",
						width = LrView.share "labelWidth",
					},
					viewFactory:edit_field {
						value = bind "jpegQuality",
						width_in_digits = 3,
						immediate = true,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Last run",
						width = LrView.share "labelWidth",
					},
					viewFactory:static_text {
						title = bind "lastRunAt",
						width_in_chars = 24,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Results",
						width = LrView.share "labelWidth",
					},
					viewFactory:static_text {
						title = bind "lastRunResults",
						width_in_chars = 34,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Cleanup",
						width = LrView.share "labelWidth",
					},
					viewFactory:static_text {
						title = bind "lastRunCleanup",
						width_in_chars = 34,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Diagnostic",
						width = LrView.share "labelWidth",
					},
					viewFactory:static_text {
						title = bind "lastRunDiagnostic",
						width_in_chars = 72,
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "Sync",
						width = LrView.share "labelWidth",
					},
					viewFactory:push_button {
						title = "Sync Now",
						enabled = bind "canSync",
						action = function()
							syncNow(properties)
						end,
					},
					viewFactory:static_text {
						title = bind "syncAvailabilitySummary",
					},
				},
				viewFactory:row {
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text {
						title = "State file",
						width = LrView.share "labelWidth",
					},
					viewFactory:static_text {
						title = LrPathUtils.child(Config.pluginDataDirectory(), Config.stateFileName),
					},
				},
			},
		},
	}
end

return {
	sectionsForTopOfDialog = function(viewFactory, propertyTable)
		return LrFunctionContext.callWithContext("BulkJpegSyncSettings", function(context)
			Config.loadPreferencesIntoProperties(LrPrefs.prefsForPlugin(), propertyTable)
			observePreferences(context, propertyTable)
			return sectionsForTopOfDialog(viewFactory, propertyTable)
		end)
	end,
}
