local LrTasks = import("LrTasks")

local Background = require("BulkJpegSyncBackground")
local Sync = require("BulkJpegSyncSync")

local shutdownWaitSec = 9
local shutdownPollSec = 0.1

return {
	LrShutdownFunction = function(doneFunction, progressFunction)
		Background.requestStop()
		Sync.requestCancel()
		local waitedSec = 0
		while
			waitedSec < shutdownWaitSec
			and (Background.isRunning() or Sync.isRunning())
		do
			local canceled = progressFunction(
				waitedSec / shutdownWaitSec,
				"Stopping Bulk JPEG Sync"
			)
			if canceled then
				break
			end
			LrTasks.sleep(shutdownPollSec)
			waitedSec = waitedSec + shutdownPollSec
		end
		doneFunction()
	end,
}
