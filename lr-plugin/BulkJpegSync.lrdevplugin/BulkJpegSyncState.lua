local FileUtils = require("BulkJpegSyncFileUtils")

local State = {}
local backupStateSuffix = ".bak"
local temporaryStateSuffix = ".tmp"

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

local function serializeValue(value, indent)
	indent = indent or ""
	local valueType = type(value)

	if valueType == "string" then
		return string.format("%q", value)
	end
	if valueType == "number" or valueType == "boolean" then
		return tostring(value)
	end
	if valueType == "table" then
		local nextIndent = indent .. "\t"
		local lines = { "{" }
		for key, child in pairs(value) do
			local keyText
			if type(key) == "string" and key:match("^[%a_][%w_]*$") then
				keyText = key
			else
				keyText = "[" .. serializeValue(key, nextIndent) .. "]"
			end
			lines[#lines + 1] = nextIndent
				.. keyText
				.. " = "
				.. serializeValue(child, nextIndent)
				.. ","
		end
		lines[#lines + 1] = indent .. "}"
		return table.concat(lines, "\n")
	end
	if value == nil then
		return "nil"
	end

	error("cannot serialize value type " .. valueType)
end

local function ensureDirectory(path)
	local directory = path:match("^(.*)[/\\][^/\\]+$") or "."
	if directory == "." then
		return true
	end
	local probePath = directory .. "/.bulk-jpeg-sync-write-test"
	local probe = io.open(probePath, "w")
	if probe then
		probe:close()
		local deletedProbe, deleteProbeErr = FileUtils.deleteFile(probePath)
		if not deletedProbe then
			return nil,
				"failed to delete state directory probe: " .. tostring(
					deleteProbeErr
				)
		end
		return true
	end

	local LrFileUtils = maybeImport("LrFileUtils")
	if LrFileUtils and LrFileUtils.createAllDirectories then
		local ok, err = LrFileUtils.createAllDirectories(directory)
		if ok == false then
			return nil, err
		end
		return true
	end

	return false, "failed to create state directory: " .. directory
end

function State.empty(profile)
	local state = {
		version = 2,
		photos = {},
	}
	if profile then
		state.catalogId = profile.id
		state.catalogPath = profile.catalogPath
		state.ownedOutputRoots = {}
		state.incrementalProcessedThroughSec = 0
	end

	return state
end

function State.validate(state)
	if type(state) ~= "table" then
		return nil, "state root is not a table"
	end
	if type(state.photos) ~= "table" then
		return nil, "state photos field is not a table"
	end
	if state.version ~= 1 and state.version ~= 2 then
		return nil, "state version is unsupported: " .. tostring(state.version)
	end
	if state.version == 2 then
		if state.catalogId ~= nil and type(state.catalogId) ~= "string" then
			return nil, "state catalog identifier is not a string"
		end
		if state.catalogPath ~= nil and type(state.catalogPath) ~= "string" then
			return nil, "state catalog path is not a string"
		end
		if
			state.incrementalProcessedThroughSec ~= nil
			and type(state.incrementalProcessedThroughSec) ~= "number"
		then
			return nil, "state incremental cursor is not a number"
		end
		if
			state.ownedOutputRoots ~= nil
			and type(state.ownedOutputRoots) ~= "table"
		then
			return nil, "state owned output roots field is not a table"
		end
	end
	for identifier, record in pairs(state.photos) do
		if type(identifier) ~= "string" then
			return nil, "state photo identifier is not a string"
		end
		if type(record) ~= "table" then
			return nil, "state photo record is not a table: " .. identifier
		end
		if record.outputPath ~= nil and type(record.outputPath) ~= "string" then
			return nil, "state output path is not a string: " .. identifier
		end
		if record.status ~= "exported" and record.status ~= "failed" then
			return nil, "state photo status is invalid: " .. identifier
		end
		if
			record.fingerprint ~= nil
			and type(record.fingerprint) ~= "string"
		then
			return nil, "state fingerprint is not a string: " .. identifier
		end
	end

	return state
end

local function migrateLegacyState(state)
	if
		type(state) ~= "table"
		or state.version ~= 1
		or type(state.photos) ~= "table"
	then
		return nil
	end

	local migratedCount = 0
	for _, record in pairs(state.photos) do
		if type(record) == "table" and record.status == "orphaned" then
			record.status = "exported"
			record.orphanedAt = nil
			migratedCount = migratedCount + 1
		end
	end
	if migratedCount == 0 then
		return nil
	end

	return { legacyOrphanedRecordsMigrated = migratedCount }
end

local function loadStateFile(path)
	local file = io.open(path, "r")
	if not file then
		if FileUtils.fileExists(path) then
			return nil, "failed to open state file: " .. tostring(path)
		end
		return nil, "missing"
	end
	file:close()

	local chunk, loadErr
	if setfenv then
		chunk, loadErr = loadfile(path)
		if chunk then
			setfenv(chunk, {})
		end
	else
		chunk, loadErr = loadfile(path, "t", {})
	end
	if not chunk then
		return nil, "failed to parse state file: " .. tostring(loadErr)
	end

	local ok, state = pcall(chunk)
	if not ok then
		return nil, "failed to load state file: " .. tostring(state)
	end

	local loadInfo = migrateLegacyState(state)
	local valid, validationErr = State.validate(state)
	if not valid then
		return nil, validationErr
	end

	return valid, nil, loadInfo
end

function State.load(path)
	local state, stateErr, loadInfo = loadStateFile(path)
	if state then
		return state, nil, loadInfo
	end

	local backup, backupErr, backupLoadInfo =
		loadStateFile(path .. backupStateSuffix)
	if backup then
		backupLoadInfo = backupLoadInfo or {}
		backupLoadInfo.recoveredFromBackup = true
		backupLoadInfo.primaryError = stateErr
		return backup, nil, backupLoadInfo
	end
	if stateErr == "missing" and backupErr == "missing" then
		return State.empty()
	end

	return nil,
		"failed to load state primary="
			.. tostring(stateErr)
			.. " backup="
			.. tostring(backupErr)
end

function State.save(path, state)
	local valid, validationErr = State.validate(state)
	if not valid then
		return nil, validationErr
	end

	local ok, dirErr = ensureDirectory(path)
	if not ok then
		return nil, dirErr
	end

	local tempPath = path .. temporaryStateSuffix
	local file, openErr = io.open(tempPath, "w")
	if not file then
		return nil, "failed to open temporary state file: " .. tostring(openErr)
	end

	local wrote, writeErr = file:write("return ", serializeValue(state), "\n")
	if not wrote then
		file:close()
		local deletedTemp, deleteTempErr = FileUtils.deleteFile(tempPath)
		if not deletedTemp then
			return nil,
				"failed to write temporary state file: "
					.. tostring(writeErr)
					.. "; failed to delete temporary state file: "
					.. tostring(deleteTempErr)
		end
		return nil,
			"failed to write temporary state file: " .. tostring(writeErr)
	end
	local closed, closeErr = file:close()
	if not closed then
		local deletedTemp, deleteTempErr = FileUtils.deleteFile(tempPath)
		if not deletedTemp then
			return nil,
				"failed to close temporary state file: "
					.. tostring(closeErr)
					.. "; failed to delete temporary state file: "
					.. tostring(deleteTempErr)
		end
		return nil,
			"failed to close temporary state file: " .. tostring(closeErr)
	end

	local replaced, replaceErr = FileUtils.replaceFile(
		tempPath,
		path,
		{ backupPath = path .. backupStateSuffix, keepBackup = true }
	)
	if not replaced then
		return nil, "failed to replace state file: " .. tostring(replaceErr)
	end

	return true
end

function State.markExported(state, item, outputPath, exportedAt)
	state.photos[item.photo.identifier] = {
		sourcePath = item.photo.sourcePath,
		outputPath = outputPath,
		fingerprint = item.fingerprint,
		exportSettingsVersion = item.configExportSettingsVersion,
		pluginVersionTimestamp = item.configPluginVersionTimestamp,
		outputSettingsChangedAt = item.configOutputSettingsChangedAt,
		outputSettingsFingerprint = item.configOutputSettingsFingerprint,
		lastExportTime = exportedAt,
		status = "exported",
		lastError = nil,
	}
end

function State.markFailed(state, item, errorMessage)
	local existing = state.photos[item.photo.identifier] or {}
	existing.sourcePath = item.photo.sourcePath
	existing.outputPath = item.outputPath
	existing.status = "failed"
	existing.lastError = tostring(errorMessage)
	state.photos[item.photo.identifier] = existing
end

function State.deleteRecord(state, identifier)
	state.photos[identifier] = nil
end

return State
