local Photo = {}

local function raw(photo, key)
	if not photo or not photo.getRawMetadata then
		return nil
	end

	return photo:getRawMetadata(key)
end

local function formatted(photo, key)
	if not photo or not photo.getFormattedMetadata then
		return nil
	end

	return photo:getFormattedMetadata(key)
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

local function canonicalDate(value)
	if type(value) ~= "string" then
		return nil
	end

	local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
	if year and month and day then
		return year .. "-" .. month .. "-" .. day
	end

	return nil
end

local function lightroomTimestampDate(value)
	if type(value) ~= "number" then
		return nil
	end

	local LrDate = maybeImport("LrDate")
	if not LrDate or not LrDate.timeToIsoDate then
		return nil
	end

	return canonicalDate(LrDate.timeToIsoDate(value))
end

local function captureDate(rawMetadata, formattedMetadata)
	local isoKeys = {
		"dateTimeOriginalISO8601",
		"dateTimeISO8601",
		"dateTimeDigitizedISO8601",
	}
	for _, key in ipairs(isoKeys) do
		local value = canonicalDate(rawMetadata[key])
		if value then
			return value, key
		end
	end

	local timestampKeys = {
		"dateTimeOriginal",
		"dateTime",
		"dateTimeDigitized",
	}
	for _, key in ipairs(timestampKeys) do
		local value = lightroomTimestampDate(rawMetadata[key])
		if value then
			return value, key
		end
	end

	return nil, nil
end

function Photo.snapshotFromMetadata(photo, rawMetadata, formattedMetadata)
	rawMetadata = rawMetadata or {}
	formattedMetadata = formattedMetadata or {}
	local identifier = firstPresent(
		rawMetadata.uuid,
		rawMetadata.localIdentifier,
		photo and photo.localIdentifier,
		tostring(photo)
	)
	local rawPath = rawMetadata.path
	local formattedFileName = formattedMetadata.fileName
	local sourcePath = rawPath or ""
	local sourcePathFileName = tostring(sourcePath):match("[^/\\]+$")
	local fileName =
		firstPresent(formattedFileName, sourcePathFileName, "photo")
	local rawRating = firstPresent(rawMetadata.rating)
	local rating = tonumber(firstPresent(rawRating, 0)) or 0
	local captureTime, captureDateSource =
		captureDate(rawMetadata, formattedMetadata)

	return {
		handle = photo,
		identifier = tostring(identifier),
		sourcePath = tostring(sourcePath),
		fileName = tostring(fileName),
		captureTime = captureTime,
		captureDateMissing = captureTime == nil,
		captureDateSource = captureDateSource,
		rating = rating,
		ratingMissing = rawRating == nil,
		isRejected = rawMetadata.pickStatus == -1,
		isVideo = rawMetadata.fileFormat == "VIDEO",
		isVirtualCopy = rawMetadata.isVirtualCopy == true,
		copyName = formattedMetadata.copyName,
		lastEditTime = firstPresent(rawMetadata.lastEditTime, ""),
	}
end

function Photo.snapshot(photo)
	return Photo.snapshotFromMetadata(photo, {
		uuid = raw(photo, "uuid"),
		path = raw(photo, "path"),
		rating = raw(photo, "rating"),
		pickStatus = raw(photo, "pickStatus"),
		isVirtualCopy = raw(photo, "isVirtualCopy"),
		fileFormat = raw(photo, "fileFormat"),
		dateTimeOriginalISO8601 = raw(photo, "dateTimeOriginalISO8601"),
		dateTimeISO8601 = raw(photo, "dateTimeISO8601"),
		dateTimeDigitizedISO8601 = raw(photo, "dateTimeDigitizedISO8601"),
		dateTimeOriginal = raw(photo, "dateTimeOriginal"),
		dateTime = raw(photo, "dateTime"),
		dateTimeDigitized = raw(photo, "dateTimeDigitized"),
		lastEditTime = raw(photo, "lastEditTime"),
	}, {
		fileName = formatted(photo, "fileName"),
		copyName = formatted(photo, "copyName"),
	})
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
