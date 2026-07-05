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

local function operationError(operation, sourcePath, targetPath, err)
	local message = tostring(err or "unknown error")
	if targetPath then
		return string.format(
			"failed to %s file source=%s target=%s error=%s",
			operation,
			tostring(sourcePath),
			tostring(targetPath),
			message
		)
	end

	return string.format("failed to %s file path=%s error=%s", operation, tostring(sourcePath), message)
end

local function fileExists(path)
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
		if ok == true then
			return true
		end
		return nil, operationError("move", sourcePath, targetPath, err)
	end

	local ok, err = os.rename(sourcePath, targetPath)
	if not ok then
		return nil, operationError("move", sourcePath, targetPath, err)
	end

	return true
end

local function deleteFile(path)
	local LrFileUtils = maybeImport("LrFileUtils")
	if LrFileUtils and LrFileUtils.delete then
		local ok, err = LrFileUtils.delete(path)
		if ok == false then
			return nil, operationError("delete", path, nil, err)
		end
		return true
	end

	local ok, err = os.remove(path)
	if not ok then
		return nil, operationError("delete", path, nil, err)
	end

	return true
end

local function replaceFile(sourcePath, targetPath, options)
	options = options or {}
	local backupPath = options.backupPath
	local backedUp = false

	if fileExists(targetPath) then
		if backupPath then
			if fileExists(backupPath) then
				local deletedBackup, deleteBackupErr = deleteFile(backupPath)
				if not deletedBackup then
					return nil, deleteBackupErr
				end
			end

			local movedBackup, moveBackupErr = moveFile(targetPath, backupPath)
			if not movedBackup then
				return nil, moveBackupErr
			end
			backedUp = true
		else
			local deletedTarget, deleteTargetErr = deleteFile(targetPath)
			if not deletedTarget then
				return nil, deleteTargetErr
			end
		end
	end

	local movedReplacement, moveReplacementErr = moveFile(sourcePath, targetPath)
	if movedReplacement then
		return true
	end
	if not backedUp then
		return nil, moveReplacementErr
	end

	local restored, restoreErr = moveFile(backupPath, targetPath)
	if not restored then
		return nil, moveReplacementErr .. "; failed to restore backup: " .. tostring(restoreErr)
	end

	return nil, moveReplacementErr
end

return {
	maybeImport = maybeImport,
	fileExists = fileExists,
	moveFile = moveFile,
	deleteFile = deleteFile,
	replaceFile = replaceFile,
}
