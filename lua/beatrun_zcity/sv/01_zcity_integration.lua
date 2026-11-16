-- Server-side cleanup & Z-City Big Appearance short-sleeve hands compatibility.
-- Never wraps or modifies Z-City or Big Appearance files directly.

local SHORT_SLEEVE_PATTERNS = {
	"tshirt", "t_shirt", "t%-shirt", "shortsleeve", "short_sleeve", "short%-sleeve",
	"short", "sleeveless", "tanktop", "tank_top", "tank%-top",
	"topless", "shirtless", "naked", "polo"
}

local function NameLooksShortSleeve(name)
	if not isstring(name) or name == "" then return false end
	local low = string.lower(name)
	for _, pat in ipairs(SHORT_SLEEVE_PATTERNS) do
		if string.find(low, pat) then return true end
	end
	if low == "tee" or string.find(low, "_tee", 1, true) or string.find(low, "tee_", 1, true) then
		return true
	end
	return false
end

local function InspectShortSleeveHands(ply)
	if not (IsValid(ply) and ply.GetBodyGroups and ply.GetBodygroup) then return nil end

	local groups = ply:GetBodyGroups()
	if not istable(groups) or #groups == 0 then return nil end

	local handsGroup, bareIdx, armsIdx
	local shortSleeves = false
	local sigParts = { ply:GetModel() or "" }

	for _, g in ipairs(groups) do
		local val = ply:GetBodygroup(g.id) or 0
		sigParts[#sigParts + 1] = tostring(g.id) .. ":" .. tostring(val)

		local gname = isstring(g.name) and string.lower(g.name) or ""
		if gname == "hands" then
			handsGroup = g
		elseif istable(g.submodels) and not shortSleeves then
			local subName = g.submodels[val]
			if NameLooksShortSleeve(subName) then
				shortSleeves = true
			end
		end
	end

	if not shortSleeves and istable(ZCGloves) and isfunction(ZCGloves.ShortSleevesByName) then
		local ok, res = pcall(ZCGloves.ShortSleevesByName, ply)
		if ok and res then shortSleeves = true end
	end

	if not handsGroup or not istable(handsGroup.submodels) then
		return nil, table.concat(sigParts, "|")
	end

	if istable(ZCGloves) and isfunction(ZCGloves.ArmsPart) then
		local ok, idx = pcall(ZCGloves.ArmsPart, handsGroup)
		if ok and isnumber(idx) then armsIdx = idx end
	end
	if istable(ZCGloves) and isfunction(ZCGloves.BarePart) then
		local ok, idx = pcall(ZCGloves.BarePart, handsGroup)
		if ok and isnumber(idx) then bareIdx = idx end
	end

	if not armsIdx or not bareIdx then
		for idx, subName in pairs(handsGroup.submodels) do
			if isnumber(idx) and isstring(subName) then
				local low = string.lower(subName)
				if not armsIdx and (string.find(low, "tshirt", 1, true) or string.find(low, "shortsleeve", 1, true) or string.find(low, "short_sleeve", 1, true)) then
					armsIdx = idx
				elseif not bareIdx and string.find(low, "hand", 1, true)
					and not string.find(low, "tshirt", 1, true)
					and not string.find(low, "short", 1, true)
					and not string.find(low, "glove", 1, true)
					and not string.find(low, "skilet", 1, true)
					and not string.find(low, "medic", 1, true)
					and not string.find(low, "robot", 1, true) then
					bareIdx = idx
				end
			end
		end
	end

	return {
		groupId = handsGroup.id,
		cur = ply:GetBodygroup(handsGroup.id) or 0,
		bareIdx = bareIdx,
		armsIdx = armsIdx,
		shortSleeves = shortSleeves
	}, table.concat(sigParts, "|")
end

-- Legacy Big Appearance models (models/zcity*, models/zcityadodser*) store bare arms for T-shirts
-- in the HANDS bodygroup ("handsfortshirt") rather than in TORSO. When a player wears a short-sleeve
-- TORSO with HANDS=0 ("hands") — either because they chose None or because ZCG.FixBodygroups skipped
-- them due to PlayerModels path collisions / mutated CurAppearance — their bare arms vanish completely.
local function EnsureShortSleeveHandsBodygroup(ply, force)
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return end
	if IsValid(ply.FakeRagdoll) then return end
	if not (hg ~= nil or ZCGloves ~= nil) then return end

	local info, sig = InspectShortSleeveHands(ply)
	if not force and sig and ply._BRZAppBgSig == sig then return end
	ply._BRZAppBgSig = sig

	if not info or info.armsIdx == nil or info.bareIdx == nil then return end

	if info.shortSleeves then
		if info.cur == info.bareIdx then
			ply:SetBodygroup(info.groupId, info.armsIdx)
			ply._BRZAutoTShirtHands = true
			ply._BRZAppBgSig = nil
		end
	elseif ply._BRZAutoTShirtHands and info.cur == info.armsIdx then
		local explicitChoice = istable(ply.CurAppearance)
			and istable(ply.CurAppearance.ABodygroups)
			and ply.CurAppearance.ABodygroups.HANDS
		local wantsTShirtHands = isstring(explicitChoice) and string.find(string.lower(explicitChoice), "t%-shirt") ~= nil
		if not wantsTShirtHands then
			ply:SetBodygroup(info.groupId, info.bareIdx)
			ply._BRZAppBgSig = nil
		end
		ply._BRZAutoTShirtHands = nil
	end
end

hook.Add("PlayerDeath", "BeatrunZCity_ResetOnDeath", function(ply)
	BeatrunResetSlideRollState(ply)
	if IsValid(ply) then
		ply._BRZAppBgSig = nil
		ply._BRZAutoTShirtHands = nil
	end
end)

hook.Add("PlayerSilentDeath", "BeatrunZCity_ResetOnSilentDeath", function(ply)
	BeatrunResetSlideRollState(ply)
	if IsValid(ply) then
		ply._BRZAppBgSig = nil
		ply._BRZAutoTShirtHands = nil
	end
end)

hook.Add("PlayerSpawn", "BeatrunZCity_ResetOnSpawn", function(ply)
	BeatrunResetSlideRollState(ply)
	if IsValid(ply) then
		ply._BRZAppBgSig = nil
		ply._BRZAutoTShirtHands = nil
		timer.Simple(0.15, function()
			if IsValid(ply) then EnsureShortSleeveHandsBodygroup(ply, true) end
		end)
	end
end)

hook.Add("PlayerPostThink", "BeatrunZCity_CleanupFakeRagdoll", function(ply)
	if not IsValid(ply) then return end
	local active = (ply.GetSliding and ply:GetSliding()) or (ply.GetSafetyRollTime and ply:GetSafetyRollTime() > CurTime())
	if active and not BeatrunCanSlideOrRoll(ply) then
		BeatrunResetSlideRollState(ply)
	end

	-- Throttled lightweight check (4 Hz) so changing appearance/T-shirt mid-round heals bare arms
	-- immediately without scanning bodygroups every server tick.
	local now = CurTime()
	if (ply._BRZNextAppBgCheck or 0) <= now then
		ply._BRZNextAppBgCheck = now + 0.25
		EnsureShortSleeveHandsBodygroup(ply, false)
	end
end)
