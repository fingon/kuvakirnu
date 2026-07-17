return {
	version = 1,
	photos = {
		exported = {
			outputPath = "/out/exported.jpg",
			status = "exported",
		},
		failed = {
			sourcePath = "/source/failed.raw",
			outputPath = "/out/failed.jpg",
			status = "failed",
			lastError = "offline original",
		},
		orphaned = {
			sourcePath = "/source/orphan.raw",
			outputPath = "/out/stable-orphan.jpg",
			fingerprint = "legacy fingerprint",
			status = "orphaned",
			orphanedAt = "2026-07-05T07:06:09Z",
		},
	},
}
