local LrDialogs = import("LrDialogs")
local LrTasks = import("LrTasks")

local Logger = require("BulkJpegSyncLogger")
local Sync = require("BulkJpegSyncSync")

local SyncLauncher = {}

local function runAsync(properties, options)
	LrTasks.startAsyncTask(function()
		local ok, err = Sync.run(properties, options)
		if not ok then
			Logger.error("sync_failed", { error = tostring(err) })
			if not (options and options.suppressDialogs) then
				LrDialogs.message(
					"Bulk JPEG Sync failed",
					tostring(err),
					"critical"
				)
			end
		end
	end)
end

function SyncLauncher.runAsync(properties)
	runAsync(properties)
end

function SyncLauncher.runIncrementalAsync(properties)
	runAsync(properties, { mode = "incremental" })
end

function SyncLauncher.runBackgroundAsync(properties, options)
	options = options or {}
	options.suppressDialogs = true
	runAsync(properties, options)
end

return SyncLauncher
