local LrApplication = import("LrApplication")
local LrDialogs = import("LrDialogs")
local LrFunctionContext = import("LrFunctionContext")
local LrPathUtils = import("LrPathUtils")
local LrPrefs = import("LrPrefs")
local LrTasks = import("LrTasks")
local LrView = import("LrView")

local Catalog = require("BulkJpegSyncCatalog")
local Config = require("BulkJpegSyncConfig")
local Logger = require("BulkJpegSyncLogger")
local Profile = require("BulkJpegSyncProfile")
local SyncLauncher = require("BulkJpegSyncSyncLauncher")

local includeUnstarredTitle = "Include unstarred"
local includeVirtualCopiesTitle = "Include virtual copies"
local smartCollectionDebounceSec = 0.3
local smartCollectionLookupStates = setmetatable({}, { __mode = "k" })

local function refreshDerivedProperties(properties)
	Config.refreshDerivedProperties(properties)
	if properties.catalogProfileId == nil then
		properties.canSync = false
		properties.syncAvailabilitySummary = "Loading catalog settings..."
	end
end

local function saveProperties(properties)
	if properties.catalogProfileId == nil then
		return nil, "catalog settings are still loading"
	end
	local prefs = LrPrefs.prefsForPlugin()
	Config.savePropertiesToPreferences(
		properties,
		prefs,
		properties.catalogProfileId
	)
	return true
end

local function syncNow(properties)
	local saved, saveErr = saveProperties(properties)
	if not saved then
		properties.syncAvailabilitySummary = tostring(saveErr)
		return
	end
	refreshDerivedProperties(properties)
	if properties.canSync then
		local launched, launchErr = SyncLauncher.runAsync(properties)
		if not launched then
			properties.syncAvailabilitySummary = tostring(launchErr)
		end
	end
end

local function syncChanges(properties)
	local saved, saveErr = saveProperties(properties)
	if not saved then
		properties.syncAvailabilitySummary = tostring(saveErr)
		return
	end
	refreshDerivedProperties(properties)
	if properties.canSync then
		local launched, launchErr = SyncLauncher.runIncrementalAsync(properties)
		if not launched then
			properties.syncAvailabilitySummary = tostring(launchErr)
		end
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

local function scheduleSmartCollectionLookup(properties, value)
	local lookupState = smartCollectionLookupStates[properties]
	if not lookupState then
		lookupState = { generation = 0, running = false, closed = false }
		smartCollectionLookupStates[properties] = lookupState
	end
	lookupState.generation = lookupState.generation + 1
	lookupState.value = value or ""
	properties.smartCollectionLookupError = nil
	if lookupState.value == "" then
		properties.smartCollectionMatchCount = nil
		properties.smartCollectionLookupPending = false
		refreshDerivedProperties(properties)
	else
		properties.smartCollectionLookupPending = true
		refreshDerivedProperties(properties)
	end
	if lookupState.running or lookupState.closed then
		return
	end

	lookupState.running = true
	LrFunctionContext.postAsyncTaskWithContext(
		"BulkJpegSyncSmartCollectionLookup",
		function(context)
			context:addCleanupHandler(function()
				lookupState.running = false
			end)
			context:addFailureHandler(function(_, err)
				properties.smartCollectionLookupPending = false
				properties.smartCollectionLookupError = tostring(err)
				refreshDerivedProperties(properties)
				Logger.error("smart_collection_lookup_failed", {
					error = tostring(err),
				})
			end)
			while not lookupState.closed do
				local generation = lookupState.generation
				local filter = lookupState.value
				if filter == "" then
					return
				end
				LrTasks.sleep(smartCollectionDebounceSec)
				if generation == lookupState.generation then
					local catalog = LrApplication.activeCatalog()
					local matching =
						Catalog.getMatchingSmartCollections(catalog, filter)
					if generation == lookupState.generation then
						properties.smartCollectionMatchCount = #matching
						properties.smartCollectionLookupPending = false
						properties.smartCollectionLookupError = nil
						refreshDerivedProperties(properties)
						return
					end
				end
			end
		end
	)
end

local function sectionsForTopOfDialog(viewFactory, properties)
	local bind = LrView.bind

	return {
		{
			title = "Bulk JPEG Sync",
			viewFactory:column({
				bind_to_object = properties,
				spacing = viewFactory:control_spacing(),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Output folder",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:push_button({
						title = "Choose...",
						action = function()
							browseForOutputDirectory(properties)
						end,
					}),
					viewFactory:push_button({
						title = "Clear",
						action = function()
							clearOutputDirectory(properties)
						end,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = bind("outputDirectoryDisplay"),
						width_in_chars = 34,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Ratings",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:push_button({
						title = includeUnstarredTitle,
						action = function()
							toggleUnstarred(properties)
						end,
					}),
					viewFactory:push_button({
						title = "★",
						action = function()
							toggleMinRating(properties, 1)
						end,
					}),
					viewFactory:push_button({
						title = "★★",
						action = function()
							toggleMinRating(properties, 2)
						end,
					}),
					viewFactory:push_button({
						title = "★★★",
						action = function()
							toggleMinRating(properties, 3)
						end,
					}),
					viewFactory:push_button({
						title = "★★★★",
						action = function()
							toggleMinRating(properties, 4)
						end,
					}),
					viewFactory:push_button({
						title = "★★★★★",
						action = function()
							toggleMinRating(properties, 5)
						end,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = bind("ratingSummary"),
						fill_horizontal = 1,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Virtual copies",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:checkbox({
						title = includeVirtualCopiesTitle,
						value = bind("includeVirtualCopies"),
						action = function()
							saveProperties(properties)
							refreshDerivedProperties(properties)
						end,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = "── in addition ──",
						fill_horizontal = 1,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "+ by smart collection",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:edit_field({
						value = bind("smartCollectionFilter"),
						width_in_chars = 24,
						immediate = true,
						validate = function(view, value)
							properties.smartCollectionFilter = value
							saveProperties(properties)
							scheduleSmartCollectionLookup(properties, value)
							return true, value
						end,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = bind("smartCollectionSummary"),
						fill_horizontal = 1,
					}),
				}),
			}),
		},
		{
			title = "Output",
			viewFactory:column({
				bind_to_object = properties,
				spacing = viewFactory:control_spacing(),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Long edge pixels",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:edit_field({
						value = bind("longEdgePixels"),
						width_in_digits = 5,
						immediate = true,
						validate = function(view, value)
							properties.longEdgePixels = value
							saveProperties(properties)
							refreshDerivedProperties(properties)
							return true, value
						end,
						action = function()
							saveProperties(properties)
							refreshDerivedProperties(properties)
						end,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "JPEG quality",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:edit_field({
						value = bind("jpegQuality"),
						width_in_digits = 3,
						immediate = true,
						validate = function(view, value)
							properties.jpegQuality = value
							saveProperties(properties)
							refreshDerivedProperties(properties)
							return true, value
						end,
						action = function()
							saveProperties(properties)
							refreshDerivedProperties(properties)
						end,
					}),
				}),
			}),
		},
		{
			title = "Last Run",
			viewFactory:column({
				bind_to_object = properties,
				spacing = viewFactory:control_spacing(),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Sync",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:push_button({
						title = "Sync Now",
						enabled = bind("canSync"),
						action = function()
							syncNow(properties)
						end,
					}),
					viewFactory:push_button({
						title = "Sync Changes",
						enabled = bind("canSync"),
						action = function()
							syncChanges(properties)
						end,
					}),
					viewFactory:static_text({
						title = bind("syncAvailabilitySummary"),
						fill_horizontal = 1,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Background",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:popup_menu({
						value = bind("backgroundSyncInterval"),
						action = function()
							saveProperties(properties)
							refreshDerivedProperties(properties)
						end,
						items = {
							{
								title = "Never",
								value = Config.backgroundSyncNever,
							},
							{
								title = "Every hour",
								value = Config.backgroundSyncHourly,
							},
							{
								title = "Every day",
								value = Config.backgroundSyncDaily,
							},
						},
					}),
					viewFactory:static_text({
						title = bind("backgroundSyncSummary"),
						fill_horizontal = 1,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = "Sync Changes exports recent edits only; Sync Now also cleans deleted outputs.",
						width_in_chars = 72,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Last run",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = bind("lastRunAt"),
						width_in_chars = 24,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Results",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = bind("lastRunResults"),
						width_in_chars = 34,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Cleanup",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = bind("lastRunCleanup"),
						width_in_chars = 34,
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Diagnostic",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = bind("lastRunDiagnostic"),
						width_in_chars = 72,
					}),
				}),
			}),
		},
		{
			title = "Files",
			viewFactory:column({
				bind_to_object = properties,
				spacing = viewFactory:control_spacing(),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "State file",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = LrPathUtils.child(
							Config.pluginDataDirectory(),
							Config.stateFileName
						),
					}),
				}),
				viewFactory:row({
					spacing = viewFactory:control_spacing(),
					viewFactory:static_text({
						title = "Log file",
						width = LrView.share("labelWidth"),
					}),
					viewFactory:static_text({
						title = bind("logFilePath"),
						fill_horizontal = 1,
					}),
				}),
			}),
		},
	}
end

return {
	startDialog = function(propertyTable)
		smartCollectionLookupStates[propertyTable] = {
			generation = 0,
			running = false,
			closed = false,
		}
		propertyTable.catalogProfileId = nil
		Config.ensureDefaults(propertyTable)
		refreshDerivedProperties(propertyTable)
		LrFunctionContext.postAsyncTaskWithContext(
			"BulkJpegSyncSettingsLoad",
			function(context)
				context:addFailureHandler(function(_, err)
					propertyTable.syncAvailabilitySummary = tostring(err)
					Logger.error("catalog_settings_load_failed", {
						error = tostring(err),
					})
				end)
				local catalog = LrApplication.activeCatalog()
				local profile, profileErr = Profile.forCatalog(catalog)
				if not profile then
					propertyTable.syncAvailabilitySummary = tostring(profileErr)
					return
				end
				Config.loadPreferencesIntoProperties(
					LrPrefs.prefsForPlugin(),
					propertyTable,
					profile.id
				)
				propertyTable.catalogProfileId = profile.id
				refreshDerivedProperties(propertyTable)
				local initFilter = propertyTable.smartCollectionFilter or ""
				if initFilter ~= "" then
					scheduleSmartCollectionLookup(propertyTable, initFilter)
				end
			end
		)
	end,
	endDialog = function(propertyTable)
		local lookupState = smartCollectionLookupStates[propertyTable]
		if lookupState then
			lookupState.closed = true
			lookupState.generation = lookupState.generation + 1
		end
		if propertyTable.catalogProfileId then
			saveProperties(propertyTable)
		end
	end,
	sectionsForTopOfDialog = function(viewFactory, propertyTable)
		return sectionsForTopOfDialog(viewFactory, propertyTable)
	end,
}
