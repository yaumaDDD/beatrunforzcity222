-- Beatrun non-colliding client viewpunch (used only during Slide & Safety Roll BodyAnim)

local PLAYER = FindMetaTable("Player")
local math_Approach = math.Approach

local function BeatrunApproachVec(vec, target, step)
	vec.x = math_Approach(vec.x, target.x, step)
	vec.y = math_Approach(vec.y, target.y, step)
	vec.z = math_Approach(vec.z, target.z, step)
end

local ViewPunch_Angles = Angle(0, 0, 0)
local ViewPunch_Velocity = Vector(0, 0, 0)
local SmoothViewPunch_Angles = Angle(0, 0, 0)
local SmoothViewPunch_Vel = Vector(0, 0, 0)

function PLAYER:CLViewPunch(ang)
	if not isangle(ang) then return end
	local cv = GetConVar("Beatrun_SlideCamTilt")
	if cv and not cv:GetBool() then return end

	ViewPunch_Velocity.x = ViewPunch_Velocity.x + ang.p * 8
	ViewPunch_Velocity.y = ViewPunch_Velocity.y + ang.y * 8
	ViewPunch_Velocity.z = ViewPunch_Velocity.z + ang.r * 8

	SmoothViewPunch_Vel.x = SmoothViewPunch_Vel.x + ang.p * 4
	SmoothViewPunch_Vel.y = SmoothViewPunch_Vel.y + ang.y * 4
	SmoothViewPunch_Vel.z = SmoothViewPunch_Vel.z + ang.r * 4
end

function PLAYER:GetCLViewPunchAngles()
	return ViewPunch_Angles
end

function PLAYER:GetSmoothViewPunchAngles()
	return SmoothViewPunch_Angles
end

hook.Add("Think", "BeatrunZCity_CLViewPunch", function()
	local dt = math.min(FrameTime(), 0.05)
	if dt <= 0 then return end

	local vDecay = dt * 60
	ViewPunch_Angles.p = math_Approach(ViewPunch_Angles.p + ViewPunch_Velocity.x * dt, 0, math.abs(ViewPunch_Angles.p) * dt * 10 + 0.01)
	ViewPunch_Angles.y = math_Approach(ViewPunch_Angles.y + ViewPunch_Velocity.y * dt, 0, math.abs(ViewPunch_Angles.y) * dt * 10 + 0.01)
	ViewPunch_Angles.r = math_Approach(ViewPunch_Angles.r + ViewPunch_Velocity.z * dt, 0, math.abs(ViewPunch_Angles.r) * dt * 10 + 0.01)
	BeatrunApproachVec(ViewPunch_Velocity, vector_origin, ViewPunch_Velocity:Length() * dt * 12 + vDecay * 0.25)

	SmoothViewPunch_Angles.p = math_Approach(SmoothViewPunch_Angles.p + SmoothViewPunch_Vel.x * dt, 0, math.abs(SmoothViewPunch_Angles.p) * dt * 6 + 0.01)
	SmoothViewPunch_Angles.y = math_Approach(SmoothViewPunch_Angles.y + SmoothViewPunch_Vel.y * dt, 0, math.abs(SmoothViewPunch_Angles.y) * dt * 6 + 0.01)
	SmoothViewPunch_Angles.r = math_Approach(SmoothViewPunch_Angles.r + SmoothViewPunch_Vel.z * dt, 0, math.abs(SmoothViewPunch_Angles.r) * dt * 6 + 0.01)
	BeatrunApproachVec(SmoothViewPunch_Vel, vector_origin, SmoothViewPunch_Vel:Length() * dt * 8 + vDecay * 0.15)
end)
