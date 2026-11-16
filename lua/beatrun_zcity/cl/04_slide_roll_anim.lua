-- Slide & Safety Roll animation controller.
-- Starts BodyAnim ONLY when a slide or roll begins and removes it cleanly when finished.

local cvAnimSet = GetConVar("Beatrun_AnimSet")
local cvRollAlways = GetConVar("Beatrun_RollAlways")
local cvRollAnim = GetConVar("Beatrun_RollAnim")
local cvRollHolster = GetConVar("Beatrun_ZCity_RollHolster")
local cvCamLock = GetConVar("Beatrun_TrickCamLockAng")

local function GetRigName()
	return (cvAnimSet and cvAnimSet:GetInt() == 1) and "old_climbanim" or "new_climbanim"
end

local slideState = "idle" -- "idle" | "sliding" | "ending"
local lastRollToken = 0
local slideHandled = false

local function SlideAnimThink()
	local ply = LocalPlayer()
	local ba = BodyAnim

	if not IsValid(ply) or not BeatrunCanSlideOrRoll(ply) then
		hook.Remove("Think", "BeatrunZCity_SlideAnimThink")
		slideState = "idle"
		CamShake = false
		RemoveBodyAnim(false)
		return
	end

	if not ply:GetSliding() then
		hook.Remove("Think", "BeatrunZCity_SlideAnimThink")
		CamShake = false
		if slideState == "sliding" then
			BeatrunSlideAnimEnd(false, PlayerCannotStand(ply))
		end
		return
	end

	if IsValid(ba) then
		local seq = ba:GetSequenceName(ba:GetSequence())
		if (seq == "meslidestart" and BodyAnimCycle >= 0.55) then
			local loopSeq = ba:LookupSequence("meslideloop")
			if loopSeq and loopSeq >= 0 then
				ba:SetSequence(loopSeq)
				BodyAnimString = "meslideloop"
				BodyAnimCycle = 0
			end
		elseif (seq == "meslidestart45" and BodyAnimCycle >= 0.55) then
			local loopSeq = ba:LookupSequence("meslideloop45")
			if loopSeq and loopSeq >= 0 then
				ba:SetSequence(loopSeq)
				BodyAnimString = "meslideloop45"
				BodyAnimCycle = 0
			end
		end

		local slideAng = ply:GetSlidingAngle()
		ply.OrigEyeAng = Angle(0, slideAng.y, 0)

		local tr = util.QuickTrace(ply:GetPos(), Vector(0, 0, -64), ply)
		local normal = tr.HitNormal
		local oldang = ba:GetAngles()
		local targetAng = Angle(oldang)
		targetAng.y = slideAng.y
		targetAng.x = math.max(normal:Angle().x + 90, 360)

		ba:SetAngles(LerpAngle(20 * FrameTime(), oldang, targetAng))
		BodyLimitX = math.min(20 + targetAng.x - 360, 60)
		CamShakeMult = ply:GetVelocity():Length() * 0.0005
	end
end

function BeatrunSlideAnimStart()
	local ply = LocalPlayer()
	if not IsValid(ply) or not BeatrunCanSlideOrRoll(ply) then return end

	-- Already sliding with a live animation (prediction + network trigger) - don't restart it
	if slideHandled and IsValid(BodyAnim) and (BodyAnimString == "meslidestart" or BodyAnimString == "meslidestart45" or BodyAnimString == "meslideloop" or BodyAnimString == "meslideloop45") then
		return
	end

	-- Sync the slide-start armed flag here as well so multiplayer net-triggered slides always know
	-- whether the slide started armed even if client SetupMove prediction skipped the start tick.
	local activeWep = ply:GetActiveWeapon()
	ply._BRZSlideArmed = BeatrunIsSlideWeapon(activeWep)

	local slippery = ply:GetSlidingSlippery()
	local slideAng = ply:GetSlidingAngle()

	StartBodyAnim({
		AnimString = slippery and "meslidestart45" or "meslidestart",
		animmodelstring = GetRigName(),
		-- Same camera setup as the safety roll (that is the view that looked right): the camera rides
		-- the animation's CameraJoint, and the body animation owns the view angles.
		camjoint = "CameraJoint",
		deleteonend = false,
		followplayer = true,
		lockang = not (cvCamLock and cvCamLock:GetInt() == 0),
		allowmove = true,
		BodyAnimSpeed = 1.1,
		BodyAnimCycle = (ply:Crouching() and 0.1 or 0),
		BodyLimitX = 40,
		BodyLimitY = 80,
		StartAngle = slideAng
	})

	CamShake = slippery
	slideState = "sliding"
	slideHandled = true
	hook.Add("Think", "BeatrunZCity_SlideAnimThink", SlideAnimThink)
end

function BeatrunSlideAnimEnd(slippery, blocked, fellOff)
	local ply = LocalPlayer()
	hook.Remove("Think", "BeatrunZCity_SlideAnimThink")
	CamShake = false

	if not IsValid(BodyAnim) then
		slideState = "idle"
		if fellOff then slideHandled = false end
		return
	end

	if not IsValid(ply) or not BeatrunCanSlideOrRoll(ply) then
		slideState = "idle"
		slideHandled = false
		RemoveBodyAnim(false)
		return
	end

	slideState = "ending"

	if slippery or fellOff then
		-- Slide jump, steep slope exit, or sliding off a ledge: immediately smooth-lerp camera
		-- back to Z-City instead of playing a grounded stand-up animation in mid-air.
		slideState = "idle"
		if fellOff then slideHandled = false end
		RemoveBodyAnim(true)
		return
	end

	local crouchEnd = blocked or PlayerCannotStand(ply) or BeatrunSlideHoldingCrouch
	local endAnim = crouchEnd and "meslideendcrouch" or "meslideend"
	local seq = BodyAnim:LookupSequence(endAnim)

	if not seq or seq < 0 then
		slideState = "idle"
		RemoveBodyAnim(true)
		return
	end

	BodyAnimString = endAnim
	BodyAnim:ResetSequence(seq)
	BodyAnim:SetCycle(0)
	BodyAnimCycle = 0
	BodyAnimSpeed = 1.35
	deleteonend = true
	CamIgnoreAng = false
	camjoint = "CameraJoint"

	-- Safety timeout if sequence fails to finish cleanly
	timer.Simple(0.55, function()
		if slideState == "ending" and (not IsValid(LocalPlayer()) or not LocalPlayer():GetSliding()) then
			slideState = "idle"
			if IsValid(BodyAnim) and (BodyAnimString == "meslideend" or BodyAnimString == "meslideendcrouch") then
				RemoveBodyAnim(true)
			end
		end
	end)
end

-- Undo every per-bone edit made on the trick body copies. Insurance: if anything ever leaked into the
-- player's own model instance, this clears it.
function BeatrunResetBodyBones()
	for _, ent in ipairs({ BodyAnimMDL, BodyAnimMDLarm }) do
		if IsValid(ent) then
			pcall(function()
				for i = 0, (ent:GetBoneCount() or 0) - 1 do
					ent:ManipulateBoneScale(i, Vector(1, 1, 1))
					ent:ManipulateBonePosition(i, vector_origin)
				end
				ent:SetupBones()
			end)
		end
	end
end

function BeatrunSlideAnimAbort()
	hook.Remove("Think", "BeatrunZCity_SlideAnimThink")
	CamShake = false
	slideState = "idle"
	slideHandled = false
	RemoveBodyAnim(false)
end

function BeatrunRollAnimStart(isLandInPlace, bigFall)
	local ply = LocalPlayer()
	if not IsValid(ply) or not BeatrunCanSlideOrRoll(ply) then return end

	-- "Land in place" becomes a real roll unless the player asked for the old behaviour
	if isLandInPlace and cvRollAlways and cvRollAlways:GetBool() then
		isLandInPlace = false
	end

	local holster = not cvRollHolster or cvRollHolster:GetBool()
	local holdingWeapon = false
	if holster then
		-- Immediately switch client weapon selection to bare hands to match server-side holstering
		if ply.GetWeapon and input and isfunction(input.SelectWeapon) then
			local hands = ply:GetWeapon("weapon_hands_sh") or ply:GetWeapon("weapon_hands") or ply:GetWeapon("gmod_hands")
			if IsValid(hands) and ply:GetActiveWeapon() ~= hands then
				pcall(input.SelectWeapon, hands)
			end
		end
	else
		local wep = ply:GetActiveWeapon()
		holdingWeapon = IsValid(wep) and wep:GetClass() ~= "weapon_hands_sh"
	end

	-- Beatrun_RollAnim 0 = plain landing animation, 1 = the actual roll
	local useRoll = not (cvRollAnim and cvRollAnim:GetInt() == 0)

	-- Height decides the pose (2.21.7): a hard fall from a roof lands crouched / rolls crouched, a short
	-- drop keeps the normal landing. The rig has land*, land*crouch, meroll* and meroll*crouch.
	local animName
	local speed
	if isLandInPlace or not useRoll then
		animName = bigFall and (holdingWeapon and "landguncrouch" or "landcrouch")
			or (holdingWeapon and "landgun" or "land")
		speed = bigFall and 0.95 or 1.05
	else
		animName = bigFall and (holdingWeapon and "merollguncrouch" or "merollcrouch")
			or (holdingWeapon and "merollgun" or "meroll")
		speed = bigFall and 0.95 or 1.15
	end

	-- The same animation may be requested twice (client prediction + the network trigger) - don't restart it
	if IsValid(BodyAnim) and BodyAnimString == animName then
		lastRollToken = ply:GetSafetyRollTime()
		return
	end

	slideState = "idle"
	slideHandled = false
	lastRollToken = ply:GetSafetyRollTime()
	hook.Remove("Think", "BeatrunZCity_SlideAnimThink")

	local rollAng = ply:GetSafetyRollAng()
	local startAng = (rollAng and rollAng ~= angle_zero) and rollAng or ply:EyeAngles()

	StartBodyAnim({
		AnimString = animName,
		animmodelstring = GetRigName(),
		camjoint = "CameraJoint",
		deleteonend = true,
		followplayer = true,
		lockang = useRoll and not isLandInPlace,
		allowmove = true,
		BodyAnimSpeed = speed,
		StartAngle = startAng
	})
end

function BeatrunRollAnimAbort()
	if IsValid(BodyAnim) and (string.find(BodyAnimString, "roll", 1, true) or string.find(BodyAnimString, "land", 1, true)) then
		RemoveBodyAnim(false)
	end
end

-- Multiplayer prediction reconciliation & safety monitor:
-- Ensures BodyAnim starts even if prediction skipped a frame, and cleans up immediately if interrupted.
hook.Add("Think", "BeatrunZCity_SlideRollSync", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	if not BeatrunCanSlideOrRoll(ply) then
		if IsValid(BodyAnim) or slideState ~= "idle" then
			BeatrunSlideAnimAbort()
		end
		return
	end

	local sliding = ply:GetSliding()
	local rollEndTime = ply:GetSafetyRollTime()
	local rolling = CurTime() < rollEndTime

	if not sliding then
		slideHandled = false
	end

	if sliding and not slideHandled and not IsValid(BodyAnim) then
		BeatrunSlideAnimStart()
	elseif not sliding and slideState == "sliding" then
		BeatrunSlideAnimEnd(false, PlayerCannotStand(ply))
	end

	if rolling and not sliding and rollEndTime > lastRollToken and not IsValid(BodyAnim) then
		local ang = ply:GetSafetyRollAng()
		BeatrunRollAnimStart(ang == angle_zero, (ply._BRZRollVariant or 1) >= 2)
	end
end)

-- Network triggers: the server tells the owning client when to (re)start or end the animation.
-- This is the "server side" half of the animation system, so multiplayer never depends on prediction alone.
net.Receive("Beatrun_ZC_SlideStart", function()
	BeatrunSlideAnimStart()
end)

net.Receive("Beatrun_ZC_SlideEnd", function()
	local blocked = net.ReadBool()
	local slippery = net.ReadBool()
	local fellOff = net.ReadBool()
	BeatrunSlideAnimEnd(slippery, blocked, fellOff)
end)

net.Receive("Beatrun_ZC_RollStart", function()
	local isLandInPlace = net.ReadBool()
	local bigFall = net.ReadBool()
	BeatrunRollAnimStart(isLandInPlace, bigFall)
end)

if game.SinglePlayer() then
	net.Receive("sliding_spfix", function()
		BeatrunSlideAnimStart()
	end)

	net.Receive("sliding_spend", function()
		local blocked = net.ReadBool()
		local slippery = net.ReadBool()
		local fellOff = net.ReadBool()
		BeatrunSlideAnimEnd(slippery, blocked, fellOff)
	end)

	net.Receive("RollAnimSP", function()
		local isLandInPlace = net.ReadBool()
		local bigFall = net.ReadBool()
		BeatrunRollAnimStart(isLandInPlace, bigFall)
	end)
end
