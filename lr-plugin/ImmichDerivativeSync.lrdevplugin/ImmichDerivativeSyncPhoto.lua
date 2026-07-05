local Photo = {}

local function raw(photo, key)
	if not photo or not photo.getRawMetadata then
		return nil
	end

	local ok, value = pcall(function()
		return photo:getRawMetadata(key)
	end)
	if ok then
		return value
	end

	return nil
end

local function formatted(photo, key)
	if not photo or not photo.getFormattedMetadata then
		return nil
	end

	local ok, value = pcall(function()
		return photo:getFormattedMetadata(key)
	end)
	if ok then
		return value
	end

	return nil
end

local function firstPresent(...)
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		if value ~= nil and value ~= "" then
			return value
		end
	end

	return nil
end

function Photo.snapshot(photo)
	local identifier = firstPresent(raw(photo, "uuid"), raw(photo, "localIdentifier"), photo.localIdentifier, tostring(photo))
	local rawPath = raw(photo, "path")
	local formattedFileName = formatted(photo, "fileName")
	local rawFileName = raw(photo, "fileName")
	local sourcePath = rawPath or ""
	local sourcePathFileName = tostring(sourcePath):match("[^/\\]+$")
	local fileName = firstPresent(rawFileName, formattedFileName, sourcePathFileName, "photo")
	local rating = tonumber(firstPresent(raw(photo, "rating"), 0)) or 0

	return {
		handle = photo,
		identifier = tostring(identifier),
		sourcePath = tostring(sourcePath),
		fileName = tostring(fileName),
		captureTime = firstPresent(raw(photo, "dateTimeOriginal"), raw(photo, "captureTime"), formatted(photo, "dateTimeOriginal")),
		rating = rating,
		isRejected = raw(photo, "isRejected") == true or raw(photo, "pickStatus") == -1,
		isVirtualCopy = raw(photo, "isVirtualCopy") == true,
		copyName = firstPresent(raw(photo, "copyName"), formatted(photo, "copyName")),
		copyNumber = firstPresent(raw(photo, "copyNumber"), formatted(photo, "copyNumber")),
		lastEditTime = firstPresent(raw(photo, "lastEditTime"), raw(photo, "lastUpdated"), raw(photo, "lastImportTime"), ""),
	}
end

function Photo.fingerprint(photo)
	return table.concat({
		tostring(photo.sourcePath or ""),
		tostring(photo.rating or ""),
		tostring(photo.isRejected or false),
		tostring(photo.isVirtualCopy or false),
		tostring(photo.copyName or ""),
		tostring(photo.copyNumber or ""),
		tostring(photo.captureTime or ""),
		tostring(photo.lastEditTime or ""),
	}, "|")
end

return Photo
