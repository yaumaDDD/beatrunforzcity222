-- First-person Beatrun BodyAnim for Slide & Safety Roll only.
-- Standalone: never patches hg.renderOverride or other Z-City internals.
-- Active strictly during slide/roll, then smoothly restores Z-City's camera & viewviewer.

local cvAnimSet = GetConVar("Beatrun_AnimSet")
local cvCamTilt = GetConVar("Beatrun_SlideCamTilt")
local cvHideBody = GetConVar("Beatrun_SlideHideBody")
local cvTrickCam = GetConVar("Beatrun_TrickCam")
local cvTrickCamOffset = GetConVar("Beatrun_TrickCamOffset")
-- A real non-melee weapon in hand RIGHT NOW. Bare hands and all melee SWEPs are excluded from
-- armed slide visuals and use the regular unarmed slide animation.
local function BeatrunWeaponArmed(ply)
	if not IsValid(ply) then return false end
	return BeatrunIsSlideWeapon(ply:GetActiveWeapon())
end

local cvTrickCamUp = GetConVar("Beatrun_TrickCamUp")
local cvTrickCamAnchor = GetConVar("Beatrun_TrickCamAnchor")
local cvTrickCamMatchEye = GetConVar("Beatrun_TrickCamMatchEye")
local cvCamLimits = GetConVar("Beatrun_TrickCamLimits")
local cvCamAngles = GetConVar("Beatrun_TrickCamAngles")
local cvSlideShoot = GetConVar("Beatrun_ZCity_SlideShoot")
local cvTrickCamMode = GetConVar("Beatrun_TrickCamMode")
local cvTrickCamDist = GetConVar("Beatrun_TrickCamDistance")
local cvTrickCamHeight = GetConVar("Beatrun_TrickCamHeight")

-- 0 = first person on the animation's camera attachment (like Beatrun)
-- 1 = third person looking at the animated body
local function GetTrickCamMode()
	return cvTrickCamMode and cvTrickCamMode:GetInt() or 0
end

-- The camera only follows the trick (slide / safety roll) while it is playing; afterwards everything
-- is smoothed back to Z-City's own camera.
local function ShouldUseTrickCam(ply)
	-- Without the animated body there is nothing to put the camera on
	if cvHideBody and not cvHideBody:GetBool() then return false end
	return not (cvTrickCam and not cvTrickCam:GetBool())
end

BodyAnim = BodyAnim or nil
BodyAnimMDL = BodyAnimMDL or nil
BodyAnimMDLarm = BodyAnimMDLarm or nil
BodyAnimCycle = BodyAnimCycle or 0
BodyAnimString = BodyAnimString or "nil"
BodyAnimMDLString = BodyAnimMDLString or "nil"
BodyAnimSpeed = BodyAnimSpeed or 1
BodyAnimLimitEase = BodyAnimLimitEase or false

BodyLimitX = BodyLimitX or 40
BodyLimitY = BodyLimitY or 80
camjoint = camjoint or "CameraJoint"
lockang = lockang or false
deleteonend = deleteonend ~= false
allowmove = allowmove ~= false
followplayer = followplayer ~= false
CamIgnoreAng = CamIgnoreAng or false
CamShake = CamShake or false
CamShakeMult = CamShakeMult or 0

local attach = nil
local lastattachpos = nil
local lastattachang = nil
local endlerp = 0
local lastNativeCamPos = nil
local lastNativeCamAng = nil
local lastAppliedFrame = -1

local lastangy = 0
local viewtiltlerp = Vector(0, 0, 0)
local ViewTiltAngle = Angle(0, 0, 0)
local CamShakeAng = Angle(0, 0, 0)
local lerpedpos = Vector(0, 0, 0)
local lastTrickCamPos = nil
local lerpchangeatt = 1
local lastatt = nil
local savedatt = nil

local BodyAnimPosEase = Vector(0, 0, 0)
local BodyAnimPosEaseLerp = 1
local BodyAnimFootDrop = 0

local pastlimitx = false
local pastlimity = false
local lastlimitx = 0
local lastlimity = 0

local armbones = {
	["ValveBiped.Bip01_R_Clavicle"] = true, ["ValveBiped.Bip01_R_UpperArm"] = true,
	["ValveBiped.Bip01_R_Forearm"] = true, ["ValveBiped.Bip01_R_Hand"] = true,
	["ValveBiped.Bip01_R_Wrist"] = true, ["ValveBiped.Bip01_R_Ulna"] = true,
	["ValveBiped.Bip01_L_Clavicle"] = true, ["ValveBiped.Bip01_L_UpperArm"] = true,
	["ValveBiped.Bip01_L_Forearm"] = true, ["ValveBiped.Bip01_L_Hand"] = true,
	["ValveBiped.Bip01_L_Wrist"] = true, ["ValveBiped.Bip01_L_Ulna"] = true,
	["ValveBiped.Bip01_L_Finger4"] = true, ["ValveBiped.Bip01_L_Finger41"] = true, ["ValveBiped.Bip01_L_Finger42"] = true,
	["ValveBiped.Bip01_L_Finger3"] = true, ["ValveBiped.Bip01_L_Finger31"] = true, ["ValveBiped.Bip01_L_Finger32"] = true,
	["ValveBiped.Bip01_L_Finger2"] = true, ["ValveBiped.Bip01_L_Finger21"] = true, ["ValveBiped.Bip01_L_Finger22"] = true,
	["ValveBiped.Bip01_L_Finger1"] = true, ["ValveBiped.Bip01_L_Finger11"] = true, ["ValveBiped.Bip01_L_Finger12"] = true,
	["ValveBiped.Bip01_L_Finger0"] = true, ["ValveBiped.Bip01_L_Finger01"] = true, ["ValveBiped.Bip01_L_Finger02"] = true,
	["ValveBiped.Bip01_R_Finger4"] = true, ["ValveBiped.Bip01_R_Finger41"] = true, ["ValveBiped.Bip01_R_Finger42"] = true,
	["ValveBiped.Bip01_R_Finger3"] = true, ["ValveBiped.Bip01_R_Finger31"] = true, ["ValveBiped.Bip01_R_Finger32"] = true,
	["ValveBiped.Bip01_R_Finger2"] = true, ["ValveBiped.Bip01_R_Finger21"] = true, ["ValveBiped.Bip01_R_Finger22"] = true,
	["ValveBiped.Bip01_R_Finger1"] = true, ["ValveBiped.Bip01_R_Finger11"] = true, ["ValveBiped.Bip01_R_Finger12"] = true,
	["ValveBiped.Bip01_R_Finger0"] = true, ["ValveBiped.Bip01_R_Finger01"] = true, ["ValveBiped.Bip01_R_Finger02"] = true,
}

local rightArmBones = {
	["ValveBiped.Bip01_R_Clavicle"] = true, ["ValveBiped.Bip01_R_UpperArm"] = true,
	["ValveBiped.Bip01_R_Forearm"] = true, ["ValveBiped.Bip01_R_Hand"] = true,
	["ValveBiped.Bip01_R_Wrist"] = true, ["ValveBiped.Bip01_R_Ulna"] = true,
	["ValveBiped.Bip01_R_Finger4"] = true, ["ValveBiped.Bip01_R_Finger41"] = true, ["ValveBiped.Bip01_R_Finger42"] = true,
	["ValveBiped.Bip01_R_Finger3"] = true, ["ValveBiped.Bip01_R_Finger31"] = true, ["ValveBiped.Bip01_R_Finger32"] = true,
	["ValveBiped.Bip01_R_Finger2"] = true, ["ValveBiped.Bip01_R_Finger21"] = true, ["ValveBiped.Bip01_R_Finger22"] = true,
	["ValveBiped.Bip01_R_Finger1"] = true, ["ValveBiped.Bip01_R_Finger11"] = true, ["ValveBiped.Bip01_R_Finger12"] = true,
	["ValveBiped.Bip01_R_Finger0"] = true, ["ValveBiped.Bip01_R_Finger01"] = true, ["ValveBiped.Bip01_R_Finger02"] = true,
}

local function GetSmoothPlayerPos(ply)
	if not IsValid(ply) then return vector_origin end
	local pos = ply:GetPos()
	local mins, maxs = ply:GetHull()
	local tr = util.TraceHull({
		start = pos + Vector(0, 0, 8),
		endpos = pos - Vector(0, 0, 12),
		mins = mins,
		maxs = maxs,
		filter = ply,
		mask = MASK_PLAYERSOLID
	})
	if tr.Hit and tr.HitNormal and tr.HitNormal.z > 0.7 then
		BodyAnimFootDrop = Lerp(FrameTime() * 15, BodyAnimFootDrop, math.max(0, pos.z - tr.HitPos.z))
	else
		BodyAnimFootDrop = Lerp(FrameTime() * 15, BodyAnimFootDrop, 0)
	end
	return pos
end

-- Verbatim from Beatrun (BodyAnim.lua, BodyAnimHideHead): hair, hats and other bones parented to the
-- head (or the neck, on some models) aren't on the animation rig, so the whole subtree of the neck is
-- hidden on the *drawn* model. The rig itself keeps its head, the camera anchor needs it.
local function BodyAnimHideHead(ent)
	if not IsValid(ent) then return end

	local root = ent:LookupBone("ValveBiped.Bip01_Neck1") or ent:LookupBone("ValveBiped.Bip01_Head1")
	if not root then return end

	local bones = {}

	for i = 0, ent:GetBoneCount() - 1 do
		local bone = ent:GetBoneParent(i)

		while bone and bone >= 0 do
			if bone == root then
				bones[#bones + 1] = i
				ent:ManipulateBoneScale(i, vector_origin)
				break
			end

			bone = ent:GetBoneParent(bone)
		end
	end

	ent.hiddenheadbones = bones
	BeatrunZCityHiddenHeadBones = #bones
end

-- Apply zero scale to hidden head/hair bone matrices WITHOUT re-running SetupBones, so any TPIK
-- matrices already written onto the entity stay intact.
local function ApplyHiddenHeadBoneMatrices(ent)
	if not IsValid(ent) or not ent.hiddenheadbones then return end

	for _, b in ipairs(ent.hiddenheadbones) do
		local m = ent:GetBoneMatrix(b)
		if m then
			m:SetScale(vector_origin)
			ent:SetBoneMatrix(b, m)
		end
	end
end

-- Called right before drawing, after the bones (jiggle bones included) are set up for the frame
-- (also from Beatrun).
local function HideHeadBones(ent)
	if not IsValid(ent) or not ent.hiddenheadbones then return end

	ent:SetupBones()
	ApplyHiddenHeadBoneMatrices(ent)
end

local function CopyModelAppearance(src, dst, isPlayerModel)
	if not IsValid(src) or not IsValid(dst) then return end

	if BeatrunZCityAppCompat and isfunction(BeatrunZCityAppCompat.CopyCleanAppearance) then
		BeatrunZCityAppCompat.CopyCleanAppearance(src, dst, isPlayerModel)
		return
	end

	if src:GetModel() == dst:GetModel() then
		dst:SetSkin(src:GetSkin() or 0)

		local bgs = src:GetBodyGroups()
		if istable(bgs) then
			for _, bg in ipairs(bgs) do
				dst:SetBodygroup(bg.id, src:GetBodygroup(bg.id) or 0)
			end
		end

		for i = 0, 31 do
			local sub = src:GetSubMaterial(i) or ""
			if sub == "null" or sub == "zcity_csgo_gloves/invisible" then sub = "" end
			dst:SetSubMaterial(i, sub ~= "" and sub or nil)
		end
	end

	if src.GetPlayerColor then
		dst.GetPlayerColor = function()
			return IsValid(src) and src:GetPlayerColor() or vector_origin
		end
	end
end

local function SyncModelAppearance(src, dst, isPlayerModel)
	if not IsValid(src) or not IsValid(dst) then return end

	if BeatrunZCityAppCompat and isfunction(BeatrunZCityAppCompat.SyncTrickModelAppearance) then
		BeatrunZCityAppCompat.SyncTrickModelAppearance(src, dst, isPlayerModel, false)
	end
end

local function BuildBodyAndArmModels(ply)
	if IsValid(BodyAnimMDL) then
		if ZCGloves and ZCGloves.ClearGlove then pcall(ZCGloves.ClearGlove, BodyAnimMDL) end
		BodyAnimMDL:Remove()
	end
	if IsValid(BodyAnimMDLarm) then
		if ZCGloves and ZCGloves.ClearGlove then pcall(ZCGloves.ClearGlove, BodyAnimMDLarm) end
		BodyAnimMDLarm:Remove()
	end

	local mdl = ply:GetModel()
	if not mdl or mdl == "" then mdl = "models/player/kleiner.mdl" end
	local zcgID = ply:GetNWString("zcg_glove", "")
	local zcgActive = BeatrunZCityAppCompat and BeatrunZCityAppCompat.IsActive() or (istable(ZCGloves) and true or false)

	BodyAnimMDL = ClientsideModel(mdl, RENDERGROUP_BOTH)
	local hasHandBones = false
	if IsValid(BodyAnimMDL) then
		BodyAnimMDL.GetPlayerColor = function()
			return IsValid(ply) and ply:GetPlayerColor() or vector_origin
		end

		-- Never share the player's model instance when ZCGloves / Big Appearance is active:
		-- glove submaterial hiding, bone shrinking and ClearGlove on BodyAnimMDL would otherwise
		-- leak back onto ply and leave the player's own hands invisible after the slide.
		local cvSnatch = GetConVar("Beatrun_SnatchModel")
		if (not zcgActive) and (not cvSnatch or cvSnatch:GetBool()) and isfunction(BodyAnimMDL.SnatchModelInstance) then
			pcall(BodyAnimMDL.SnatchModelInstance, BodyAnimMDL, ply)
		end

		BodyAnimMDL:SetParent(BodyAnim)
		BodyAnimMDL:AddEffects(EF_BONEMERGE)
		BodyAnimMDL:SetNoDraw(true)
		BodyAnimMDL:SetNWEntity("ply", ply)
		CopyModelAppearance(ply, BodyAnimMDL, true)
		BodyAnimMDL:SetupBones()

		hasHandBones = BodyAnimMDL:LookupBone("ValveBiped.Bip01_R_Hand") ~= nil
		BodyAnimMDL._BRZUnifiedArms = hasHandBones

		if hasHandBones then
			-- Keep BOTH arms intact on the unified player model so there is zero shoulder seam and
			-- zero torn-sleeve triangle artifacts when right-arm-only TPIK moves the shooting hand.
			-- The left arm stays naturally in Beatrun's slide animation pose.
			if zcgID ~= "" then
				BodyAnimMDL:SetNWString("zcg_glove", zcgID)
			else
				BodyAnimMDL:SetNWString("zcg_glove", "")
			end
		else
			BodyAnimMDL:SetNWString("zcg_glove", "")
			-- Fallback for non-ValveBiped models: arms come from BodyAnimMDLarm (C-hands).
			for i = 0, (BodyAnimMDL:GetBoneCount() or 0) - 1 do
				if armbones[BodyAnimMDL:GetBoneName(i)] then
					BodyAnimMDL:ManipulateBoneScale(i, vector_origin)
				end
			end
		end

		BodyAnimHideHead(BodyAnimMDL)

		-- Like Beatrun, the head is hidden on the rig as well while the player is in first person.
		-- Skipped when the trick camera anchors on that very bone, otherwise the anchor collapses.
		local anchorMode = cvTrickCamAnchor and cvTrickCamAnchor:GetInt() or 0
		if IsValid(BodyAnim) and not ply:ShouldDrawLocalPlayer() and anchorMode ~= 0 then
			local head = BodyAnim:LookupBone("ValveBiped.Bip01_Head1")
			if head then BodyAnim:ManipulateBoneScale(head, vector_origin) end
		end
	end

	local armMdl = mdl
	local hands = ply.GetHands and ply:GetHands()
	if not hasHandBones and IsValid(hands) and hands:GetModel() then
		armMdl = hands:GetModel()
	end

	local armUsesPlayerModel = (armMdl == mdl) and hasHandBones
	BodyAnimMDLarm = ClientsideModel(armMdl, RENDERGROUP_BOTH)
	if IsValid(BodyAnimMDLarm) then
		BodyAnimMDLarm._BRZIsPlayerModel = armUsesPlayerModel
		BodyAnimMDLarm:SetParent(BodyAnim)
		BodyAnimMDLarm:AddEffects(EF_BONEMERGE)
		BodyAnimMDLarm:SetNoDraw(true)
		BodyAnimMDLarm:SetNWEntity("ply", ply)
		if armUsesPlayerModel and zcgID ~= "" then
			BodyAnimMDLarm:SetNWString("zcg_glove", zcgID)
		else
			BodyAnimMDLarm:SetNWString("zcg_glove", "")
		end
		CopyModelAppearance(armUsesPlayerModel and ply or hands, BodyAnimMDLarm, armUsesPlayerModel)
		BodyAnimMDLarm:SetupBones()

		-- When BodyAnimMDLarm is used as the SlideWeapon 0 fallback on a ValveBiped model, keep only
		-- the right arm visible so the left arm never floats in the air.
		local keepSet = hasHandBones and rightArmBones or armbones
		for i = 0, (BodyAnimMDLarm:GetBoneCount() or 0) - 1 do
			if not keepSet[BodyAnimMDLarm:GetBoneName(i)] then
				BodyAnimMDLarm:ManipulateBoneScale(i, vector_origin)
			end
		end
	end
end

-- Z-City renders the player through a per-entity RenderOverride, which bypasses the engine's
-- PrePlayerDraw / ShouldDrawLocalPlayer / view.drawviewer controls. While our animated body replaces
-- the model that override is swapped out (and restored afterwards), so the player never sees his
-- "running" body and the trick body at the same time.
function BeatrunHideStaticPlayerModel(ply)
	if not IsValid(ply) or ply._BRZHiddenOverride ~= nil then return end

	ply._BRZHiddenOverride = ply.RenderOverride or false

	-- Suppress Z-City's static player render while BodyAnim is active (ply:SetNoDraw(true) and
	-- view.drawviewer = false prevent RenderOverride from executing anyway). The Z-City weapon
	-- and TPIK-posed arms are drawn directly alongside BodyAnimMDL in PostDrawOpaqueRenderables.
	ply.RenderOverride = function() end

	-- Same approach as Beatrun itself: the engine never draws the local player while the animated
	-- body replaces it, so Z-City's RenderOverride never runs and no second body can appear.
	ply._BRZHiddenNoDraw = ply:GetNoDraw()
	ply:SetNoDraw(true)

	-- And a fully transparent colour as a last resort
	ply._BRZHiddenColor = ply:GetColor()
	ply:SetColor(Color(255, 255, 255, 0))
end

function BeatrunRestoreStaticPlayerModel(ply)
	if not IsValid(ply) or ply._BRZHiddenOverride == nil then return end

	ply.RenderOverride = ply._BRZHiddenOverride ~= false and ply._BRZHiddenOverride or nil
	ply._BRZHiddenOverride = nil

	if ply._BRZHiddenColor then
		ply:SetColor(ply._BRZHiddenColor)
		ply._BRZHiddenColor = nil
	end

	ply:SetNoDraw(ply._BRZHiddenNoDraw and true or false)
	ply._BRZHiddenNoDraw = nil

	if BeatrunZCityAppCompat and isfunction(BeatrunZCityAppCompat.SanitizeOrphanHiddenSlots) then
		BeatrunZCityAppCompat.SanitizeOrphanHiddenSlots(ply, true)
	end
end

function BodyAnimSetEase(pos)
	BodyAnimPosEase:Set(pos)
	BodyAnimPosEaseLerp = 0
end

function RemoveBodyAnim(smooth)
	local ply = LocalPlayer()

	BeatrunRestoreStaticPlayerModel(ply)
	local canSmooth = smooth
		and lastattachpos ~= nil
		and lastattachang ~= nil
		and IsValid(ply)
		and BeatrunCanSlideOrRoll(ply)
		and (not BeatrunIsThirdPerson(ply) or ShouldUseTrickCam(ply))
		and not ply:InVehicle()

	if canSmooth then
		attach = {
			Pos = Vector(lastattachpos),
			Ang = Angle(lastattachang)
		}
		endlerp = 0
	else
		attach = nil
		endlerp = 0
	end

	if IsValid(ply) then
		ply._BRZSlideMuzzlePos = nil
		ply._BRZSlideMuzzleDir = nil
		ply._BRZSlideMuzzleTime = nil
	end

	if IsValid(BodyAnimMDLarm) then
		if ZCGloves and ZCGloves.ClearGlove then pcall(ZCGloves.ClearGlove, BodyAnimMDLarm) end
		BodyAnimMDLarm:Remove()
	end
	BodyAnimMDLarm = nil

	if IsValid(BodyAnimMDL) then
		if ZCGloves and ZCGloves.ClearGlove then pcall(ZCGloves.ClearGlove, BodyAnimMDL) end
		BodyAnimMDL:Remove()
	end
	BodyAnimMDL = nil

	if IsValid(BodyAnim) then BodyAnim:Remove() end
	BodyAnim = nil
	lastTrickCamPos = nil
	BeatrunZCityTrickEyePos = nil
	BeatrunZCitySlideWeaponState = nil
	BeatrunZCitySlideTPIKState = nil

	BodyAnimString = "nil"
	BodyAnimCycle = 0
	BodyAnimSpeed = 1
	lockang = false
	allowmove = true
	CamIgnoreAng = false
	CamShake = false
	CamShakeMult = 0
	pastlimitx = false
	pastlimity = false
	BodyAnimLimitEase = false
	lastattachpos = nil
	lastattachang = nil
end

function StartBodyAnim(animtable)
	local ply = LocalPlayer()
	if not IsValid(ply) or not istable(animtable) then return end
	if not BeatrunCanSlideOrRoll(ply) then return end

	RemoveBodyAnim(false)

	local rigName = animtable.animmodelstring or (cvAnimSet and cvAnimSet:GetInt() == 1 and "old_climbanim" or "new_climbanim")
	local mdlPath = "models/" .. rigName .. ".mdl"
	if not util.IsValidModel(mdlPath) then
		mdlPath = "models/new_climbanim.mdl"
	end

	BodyAnim = ClientsideModel(mdlPath, RENDERGROUP_BOTH)
	if not IsValid(BodyAnim) then return end

	BodyAnimMDLString = rigName
	BodyAnimString = animtable.AnimString or "meslidestart"
	BodyAnimSpeed = animtable.BodyAnimSpeed or 1
	BodyAnimCycle = animtable.BodyAnimCycle or 0
	camjoint = animtable.camjoint or "CameraJoint"
	deleteonend = animtable.deleteonend ~= false
	followplayer = animtable.followplayer ~= false
	lockang = animtable.lockang and true or false
	allowmove = animtable.allowmove ~= false
	CamIgnoreAng = animtable.CamIgnoreAng and true or false
	BodyLimitX = animtable.BodyLimitX or 40
	BodyLimitY = animtable.BodyLimitY or 80

	local startAng = animtable.StartAngle and Angle(animtable.StartAngle) or Angle(0, ply:EyeAngles().y, 0)
	startAng.x = 0
	startAng.z = 0

	BodyAnim:SetPos(ply:GetPos())
	BodyAnim:SetAngles(startAng)
	BodyAnim:SetNoDraw(true)

	local seq = BodyAnim:LookupSequence(BodyAnimString)
	if seq and seq >= 0 then
		BodyAnim:ResetSequence(seq)
		BodyAnim:SetCycle(BodyAnimCycle)
	end

	ply.OrigEyeAng = Angle(startAng)
	viewtiltlerp = Vector(0, ply:EyeAngles().y, 0)
	lastangy = ply:EyeAngles().y

	BuildBodyAndArmModels(ply)

	if cvHideBody == nil or cvHideBody:GetBool() then
		BeatrunHideStaticPlayerModel(ply)
	end

	attach = nil
	endlerp = 0
end

-- The animated body is drawn in first person AND in third person. In third person the engine would draw
-- the static player model instead of the animation, so the real model is hidden while ours is active.
local function IsBodyAnimVisible(ply)
	if not IsValid(ply) or not ply:Alive() or ply:InVehicle() then return false end
	if IsValid(ply.FakeRagdoll) then return false end
	if cvHideBody and not cvHideBody:GetBool() then return false end
	return IsValid(BodyAnim) and IsValid(BodyAnimMDL)
end

local function IsBodyAnimFirstPersonVisible(ply)
	if BeatrunIsThirdPerson(ply) then return false end
	return IsBodyAnimVisible(ply)
end

-- Belt and braces: some setups draw the local player through ShouldDrawLocalPlayer instead of the
-- CalcView "drawviewer" field. Both are disabled while our animated body replaces the model.
hook.Add("ShouldDrawLocalPlayer", "BeatrunZCity_NoStaticLocalModel", function(ply)
	if ply ~= LocalPlayer() then return end
	if not IsValid(ply) or ply:InVehicle() then return end
	if not BeatrunIsThirdPerson(ply) then return end
	if IsValid(ply.FakeRagdoll) then return end
	if cvHideBody and not cvHideBody:GetBool() then return end

	if IsValid(BodyAnim) and IsValid(BodyAnimMDL) then return false end
end)

hook.Add("PrePlayerDraw", "BeatrunZCity_HideStaticLocalModel", function(ply)
	if ply ~= LocalPlayer() then return end
	if not IsValid(ply) or ply:InVehicle() then return end
	if not BeatrunIsThirdPerson(ply) then return end
	if IsValid(ply.FakeRagdoll) then return end
	if cvHideBody and not cvHideBody:GetBool() then return end

	-- Hiding the static model without a replacement would make the player invisible
	if IsValid(BodyAnim) and IsValid(BodyAnimMDL) then return true end
end)

hook.Add("Think", "BeatrunZCity_BodyAnimThink", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	if IsValid(BodyAnim) then
		if not BeatrunCanSlideOrRoll(ply) or ply:InVehicle() then
			RemoveBodyAnim(false)
			return
		end

		-- An armed slide shows the player's real viewmodel: it is his actual weapon model and it always
		-- follows the aim, which the merged animation arm can never do. A bare-handed slide keeps the
		-- animated arms and hides the viewmodel.
		-- Armed slide: draw the player's own viewmodel - it is his real weapon with his arms, it always
		-- follows the aim and it is exactly what Z-City shows in its own first person. The animated body
		-- keeps the legs, so the slide looks like the trick instead of a plain walk with a gun.
		-- Z-City draws its weapons as world models at the hand (SWEP:ShouldDrawViewModel returns false),
		-- so there is no engine viewmodel to manage here. Base Source weapons keep their own one.
		ply._BRZVMShown = false

		local dt = FrameTime()
		local seqDur = BodyAnim:SequenceDuration()
		if seqDur and seqDur > 0 then
			BodyAnimCycle = BodyAnimCycle + (dt / seqDur) * BodyAnimSpeed
		else
			BodyAnimCycle = 1
		end

		if deleteonend and BodyAnimCycle >= 1 then
			RemoveBodyAnim(true)
			return
		end

		BodyAnim:SetCycle(math.Clamp(BodyAnimCycle, 0, 1))

		if followplayer then
			local pos = GetSmoothPlayerPos(ply)
			pos.z = pos.z - BodyAnimFootDrop
			if BodyAnimPosEaseLerp < 1 then
				local eased = LerpVector(BodyAnimPosEaseLerp, BodyAnimPosEase, pos)
				BodyAnimPosEaseLerp = math.Approach(BodyAnimPosEaseLerp, 1, dt * 5)
				BodyAnim:SetPos(eased)
				BodyAnim:SetRenderOrigin(eased)
			else
				BodyAnim:SetPos(pos)
				BodyAnim:SetRenderOrigin(pos)
			end
		end

		if CamIgnoreAng then
			local eyeang = ply:EyeAngles()
			eyeang.x = 0
			eyeang.z = 0
			BodyAnim:SetAngles(eyeang)
		end

		if ply:GetSliding() and BodyAnim:LookupBone("ValveBiped.Bip01_Spine1") then
			local pitch = math.Clamp(ply:EyeAngles().p, -25, 45)
			BodyAnim:ManipulateBoneAngles(BodyAnim:LookupBone("ValveBiped.Bip01_Spine1"), Angle(0, pitch * 0.25, 0))
		end

		BodyAnim:InvalidateBoneCache()
	end
end)

local cvSlideWeapon = GetConVar("Beatrun_ZCity_SlideWeapon")
local lastTPIKFrame = -1
local lastAimNetTime = 0
local lastAimNetPos = nil
local lastAimNetDir = nil

-- World-space translation from ply's ducked/standing eye anchor (where Z-City's
-- WorldModel_Transform places the gun) down to our sliding rig's camera/head, plus a one-handed
-- right-arm offset so the pistol sits naturally in front of the right shoulder clear of the torso
-- and legs instead of buried in the stomach/crotch.
local function GetSlideWeaponEyeShift(ply, wpn)
	local aimAng = ply:GetAimVector():Angle()
	local targetEye
	if GetTrickCamMode() == 0 and not BeatrunIsThirdPerson(ply) and isvector(BeatrunZCityTrickEyePos) then
		targetEye = BeatrunZCityTrickEyePos - aimAng:Up() * 1
	else
		local headBone = BodyAnim:LookupBone("ValveBiped.Bip01_Head1") or BodyAnim:LookupBone("ValveBiped.Bip01_Neck1")
		if headBone then
			local headPos = BodyAnim:GetBonePosition(headBone)
			if isvector(headPos) then
				targetEye = headPos + Vector(0, 0, 3)
			end
		end
	end

	if not isvector(targetEye) then return vector_origin end

	local srcEye = isvector(wpn.fuckingfuckpos) and wpn.fuckingfuckpos or ply:EyePos()
	local shift = targetEye - srcEye
	if shift:LengthSqr() > 96 * 96 then return vector_origin end

	-- One-handed right-arm slide stance: move out toward the right shoulder line and lift cleanly
	-- above the reclined torso/thighs; pull back toward center while aiming down sights (RMB).
	local isZoom = isfunction(wpn.IsZoom) and wpn:IsZoom()
	if isZoom then
		shift = shift + aimAng:Forward() * 1.0 + aimAng:Up() * 2.5
	else
		shift = shift + aimAng:Forward() * 2.5 + aimAng:Right() * 3.5 + aimAng:Up() * 2.5
	end

	return shift
end

-- Clamp the target right-hand grip position to the real physical reach of the animated body's
-- right shoulder (ValveBiped.Bip01_R_UpperArm), translating the weapon by the exact same delta so
-- the pistol NEVER detaches from the right palm even at extreme look angles.
local function ClampSlideGunToRightShoulder(ply, bodyEnt, gunPos, handPos)
	if not (IsValid(bodyEnt) and isvector(handPos)) then return gunPos, handPos end

	local rUpper = bodyEnt:LookupBone("ValveBiped.Bip01_R_UpperArm")
	if not rUpper then return gunPos, handPos end

	local sMat = bodyEnt:GetBoneMatrix(rUpper)
	if not sMat then return gunPos, handPos end

	local shoulderPos = sMat:GetTranslation()
	local rForearm = bodyEnt:LookupBone("ValveBiped.Bip01_R_Forearm")
	local limbLen = (rForearm and isfunction(ply.BoneLength)) and ply:BoneLength(rForearm) or 0
	if not isnumber(limbLen) or limbLen <= 1 then limbLen = 11.5 end

	local maxReach = limbLen * 2 - 1.2
	local toHand = handPos - shoulderPos
	local dist = toHand:Length()
	if dist > maxReach and dist > 0.001 then
		local clampedHand = shoulderPos + toHand * (maxReach / dist)
		local delta = clampedHand - handPos
		return gunPos + delta, clampedHand
	end

	return gunPos, handPos
end

-- Compute the exact world-space muzzle origin and barrel forward direction for the drawn weapon,
-- matching Z-City's SWEP:GetTrace() formula (LocalMuzzlePos/Ang + inverse FakePos/Ang).
local function ComputeSlideMuzzle(wpn, wm, gunPos, gunAng, ply)
	if isvector(wpn.LocalMuzzlePos) and isangle(wpn.LocalMuzzleAng) then
		local gpos, gang = gunPos, gunAng
		if isfunction(wpn.ShouldUseFakeModel) and wpn:ShouldUseFakeModel()
			and isvector(wpn.FakePos) and isangle(wpn.FakeAng) and isfunction(Matrix) then
			local mat = Matrix()
			mat:SetTranslation(wpn.FakePos)
			mat:SetAngles(wpn.FakeAng)
			mat = mat:GetInverse()
			gpos, gang = LocalToWorld(mat:GetTranslation(), mat:GetAngles(), gpos, gang)
		end
		local mpos, mang = LocalToWorld(wpn.LocalMuzzlePos, wpn.LocalMuzzleAng, gpos, gang)
		return mpos, mang:Forward()
	end

	if IsValid(wm) then
		local attIdx = wm:LookupAttachment("muzzle")
		if not attIdx or attIdx <= 0 then attIdx = wm:LookupAttachment("muzzle_flash") end
		if attIdx and attIdx > 0 then
			local att = wm:GetAttachment(attIdx)
			if att and isvector(att.Pos) and isangle(att.Ang) then
				return att.Pos, att.Ang:Forward()
			end
		end
	end

	return gunPos, ply:GetAimVector()
end

local function SyncSlideMuzzleAim(ply, wpn, gunPos, gunAng, muzzlePos, muzzleDir)
	local now = CurTime()
	local firstFrame = not isvector(ply._BRZSlideMuzzlePos)

	ply._BRZSlideMuzzlePos = muzzlePos
	ply._BRZSlideMuzzleDir = muzzleDir
	ply._BRZSlideMuzzleTime = now

	wpn._BRZSlideGunPos = gunPos
	wpn._BRZSlideGunAng = gunAng
	wpn._BRZSlideGunTime = now
	wpn.desiredPos = gunPos
	wpn.desiredAng = gunAng

	if not (ply:GetSliding() and ply._BRZSlideArmed) then return end

	local firing = isfunction(ply.KeyDown) and ply:KeyDown(IN_ATTACK)
	local minInterval = firing and 0.015 or 0.033
	local elapsed = now - lastAimNetTime
	if not firstFrame and elapsed < minInterval and lastAimNetPos and lastAimNetDir then return end

	local moved = firstFrame or not lastAimNetPos or (muzzlePos - lastAimNetPos):LengthSqr() > 0.25 * 0.25
	local turned = firstFrame or not lastAimNetDir or muzzleDir:Dot(lastAimNetDir) < 0.9995
	if not firstFrame and not firing and not moved and not turned and elapsed < 0.12 then return end

	lastAimNetTime = now
	lastAimNetPos = Vector(muzzlePos)
	lastAimNetDir = Vector(muzzleDir)

	net.Start("Beatrun_ZC_SlideAim", true)
		net.WriteVector(muzzlePos)
		net.WriteNormal(muzzleDir)
	net.SendToServer()
end

local function AdvanceZCityFakeModelCycle(wpn, wm)
	if not (isfunction(wpn.ShouldUseFakeModel) and wpn:ShouldUseFakeModel()) then return end
	if wpn.seq then wm:SetSequence(wpn.seq) end
	if not (isnumber(wpn.animtime) and isnumber(wpn.animspeed) and wpn.animspeed ~= 0) then return end

	local timing
	if not wpn.cycling then
		timing = 1 - math.Clamp((wpn.animtime - CurTime()) / wpn.animspeed, 0, 1)
		timing = wpn.reverseanim and (1 - timing) or timing
	else
		timing = ((CurTime() - (wpn.animtime - wpn.animspeed)) % wpn.animspeed) / wpn.animspeed
	end
	wm:SetCycle(timing)
end

local function CanRunZCityTPIKOn(armEnt)
	if not IsValid(armEnt) then return false end
	return armEnt:LookupBone("ValveBiped.Bip01_Head1") ~= nil
		and armEnt:LookupBone("ValveBiped.Bip01_Pelvis") ~= nil
		and armEnt:LookupBone("ValveBiped.Bip01_R_UpperArm") ~= nil
		and armEnt:LookupBone("ValveBiped.Bip01_R_Forearm") ~= nil
		and armEnt:LookupBone("ValveBiped.Bip01_R_Hand") ~= nil
end

-- Poses ONLY the RIGHT arm & right fingers of armEnt (our unified BodyAnimMDL, or BodyAnimMDLarm
-- fallback) onto the drawn Z-City weapon via SWEP:SetHandPos() + hg.DoTPIK(). The LEFT arm is
-- forced off (setlhik=false, setlh=false, lhandik=false, lerp_lh=0) so the left arm stays 100% in
-- Beatrun's slide animation pose while ONLY the right arm aims and shoots.
local function ApplySlideWeaponTPIK(ply, wpn, armEnt, handPos, handAng)
	if not IsValid(armEnt) or not CanRunZCityTPIKOn(armEnt) then return false end
	if not (hg and isfunction(hg.DoTPIK)) then return false end

	local prevFake = ply.FakeRagdoll
	local prevOld = ply.OldRagdoll
	local prevHandPos, prevHandAng = wpn.handPos, wpn.handAng
	local prevSetLhik = wpn.setlhik
	local prevSetLh = wpn.setlh
	local prevLhandik = wpn.lhandik
	local prevLerpLH = ply.lerp_lh

	if isvector(handPos) and isangle(handAng) then
		wpn.handPos = handPos
		wpn.handAng = handAng
	end

	-- Force single-handed right-arm hold during the slide: left hand & left arm stay untouched.
	wpn.setlhik = false
	wpn.setlh = false
	wpn.lhandik = false

	ply.FakeRagdoll = armEnt
	ply.OldRagdoll = armEnt
	local okHand = true
	if isfunction(wpn.SetHandPos) then
		okHand = pcall(wpn.SetHandPos, wpn)
	end
	ply.FakeRagdoll = prevFake
	ply.OldRagdoll = prevOld
	wpn.handPos = prevHandPos
	wpn.handAng = prevHandAng

	if lastTPIKFrame ~= FrameNumber() then
		lastTPIKFrame = FrameNumber()
		-- Allow DoTPIK to solve every render frame rather than stalling between server ticks at high FPS
		ply.nextrebuild = 0
	end

	-- Ensure DoTPIK skips the entire left-arm IK block (if lerp_lh != 0) and moves ONLY the right arm.
	wpn.lhandik = false
	ply.lerp_lh = 0
	local okIK = pcall(hg.DoTPIK, ply, armEnt)

	wpn.setlhik = prevSetLhik
	wpn.setlh = prevSetLh
	wpn.lhandik = prevLhandik
	ply.lerp_lh = prevLerpLH

	return okHand and okIK
end

-- Draws the local player's active Z-City weapon directly in our render pass. While ply has
-- SetNoDraw(true) and view.drawviewer = false, ply.RenderOverride never executes, so Z-City's
-- DrawPlayerRagdoll -> hg.RenderWeapons never gets a chance to draw the worldModel.
local function DrawSlideZCityWeapon(ply, bodyEnt)
	if not BeatrunWeaponArmed(ply) then
		BeatrunZCitySlideWeaponState = "unarmed"
		return false
	end

	local wpn = ply:GetActiveWeapon()
	if not IsValid(wpn) then
		BeatrunZCitySlideWeaponState = "no weapon"
		return false
	end

	-- Z-City firearms (homigrad_base)
	if isfunction(wpn.WorldModel_Transform) then
		if not IsValid(wpn.worldModel) and isfunction(wpn.CreateWorldModel) then
			local okCreate, created = pcall(wpn.CreateWorldModel, wpn)
			if okCreate and IsValid(created) and not IsValid(wpn.worldModel) then
				wpn.worldModel = created
			end
		end

		local wm = wpn.worldModel
		if not IsValid(wm) then
			BeatrunZCitySlideWeaponState = "no worldModel"
			return false
		end

		-- Compute with ply.FakeRagdoll untouched (nil): Z-City uses ply:GetAimVector() freely instead
		-- of clamping weapon aim to the head bone (which FakeRagdoll forces when IN_USE is not held).
		local ok, pos, ang, handPos, handAng = pcall(wpn.WorldModel_Transform, wpn, true, false, wm)
		if not ok or not isvector(pos) or not isangle(ang) then
			BeatrunZCitySlideWeaponState = "transform failed"
			return false
		end

		local shift = GetSlideWeaponEyeShift(ply, wpn)
		pos = pos + shift
		if isvector(handPos) then
			handPos = handPos + shift
		end

		pos, handPos = ClampSlideGunToRightShoulder(ply, bodyEnt, pos, handPos)

		AdvanceZCityFakeModelCycle(wpn, wm)

		-- Both SetRenderOrigin/Angles and SetPos/Angles are required: SWEP:Camera already wrote
		-- SetRenderOrigin during CalcView, which otherwise overrides SetPos during DrawModel.
		wm:SetRenderOrigin(pos)
		wm:SetRenderAngles(ang)
		wm:SetPos(pos)
		wm:SetAngles(ang)
		wm:SetupBones()
		wm:DrawModel()

		if isfunction(wpn.DrawAttachments) then
			pcall(wpn.DrawAttachments, wpn)
		end

		local muzzlePos, muzzleDir = ComputeSlideMuzzle(wpn, wm, pos, ang, ply)
		SyncSlideMuzzleAim(ply, wpn, pos, ang, muzzlePos, muzzleDir)

		BeatrunZCitySlideWeaponState = "gun ok (1H right)"
		return true, wpn, handPos, handAng
	end

	-- Z-City non-melee TPIK items (weapon_tpik_base, medicine, etc.; melee SWEPs are filtered out above)
	if isfunction(wpn.DrawWorldModel2) then
		local ok = pcall(wpn.DrawWorldModel2, wpn)
		BeatrunZCitySlideWeaponState = ok and "tpik item ok (1H right)" or "DrawWorldModel2 err"
		return ok, wpn, nil, nil
	end

	BeatrunZCitySlideWeaponState = "non-zcity weapon"
	return false
end

hook.Add("PostDrawOpaqueRenderables", "BeatrunZCity_DrawBodyAnim", function(bDrawingDepth, bDrawingSkybox, bDrawing3DSkybox)
	if bDrawingDepth or bDrawingSkybox or bDrawing3DSkybox or RENDERING_SCOPE then return end

	local ply = LocalPlayer()
	if not IsBodyAnimVisible(ply) then return end

	-- If the player's model changed mid-trick (class change / appearance apply), rebuild the trick
	-- body copy so bodygroup and submaterial indices always match the active player model.
	local plyMdl = ply:GetModel()
	if isstring(plyMdl) and plyMdl ~= "" and IsValid(BodyAnimMDL) and BodyAnimMDL:GetModel() ~= plyMdl then
		BuildBodyAndArmModels(ply)
		if not IsValid(BodyAnimMDL) then return end
	end

	-- Beatrun_ZCity_SlideWeapon 0: hide animated body legs/torso, still draw weapon & right arm.
	-- 1 (default): draw unified animated body (legs + torso + animated left arm + IK right arm) + gun.
	local armed = BeatrunWeaponArmed(ply)
	local hideBody = armed and cvSlideWeapon and cvSlideWeapon:GetInt() == 0
	local useUnifiedBody = (not hideBody) and IsValid(BodyAnimMDL) and BodyAnimMDL._BRZUnifiedArms
	local appCompat = BeatrunZCityAppCompat

	-- ply has SetNoDraw(true) during the trick so refresh bones before weapon/TPIK transforms.
	ply:SetupBones()
	BodyAnim:SetupBones()

	-- In third person (and with the third person trick camera) the body has to respect depth,
	-- otherwise it is drawn through walls
	local ignorez = not BeatrunIsThirdPerson(ply) and GetTrickCamMode() == 0
	if ignorez then cam.IgnoreZ(true) end

	if useUnifiedBody then
		-- Keep jacket/hand bodygroups (sheet, TORSO, HANDS/handsfortshirt), zcg_glove and clean
		-- submaterials synced with ply so ZCGloves always evaluates the active jacket accurately.
		SyncModelAppearance(ply, BodyAnimMDL, true)

		-- Prepare fresh bonemerged bones from BodyAnim BEFORE drawing weapon so shoulder reach
		-- clamping reads the exact right-shoulder bone of the animated slide body.
		BodyAnimMDL:SetPos(BodyAnim:GetPos())
		BodyAnimMDL:SetAngles(BodyAnim:GetAngles())
		if isfunction(BodyAnimMDL.InvalidateBoneCache) then
			BodyAnimMDL:InvalidateBoneCache()
		end
		BodyAnimMDL:SetupBones()

		local drewWeapon, wpn, handPos, handAng = DrawSlideZCityWeapon(ply, BodyAnimMDL)

		if drewWeapon and IsValid(wpn) then
			local tpikOK = ApplySlideWeaponTPIK(ply, wpn, BodyAnimMDL, handPos, handAng)
			BeatrunZCitySlideTPIKState = tpikOK and "ok (right only)" or "fallback"
		else
			BeatrunZCitySlideTPIKState = armed and "none" or "unarmed"
		end

		-- Hide head/hair bones without re-calling SetupBones so right-arm TPIK stays intact.
		ApplyHiddenHeadBoneMatrices(BodyAnimMDL)
		if appCompat and isfunction(appCompat.SanitizeOrphanHiddenSlots) then
			appCompat.SanitizeOrphanHiddenSlots(BodyAnimMDL, false)
		end
		pcall(hook.Run, "CoolPostDrawAppearance", BodyAnimMDL, ply)
		if appCompat and isfunction(appCompat.ProtectNonFingerArmBones) then
			appCompat.ProtectNonFingerArmBones(BodyAnimMDL)
		end
		BodyAnimMDL:DrawModel()
		pcall(hook.Run, "PostDrawAppearance", BodyAnimMDL, ply)
	else
		-- Fallback path: Beatrun_ZCity_SlideWeapon 0 (hidden body) or non-ValveBiped model using C-hands.
		if not hideBody and IsValid(BodyAnimMDL) then
			SyncModelAppearance(ply, BodyAnimMDL, true)
			BodyAnimMDL:SetPos(BodyAnim:GetPos())
			BodyAnimMDL:SetAngles(BodyAnim:GetAngles())
			HideHeadBones(BodyAnimMDL)
			if appCompat and isfunction(appCompat.SanitizeOrphanHiddenSlots) then
				appCompat.SanitizeOrphanHiddenSlots(BodyAnimMDL, false)
			end
			pcall(hook.Run, "CoolPostDrawAppearance", BodyAnimMDL, ply)
			if appCompat and isfunction(appCompat.ProtectNonFingerArmBones) then
				appCompat.ProtectNonFingerArmBones(BodyAnimMDL)
			end
			BodyAnimMDL:DrawModel()
			pcall(hook.Run, "PostDrawAppearance", BodyAnimMDL, ply)
		end

		if IsValid(BodyAnimMDLarm) then
			if BodyAnimMDLarm._BRZIsPlayerModel then
				SyncModelAppearance(ply, BodyAnimMDLarm, true)
			end
			BodyAnimMDLarm:SetPos(BodyAnim:GetPos())
			BodyAnimMDLarm:SetAngles(BodyAnim:GetAngles())
			if isfunction(BodyAnimMDLarm.InvalidateBoneCache) then
				BodyAnimMDLarm:InvalidateBoneCache()
			end
			BodyAnimMDLarm:SetupBones()
		end

		local drewWeapon, wpn, handPos, handAng = DrawSlideZCityWeapon(ply, BodyAnimMDLarm)

		if IsValid(BodyAnimMDLarm) then
			if drewWeapon and IsValid(wpn) then
				local tpikOK = ApplySlideWeaponTPIK(ply, wpn, BodyAnimMDLarm, handPos, handAng)
				BeatrunZCitySlideTPIKState = tpikOK and "ok (right only)" or "fallback"
			else
				BeatrunZCitySlideTPIKState = armed and "none" or "unarmed"
			end

			if BodyAnimMDLarm._BRZIsPlayerModel and appCompat and isfunction(appCompat.RunZCGDrawHookOnly) then
				appCompat.RunZCGDrawHookOnly(BodyAnimMDLarm, ply)
				if isfunction(appCompat.ProtectNonFingerArmBones) then
					appCompat.ProtectNonFingerArmBones(BodyAnimMDLarm)
				end
				BodyAnimMDLarm:DrawModel()
				appCompat.RunZCGAfterHookOnly(BodyAnimMDLarm, ply)
			else
				BodyAnimMDLarm:DrawModel()
			end
		end
	end

	if ignorez then cam.IgnoreZ(false) end
end)

-- Camera anchor for the trick: the head bone of the animation rig (the head itself is hidden on the
-- drawn model, the neck is kept). The camera sits INSIDE the head by default; Beatrun_TrickCamOffset
-- (forward) and Beatrun_TrickCamUp (up) move it, so a first person feel can be dialled in exactly.
local function GetTrickCamAttachment()
	if not IsValid(BodyAnim) then return end

	BodyAnim:SetupBones()

	local bone = BodyAnim:LookupBone("ValveBiped.Bip01_Head1") or BodyAnim:LookupBone("ValveBiped.Bip01_Neck1")
	if not bone then return end

	local pos, ang = BodyAnim:GetBonePosition(bone)
	if not pos or not ang then return end

	local offset = cvTrickCamOffset and cvTrickCamOffset:GetFloat() or 0
	local up = cvTrickCamUp and cvTrickCamUp:GetFloat() or 0

	-- Both offsets are applied in world space: in a slide the body is lying down, so the head's local
	-- "up" axis points horizontally. Using it pushed the camera out in FRONT of the body (empty frame)
	-- and made Beatrun_TrickCamOffset move the camera vertically.
	local fwd = (IsValid(LocalPlayer()) and LocalPlayer():EyeAngles() or ang)
	fwd = Angle(0, fwd.y, 0):Forward()

	return pos + fwd * offset + Vector(0, 0, up), ang
end

-- Orientation of the animation itself. The head bone is a bad source (in a slide the head is tilted
-- back, so the camera stares at the sky); the rig's CameraJoint is authored as a camera and is what
-- Beatrun locks to, so it is the default.
local function GetAnimCamAngles(mode)
	if not IsValid(BodyAnim) then return end

	if mode == 2 then
		BodyAnim:SetupBones()
		local id = BodyAnim:LookupAttachment(camjoint)
		if id and id > 0 then
			local data = BodyAnim:GetAttachment(id)
			if data and data.Ang then return Angle(data.Ang), "CameraJoint" end
		end
	end

	local bone = BodyAnim:LookupBone("ValveBiped.Bip01_Head1") or BodyAnim:LookupBone("ValveBiped.Bip01_Neck1")
	if bone then
		local _, ang = BodyAnim:GetBonePosition(bone)
		if ang then return Angle(ang), "head bone" end
	end

	return Angle(0, BodyAnim:GetAngles().y, 0), "rig yaw"
end

local function ApplyBodyAnimToView(ply, view, isFallback)
	if not IsValid(ply) or not ply:Alive() or ply:InVehicle() then return end
	if IsValid(ply.FakeRagdoll) then
		if not IsValid(BodyAnim) then
			attach = nil
			endlerp = 0
		end
		return
	end

	-- Third person trick camera (Beatrun_TrickCamMode 1): clearly shows the animation instead of
	-- sitting inside its head. Uses the rig's head position, pulled back and up, aimed at the body.
	if ShouldUseTrickCam(ply) and GetTrickCamMode() == 1 and IsValid(BodyAnim) then
		BodyAnim:SetupBones()

		local bone = BodyAnim:LookupBone("ValveBiped.Bip01_Head1") or BodyAnim:LookupBone("ValveBiped.Bip01_Neck1")
		local headPos = bone and BodyAnim:GetBonePosition(bone)

		if headPos then
			local eyeang = ply:EyeAngles()
			eyeang.x = 0
			eyeang.z = 0

			local dist = cvTrickCamDist and cvTrickCamDist:GetFloat() or 150
			local height = cvTrickCamHeight and cvTrickCamHeight:GetFloat() or 45

			local desired = headPos - eyeang:Forward() * dist + Vector(0, 0, height)

			-- Keep the camera out of walls
			local tr = util.TraceHull({
				start = headPos,
				endpos = desired,
				mins = Vector(-8, -8, -8),
				maxs = Vector(8, 8, 8),
				filter = ply,
				mask = MASK_SOLID
			})
			if tr.Hit then desired = tr.HitPos end

			if lastTrickCamPos then
				view.origin = LerpVector(math.Clamp(FrameTime() * 18, 0, 1), lastTrickCamPos, desired)
			else
				view.origin = desired
			end

			lastTrickCamPos = Vector(view.origin)

			view.angles = (headPos - view.origin):Angle()
			view.drawviewer = false
			BeatrunZCityCamAnchor = "thirdperson"

			return isFallback and view or nil
		end
	end

	if BeatrunIsThirdPerson(ply) then
		-- Hide the static body the engine draws in third person, otherwise the player sees his normal
		-- (running/idle) model and the animated trick body at the same time.
		if (cvHideBody == nil or cvHideBody:GetBool()) and IsValid(BodyAnim) then
			view.drawviewer = false
		end

		-- Z-City's camera stays in charge unless the trick camera is enabled.
		-- When enabled the view is attached to the animation for the duration of the slide/roll.
		if not ShouldUseTrickCam(ply) then
			if not IsValid(BodyAnim) then
				attach = nil
				lastTrickCamPos = nil
				endlerp = 0
			end
			return
		end
	end

	if IsValid(BodyAnim) then
		local oldang = BodyAnim:GetAngles()
		local eyeang = ply:EyeAngles()
		if CamIgnoreAng then
			BodyAnim:SetAngles(Angle(0, eyeang.y, 0))
		end

		if lastatt and lastatt ~= camjoint then
			savedatt = lastatt
			lerpchangeatt = 0
		end

		-- Exactly like Beatrun: the camera rides the rig's own camera attachment ("CameraJoint"),
		-- which is placed at the eyes in every slide/roll animation. The head bone (pushed out by
		-- Beatrun_TrickCamOffset) and the "eyes" attachment are only fallbacks for a rig without it.
		BodyAnim:SetupBones()

		local attData
		local anchorMode = cvTrickCamAnchor and cvTrickCamAnchor:GetInt() or 0

		-- 2 = do not move the camera at all: stay at your own eyes and only watch your animated body
		if anchorMode == 2 then
			BeatrunZCityCamAnchor = "own eye"
			view.drawviewer = false
			return isFallback and view or nil
		end

		-- 1 = the rig's camera attachment (Beatrun's original anchor), 0 = the head bone itself
		if anchorMode == 1 then
			local attId = BodyAnim:LookupAttachment(camjoint)
			if attId and attId > 0 then
				attData = BodyAnim:GetAttachment(attId)
				if attData then BeatrunZCityCamAnchor = "attachment:" .. tostring(camjoint) end

				local offset = cvTrickCamOffset and cvTrickCamOffset:GetFloat() or 0
				local up = cvTrickCamUp and cvTrickCamUp:GetFloat() or 0
				if attData and attData.Ang then
					local fwd = Angle(0, ply:EyeAngles().y, 0):Forward()
					attData = {
						Pos = Vector(attData.Pos) + fwd * offset + Vector(0, 0, up),
						Ang = Angle(attData.Ang)
					}
				end
			end
		end

		if not attData then
			local headPos, headAng = GetTrickCamAttachment()
			if headPos then
				attData = { Pos = headPos, Ang = headAng }
				BeatrunZCityCamAnchor = "bone:head"
			end
		end

		if not attData then
			local eyesId = BodyAnim:LookupAttachment("eyes")
			if eyesId and eyesId > 0 then
				attData = BodyAnim:GetAttachment(eyesId)
				if attData then BeatrunZCityCamAnchor = "attachment:eyes" end
			end
		end

		if not attData then BeatrunZCityCamAnchor = "none" end

		-- The animation's head sits higher than the player's own ducked eye (37 vs 28 units in a
		-- slide), which made the trick camera feel like a detached third person camera above you.
		-- Keep the animation's horizontal position, but hold the camera at your own eye height.
		if attData and (cvTrickCamMatchEye == nil or cvTrickCamMatchEye:GetBool()) then
			local eye = ply:EyePos()
			local up = cvTrickCamUp and cvTrickCamUp:GetFloat() or 0
			attData = {
				Pos = Vector(attData.Pos.x, attData.Pos.y, eye.z + up),
				Ang = attData.Ang
			}
			BeatrunZCityCamAnchor = BeatrunZCityCamAnchor .. "+eyeheight"
		end

		if attData then
			if lerpchangeatt < 1 and savedatt then
				local prevId = BodyAnim:LookupAttachment(savedatt)
				local prevData = prevId and prevId > 0 and BodyAnim:GetAttachment(prevId) or attData
				lerpedpos = LerpVector(lerpchangeatt, prevData.Pos, attData.Pos)
				lerpchangeatt = math.Approach(lerpchangeatt, 1, FrameTime() * 6)
			end

			BodyAnim:SetAngles(oldang)

			BeatrunZCityTrickEyePos = Vector(attData.Pos)
			BeatrunZCityTrickEyeAng = Angle(view.angles or attData.Ang)

			view.origin = lerpchangeatt < 1 and lerpedpos or attData.Pos
			if cvHideBody and cvHideBody:GetBool() then
				-- Native Source engine hiding of LocalPlayer during 1P BodyAnim without touching hg.renderOverride
				view.drawviewer = false
			end

			local angMode = cvCamAngles and cvCamAngles:GetInt() or 0

			-- While the player is shooting, the weapon has to aim where the mouse points. Forcing the
			-- animation's angles (and SetEyeAngles) every frame made shooting impossible during a slide.
			-- Distance of the head: a slide started with a weapon keeps the player's own view angles, so
			-- he can turn the head and aim the whole slide long. A slide started bare-handed stays locked
			-- to the animation and cannot be turned at all.
			local freeAim = (cvSlideShoot == nil or cvSlideShoot:GetBool()) and ply._BRZSlideArmed

			if freeAim then
				BeatrunZCityCamAngles = "player (weapon in hand)"
			elseif lockang then
				view.angles = Angle(attData.Ang)
				local neweye = Angle(attData.Ang)
				neweye.y = BodyAnim:GetAngles().y
				neweye.z = 0
				ply:SetEyeAngles(neweye)
				BeatrunZCityCamAngles = "locked"
			elseif angMode ~= 0 then
				-- The camera is attached to the animation in orientation too, so it turns and tilts with
				-- the body instead of just sliding along beside it.
				local animAng, source = GetAnimCamAngles(angMode)
				view.angles = Angle(animAng or attData.Ang)
				view.angles:Add(ply:GetSmoothViewPunchAngles() + ply:GetCLViewPunchAngles())

				local neweye = Angle(view.angles)
				neweye.y = BodyAnim:GetAngles().y
				neweye.z = 0
				ply:SetEyeAngles(neweye)
				BeatrunZCityCamAngles = "anim:" .. tostring(source)
			elseif BeatrunIsThirdPerson(ply) then
				-- Third person: follow the player's aim, Z-City's own camera angles do not match the body
				view.angles = Angle(eyeang)
			end
			-- First person: the incoming view angles (Z-City's eye angles + viewpunch) are already
			-- correct for the head, so only the origin is replaced.

			if cvCamTilt and cvCamTilt:GetBool() and (not cvCamAngles or cvCamAngles:GetInt() == 0) and not lockang then
				local angYaw = view.angles.y
				local target = lockang and (ply.OrigEyeAng and ply.OrigEyeAng.y or angYaw) or angYaw
				viewtiltlerp.y = math.ApproachAngle(viewtiltlerp.y, target, FrameTime() * (1 + math.abs(math.AngleDifference(viewtiltlerp.y, target)) * 5))
				local diff = math.AngleDifference(viewtiltlerp.y, lockang and (ply.OrigEyeAng and ply.OrigEyeAng.y or angYaw) or lastangy) * 0.15
				ViewTiltAngle = Angle(0, 0, diff + viewtiltlerp.z)
				view.angles:Add(ViewTiltAngle)
				view.angles:Add(ply:GetSmoothViewPunchAngles() + ply:GetCLViewPunchAngles())
				lastangy = angYaw
			end

			if CamShake then
				CamShakeAng:Set(Angle(0, 0, math.Rand(-0.9, 0.9) * CamShakeMult))
				view.angles:Add(CamShakeAng)
			end

			lastattachpos = Vector(view.origin)
			lastattachang = Angle(view.angles)
			lastatt = camjoint
			return isFallback and view or nil
		end

		BodyAnim:SetAngles(oldang)
	elseif attach ~= nil then
		endlerp = math.Approach(endlerp, 1, RealFrameTime() * 7)
		local targetPos = lastNativeCamPos or ply:EyePos()
		local targetAng = lastNativeCamAng or ply:EyeAngles()

		view.origin = LerpVector(endlerp, attach.Pos, targetPos)
		view.angles = LerpAngle(math.min(1, endlerp * 1.4), attach.Ang, targetAng)

		if endlerp >= 1 then
			attach = nil
			endlerp = 0
		end
		return isFallback and view or nil
	end
end

local function ApplyTrickCam(ply, view)
	if not istable(view) or not view.origin or not view.angles then return end
	if lastAppliedFrame == FrameNumber() then return end

	lastAppliedFrame = FrameNumber()
	lastNativeCamPos = Vector(view.origin)
	lastNativeCamAng = Angle(view.angles)

	local before = Vector(view.origin)
	local ok, err = pcall(ApplyBodyAnimToView, ply, view, false)

	-- beatrun_zcity_camtest: lift the camera 300 units for 5 seconds. If the world does not jump,
	-- the camera stack is not using our CalcView result at all.
	if (BeatrunZCityCamTestUntil or 0) > CurTime() then
		view.origin = Vector(view.origin) + Vector(0, 0, 300)
		BeatrunZCityCamAnchor = "SELF-TEST (+300 up)"
	end

	if not ok then
		BeatrunZCityCamError = tostring(err)
	elseif view.origin ~= before then
		-- Only report success when the camera was actually moved onto the trick
		BeatrunZCityTrickCamApplied = FrameNumber()
		BeatrunZCityTrickCamAppliedTime = CurTime()
	end
end

BeatrunAddOrderedHook("PostHGCalcView", "zz_BeatrunZCity_SlideRollCam", function(ply, view)
	if ply ~= LocalPlayer() then return end
	ApplyTrickCam(ply, view)
end, "HOOK_LOW")

BeatrunAddOrderedHook("PostPostHGCalcView", "zz_BeatrunZCity_SlideRollCam", function(ply, view)
	if ply ~= LocalPlayer() then return end
	ApplyTrickCam(ply, view)
end, "HOOK_LOW")

-- Z-City owns the camera through its own "CalcView" hook ("homigrad-view"), and whichever hook
-- returns a view first wins the hook.Call chain. Wrapping the *returned* view is therefore the only
-- reliable way to put the camera onto the trick, in first AND third person.
-- The hooks are wrapped by writing straight into the CalcView hook table (no hook.Add during the
-- iteration, which silently failed on some builds), and every failure is reported to the HUD.
BeatrunZCityCalcViewHookCount = 0
BeatrunZCityCameraWrapped = 0

local wrapAttempts = 0
local wrapDone = false
local wrapAnnounced = false

-- Lua functions cannot hold fields ("attempt to index a function value"), so the installed
-- wrappers are tracked here by name instead of marking the functions themselves.
local wrappedOriginal = {}
local wrappedCurrent = {}

local function GetCalcViewTable()
	local t
	if isfunction(hook.GetTable) then
		local ok, tbl = pcall(hook.GetTable)
		if ok and istable(tbl) then t = tbl["CalcView"] end
	end
	if not t and istable(_G.Hooks) then t = _G.Hooks["CalcView"] end
	return istable(t) and t or nil
end

local function MakeCalcViewWrapper(name, original)
	local wrapper = function(ply, ...)
		-- A broken camera hook must never kill the view: catch and report it instead
		local ok, a, b, c, d, e, f = pcall(original, ply, ...)
		if not ok then
			BeatrunZCityCamError = "CalcView[" .. tostring(name) .. "]: " .. tostring(a)
			return
		end

		if istable(a) and (IsValid(BodyAnim) or attach ~= nil or (BeatrunZCityCamTestUntil or 0) > CurTime()) then
			ApplyTrickCam(ply, a)
			BeatrunZCityLastCamOrigin = Vector(a.origin or vector_origin)
		end

		return a, b, c, d, e, f
	end

	return wrapper
end

local function WrapCalcViewHooks()
	local calcview = GetCalcViewTable()
	if not calcview then
		BeatrunZCityCamWrapError = "no CalcView hook table"
		return
	end

	local names = {}
	for name, fn in pairs(calcview) do
		if isstring(name) and isfunction(fn) and wrappedCurrent[name] ~= fn then
			names[#names + 1] = name
		end
	end

	BeatrunZCityCalcViewHookCount = table.Count(calcview)

	for i = 1, #names do
		local name = names[i]
		local fn = calcview[name]
		if isfunction(fn) then
			wrappedOriginal[name] = fn
			local wrapper = MakeCalcViewWrapper(name, fn)
			wrappedCurrent[name] = wrapper
			calcview[name] = wrapper
		end
	end

	local wrapped = 0
	for name, wrapper in pairs(wrappedCurrent) do
		if calcview[name] == wrapper then wrapped = wrapped + 1 end
	end
	BeatrunZCityCameraWrapped = wrapped

	BeatrunZCityCamWrapError = nil

	if not wrapAnnounced and (BeatrunZCityCameraWrapped or 0) > 0 then
		wrapAnnounced = true
		print("[Beatrun Z-City] trick camera: wrapped " .. tostring(BeatrunZCityCameraWrapped) .. " CalcView hook(s)")
	end
end

local function TryWrap()
	local ok, err = pcall(WrapCalcViewHooks)
	if not ok then
		BeatrunZCityCamWrapError = tostring(err)
		return false
	end

	-- Wrapped every hook that exists so far; keep retrying for a while in case Z-City adds its
	-- camera hook late (map change / gamemode reload), but stop after ~20 seconds.
	return (BeatrunZCityCameraWrapped or 0) > 0
end

hook.Add("Think", "BeatrunZCity_WrapZCityCamera", function()
	wrapAttempts = wrapAttempts + 1

	if wrapAttempts % 15 == 1 then
		wrapDone = TryWrap() or wrapDone
	elseif wrapDone and (BeatrunZCityCameraWrapped or 0) < BeatrunZCityCalcViewHookCount then
		TryWrap()
	end

	if wrapAttempts > 1200 then
		hook.Remove("Think", "BeatrunZCity_WrapZCityCamera")
	end
end)

-- Retry once more when a map / gamemode reload happens
hook.Add("OnGamemodeLoaded", "BeatrunZCity_WrapZCityCamera", function()
	wrapAttempts = 0
	wrapDone = false
	TryWrap()
end)

BeatrunAddOrderedHook("CalcView", "zz_BeatrunZCity_SlideRollCamFallback", function(ply, origin, angles, fov)
	if ply ~= LocalPlayer() then return end
	if lastAppliedFrame == FrameNumber() then return end
	if not IsValid(BodyAnim) and attach == nil then return end

	lastNativeCamPos = Vector(origin)
	lastNativeCamAng = Angle(angles)

	local view = {
		origin = Vector(origin),
		angles = Angle(angles),
		fov = fov
	}
	return ApplyBodyAnimToView(ply, view, true)
end, "HOOK_LOW")

-- The old "eye offset" fallback is gone: it moved the player's own ViewOffset instead of riding the
-- animation, which is exactly why the slide camera felt detached from the body while the roll (which
-- skipped that fallback) felt right. The trick camera is now only ever the animation attachment.
BeatrunZCityEyeFallbackActive = false

local function StopEyeFallback(ply)
	if IsValid(ply) then
		local saved = BeatrunZCitySavedViewOffset
		if saved then ply:SetViewOffset(saved) end
		local savedDucked = BeatrunZCitySavedViewOffsetDucked
		if savedDucked then ply:SetViewOffsetDucked(savedDucked) end
	end
	BeatrunZCitySavedViewOffset = nil
	BeatrunZCitySavedViewOffsetDucked = nil
end

-- Z-City builds and renders its own view (lua/homigrad/cl_camera.lua calls render.RenderView itself),
-- so a CalcView return can be ignored no matter what we ask for. While an animation is alive we take
-- the final view over at the last moment: the view that actually gets rendered is the animation's.
local forceViewHits = 0
local origRenderView = render.RenderView
local origStart3D = cam and cam.Start3D

local function ForcedView()
	if not IsValid(BodyAnim) then return end
	if not isvector(BeatrunZCityTrickEyePos) then return end

	local cv = GetConVar("Beatrun_ForceCam")
	if cv and not cv:GetBool() then return end

	forceViewHits = forceViewHits + 1
	return BeatrunZCityTrickEyePos, BeatrunZCityTrickEyeAng
end

if isfunction(origRenderView) then
	render.RenderView = function(view, ...)
		local pos, ang = ForcedView()
		if pos and istable(view) then
			view.origin = Vector(pos)
			if ang then view.angles = Angle(ang) end
		end
		return origRenderView(view, ...)
	end
end

if isfunction(origStart3D) then
	cam.Start3D = function(pos, ang, fov, ...)
		local fpos, fang = ForcedView()
		if fpos then
			pos = Vector(fpos)
			if fang then ang = Angle(fang) end
		end
		return origStart3D(pos, ang, fov, ...)
	end
end

hook.Add("Think", "BeatrunZCity_ForceCamRate", function()
	BeatrunZCityForceCamHits = forceViewHits
	forceViewHits = 0
end)

concommand.Add("beatrun_zcity_camtest", function()
	BeatrunZCityCamTestUntil = CurTime() + 5
	print("[Beatrun Z-City] camera self test: for 5 seconds the view is lifted 300 units.")
	print("[Beatrun Z-City] if the camera does not move, the camera stack ignores CalcView.")
end)

local function GetArmedSlideYawConstraint(ply)
	if not IsValid(ply) or not ply:Alive() or not ply:GetSliding() then return nil, 0 end
	if not BeatrunCanSlideOrRoll(ply) then return nil, 0 end
	if not (ply._BRZSlideArmed or BeatrunWeaponArmed(ply)) then return nil, 0 end

	local limit = isfunction(BeatrunGetSlideYawLimit) and BeatrunGetSlideYawLimit() or 90
	if limit <= 0 then return nil, 0 end

	local slideAng = ply.GetSlidingAngle and ply:GetSlidingAngle() or nil
	local baseYaw = (isangle(slideAng) and slideAng.y)
		or (IsValid(BodyAnim) and BodyAnim:GetAngles().y)
		or (isangle(ply.OrigEyeAng) and ply.OrigEyeAng.y)
	if not isnumber(baseYaw) then return nil, 0 end

	return baseYaw, limit
end

-- Primary Z-City mouse limit hook: runs inside Z-City's InputMouseApply ("fakeCameraAngles") BEFORE
-- ViewPunch3/4 and before `angle.yaw = angle.yaw - x / 50`, so hitting +/-90 deg feels like a clean
-- smooth stop with zero sticking when turning back toward center and zero phantom wall-sway.
BeatrunAddOrderedHook("HG.InputMouseApply", "aa_BeatrunZCity_SlideYawLimit", function(tbl)
	if not istable(tbl) or not isangle(tbl.angle) then return end
	if lockang then return end

	local ply = LocalPlayer()
	local baseYaw, limit = GetArmedSlideYawConstraint(ply)
	if not baseYaw then return end

	local curYaw = tbl.angle.yaw
	local curDiff = math.AngleDifference(curYaw, baseYaw) -- >0 left, <0 right
	local x = tbl.x or 0
	local step = -x / 50 -- Z-City applies angle.yaw = angle.yaw - x / 50

	if curDiff > limit then
		if step > 0 then tbl.x = 0 end
		tbl.angle.yaw = math.NormalizeAngle(baseYaw + limit)
	elseif curDiff < -limit then
		if step < 0 then tbl.x = 0 end
		tbl.angle.yaw = math.NormalizeAngle(baseYaw - limit)
	else
		local nextDiff = curDiff + step
		if nextDiff > limit then
			tbl.x = -(limit - curDiff) * 50
		elseif nextDiff < -limit then
			tbl.x = -(-limit - curDiff) * 50
		end
	end
end, "HOOK_HIGH")

hook.Add("CreateMove", "BeatrunZCity_BodyAnimMouse", function(cmd)
	local ply = LocalPlayer()
	if not IsValid(ply) then
		pastlimitx = false
		pastlimity = false
		BodyAnimLimitEase = false
		return
	end

	-- Armed slide horizontal turn cone (+/-90 deg by default): always enforced while sliding with a
	-- weapon so keyboard turns (+left/+right), non-Z-City input, recoil or inverted mouse cannot
	-- twist the player behind their own back.
	local slideBaseYaw, slideYawLimit = GetArmedSlideYawConstraint(ply)
	if slideBaseYaw and not lockang then
		local nang = cmd:GetViewAngles()
		local diff = math.AngleDifference(nang.y, slideBaseYaw)
		if diff > slideYawLimit then
			nang.y = math.NormalizeAngle(slideBaseYaw + slideYawLimit)
			cmd:SetViewAngles(nang)
		elseif diff < -slideYawLimit then
			nang.y = math.NormalizeAngle(slideBaseYaw - slideYawLimit)
			cmd:SetViewAngles(nang)
		end
	end

	if not IsValid(BodyAnim) or lockang or not ply.OrigEyeAng
		or (cvCamLimits and not cvCamLimits:GetBool()) then
		pastlimitx = false
		pastlimity = false
		BodyAnimLimitEase = false
		return
	end

	local nang = cmd:GetViewAngles()
	local oang = ply.OrigEyeAng
	local limitx = BodyLimitX or 40
	local limity = BodyLimitY or 80
	if slideBaseYaw and slideYawLimit > 0 and slideYawLimit < limity then
		limity = slideYawLimit
	end

	pastlimitx = math.AngleDifference(nang.x, oang.x) > limitx
	pastlimity = math.abs(math.AngleDifference(nang.y, oang.y)) > limity

	if (limitx ~= lastlimitx and pastlimitx) or (limity ~= lastlimity and pastlimity) then
		BodyAnimLimitEase = true
	end

	if pastlimitx then
		if BodyAnimLimitEase then
			nang.x = math.Approach(nang.x, oang.x + limitx, FrameTime() * 125)
		else
			nang.x = oang.x + limitx
		end
		cmd:SetViewAngles(nang)
	elseif not pastlimity then
		BodyAnimLimitEase = false
	end

	if pastlimity then
		if math.AngleDifference(nang.y, oang.y) < 0 then
			nang.y = BodyAnimLimitEase and math.ApproachAngle(nang.y, oang.y - limity, FrameTime() * 300) or math.NormalizeAngle(oang.y - limity)
		else
			nang.y = BodyAnimLimitEase and math.ApproachAngle(nang.y, oang.y + limity, FrameTime() * 300) or math.NormalizeAngle(oang.y + limity)
		end
		cmd:SetViewAngles(nang)
	elseif not pastlimitx then
		BodyAnimLimitEase = false
	end

	lastlimitx = limitx
	lastlimity = limity
end)

BeatrunAddOrderedHook("InputMouseApply", "zz_BeatrunZCity_BodyAnimMouse", function(cmd, x, y, ang)
	local ply = LocalPlayer()

	if IsValid(BodyAnim) and lockang then
		cmd:SetMouseX(0)
		cmd:SetMouseY(0)
		return true
	end

	-- Fallback for non-Z-City environments where HG.InputMouseApply is not invoked.
	local slideBaseYaw, slideYawLimit = GetArmedSlideYawConstraint(ply)
	if slideBaseYaw and isangle(ang) then
		local curDiff = math.AngleDifference(ang.y, slideBaseYaw)
		local mx = x or 0
		local step = -mx * 0.022
		local nextDiff = curDiff + step
		if nextDiff > slideYawLimit or nextDiff < -slideYawLimit then
			local targetDiff = math.Clamp(nextDiff, -slideYawLimit, slideYawLimit)
			ang.y = math.NormalizeAngle(slideBaseYaw + targetDiff)
			ang.p = math.Clamp(ang.p + (y or 0) * 0.022, -89, 89)
			cmd:SetViewAngles(ang)
			return true
		end
	end

	if not IsValid(BodyAnim) then
		pastlimitx = false
		pastlimity = false
		return
	end

	if cvCamLimits and not cvCamLimits:GetBool() then return end

	local clamped = false
	if pastlimitx and (y or 0) > 0 then
		cmd:SetMouseY(0)
		clamped = true
	end
	if pastlimity and isangle(ang) and IsValid(ply) and isangle(ply.OrigEyeAng) then
		local diff = math.AngleDifference(ang.y, ply.OrigEyeAng.y)
		if (diff > 0 and (x or 0) < 0) or (diff < 0 and (x or 0) > 0) then
			cmd:SetMouseX(0)
			clamped = true
		end
	end
	if clamped then return true end
end, "HOOK_LOW")

hook.Add("ShutDown", "BeatrunZCity_BodyAnimCleanup", function()
	RemoveBodyAnim(false)
end)
