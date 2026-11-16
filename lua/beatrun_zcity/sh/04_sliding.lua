-- Beatrun sprinting slide as a standalone addon for Z-City.
-- Runs after Z-City's SetupMove without replacing or editing any Z-City hooks.

local qslide_duration = 1.15
local cvSlideEnabled = GetConVar("Beatrun_ZCity_SlideEnabled")
local cvSlideMinSpeed = GetConVar("Beatrun_ZCity_SlideMinSpeed")
local cvAutoHold = GetConVar("Beatrun_ZCity_SlideAutoHold")
local cvSlideYawLimit = GetConVar("Beatrun_ZCity_SlideYawLimit")

function BeatrunGetSlideYawLimit()
	local limit = cvSlideYawLimit and cvSlideYawLimit:GetFloat() or 90
	if limit <= 0 or limit >= 180 then return 0 end
	return math.Clamp(limit, 5, 179)
end

local slide_sounds = {
	[0] = { "Slide.Concrete" },
	[MAT_CONCRETE] = { "Slide.Concrete" },
	[MAT_SAND] = { "Slide.Gravel" },
	[MAT_DIRT] = { "Slide.Gravel" },
	[MAT_SNOW] = { "Slide.Gravel" },
	[MAT_GRASS] = { "Slide.Gravel" },
	[MAT_METAL] = { "Slide.Metal" },
	[MAT_VENT] = { "Slide.Duct" },
	[MAT_TILE] = { "Slide.Marble" },
	[MAT_GLASS] = { "Slide.Glass" },
	[MAT_GRATE] = { "Slide.Gantry" },
	[MAT_PLASTIC] = { "Slide.Tarp" },
	[MAT_SLOSH] = { "Slide.Water" },
	[MAT_WOOD] = { "Slide.Wood" }
}

local slideloop_sounds = {
	[0] = "Slide.ConcreteLoop",
	[MAT_CONCRETE] = "Slide.ConcreteLoop",
	[MAT_GLASS] = "Slide.GlassLoop",
	[MAT_WOOD] = "Slide.WoodLoop",
	[MAT_SAND] = "Slide.GravelLoop",
	[MAT_DIRT] = "Slide.GravelLoop",
	[MAT_SNOW] = "Slide.GravelLoop",
	[MAT_GRASS] = "Slide.GravelLoop",
	[MAT_METAL] = "Slide.MetalLoop",
	[MAT_GRATE] = "Slide.GantryLoop",
	[MAT_PLASTIC] = "Slide.TarpLoop",
	[MAT_SLOSH] = "Slide.WaterLoop",
	[MAT_TILE] = "Slide.MarbleLoop",
	[MAT_VENT] = "Slide.DuctLoop"
}

if CLIENT then
	BeatrunSlideHoldingCrouch = BeatrunSlideHoldingCrouch or false
end

local slidepunch = Angle(2.5, 0, -0.5)
local slidejumplift = Vector(0, 0, 33)
local slidejumptr = {
	mask = MASK_PLAYERSOLID,
	collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT
}
local trace_down = Vector(0, 0, 32)
local trace_tbl = {}

local function SlideSurfaceSound(ply, pos)
	trace_tbl.start = pos
	trace_tbl.endpos = pos - trace_down
	trace_tbl.filter = ply

	local tr = util.TraceLine(trace_tbl)
	local sndtable = slide_sounds[tr.MatType] or slide_sounds[0]

	ply:EmitSound("Cloth.FallShortMedium")
	ply:EmitSound(sndtable[math.random(#sndtable)], 75, 100 + math.random(-20, -15), 0.5)

	return tr.MatType
end

local function SlideLoopSound(ply, mat)
	if ply.SlideLoopSound then
		pcall(function() ply.SlideLoopSound:Stop() end)
		ply.SlideLoopSound = nil
	end

	local sndtable
	if ply:WaterLevel() > 0 then
		sndtable = slideloop_sounds[MAT_SLOSH]
	else
		sndtable = slideloop_sounds[mat] or slideloop_sounds[0]
	end

	ply.SlideLoopSound = CreateSound(ply, sndtable)
	ply.SlideLoopSound:PlayEx(0.15, 100)
end

local function SavePlayerSlideState(ply)
	if not ply._BeatrunOrigDuckSpeed then
		ply._BeatrunOrigDuckSpeed = ply:GetDuckSpeed()
		ply._BeatrunOrigUnDuckSpeed = ply:GetUnDuckSpeed()
	end
	if not ply._BeatrunOrigViewOffset then
		ply._BeatrunOrigViewOffset = ply:GetViewOffset()
	end
	if not ply._BeatrunOrigViewOffsetDucked then
		ply._BeatrunOrigViewOffsetDucked = ply:GetViewOffsetDucked()
	end
end

local function RestorePlayerSlideState(ply)
	if IsValid(ply.FakeRagdoll) then
		ply._BeatrunOrigDuckSpeed = nil
		ply._BeatrunOrigUnDuckSpeed = nil
		ply._BeatrunOrigViewOffset = nil
		ply._BeatrunOrigViewOffsetDucked = nil
		return
	end

	if ply._BeatrunOrigDuckSpeed then
		ply:SetDuckSpeed(ply._BeatrunOrigDuckSpeed)
		ply:SetUnDuckSpeed(ply._BeatrunOrigUnDuckSpeed)
	end
	if ply._BeatrunOrigViewOffsetDucked then
		ply:SetViewOffsetDucked(ply._BeatrunOrigViewOffsetDucked)
	end
	if ply._BeatrunOrigViewOffset then
		ply:SetViewOffset(ply._BeatrunOrigViewOffset)
	end

	ply._BeatrunOrigDuckSpeed = nil
	ply._BeatrunOrigUnDuckSpeed = nil
	ply._BeatrunOrigViewOffset = nil
	ply._BeatrunOrigViewOffsetDucked = nil
end

local function EndSlideState(ply, mv, blocked, jumped, slippery)
	local CT = CurTime()
	ply:SetSliding(false)
	ply:SetSlidingTime(0)
	ply:SetSlidingSlippery(false)
	ply:SetSlidingDelay(CT + 0.25)

	if SERVER and ply.SlideLoopSound then
		ply.SlideLoopSound:FadeOut(0.15)
	end

	if not jumped then
		ply:ViewPunch(Angle(0.85, 0.35, 0))
	end

	RestorePlayerSlideState(ply)
	ply._BRZSlideMuzzlePos = nil
	ply._BRZSlideMuzzleDir = nil
	ply._BRZSlideMuzzleTime = nil

	-- Sync velocity cleanly back to Z-City inertia
	if mv then
		local v = mv:GetVelocity()
		ply.MovementInertia = v
		ply.CurrentSpeed = math.sqrt(v.x * v.x + v.y * v.y)
	end

	if CLIENT and IsFirstTimePredicted() and BeatrunSlideAnimEnd then
		BeatrunSlideAnimEnd(slippery and true or false, blocked and true or false)
	elseif SERVER then
		if game.SinglePlayer() then
			net.Start("sliding_spend")
				net.WriteBool(blocked and true or false)
				net.WriteBool(slippery and true or false)
			net.Send(ply)
		else
			net.Start("Beatrun_ZC_SlideEnd")
				net.WriteBool(blocked and true or false)
				net.WriteBool(slippery and true or false)
			net.Send(ply)
		end
	end
end

BeatrunAddOrderedHook("SetupMove", "zz_BeatrunZCity_Slide", function(ply, mv, cmd)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	if not cvSlideEnabled:GetBool() or not BeatrunCanSlideOrRoll(ply) then
		if ply:GetSliding() then
			BeatrunResetSlideRollState(ply)
			if CLIENT and IsFirstTimePredicted() and BeatrunSlideAnimAbort then
				BeatrunSlideAnimAbort()
			end
		end
		ply._BeatrunWasDucking = mv:KeyDown(IN_DUCK)
		return
	end

	if ply:GetSafetyRollTime() > CurTime() then
		ply._BeatrunWasDucking = mv:KeyDown(IN_DUCK)
		return
	end

	local CT = CurTime()
	local sliding = ply:GetSliding()
	local autohold = cvAutoHold and cvAutoHold:GetBool()

	-- Raw key state: the combo (sprint + crouch press) only *starts* the slide. With auto-hold the
	-- slide then runs on its own until it times out or the speed drops, so letting go of the keys no
	-- longer interrupts the trick.
	local duckRaw = mv:KeyDown(IN_DUCK)
	local duckPressed = duckRaw and not ply._BeatrunWasDucking
	ply._BeatrunWasDucking = duckRaw
	local ducking = duckRaw or (sliding and autohold) or false

	local velVec = mv:GetVelocity()
	local horizSpeed = math.sqrt(velVec.x * velVec.x + velVec.y * velVec.y)
	local sprinting = mv:KeyDown(IN_SPEED)
	local aiming = mv:KeyDown(IN_ATTACK2)
	local jumping = mv:KeyDown(IN_JUMP) or mv:KeyPressed(IN_JUMP)
	local onground = ply:OnGround()

	if not ply.SlideSlipperyTrace then
		local mins, maxs = ply:GetHull()
		ply.SlideSlipperyTraceOut = {}
		ply.SlideSlipperyTrace = {
			mask = MASK_SHOT_HULL,
			collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT,
			maxs = maxs,
			mins = mins,
			output = ply.SlideSlipperyTraceOut
		}
	end

	local slippery = false
	if sliding then
		local slipperytrace = ply.SlideSlipperyTrace
		local slipperytraceout = ply.SlideSlipperyTraceOut
		slipperytrace.filter = ply
		slipperytrace.start = mv:GetOrigin()
		slipperytrace.endpos = slipperytrace.start - Vector(0, 0, 32)
		util.TraceHull(slipperytrace)

		local normal = slipperytraceout.HitNormal
		if normal then
			local sang = normal:Angle()
			slippery = sang.x > 315 and sang.x < 330 and onground and ply:WaterLevel() < 1
		end
		ply:SetSlidingSlippery(slippery)
	end

	local mobility = BeatrunGetMobilityFactor(ply)
	local minSpeed = cvSlideMinSpeed:GetFloat() * (0.85 + 0.15 * mobility)
	local ableToSlide = duckPressed and sprinting and not aiming and not jumping and horizSpeed >= minSpeed
	local alreadySliding = sliding or (ply:GetSlidingDelay() >= CT)

	if not alreadySliding and onground and ableToSlide then
		SavePlayerSlideState(ply)

		local startVel = math.Clamp(horizSpeed * 1.12 * mobility, 220, 480 * mobility)
		local slideAng = velVec:Angle()
		slideAng.x = 0
		slideAng.z = 0

		ParkourEvent("slide", ply)

		ply:SetViewOffset(Vector(0, 0, 64))
		ply:SetSliding(true)
		ply:SetSlidingSlippery(false)

		-- Armed slide is only enabled if a valid non-melee weapon was already in hand when the
		-- slide started (bare hands and melee SWEPs use the regular unarmed slide).
		local wep = ply:GetActiveWeapon()
		ply._BRZSlideArmed = BeatrunIsSlideWeapon(wep)

		ply._BRZSlideProtectUntil = CT + 0.2

		local slidetime = math.max(0.1, qslide_duration)
		local slideCalcTime = slidetime * math.Clamp(startVel / 300, 0.65, 1.05) * (0.75 + 0.25 * mobility)
		ply:SetSlidingTime(CT + slideCalcTime)
		ply:SetSlidingAngle(slideAng)
		ply:SetSlidingVel(startVel)
		ply:SetSlidingStrafe(0)
		ply:SetSlidingLastPos(mv:GetOrigin())
		ply.SlidingInitTime = CT

		if not ply:Crouching() then
			ply:ViewPunch(slidepunch)
		end

		ply:SetDuckSpeed(0.1)
		ply:SetUnDuckSpeed(0.05)

		if SERVER then
			BeatrunConsumeStamina(ply, 8)
			local mat = SlideSurfaceSound(ply, mv:GetOrigin())
			SlideLoopSound(ply, mat)
		end

		if CLIENT and IsFirstTimePredicted() and BeatrunSlideAnimStart then
			BeatrunSlideAnimStart()
		elseif SERVER then
			if game.SinglePlayer() then
				ply:SendLua("LocalPlayer().SlidingInitTime = CurTime()")
				net.Start("sliding_spfix")
				net.Send(ply)
			else
				net.Start("Beatrun_ZC_SlideStart")
				net.Send(ply)
			end
		end

		sliding = true
	end

	if sliding and ((not ducking and not slippery and not autohold) or (not onground and not autohold)) then
		local blocked = false
		if not ducking then
			ply.SlideHull = ply.SlideHull or {}
			ply.SlideHullOut = ply.SlideHullOut or {}
			local hulltr = ply.SlideHull
			local hulltrout = ply.SlideHullOut
			local mins, maxs = ply:GetHull()
			local origin = mv:GetOrigin()

			hulltr.start = origin
			hulltr.endpos = origin
			hulltr.maxs = maxs
			hulltr.mins = mins
			hulltr.filter = ply
			hulltr.mask = MASK_PLAYERSOLID
			hulltr.collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT
			hulltr.output = hulltrout

			util.TraceHull(hulltr)
			if hulltrout.Hit then
				blocked = true
			end
		end

		EndSlideState(ply, mv, blocked, false, false)
		return
	end

	if sliding and autohold and duckPressed and (CT - (ply.SlidingInitTime or 0)) > 0.2 then
		-- A second, deliberate crouch press cancels the auto-held slide
		EndSlideState(ply, mv, false, false, slippery)
		return
	end

	if sliding then
		local eyeang = cmd:GetViewAngles()
		eyeang.x = 0
		eyeang.z = 0
		local fwd = eyeang:Forward()

		ply:SetViewOffsetDucked(Vector(0, 0, 28) + fwd * -22)

		if autohold then
			-- Keep the player ducked for the whole trick so the hull never stands up mid-slide
			mv:AddKey(IN_DUCK)
			ply:SetDuckSpeed(0.1)
			ply:SetUnDuckSpeed(0.05)
		end

		local slidetime = math.max(0.1, qslide_duration)
		local slidedelta = (ply:GetSlidingTime() - CT) / slidetime
		local speed = ply:GetSlidingVel() * math.min(1.55, (ply:GetSlidingTime() - CT + 0.5) / slidetime)

		-- Override Z-City's speed cap cleanly during the active slide only
		mv:SetMaxSpeed(speed)
		mv:SetMaxClientSpeed(speed)
		ply:SetMaxSpeed(math.max(100, speed))
		mv:SetVelocity(ply:GetSlidingAngle():Forward() * speed)
		ply.MovementInertia = mv:GetVelocity()

		local pos = mv:GetOrigin()
		local lastpos = ply:GetSlidingLastPos() or pos
		if not slippery and pos.z > lastpos.z + 1 then
			ply:SetSlidingTime(ply:GetSlidingTime() - 0.025)
		elseif slippery or (slidedelta < 1 and pos.z < lastpos.z - 0.25) then
			ply:SetSlidingTime(CT + slidetime)
			ply:SetSlidingVel(math.min(mv:GetVelocity():Length() * 0.9, 450 * mobility))
		end
		ply:SetSlidingLastPos(pos)

		-- Beatrun_ZCity_SlideSteer 0 (default): the slide course is fixed at the moment it starts.
		local steer = GetConVar("Beatrun_ZCity_SlideSteer")
		if not slippery and (not steer or steer:GetBool()) then
			if mv:KeyDown(IN_MOVELEFT) then
				local ang = ply:GetSlidingAngle()
				ang.y = ang.y + 0.5
				ply:SetSlidingAngle(ang)
			elseif mv:KeyDown(IN_MOVERIGHT) then
				local ang = ply:GetSlidingAngle()
				ang.y = ang.y - 0.5
				ply:SetSlidingAngle(ang)
			end
		end

		if mv:KeyPressed(IN_JUMP) then
			local mins, maxs = ply:GetHullDuck()
			local origin = mv:GetOrigin()
			slidejumptr.start = origin
			slidejumptr.endpos = origin + slidejumplift
			slidejumptr.mins = mins
			slidejumptr.maxs = maxs
			slidejumptr.filter = ply

			if util.TraceHull(slidejumptr).Hit then
				mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))
			else
				local vel = mv:GetVelocity()
				vel:Mul(math.min(math.max(speed, 260) / 300, 1))
				vel.z = 175

				mv:SetOrigin(origin + slidejumplift)
				ply:SetGroundEntity(nil)
				mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_DUCK)))
				mv:SetVelocity(vel)

				ParkourEvent("jumpslide", ply)
				EndSlideState(ply, mv, false, true, true)
				return
			end
		end

		if horizSpeed <= 75 or ply:GetSlidingTime() < CT then
			EndSlideState(ply, mv, PlayerCannotStand(ply), false, slippery)
			return
		end
	end
end, "HOOK_LOW")

BeatrunAddOrderedHook("StartCommand", "zz_BeatrunZCity_SlideCmd", function(ply, cmd)
	if not IsValid(ply) then return end
	if ply:GetSliding() and BeatrunCanSlideOrRoll(ply) then
		if CLIENT and ply == LocalPlayer() then
			BeatrunSlideHoldingCrouch = cmd:KeyDown(IN_DUCK)
		end

		cmd:RemoveKey(IN_SPEED)
		cmd:ClearMovement()

		-- Limit horizontal look/aim rotation relative to the slide direction while armed so the
		-- player cannot snap their neck 180 degrees and shoot behind their own back.
		local limit = BeatrunGetSlideYawLimit()
		if limit > 0 then
			local wep = ply:GetActiveWeapon()
			local armed = ply._BRZSlideArmed or BeatrunIsSlideWeapon(wep)
			if armed then
				local slideAng = ply:GetSlidingAngle()
				if isangle(slideAng) then
					local effLimit = SERVER and math.min(180, limit + 5) or limit
					local ang = cmd:GetViewAngles()
					local diff = math.AngleDifference(ang.y, slideAng.y)
					if diff > effLimit then
						ang.y = math.NormalizeAngle(slideAng.y + effLimit)
						cmd:SetViewAngles(ang)
					elseif diff < -effLimit then
						ang.y = math.NormalizeAngle(slideAng.y - effLimit)
						cmd:SetViewAngles(ang)
					end
				end
			end
		end

		local slidetime = math.max(0.1, qslide_duration)
		local autohold = cvAutoHold and cvAutoHold:GetBool()
		if autohold or ((ply:GetSlidingTime() - CurTime()) / slidetime > 0.8 and ((ply.SlidingInitTime or 0) > CurTime() - 0.25 or ply:GetSlidingSlippery())) then
			cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_DUCK))
			if autohold and CLIENT and ply == LocalPlayer() then
				-- The animation must not fall back to the "released crouch" end pose while auto-holding
				BeatrunSlideHoldingCrouch = true
			end
		end
	elseif CLIENT and ply == LocalPlayer() then
		BeatrunSlideHoldingCrouch = cmd:KeyDown(IN_DUCK)
	end
end, "HOOK_LOW")

-- Silence native footsteps strictly while actively sliding
hook.Add("PlayerFootstep", "BeatrunZCity_SilenceSlide", function(ply)
	if IsValid(ply) and ply:IsPlayer() and not IsValid(ply.FakeRagdoll) and ply:GetSliding() then
		return true
	end
end)

hook.Add("HG_PlayerFootstep", "BeatrunZCity_SilenceSlide", function(ply)
	if IsValid(ply) and ply:IsPlayer() and not IsValid(ply.FakeRagdoll) and ply:GetSliding() then
		return true
	end
end)

-- Receive the drawn right-hand pistol muzzle origin & barrel direction from the sliding client
-- so server bullets originate from and fly along the exact direction of the animated shooting hand.
if SERVER then
	net.Receive("Beatrun_ZC_SlideAim", function(_, ply)
		if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
		if not ply:GetSliding() or not ply._BRZSlideArmed or not BeatrunCanSlideOrRoll(ply) then return end

		local mpos = net.ReadVector()
		local mdir = net.ReadNormal()
		if not isvector(mpos) or not isvector(mdir) then return end

		local len = mdir:Length()
		if len < 0.01 then return end
		mdir = mdir * (1 / len)

		-- Anti-exploit bounds: muzzle must stay near the sliding player, aligned with real aim,
		-- and within the allowed left/right slide yaw cone (cannot shoot behind own back).
		local anchor = ply:GetPos() + Vector(0, 0, 24)
		if (mpos - anchor):LengthSqr() > 128 * 128 then return end
		if mdir:Dot(ply:GetAimVector()) < 0.15 then return end

		local limit = BeatrunGetSlideYawLimit()
		if limit > 0 and mdir:Length2D() > 0.15 then
			local slideAng = ply:GetSlidingAngle()
			if isangle(slideAng) then
				local yawDiff = math.abs(math.AngleDifference(mdir:Angle().y, slideAng.y))
				if yawDiff > math.min(180, limit + 18) then return end
			end
		end

		ply._BRZSlideMuzzlePos = mpos
		ply._BRZSlideMuzzleDir = mdir
		ply._BRZSlideMuzzleTime = CurTime()
	end)
end

-- Redirect bullets fired during an armed slide so they originate from the drawn right-hand weapon
-- barrel and fly strictly along its pointing direction (ignoring secondary ricochet/penetration shots).
hook.Add("EntityFireBullets", "BeatrunZCity_SlideBulletAim", function(ent, data)
	if not istable(data) then return end
	if (data.penetrated and data.penetrated > 0) or (data.limit_ricochet and data.limit_ricochet > 0) then return end

	local ply = data.Attacker
	if not (IsValid(ply) and ply:IsPlayer()) then
		if IsValid(ent) and ent:IsPlayer() then
			ply = ent
		elseif IsValid(ent) and ent.GetOwner and IsValid(ent:GetOwner()) and ent:GetOwner():IsPlayer() then
			ply = ent:GetOwner()
		else
			return
		end
	end

	if not ply:GetSliding() or not ply._BRZSlideArmed or ply.suiciding then return end
	if not (isvector(ply._BRZSlideMuzzlePos) and isvector(ply._BRZSlideMuzzleDir)) then return end
	if (CurTime() - (ply._BRZSlideMuzzleTime or 0)) > 0.25 then return end

	local mpos = ply._BRZSlideMuzzlePos
	local mdir = ply._BRZSlideMuzzleDir
	local wpn = ply:GetActiveWeapon()

	-- Wall-clip guard: if a wall lies between the sliding chest and the extended hand, clamp to the wall.
	local chestPos = ply:GetPos() + Vector(0, 0, 20)
	local filter = { ply }
	if IsValid(wpn) then
		filter[#filter + 1] = wpn
		if IsValid(wpn.worldModel) then
			filter[#filter + 1] = wpn.worldModel
		end
	end
	local tr = util.TraceLine({
		start = chestPos,
		endpos = mpos,
		filter = filter,
		mask = MASK_SHOT
	})
	local safeSrc = tr.Hit and (tr.HitPos - tr.Normal * 1.5) or mpos

	data.Src = safeSrc
	data.Dir = mdir

	-- Keep Z-City's client worldModel & desiredPos snapped to the drawn right-hand slide transform so
	-- the muzzle flash spawned immediately after FireLuaBullets comes right out of the drawn barrel.
	if CLIENT and ply == LocalPlayer() and IsValid(wpn) and isvector(wpn._BRZSlideGunPos) and isangle(wpn._BRZSlideGunAng) then
		if (CurTime() - (wpn._BRZSlideGunTime or 0)) <= 0.15 then
			wpn.desiredPos = wpn._BRZSlideGunPos
			wpn.desiredAng = wpn._BRZSlideGunAng
			local wm = wpn.worldModel
			if IsValid(wm) then
				wm:SetRenderOrigin(wpn._BRZSlideGunPos)
				wm:SetRenderAngles(wpn._BRZSlideGunAng)
				wm:SetPos(wpn._BRZSlideGunPos)
				wm:SetAngles(wpn._BRZSlideGunAng)
				wm:SetupBones()
			end
		end
	end

	return true
end)

