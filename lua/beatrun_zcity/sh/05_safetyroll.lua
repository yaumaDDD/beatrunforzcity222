-- Beatrun fall safety roll as a standalone addon for Z-City.
-- Never replaces Z-City hooks; returns true in OnPlayerHitGround only when a timed roll succeeds.

local cvRollEnabled = GetConVar("Beatrun_ZCity_RollEnabled")
local cvRollSpeedLoss = GetConVar("Beatrun_RollSpeedLoss")
local cvRollAlways = GetConVar("Beatrun_RollAlways")
local cvRollAnim = GetConVar("Beatrun_RollAnim")
local cvRollNoDamage = GetConVar("Beatrun_RollNoDamage")
local cvRollHolster = GetConVar("Beatrun_ZCity_RollHolster")
local cvRollFallReduction = GetConVar("Beatrun_ZCity_RollFallReduction")
local cvMaxSafeRollSpeed = GetConVar("Beatrun_ZCity_MaxSafeRollSpeed")
local cvRollMinSpeed = GetConVar("Beatrun_ZCity_RollMinSpeed")
local cvRollMinHeight = GetConVar("Beatrun_ZCity_RollMinHeight")
local cvRollBigHeight = GetConVar("Beatrun_ZCity_RollBigHeight")
local cvRollDebugLog = GetConVar("Beatrun_RollDebugLog")

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
	end

	-- Armed for this fall: keep the roll armed until the ground arrives and brace the impact ahead of
	-- time, so Z-City's fallStun/ragdoll is already blocked when the feet touch.
	if airborne and ply._BRZFallArmed and not rollBlocked then
		ply:SetSafetyRollKeyTime(CT + 0.5)
		ply._BRZBraced = true
		ply._BRZBracedUntil = CT + 0.35
	elseif onground and ply._BRZFallArmed and CT > ply:GetSafetyRollKeyTime() then
		-- landed without a trick (too low or a bad spot) - the arm has done its job
		ply._BRZFallArmed = nil
	end

	local isArming = CT < ply:GetSafetyRollKeyTime()
	if CT >= ply:GetSafetyRollTime() then
		ply._BRZRollSlowFactor = nil
		ply._BRZRollSeconds = nil
		ply._BRZRollVariant = nil
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

		local rollSpeed = 0
		if not landInPlace then
			local vel = mv:GetVelocity()
			vel.x = 0
			vel.y = 0

			local mobility = BeatrunGetMobilityFactor(ply)
			local speedloss = cvRollSpeedLoss:GetBool() or ply:GetRollLoss()

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

			-- 2.21.17: the roll has to carry the body forward, like Beatrun's does. Z-City's inertia
			-- (homigrad/movement/sh_inertia.lua) rebuilds the movement wish from ply.MovementInertia in
			-- its own SetupMove, and our hook runs after it - zeroing the wish speeds here is exactly
			-- what kept the roll in place. So the roll direction is handed back as the movement wish and
			-- the velocity is set as well, for servers whose inertia is off.
			local viewAng = Angle(0, ply:EyeAngles().y, 0)
			local wishFwd = dir:Dot(viewAng:Forward()) * rollSpeed
			local wishSide = dir:Dot(viewAng:Right()) * rollSpeed

			mv:SetForwardSpeed(wishFwd)
			mv:SetSideSpeed(wishSide)
			mv:SetMaxSpeed(rollSpeed)
			mv:SetMaxClientSpeed(rollSpeed)
			ply:SetMaxSpeed(math.max(100, rollSpeed))
			mv:SetVelocity(dir * rollSpeed + vel)

			ply.MovementInertia = dir * rollSpeed
			ply.CurrentSpeed = rollSpeed
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
-- can never disagree with the movement:
--   1 = knee landing  "land" / "landgun"                 (below Beatrun_ZCity_RollBigHeight)
--   2 = real roll     "meroll" / "merollgun"             (RollBigHeight .. 2 x RollBigHeight)
--   3 = low roll      "merollcrouch" / "merollguncrouch" (2 x RollBigHeight and above)
-- Beatrun_RollAnim 1 forces 2/3, 2 forces 1.
-- ---------------------------------------------------------------------------
function BeatrunRollVariantForHeight(fallHeight)
	fallHeight = math.max(0, fallHeight or 0)

	local bigHeight = cvRollBigHeight and cvRollBigHeight:GetFloat() or 350
	local rollMode = cvRollAnim and cvRollAnim:GetInt() or 0

	local useRoll
	if rollMode == 2 then
		useRoll = false
	elseif rollMode == 1 then
		useRoll = true
	else
		useRoll = fallHeight >= bigHeight
	end

	local lowRoll = useRoll and fallHeight >= bigHeight * 2
	local variant = useRoll and (lowRoll and 3 or 2) or 1

	return variant, useRoll, lowRoll, bigHeight
end

-- Runs BEFORE Z-City's fallStun and returns true only when a timed roll mitigates the impact
local function TrySafetyRoll(ply, water, floater, speed)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if water or floater then return end
	if not cvRollEnabled:GetBool() or not BeatrunCanSlideOrRoll(ply) then return end

	local CT = CurTime()
	local maxSafeSpeed = cvMaxSafeRollSpeed:GetFloat()

	if CT > ply:GetSafetyRollKeyTime() then return end

	-- The arm belongs to exactly one landing, and a roll that just started must not be re-triggered
	-- by the next physics frame (that was the other half of the "animation plays twice" bug).
	ply._BRZFallArmed = nil
	if CT < (ply._BRZRollStartGuard or 0) then return end
	ply._BRZRollStartGuard = CT + 0.45

	-- The hard cap used to be 820: any fall faster than that skipped the roll entirely, so the ragdoll
	-- and the broken legs came through even though the player pressed in time. Now the timing is the
	-- only condition; a very fast fall is still protected.
	local hardCap = math.max(maxSafeSpeed, 3000)
	if speed < cvRollMinSpeed:GetFloat() or speed > hardCap then return end

	-- Height gate (2.21.7): the roll is the answer to a real fall, not to a step down or a normal jump.
	local fallHeight = math.max(0, (ply._BRZFallPeakZ or ply:GetPos().z) - ply:GetPos().z)
	if ply._BRZLastFallHeight and ply._BRZLastFallHeight > fallHeight then
		fallHeight = ply._BRZLastFallHeight
	end

	local minHeight = cvRollMinHeight and cvRollMinHeight:GetFloat() or 70
	if fallHeight < minHeight then
		if cvRollDebugLog and cvRollDebugLog:GetBool() then
			print(string.format("[Beatrun Z-City] fall %.0f units / speed %.0f - too low for a roll", fallHeight, speed))
		end
		return
	end

	-- Big fall = the heavy variant: longer roll, crouched pose, wider protection window, more stamina.
	local bigHeight = cvRollBigHeight and cvRollBigHeight:GetFloat() or 260
	local bigFall = fallHeight >= bigHeight

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

	local mobility = BeatrunGetMobilityFactor(ply)
	ply:SetRollLoss(mobility < 0.75)

	ParkourEvent("roll", ply)

	local ang = ply:EyeAngles()
	ang.x = 0
	ang.z = 0

	local horizVel = ply:GetVelocity()
	horizVel.z = 0

	local standingStill = horizVel:Length() < 160 or ply:KeyDown(IN_BACK)

	-- 2.21.14: the variant comes from the shared helper, so client and server always agree on it.
	local variant, useRoll, lowRoll, bigH = BeatrunRollVariantForHeight(fallHeight)

	-- Beatrun_RollAlways 0 keeps the old escape hatch: standing still / holding back = knee landing
	if useRoll and standingStill and not ply:KeyDown(IN_BACK) and (not cvRollAlways or cvRollAlways:GetBool()) then
		standingStill = false
	end
	if useRoll and standingStill and (not cvRollAlways or not cvRollAlways:GetBool()) then
		useRoll = false
	end

	ply._BRZRollVariant = variant

	if cvRollDebugLog and cvRollDebugLog:GetBool() then
		local names = { [1] = "land", [2] = "meroll", [3] = "merollcrouch" }
		print(string.format("[Beatrun Z-City] fall %.0f -> variant %d (%s)  [knee < %.0f, roll %.0f..%.0f, low roll >= %.0f]",
			fallHeight, variant, names[variant], bigH, bigH, bigH * 2 - 1, bigH * 2))
	end

	-- How long the trick owns the player: a drop from a roof rolls noticeably longer than a fence hop.
	local rollSeconds = math.Clamp(0.85 + fallHeight / 520, 0.85, 1.7)
	if useRoll then rollSeconds = math.min(rollSeconds, 1.9) end
	ply._BRZRollSeconds = rollSeconds

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
		ply._BRZRollSlowFactor = math.Clamp(1 - (fallHeight - bigHeight) / 2600, 0.62, 1)
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
		local blocked = CT <= (ply._BeatrunRollHandledUntil or 0)   -- this landing was taken by the roll
			or CT < rollEnd                                         -- the roll is still playing
			or ply._BRZFallArmed                                    -- a roll is armed and will take it

		if blocked then
			if cvRollDebugLog and cvRollDebugLog:GetBool() then
				print("[Beatrun Z-City] Z-City fallStun blocked - the roll owns this landing")
			end
			return true
		end
	end

	local ok, consumed = pcall(TrySafetyRoll, ply, inwater, onfloater, speed)
	if ok and consumed then return true end
	if FallStunOriginal then return FallStunOriginal(ply, inwater, onfloater, speed) end
end

local function InstallFallStunGuard()
	if not hook.GetTable then return false end
	local tables = hook.GetTable()
	if not istable(tables) then return false end
	local list = tables["OnPlayerHitGround"]
	if not istable(list) or not list.fallStun or list.fallStun == FallStunWrapper then return false end
	FallStunOriginal = FallStunOriginal or list.fallStun
	hook.Add("OnPlayerHitGround", "fallStun", FallStunWrapper)
	return true
end

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
		local fallHeight = math.max(0, (ply._BRZFallPeakZ or ply:GetPos().z) - ply:GetPos().z)
		if ply._BRZLastFallHeight and ply._BRZLastFallHeight > fallHeight then
			fallHeight = ply._BRZLastFallHeight
		end
		if fallHeight < (cvRollMinHeight and cvRollMinHeight:GetFloat() or 70) then return end

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
