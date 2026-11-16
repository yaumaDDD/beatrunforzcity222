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

local landang = Angle(0, 0, 0)

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
	local sprintPressed = sprintNow and not ply._BeatrunPrevRollSprint
	ply._BeatrunPrevRollDuck = duckNow
	ply._BeatrunPrevRollSprint = sprintNow

	local velZ = mv:GetVelocity().z
	local rollPressed = duckPressed or sprintPressed

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
	-- 2.21.7: a *held* Ctrl (or Shift) is enough - you no longer have to press it again in mid-air,
	-- which is exactly what made the roll feel unreliable when you jumped off a roof already holding Ctrl.
	local holdingBrace = duckNow or sprintNow
	if velZ <= -300 and not onground and not ply:GetSliding() and (rollPressed or holdingBrace) then
		ply:SetSafetyRollKeyTime(CT + 0.6)
	end

	-- Pre-emptive brace: while Ctrl is held during a real fall the protection window stays open ahead of
	-- the impact, so Z-City's fallStun/ragdoll is already blocked when the ground arrives.
	if holdingBrace and not onground and not ply:GetSliding() and velZ <= -250 then
		ply._BRZBraced = true
		ply._BRZBracedUntil = CT + 0.3
	end

	local isArming = CT < ply:GetSafetyRollKeyTime()
	if CT >= ply:GetSafetyRollTime() then
		ply._BRZRollSlowFactor = nil
		ply._BRZRollSeconds = nil
		ply._BRZRollVariant = nil
	end

	if onground and not isArming and CT >= ply:GetSafetyRollTime() then
		local vel = mv:GetVelocity()
		vel.z = 0
		ply._BeatrunLastGroundSpeed = vel:Length()
	end

	if CT < ply:GetSafetyRollTime() then
		local ang = ply:GetSafetyRollAng()
		mv:SetSideSpeed(0)
		mv:SetForwardSpeed(0)
		mv:AddKey(IN_DUCK)

		local rollSpeed = 0
		if ang ~= landang then
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

			mv:SetMaxSpeed(rollSpeed)
			mv:SetMaxClientSpeed(rollSpeed)
			ply:SetMaxSpeed(math.max(100, rollSpeed))
			mv:SetVelocity(ang:Forward() * rollSpeed + vel)
		else
			local vel = mv:GetVelocity()
			vel.x = 0
			vel.y = 0
			mv:SetVelocity(vel)
		end

		ply.MovementInertia = mv:GetVelocity()
		ply.CurrentSpeed = rollSpeed
	end
end, "HOOK_LOW")

-- Runs BEFORE Z-City's fallStun and returns true only when a timed roll mitigates the impact
local function TrySafetyRoll(ply, water, floater, speed)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if water or floater then return end
	if not cvRollEnabled:GetBool() or not BeatrunCanSlideOrRoll(ply) then return end

	local CT = CurTime()
	local maxSafeSpeed = cvMaxSafeRollSpeed:GetFloat()

	if CT > ply:GetSafetyRollKeyTime() then return end

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

	-- 2.21.8: the fall height decides which trick you get, not a convar.
	--   Beatrun_RollAnim 0 (default) -> height decides: >= RollBigHeight = real roll, lower = knee landing
	--   Beatrun_RollAnim 1          -> always the roll animation
	--   Beatrun_RollAnim 2          -> always the knee landing
	local rollMode = cvRollAnim and cvRollAnim:GetInt() or 0
	local useRoll
	if rollMode == 2 then
		useRoll = false
	elseif rollMode == 1 then
		useRoll = true
	else
		useRoll = bigFall
	end

	-- Beatrun_RollAlways 0 keeps the old escape hatch: standing still / holding back = knee landing
	if useRoll and standingStill and not ply:KeyDown(IN_BACK) and (not cvRollAlways or cvRollAlways:GetBool()) then
		standingStill = false
	end
	if useRoll and standingStill and (not cvRollAlways or not cvRollAlways:GetBool()) then
		useRoll = false
	end

	-- An extremely long drop gets the low, crouched roll on top of the normal one
	local lowRoll = useRoll and fallHeight >= bigHeight * 2

	ply._BRZRollVariant = useRoll and (lowRoll and 3 or 2) or 1

	-- How long the trick owns the player: a drop from a roof rolls noticeably longer than a fence hop.
	local rollSeconds = math.Clamp(0.85 + fallHeight / 520, 0.85, 1.7)
	if useRoll then rollSeconds = math.min(rollSeconds, 1.9) end
	ply._BRZRollSeconds = rollSeconds

	if not useRoll then
		-- Knee landing (Mirror's Edge "land" pose, like Beatrun's in-place landing): you drop onto one
		-- knee, you do not launch forward.
		ply:SetSafetyRollAng(landang)
		ply:SetSafetyRollTime(CT + math.Clamp(rollSeconds, 0.6, 0.85))
		ply._BRZRollSlowFactor = nil
	else
		ply:SetSafetyRollAng(ang)
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

	if CLIENT and IsFirstTimePredicted() and BeatrunRollAnimStart then
		BeatrunRollAnimStart(isLandInPlace, lowRoll)
	elseif SERVER then
		if game.SinglePlayer() then
			net.Start("RollAnimSP")
				net.WriteBool(isLandInPlace)
				net.WriteBool(lowRoll)
				net.Send(ply)
		else
			-- Dedicated server: push the animation to the owning client too, so it never depends on
			-- prediction alone (that was why the roll sometimes never played for the player himself).
			net.Start("Beatrun_ZC_RollStart")
				net.WriteBool(isLandInPlace)
				net.WriteBool(lowRoll)
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
