-- Admin-only replicated ConVar updater for Slide & Safety Roll menu

local ALLOWED_CONVARS = {
	["beatrun_zcity_slideenabled"] = true,
	["beatrun_zcity_rollenabled"] = true,
	["beatrun_zcity_slideminspeed"] = true,
	["beatrun_zcity_organismimpact"] = true,
	["beatrun_zcity_staminadrain"] = true,
	["beatrun_zcity_rollfallreduction"] = true,
	["beatrun_zcity_maxsaferollspeed"] = true,
	["beatrun_rollspeedloss"] = true,
	["beatrun_rollalways"] = true,
	["beatrun_zcity_slideautohold"] = true,
	["beatrun_zcity_slideaircheck"] = true,
	["beatrun_zcity_slideyawlimit"] = true,
	["beatrun_rollanim"] = true,
	["beatrun_zcity_rollholster"] = true,
	["beatrun_zcity_climbenabled"] = true,
	["beatrun_zcity_climbhangheight"] = true,
	["beatrun_zcity_climbmaxledgeheight"] = true,
	["beatrun_zcity_climbreach"] = true,
	["beatrun_zcity_climbholddelay"] = true,
	["beatrun_zcity_climbheavetime"] = true,
	["beatrun_zcity_climbcooldown"] = true,
	["beatrun_zcity_rollminheight"] = true,
	["beatrun_zcity_rollbigheight"] = true,
}

net.Receive("Beatrun_ChangeConvar", function(_, ply)
	if not IsValid(ply) or not ply:IsAdmin() then return end

	local name = string.lower(net.ReadString() or "")
	if not ALLOWED_CONVARS[name] then return end

	local value = net.ReadString() or ""
	local cv = GetConVar(name)
	if cv then
		RunConsoleCommand(cv:GetName(), value)
	end
end)
