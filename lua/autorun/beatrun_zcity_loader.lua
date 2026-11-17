-- Which copy is this? Two copies of the addon in garrysmod/addons makes the game load the older one,
-- and the player keeps seeing the old version no matter how often they download the new zip. Print the
-- real path (and shout if a second copy already initialised) so this is impossible to miss.
local THIS_VERSION = "2.21.33"
local thisFile = (debug and debug.getinfo and debug.getinfo(1, "S") and debug.getinfo(1, "S").short_src) or "?"

-- 2.21.33: the addon keeps the console silent. ONE command prints every log line it has:
--   Beatrun_ZCity_Log 1
-- (0 turns it off again; the old Beatrun_RollDebugLog still works as well). Console commands such as
-- beatrun_zcity_version / beatrun_zcity_debug always print - they only run when you ask for them.
if SERVER then
	CreateConVar("Beatrun_ZCity_Log", "0", FCVAR_ARCHIVE, "Beatrun Z-City: print the addon's console log (one landing line per landing, climb decisions, camera wrap)", 0, 1)
else
	CreateClientConVar("Beatrun_ZCity_Log", "0", true, false, "Beatrun Z-City: print the addon's console log (one landing line per landing, climb decisions, camera wrap)", 0, 1)
end

local function LogOn()
	local cv = GetConVar("Beatrun_ZCity_Log")
	if cv and cv:GetBool() then return true end
	local old = GetConVar("Beatrun_RollDebugLog")
	if old and old:GetBool() then return true end
	return false
end

if LogOn() and BeatrunZCity and BeatrunZCity.Version and BeatrunZCity.Version ~= THIS_VERSION then
	print("======================================================================")
	print("[Beatrun Z-City] TWO COPIES OF THE ADDON ARE INSTALLED!")
	print("[Beatrun Z-City]   already loaded: version " .. tostring(BeatrunZCity.Version) .. " from " .. tostring(BeatrunZCity.Path))
	print("[Beatrun Z-City]   this copy     : version " .. THIS_VERSION .. " from " .. thisFile)
	print("[Beatrun Z-City] delete the older folder in garrysmod/addons, keep one.")
	print("======================================================================")
end

BeatrunZCity = BeatrunZCity or {}
BeatrunZCity.Version = THIS_VERSION
BeatrunZCity.Path = thisFile
BeatrunZCity.Mode = "slide_and_roll_only"

if LogOn() then print("[Beatrun Z-City] version " .. THIS_VERSION .. " loaded from " .. thisFile) end

local BASE = "beatrun_zcity/"

local function LoadFolder(sub, realm)
	local files = file.Find(BASE .. sub .. "/*.lua", "LUA")
	if not files then return end

	table.sort(files)

	for _, fname in ipairs(files) do
		local path = BASE .. sub .. "/" .. fname

		if realm == "sh" then
			if SERVER then AddCSLuaFile(path) end
			include(path)
		elseif realm == "sv" then
			if SERVER then include(path) end
		elseif realm == "cl" then
			if SERVER then
				AddCSLuaFile(path)
			else
				include(path)
			end
		end
	end
end

LoadFolder("sh", "sh")
LoadFolder("sv", "sv")
LoadFolder("cl", "cl")
