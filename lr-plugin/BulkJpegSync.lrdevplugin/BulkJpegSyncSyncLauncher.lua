local LrDialogs = import "LrDialogs"
local LrTasks = import "LrTasks"

local Logger = require "BulkJpegSyncLogger"
local Sync = require "BulkJpegSyncSync"

local SyncLauncher = {}

function SyncLauncher.runAsync()
	LrTasks.startAsyncTask(function()
		local ok, err = Sync.run()
		if not ok then
			Logger.error("sync_failed", { error = tostring(err) })
			LrDialogs.message("Bulk JPEG Sync failed", tostring(err), "critical")
		end
	end)
end

return SyncLauncher
