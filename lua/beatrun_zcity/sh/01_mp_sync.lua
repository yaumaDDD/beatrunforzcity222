-- Non-invasive state synchronization for Slide & Safety Roll using GMod NW2 + predicted local state.
-- Never calls Entity:NetworkVar on Player and never modifies Z-City DataTables or player classes.

local PLAYER = FindMetaTable("Player")

local VARS = {
	{ kind = "Bool", key = "BRZ_Sliding", name = "Sliding", default = false },
	{ kind = "Bool", key = "BRZ_SlidingSlippery", name = "SlidingSlippery", default = false },
	{ kind = "Bool", key = "BRZ_RollLoss", name = "RollLoss", default = false },
	-- true = this landing is the in-place knee landing ("land"), false = a real roll that carries you
	-- forward. A bool is needed because comparing two Angle objects never matches them.
	{ kind = "Bool", key = "BRZ_RollLand", name = "RollLand", default = false },

	{ kind = "Float", key = "BRZ_SlidingTime", name = "SlidingTime", default = 0 },
	{ kind = "Float", key = "BRZ_SlidingDelay", name = "SlidingDelay", default = 0 },
	{ kind = "Float", key = "BRZ_SlidingVel", name = "SlidingVel", default = 0 },
	{ kind = "Float", key = "BRZ_SlidingStrafe", name = "SlidingStrafe", default = 0 },
	-- 2.21.27: server = true. These two are the landing's identity and its clock, and only the server
	-- may write them. A client write used to live in _BRZPred for a while, so a client-side reset
	-- (SetSafetyRollTime(0)) hid the real value; when the server's number then came through, the client
	-- read that as a brand-new landing and replayed the pose (the double roll in the log).
	{ kind = "Float", key = "BRZ_SafetyRollKeyTime", name = "SafetyRollKeyTime", default = 0, server = true },
	{ kind = "Float", key = "BRZ_SafetyRollTime", name = "SafetyRollTime", default = 0, server = true },

	{ kind = "Vector", key = "BRZ_SlidingLastPos", name = "SlidingLastPos", default = vector_origin },

	{ kind = "Angle", key = "BRZ_SlidingAngle", name = "SlidingAngle", default = angle_zero },
	{ kind = "Angle", key = "BRZ_SafetyRollAng", name = "SafetyRollAng", default = angle_zero },
}

local KEY_TO_DEFAULT = {}
for _, v in ipairs(VARS) do
	KEY_TO_DEFAULT[v.key] = v.default
end

for _, v in ipairs(VARS) do
	local key = v.key
	local default = v.default
	local nwGet = "GetNW2" .. v.kind
	local nwSet = "SetNW2" .. v.kind
	local getter = "Get" .. v.name
	local setter = "Set" .. v.name

	PLAYER[getter] = function(self)
		if CLIENT and self == LocalPlayer() and self._BRZPred and self._BRZPred[key] ~= nil then
			return self._BRZPred[key]
		end
		if SERVER and self._BRZPred and self._BRZPred[key] ~= nil then
			return self._BRZPred[key]
		end
		return self[nwGet](self, key, default)
	end

	PLAYER[setter] = function(self, val)
		-- Server-authored values ignore client writes completely (see the server = true comment above).
		if v.server and CLIENT then return end
		self._BRZPred = self._BRZPred or {}
		self._BRZPred[key] = val
		if SERVER then
			self[nwSet](self, key, val)
		end
	end
end

if CLIENT then
	hook.Add("EntityNetworkedVarChanged", "BeatrunZCity_NW2Sync", function(ent, key, _, newval)
		if not IsValid(ent) or ent ~= LocalPlayer() then return end
		if KEY_TO_DEFAULT[key] == nil then return end
		ent._BRZPred = ent._BRZPred or {}
		ent._BRZPred[key] = newval
	end)
end

-- Safe ordered hook helper compatible with both vanilla GMod and Z-City's ULib/Srlion hook library
function BeatrunAddOrderedHook(event, name, func, priorityGlobal)
	local prio = priorityGlobal and rawget(_G, priorityGlobal) or nil
	if isnumber(prio) then
		local ok = pcall(hook.Add, event, name, func, prio)
		if ok then
			local hooks = hook.GetTable()
			if hooks and hooks[event] and hooks[event][name] ~= nil then
				return
			end
		end
	end
	hook.Add(event, name, func)
end

function BeatrunResetSlideRollState(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return end

	ply:SetSliding(false)
	ply:SetSlidingSlippery(false)
	ply:SetRollLoss(false)
	ply:SetRollLand(false)
	ply:SetSlidingTime(0)
	ply:SetSlidingDelay(0)
	ply:SetSlidingVel(0)
	ply:SetSlidingStrafe(0)
	ply:SetSafetyRollKeyTime(0)
	ply:SetSafetyRollTime(0)

	if SERVER and ply.SlideLoopSound then
		pcall(function() ply.SlideLoopSound:Stop() end)
		ply.SlideLoopSound = nil
	end

	if not IsValid(ply.FakeRagdoll) then
		if ply._BeatrunOrigDuckSpeed then
			ply:SetDuckSpeed(ply._BeatrunOrigDuckSpeed)
		end
		if ply._BeatrunOrigUnDuckSpeed then
			ply:SetUnDuckSpeed(ply._BeatrunOrigUnDuckSpeed)
		end
		if ply._BeatrunOrigViewOffsetDucked then
			ply:SetViewOffsetDucked(ply._BeatrunOrigViewOffsetDucked)
		end
		if ply._BeatrunOrigViewOffset then
			ply:SetViewOffset(ply._BeatrunOrigViewOffset)
		end
	end

	ply._BeatrunOrigDuckSpeed = nil
	ply._BeatrunOrigUnDuckSpeed = nil
	ply._BeatrunOrigViewOffsetDucked = nil
	ply._BeatrunOrigViewOffset = nil
	ply._BeatrunWasActiveMove = nil
	ply._BRZSlideMuzzlePos = nil
	ply._BRZSlideMuzzleDir = nil
	ply._BRZSlideMuzzleAng = nil
	ply._BRZSlideMuzzleTime = nil
end
