-- Server-side cleanup for Beatrun Slide & Safety Roll in Z-City.
-- Never wraps or modifies Z-City hooks directly.

hook.Add("PlayerDeath", "BeatrunZCity_ResetOnDeath", function(ply)
	BeatrunResetSlideRollState(ply)
end)

hook.Add("PlayerSilentDeath", "BeatrunZCity_ResetOnSilentDeath", function(ply)
	BeatrunResetSlideRollState(ply)
end)

hook.Add("PlayerSpawn", "BeatrunZCity_ResetOnSpawn", function(ply)
	BeatrunResetSlideRollState(ply)
end)

hook.Add("PlayerPostThink", "BeatrunZCity_CleanupFakeRagdoll", function(ply)
	if not IsValid(ply) then return end
	local active = (ply.GetSliding and ply:GetSliding()) or (ply.GetSafetyRollTime and ply:GetSafetyRollTime() > CurTime())
	if active and not BeatrunCanSlideOrRoll(ply) then
		BeatrunResetSlideRollState(ply)
	end
end)
