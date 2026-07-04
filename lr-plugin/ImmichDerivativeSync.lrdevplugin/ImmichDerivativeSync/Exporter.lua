local Path = require "ImmichDerivativeSync.Path"

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

	local command = string.format("mkdir -p %q", directory)
	local ok = os.execute(command)
	if ok == true or ok == 0 then
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

local function moveFile(sourcePath, targetPath)
	local LrFileUtils = maybeImport("LrFileUtils")
	if LrFileUtils and LrFileUtils.move then
		local ok, err = LrFileUtils.move(sourcePath, targetPath)
		if ok == false then
			return nil, err
		end
		return true
	end

	local ok, err = os.rename(sourcePath, targetPath)
	if not ok then
		return nil, err
	end

	return true
end

function Exporter.exportSettings(config, temporaryDirectory)
	return {
		LR_export_destinationType = "specificFolder",
		LR_export_destinationPathPrefix = temporaryDirectory,
		LR_export_useSubfolder = false,
		LR_format = "JPEG",
		LR_jpeg_quality = config.jpegQuality / 100,
		LR_size_doConstrain = true,
		LR_size_maxHeight = config.longEdgePixels,
		LR_size_maxWidth = config.longEdgePixels,
		LR_size_units = "pixels",
		LR_outputSharpeningOn = false,
		LR_embeddedMetadataOption = "all",
		LR_minimizeEmbeddedMetadata = false,
		LR_includeVideoFiles = false,
		LR_collisionHandling = "overwrite",
	}
end

function Exporter.exportItems(items, config, progressScope)
	local LrExportSession = maybeImport("LrExportSession")
	if not LrExportSession then
		return nil, "LrExportSession is unavailable"
	end

	local photos = {}
	for _, item in ipairs(items) do
		photos[#photos + 1] = item.photo.handle
	end

	local temporaryDirectory = Path.dirname(items[1].outputPath) .. "/.immich-derivative-sync-tmp"
	local ok, dirErr = mkdirp(temporaryDirectory)
	if not ok then
		return nil, dirErr
	end

	local session = LrExportSession({
		photosToExport = photos,
		exportSettings = Exporter.exportSettings(config, temporaryDirectory),
	})

	local index = 0
	for _, rendition in session:renditions({ stopIfCanceled = true }) do
		index = index + 1
		local item = items[index]
		if progressScope then
			progressScope:setPortionComplete(index - 1, #items)
			progressScope:setCaption("Exporting " .. item.photo.fileName)
		end

		local success, exportedPathOrMessage = rendition:waitForRender()
		if not success then
			return nil, exportedPathOrMessage
		end

		local finalDirOk, finalDirErr = mkdirp(Path.dirname(item.outputPath))
		if not finalDirOk then
			return nil, finalDirErr
		end

		local moved, moveErr = moveFile(exportedPathOrMessage, item.outputPath)
		if not moved then
			return nil, moveErr
		end
	end

	if progressScope then
		progressScope:setPortionComplete(#items, #items)
	end

	return true
end

return Exporter
