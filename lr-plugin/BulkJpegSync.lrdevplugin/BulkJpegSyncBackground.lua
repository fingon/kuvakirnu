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
		local LrApplication = maybeImport("LrApplication")
		if not LrApplication or not LrApplication.activeCatalog then
			Logger.error("background_sync_unavailable", {
				error = "Lightroom catalog is unavailable",
			})
			running = false
			return
		end
		local Profile = require("BulkJpegSyncProfile")
		local profile, profileErr =
			Profile.forCatalog(LrApplication.activeCatalog())
		if not profile then
			Logger.error("background_sync_unavailable", { error = profileErr })
			running = false
			return
		end
		local properties = {}
		Config.loadPreferencesIntoProperties(prefs, properties, profile.id)
		local currentTimeSec = nowSec()
		local Sync = require("BulkJpegSyncSync")
		local mode, reason = Background.nextMode(properties, currentTimeSec)
		if mode and not Sync.isRunning() then
			properties.lastBackgroundAttemptAtSec = currentTimeSec
			Config.saveRuntimeToPreferences(properties, prefs, profile.id)
			local ok, err = Sync.run(nil, {
				mode = mode,
				startedAtSec = currentTimeSec,
				suppressDialogs = true,
			})
			if ok and mode == fullMode then
				properties.lastBackgroundFullSyncAtSec = currentTimeSec
				Config.saveRuntimeToPreferences(properties, prefs, profile.id)
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
	local LrFunctionContext = maybeImport("LrFunctionContext")
	if
		not LrFunctionContext or not LrFunctionContext.postAsyncTaskWithContext
	then
		Logger.error("background_sync_unavailable", {
			error = "Lightroom function context is unavailable",
		})
		return
	end

	running = true
	stopRequested = false
	LrFunctionContext.postAsyncTaskWithContext(
		"BulkJpegSyncBackground",
		function(context)
			context:addCleanupHandler(function()
				running = false
				stopRequested = false
			end)
			context:addFailureHandler(function(_, err)
				Logger.error("background_sync_failed", {
					error = tostring(err),
				})
			end)
			runLoop()
		end
	)
end

function Background.requestStop()
	stopRequested = true
end

function Background.isRunning()
	return running
end

return Background
