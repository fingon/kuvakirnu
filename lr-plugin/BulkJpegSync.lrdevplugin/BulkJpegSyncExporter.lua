local FileUtils = require("BulkJpegSyncFileUtils")
local Logger = require("BulkJpegSyncLogger")
local Path = require("BulkJpegSyncPath")

local Exporter = {}

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

local function mkdirp(directory)
	local LrFileUtils = maybeImport("LrFileUtils")
	if LrFileUtils and LrFileUtils.createAllDirectories then
		local ok, err = LrFileUtils.createAllDirectories(directory)
		if ok == false then
			return nil, err
		end
		return true
	end

	if directory == "." then
		return true
	end

	return nil, "failed to create output directory: " .. directory
end

function Exporter.fileExists(path)
	local LrFileUtils = maybeImport("LrFileUtils")
	if LrFileUtils and LrFileUtils.exists then
		return LrFileUtils.exists(path) == "file"
	end

	local file = io.open(path, "r")
	if file then
		file:close()
		return true
	end

	return false
end

function Exporter.exportSettings(config, temporaryDirectory)
	return {
		LR_export_destinationType = "specificFolder",
		LR_export_destinationPathPrefix = temporaryDirectory,
		LR_export_useSubfolder = false,
		LR_format = "JPEG",
		LR_jpeg_quality = config.jpegQuality / 100,
		LR_size_doConstrain = true,
		LR_size_doNotEnlarge = true,
		LR_size_maxHeight = config.longEdgePixels,
		LR_size_maxWidth = config.longEdgePixels,
		LR_size_units = "pixels",
		LR_outputSharpeningOn = false,
		LR_embeddedMetadataOption = "all",
		LR_metadata_keywordOptions = "lightroomHierarchical",
		LR_minimizeEmbeddedMetadata = false,
		LR_removeLocationMetadata = false,
		LR_includeVideoFiles = false,
		LR_collisionHandling = "overwrite",
	}
end

function Exporter.exportItems(items, config, progressScope)
	if #items == 0 then
		return {}
	end
	local LrExportSession = maybeImport("LrExportSession")
	if not LrExportSession then
		return nil, "LrExportSession is unavailable"
	end

	local photos = {}
	local itemByPhoto = {}
	local outcomes = {}
	for _, item in ipairs(items) do
		photos[#photos + 1] = item.photo.handle
		itemByPhoto[item.photo.handle] = item
		outcomes[item] = { status = "pending" }
	end

	local temporaryDirectory = Path.dirname(items[1].outputPath)
		.. "/.bulk-jpeg-sync-tmp"
	local ok, dirErr = mkdirp(temporaryDirectory)
	if not ok then
		return nil, dirErr
	end

	local session = LrExportSession({
		photosToExport = photos,
		exportSettings = Exporter.exportSettings(config, temporaryDirectory),
	})

	local renditionOptions = { stopIfCanceled = true }
	if progressScope then
		renditionOptions.progressScope = progressScope
	end
	for _, rendition in session:renditions(renditionOptions) do
		local item = itemByPhoto[rendition.photo]
		if not item or outcomes[item].status ~= "pending" then
			for _, pendingItem in ipairs(items) do
				if outcomes[pendingItem].status == "pending" then
					outcomes[pendingItem] = {
						status = "failed",
						error = "Lightroom returned an extra, duplicate, or unmappable rendition",
					}
				end
			end
			break
		end
		if progressScope then
			progressScope:setCaption("Exporting " .. item.photo.fileName)
		end

		local success, exportedPathOrMessage = rendition:waitForRender()
		if not success then
			outcomes[item] = {
				status = "failed",
				error = tostring(exportedPathOrMessage),
			}
		else
			local finalDirOk, finalDirErr =
				mkdirp(Path.dirname(item.outputPath))
			if not finalDirOk then
				outcomes[item] = {
					status = "failed",
					error = tostring(finalDirErr),
				}
			else
				local replaced, replaceErr = FileUtils.replaceFile(
					exportedPathOrMessage,
					item.outputPath
				)
				if not replaced then
					outcomes[item] = {
						status = "failed",
						error = tostring(replaceErr),
					}
				else
					outcomes[item] = { status = "exported" }
					if replaceErr then
						Logger.warn("export_backup_cleanup_failed", {
							output = item.outputPath,
							error = replaceErr,
						})
					end
				end
			end
		end
	end

	local wasCanceled = progressScope
		and progressScope.isCanceled
		and progressScope:isCanceled()
	for _, item in ipairs(items) do
		if outcomes[item].status == "pending" then
			if wasCanceled then
				outcomes[item] = { status = "canceled" }
			else
				outcomes[item] = {
					status = "failed",
					error = "Lightroom returned no rendition for the photo",
				}
			end
		end
	end

	return outcomes
end

return Exporter
