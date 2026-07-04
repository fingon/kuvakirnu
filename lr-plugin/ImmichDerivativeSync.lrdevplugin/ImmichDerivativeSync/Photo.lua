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
	local values = { ... }
	for _, value in ipairs(values) do
		if value ~= nil and value ~= "" then
			return value
		end
	end

	return nil
end

function Photo.snapshot(photo)
	local identifier = firstPresent(raw(photo, "uuid"), raw(photo, "localIdentifier"), photo.localIdentifier, tostring(photo))
	local sourcePath = firstPresent(raw(photo, "path"), formatted(photo, "fileName"), "")
	local fileName = firstPresent(raw(photo, "fileName"), formatted(photo, "fileName"), sourcePath:match("[^/\\]+$"), "photo")
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
		lastEditTime = firstPresent(raw(photo, "lastEditTime"), raw(photo, "lastUpdated"), raw(photo, "lastImportTime"), ""),
	}
end

function Photo.fingerprint(photo)
	return table.concat({
		tostring(photo.sourcePath or ""),
		tostring(photo.rating or ""),
		tostring(photo.isRejected or false),
		tostring(photo.captureTime or ""),
		tostring(photo.lastEditTime or ""),
	}, "|")
end

return Photo
