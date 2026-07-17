return {
	LrSdkVersion = 13.0,
	LrSdkMinimumVersion = 6.0,
	LrToolkitIdentifier = "fi.iki.fingon.bulk-jpeg-sync",
	LrPluginName = "Bulk JPEG Sync",
	LrPluginInfoProvider = "SettingsProvider.lua",
	LrInitPlugin = "PluginInit.lua",
	LrForceInitPlugin = true,
	LrShutdownPlugin = "PluginShutdown.lua",
	LrShutdownApp = "AppShutdown.lua",
	LrLibraryMenuItems = {
		{
			title = "Sync JPEGs to Folder",
			file = "SyncMenu.lua",
		},
	},
	LrExportMenuItems = {
		{
			title = "Sync JPEGs to Folder",
			file = "SyncMenu.lua",
		},
	},
	VERSION = {
		major = 0,
		minor = 1,
		revision = 0,
		build = 1,
	},
}
