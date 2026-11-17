-- Beatrun ledge climb & hang for Z-City (2.21.8).
-- Ported from Beatrun's sh/climb.lua to this addon's scheme: no gamemode edits, no MOVETYPE_NOCLIP,
-- no view/angle lock. The origin is driven inside SetupMove (predicted on the client and repeated on
-- the server) and the animation goes through StartBodyAnim like the slide and the safety roll.
--
-- Flow (2.21.20, the two climbs that looked right, jump-only entry):
--   * jump at a wall (and nothing else - no sprint+W, no flying into it) -> grab
--   * low ledge (waist/chest height, ClimbLowHeight)  -> immediate vault onto it (vaultonto)
--   * high ledge                                      -> hang, then the pull-up starts by itself (hangheaveup)
--   * while hanging: Ctrl / S drops you, Jump pushes you off the wall (the safety roll gets armed)

local cvEnabled = GetConVar("Beatrun_ZCity_ClimbEnabled")
local cvHangHeight = GetConVar("Beatrun_ZCity_ClimbHangHeight")
local cvMaxLedge = GetConVar("Beatrun_ZCity_ClimbMaxLedgeHeight")
local cvLowHeight = GetConVar("Beatrun_ZCity_ClimbLowHeight")
local cvReach = GetConVar("Beatrun_ZCity_ClimbReach")
local cvHoldDelay = GetConVar("Beatrun_ZCity_ClimbHoldDelay")
local cvHeaveTime = GetConVar("Beatrun_ZCity_ClimbHeaveTime")
local cvCooldown = GetConVar("Beatrun_ZCity_ClimbCooldown")

local STATE_NONE, STATE_HANG, STATE_HEAVE = 0, 1, 2
local LOW_HEAVE_TIME = 0.45

local function Log(fmt, ...)
	if BeatrunZCityLogEnabled() then
		BeatrunZCityLogLine("[Beatrun Z-City] " .. string.format(fmt, ...))
	end
end

local PLAYER = FindMetaTable("Player")

function PLAYER:GetBRZClimbState()
	return self._BRZClimbState or STATE_NONE
end

function PLAYER:SetBRZClimbState(state)
	self._BRZClimbState = state or STATE_NONE
	self._BRZClimbStateTime = CurTime()
	return self._BRZClimbState
end

local function ClearClimbState(ply)
	ply._BRZClimbState = STATE_NONE
	ply._BRZClimbStateTime = 0
	ply._BRZClimbAng = nil
	ply._BRZClimbHangPos = nil
	ply._BRZClimbStandPos = nil
	ply._BRZClimbHeaveStart = nil
	ply._BRZClimbHeaveDur = nil
	ply._BRZClimbGrabSpeed = nil
	ply._BRZClimbLow = nil
	ply._BRZClimbJumpWindow = nil
end

-- ---------------------------------------------------------------------------
-- Ledge search: a wall in front of the eyes plus a player-sized hull that has to find a real standing
-- spot on top of it (the same idea as Beatrun's ClimbingTrace / ClimbingTraceEnd pair).
-- ---------------------------------------------------------------------------
local wallTable = {}
local ledgeHull = {}
local standTable = {}
local floorTable = {}
local hangTable = {}

local function ProbeLedge(ply, origin, hit, eyeang, reach, mins, maxs)
	local normal = hit.HitNormal
	if math.abs(normal.z) > 0.4 then return end
	if IsValid(hit.Entity) and hit.Entity.NoClimbing then return end

	local wallang = normal:Angle()
	wallang.y = wallang.y + 180 -- forward points INTO the wall, exactly like Beatrun
	wallang.x, wallang.z = 0, 0
	if math.abs(math.AngleDifference(wallang.y, eyeang.y)) > 60 then return end

	-- push the standing hull into the wall and look for a ledge top it can rest on
	local flat = hit.HitPos - origin
	flat.z = 0
	local dist = flat:Length()
	local lead = math.Clamp(dist + math.max(maxs.x, maxs.y) + 4, 26, 62)

	local up = math.max(maxs.z * 0.9, 64)
	local probeStart = Vector(origin.x, origin.y, origin.z + up) + wallang:Forward() * lead

	ledgeHull.mins = Vector(mins.x, mins.y, 0)
	ledgeHull.maxs = maxs
	ledgeHull.filter = ply
	ledgeHull.mask = MASK_PLAYERSOLID
	ledgeHull.start = probeStart
	ledgeHull.endpos = probeStart - Vector(0, 0, up + 130)

	local ledge = util.TraceHull(ledgeHull)
	if not ledge.Hit then return end
	if ledge.Fraction <= 0.02 then return end -- started inside solid: nothing standable up there
	if ledge.HitNormal.z < 0.6 then return end -- must be a floor-like top surface

	local topZ = ledge.HitPos.z
	local height = topZ - origin.z
	if height < 12 then return end -- already level with it
	if height > cvMaxLedge:GetFloat() then return end

	local standPos = Vector(ledge.HitPos.x, ledge.HitPos.y, topZ + 1)

	-- that spot has to be free for the player's own hull, with a floor under it
	standTable.start = standPos
	standTable.endpos = standPos
	standTable.mins = Vector(mins.x, mins.y, 1)
	standTable.maxs = maxs
	standTable.filter = ply
	standTable.mask = MASK_PLAYERSOLID
	if util.TraceHull(standTable).Hit then return end

	floorTable.start = standPos
	floorTable.endpos = standPos - Vector(0, 0, 12)
	floorTable.filter = ply
	floorTable.mask = MASK_PLAYERSOLID
	if not util.TraceLine(floorTable).Hit then return end

	-- the hanging body: hands on the ledge edge, feet in the air
	local radius = math.max(maxs.x, maxs.y) + 1.5
	local hangPos = Vector(hit.HitPos.x, hit.HitPos.y, 0) + normal * radius
	hangPos.z = topZ - cvHangHeight:GetFloat()

	hangTable.start = hangPos
	hangTable.endpos = hangPos
	hangTable.mins = mins
	hangTable.maxs = maxs
	hangTable.filter = ply
	hangTable.mask = MASK_PLAYERSOLID
	-- No free air below the ledge (the floor is right there) -> no hang, just vault up onto it
	if util.TraceHull(hangTable).Hit then hangPos = nil end

	return {
		wallang = wallang,
		hangPos = hangPos,
		standPos = standPos,
		topZ = topZ,
		height = height,
		dist = dist
	}
end

local function FindLedge(ply, mv, eyeang)
	local mins, maxs = ply:GetHull()
	local origin = mv:GetOrigin()
	local reach = cvReach:GetFloat()

	local fwd = eyeang:Forward()
	fwd = Vector(fwd.x, fwd.y, math.Clamp(fwd.z, -0.6, 0.5))
	if fwd:LengthSqr() < 0.001 then return end
	fwd:Normalize()

	-- 2.21.8: probe at three heights instead of only at the chest. A waist-high wall has nothing in
	-- front of your chest, and that is why the low "vault onto the wall" climb never fired.
	local heights = { maxs.z * 0.85, maxs.z * 0.5, math.min(maxs.z * 0.22, 16) }

	for i = 1, #heights do
		wallTable.start = origin + Vector(0, 0, heights[i])
		wallTable.endpos = wallTable.start + fwd * reach
		wallTable.filter = ply
		wallTable.mask = MASK_PLAYERSOLID

		local wall = util.TraceLine(wallTable)
		if wall.Hit and wall.Fraction > 0 then
			local ledge = ProbeLedge(ply, origin, wall, eyeang, reach, mins, maxs)
			if ledge then
				ledge.probeHeight = heights[i]
				return ledge
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- State changes
-- ---------------------------------------------------------------------------
local StartHeave

local function StartGrab(ply, mv, ledge, CT, fromGround)
	local grabSpeed = math.max(0, -mv:GetVelocity().z)
	local hard = grabSpeed > 420
	local origin = mv:GetOrigin()

	ply._BRZClimbAng = ledge.wallang
	ply._BRZClimbStandPos = ledge.standPos
	ply._BRZClimbGrabSpeed = grabSpeed

	-- you cannot hang from a ledge with a rifle in your hands
	if isfunction(BeatrunZCityHolsterForTrick) then
		BeatrunZCityHolsterForTrick(ply)
	end

	-- Two different climbs by height (2.21.8), exactly like the rig's two animations:
	--   low ledge (ClimbLowHeight and below) -> vault onto the wall        (vaultonto)
	--   higher ledge                         -> hang, then pull up on W   (hangheaveup)
	-- No room to hang below the ledge (a floor right under it) also falls back to the vault.
	-- From the ground (jump or sprint into the wall) the height picks the animation: a low ledge is
	-- vaulted, a higher one is hung on. Catching a ledge while falling always goes through the hang,
	-- because hanging is what that looks like.
	local lowLedge
	if fromGround then
		lowLedge = ledge.height <= cvLowHeight:GetFloat() or not isvector(ledge.hangPos)
	else
		lowLedge = not isvector(ledge.hangPos)
	end

	Log("ledge grab: height %.0f, wall %.0f away, impact %.0f, %s -> %s", ledge.height, ledge.dist, grabSpeed,
		fromGround and "from the ground" or "caught in the air",
		lowLedge and "vault (vaultonto)" or "hang (hangheaveup)")

	if lowLedge then
		ply._BRZClimbLow = true
		ply._BRZClimbHangPos = Vector(origin)

		if SERVER then
			ply:EmitSound("Cloth.MovementRun")
			ply:EmitSound("WallrunRelease.Concrete")
		end

		StartHeave(ply, mv, CT, true)
		return
	end

	ply._BRZClimbLow = false
	ply._BRZClimbHangPos = ledge.hangPos
	ply:SetBRZClimbState(STATE_HANG)

	mv:SetVelocity(vector_origin)
	mv:SetForwardSpeed(0)
	mv:SetSideSpeed(0)
	mv:SetUpSpeed(0)
	mv:SetOrigin(ledge.hangPos)
	mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))

	if CLIENT and IsFirstTimePredicted() and isfunction(BeatrunZCityClimbAnimGrab) then
		BeatrunZCityClimbAnimGrab(ledge.wallang, hard)
	end

	if SERVER then
		ply:EmitSound("Cloth.MovementRun")
		ply:EmitSound("WallrunRelease.Concrete")
		if hard then ply:EmitSound("Cloth.FallShortMedium") end

		-- 2.21.35: the others see the grab (and, when it ends, the hang pose - see cl/10_remote_tricks.lua)
		BeatrunZCBroadcastTrick(ply, hard and "hanghardstart2" or "hanghardstart", 0, hard and 1.25 or 1.1, "oneshot")

		if not game.SinglePlayer() then
			net.Start("Beatrun_ZC_ClimbGrab")
				net.WriteAngle(ledge.wallang)
				net.WriteBool(hard)
			net.Send(ply)
		end
	end
end

StartHeave = function(ply, mv, CT, low)
	local dur = low and LOW_HEAVE_TIME or math.max(0.2, cvHeaveTime:GetFloat())

	ply:SetBRZClimbState(STATE_HEAVE)
	ply._BRZClimbHeaveStart = CT
	ply._BRZClimbHeaveDur = dur
	ply._BRZClimbLow = low and true or false

	mv:SetVelocity(vector_origin)
	mv:SetForwardSpeed(0)
	mv:SetSideSpeed(0)
	mv:SetUpSpeed(0)

	if CLIENT and IsFirstTimePredicted() and isfunction(BeatrunZCityClimbAnimHeave) then
		BeatrunZCityClimbAnimHeave(ply._BRZClimbAng, low)
	end

	if SERVER then
		ply:EmitSound("Cloth.MovementWalk")

		BeatrunZCBroadcastTrick(ply, low and "vaultonto" or "hangheaveup", low and 0.45 or math.max(0.2, cvHeaveTime:GetFloat()), 1, "oneshot")

		if not game.SinglePlayer() then
			net.Start("Beatrun_ZC_ClimbHeave")
				net.WriteAngle(ply._BRZClimbAng or angle_zero)
				net.WriteBool(low and true or false)
			net.Send(ply)
		end
	end
end

local function FinishHeave(ply, mv, CT)
	local standPos = ply._BRZClimbStandPos
	local ang = ply._BRZClimbAng

	ClearClimbState(ply)
	ply._BRZClimbCooldown = CT + cvCooldown:GetFloat()

	if isvector(standPos) then mv:SetOrigin(standPos) end

	local push = ang and ang:Forward() or Vector(1, 0, 0)
	push = Vector(push.x, push.y, 0)
	if push:LengthSqr() > 0.001 then
		push:Normalize()
		push:Mul(40)
	else
		push = vector_origin
	end
	mv:SetVelocity(push)

	if CLIENT and IsFirstTimePredicted() and isfunction(BeatrunZCityClimbAnimEnd) then
		BeatrunZCityClimbAnimEnd(true)
	end

	if SERVER then
		ply:EmitSound("Cloth.MovementWalk")
		BeatrunZCBroadcastTrickStop(ply)
		if not game.SinglePlayer() then
			net.Start("Beatrun_ZC_ClimbEnd")
				net.WriteBool(true)
			net.Send(ply)
		end
	end
end

local function ReleaseGrab(ply, mv, CT, jumpOff)
	local ang = ply._BRZClimbAng
	local hangPos = ply._BRZClimbHangPos

	ClearClimbState(ply)
	ply._BRZClimbCooldown = CT + cvCooldown:GetFloat()

	if isvector(hangPos) then mv:SetOrigin(hangPos) end

	local vel = vector_origin
	if jumpOff and ang then
		local away = ang:Forward() * -1
		vel = Vector(away.x, away.y, 0)
		if vel:LengthSqr() > 0.001 then
			vel:Normalize()
			vel:Mul(110)
		else
			vel = vector_origin
		end
		vel.z = 210
	end
	mv:SetVelocity(vel)

	-- Dropping off a ledge is a fall: arm the safety roll for it (Ctrl can stay held).
	-- 2.21.27: the landing gate reads this tap record instead of the replicated key window, so a climb
	-- drop counts as "the player asked for the trick" exactly like a Ctrl tap does.
	ply:SetSafetyRollKeyTime(CT + 0.6)
	ply._BRZFallTappedAt = CT
	ply._BRZFallPeakZ = nil

	if CLIENT and IsFirstTimePredicted() and isfunction(BeatrunZCityClimbAnimEnd) then
		BeatrunZCityClimbAnimEnd(false)
	end

	if SERVER then
		ply:EmitSound("Cloth.MovementRun")
		BeatrunZCBroadcastTrickStop(ply)
		if not game.SinglePlayer() then
			net.Start("Beatrun_ZC_ClimbEnd")
				net.WriteBool(false)
			net.Send(ply)
		end
	end
end

local function CancelClimb(ply)
	ClearClimbState(ply)
	if SERVER then BeatrunZCBroadcastTrickStop(ply) end
	if CLIENT and IsFirstTimePredicted() and isfunction(BeatrunZCityClimbAnimEnd) then
		BeatrunZCityClimbAnimEnd(false)
	end
	if SERVER and not game.SinglePlayer() then
		net.Start("Beatrun_ZC_ClimbEnd")
			net.WriteBool(false)
		net.Send(ply)
	end
end

-- ---------------------------------------------------------------------------
-- Per-tick updates
-- ---------------------------------------------------------------------------
local function UpdateHang(ply, mv, CT)
	local held = CT - (ply._BRZClimbStateTime or CT)
	local hangPos = ply._BRZClimbHangPos

	mv:SetVelocity(vector_origin)
	mv:SetForwardSpeed(0)
	mv:SetSideSpeed(0)
	mv:SetUpSpeed(0)
	if isvector(hangPos) then mv:SetOrigin(hangPos) end
	mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))

	-- Read the movement wish BEFORE the velocity is zeroed for the hang pose
	local wishForward = isfunction(mv.GetForwardSpeed) and mv:GetForwardSpeed() or 0

	if held > 0.12 then
		if mv:KeyPressed(IN_DUCK) then
			ReleaseGrab(ply, mv, CT, false)
			return
		end

		-- Backing off lets go instead of dragging you up onto the ledge
		if mv:KeyDown(IN_BACK) or wishForward < -50 then
			ReleaseGrab(ply, mv, CT, false)
			return
		end

		if held > cvHoldDelay:GetFloat() then
			if mv:KeyPressed(IN_JUMP) then
				ReleaseGrab(ply, mv, CT, true)
				return
			end

			-- 2.21.9: the pull-up no longer waits for W. After a short hang the climb finishes by
			-- itself, so "jump at the wall" is the whole input and the animation carries you up.
			StartHeave(ply, mv, CT, false)
			return
		end
	end

	-- safety: never hang forever (bleeding out, alt-tab, stuck input)
	if held > 15 then
		ReleaseGrab(ply, mv, CT, false)
	end
end

local function UpdateHeave(ply, mv, CT)
	local dur = ply._BRZClimbHeaveDur or math.max(0.2, cvHeaveTime:GetFloat())
	local startT = ply._BRZClimbHeaveStart or CT
	local from = ply._BRZClimbHangPos
	local to = ply._BRZClimbStandPos

	if not (isvector(from) and isvector(to)) then
		CancelClimb(ply)
		return
	end

	local t = math.Clamp((CT - startT) / math.max(dur, 0.05), 0, 1)
	local lift = 8 -- rise just above the edge, then step over it and settle down
	local pos

	if t < 0.6 then
		local u = t / 0.6
		local s = u * u * (3 - 2 * u)
		pos = Vector(from.x, from.y, Lerp(s, from.z, to.z + lift))
	else
		local u = math.Clamp((t - 0.6) / 0.4, 0, 1)
		local s = u * u * (3 - 2 * u)
		pos = Vector(
			Lerp(s, from.x, to.x),
			Lerp(s, from.y, to.y),
			Lerp(s, to.z + lift, to.z)
		)
	end

	mv:SetVelocity(vector_origin)
	mv:SetForwardSpeed(0)
	mv:SetSideSpeed(0)
	mv:SetUpSpeed(0)
	mv:SetOrigin(pos)
	mv:SetButtons(bit.band(mv:GetButtons(), bit.bnot(IN_JUMP)))

	if t >= 1 then
		FinishHeave(ply, mv, CT)
	end
end

-- ---------------------------------------------------------------------------
-- SetupMove entry point
-- ---------------------------------------------------------------------------
BeatrunAddOrderedHook("SetupMove", "zz_BeatrunZCity_Climb", function(ply, mv, cmd)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	local CT = CurTime()
	local state = ply:GetBRZClimbState()

	if not cvEnabled:GetBool() or not BeatrunCanSlideOrRoll(ply) then
		if state ~= STATE_NONE then CancelClimb(ply) end
		return
	end

	if state == STATE_HANG then
		UpdateHang(ply, mv, CT)
		return
	elseif state == STATE_HEAVE then
		UpdateHeave(ply, mv, CT)
		return
	end

	-- Conditions to start a grab
	if (ply._BRZClimbCooldown or 0) > CT then return end
	if CT < ply:GetSafetyRollTime() then return end
	if ply:GetSliding() then return end

	local onground = ply:OnGround()
	local vel = mv:GetVelocity()

	local jumpWindow = (ply._BRZClimbJumpWindow or 0) > CT

	-- 2.21.9/2.21.17: the only way in is jumping at the wall - no sprint+W combos, no extra keys, and
	-- no grabs while you are merely flying past a wall. The grab itself happens a few ticks later, in
	-- the air, exactly like Beatrun.
	if onground then
		if mv:KeyPressed(IN_JUMP) then
			ply._BRZClimbJumpWindow = CT + 0.5
		end
		return
	end

	if not jumpWindow then return end

	local eyeang = ply:EyeAngles()
	local ledge = FindLedge(ply, mv, eyeang)

	if not ledge then
		if CT > (ply._BRZClimbLogAt or 0) then
			ply._BRZClimbLogAt = CT + 0.5
			Log("no ledge: wall not found or the ledge is not standable (ClimbReach %.0f, ClimbMaxLedgeHeight %.0f)",
				cvReach:GetFloat(), cvMaxLedge:GetFloat())
		end
		return
	end

	-- Never grab while actually moving away from the wall: that is what used to pull you forward when
	-- you were backing off. Jumping at a wall from a standstill still works - only real backward
	-- movement is rejected.
	local flatVel = Vector(vel.x, vel.y, 0)
	if flatVel:Dot(ledge.wallang:Forward()) < -60 then
		Log("ledge found, but you are moving away from it - no grab")
		return
	end

	ply._BRZClimbJumpWindow = nil

	StartGrab(ply, mv, ledge, CT, jumpWindow)
end)

-- Reset on death/spawn so a ragdoll or respawn never leaves a player stuck mid-climb
local function ResetOnEntity(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end
	ClearClimbState(ply)
	ply._BRZClimbCooldown = 0
end

hook.Add("PlayerDeath", "BeatrunZCity_ClimbReset", ResetOnEntity)
hook.Add("PlayerSpawn", "BeatrunZCity_ClimbReset", ResetOnEntity)

-- Public helpers (debug panel / other addons)
function BeatrunZCityIsClimbing(ply)
	return IsValid(ply) and ply:GetBRZClimbState() ~= STATE_NONE
end
