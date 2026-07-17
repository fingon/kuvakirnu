local LrPathUtils = import("LrPathUtils")
local LrUUID = import("LrUUID")

local Config = require("BulkJpegSyncConfig")

local Profile = {}

local catalogProfileIdProperty = "bulkJpegSyncProfileId"
local catalogStateDirectory = "catalogs"

function Profile.forCatalog(catalog)
	if not catalog or not catalog.getPath then
		return nil, "Lightroom catalog identity is unavailable"
	end

	local catalogPath = catalog:getPath()
	local profileId =
		catalog:getPropertyForPlugin(_PLUGIN, catalogProfileIdProperty)
	if profileId == nil or profileId == "" then
		profileId = LrUUID.generateUUID()
		catalog:withWriteAccessDo("Initialize Bulk JPEG Sync", function()
			catalog:setPropertyForPlugin(
				_PLUGIN,
				catalogProfileIdProperty,
				profileId
			)
		end)
	end

	return {
		id = tostring(profileId),
		catalogPath = tostring(catalogPath),
	}
end

function Profile.statePath(profile)
	return LrPathUtils.child(
		LrPathUtils.child(
			LrPathUtils.child(
				Config.pluginDataDirectory(),
				catalogStateDirectory
			),
			profile.id
		),
		Config.stateFileName
	)
end

function Profile.legacyStatePath()
	return LrPathUtils.child(Config.pluginDataDirectory(), Config.stateFileName)
end

return Profile
