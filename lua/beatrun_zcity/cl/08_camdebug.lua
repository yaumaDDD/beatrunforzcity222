-- On-screen diagnostics for the trick camera / duplicate body problem.
-- Toggle with:  Beatrun_ZCity_DebugHUD 0

local cvHUD = GetConVar("Beatrun_ZCity_DebugHUD")

local function GetConVarBool(name)
	local cv = GetConVar(name)
	return cv and cv:GetBool() or false
end

local function HeadPos()
	if not IsValid(BodyAnim) then return end
	local bone = BodyAnim:LookupBone("ValveBiped.Bip01_Head1")
	if not bone then return end
	local pos, ang = BodyAnim:GetBonePosition(bone)
	return pos, ang
end

local function ShouldShow()
	if cvHUD and not cvHUD:GetBool() then return end
	if IsValid(BodyAnim) then return true end
	local t = BeatrunZCityTrickCamAppliedTime
	return t ~= nil and (CurTime() - t) < 5
end

hook.Add("HUDPaint", "BeatrunZCity_CamDebugHUD", function()
	if not ShouldShow() then return end

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local lines = {}
	local function Add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end

	local version = BeatrunZCity and BeatrunZCity.Version or "?"
	Add("BeatrunZCity %s   [%s]", tostring(version), tostring(BeatrunZCity and BeatrunZCity.Path))
	Add("thirdperson: %s   hg_thirdperson: %s   trickcam cv: %s",
		tostring(BeatrunIsThirdPerson(ply)),
		tostring(GetConVarBool("hg_thirdperson")),
		tostring(GetConVarBool("Beatrun_TrickCam")))

	Add("BodyAnim: %s   model: %s   hiddenHead: %s   offset: %s",
		tostring(IsValid(BodyAnim)),
		tostring(IsValid(BodyAnimMDL)),
		tostring(ply._BRZHiddenOverride ~= nil),
		tostring(GetConVar("Beatrun_TrickCamOffset") and GetConVar("Beatrun_TrickCamOffset"):GetFloat()))

	Add("CalcView hooks: %s found / %s wrapped   RenderOverride hidden: %s",
		tostring(BeatrunZCityCalcViewHookCount or "?"),
		tostring(BeatrunZCityCameraWrapped or "0"),
		tostring(ply._BRZHiddenOverride ~= nil))

	if BeatrunZCityCamWrapError then
		Add("WRAP ERROR: %s", tostring(BeatrunZCityCamWrapError))
	end

	local appliedAge = BeatrunZCityTrickCamAppliedTime and (CurTime() - BeatrunZCityTrickCamAppliedTime) or nil
	Add("angles: %s", tostring(BeatrunZCityCamAngles or "?"))
	Add("forced rendered views: %s /s", tostring(BeatrunZCityForceCamHits or 0))
	Add("trick cam applied: %s   anchor: %s   body: %s", appliedAge and string.format("%.2fs ago", appliedAge) or "never", tostring(BeatrunZCityCamAnchor or "?"), IsValid(BodyAnimMDL) and "drawn" or "n/a")

	-- The real camera the engine ended up using (not our requested value)
	local enginePos
	if isfunction(render.GetViewSetup) then
		local ok, setup = pcall(render.GetViewSetup)
		if ok and istable(setup) and setup.origin then enginePos = setup.origin end
	end

	local head = HeadPos()
	local camori = BeatrunZCityLastCamOrigin
	if head and camori then
		Add("real cam -> head distance: %.1f", camori:Distance(head))
	elseif head then
		Add("real cam -> head distance: n/a (camera not reported yet)   eye->head %.1f", EyePos():Distance(head))
	else
		Add("real cam -> head distance: n/a (no head bone)")
	end

	if head and enginePos then
		Add("ENGINE cam -> head: %.1f   mode: %s", enginePos:Distance(head),
			tostring(GetConVar("Beatrun_TrickCamMode") and GetConVar("Beatrun_TrickCamMode"):GetInt()))
	elseif head then
		Add("ENGINE cam -> head: n/a (render.GetViewSetup missing)")
	end

	Add("eye offset fallback: %s", BeatrunZCityEyeFallbackActive and "ON" or "off")

	local camori2 = BeatrunZCityLastCamOrigin
	if camori2 then
		Add("trick cam vs normal eye: %.1f", camori2:Distance(ply:EyePos()))

		if head then
			local base = ply:GetPos().z
			Add("heights: cam %.1f | anim head %.1f | own eye %.1f",
				camori2.z - base, head.z - base, ply:EyePos().z - base)
		end
	end

	if IsValid(BodyAnim) then
		local spine = BodyAnimMDL and IsValid(BodyAnimMDL) and BodyAnimMDL:LookupBone("ValveBiped.Bip01_Spine2")
		local spinescale
		if spine then
			local ok, res = pcall(BodyAnimMDL.GetManipulateBoneScale, BodyAnimMDL, spine)
			if ok then spinescale = res end
		end
		local torsoOK = not spinescale or spinescale:Length() > 0.01
		Add("head bones hidden: %s   torso visible: %s", tostring(BeatrunZCityHiddenHeadBones or "?"), torsoOK and "yes" or "NO")

		Add("anim: %s   cycle: %.2f   rig dz: %.1f   rig->ply: %.1f",
			tostring(BodyAnimString), tonumber(BodyAnimCycle) or 0,
			BodyAnim:GetPos().z - ply:GetPos().z,
			BodyAnim:GetPos():Distance(ply:GetPos()))
	end

	if IsValid(BodyAnim) and BeatrunZCityMarkerHead then
		-- Project the animation head into screen space with the REAL view matrix. If the rendered camera
		-- sits in the animation's head, this lands on the screen centre; otherwise it lands somewhere
		-- else and the number below tells us exactly how far off it is.
		local scr
		local ok = pcall(function()
			local sx, sy = BeatrunZCityMarkerHead:ToScreen()
			if isnumber(sx) and isnumber(sy) then scr = { x = sx, y = sy } end
		end)
		if not ok then scr = nil end
		if scr then
			local cx, cy = ScrW() * 0.5, ScrH() * 0.5
			local off = math.sqrt((scr.x - cx) ^ 2 + (scr.y - cy) ^ 2)
			Add("anim head on screen: %d px from centre  (%d, %d)", math.Round(off), math.Round(scr.x), math.Round(scr.y))
			surface.SetDrawColor(0, 255, 0, 255)
			surface.DrawRect(scr.x - 3, scr.y - 3, 7, 7)
			surface.SetDrawColor(255, 255, 255, 120)
			surface.DrawLine(cx - 12, cy, cx + 12, cy)
			surface.DrawLine(cx, cy - 12, cx, cy + 12)
			draw.SimpleText("ANIM HEAD", "DermaDefault", scr.x + 8, scr.y - 6, Color(0, 255, 0, 255))
		end
	end

	if IsValid(BodyAnim) or (BeatrunZCityMarkerHead and CurTime() - (BeatrunZCityMarkerHeadTime or 0) < 2) then
		Add("markers: green = anim head, blue = body head, red = your eye, yellow = requested cam")
		if BeatrunZCityLastMeasure then
			local m = BeatrunZCityLastMeasure
			Add("measured: cam->head %.1f   body->head %.1f   eye->head %.1f", m.dCamHead, m.dBodyHead, m.dEyeHead)
		end
		Add("3D draw hooks firing: %s /s   marker head set: %s",
			tostring(BeatrunZCityMarkerCalls or 0),
			tostring(BeatrunZCityMarkerHead and "yes" or "NO"))
	end

	if BeatrunZCityTuneText then
		Add("%s", BeatrunZCityTuneText)
	end

	if BeatrunZCityCamError then
		Add("ERROR: %s", tostring(BeatrunZCityCamError))
	end

	local x, y = 20, 20
	surface.SetFont("DermaDefault")
	for i = 1, #lines do
		local text = lines[i]
		local w = surface.GetTextSize(text)
		draw.RoundedBox(3, x - 6, y - 3, w + 12, 20, Color(0, 0, 0, 170))
		draw.SimpleText(text, "DermaDefault", x, y, i == 1 and Color(120, 220, 255) or Color(235, 235, 235), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		y = y + 20
	end
end)
