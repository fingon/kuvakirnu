local Catalog = {}

local rejectedPickValue = -1
local rawMetadataKeys = {
	"uuid",
	"path",
	"rating",
	"pickStatus",
	"isVirtualCopy",
	"dateTimeOriginalISO8601",
	"dateTimeISO8601",
	"dateTimeDigitizedISO8601",
	"dateTimeOriginal",
	"dateTime",
	"dateTimeDigitized",
	"lastEditTime",
}
local formattedMetadataKeys = {
	"fileName",
	"copyName",
}

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

function Catalog.batchMetadata(catalog, photos)
	if not catalog or not catalog.batchGetRawMetadata or not catalog.batchGetFormattedMetadata then
		return nil, "Lightroom batch metadata is unavailable"
	end

	local rawMetadata = catalog:batchGetRawMetadata(photos, rawMetadataKeys) or {}
	local formattedMetadata = catalog:batchGetFormattedMetadata(photos, formattedMetadataKeys) or {}

	return {
		raw = rawMetadata,
		formatted = formattedMetadata,
	}
end

function Catalog.rawMetadataKeys()
	return rawMetadataKeys
end

function Catalog.formattedMetadataKeys()
	return formattedMetadataKeys
end

return Catalog
