-- Compatibility layer for Z-City Big Appearance / Appearance Mod + zcity_csgo_gloves (ZCGloves).
-- Standalone: never modifies Z-City or Big Appearance files on disk.
--
-- Fixes the missing-hands / collapsed-forearm bugs with gloves & jackets:
--   1. Clean submaterial copying (0..31) that never copies ZCGloves' hide material ("null" /
--      "zcity_csgo_gloves/invisible") from ply onto BodyAnimMDL / BodyAnimMDLarm, restoring the
--      real pre-hide material from ZCGloves.States instead (while preserving Z-City's uppercase
--      "NULL" used by ent_zcity_equipment_base for armor).
--   2. Live per-frame sync of skin, bodygroups (sheet / TORSO / HANDS including handsfortshirt),
--      zcg_glove, organism, and submaterials onto BodyAnimMDL / BodyAnimMDLarm, clearing stale
--      glove hide slots immediately whenever the jacket or glove changes.
--   3. Orphan "null" sanitization: if a hand slot still carries ZCGloves' hide material without
--      being tracked in ZCGloves.States[ent] (or when a short-sleeve / shared-slot jacket or stock
--      Z-City glove is worn, or on the first notReady frame), the slot is restored immediately.
--   4. Non-finger forearm helper bone protection: on Appearance Mod models (models/slav/...),
--      helper bones under ValveBiped.Bip01_L/R_Hand carry the forearm mesh. When ZCGloves shrinks
--      hand bones on a non-T-shirt jacket (e.g. SlotShared or unreadable mesh), non-finger helper
--      bones are restored right before DrawModel() and growHands' sentinel is kept intact so all
--      shrunk fingers are still restored in PostDrawAppearance.
--   5. Safe ZCG-only hook runner for BodyAnimMDLarm (Beatrun_ZCity_SlideWeapon 0) so CS:GO gloves
--      render on the right hand without drawing floating chest armor.

BeatrunZCityAppCompat = BeatrunZCityAppCompat or {}
local AppCompat = BeatrunZCityAppCompat

local handOrFingerCache = {}
local wrappedZCGOrig = nil
local wrappedZCGFunc = nil
local wrapAttempts = 0
local wrapDone = false

local function GetHookSubTable(eventName)
	local t
	if isfunction(hook.GetTable) then
		local ok, tbl = pcall(hook.GetTable)
		if ok and istable(tbl) then t = tbl[eventName] end
	end
	if not t and istable(_G.Hooks) then t = _G.Hooks[eventName] end
	return istable(t) and t or nil
end

function AppCompat.IsActive()
	return istable(ZCGloves) and isfunction(ZCGloves.HideMaterial)
end

function AppCompat.GetHideMaterial()
	if istable(ZCGloves) and isfunction(ZCGloves.HideMaterial) then
		local ok, mat = pcall(ZCGloves.HideMaterial)
		if ok and isstring(mat) and mat ~= "" then return mat end
	end
	return "null"
end

-- Case-sensitive match for ZCGloves' hide material only. Z-City's ent_zcity_equipment_base uses
-- uppercase "NULL" to hide jackets under armor, so "NULL" is preserved unless Config explicitly
-- sets HideMaterial = "NULL".
function AppCompat.IsHideMaterial(sub)
	if not isstring(sub) or sub == "" then return false end
	local hideMat = AppCompat.GetHideMaterial()
	return sub == hideMat or sub == "null" or sub == "zcity_csgo_gloves/invisible"
end

local function IsSlotTrackedByZCG(state, slot)
	if not istable(state) then return false end
	if istable(state.hide) and state.hide.slot == slot then return true end
	if istable(state.more) and state.more[slot] ~= nil then return true end
	return false
end

local function SafeBoolCall(fn, ...)
	if not isfunction(fn) then return false end
	local ok, res = pcall(fn, ...)
	return ok and res and true or false
end

local function SafeCall(fn, ...)
	if not isfunction(fn) then return nil end
	local ok, res = pcall(fn, ...)
	return ok and res or nil
end

-- Returns the real visible submaterial for slot (0..31) on src, unwrapping ZCGloves' hide material
-- back to the saved pre-hide material (or "" for default).
function AppCompat.GetCleanSubMaterial(src, slot)
	if not IsValid(src) or not isnumber(slot) or slot < 0 or slot > 31 then return "" end

	local sub = src:GetSubMaterial(slot) or ""
	local state = istable(ZCGloves) and istable(ZCGloves.States) and ZCGloves.States[src] or nil

	if istable(state) then
		if istable(state.hide) and state.hide.slot == slot then
			local old = state.hide.old
			if isstring(old) and not AppCompat.IsHideMaterial(old) then return old end
			return ""
		end
		if istable(state.more) and state.more[slot] ~= nil then
			local old = state.more[slot]
			if isstring(old) and not AppCompat.IsHideMaterial(old) then return old end
			return ""
		end
	end

	if AppCompat.IsHideMaterial(sub) then
		return ""
	end

	return sub
end

local function RestoreTrackedSlot(ent, state, slot)
	if not istable(state) then return false end

	if istable(state.hide) and state.hide.slot == slot then
		local old = state.hide.old
		state.hide = nil
		if isstring(old) and old ~= "" and not AppCompat.IsHideMaterial(old) then
			ent:SetSubMaterial(slot, old)
		else
			ent:SetSubMaterial(slot, nil)
		end
		if istable(ent.zcg_hidden_slots) then ent.zcg_hidden_slots[slot] = nil end
		return true
	end

	if istable(state.more) and state.more[slot] ~= nil then
		local old = state.more[slot]
		state.more[slot] = nil
		if next(state.more) == nil then state.more = nil end
		if isstring(old) and old ~= "" and not AppCompat.IsHideMaterial(old) then
			ent:SetSubMaterial(slot, old)
		else
			ent:SetSubMaterial(slot, nil)
		end
		if istable(ent.zcg_hidden_slots) then ent.zcg_hidden_slots[slot] = nil end
		return true
	end

	return false
end

local function CollectHandSlots(ent, state)
	local slots = {}

	if istable(ent.zcg_hidden_slots) then
		for slot in pairs(ent.zcg_hidden_slots) do
			if isnumber(slot) and slot >= 0 and slot <= 31 then
				slots[slot] = true
			end
		end
	end

	if istable(state) then
		if istable(state.hide) and isnumber(state.hide.slot) and state.hide.slot >= 0 and state.hide.slot <= 31 then
			slots[state.hide.slot] = true
		end
		if istable(state.more) then
			for slot in pairs(state.more) do
				if isnumber(slot) and slot >= 0 and slot <= 31 then
					slots[slot] = true
				end
			end
		end
	end

	if istable(ZCGloves) then
		local mainSlot = SafeCall(ZCGloves.HandsSlot, ent)
		if isnumber(mainSlot) and mainSlot >= 0 and mainSlot <= 31 then
			slots[mainSlot] = true
		end

		local moreSlots = SafeCall(ZCGloves.HandSlots, ent)
		if istable(moreSlots) then
			for _, slot in ipairs(moreSlots) do
				if isnumber(slot) and slot >= 0 and slot <= 31 then
					slots[slot] = true
				end
			end
		end
	end

	return slots
end

-- Clears orphaned ZCGloves hide materials on hand slots of ent.
-- Never touches non-hand slots (so armor HideSubMaterails on jackets stay intact).
-- When forceInvalid is true (e.g. after jacket/bodygroup change or restoring ply after a slide),
-- also restores tracked slots if the current jacket/glove should not hide hand materials.
function AppCompat.SanitizeOrphanHiddenSlots(ent, forceInvalid)
	if not IsValid(ent) or not AppCompat.IsActive() then return 0 end

	local state = istable(ZCGloves.States) and ZCGloves.States[ent] or nil
	local slots = CollectHandSlots(ent, state)
	if next(slots) == nil then return 0 end

	local shouldNotHideAny = false
	if forceInvalid then
		local variant = SafeCall(ZCGloves.GloveOf, ent)
		if not variant
			or SafeBoolCall(ZCGloves.StockGlove, ent)
			or SafeBoolCall(ZCGloves.ShortSleevesByName, ent) then
			shouldNotHideAny = true
		end
	elseif istable(state) then
		if not state.variant or not state.drawn then
			shouldNotHideAny = true
		elseif SafeBoolCall(ZCGloves.ShortSleevesByName, ent)
			or SafeBoolCall(ZCGloves.StockGlove, ent) then
			shouldNotHideAny = true
		end
	end

	local restored = 0
	for slot in pairs(slots) do
		local cur = ent:GetSubMaterial(slot) or ""
		if AppCompat.IsHideMaterial(cur) then
			local tracked = IsSlotTrackedByZCG(state, slot)
			local slotShared = false
			if tracked and forceInvalid and not shouldNotHideAny then
				slotShared = SafeBoolCall(ZCGloves.SlotShared, ent, slot)
			end

			if not tracked then
				ent:SetSubMaterial(slot, nil)
				if istable(ent.zcg_hidden_slots) then ent.zcg_hidden_slots[slot] = nil end
				restored = restored + 1
			elseif shouldNotHideAny or slotShared then
				if RestoreTrackedSlot(ent, state, slot) then
					restored = restored + 1
				end
			end
		elseif istable(ent.zcg_hidden_slots) and ent.zcg_hidden_slots[slot] and not IsSlotTrackedByZCG(state, slot) then
			ent.zcg_hidden_slots[slot] = nil
		end
	end

	return restored
end

local function IsHandOrFingerBone(ent, modelKey, bone)
	local cache = handOrFingerCache[modelKey]
	if not cache then
		cache = {}
		handOrFingerCache[modelKey] = cache
	end

	local cached = cache[bone]
	if cached ~= nil then return cached end

	local name = ent:GetBoneName(bone)
	if not isstring(name) then
		cache[bone] = true
		return true
	end

	local low = string.lower(name)
	local ok = (low == "valvebiped.bip01_l_hand"
		or low == "valvebiped.bip01_r_hand"
		or string.find(low, "finger", 1, true) ~= nil)
	cache[bone] = ok
	return ok
end

-- Restores any non-finger helper bone below L/R_Hand that ZCGloves' shrinkHands shrank this frame.
-- Keeps growHands' sentinel bone (entry.bone) pointing at a real shrunk hand/finger bone so
-- PostDrawAppearance still restores all fingers after DrawModel().
function AppCompat.ProtectNonFingerArmBones(ent)
	if not IsValid(ent) or not istable(ZCGloves) or not istable(ZCGloves.States) then return 0 end

	local state = ZCGloves.States[ent]
	if not istable(state) or not state.shrunk then return 0 end

	local saved = state.bones
	if not istable(saved) or (saved.n or 0) <= 0 or saved.frame ~= FrameNumber() then return 0 end

	local model = ent:GetModel()
	if not isstring(model) or model == "" then return 0 end
	local modelKey = string.lower(model)
	local count = ent:GetBoneCount() or 0

	local restored = 0
	local restoredBones = nil

	for i = 1, saved.n, 2 do
		local bone = saved[i]
		local origMat = saved[i + 1]
		if isnumber(bone) and bone >= 0 and bone < count and origMat then
			if not IsHandOrFingerBone(ent, modelKey, bone) then
				ent:SetBoneMatrix(bone, origMat)
				restored = restored + 1
				restoredBones = restoredBones or {}
				restoredBones[bone] = true
			end
		end
	end

	if restored > 0 and istable(saved.hands) then
		for k = 1, saved.count or 0 do
			local entry = saved.hands[k]
			if istable(entry) and restoredBones[entry.bone] then
				local newMark, newLimit = nil, nil
				for i = entry.first or 1, entry.last or 0, 2 do
					local b = saved[i]
					local m = saved[i + 1]
					if isnumber(b) and m and not restoredBones[b] then
						newMark = b
						newLimit = m:GetScale().x * 0.5
						break
					end
				end
				if newMark then
					entry.bone = newMark
					entry.limit = newLimit
				end
			end
		end
	end

	return restored
end

-- Copies skin, bodygroups, player color, and clean submaterials (0..31, never ZCGloves "null")
-- from src onto dst. Safe for both initial setup and live per-frame sync.
function AppCompat.SyncTrickModelAppearance(src, dst, isPlayerModel, initial)
	if not IsValid(src) or not IsValid(dst) then return false end

	if initial and src.GetPlayerColor then
		dst.GetPlayerColor = function()
			return IsValid(src) and src:GetPlayerColor() or vector_origin
		end
	end

	local sameModel = (src:GetModel() == dst:GetModel())
	local bgChanged = false

	if sameModel then
		local skin = src:GetSkin() or 0
		if dst:GetSkin() ~= skin then
			dst:SetSkin(skin)
		end

		local bgs = src:GetBodyGroups()
		if istable(bgs) then
			for _, bg in ipairs(bgs) do
				local val = src:GetBodygroup(bg.id) or 0
				if dst:GetBodygroup(bg.id) ~= val then
					dst:SetBodygroup(bg.id, val)
					bgChanged = true
				end
			end
		end
	end

	if isPlayerModel then
		local zcgID = src:GetNWString("zcg_glove", "")
		if dst:GetNWString("zcg_glove", "") ~= zcgID then
			dst:SetNWString("zcg_glove", zcgID)
			bgChanged = true
		end
		dst.organism = src.organism
		dst.new_organism = src.new_organism
		dst.CurAppearance = src.CurAppearance
	elseif initial then
		dst:SetNWString("zcg_glove", "")
	end

	if bgChanged and not initial and AppCompat.IsActive() then
		AppCompat.SanitizeOrphanHiddenSlots(dst, true)
	end

	if sameModel then
		local dstState = istable(ZCGloves) and istable(ZCGloves.States) and ZCGloves.States[dst] or nil

		for i = 0, 31 do
			local clean = AppCompat.GetCleanSubMaterial(src, i)

			if not initial and istable(dstState) and istable(dstState.hide) and dstState.hide.slot == i then
				dstState.hide.old = clean
			elseif not initial and istable(dstState) and istable(dstState.more) and dstState.more[i] ~= nil then
				dstState.more[i] = clean
			else
				local cur = dst:GetSubMaterial(i) or ""
				if cur ~= clean then
					dst:SetSubMaterial(i, clean ~= "" and clean or nil)
				end
			end
		end
	end

	return bgChanged
end

function AppCompat.CopyCleanAppearance(src, dst, isPlayerModel)
	return AppCompat.SyncTrickModelAppearance(src, dst, isPlayerModel, true)
end

-- Non-invasive wrapper around ZCGloves' CoolPostDrawAppearance hook so orphan "null" slots and
-- Appearance Mod non-finger forearm helper bones are also protected on ply & ragdolls outside slides.
function AppCompat.TryWrapZCGHook()
	if not AppCompat.IsActive() then return false end

	local tbl = GetHookSubTable("CoolPostDrawAppearance")
	if not tbl then return false end

	local cur = tbl["zcg_gloves"]
	if not isfunction(cur) then return false end
	if cur == wrappedZCGFunc then
		BeatrunZCityZCGCompatWrapped = true
		return true
	end

	wrappedZCGOrig = cur
	wrappedZCGFunc = function(ent, owner, ...)
		if IsValid(ent) then
			AppCompat.SanitizeOrphanHiddenSlots(ent, false)
		end

		local ok, a, b, c = pcall(wrappedZCGOrig, ent, owner, ...)

		if IsValid(ent) then
			AppCompat.ProtectNonFingerArmBones(ent)
			local state = istable(ZCGloves) and istable(ZCGloves.States) and ZCGloves.States[ent] or nil
			if not state or not state.drawn or not state.variant then
				AppCompat.SanitizeOrphanHiddenSlots(ent, false)
			end
		end

		if ok then return a, b, c end
	end

	-- Re-register via hook.Add preserving ZCGloves' exact HookOrder so standard GMod, ULib and
	-- Srlion's hook library all dispatch the wrapper in the same priority slot.
	local order = istable(ZCGloves.HookOrder) and ZCGloves.HookOrder.draw or nil
	local registered = false
	if isnumber(order) and pcall(hook.Add, "CoolPostDrawAppearance", "zcg_gloves", wrappedZCGFunc, order) then
		local afterTbl = GetHookSubTable("CoolPostDrawAppearance")
		registered = istable(afterTbl) and afterTbl["zcg_gloves"] == wrappedZCGFunc
	end
	if not registered then
		pcall(hook.Add, "CoolPostDrawAppearance", "zcg_gloves", wrappedZCGFunc)
		local afterTbl = GetHookSubTable("CoolPostDrawAppearance")
		if istable(afterTbl) and afterTbl["zcg_gloves"] ~= wrappedZCGFunc then
			afterTbl["zcg_gloves"] = wrappedZCGFunc
		end
	end

	BeatrunZCityZCGCompatWrapped = true
	return true
end

-- Runs ONLY ZCGloves' draw/after hooks on an arm-only model (BodyAnimMDLarm when SlideWeapon 0),
-- avoiding zc_equipmentDraw (which would otherwise draw chest armor over a hidden torso).
function AppCompat.RunZCGDrawHookOnly(ent, ply)
	if not IsValid(ent) or not AppCompat.IsActive() then return end
	AppCompat.TryWrapZCGHook()

	local tbl = GetHookSubTable("CoolPostDrawAppearance")
	local fn = tbl and tbl["zcg_gloves"]
	if isfunction(fn) then
		if fn ~= wrappedZCGFunc then
			AppCompat.SanitizeOrphanHiddenSlots(ent, false)
		end
		pcall(fn, ent, ply)
		if fn ~= wrappedZCGFunc then
			AppCompat.ProtectNonFingerArmBones(ent)
		end
	end
end

function AppCompat.RunZCGAfterHookOnly(ent, ply)
	if not IsValid(ent) or not AppCompat.IsActive() then return end

	local tbl = GetHookSubTable("PostDrawAppearance")
	local fn = tbl and tbl["zcg_gloves"]
	if isfunction(fn) then
		pcall(fn, ent, ply)
	end
end

function AppCompat.GetDebugSummary(ply)
	if not AppCompat.IsActive() then return "inactive (ZCGloves not loaded)" end
	local jacket = IsValid(ply) and SafeCall(ZCGloves.JacketOf, ply) or nil
	local variant = IsValid(ply) and SafeCall(ZCGloves.GloveOf, ply) or nil
	local short = IsValid(ply) and SafeBoolCall(ZCGloves.ShortSleevesByName, ply) or false
	local stock = IsValid(ply) and SafeBoolCall(ZCGloves.StockGlove, ply) or false
	return string.format(
		"active | wrapped=%s | jacket=%s | glove=%s | shortSleeves=%s | stockGlove=%s",
		tostring(BeatrunZCityZCGCompatWrapped == true),
		tostring(jacket or "none"),
		tostring(istable(variant) and variant.id or "none"),
		tostring(short),
		tostring(stock)
	)
end

hook.Add("Think", "BeatrunZCity_WrapZCGCompat", function()
	wrapAttempts = wrapAttempts + 1
	if wrapAttempts % 15 == 1 then
		wrapDone = AppCompat.TryWrapZCGHook() or wrapDone
	end
	if wrapDone or wrapAttempts > 1200 then
		hook.Remove("Think", "BeatrunZCity_WrapZCGCompat")
	end
end)

hook.Add("InitPostEntity", "BeatrunZCity_WrapZCGCompat", function()
	if AppCompat.TryWrapZCGHook() then
		wrapDone = true
		hook.Remove("Think", "BeatrunZCity_WrapZCGCompat")
	end
end)

hook.Add("OnGamemodeLoaded", "BeatrunZCity_WrapZCGCompat", function()
	wrapAttempts = 0
	wrapDone = AppCompat.TryWrapZCGHook()
	if wrapDone then
		hook.Remove("Think", "BeatrunZCity_WrapZCGCompat")
	end
end)
