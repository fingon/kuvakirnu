local Config = require("BulkJpegSyncConfig")
local Logger = require("BulkJpegSyncLogger")

local Background = {}

local pollIntervalSec = 60
local fullMode = "full"
local incrementalMode = "incremental"
local running = false
local stopRequested = false

local function maybeImport(name)
	if type(import) ~= "function" then
		return nil
	end

	local ok, module = pcall(import, name)
	if ok then
		return module
	end

	return nil
end

local function nowSec()
	return os.time()
end

function Background.nextMode(properties, currentTimeSec)
	Config.ensureDefaults(properties)
	if not Config.canSync(properties) then
		return nil, "not_configured"
	end

	local intervalSec =
		Config.backgroundSyncIntervalSec(properties.backgroundSyncInterval)
	if not intervalSec then
		return nil, "disabled"
	end

	local lastAttemptAtSec = tonumber(properties.lastBackgroundAttemptAtSec)
		or 0
	if currentTimeSec - lastAttemptAtSec < intervalSec then
		return nil, "not_due"
	end

	local lastSuccessfulSyncStartedAtSec = tonumber(
		properties.lastSuccessfulSyncStartedAtSec
	) or 0
	if lastSuccessfulSyncStartedAtSec <= 0 then
		return fullMode, "initial_full"
	end

	if properties.backgroundSyncInterval == Config.backgroundSyncDaily then
		return fullMode, "daily_full"
	end

	local lastFullSyncAtSec = tonumber(properties.lastBackgroundFullSyncAtSec)
		or 0
	if currentTimeSec - lastFullSyncAtSec >= Config.backgroundSyncDailySec then
		return fullMode, "hourly_daily_full"
	end

	return incrementalMode, "hourly_incremental"
end

local function sleep(seconds)
	local LrTasks = maybeImport("LrTasks")
	if LrTasks and LrTasks.sleep then
		LrTasks.sleep(seconds)
	end
end

local function runLoop()
	local LrPrefs = maybeImport("LrPrefs")
	if not LrPrefs or not LrPrefs.prefsForPlugin then
		Logger.error("background_sync_unavailable", {
			error = "Lightroom preferences are unavailable",
		})
		running = false
		return
	end

	while not stopRequested do
		local prefs = LrPrefs.prefsForPlugin()
		Config.ensureDefaults(prefs)
		local currentTimeSec = nowSec()
		local Sync = require("BulkJpegSyncSync")
		local mode, reason = Background.nextMode(prefs, currentTimeSec)
		if mode and not Sync.isRunning() then
			prefs.lastBackgroundAttemptAtSec = currentTimeSec
			local ok, err = Sync.run(prefs, {
				mode = mode,
				startedAtSec = currentTimeSec,
				suppressDialogs = true,
			})
			if ok and mode == fullMode then
				prefs.lastBackgroundFullSyncAtSec = currentTimeSec
			elseif not ok then
				Logger.error("background_sync_failed", {
					mode = mode,
					reason = reason,
					error = tostring(err),
				})
			end
		elseif mode and Sync.isRunning() then
			Logger.info("background_sync_deferred", {
				reason = "sync_running",
			})
		end

		sleep(pollIntervalSec)
	end

	running = false
	stopRequested = false
end

function Background.start()
	if running then
		return
	end
	local LrTasks = maybeImport("LrTasks")
	if not LrTasks or not LrTasks.startAsyncTask then
		Logger.error("background_sync_unavailable", {
			error = "Lightroom tasks are unavailable",
		})
		return
	end

	running = true
	stopRequested = false
	LrTasks.startAsyncTask(runLoop)
end

function Background.requestStop()
	stopRequested = true
end

return Background
