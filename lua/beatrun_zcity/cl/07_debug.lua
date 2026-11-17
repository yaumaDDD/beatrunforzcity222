-- Diagnostic command: prints why the Beatrun body animation is (not) playing for the local player.
-- Usage: beatrun_zcity_debug  (in console) - useful to report problems.

local function Safe(fn, ...)
	if not isfunction(fn) then return "n/a" end

	local ok, res = pcall(fn, ...)
	return ok and tostring(res) or "error"
end

local function Report()
	local ply = LocalPlayer()
	if not IsValid(ply) then
		print("[Beatrun Z-City] no local player")
		return
	end

	local cvHideBody = GetConVar("Beatrun_SlideHideBody")
	local rollEnd = Safe(ply.GetSafetyRollTime, ply)
	local rollLeft = tonumber(rollEnd) and string.format("%.2f", tonumber(rollEnd) - CurTime()) or rollEnd

	print("========== BEATRUN Z-CITY DEBUG ==========")
	print("version:            " .. tostring(BeatrunZCity and BeatrunZCity.Version))
	print("gamemode:           " .. tostring(engine.ActiveGamemode and engine.ActiveGamemode()))
	print("Z-City detected:    " .. tostring(Safe(BeatrunIsZCity)))
	print("third person:       " .. tostring(Safe(BeatrunIsThirdPerson, ply)))
	print("can slide/roll:     " .. tostring(Safe(BeatrunCanSlideOrRoll, ply)))
	print("alive / vehicle:    " .. tostring(ply:Alive()) .. " / " .. tostring(ply:InVehicle()))
	print("fake ragdoll:       " .. tostring(IsValid(ply.FakeRagdoll)))

	-- Weapon / render state: the whole "no gun in the hand" question lives here.
	local wpn = ply:GetActiveWeapon()
	local vm = ply:GetViewModel()

	local function Str(value)
		if value == nil then return "nil" end
		return tostring(value)
	end

	print("weapon:             " .. (IsValid(wpn) and Str(wpn:GetClass()) or "none"))
	if IsValid(vm) then
		print("viewmodel:          valid=true nodraw=" .. Str(vm:GetNoDraw()))
	else
		print("viewmodel:          valid=false (Z-City weapons draw as world models at the hand)")
	end
	print("Z-City render:      DrawPlayerRagdoll=" .. Str(type(DrawPlayerRagdoll)) .. " RenderOverride=" .. Str(type(ply.RenderOverride)))
	print("big appearance/ZCG: " .. (BeatrunZCityAppCompat and isfunction(BeatrunZCityAppCompat.GetDebugSummary) and BeatrunZCityAppCompat.GetDebugSummary(ply) or "n/a"))
	print("player appearance:  " .. (BeatrunZCityAppCompat and isfunction(BeatrunZCityAppCompat.GetDetailedAppearanceDebug) and BeatrunZCityAppCompat.GetDetailedAppearanceDebug(ply) or "n/a"))
	print("slide air check:    " .. tostring(Safe(function() return GetConVar("Beatrun_ZCity_SlideAirCheck"):GetBool() end)) .. " | roll holster=" .. tostring(Safe(function() return GetConVar("Beatrun_ZCity_RollHolster"):GetBool() end)))
	print("slide weapon draw:  " .. Str(BeatrunZCitySlideWeaponState) .. " | TPIK=" .. Str(BeatrunZCitySlideTPIKState) .. " | worldModel=" .. tostring(IsValid(wpn) and IsValid(wpn.worldModel)) .. " | unified=" .. tostring(IsValid(BodyAnimMDL) and BodyAnimMDL._BRZUnifiedArms))
	print("slide barrel smoke: " .. (IsValid(wpn) and IsValid(wpn.particleEffect) and "pinned to the drawn barrel" or "no smoke system right now"))
	print("slide muzzle sync:  pos=" .. Str(ply._BRZSlideMuzzlePos) .. " dir=" .. Str(ply._BRZSlideMuzzleDir)
		.. " (flash/smoke take this exact point while armed)")
	print("slide yaw limit:    +/-" .. tostring(isfunction(BeatrunGetSlideYawLimit) and BeatrunGetSlideYawLimit() or 90) .. " deg")
	print("slide armed flag:   " .. tostring(ply._BRZSlideArmed ~= nil and ply._BRZSlideArmed or false))
	print("sliding:            " .. tostring(Safe(ply.GetSliding, ply)))
	print("roll time left:     " .. tostring(rollLeft))
	print("BodyAnim:           " .. tostring(IsValid(BodyAnim)))
	print("BodyAnim string:    " .. tostring(BodyAnimString))
	print("BodyAnimModel:      " .. tostring(IsValid(BodyAnimMDL)) .. " (" .. tostring(IsValid(BodyAnimMDL) and BodyAnimMDL:GetModel() or "-") .. ")")
	print("BodyAnimArmModel:   " .. tostring(IsValid(BodyAnimMDLarm)) .. " (" .. tostring(IsValid(BodyAnimMDLarm) and BodyAnimMDLarm:GetModel() or "-") .. ")")
	print("cycle / speed:      " .. string.format("%.2f / %.2f", tonumber(BodyAnimCycle) or -1, tonumber(BodyAnimSpeed) or -1))
	print("cv HideBody:        " .. tostring(cvHideBody and cvHideBody:GetBool()))
	print("cv AnimSet:         " .. tostring(Safe(function() return GetConVar("Beatrun_AnimSet"):GetInt() end)))
	print("roll heights:       fixed knees 290..350, roll 351..750, above 750 no trick")
	print("cv TrickCam:        " .. tostring(Safe(function() return GetConVar("Beatrun_TrickCam"):GetBool() end)))
	print("cv TrickCamOffset:  " .. tostring(Safe(function() return GetConVar("Beatrun_TrickCamOffset"):GetFloat() end)))
	print("static model hidden:" .. tostring(ply._BRZHiddenOverride ~= nil))
	print("Z-City cam hooks:   " .. tostring(BeatrunZCityCalcViewHookCount) .. " found / " .. tostring(BeatrunZCityCameraWrapped) .. " wrapped")
	print("cam wrap error:     " .. tostring(BeatrunZCityCamWrapError))
	print("trick cam applied:  " .. tostring(BeatrunZCityTrickCamApplied))
	print("camjoint:           " .. tostring(camjoint) .. " (found: " .. tostring(IsValid(BodyAnim) and isstring(camjoint) and camjoint ~= "" and BodyAnim:LookupAttachment(camjoint) > 0) .. ")")
	print("head bone exists:   " .. tostring(IsValid(BodyAnim) and BodyAnim:LookupBone("ValveBiped.Bip01_Head1") ~= nil))
	local headdist = "n/a"
	if IsValid(BodyAnim) then
		local bone = BodyAnim:LookupBone("ValveBiped.Bip01_Head1")
		local pos = bone and BodyAnim:GetBonePosition(bone)
		if pos then headdist = string.format("%.1f", EyePos():Distance(pos)) end
	end
	print("cam -> head dist:   " .. headdist)
	print("cv SlideAutoHold:   " .. tostring(Safe(function() return GetConVar("Beatrun_ZCity_SlideAutoHold"):GetBool() end)))
	print("cam anchor:         " .. tostring(BeatrunZCityCamAnchor))
	print("eye cam fallback:   " .. tostring(BeatrunZCityEyeFallbackActive))
	print("cam error:          " .. tostring(BeatrunZCityCamError))
	print("new_climbanim model:" .. tostring(util.IsValidModel("models/new_climbanim.mdl")))
	print("=========================================")
end

concommand.Add("beatrun_zcity_version", function()
	print("[Beatrun Z-City] version " .. tostring(BeatrunZCity and BeatrunZCity.Version))
	print("[Beatrun Z-City] loaded from " .. tostring(BeatrunZCity and BeatrunZCity.Path))
	local anchor = GetConVar("Beatrun_TrickCamAnchor")
	print("[Beatrun Z-City] anchor " .. (anchor and anchor:GetString() or "?") .. " | lockang " .. tostring(GetConVar("Beatrun_TrickCamLockAng") and GetConVar("Beatrun_TrickCamLockAng"):GetString()))
end)

concommand.Add("beatrun_zcity_debug", Report)

-- World markers. The HUD numbers come from the same CalcView we return ourselves, so they cannot
-- prove anything. These are drawn inside the real 3D scene, from every 3D hook GMod offers, so we can
-- also see whether those hooks fire at all under Z-City's render pipeline.
local function BoneWorldPos(ent, names)
	if not IsValid(ent) then return end
	for _, name in ipairs(names) do
		local id = ent:LookupBone(name)
		if id then
			local ok, pos = pcall(ent.GetBonePosition, ent, id)
			if ok and isvector(pos) and pos ~= vector_origin then return pos end
		end
	end
end

local HEAD_BONES = { "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Neck1", "bip_head", "Head" }

BeatrunZCityMarkerHead = nil
BeatrunZCityMarkerHeadTime = 0
BeatrunZCityMarkerCalls = 0
local markerCallsWindow, markerCallsCount = 0, 0

local function DrawMarkers(hookName)
	if not IsValid(BodyAnim) then return end

	local cv = GetConVar("Beatrun_BodyMarker")
	if cv and not cv:GetBool() then return end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local head = BoneWorldPos(BodyAnim, HEAD_BONES)
	if isvector(head) then
		BeatrunZCityMarkerHead = head
		BeatrunZCityMarkerHeadTime = CurTime()
	end

	markerCallsCount = markerCallsCount + 1
	render.SetColorMaterial()

	local points = {
		{ head, Color(0, 255, 0, 255), 8 },
		{ BoneWorldPos(BodyAnimMDL, HEAD_BONES), Color(0, 128, 255, 255), 8 },
		{ ply:EyePos(), Color(255, 0, 0, 255), 8 },
		{ BeatrunZCityTrickEyePos, Color(255, 255, 0, 255), 6 },
		{ BodyAnim:GetPos(), Color(255, 0, 255, 255), 6 }
	}

	for _, p in ipairs(points) do
		if isvector(p[1]) then
			render.DrawSphere(p[1], p[3], 16, 16, p[2])
			render.DrawWireframeSphere(p[1], p[3] + 2, 12, 12, color_white, true)
		end
	end

	-- Projected label: this is drawn through the real view matrix, so its screen position shows where
	-- the animation head actually ends up no matter what CalcView reports.
	if isvector(head) then
		cam.Start3D2D(head + Vector(0, 0, 14), EyeAngles(), 0.12)
			draw.SimpleText("HEAD", "DermaLarge", 0, 0, Color(0, 255, 0, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		cam.End3D2D()
	end
end

hook.Add("PostDrawTranslucentRenderables", "BeatrunZCity_WorldMarkers", function() DrawMarkers("PostDrawTranslucent") end)
hook.Add("PreDrawOpaqueRenderables", "BeatrunZCity_WorldMarkersPre", function() DrawMarkers("PreDrawOpaque") end)

-- Marker persists for 2 seconds after the animation dies, so a screenshot taken right after a trick
-- still shows where everything was.
hook.Add("PostDrawTranslucentRenderables", "BeatrunZCity_WorldMarkersAfter", function()
	if IsValid(BodyAnim) then return end
	if not BeatrunZCityMarkerHead or (CurTime() - BeatrunZCityMarkerHeadTime) > (tonumber(GetConVar("Beatrun_BodyMarkerHold") and GetConVar("Beatrun_BodyMarkerHold"):GetFloat()) or 15) then return end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	render.SetColorMaterial()
	render.DrawSphere(BeatrunZCityMarkerHead, 8, 16, 16, Color(0, 255, 0, 120))
	render.DrawSphere(ply:EyePos(), 8, 16, 16, Color(255, 0, 0, 120))
	if isvector(BeatrunZCityTrickEyePos) then
		render.DrawSphere(BeatrunZCityTrickEyePos, 6, 16, 16, Color(255, 255, 0, 120))
	end
end)

-- Measurements in world space, no screenshot needed: printed to the console while a trick plays and
-- once as a final summary when it ends.
local lastSample, nextSample = 0, 0

local function Describe(v)
	if not isvector(v) then return "n/a" end
	return string.format("(%.1f %.1f %.1f)", v.x, v.y, v.z)
end

local function Dist(a, b)
	if not isvector(a) or not isvector(b) then return -1 end
	return a:Distance(b)
end

function BeatrunZCityMeasure()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local animHead = IsValid(BodyAnim) and BoneWorldPos(BodyAnim, HEAD_BONES) or BeatrunZCityMarkerHead
	local bodyHead = IsValid(BodyAnimMDL) and BoneWorldPos(BodyAnimMDL, HEAD_BONES) or nil
	local eye = ply:EyePos()
	local cam = BeatrunZCityTrickEyePos

	BeatrunZCityLastMeasure = {
		animHead = animHead, bodyHead = bodyHead, eye = eye, cam = cam,
		dCamHead = Dist(cam, animHead),
		dBodyHead = Dist(bodyHead, animHead),
		dEyeHead = Dist(eye, animHead),
		time = CurTime()
	}

	local m = BeatrunZCityLastMeasure
	print(string.format(
		"[Beatrun Z-City] anchor %s | cam vs anim head %.2f | drawn body head vs anim head %.2f | your eye vs anim head %.2f",
		tostring(BeatrunZCityCamAnchor), m.dCamHead, m.dBodyHead, m.dEyeHead))
	print(string.format(
		"[Beatrun Z-City] anim head %s | body head %s | requested cam %s | eye %s",
		Describe(animHead), Describe(bodyHead), Describe(cam), Describe(eye)))
	return m
end

concommand.Add("beatrun_zcity_lastcam", function()
	local m = BeatrunZCityLastMeasure
	if not m then
		print("[Beatrun Z-City] no measurement yet - do a trick first")
		return
	end
	print(string.format("[Beatrun Z-City] last measurement %.1fs ago", CurTime() - m.time))
	BeatrunZCityMeasure()
end)

hook.Add("Think", "BeatrunZCity_MeasureTick", function()
	local cvReport = GetConVar("Beatrun_CamReport")
	if not cvReport or not cvReport:GetBool() then return end
	if not IsValid(BodyAnim) then return end
	if nextSample > CurTime() then return end
	nextSample = CurTime() + 1
	BeatrunZCityMeasure()
end)

hook.Add("Think", "BeatrunZCity_MarkerRate", function()
	if markerCallsWindow < CurTime() then
		BeatrunZCityMarkerCalls = markerCallsCount
		markerCallsCount = 0
		markerCallsWindow = CurTime() + 1
	end
end)

-- Live trick camera tuning. The exact camera height depends on the rig's pose (the slide puts the
-- CameraJoint inside the body), so instead of guessing a number, tune it while the animation plays.
local function TuneAxis(convar, delta, dt, rate, minv, maxv)
	local cv = GetConVar(convar)
	if not cv then return false end
	local v = math.Clamp(cv:GetFloat() + delta * dt * rate, minv, maxv)
	RunConsoleCommand(convar, tostring(math.Round(v, 1)))
	return true
end

hook.Add("Think", "BeatrunZCity_CamTune", function()
	local cvTune = GetConVar("Beatrun_TrickCamTune")
	if cvTune and not cvTune:GetBool() then return end
	if not IsValid(BodyAnim) then return end

	local dt = FrameTime()
	local changed = false
	if input.IsKeyDown(KEY_PAD_8) then changed = TuneAxis("Beatrun_TrickCamUp", 1, dt, 24, -64, 64) or changed end
	if input.IsKeyDown(KEY_PAD_2) then changed = TuneAxis("Beatrun_TrickCamUp", -1, dt, 24, -64, 64) or changed end
	if input.IsKeyDown(KEY_PAD_4) then changed = TuneAxis("Beatrun_TrickCamOffset", -1, dt, 24, -64, 64) or changed end
	if input.IsKeyDown(KEY_PAD_6) then changed = TuneAxis("Beatrun_TrickCamOffset", 1, dt, 24, -64, 64) or changed end

	if changed then
		local up = GetConVar("Beatrun_TrickCamUp")
		local off = GetConVar("Beatrun_TrickCamOffset")
		BeatrunZCityTuneText = string.format("tune  up %+0.1f   fwd %+0.1f", up and up:GetFloat() or 0, off and off:GetFloat() or 0)
	end
end)

-- Camera tuning from the console (no numpad needed):
--   beatrun_cam_up 4        absolute height
--   beatrun_cam_up +2       add 2 to the current height
--   beatrun_cam_fwd -6      move the camera 6 units back
--   beatrun_cam_show        print the current values
--   beatrun_cam_reset       back to the shipped values
local CAM_COMMANDS = {
	["beatrun_cam_up"] = { convar = "Beatrun_TrickCamUp", label = "height above the animation head" },
	["beatrun_cam_fwd"] = { convar = "Beatrun_TrickCamOffset", label = "forward/back offset" },
	["beatrun_cam_eye"] = { convar = "Beatrun_TrickCamMatchEye", label = "hold at your own eye height" },
	["beatrun_cam_angles"] = { convar = "Beatrun_TrickCamAngles", label = "0 = your look, 2 = animation CameraJoint" }
}

local function ReportCam()
	for name, cvName in SortedPairs({
		["Beatrun_TrickCamUp"] = "height",
		["Beatrun_TrickCamOffset"] = "forward",
		["Beatrun_TrickCamAnchor"] = "anchor",
		["Beatrun_TrickCamAngles"] = "angles",
		["Beatrun_TrickCamMatchEye"] = "eye height",
		["Beatrun_TrickCamLimits"] = "mouse limits"
	}) do
		local cv = GetConVar(name)
		if cv then print(string.format("  %-28s %-10s (%s)", name, cv:GetString(), cvName)) end
	end
end

for command, info in pairs(CAM_COMMANDS) do
	concommand.Add(command, function(_, _, args)
		local cv = GetConVar(info.convar)
		if not cv then return end

		local arg = args and args[1]
		if arg == nil or arg == "" then
			print(string.format("[Beatrun Z-City] %s = %s  (%s)", info.convar, cv:GetString(), info.label))
			return
		end

		local value
		if string.sub(arg, 1, 1) == "+" or string.sub(arg, 1, 1) == "-" then
			local delta = tonumber(string.sub(arg, 2)) or 0
			if string.sub(arg, 1, 1) == "-" then delta = -delta end
			value = cv:GetFloat() + delta
		else
			value = tonumber(arg) or 0
		end

		RunConsoleCommand(info.convar, tostring(math.Round(value, 1)))
		print(string.format("[Beatrun Z-City] %s = %s", info.convar, tostring(math.Round(value, 1))))
	end)
end

concommand.Add("beatrun_cam_show", function()
	print("[Beatrun Z-City] trick camera:")
	ReportCam()
end)

concommand.Add("beatrun_cam_reset", function()
	for name, value in pairs(DEFAULTS) do
		if string.find(name, "TrickCam", 1, true) or name == "Beatrun_ForceCam" then
			RunConsoleCommand(name, value)
		end
	end
	print("[Beatrun Z-City] trick camera settings reset:")
	ReportCam()
end)

concommand.Add("beatrun_zcity_camparams", function()
	for _, name in ipairs({
		"Beatrun_TrickCamUp", "Beatrun_TrickCamOffset", "Beatrun_TrickCamMatchEye",
		"Beatrun_TrickCamLockAng", "Beatrun_TrickCamAnchor"
	}) do
		local cv = GetConVar(name)
		if cv then print(string.format("%s %s", name, cv:GetString())) end
	end
end)

-- Stale archived values in the user's config used to make the trick camera look "inert": the
-- defaults shipped in a new version never applied. This puts every setting back to the shipped value.
local DEFAULTS = {
	["Beatrun_TrickCam"] = "1",
	["Beatrun_TrickCamMode"] = "0",
	["Beatrun_TrickCamAnchor"] = "0",
	["Beatrun_TrickCamOffset"] = "4",
	["Beatrun_TrickCamUp"] = "4",
	["Beatrun_TrickCamLockAng"] = "0",
	["Beatrun_TrickCamLimits"] = "0",
	["Beatrun_SnatchModel"] = "0",
	["Beatrun_TrickCamAngles"] = "2",
	["Beatrun_TrickCamMatchEye"] = "0",
	["Beatrun_TrickCamTune"] = "0",
	["Beatrun_BodyMarker"] = "0",
	["Beatrun_TrickCamDistance"] = "150",
	["Beatrun_TrickCamHeight"] = "45",
	["Beatrun_SlideHideBody"] = "1",
	["Beatrun_SlideCamTilt"] = "1",
	["Beatrun_AnimSet"] = "0"
}

local function ApplyDefaults()
	for name, value in pairs(DEFAULTS) do
		RunConsoleCommand(name, value)
	end
end

-- The settings are the player's: nothing is reset on updates any more (that wiped a perfectly tuned
-- camera). This one-shot migration puts the camera back to the numbers we tuned it with, and then never
-- touches them again.
local CAMERA_TUNED = {
	["Beatrun_TrickCam"] = "1",
	["Beatrun_TrickCamMode"] = "0",
	["Beatrun_TrickCamAnchor"] = "0",
	["Beatrun_TrickCamOffset"] = "4",
	["Beatrun_TrickCamUp"] = "4",
	["Beatrun_TrickCamAngles"] = "2",
	["Beatrun_TrickCamMatchEye"] = "0",
	["Beatrun_TrickCamLockAng"] = "0",
	["Beatrun_TrickCamLimits"] = "0",
	["Beatrun_TrickCamDistance"] = "150",
	["Beatrun_SlideHideBody"] = "1",
	["Beatrun_SlideCamTilt"] = "1"
}

hook.Add("Think", "BeatrunZCity_CameraRestore", function()
	hook.Remove("Think", "BeatrunZCity_CameraRestore")

	if file.Exists("beatrun_zcity/camera_tuned_v3.txt", "DATA") then return end

	for name, value in pairs(CAMERA_TUNED) do RunConsoleCommand(name, value) end
	file.CreateDir("beatrun_zcity")
	file.Write("beatrun_zcity/camera_tuned_v3.txt", "1")
	print("[Beatrun Z-City] camera settings restored to the tuned values (this happens once)")
end)

concommand.Add("beatrun_zcity_resetcfg", function()
	ApplyDefaults()
	file.CreateDir("beatrun_zcity")
	file.Write("beatrun_zcity/cfg_version.txt", (BeatrunZCity and BeatrunZCity.Version) or "?")
	print("[Beatrun Z-City] convar values reset to the shipped defaults:")
	for name, value in SortedPairs(DEFAULTS) do
		print("  " .. name .. " " .. value)
	end
end)
