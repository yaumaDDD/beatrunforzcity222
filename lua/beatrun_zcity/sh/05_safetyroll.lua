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
local function HolsterWeaponForRoll(ply, cmd)
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

	-- Arm safety roll without stripping IN_DUCK (avoids Z-City AntiCrouchSpam penalty)
	if velZ <= -300 and not onground and not wasOnGround and not ply:GetSliding() and rollPressed then
		ply:SetSafetyRollKeyTime(CT + 0.6)
	end

	local isArming = CT < ply:GetSafetyRollKeyTime()
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

	if cvRollDebugLog and cvRollDebugLog:GetBool() then
		print(string.format("[Beatrun Z-City] landing speed %.0f - roll accepted", speed))
	end

	local tr = util.TraceLine({
		start = ply:GetPos(),
		endpos = ply:GetPos() - Vector(0, 0, 150),
		filter = ply
	})
	if tr.HitNormal and tr.HitNormal:Angle().x > 314 then return end

	ply._BeatrunRollHandledUntil = CT + 0.15
	ply:SetSafetyRollKeyTime(0)
	ply._BRZRollProtectUntil = CT + 2.5

	local mobility = BeatrunGetMobilityFactor(ply)
	ply:SetRollLoss(mobility < 0.75)

	ParkourEvent("roll", ply)

	local ang = ply:EyeAngles()
	ang.x = 0
	ang.z = 0

	local horizVel = ply:GetVelocity()
	horizVel.z = 0

	local isLandInPlace = horizVel:Length() < 160 or ply:KeyDown(IN_BACK)

	-- The roll was requested by the player, so play a real roll instead of the plain landing animation.
	-- Beatrun_RollAlways 0 restores the old behaviour (standing still / holding back = normal landing).
	if isLandInPlace and not ply:KeyDown(IN_BACK) and (not cvRollAlways or cvRollAlways:GetBool()) then
		isLandInPlace = false
	end

	-- Beatrun_RollAnim 0: a plain landing instead of a rolling one - no forward push, shorter window
	local useRoll = not (cvRollAnim and cvRollAnim:GetInt() == 0)

	if isLandInPlace or not useRoll then
		ply:SetSafetyRollAng(landang)
		ply:SetSafetyRollTime(CT + 0.6)
	else
		ply:SetSafetyRollAng(ang)
		ply:SetSafetyRollTime(CT + 1.0)
	end

	-- Immediately stow any held firearm/melee/item to bare hands when entering the safety roll
	HolsterWeaponForRoll(ply)

	if SERVER then
		BeatrunConsumeStamina(ply, math.Clamp(speed / 38, 8, 22))
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
		BeatrunRollAnimStart(isLandInPlace)
	elseif SERVER then
		if game.SinglePlayer() then
			net.Start("RollAnimSP")
				net.WriteBool(isLandInPlace)
				net.Send(ply)
		else
			-- Dedicated server: push the animation to the owning client too, so it never depends on
			-- prediction alone (that was why the roll sometimes never played for the player himself).
			net.Start("Beatrun_ZC_RollStart")
				net.WriteBool(isLandInPlace)
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
		HolsterWeaponForRoll(ply, cmd)
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

local cvSlideNoDamage = GetConVar("Beatrun_ZCity_SlideNoDamage")

local function Protected(ply)
	if ply._BRZRollProtectUntil and ply._BRZRollProtectUntil > CurTime() then return true end
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
