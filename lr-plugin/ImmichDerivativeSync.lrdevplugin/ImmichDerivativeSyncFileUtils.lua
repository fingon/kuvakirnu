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

local function deleteFile(path)
	local LrFileUtils = maybeImport("LrFileUtils")
	if LrFileUtils and LrFileUtils.delete then
		LrFileUtils.delete(path)
		return true
	end

	local ok, err = os.remove(path)
	if not ok then
		return nil, err
	end

	return true
end

return {
	maybeImport = maybeImport,
	moveFile = moveFile,
	deleteFile = deleteFile,
}
