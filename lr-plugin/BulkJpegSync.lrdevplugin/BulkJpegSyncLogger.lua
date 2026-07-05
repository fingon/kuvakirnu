local Config = require "BulkJpegSyncConfig"

local Logger = {}

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

local function formatMetadata(metadata)
	local parts = {}
	if metadata then
		for key, value in pairs(metadata) do
			parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
		end
	end

	return table.concat(parts, " ")
end

local function ensureDirectory(path)
	local directory = tostring(path):match("^(.*)[/\\][^/\\]+$") or "."
	if directory == "." then
		return true
	end

	local LrFileUtils = maybeImport("LrFileUtils")
	if LrFileUtils and LrFileUtils.createAllDirectories then
		local ok = LrFileUtils.createAllDirectories(directory)
		if ok == false then
			return false
		end
	end

	return true
end

local function appendLogFile(line)
	local path = Config.logFilePath()
	if not ensureDirectory(path) then
		io.stderr:write("[error] log_directory_unavailable path=" .. tostring(path) .. "\n")
		return
	end

	local file, openErr = io.open(path, "a")
	if not file then
		io.stderr:write("[error] log_file_unavailable path=" .. tostring(path) .. " error=" .. tostring(openErr) .. "\n")
		return
	end

	local wrote, writeErr = file:write(os.date("!%Y-%m-%dT%H:%M:%SZ"), " ", line, "\n")
	local closed, closeErr = file:close()
	if not wrote then
		io.stderr:write("[error] log_file_write_failed path=" .. tostring(path) .. " error=" .. tostring(writeErr) .. "\n")
	end
	if not closed then
		io.stderr:write("[error] log_file_close_failed path=" .. tostring(path) .. " error=" .. tostring(closeErr) .. "\n")
	end
end

local function log(level, message, metadata)
	local line = "[" .. level .. "] " .. message
	local suffix = formatMetadata(metadata)
	if suffix ~= "" then
		line = line .. " " .. suffix
	end
	appendLogFile(line)

	local LrLogger = maybeImport("LrLogger")
	if LrLogger then
		local logger = LrLogger("BulkJpegSync")
		if logger[level] then
			logger:enable("logfile")
			logger[level](logger, line)
			return
		end
	end

	io.stderr:write(line .. "\n")
end

function Logger.debug(message, metadata)
	log("debug", message, metadata)
end

function Logger.info(message, metadata)
	log("info", message, metadata)
end

function Logger.warn(message, metadata)
	log("warn", message, metadata)
end

function Logger.error(message, metadata)
	log("error", message, metadata)
end

return Logger
