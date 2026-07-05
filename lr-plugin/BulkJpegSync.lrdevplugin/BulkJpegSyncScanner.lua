local Photo = require "BulkJpegSyncPhoto"

local Scanner = {}
local exportedStatus = "exported"

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

local function yield()
	local LrTasks = maybeImport("LrTasks")
	if LrTasks and LrTasks.yield then
		LrTasks.yield()
	end
end

local function canceled(progressScope)
	return progressScope and progressScope.isCanceled and progressScope:isCanceled()
end

function Scanner.matches(photo, config)
	if photo.isVirtualCopy and not config.includeVirtualCopies then
		return false
	end
	if photo.isRejected then
		return false
	end

	local rating = tonumber(photo.rating) or 0
	if rating == 0 then
		return config.includeUnstarred == true
	end
	if config.minRating == nil then
		return false
	end

	return rating >= config.minRating
end

function Scanner.plan(photos, state, config, pathGenerator, fileExists, progressScope)
	local exports = {}
	local orphans = {}
	local seen = {}
	local totalPhotos = #photos
	local stats = {
		candidates = totalPhotos,
		selected = 0,
		skipped = 0,
		orphaned = 0,
		ignored = 0,
	}

	for index, handle in ipairs(photos) do
		if canceled(progressScope) then
			return nil, "sync canceled"
		end
		if progressScope and index % 100 == 0 then
			progressScope:setCaption("Planning derivatives " .. tostring(index) .. " of " .. tostring(totalPhotos))
			progressScope:setPortionComplete(index, totalPhotos)
			yield()
		end

		local photo = handle.identifier and handle or Photo.snapshot(handle)
		local record = state.photos[photo.identifier]
		seen[photo.identifier] = true

		if Scanner.matches(photo, config) then
			stats.selected = stats.selected + 1
			local outputPath = record and record.outputPath or pathGenerator(config.outputDirectory, photo)
			local fingerprint = Photo.fingerprint(photo)
			local needsExport = record == nil
				or record.status ~= exportedStatus
				or record.fingerprint ~= fingerprint
				or record.exportSettingsVersion ~= config.exportSettingsVersion
				or not fileExists(outputPath)

			if needsExport then
				exports[#exports + 1] = {
					photo = photo,
					outputPath = outputPath,
					fingerprint = fingerprint,
				}
			else
				stats.skipped = stats.skipped + 1
			end
		elseif record and record.status == exportedStatus then
			orphans[#orphans + 1] = {
				identifier = photo.identifier,
				photo = photo,
				record = record,
			}
			stats.orphaned = stats.orphaned + 1
		else
			stats.ignored = stats.ignored + 1
		end
	end

	for identifier, record in pairs(state.photos) do
		if record.status == exportedStatus and not seen[identifier] then
			orphans[#orphans + 1] = {
				identifier = identifier,
				record = record,
			}
			stats.orphaned = stats.orphaned + 1
		end
	end

	if progressScope then
		progressScope:setCaption("Planning derivatives " .. tostring(totalPhotos) .. " of " .. tostring(totalPhotos))
		progressScope:setPortionComplete(totalPhotos, totalPhotos)
	end

	return {
		exports = exports,
		orphans = orphans,
		seen = seen,
		stats = stats,
	}
end

return Scanner
