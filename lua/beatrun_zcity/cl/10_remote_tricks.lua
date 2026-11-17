-- Other players' tricks (2.21.35).
--
-- Until now every animation lived only on the owning client: the trick body is a ClientsideModel, so
-- nobody else could see your slide, your roll or your ledge climb. This file rebuilds those tricks on
-- the clients of everyone else.
--
-- Nothing is streamed over the network. The server sends only the pose name, how long it is played,
-- its playback speed and how it is played (oneshot / loop / freeze) - see BeatrunZCBroadcastTrick in
-- sh/02_helpers.lua. Each receiving client:
--   * creates the same animation rig (models/new_climbanim.mdl or old_climbanim.mdl),
--   * creates a copy of that player's own model, parented to the rig with EF_BONEMERGE, so the player's
--     skin/bodygroups/colour are used and the body follows the rig's bones exactly like the local one,
--   * drives the rig's cycle itself (the pose is fully deterministic from the sent timing),
--   * hides the player's static model for as long as the trick lasts and puts it back afterwards.

local MODE_ONESHOT, MODE_LOOP, MODE_FREEZE = 0, 1, 2

-- [Player] = { rig, body, rigModel, anim, seqDur, start, dur, speed, mode }
local remote = {}

local cvAnimSet = GetConVar("Beatrun_AnimSet")

local function RigModel()
	if cvAnimSet and cvAnimSet:GetInt() == 1 then return "models/old_climbanim.mdl" end
	return "models/new_climbanim.mdl"
end

local function RestorePlayerRender(ply)
	if not IsValid(ply) then return end
	if ply._BRZRemoteTrickRender == nil then return end

	-- false means "there was no RenderOverride at all" - put back nil, not a false function
	ply.RenderOverride = ply._BRZRemoteTrickRender ~= false and ply._BRZRemoteTrickRender or nil
	ply._BRZRemoteTrickRender = nil
end

local function Clear(ply)
	local t = remote[ply]
	if not t then return end
	remote[ply] = nil

	if IsValid(t.rig) then t.rig:Remove() end
	if IsValid(t.body) then t.body:Remove() end

	RestorePlayerRender(ply)
end

local function Build(ply)
	local rigName = RigModel()
	local t = remote[ply]

	if t and IsValid(t.rig) and t.rigModel == rigName then return t end
	if t then Clear(ply) end

	local rig = ClientsideModel(rigName, RENDERGROUP_BOTH)
	if not IsValid(rig) then return nil end

	rig:SetNoDraw(true)
	rig:SetPos(ply:GetPos())
	rig:SetAngles(Angle(0, ply:EyeAngles().y, 0))

	local mdl = ply:GetModel()
	if not mdl or mdl == "" then mdl = "models/player/kleiner.mdl" end

	local body = ClientsideModel(mdl, RENDERGROUP_BOTH)
	if IsValid(body) then
		body:SetParent(rig)
		body:AddEffects(EF_BONEMERGE)
		body:SetNoDraw(true)

		-- Same look as the player himself: skin, bodygroups, scale, colour, material.
		pcall(function()
			body:SetSkin(ply:GetSkin())
			body:SetModelScale(ply:GetModelScale(), 0)
			body:SetColor(ply:GetColor())
			body:SetMaterial(ply:GetMaterial())
		end)

		local groups = ply:GetBodyGroups()
		if istable(groups) then
			for i = 1, #groups do
				local g = groups[i]
				if istable(g) and isnumber(g.id) then
					local value = ply:GetBodygroup(g.id)
					if isnumber(value) then
						pcall(body.SetBodygroup, body, g.id, value)
					end
				end
			end
		end
	end

	-- Hide the player's own model (Z-City draws him through a per-entity RenderOverride, so that is the
	-- one that has to be taken over; it is put back exactly as it was when the trick ends).
	ply._BRZRemoteTrickRender = ply.RenderOverride or false
	ply.RenderOverride = function() end

	remote[ply] = { rig = rig, body = body, rigModel = rigName }
	return remote[ply]
end

local function Play(ply, anim, dur, speed, mode)
	if not IsValid(ply) or not ply:Alive() then return end
	if not isstring(anim) or anim == "" then return end

	local t = Build(ply)
	if not t or not IsValid(t.rig) then return end

	local rig = t.rig
	local seq = rig:LookupSequence(anim)
	if not seq or seq < 0 then return end

	local seqDur = rig:SequenceDuration()
	if not isnumber(seqDur) or seqDur <= 0 then seqDur = 1 end

	rig:ResetSequence(seq)
	rig:SetCycle(0)
	rig:SetPlaybackRate(0) -- the cycle is driven from the sent timing, not by the engine

	t.anim = anim
	t.seqDur = seqDur
	t.speed = math.max(0.05, tonumber(speed) or 1)
	t.mode = tonumber(mode) or MODE_ONESHOT

	local d = tonumber(dur) or 0
	if t.mode == MODE_LOOP or d <= 0 then
		t.dur = seqDur / t.speed
	else
		t.dur = d
	end

	t.start = CurTime()
end

net.Receive("Beatrun_ZC_RemoteTrick", function()
	local ply = net.ReadEntity()
	local anim = net.ReadString()
	local dur = net.ReadFloat()
	local speed = net.ReadFloat()
	local mode = net.ReadUInt(2)

	-- The owner builds his own animation through the normal (local) pipeline.
	if not IsValid(ply) or ply == LocalPlayer() then return end

	if anim == "" then
		Clear(ply)
	else
		Play(ply, anim, dur, speed, mode)
	end
end)

hook.Add("Think", "BeatrunZCity_RemoteTricks", function()
	if next(remote) == nil then return end

	local now = CurTime()
	local actions = {}

	for ply, t in pairs(remote) do
		-- A looping pose is ended by its stop message. As a safety net the loop is also dropped when the
		-- player is clearly not sliding any more (or after 20 s), so a missed message cannot leave a
		-- player looping a slide animation on somebody else's screen forever.
		local running = now - (t.start or now)
		local loopStale = (t.mode == MODE_LOOP) and (running > 20 or
			(isfunction(ply.GetSliding) and not ply:GetSliding()))

		if not IsValid(ply) or not IsValid(t.rig) or not ply:Alive() or ply:InVehicle() or loopStale then
			actions[#actions + 1] = { ply = ply, clear = true }
		else
			local frac = ((now - (t.start or now)) / math.max(0.05, t.dur or 1)) * (t.speed or 1)

			local cycle
			if t.mode == MODE_LOOP then
				cycle = frac % 1
			elseif t.mode == MODE_FREEZE then
				cycle = 0.999
			else
				cycle = math.Clamp(frac, 0, 1)
			end

			t.rig:SetPos(ply:GetPos())
			t.rig:SetAngles(Angle(0, ply:EyeAngles().y, 0))
			t.rig:SetCycle(cycle)
			t.rig:SetupBones()

			if t.mode == MODE_ONESHOT and frac >= 1 then
				if t.anim == "hanghardstart" or t.anim == "hanghardstart2" then
					-- The grab animation is over, the player keeps hanging until the pull-up arrives.
					actions[#actions + 1] = { ply = ply, nextAnim = "hangpose" }
				else
					actions[#actions + 1] = { ply = ply, clear = true }
				end
			end
		end
	end

	-- Applied after the traversal: Play/Clear touch `remote`, which must not happen mid-iteration.
	for i = 1, #actions do
		local a = actions[i]
		if a.clear then
			Clear(a.ply)
		elseif a.nextAnim then
			Play(a.ply, a.nextAnim, 0, 1, MODE_FREEZE)
		end
	end
end)

-- The body copy is drawn by us (exactly like the local trick body), so it is always in the right pass.
hook.Add("PostDrawOpaqueRenderables", "BeatrunZCity_RemoteTricksDraw", function(bDrawingDepth, bDrawingSkybox)
	if bDrawingSkybox or next(remote) == nil then return end

	for ply, t in pairs(remote) do
		if IsValid(t.body) then
			t.body:DrawModel()
		end
	end
end)

-- Second net, in case Z-City re-assigns the player's RenderOverride during its own draw pass.
hook.Add("PrePlayerDraw", "BeatrunZCity_RemoteTrickHide", function(ply)
	if remote[ply] ~= nil then return true end
end)

hook.Add("PlayerDisconnected", "BeatrunZCity_RemoteTricksCleanup", function(ply)
	Clear(ply)
end)
