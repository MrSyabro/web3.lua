package = "Web3.lua"
version = "dev-1"
source = {
   url = "git+https://github.com/MrSyabro/web3.lua.git" -- We don't have one yet
}
description = {
   summary = "Web3.Lua simpli library",
   homepage = "https://github.com/MrSyabro/web3.lua", -- We don't have one yet
   license = "MIT/X11" -- or whatever you like
}
dependencies = {
   "lua >= 5.2",
   "dkjson",
   "luasec",
   "luasocket",
   -- If you depend on other rocks, add them here
}
build = {
	type = "builtin",
	modules = {
		web3 = "src/web3.lua",
	}
	-- Now we need to tell it what to build.
}
