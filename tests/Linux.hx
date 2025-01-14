class Linux {
	static public function isAptPackageInstalled(aptPackage:String):Bool {
		return Util.commandSucceed("dpkg-query", ["-W", "-f='${Status}'", aptPackage]);
	}

	static public function requireAptPackages(packages:Array<String>):Void {
		var notYetInstalled = [for (p in packages) if (!isAptPackageInstalled(p)) p];
		if (notYetInstalled.length > 0) {
			var aptCacheDir = Sys.getEnv("APT_CACHE_DIR");
			var baseCommand = if (aptCacheDir != null) {
				["apt-get", "-o", 'dir::cache::archives=${aptCacheDir}', "install", "-qqy"];
			} else {
				["apt-get", "install", "-qqy"];
			};
			Util.runCommand("sudo", baseCommand.concat(notYetInstalled), true);
		}
	}
}
