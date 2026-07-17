local LrDialogs = import("LrDialogs")
local LrFunctionContext = import("LrFunctionContext")

local Logger = require("BulkJpegSyncLogger")
local Sync = require("BulkJpegSyncSync")

local SyncLauncher = {}
local pending = false

local function runAsync(properties, options)
	if pending or Sync.isRunning() then
		return false, "sync is already pending or running"
	end
	pending = true
	LrFunctionContext.postAsyncTaskWithContext(
		"BulkJpegSyncLaunch",
		function(context)
			context:addCleanupHandler(function()
				pending = false
			end)
			context:addFailureHandler(function(_, err)
				Logger.error("sync_failed", { error = tostring(err) })
				if not (options and options.suppressDialogs) then
					LrDialogs.message(
						"Bulk JPEG Sync failed",
						tostring(err),
						"critical"
					)
				end
			end)
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
		end
	)
	return true
end

function SyncLauncher.isPendingOrRunning()
	return pending or Sync.isRunning()
end

function SyncLauncher.runAsync(properties)
	return runAsync(properties)
end

function SyncLauncher.runIncrementalAsync(properties)
	return runAsync(properties, { mode = "incremental" })
end

function SyncLauncher.runBackgroundAsync(properties, options)
	options = options or {}
	options.suppressDialogs = true
	return runAsync(properties, options)
end

return SyncLauncher
