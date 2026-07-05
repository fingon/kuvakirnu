local Photo = require "ImmichDerivativeSyncPhoto"

local Scanner = {}

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

function Scanner.plan(photos, state, config, pathGenerator, fileExists)
	local exports = {}
	local orphans = {}
	local seen = {}

	for _, handle in ipairs(photos) do
		local photo = handle.identifier and handle or Photo.snapshot(handle)
		local record = state.photos[photo.identifier]
		seen[photo.identifier] = true

		if Scanner.matches(photo, config) then
			local outputPath = record and record.outputPath or pathGenerator(config.outputDirectory, photo)
			local fingerprint = Photo.fingerprint(photo)
			local needsExport = record == nil
				or record.status ~= "exported"
				or record.fingerprint ~= fingerprint
				or record.exportSettingsVersion ~= config.exportSettingsVersion
				or not fileExists(outputPath)

			if needsExport then
				exports[#exports + 1] = {
					photo = photo,
					outputPath = outputPath,
					fingerprint = fingerprint,
				}
			end
		elseif record and record.status == "exported" then
			orphans[#orphans + 1] = {
				photo = photo,
				record = record,
			}
		end
	end

	return {
		exports = exports,
		orphans = orphans,
		seen = seen,
	}
end

return Scanner
