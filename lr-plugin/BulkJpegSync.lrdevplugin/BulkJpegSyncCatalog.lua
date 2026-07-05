local Catalog = {}

local rejectedPickValue = -1

local function ratingCriterion(operation, value)
	return {
		criteria = "rating",
		operation = operation,
		value = value,
	}
end

local function nonRejectedCriterion()
	return {
		criteria = "pick",
		operation = "!=",
		value = rejectedPickValue,
	}
end

local function ratingSearch(config)
	local searches = {}
	if config.includeUnstarred == true then
		searches[#searches + 1] = ratingCriterion("==", 0)
	end
	if config.minRating ~= nil then
		searches[#searches + 1] = ratingCriterion(">=", config.minRating)
	end

	if #searches == 1 then
		return searches[1]
	end

	local union = { combine = "union" }
	for _, search in ipairs(searches) do
		union[#union + 1] = search
	end

	return union
end

function Catalog.searchDescription(config)
	return {
		combine = "intersect",
		nonRejectedCriterion(),
		ratingSearch(config),
	}
end

function Catalog.findCandidates(catalog, config)
	if not catalog or not catalog.findPhotos then
		return nil, "Lightroom catalog search is unavailable"
	end

	local photos = catalog:findPhotos({
		searchDesc = Catalog.searchDescription(config),
	})

	return photos or {}
end

return Catalog
