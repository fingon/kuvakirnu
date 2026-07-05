local State = {}

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
			lines[#lines + 1] = nextIndent .. keyText .. " = " .. serializeValue(child, nextIndent) .. ","
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
	local probePath = directory .. "/.immich-derivative-sync-write-test"
	local probe = io.open(probePath, "w")
	if probe then
		probe:close()
		os.remove(probePath)
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

function State.empty()
	return {
		version = 1,
		photos = {},
	}
end

function State.validate(state)
	if type(state) ~= "table" then
		return nil, "state root is not a table"
	end
	if type(state.photos) ~= "table" then
		return nil, "state photos field is not a table"
	end

	return state
end

function State.load(path)
	local file = io.open(path, "r")
	if not file then
		return State.empty()
	end
	file:close()

	local chunk, loadErr = loadfile(path)
	if not chunk then
		return nil, "failed to parse state file: " .. tostring(loadErr)
	end

	local ok, state = pcall(chunk)
	if not ok then
		return nil, "failed to load state file: " .. tostring(state)
	end

	return State.validate(state)
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

	local tempPath = path .. ".tmp"
	local file, openErr = io.open(tempPath, "w")
	if not file then
		return nil, "failed to open temporary state file: " .. tostring(openErr)
	end

	file:write("return ")
	file:write(serializeValue(state))
	file:write("\n")
	file:close()

	local renamed, renameErr = os.rename(tempPath, path)
	if not renamed then
		return nil, "failed to replace state file: " .. tostring(renameErr)
	end

	return true
end

function State.markExported(state, item, outputPath, exportedAt)
	state.photos[item.photo.identifier] = {
		sourcePath = item.photo.sourcePath,
		outputPath = outputPath,
		fingerprint = item.fingerprint,
		exportSettingsVersion = item.configExportSettingsVersion,
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

function State.markOrphaned(state, item, orphanedAt)
	item.record.status = "orphaned"
	item.record.orphanedAt = orphanedAt
	state.photos[item.photo.identifier] = item.record
end

return State
