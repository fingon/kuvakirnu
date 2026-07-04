local LrBinding = import "LrBinding"
local LrDialogs = import "LrDialogs"
local LrFunctionContext = import "LrFunctionContext"
local LrPathUtils = import "LrPathUtils"
local LrView = import "LrView"

local Config = require "ImmichDerivativeSync.Config"

local function browseForOutputDirectory(properties)
	local path = LrDialogs.runOpenPanel({
		title = "Choose Immich derivative output folder",
		canChooseFiles = false,
		canChooseDirectories = true,
		allowsMultipleSelection = false,
	})

	if path and path[1] then
		properties.outputDirectory = path[1]
	end
end

local function sectionsForTopOfDialog(viewFactory, properties)
	local bind = LrView.bind

	return {
		{
			title = "Derivative Sync",
			viewFactory:row {
				spacing = viewFactory:control_spacing(),
				viewFactory:static_text {
					title = "Output folder",
					width = LrView.share "labelWidth",
				},
				viewFactory:edit_field {
					value = bind "outputDirectory",
					width_in_chars = 48,
				},
				viewFactory:push_button {
					title = "Choose...",
					action = function()
						browseForOutputDirectory(properties)
					end,
				},
			},
			viewFactory:row {
				spacing = viewFactory:control_spacing(),
				viewFactory:static_text {
					title = "Minimum rating",
					width = LrView.share "labelWidth",
				},
				viewFactory:edit_field {
					value = bind "minRating",
					width_in_digits = 2,
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
				},
			},
			viewFactory:row {
				spacing = viewFactory:control_spacing(),
				viewFactory:static_text {
					title = "Last run",
					width = LrView.share "labelWidth",
				},
				viewFactory:static_text {
					title = bind "lastRunSummary",
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
	}
end

return {
	sectionsForTopOfDialog = function(viewFactory, propertyTable)
		Config.ensureDefaults(propertyTable)
		return LrFunctionContext.callWithContext("ImmichDerivativeSyncSettings", function()
			return sectionsForTopOfDialog(viewFactory, propertyTable)
		end)
	end,
}
