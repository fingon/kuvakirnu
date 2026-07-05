local LrDialogs = import "LrDialogs"
local LrTasks = import "LrTasks"

local Logger = require "ImmichDerivativeSyncLogger"
local Sync = require "ImmichDerivativeSyncSync"

local SyncLauncher = {}

function SyncLauncher.runAsync()
	LrTasks.startAsyncTask(function()
		local ok, err = Sync.run()
		if not ok then
			Logger.error("sync_failed", { error = tostring(err) })
			LrDialogs.message("Immich Derivative Sync failed", tostring(err), "critical")
		end
	end)
end

return SyncLauncher
