-- Ledge climb & hang animation controller for the Beatrun Z-City addon (2.21.7).
-- Uses the same rig and the same StartBodyAnim pipeline as the slide and the safety roll, so the body,
-- the Z-City appearance/gloves and the trick camera behave exactly like they already do for those tricks.

local cvAnimSet = GetConVar("Beatrun_AnimSet")
local cvHeaveTime = GetConVar("Beatrun_ZCity_ClimbHeaveTime")

local climbAnimState = 0 -- 0 = none, 1 = hang, 2 = heave

local GRAB_ANIMS = {
	["hanghardstart"] = true,
	["hanghardstart2"] = true,
	["hanghardstartvertical"] = true,
	["hangpose"] = true,
	["hang"] = true,
}

local function GetRigName()
	return (cvAnimSet and cvAnimSet:GetInt() == 1) and "old_climbanim" or "new_climbanim"
end

local function IsHangSequence(name)
	return isstring(name) and GRAB_ANIMS[name] == true
end

-- Beatrun's climb state sets exactly these view limits (BodyLimitX 80 / BodyLimitY 170), the same
-- numbers its own sh/climb.lua pushes while the player hangs.
local function ClimbClampLimits()
	BodyLimitX = 80
	BodyLimitY = 170
end

-- 2.21.18: the player's origin hangs 0.533 units INSIDE the wall (Beatrun's own ClimbingCheck number),
-- so the rig and the trick camera riding its head bone ended up inside the wall brush. The rendered rig
-- is pushed back out by this much - the body still hugs the wall, the camera no longer clips into the map.
local HANG_WALL_GAP = 8

local function HangOffset(ang)
	if not ang then return nil end
	local fwd = ang:Forward()
	return fwd * -HANG_WALL_GAP
end

-- Jumped onto a ledge: play the grab animation, then fall into the hang pose
function BeatrunZCityClimbAnimGrab(ang, hard)
	local ply = LocalPlayer()
	if not IsValid(ply) or not BeatrunCanSlideOrRoll(ply) then return end

	-- Client prediction and the server trigger can both call this - never restart a running grab
	if climbAnimState == 1 and IsValid(BodyAnim) and IsHangSequence(BodyAnimString) then return end

	climbAnimState = 1
	ClimbClampLimits()

	local cvDbg = GetConVar("Beatrun_RollDebugLog")
	if cvDbg and cvDbg:GetBool() then
		print(string.format("[Beatrun Z-City] climb anim: grab %s (hard=%s, rig %s)",
			hard and "hanghardstart2" or "hanghardstart", tostring(hard), GetRigName()))
	end

	StartBodyAnim({
		AnimString = hard and "hanghardstart2" or "hanghardstart",
		animmodelstring = GetRigName(),
		camjoint = "CameraJoint",
		deleteonend = false,
		followplayer = true,
		lockang = false,
		allowmove = true,
		BodyAnimSpeed = hard and 1.25 or 1.1,
		BodyLimitX = 80,
		BodyLimitY = 170,
		posoffset = HangOffset(ang),
		StartAngle = ang or ply:EyeAngles()
	})
end

-- Pulling up over the edge. Two sequences, exactly the split Beatrun makes:
--   low ledge  -> "vaultonto"   (Beatrun's small-obstacle vault, a single animation for the whole climb)
--   real ledge -> "hangheaveup" (the pull-up after the hang, Beatrun's "climbheave")
function BeatrunZCityClimbAnimHeave(ang, low)
	local ply = LocalPlayer()
	if not IsValid(ply) or not BeatrunCanSlideOrRoll(ply) then return end

	local dur = low and 0.5 or math.max(0.2, cvHeaveTime and cvHeaveTime:GetFloat() or 0.85)
	local seqName = low and "vaultonto" or "hangheaveup"

	-- Client prediction and the server trigger can both ask for the pull-up - never restart it, and
	-- never cut a vaultonto that is already playing (it is the whole low-ledge climb).
	if IsValid(BodyAnim) and BodyAnimString == seqName and BodyAnimCycle < 0.5 then
		return
	end

	climbAnimState = 2
	ClimbClampLimits()

	local cvDebug = GetConVar("Beatrun_RollDebugLog")
	if cvDebug and cvDebug:GetBool() then
		print(string.format("[Beatrun Z-City] climb anim: %s (%.2fs, rig %s)", seqName, dur, GetRigName()))
	end

	StartBodyAnim({
		AnimString = seqName,
		animmodelstring = GetRigName(),
		camjoint = "CameraJoint",
		deleteonend = false,
		followplayer = true,
		lockang = false,
		allowmove = true,
		BodyAnimSpeed = 1,
		BodyLimitX = 80,
		BodyLimitY = 170,
		-- the vault starts from the player's own position (open air), the pull-up starts off a hang
		posoffset = low and nil or HangOffset(ang),
		StartAngle = ang or ply:EyeAngles()
	})

	-- Make the animation last exactly as long as the pull-up movement does
	if IsValid(BodyAnim) then
		local seqDur = BodyAnim:SequenceDuration()
		if seqDur and seqDur > 0.05 then
			BodyAnimSpeed = math.Clamp(seqDur / dur, 0.7, 1.8)
		end
	end
end

function BeatrunZCityClimbAnimEnd(landed)
	climbAnimState = 0
	if IsValid(BodyAnim) and (IsHangSequence(BodyAnimString) or BodyAnimString == "hangheaveup"
		or BodyAnimString == "vaultonto") then
		RemoveBodyAnim(landed and true or false)
	end
end

-- Grab animation -> hang loop. The hang sequence holds the pose until W pulls the player up.
hook.Add("Think", "BeatrunZCity_ClimbAnimThink", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local state = (isfunction(ply.GetBRZClimbState) and ply:GetBRZClimbState()) or 0

	if state == 0 then
		if climbAnimState ~= 0 then
			BeatrunZCityClimbAnimEnd(false)
		end
		return
	end

	climbAnimState = state

	if not IsValid(BodyAnim) then return end

	if state == 1 then
		if IsHangSequence(BodyAnimString) and BodyAnimString ~= "hang" then
			if BodyAnimCycle >= 0.92 then
				local seq = BodyAnim:LookupSequence("hang")
				if seq and seq >= 0 then
					BodyAnim:ResetSequence(seq)
					BodyAnimString = "hang"
					BodyAnimCycle = 0
					BodyAnimSpeed = 1
				end
			end
		elseif BodyAnimString == "hang" and BodyAnimCycle >= 1 then
			-- subtle idle loop while gripping
			BodyAnimCycle = 0
			BodyAnim:SetCycle(0)
		end
	end
end)

-- Server -> owning client animation triggers (dedicated servers)
net.Receive("Beatrun_ZC_ClimbGrab", function()
	local ang = net.ReadAngle()
	local hard = net.ReadBool()
	BeatrunZCityClimbAnimGrab(ang, hard)
end)

net.Receive("Beatrun_ZC_ClimbHeave", function()
	local ang = net.ReadAngle()
	local low = net.ReadBool()
	BeatrunZCityClimbAnimHeave(ang, low)
end)

net.Receive("Beatrun_ZC_ClimbEnd", function()
	local landed = net.ReadBool()
	BeatrunZCityClimbAnimEnd(landed)
end)
