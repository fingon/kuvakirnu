local LrTasks = import "LrTasks"
local LrDialogs = import "LrDialogs"

local Sync = require "ImmichDerivativeSyncSync"
local Logger = require "ImmichDerivativeSyncLogger"

LrTasks.startAsyncTask(function()
	local ok, err = Sync.run()
	if not ok then
		Logger.error("sync_failed", { error = tostring(err) })
		LrDialogs.message("Immich Derivative Sync failed", tostring(err), "critical")
	end
end)
