return {
	LrSdkVersion = 13.0,
	LrSdkMinimumVersion = 6.0,
	LrToolkitIdentifier = "fi.lehteni.immich-derivative-sync",
	LrPluginName = "Immich Derivative Sync",
	LrPluginInfoProvider = "SettingsProvider.lua",
	LrLibraryMenuItems = {
		{
			title = "Sync Derivatives to Folder",
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
