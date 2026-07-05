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
	if
		not catalog
		or not catalog.batchGetRawMetadata
		or not catalog.batchGetFormattedMetadata
	then
		return nil, "Lightroom batch metadata is unavailable"
	end

	local rawMetadata = catalog:batchGetRawMetadata(photos, rawMetadataKeys)
		or {}
	local formattedMetadata = catalog:batchGetFormattedMetadata(
		photos,
		formattedMetadataKeys
	) or {}

	return {
		raw = rawMetadata,
		formatted = formattedMetadata,
	}
end

local function photoIdentifier(photo)
	if type(photo) == "table" and photo.localIdentifier then
		return tostring(photo.localIdentifier)
	end
	if type(photo) == "table" and photo.id then
		return tostring(photo.id)
	end
	return tostring(photo)
end

local function collectSmartCollections(source)
	local result = {}

	local collections = source:getChildCollections() or {}
	for _, item in ipairs(collections) do
		if item.isSmartCollection and item:isSmartCollection() then
			result[#result + 1] = item
		end
	end

	local sets = source:getChildCollectionSets() or {}
	for _, set in ipairs(sets) do
		local nested = collectSmartCollections(set)
		for _, n in ipairs(nested) do
			result[#result + 1] = n
		end
	end

	return result
end

function Catalog.getMatchingSmartCollections(catalog, nameSubstring)
	if not catalog then
		return {}
	end

	local all = collectSmartCollections(catalog)
	if nameSubstring == nil or nameSubstring == "" then
		return all
	end

	local matching = {}
	for _, sc in ipairs(all) do
		local name = sc:getName() or ""
		if name:find(nameSubstring, 1, true) then
			matching[#matching + 1] = sc
		end
	end

	return matching
end

function Catalog.photosFromSmartCollections(catalog, smartCollections)
	if not smartCollections then
		return {}
	end

	local seen = {}
	local photos = {}
	for _, sc in ipairs(smartCollections) do
		local collectionPhotos = sc:getPhotos() or {}
		for _, photo in ipairs(collectionPhotos) do
			local id = photoIdentifier(photo)
			if not seen[id] then
				seen[id] = true
				photos[#photos + 1] = photo
			end
		end
	end

	return photos
end

function Catalog.findBySmartCollectionFilter(catalog, nameSubstring)
	local matching = Catalog.getMatchingSmartCollections(catalog, nameSubstring)
	return Catalog.photosFromSmartCollections(catalog, matching)
end

function Catalog.unionPhotoLists(list1, list2)
	if #list1 == 0 then
		return list2
	end
	if #list2 == 0 then
		return list1
	end

	local seen = {}
	local result = {}
	for _, photo in ipairs(list1) do
		local id = photoIdentifier(photo)
		seen[id] = true
		result[#result + 1] = photo
	end
	for _, photo in ipairs(list2) do
		local id = photoIdentifier(photo)
		if not seen[id] then
			seen[id] = true
			result[#result + 1] = photo
		end
	end

	return result
end

function Catalog.rawMetadataKeys()
	return rawMetadataKeys
end

function Catalog.formattedMetadataKeys()
	return formattedMetadataKeys
end

return Catalog
