-- Slide & Safety Roll animation controller.
-- Starts BodyAnim ONLY when a slide or roll begins and removes it cleanly when finished.

local cvAnimSet = GetConVar("Beatrun_AnimSet")
local cvRollHolster = GetConVar("Beatrun_ZCity_RollHolster")
local cvCamLock = GetConVar("Beatrun_TrickCamLockAng")

local function GetRigName()
	return (cvAnimSet and cvAnimSet:GetInt() == 1) and "old_climbanim" or "new_climbanim"
end

local slideState = "idle" -- "idle" | "sliding" | "ending"
local lastRollToken = 0
local lastRollAnimAt = 0
local lastTrickAnimAt = 0
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

-- kneeLanding = the Mirror's Edge "land" pose (drop onto one knee, no forward launch),
-- lowRoll     = the extra low/crouched roll used for very long drops
-- variant: 1 = knee landing ("land"), 2 = roll ("meroll"), 3 = low roll ("merollcrouch").
-- The number is decided on the server (BeatrunRollVariantForHeight) and sent over the network, so the
-- animation always matches the movement - it cannot flip between "land" and "meroll" on the same fall.
-- forced = the pose came from the server (Beatrun_ZC_RollStart / RollAnimSP), so it is the truth and it
-- may replace a pose the client guessed a moment ago.
function BeatrunRollAnimStart(variant, lowRollFlag, forced)
	local ply = LocalPlayer()
	if not IsValid(ply) or not BeatrunCanSlideOrRoll(ply) then return end

	-- old call style (kneeLanding, lowRoll) still works
	if type(variant) == "boolean" then
		variant = variant and 1 or (lowRollFlag and 3 or 2)
	end

	local kneeLanding = (variant == 1)
	local lowRoll = (variant == 3)

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

	-- Height decides the pose and only the pose (fixed table, 2.21.23):
	--   290 .. 350 -> "land" / "landgun"      (knee landing, like Beatrun)
	--   351 .. 449 -> nothing of ours, Z-City lands it
	--   450 .. 750 -> "meroll" / "merollgun"  (the one safety roll)
	--   above 750  -> no trick at all, Z-City takes the landing
	-- "merollcrouch" is kept only for the old bool call style.
	local animName
	local speed
	if kneeLanding then
		animName = holdingWeapon and "landgun" or "land"
		speed = 1.05
	elseif lowRoll then
		animName = holdingWeapon and "merollguncrouch" or "merollcrouch"
		speed = 0.95
	else
		animName = holdingWeapon and "merollgun" or "meroll"
		speed = 1.15
	end

	-- 2.21.11: a hard anti-double guard. A trick animation that starts less than 0.9 s after the
	-- previous one is always the same landing being triggered twice (prediction + the server trigger,
	-- a re-armed fall, or the crouch that follows the roll) - a real roll lasts at least that long.
	local now = CurTime()
	local token = ply:GetSafetyRollTime() or 0

	-- 2.21.23: "same trick" is identified by the roll token (the server writes a new
	-- SafetyRollTime for every landing), not by the pose name. A repeating pose name used to make the
	-- addon either replay the animation from the top (two animations for one landing) or swallow a
	-- real one; the token says exactly which landing this pose belongs to.
	if IsValid(BodyAnim) and BodyAnimString == animName and lastRollToken == token then
		return
	end

	-- A second start for a landing we already animated, or a start right after another pose: ignore.
	-- A pose the server sent is the answer for its own token, so the time guards do not apply to it.
	if IsValid(BodyAnim) and BodyAnimString == animName and (now - lastRollAnimAt) < 0.5 then
		return
	end
	if not forced and now - lastTrickAnimAt < 0.45 and lastRollToken == token then
		return
	end
	if not forced and now - lastRollAnimAt < 0.15 then
		return
	end
	lastRollAnimAt = now
	lastTrickAnimAt = now

	local cvDbg2 = GetConVar("Beatrun_RollDebugLog")
	if cvDbg2 and cvDbg2:GetBool() then
		print(string.format("[Beatrun Z-City] roll anim start: %s (variant %d) at %.2f",
			tostring(animName), variant, now))
	end

	slideState = "idle"
	slideHandled = false
	lastRollToken = token
	hook.Remove("Think", "BeatrunZCity_SlideAnimThink")

	local rollAng = ply:GetSafetyRollAng()
	local startAng = (rollAng and rollAng ~= angle_zero) and rollAng or ply:EyeAngles()

	-- Same camera setup as the slide (that is the view that feels right): the camera rides the
	-- animation's CameraJoint and the view stays yours, exactly like meslidestart/meslideloop.
	StartBodyAnim({
		AnimString = animName,
		animmodelstring = GetRigName(),
		camjoint = "CameraJoint",
		deleteonend = true,
		followplayer = true,
		lockang = not (cvCamLock and cvCamLock:GetInt() == 0),
		allowmove = true,
		BodyAnimSpeed = speed,
		StartAngle = startAng
	})

	-- 2.21.13: match the animation length to the trick length instead of a fixed speed. A 400 unit
	-- fall rolls for ~1.6 s while "meroll" is much shorter, so the pose used to end early (and any
	-- re-trigger looked like the animation playing a second time).
	if IsValid(BodyAnim) then
		local seqDur = BodyAnim:SequenceDuration()
		local want = ply._BRZRollSeconds or ((ply:GetSafetyRollTime() or 0) - CurTime())
		if seqDur and seqDur > 0.05 and want and want > 0.15 then
			BodyAnimSpeed = math.Clamp(seqDur / want, 0.6, 2)
		end
	end
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
		-- 2.21.19: never guess "roll" when we have no number for this fall - the gentle knee landing is
		-- the safe answer, and the server message corrects it upwards if the fall really was a big one.
		local variant = ply._BRZRollVariant or 1
		BeatrunRollAnimStart(variant)
	end
end)

-- 2.21.21: the pose the server decided for this landing. If the client cannot play it on the exact frame
-- the message arrives (a Z-City ragdoll/stun state is one frame old, the player model is being swapped),
-- try again a few times instead of dropping it - a dropped pose is what left the camera on a ragdoll.
local function QueueRollAnim(variant, forced, attempt)
	attempt = attempt or 0
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	if not BeatrunCanSlideOrRoll(ply) then
		if attempt < 4 then
			timer.Simple(0.06, function() QueueRollAnim(variant, forced, attempt + 1) end)
		end
		return
	end

	ply._BRZRollVariant = variant
	BeatrunRollAnimStart(variant, nil, forced)
end

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
	local variant = net.ReadInt(8)
	QueueRollAnim(variant, true)
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
		local variant = net.ReadInt(8)
		QueueRollAnim(variant, true)
	end)
end
