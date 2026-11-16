-- Shared helpers for Beatrun Slide & Safety Roll in Z-City

local cvOrganism = GetConVar("Beatrun_ZCity_OrganismImpact")
local cvStamina = GetConVar("Beatrun_ZCity_StaminaDrain")

-- Polyfill FastToTable if missing
function FastToTable(tbl)
	return istable(tbl) and tbl or {}
end

-- "thirdperson" is a console COMMAND in GMod, not a convar: looking it up as a convar spams
-- "Tried to look up command thirdperson as if it were a variable." every frame. Resolve it once and
-- only when no such command exists.
local cvGmodTp, cvGmodTpChecked
local function GmodThirdPerson()
	if not cvGmodTpChecked then
		cvGmodTpChecked = true
		local commands = concommand and concommand.GetTable and concommand.GetTable() or {}
		if not commands["thirdperson"] then
			local cv = GetConVar("thirdperson")
			if cv and cv.GetBool then cvGmodTp = cv end
		end
	end
	return cvGmodTp ~= nil and cvGmodTp:GetBool() or false
end

function BeatrunIsThirdPerson(ply)
	if not IsValid(ply) then return false end
	if CLIENT and ply == LocalPlayer() then
		if GetViewEntity and GetViewEntity() ~= ply then return true end
		if hg and hg.thirdperson and hg.thirdperson:GetBool() then return true end
		local cv = GetConVar("hg_thirdperson")
		if cv and cv:GetBool() then return true end
		if GmodThirdPerson() then return true end
	end
	return false
end

function BeatrunCanSlideOrRoll(ply)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
	if ply:InVehicle() or ply:GetMoveType() ~= MOVETYPE_WALK then return false end
	if ply:WaterLevel() >= 2 then return false end
	if IsValid(ply.FakeRagdoll) then return false end
	if ply:GetNWBool("Fake", false) then return false end

	if BeatrunHasOrganism(ply) and cvOrganism:GetBool() then
		local org = ply.organism
		if org.otrub then return false end
		if (org.immobilization or 0) > 15 then return false end
		if org.llegamputated or org.rlegamputated then return false end
	end

	return true
end

function BeatrunGetMobilityFactor(ply)
	if not BeatrunHasOrganism(ply) or not cvOrganism:GetBool() then return 1 end
	local org = ply.organism
	local factor = 1

	local lleg = org.lleg or 0
	local rleg = org.rleg or 0
	if lleg >= 1 or rleg >= 1 then
		factor = factor * 0.55
	elseif lleg >= 0.5 or rleg >= 0.5 then
		factor = factor * 0.8
	end

	local pain = org.pain or 0
	if pain > 40 then
		factor = factor * math.Clamp(1 - (pain - 40) / 140, 0.55, 1)
	end

	if org.stamina and org.stamina[1] then
		local stam = org.stamina[1]
		local maxStam = org.stamina.max or 100
		if maxStam > 0 and stam < maxStam * 0.2 then
			factor = factor * math.Clamp(0.65 + (stam / (maxStam * 0.2)) * 0.35, 0.65, 1)
		end
	end

	return math.Clamp(factor, 0.45, 1.15)
end

function BeatrunConsumeStamina(ply, amount)
	if not SERVER then return end
	if not cvStamina:GetBool() or not BeatrunHasOrganism(ply) then return end
	local org = ply.organism
	if not org.stamina or not org.stamina[1] then return end
	org.stamina[1] = math.max(0, org.stamina[1] - amount)
end

local standtr = {
	mask = MASK_PLAYERSOLID,
	collisiongroup = COLLISION_GROUP_PLAYER_MOVEMENT
}
local standtrout = {}
standtr.output = standtrout

function PlayerCannotStand(ply)
	if not IsValid(ply) then return false end
	local mins, maxs = ply:GetHull()
	local origin = ply:GetPos()
	standtr.start = origin
	standtr.endpos = origin
	standtr.mins = mins
	standtr.maxs = maxs
	standtr.filter = ply
	util.TraceHull(standtr)
	return standtrout.Hit
end

-- Event dispatcher used by Slide & SafetyRoll animations
if SERVER then
	function ParkourEvent(event, ply, clientOnly)
		if not IsValid(ply) then return end
		hook.Run("OnParkourEvent", event, ply)
		if not clientOnly and not game.SinglePlayer() then
			net.Start("Beatrun_ParkourEvent")
				net.WriteString(event)
				net.WriteEntity(ply)
			net.SendOmit(ply)
		end
	end
else
	function ParkourEvent(event, ply)
		hook.Run("OnParkourEvent", event, ply or LocalPlayer())
	end

	net.Receive("Beatrun_ParkourEvent", function()
		local event = net.ReadString()
		local ply = net.ReadEntity()
		if IsValid(ply) then
			hook.Run("OnParkourEvent", event, ply)
		end
	end)
end
