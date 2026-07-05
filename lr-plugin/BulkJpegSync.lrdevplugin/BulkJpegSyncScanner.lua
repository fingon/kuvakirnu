local Photo = require "BulkJpegSyncPhoto"

local Scanner = {}
local exportedStatus = "exported"
local trustedCatalogSelection = "trustedCatalogSelection"

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

local function metadataMismatch(photo, config)
	if photo.ratingMissing then
		return "missing"
	end
	if Scanner.matches(photo, config) then
		return nil
	end

	return "mismatched"
end

local function selected(photo, config, options)
	if options and options[trustedCatalogSelection] then
		if photo.isVirtualCopy and not config.includeVirtualCopies then
			return false
		end

		return true
	end

	return Scanner.matches(photo, config)
end

local function progressDone(options, index, total)
	if not options or not options.progressStart or not options.progressEnd or not options.progressTotal then
		return index, total
	end
	if total <= 0 then
		return options.progressEnd, options.progressTotal
	end

	return options.progressStart + math.floor((options.progressEnd - options.progressStart) * index / total), options.progressTotal
end

local function olderThan(timestamp, threshold)
	return threshold ~= nil and threshold ~= "" and (timestamp == nil or timestamp == "" or timestamp < threshold)
end

local function epochChanged(recordValue, configValue, lastExportTime)
	if configValue == nil or configValue == "" then
		return false
	end
	if recordValue ~= nil and recordValue ~= "" then
		return recordValue ~= configValue
	end

	return olderThan(lastExportTime, configValue)
end

local function needsExport(record, fingerprint, outputPath, config, fileExists)
	return record == nil
		or record.status ~= exportedStatus
		or record.fingerprint ~= fingerprint
		or record.exportSettingsVersion ~= config.exportSettingsVersion
		or epochChanged(record.pluginVersionTimestamp, config.pluginVersionTimestamp, record.lastExportTime)
		or epochChanged(record.outputSettingsChangedAt, config.outputSettingsChangedAt, record.lastExportTime)
		or record.outputSettingsFingerprint ~= config.outputSettingsFingerprint
		or not fileExists(outputPath)
end

function Scanner.plan(photos, state, config, pathGenerator, fileExists, progressScope, options)
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
		metadataMissing = 0,
		metadataMismatched = 0,
		captureDateMissing = 0,
	}

	for index, handle in ipairs(photos) do
		if canceled(progressScope) then
			return nil, "sync canceled"
		end
		if progressScope and index % 100 == 0 then
			local done, total = progressDone(options, index, totalPhotos)
			progressScope:setCaption("Planning derivatives " .. tostring(index) .. " of " .. tostring(totalPhotos))
			progressScope:setPortionComplete(done, total)
			yield()
		end

		local photo = handle.identifier and handle or Photo.snapshot(handle)
		local record = state.photos[photo.identifier]
		seen[photo.identifier] = true
		if photo.captureDateMissing then
			stats.captureDateMissing = stats.captureDateMissing + 1
		end

		if selected(photo, config, options) then
			stats.selected = stats.selected + 1
			if options and options[trustedCatalogSelection] then
				local mismatch = metadataMismatch(photo, config)
				if mismatch == "missing" then
					stats.metadataMissing = stats.metadataMissing + 1
				elseif mismatch == "mismatched" then
					stats.metadataMismatched = stats.metadataMismatched + 1
				end
			end
			local outputPath = record and record.outputPath or pathGenerator(config.outputDirectory, photo)
			local fingerprint = Photo.fingerprint(photo)

			if needsExport(record, fingerprint, outputPath, config, fileExists) then
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
		local done, total = progressDone(options, totalPhotos, totalPhotos)
		progressScope:setCaption("Planning derivatives " .. tostring(totalPhotos) .. " of " .. tostring(totalPhotos))
		progressScope:setPortionComplete(done, total)
	end

	return {
		exports = exports,
		orphans = orphans,
		seen = seen,
		stats = stats,
	}
end

return Scanner
