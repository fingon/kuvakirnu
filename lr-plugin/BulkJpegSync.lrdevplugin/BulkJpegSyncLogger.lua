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

local function log(level, message, metadata)
	local line = message
	local suffix = formatMetadata(metadata)
	if suffix ~= "" then
		line = line .. " " .. suffix
	end

	local LrLogger = maybeImport("LrLogger")
	if LrLogger then
		local logger = LrLogger("BulkJpegSync")
		if logger[level] then
			logger:enable("logfile")
			logger[level](logger, line)
			return
		end
	end

	io.stderr:write("[" .. level .. "] " .. line .. "\n")
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
