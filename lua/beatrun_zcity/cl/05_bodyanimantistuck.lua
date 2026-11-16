-- Safety guard ensuring BodyAnim never stays stuck after a slide or safety roll finishes

hook.Add("Think", "BeatrunZCity_BodyAnimAntiStuck", function()
	-- Safety net: if the animation died without a clean removal, give the player's own body back
	if not IsValid(BodyAnim) then
		local lp = LocalPlayer()
		if IsValid(lp) and lp._BRZHiddenOverride ~= nil and BeatrunRestoreStaticPlayerModel then
			BeatrunRestoreStaticPlayerModel(lp)
		end
		return
	end

	local ply = LocalPlayer()
	if not IsValid(ply) or not BeatrunCanSlideOrRoll(ply) or ply:InVehicle() then
		RemoveBodyAnim(false)
		return
	end

	-- Non-ending animation (deleteonend == false) is only valid while actively sliding
	if not deleteonend and not ply:GetSliding() and CurTime() >= ply:GetSafetyRollTime() then
		RemoveBodyAnim(true)
	end
end)
