local Path = {}

local function pathJoin(...)
	local parts = { ... }
	local result = nil
	for _, part in ipairs(parts) do
		part = tostring(part)
		if part ~= "" then
			if result == nil then
				result = part
			elseif result:sub(-1) == "/" or result:sub(-1) == "\\" then
				result = result .. part
			else
				result = result .. "/" .. part
			end
		end
	end

	return result or ""
end

local function sanitize(value)
	value = tostring(value or "")
	value = value:gsub("[/\\:]+", "-")
	value = value:gsub("[%c]+", "")
	value = value:gsub("^%s+", "")
	value = value:gsub("%s+$", "")
	if value == "" then
		return "untitled"
	end

	return value
end

local function splitBaseName(fileName)
	local clean = sanitize(fileName)
	local base = clean:match("^(.*)%.[^%.]+$")
	if base and base ~= "" then
		return sanitize(base)
	end

	return clean
end

local function dateParts(captureTime)
	if type(captureTime) == "string" then
		local year, month, day =
			captureTime:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
		if year and month and day then
			return year, year .. "-" .. month .. "-" .. day
		end
	end

	return "undated", "undated"
end

function Path.identifierSuffix(identifier)
	local clean = sanitize(identifier)
	clean = clean:gsub("[^%w%-_]+", "-")
	return clean
end

function Path.copyMarker(photo)
	if not photo.isVirtualCopy then
		return nil
	end

	if photo.copyName and photo.copyName ~= "" then
		return "copy-" .. Path.identifierSuffix(photo.copyName)
	end
	if photo.copyNumber and tostring(photo.copyNumber) ~= "" then
		return "copy-" .. Path.identifierSuffix(photo.copyNumber)
	end

	return "copy"
end

function Path.derivativePath(outputDirectory, photo)
	local year, day = dateParts(photo.captureTime)
	local baseName =
		splitBaseName(photo.fileName or photo.sourcePath or "photo")
	local copyMarker = Path.copyMarker(photo)
	local suffix = Path.identifierSuffix(photo.identifier)
	if copyMarker then
		return pathJoin(
			outputDirectory,
			year,
			day,
			baseName .. "__" .. copyMarker .. "__lr-" .. suffix .. ".jpg"
		)
	end

	return pathJoin(
		outputDirectory,
		year,
		day,
		baseName .. "__lr-" .. suffix .. ".jpg"
	)
end

function Path.temporaryPath(finalPath)
	return finalPath .. ".tmp"
end

function Path.dirname(path)
	return tostring(path):match("^(.*)[/\\][^/\\]+$") or "."
end

return Path
