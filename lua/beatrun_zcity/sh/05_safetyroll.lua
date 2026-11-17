-- Beatrun fall safety roll as a standalone addon for Z-City.
-- Never replaces Z-City hooks; returns true in OnPlayerHitGround only when a timed roll succeeds.

local cvRollEnabled = GetConVar("Beatrun_ZCity_RollEnabled")
local cvRollSpeedLoss = GetConVar("Beatrun_RollSpeedLoss")
local cvRollNoDamage = GetConVar("Beatrun_RollNoDamage")
local cvRollHolster = GetConVar("Beatrun_ZCity_RollHolster")
local cvRollFallReduction = GetConVar("Beatrun_ZCity_RollFallReduction")
local cvMaxSafeRollSpeed = GetConVar("Beatrun_ZCity_MaxSafeRollSpeed")
local cvRollMinSpeed = GetConVar("Beatrun_ZCity_RollMinSpeed")
-- 2.21.23: the landing table is fixed in code (290 / 350 / 750), so these three convars are no longer
-- read anywhere. They stay registered only so an old config or an old menu cannot error on them.
local cvRollMinHeight = GetConVar("Beatrun_ZCity_RollMinHeight")
local cvRollBigHeight = GetConVar("Beatrun_ZCity_RollBigHeight")
local cvRollMaxHeight = GetConVar("Beatrun_ZCity_RollMaxHeight")
local cvRollDebugLog = GetConVar("Beatrun_RollDebugLog")

local rollTrace = {}

local HANDS_CLASSES = { "weapon_hands_sh", "weapon_hands", "gmod_hands" }

local function FindHandsWeapon(ply)
	if not IsValid(ply) or not ply.GetWeapon then return nil end
	for _, cls in ipairs(HANDS_CLASSES) do
		local w = ply:GetWeapon(cls)
		if IsValid(w) then return w end
	end
	return nil
end

local function IsHandsClass(cls)
	return cls == "weapon_hands_sh" or cls == "weapon_hands" or cls == "gmod_hands"
end

-- Holsters any equipped weapon to bare hands (weapon_hands_sh in Z-City) during a safety roll,
-- matching Z-City's own TauntHolsterWeapons pattern in movement/sh_inertia.lua.
local function HolsterWeaponForTrick(ply, cmd)
	if cvRollHolster and not cvRollHolster:GetBool() then return end
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end

	local active = ply:GetActiveWeapon()
	local activeClass = IsValid(active) and active:GetClass() or nil
	if activeClass and IsHandsClass(activeClass) then return end

	local hands = FindHandsWeapon(ply)
	if IsValid(hands) then
		if cmd and isfunction(cmd.SelectWeapon) then
			cmd:SelectWeapon(hands)
		end
		if SERVER then
			ply:SelectWeapon(hands:GetClass())
			if ply:GetActiveWeapon() ~= hands and isfunction(ply.SetActiveWeapon) then
				ply:SetActiveWeapon(hands)
			end
		elseif CLIENT and ply == LocalPlayer() and input and isfunction(input.SelectWeapon) then
			pcall(input.SelectWeapon, hands)
		end
	elseif SERVER and IsValid(active) and isfunction(ply.SetActiveWeapon) then
		ply:SetActiveWeapon(NULL)
	end
end

-- Ledge climb (sh/06_climb.lua) stows weapons with exactly the same rule
BeatrunZCityHolsterForTrick = HolsterWeaponForTrick

BeatrunAddOrderedHook("SetupMove", "zz_BeatrunZCity_SafetyRoll", function(ply, mv, cmd)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	if not cvRollEnabled:GetBool() or not BeatrunCanSlideOrRoll(ply) then
		if ply:GetSafetyRollTime() > 0 or ply:GetSafetyRollKeyTime() > 0 then
			ply:SetSafetyRollTime(0)
			ply:SetSafetyRollKeyTime(0)
			if CLIENT and IsFirstTimePredicted() and BeatrunRollAnimAbort then
				BeatrunRollAnimAbort()
			end
		end
		ply._BeatrunWasOnGround = ply:OnGround()
		ply._BeatrunPrevRollDuck = mv:KeyDown(IN_DUCK)
		ply._BeatrunPrevRollSprint = mv:KeyDown(IN_SPEED)
		return
	end

	local CT = CurTime()
	local onground = ply:OnGround()
	local wasOnGround = ply._BeatrunWasOnGround
	ply._BeatrunWasOnGround = onground

	local duckNow = mv:KeyDown(IN_DUCK)
	local sprintNow = mv:KeyDown(IN_SPEED)
	local duckPressed = duckNow and not ply._BeatrunPrevRollDuck
	ply._BeatrunPrevRollDuck = duckNow
	ply._BeatrunPrevRollSprint = sprintNow

	local velZ = mv:GetVelocity().z

	-- 2.21.11: Ctrl only. Shift used to arm the roll as well, and because Shift is also part of
	-- Z-City's own sprint/slide input it produced a second animation right after the roll.
	local rollPressed = duckPressed

	-- Fall height tracking (added in 2.21.7). The roll is no longer decided by the impact speed alone:
	-- the height actually dropped is measured from the highest point of the fall, so a big fall plays the
	-- hard landing / crouched roll and a small hop never turns into a trick.
	local org = mv:GetOrigin()
	if onground then
		if not wasOnGround then
			local peak = ply._BRZFallPeakZ
			if peak and peak - org.z > 0 then
				ply._BRZLastFallHeight = math.max(0, peak - org.z)
				if cvRollDebugLog and cvRollDebugLog:GetBool() then
					print(string.format("[Beatrun Z-City] fall height %.0f units", ply._BRZLastFallHeight))
				end
			else
				ply._BRZLastFallHeight = 0
			end
			ply._BRZWasClimbHeave = nil

			-- Ctrl was held during the fall -> the block Z-City was already braced for keeps running
			-- through the impact frames, not only until the feet touch.
			if ply._BRZBraced and (ply._BRZBracedUntil or 0) >= CT - 0.6 then
				ply._BRZBracedUntil = math.max(ply._BRZBracedUntil or 0, CT + 0.6)
			else
				ply._BRZBraced = false
			end
		end
		ply._BRZFallPeakZ = org.z
		if CT > (ply._BRZBracedUntil or 0) then ply._BRZBraced = false end
	else
		-- a new fall starts: the height of the previous landing must not leak into it
		if wasOnGround then
			ply._BRZLastFallHeight = nil
			ply._BRZFallTappedAt = nil   -- 2.21.27: a tap belongs to exactly one fall
		end

		local peak = ply._BRZFallPeakZ
		if not peak or org.z > peak then
			ply._BRZFallPeakZ = org.z
		end
	end

	-- Arm the safety roll without stripping IN_DUCK (avoids Z-City AntiCrouchSpam penalty).
	-- 2.21.9: ONE tap in the air is enough. The arm sticks for the whole fall, so Ctrl never has to be
	-- held - holding it also made Z-City start its own crouch-slide right after the roll, which looked
	-- like the animation playing twice.
	local holdingBrace = duckNow
	local airborne = not onground and not ply:GetSliding()
	local rollBlocked = CT < (ply._BRZRollStartGuard or 0) or CT < ply:GetSafetyRollTime()

	if airborne and not rollBlocked and (rollPressed or holdingBrace) then
		ply._BRZFallArmed = true
		-- 2.21.27: the tap is remembered as a plain field with a timestamp, on the realm that decides
		-- (the server). The landing gate used to read the replicated 0.5 s window instead, and that window
		-- can be stale on the landing tick (the arm is dropped on the first grounded frame, and a command
		-- without IN_DUCK stops refreshing it) - which is what turned a perfectly good tap into
		-- "Ctrl was not tapped (or the tap was too early)".
		ply._BRZFallTappedAt = CT
	end

	-- Armed for this fall: keep the roll armed until the ground arrives and brace the impact ahead of
	-- time, so Z-City's fallStun/ragdoll is already blocked when the feet touch.
	if airborne and ply._BRZFallArmed and not rollBlocked then
		ply:SetSafetyRollKeyTime(CT + 0.5)
		ply._BRZBraced = true
		ply._BRZBracedUntil = CT + 0.35
	end

	-- 2.21.27: the arm now survives the landing itself. Z-City's OnPlayerHitGround runs in the same tick
	-- as the last SetupMove, so dropping the arm here could erase the tap before the landing was even
	-- decided. It is cleared a quarter of a second after the ground was touched instead.
	if onground then
		ply._BRZGroundedAt = ply._BRZGroundedAt or CT
		if ply._BRZFallArmed and (CT - ply._BRZGroundedAt) > 0.25 then
			ply._BRZFallArmed = nil
			ply._BRZFallTappedAt = nil
		end
	else
		ply._BRZGroundedAt = nil
	end

	local isArming = CT < ply:GetSafetyRollKeyTime()
	if CT >= ply:GetSafetyRollTime() then
		ply._BRZRollSlowFactor = nil
		ply._BRZRollSeconds = nil
		ply._BRZRollVariant = nil
		ply._BRZRollDistance = nil
		ply._BRZRollMoved = nil
		if ply.GetRollLand and ply:GetRollLand() then ply:SetRollLand(false) end
	end

	if onground and not isArming and CT >= ply:GetSafetyRollTime() then
		local vel = mv:GetVelocity()
		vel.z = 0
		ply._BeatrunLastGroundSpeed = vel:Length()
	end

	if CT < ply:GetSafetyRollTime() then
		local ang = ply:GetSafetyRollAng()
		mv:AddKey(IN_DUCK)

		-- 2.21.17: an Angle object never compares equal to another one, so "is this the in-place knee
		-- landing?" has to come from its own replicated flag. It used to fall through to the roll branch
		-- and pushed the player towards world +X on every knee landing.
		local landInPlace = isfunction(ply.GetRollLand) and ply:GetRollLand() or false

		if not landInPlace then
			local vel = mv:GetVelocity()
			local downVel = math.min(0, vel.z)

			local mobility = BeatrunGetMobilityFactor(ply)
			local speedloss = cvRollSpeedLoss:GetBool() or ply:GetRollLoss()
			local rollSpeed

			if speedloss then
				rollSpeed = 250 * mobility
			else
				rollSpeed = math.Clamp(ply._BeatrunLastGroundSpeed or 250, 220, 380) * mobility
			end

			-- A roll that absorbed a big fall carries less speed forward
			if ply._BRZRollSlowFactor and CT < ply:GetSafetyRollTime() then
				rollSpeed = rollSpeed * ply._BRZRollSlowFactor
			end

			local dir = ang:Forward()
			dir.z = 0
			if dir:LengthSqr() > 0.001 then dir:Normalize() else dir = Vector(0, 0, 0) end

			-- 2.21.18: the roll carries the body itself instead of only asking for speed. Z-City's
			-- inertia (homigrad/movement/sh_inertia.lua) rebuilds the movement wish from its own inertia
			-- vector in a SetupMove that runs BEFORE ours, so a SetVelocity never survived a ducked
			-- landing and the roll stayed in place. Moving the origin inside SetupMove is exactly what
			-- the ledge climb already does and it works there, so the roll does the same, with a hull
			-- trace in front of it so a wall stops the roll instead of being rolled through.
			local dt = 0.015
			if engine and isfunction(engine.TickInterval) then
				dt = math.Clamp(engine.TickInterval(), 0.001, 0.1)
			end

			-- 2.21.28: how far the roll goes is a fixed budget for the whole animation, spent tick by tick
			-- while the pose plays (ply._BRZRollDistance is set once, when the trick is accepted). Before
			-- this the roll pushed the body at a constant 220-380 u/s for up to 1.7 s - 300 to 600 units -
			-- and then left that momentum inside Z-City's inertia, which is why the character kept flying
			-- forward after the animation had already ended.
			local budget = ply._BRZRollDistance
			local moved = ply._BRZRollMoved or 0
			local stepLen = rollSpeed * dt
			if budget then
				local remaining = math.max(0, budget - moved)
				if remaining < stepLen then stepLen = remaining end
			end
			local rollEndsThisTick = (CT + dt) >= (ply:GetSafetyRollTime() or 0)

			if dir:LengthSqr() > 0.001 and stepLen > 0.0001 then
				local step = dir * stepLen
				local origin = mv:GetOrigin()

				local mins, maxs
				if isfunction(ply.OBBMins) and isfunction(ply.OBBMaxs) then
					mins, maxs = ply:OBBMins(), ply:OBBMaxs()
				else
					mins, maxs = ply:GetHull()
				end

				-- traced 2 units above the feet so the sweep never starts inside the floor
				rollTrace.start = origin + Vector(0, 0, 2)
				rollTrace.endpos = rollTrace.start + step
				rollTrace.mins = mins
				rollTrace.maxs = maxs
				rollTrace.filter = ply
				rollTrace.mask = MASK_PLAYERSOLID
				rollTrace.collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT

				local tr = util.TraceHull(rollTrace)
				if tr.Hit then
					step = step * math.Clamp(tr.Fraction or 0, 0, 1)
				end

				ply._BRZRollMoved = moved + step:Length()

				if step:LengthSqr() > 0.000001 then
					mv:SetOrigin(origin + step)
				end
			end

			-- The forward speed lives in the origin now, so the engine must not add it a second time:
			-- velocity stays vertical only and the wish speeds stay empty.
			mv:SetVelocity(Vector(0, 0, downVel))
			mv:SetForwardSpeed(0)
			mv:SetSideSpeed(0)
			mv:SetMaxSpeed(math.max(100, rollSpeed))
			mv:SetMaxClientSpeed(math.max(100, rollSpeed))
			ply:SetMaxSpeed(math.max(100, rollSpeed))

			-- 2.21.28: Z-City keeps its own momentum vector and would carry the body on with the full roll
			-- speed after the pose ended - the long "throw". On the last tick of the animation the momentum
			-- is dropped to a short step-out instead, so everything the player gains from a roll happens
			-- while the roll is visible.
			local budgetSpent = stepLen < 0.0001
			local carry = (rollEndsThisTick or budgetSpent) and 60 or rollSpeed
			ply.MovementInertia = dir * carry
			ply.CurrentSpeed = carry
		else
			-- knee landing: you drop onto the knee and stop dead, exactly like Beatrun's "land"
			mv:SetSideSpeed(0)
			mv:SetForwardSpeed(0)
			local vel = mv:GetVelocity()
			vel.x = 0
			vel.y = 0
			mv:SetVelocity(vel)
			ply.MovementInertia = mv:GetVelocity()
			ply.CurrentSpeed = 0
		end
	end
end, "HOOK_LOW")

-- ---------------------------------------------------------------------------
-- One place that maps a fall height to a trick, shared by the client and the server so the animation
-- can never disagree with the movement. The table is FIXED (2.21.26):
--   0 = no trick, plain Z-City landing     below 290
--   1 = knee landing   "land" / "landgun"  290 .. 350, inclusive
--   2 = the one roll   "meroll" / ...      351 .. 750
--   0 = no trick, Z-City fall injuries     above 750 - nothing saves that fall
--
-- It is deliberately NOT read from convars any more. A saved config, an older copy of the addon or an
-- old menu could leave RollMinHeight / RollBigHeight sitting at values from another version (your log
-- showed 70 / 260), and then the same fall played a different animation depending on the machine - the
-- exact complaint this addon had to stop. Height alone decides now, on every install, always.
local KNEE_HEIGHT, KNEE_MAX, MAX_HEIGHT = 290, 350, 750

-- Does a trick exist for this height at all? Two bands, with a deliberate gap between them.
local function HeightHasTrick(height)
	height = height or 0
	return height >= KNEE_HEIGHT and height <= MAX_HEIGHT
end

function BeatrunRollVariantForHeight(fallHeight)
	fallHeight = math.max(0, fallHeight or 0)

	local variant = 0
	if fallHeight > MAX_HEIGHT then
		variant = 0                        -- too far for a trick: Z-City owns that landing completely
	elseif fallHeight > KNEE_MAX then
		variant = 2                        -- everything above the knee landing is the roll
	elseif fallHeight >= KNEE_HEIGHT then
		variant = 1
	end

	return variant, variant == 2, false, KNEE_MAX
end

-- Fall height measured the same way everywhere (peak of the fall / last measured landing)
local function MeasuredFallHeight(ply)
	local h = math.max(0, (ply._BRZFallPeakZ or ply:GetPos().z) - ply:GetPos().z)
	if ply._BRZLastFallHeight and ply._BRZLastFallHeight > h then h = ply._BRZLastFallHeight end
	return h
end

-- 2.21.18: a fall above RollMaxHeight is beyond what a trick can save. Nothing of ours may touch that
-- landing - Z-City hands out its own injuries (broken legs, ragdoll), exactly like it does without us.
local function TrickCanSave(height)
	return HeightHasTrick(height)
end

-- 2.21.21: the one place that prints what happened on a landing. Always on, one line, prefixed with the
-- version, and remembered on the player so a debug panel can repeat it.
local ADDON_VERSION = "2.21.32"

function ReportLanding(ply, what)
	if IsValid(ply) and ply.IsPlayer and ply:IsPlayer() then
		ply._BRZLastLanding = what
	end
	print(string.format("[Beatrun Z-City %s] landing: %s", ADDON_VERSION, what))
end

-- The trick has the landing: the ragdoll Z-City fires on a hard landing must not run on top of it.
-- _BeatrunRollHandledUntil is one frame (Z-City's own hook fires right after ours), GetSafetyRollTime
-- covers the whole trick - that is exactly the window where the ragdoll used to eat the animation.
local function TrickOwnsLanding(ply)
	if not IsValid(ply) or not ply.IsPlayer then return false end
	local CT = CurTime()
	if CT <= (ply._BeatrunRollHandledUntil or 0) then return true end
	if ply.GetSafetyRollTime and CT < (ply:GetSafetyRollTime() or 0) then return true end

	-- The arm is set while falling, so it is already there when Z-City's own fallStun hook gets to run
	-- before ours: this landing is the one the trick is for, so its ragdoll must not fire either.
	if ply._BRZFallArmed then
		local h = MeasuredFallHeight(ply)
		if h >= KNEE_HEIGHT and TrickCanSave(h) then return true end
	end
	return false
end

-- Runs BEFORE Z-City's fallStun and returns true only when a timed roll mitigates the impact
-- 2.21.21: every early return leaves a short reason behind, so the one-line landing report says what
-- actually happened instead of a guess.
local function Decline(ply, why)
	if IsValid(ply) and ply.IsPlayer and ply:IsPlayer() then ply._BRZRollDecline = why end
end

local function TrySafetyRoll(ply, water, floater, speed)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	-- 2.21.26: THE DECISION IS THE SERVER'S ALONE. This function also ran on the client (prediction plus
	-- local landing sounds), and it wrote its own SafetyRollTime with the CLIENT clock. When the server's
	-- authoritative value arrived a moment later the number changed, the client read that as a fresh
	-- landing and replayed the pose - exactly the "knee landing plays twice" in the log (start at 133.75,
	-- then again at 134.50 as soon as the pose had ended). The client only plays what the server sends
	-- now, and the server already emits the landing sounds.
	if CLIENT then return end

	if water or floater then Decline(ply, "landed in water / on a floater") return end
	if not cvRollEnabled:GetBool() then Decline(ply, "the trick is disabled in the settings") return end
	if not BeatrunCanSlideOrRoll(ply) then Decline(ply, "you are not in a rollable state (ragdoll, vehicle, broken legs)") return end

	if IsValid(ply) and ply.IsPlayer and ply:IsPlayer() then ply._BRZRollDecline = nil end

	local CT = CurTime()
	local maxSafeSpeed = cvMaxSafeRollSpeed:GetFloat()

	-- 2.21.23: the trick owns the player for its whole duration. Without this a second ground touch
	-- during the roll (the body bounces once, or the roll steps over a small edge) started the same
	-- animation again from the top - that was the "two animations" you saw in the log.
	if CT < (ply:GetSafetyRollTime() or 0) then Decline(ply, "the trick is still playing") return end

	-- 2.21.27: one tap (or held Ctrl) during the fall is enough, and it is read from the tap we recorded
	-- ourselves instead of the replicated key window, so the landing tick cannot invalidate it.
	local tappedAt = ply._BRZFallTappedAt
	if not (ply._BRZFallArmed or (tappedAt and (CT - tappedAt) <= 4)) then
		Decline(ply, "Ctrl was not tapped in the air")
		if cvRollDebugLog and cvRollDebugLog:GetBool() then
			print(string.format("[Beatrun Z-City] no tap: arm=%s tapped=%s keyWindow=%.2f now=%.2f",
				tostring(ply._BRZFallArmed), tostring(tappedAt), ply:GetSafetyRollKeyTime() or 0, CT))
		end
		return
	end

	-- The arm belongs to exactly one landing, and a roll that just started must not be re-triggered
	-- by the next physics frame (that was the other half of the "animation plays twice" bug).
	ply._BRZFallArmed = nil
	if CT < (ply._BRZRollStartGuard or 0) then Decline(ply, "the previous trick had just started") return end

	ply._BRZRollStartGuard = CT + 0.45

	-- The hard cap used to be 820: any fall faster than that skipped the roll entirely, so the ragdoll
	-- and the broken legs came through even though the player pressed in time. Now the timing is the
	-- only condition; a very fast fall is still protected.
	local hardCap = math.max(maxSafeSpeed, 3000)
	if speed < cvRollMinSpeed:GetFloat() then Decline(ply, string.format("the impact was only %.0f (min %.0f)", speed, cvRollMinSpeed:GetFloat())) return end
	if speed > hardCap then Decline(ply, string.format("the impact %.0f is beyond the cap", speed)) return end

	-- Height gate (2.21.7): the roll is the answer to a real fall, not to a step down or a normal jump.
	local fallHeight = MeasuredFallHeight(ply)

	if fallHeight > MAX_HEIGHT then
		Decline(ply, string.format("a %.0f unit fall is above %d - no trick can save it", fallHeight, MAX_HEIGHT))
		if cvRollDebugLog and cvRollDebugLog:GetBool() then
			print(string.format("[Beatrun Z-City] fall %.0f units is above %d - no trick, Z-City takes the landing", fallHeight, MAX_HEIGHT))
		end
		return
	end

	if fallHeight < KNEE_HEIGHT then
		Decline(ply, string.format("a %.0f unit fall is below %d", fallHeight, KNEE_HEIGHT))
		if cvRollDebugLog and cvRollDebugLog:GetBool() then
			print(string.format("[Beatrun Z-City] fall %.0f units / speed %.0f - too low for a roll", fallHeight, speed))
		end
		return
	end

	-- Big fall = the heavy variant: longer roll, crouched pose, wider protection window, more stamina.
	-- Everything above the knee landing is the roll, so this is also the knee/roll boundary.
	local bigFall = fallHeight > KNEE_MAX

	if cvRollDebugLog and cvRollDebugLog:GetBool() then
		print(string.format("[Beatrun Z-City] landing speed %.0f, fall height %.0f (%s) - roll accepted",
			speed, fallHeight, bigFall and "big" or "small"))
	end

	local tr = util.TraceLine({
		start = ply:GetPos(),
		endpos = ply:GetPos() - Vector(0, 0, 150),
		filter = ply
	})
	if tr.HitNormal and tr.HitNormal:Angle().x > 314 then return end

	local protectTime = math.Clamp(1.7 + fallHeight / 170, 2.5, 4.5)

	ply._BeatrunRollHandledUntil = CT + 0.16
	ply:SetSafetyRollKeyTime(0)
	ply._BRZRollProtectUntil = CT + protectTime
	ply._BRZRollHeight = fallHeight

	-- 2.21.23: this fall has just been paid for. Forgetting the height here is what makes a second
	-- ground touch of the same landing harmless: the old code kept re-measuring the same 300-400 units
	-- and started the trick again (the "two animations" in the log).
	ply._BRZLastFallHeight = nil
	ply._BRZFallPeakZ = ply:GetPos().z
	ply._BRZFallTappedAt = nil

	local mobility = BeatrunGetMobilityFactor(ply)
	ply:SetRollLoss(mobility < 0.75)

	ParkourEvent("roll", ply)

	local ang = ply:EyeAngles()
	ang.x = 0
	ang.z = 0

	-- 2.21.14: the variant comes from the shared helper, so client and server always agree on it.
	local variant, useRoll, lowRoll, bigH = BeatrunRollVariantForHeight(fallHeight)

	-- 2.21.19: height only. No "standing still" downgrade and no always-roll override any more - the
	-- same fall always has to give the same landing, that was the whole point of 2.21.14.
	ply._BRZRollVariant = variant

	if cvRollDebugLog and cvRollDebugLog:GetBool() then
		local names = { [0] = "nothing", [1] = "land", [2] = "meroll", [3] = "merollcrouch" }
		print(string.format("[Beatrun Z-City] fall %.0f -> variant %d (%s)  [nothing < %d, knees %d..%d, roll %d..%d, nothing > %d]",
			fallHeight, variant, names[variant] or "?", KNEE_HEIGHT, KNEE_HEIGHT, KNEE_MAX,
			KNEE_MAX + 1, MAX_HEIGHT, MAX_HEIGHT))
	end

	-- How long the trick owns the player. 2.21.28: the roll is no longer stretched to 1.7 s - the pose is
	-- played at (almost) its own speed and the ground it covers is spread over this window, so a big fall
	-- does not turn into a slow-motion roll that crawls forward.
	local rollSeconds = math.Clamp(0.62 + fallHeight / 1100, 0.75, 1.05)
	ply._BRZRollSeconds = rollSeconds

	-- 2.21.28: the whole forward travel of a roll, in units, decided once. Beatrun's roll is a recovery,
	-- not a launch: about one and a half body lengths, a bit more from a bigger drop. The movement code
	-- spends exactly this much during the animation and nothing afterwards.
	ply._BRZRollDistance = math.Clamp(110 + fallHeight * 0.12, 130, 200)
	ply._BRZRollMoved = 0

	-- 2.21.21: ONE line per landing, always printed (not behind the debug convar). It names the pose and
	-- the movement, so the console alone tells which branch ran - no more guessing from a screenshot.
	-- 2.21.28: a roll line also carries the ground it will cover, so the log shows the travel directly.
	local landingText
	if variant == 2 then
		landingText = string.format("ROLL - meroll, carries forward (fall %.0f, impact %.0f, %.0fu in %.2fs)",
			fallHeight, speed, ply._BRZRollDistance, rollSeconds)
	elseif variant == 1 then
		landingText = string.format("KNEE landing - land, stays in place (fall %.0f, impact %.0f)", fallHeight, speed)
	else
		landingText = string.format("no trick (fall %.0f, impact %.0f)", fallHeight, speed)
	end
	ReportLanding(ply, landingText)

	ply:SetSafetyRollAng(ang)
	if isfunction(ply.SetRollLand) then ply:SetRollLand(not useRoll) end

	if not useRoll then
		-- Knee landing (Mirror's Edge "land" pose, like Beatrun's in-place landing): you drop onto one
		-- knee, you do not launch forward. You still face where you were looking.
		ply:SetSafetyRollTime(CT + math.Clamp(rollSeconds, 0.6, 0.85))
		ply._BRZRollSlowFactor = nil
	else
		ply:SetSafetyRollTime(CT + rollSeconds)

		-- The heavier the fall, the less of it is turned into a forward sprint - you absorb, you don't launch.
		ply._BRZRollSlowFactor = math.Clamp(1 - (fallHeight - KNEE_MAX) / 2600, 0.62, 1)
	end

	local isLandInPlace = not useRoll

	-- Immediately stow any held firearm/melee/item to bare hands when entering the safety roll
	HolsterWeaponForTrick(ply)

	if SERVER then
		BeatrunConsumeStamina(ply, math.Clamp(speed / 38 + fallHeight / 55, 8, 34))
		if not isLandInPlace then
			timer.Simple(0.15, function()
				if not IsValid(ply) or IsValid(ply.FakeRagdoll) then return end
				ply:EmitSound("Cloth.Roll")
				ply:EmitSound("Cloth.BodyRoll")
				ply:EmitSound("Cloth.BodyRollSwish")
			end)
			ply:EmitSound("Cloth.RollLand")
			ply:EmitSound("Cloth.BodyRoll")
			ply:EmitSound("Cloth.RollCloth")
		else
			ply:EmitSound("Cloth.FallShortMedium")
			ply:EmitSound("Land.Concrete")
		end
	elseif CLIENT and (IsFirstTimePredicted() or game.SinglePlayer()) then
		ply:EmitSound("Cloth.FallShortMedium")
		ply:EmitSound("Cloth.MovementRun")
		ply:EmitSound("Land.Concrete")
		timer.Simple(0.3, function()
			if IsValid(ply) then
				ply:EmitSound("Cloth.MovementWalk")
			end
		end)
	end

	-- 2.21.14: the animation is driven by the authoritative decision only. Client prediction used to
	-- start it as well, and when the client and the server measured the fall height slightly
	-- differently the same jump could show "land" one time and "meroll" the next - the so called
	-- "roll works at 350, then at 700" flip-flop. Now exactly one trigger exists, and it carries the
	-- variant number itself.
	if SERVER then
		if game.SinglePlayer() then
			net.Start("RollAnimSP")
				net.WriteInt(variant, 8)
			net.Send(ply)
		else
			net.Start("Beatrun_ZC_RollStart")
				net.WriteInt(variant, 8)
			net.Send(ply)
		end
	end

	-- Prevent Z-City's fallStun ragdoll on successful timed roll
	return true
end

BeatrunAddOrderedHook("OnPlayerHitGround", "!BeatrunZCity_SafetyRoll", TrySafetyRoll, "HOOK_HIGH")

-- Keep hands bare for the full duration of the safety roll so a weapon cannot be drawn or fired mid-roll
BeatrunAddOrderedHook("StartCommand", "zz_BeatrunZCity_RollHolster", function(ply, cmd)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if cvRollHolster and not cvRollHolster:GetBool() then return end
	if not BeatrunCanSlideOrRoll(ply) then return end

	if ply.GetSafetyRollTime and CurTime() < ply:GetSafetyRollTime() then
		HolsterWeaponForTrick(ply, cmd)
		cmd:RemoveKey(IN_ATTACK)
		cmd:RemoveKey(IN_ATTACK2)
	end
end, "HOOK_LOW")

-- Z-City's own landing hook, wrapped. Whichever hook the engine runs first, the roll is decided first:
-- accepted -> Z-City's fallStun (and the ragdoll it fires through hg.LightStunPlayer) never runs;
-- not accepted -> Z-City keeps its landing exactly as it was.
local FallStunOriginal

local function FallStunWrapper(ply, inwater, onfloater, speed)
	-- 2.21.13: the roll hooks above already accepted this very landing. Z-City's fallStun would then
	-- run its own landing/stun on top of the roll - that is the second animation you see after a
	-- successful roll, because this hook fires again for the same impact.
	if IsValid(ply) and ply.IsPlayer and ply:IsPlayer() then
		local CT = CurTime()
		local rollEnd = (isfunction(ply.GetSafetyRollTime) and ply:GetSafetyRollTime()) or 0
		-- 2.21.21: "armed" must NOT count as blocked. An arm only means Ctrl was tapped during the fall;
		-- the landing itself is still undecided. Treating it as handled returned true here without ever
		-- calling TrySafetyRoll, so when this hook happened to sit before ours the whole trick silently
		-- disappeared - no pose, no variant, no message - and no change in the decision code could show.
		-- The ragdoll of an armed fall is kept away by the hg.LightStunPlayer guard below instead.
		local blocked = CT <= (ply._BeatrunRollHandledUntil or 0)   -- this landing was taken by the roll
			or CT < rollEnd                                         -- the roll is still playing

		if blocked and not TrickCanSave(MeasuredFallHeight(ply)) then
			-- 2.21.18: a fall this big is not ours. Drop the arm and let Z-City run its own landing.
			ply._BRZFallArmed = nil
			ply._BeatrunRollHandledUntil = nil
			ply._BRZRollProtectUntil = nil
			if isfunction(ply.SetSafetyRollTime) then ply:SetSafetyRollTime(0) end
			blocked = false

			if cvRollDebugLog and cvRollDebugLog:GetBool() then
				print("[Beatrun Z-City] no trick exists for this fall height - Z-City takes this landing")
			end
		end

		if blocked then
			if cvRollDebugLog and cvRollDebugLog:GetBool() then
				print("[Beatrun Z-City] Z-City fallStun blocked - the roll owns this landing")
			end
			return true
		end
	end

	local ok, consumed = pcall(TrySafetyRoll, ply, inwater, onfloater, speed)
	if ok and consumed then return true end

	-- 2.21.21: the trick did not take this landing. Say why in one line - "Ctrl was never tapped in the
	-- air" is by far the most common reason a fall that should be a knee landing ends up as Z-City's own
	-- ragdoll (which looks exactly like a roll).
	local protectedWindow = IsValid(ply) and ply.IsPlayer and ply:IsPlayer()
		and ply._BRZRollProtectUntil and ply._BRZRollProtectUntil > CurTime()

	if IsValid(ply) and ply.IsPlayer and ply:IsPlayer() and not TrickOwnsLanding(ply) and not protectedWindow then
		local h = MeasuredFallHeight(ply)
		if h >= KNEE_HEIGHT - 20 and h >= 100 then
			ReportLanding(ply, string.format("fall %.0f, impact %.0f - NO trick: %s; Z-City lands you",
				h, speed, ply._BRZRollDecline or "the trick did not take this landing"))
		end
	end

	if FallStunOriginal then return FallStunOriginal(ply, inwater, onfloater, speed) end
end

local function InstallFallStunGuard()
	if not hook.GetTable then return false end
	local tables = hook.GetTable()
	if not istable(tables) then return false end
	local list = tables["OnPlayerHitGround"]
	if not istable(list) or not list.fallStun then return false end
	if list.fallStun == FallStunWrapper then return false end
	-- Somebody (the gamemode loading late, another addon reloading it) put its own hook back under the
	-- same name: take the fresh original and wrap it again.
	FallStunOriginal = list.fallStun
	hook.Add("OnPlayerHitGround", "fallStun", FallStunWrapper)
	return true
end

-- 2.21.21: the real reason a 300-unit fall could still look like a roll. Z-City's fallStun ends in
-- hg.LightStunPlayer(ply, 2), and that function does hg.Fake(ply, nil, true) - its fake ragdoll, which
-- looks exactly like a tumble/roll. If Z-City's OnPlayerHitGround hook happens to sit on top of our
-- wrapper (it registers late, or gets re-added), that ragdoll runs even though we already played the
-- knee landing - so the body rolls, the rig animation disappears mid-air and nothing we change in the
-- pose matters. Guarding the function itself closes that hole no matter who owns the hook.
local LightStunOriginal

local function LightStunWrapper(ply, time)
	if TrickOwnsLanding(ply) then
		if cvRollDebugLog and cvRollDebugLog:GetBool() then
			print("[Beatrun Z-City] Z-City light stun (fake ragdoll) blocked - the trick owns this landing")
		end
		return
	end
	if LightStunOriginal then return LightStunOriginal(ply, time) end
end

-- 2.21.22: one layer deeper. Every stun path in Z-City ends in hg.Fake, and hg.Fake is what actually
-- creates the fake ragdoll that tumbles the body. While our trick owns the landing the ragdoll must not
-- exist at all - whoever asks for it (fallStun, a collide, the organism, another addon).
local FakeOriginal

local function FakeWrapper(ply, ...)
	if TrickOwnsLanding(ply) then
		if cvRollDebugLog and cvRollDebugLog:GetBool() then
			print("[Beatrun Z-City] Z-City fake ragdoll (hg.Fake) blocked - the trick owns this landing")
		end
		return
	end
	if FakeOriginal then return FakeOriginal(ply, ...) end
end

local function InstallLightStunGuard()
	local changed = false

	if hg and isfunction(hg.LightStunPlayer) and hg.LightStunPlayer ~= LightStunWrapper then
		LightStunOriginal = hg.LightStunPlayer
		hg.LightStunPlayer = LightStunWrapper
		changed = true
	end

	if hg and isfunction(hg.Fake) and hg.Fake ~= FakeWrapper then
		FakeOriginal = hg.Fake
		hg.Fake = FakeWrapper
		changed = true
	end

	return changed
end

-- Both guards are re-checked once a second: whichever addon/gamemode registers last, the trick keeps
-- owning its own landing.
hook.Add("Think", "BeatrunZCity_StunGuardThink", function()
	if not SERVER then return end
	local now = CurTime()
	if now < (GUARD_NEXT_AT or 0) then return end
	GUARD_NEXT_AT = now + 1
	local a = InstallLightStunGuard()
	local b = InstallFallStunGuard()
	if cvRollDebugLog and cvRollDebugLog:GetBool() and (a or b) then
		print("[Beatrun Z-City] landing guards re-installed")
	end
end)

-- 2.21.7: actually install that guard. If Z-City's fallStun is registered before our roll hook it would
-- ragdoll the player on a >600 impact before the roll is ever asked about it - this closes that hole.
-- Retried a few times because the gamemode and other addons register their hooks at their own pace.
timer.Simple(0, InstallFallStunGuard)
timer.Simple(1, InstallFallStunGuard)
timer.Simple(5, InstallFallStunGuard)
hook.Add("InitPostEntity", "BeatrunZCity_FallStunGuard", InstallFallStunGuard)
hook.Add("OnReloaded", "BeatrunZCity_FallStunGuard", InstallFallStunGuard)

local cvSlideNoDamage = GetConVar("Beatrun_ZCity_SlideNoDamage")

local function Protected(ply)
	if ply._BRZRollProtectUntil and ply._BRZRollProtectUntil > CurTime() then return true end
	-- Pre-emptive brace (2.21.7): Ctrl was held during the fall, so the impact is already blocked.
	if ply._BRZBraced and ply._BRZBracedUntil and ply._BRZBracedUntil > CurTime() then return true end
	if cvSlideNoDamage and cvSlideNoDamage:GetBool() and ply:GetSliding() then return true end
	return false
end

hook.Add("PlayerFootstep", "BeatrunZCity_SilenceRoll", function(ply)
	if IsValid(ply) and ply:IsPlayer() and not IsValid(ply.FakeRagdoll) and CurTime() < ply:GetSafetyRollTime() then
		return true
	end
end)

hook.Add("HG_PlayerFootstep", "BeatrunZCity_SilenceRoll", function(ply)
	if IsValid(ply) and ply:IsPlayer() and not IsValid(ply.FakeRagdoll) and CurTime() < ply:GetSafetyRollTime() then
		return true
	end
end)

if SERVER then
	-- Whatever path Z-City takes, damage from the landing is dropped while the protection window is
	-- open: no health loss, no bleed, no broken legs from the impact.
	hook.Add("ScalePlayerDamage", "BeatrunZCity_RollNoDamage", function(ply, hitgroup, dmginfo)
		if not cvRollNoDamage or not cvRollNoDamage:GetBool() then return end
		if not Protected(ply) then return end

		local t = dmginfo:GetDamageType()
		if bit.band(t, DMG_FALL) ~= 0 then dmginfo:SetDamage(0) end
	end)

	hook.Add("EntityTakeDamage", "BeatrunZCity_RollNoDamage", function(ent, dmginfo)
		if not cvRollNoDamage or not cvRollNoDamage:GetBool() then return end
		if not IsValid(ent) or not ent:IsPlayer() then return end
		if not Protected(ent) then return end

		local t = dmginfo:GetDamageType()
		if bit.band(t, DMG_FALL) ~= 0 or bit.band(t, DMG_CRUSH) ~= 0 then
			dmginfo:SetDamage(0)
			return true
		end
	end)

	hook.Add("GetFallDamage", "BeatrunZCity_SafetyRoll", function(ply, speed)
		if not IsValid(ply) or not ply:IsPlayer() then return end
		if not cvRollEnabled:GetBool() or not BeatrunCanSlideOrRoll(ply) then return end

		local CT = CurTime()
		local maxSafeSpeed = cvMaxSafeRollSpeed:GetFloat()
		local rolled = (ply._BeatrunRollHandledUntil and ply._BeatrunRollHandledUntil >= CT)
			or (CT <= ply:GetSafetyRollKeyTime())

		-- Height gate has to be mirrored here: a drop that is too small for a roll keeps Z-City's own
		-- fall damage instead of being silently negated by a held Ctrl.
		local fallHeight = MeasuredFallHeight(ply)
		if fallHeight < KNEE_HEIGHT then return end
		if not TrickCanSave(fallHeight) then return end -- too big to be saved: Z-City damage stays

		local hardCap = math.max(maxSafeSpeed, 3000)
		if not rolled or speed > hardCap then
			return -- Let Z-City handle normal fall damage
		end

		if cvRollDebugLog and cvRollDebugLog:GetBool() then
			print(string.format("[Beatrun Z-City] fall damage call, speed %.0f - negated", speed))
		end

		if cvRollNoDamage and cvRollNoDamage:GetBool() then
			return 0 -- a successful timed roll negates the fall damage completely
		end

		if speed <= 650 then
			return 0
		end

		local reduction = math.Clamp(cvRollFallReduction:GetFloat(), 0, 1)
		local baseDmg = math.max(0, (speed - 580) * (100 / (1024 - 580)))
		return baseDmg * (1 - reduction)
	end)
end

-- 2.21.21: one line at start-up with the numbers this copy actually runs with. If a saved config or an
-- old server.cfg pins a stale value, it shows up here instead of silently turning every fall into a roll.
timer.Simple(1, function()
	print(string.format("[Beatrun Z-City %s] landing table (fixed): knees %d..%d, roll %d..%d, above %d no trick, min impact %.0f",
		ADDON_VERSION, KNEE_HEIGHT, KNEE_MAX, KNEE_MAX + 1, MAX_HEIGHT, MAX_HEIGHT,
		cvRollMinSpeed and cvRollMinSpeed:GetFloat() or 250))
end)
