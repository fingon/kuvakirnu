local Incremental = {}

function Incremental.lastEditTimeSec(value)
	if value == nil or value == "" then
		return nil
	end
	local number = tonumber(value)
	if number then
		return number
	end

	local year, month, day, hour, min, sec = tostring(value):match(
		"^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)"
	)
	if not year then
		return nil
	end

	return os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec),
	})
end

function Incremental.window(
	previousProcessedThroughSec,
	startedAtSec,
	cooldownSec
)
	local upperBoundSec = startedAtSec - cooldownSec
	return {
		lowerBoundSec = previousProcessedThroughSec,
		upperBoundSec = upperBoundSec,
		ready = upperBoundSec > previousProcessedThroughSec,
	}
end

function Incremental.includes(photo, window)
	local editedAtSec = Incremental.lastEditTimeSec(photo.lastEditTime)
	return editedAtSec ~= nil
		and editedAtSec > window.lowerBoundSec
		and editedAtSec <= window.upperBoundSec
end

function Incremental.filter(photos, window)
	local filtered = {}
	for _, photo in ipairs(photos) do
		if Incremental.includes(photo, window) then
			filtered[#filtered + 1] = photo
		end
	end

	return filtered
end

return Incremental
