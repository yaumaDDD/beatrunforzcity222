-- Shared compatibility layer & ConVars for Beatrun Slide & Safety Roll in Z-City

local REP = { FCVAR_REPLICATED, FCVAR_ARCHIVE, FCVAR_NOTIFY }
local REP_PLAIN = { FCVAR_REPLICATED, FCVAR_ARCHIVE }

-- Slide & Roll feature toggles and tuning
CreateConVar("Beatrun_ZCity_SlideEnabled", "1", REP, "Enable Beatrun sprinting slide in Z-City", 0, 1)
CreateConVar("Beatrun_ZCity_RollEnabled", "1", REP, "Enable Beatrun fall safety roll in Z-City", 0, 1)
CreateConVar("Beatrun_ZCity_SlideMinSpeed", "190", REP, "Minimum horizontal speed required to initiate a slide (crouch alone; sprinting lowers the gate)", 100, 350)
CreateConVar("Beatrun_ZCity_OrganismImpact", "1", REP, "Scale slide and roll reliability with Z-City organism health/injuries/pain", 0, 1)
CreateConVar("Beatrun_ZCity_StaminaDrain", "1", REP, "Drain Z-City organism stamina when sliding or safety-rolling", 0, 1)
CreateConVar("Beatrun_ZCity_RollFallReduction", "0.65", REP, "Fraction of Z-City fall damage absorbed by a timed safety roll above 650 speed", 0, 1)
CreateConVar("Beatrun_ZCity_MaxSafeRollSpeed", "3000", REP, "Maximum vertical impact speed a timed safety roll can mitigate", 500, 4000)
CreateConVar("Beatrun_RollSpeedLoss", "1", REP, "Whether safety rolls slow down to roll pace instead of preserving full speed", 0, 1)
CreateConVar("Beatrun_ZCity_SlideAutoHold", "1", REP, "Once the slide is started with the sprint+crouch combo it plays to the end without holding the keys (press crouch again to cancel)", 0, 1)
CreateConVar("Beatrun_ZCity_SlideAirCheck", "1", REP, "Stop sliding automatically when sliding off a ledge or losing surface support", 0, 1)
CreateConVar("Beatrun_RollNoDamage", "1", REP, "A successful timed safety roll negates fall damage completely", 0, 1)
CreateConVar("Beatrun_ZCity_RollHolster", "1", REP, "Holster any equipped weapon to bare hands during a safety roll", 0, 1)
CreateClientConVar("Beatrun_ZCity_SlideWeapon", "1", true, false, "Armed slide: 0 = clean first person (animated body hidden), 1 = animated body legs plus your own viewmodel with the weapon", 0, 1)
CreateConVar("Beatrun_ZCity_SlideNoDamage", "1", REP, "A slide protects from Z-City impact damage and injuries", 0, 1)
CreateConVar("Beatrun_ZCity_RollMinSpeed", "250", REP, "Minimum fall speed at which a timed roll activates", 0, 2000)
CreateConVar("Beatrun_ZCity_RollMinHeight", "70", REP, "Minimum fall height (units) a timed roll is allowed to play on: a hop or a step down never turns into a roll", 0, 400)
CreateConVar("Beatrun_ZCity_RollBigHeight", "750", REP, "Fall height (units) from which a real roll plays instead of the knee landing (and 2x this for the low roll)", 100, 2000)

-- Ledge climb & hang (Beatrun climb.lua, ported to this addon's scheme)
CreateConVar("Beatrun_ZCity_ClimbEnabled", "1", REP, "Enable Beatrun ledge climb / hang in Z-City", 0, 1)
CreateConVar("Beatrun_ZCity_ClimbHangHeight", "74", REP, "Ledge climb: how far (units) the body hangs below the ledge edge while gripping", 40, 120)
CreateConVar("Beatrun_ZCity_ClimbMaxLedgeHeight", "84", REP, "Ledge climb: maximum ledge height above your feet that can be grabbed", 24, 140)
CreateConVar("Beatrun_ZCity_ClimbLowHeight", "46", REP, "Ledge climb: up to this height you vault onto the wall (vaultonto), above it you hang and pull yourself up (hangheaveup)", 12, 120)
CreateConVar("Beatrun_ZCity_ClimbReach", "60", REP, "Ledge climb: how far ahead of you a wall is detected (units)", 24, 120)
CreateConVar("Beatrun_ZCity_ClimbHoldDelay", "0.35", REP, "Ledge climb: how long you hang before the pull-up starts by itself", 0, 2)
CreateConVar("Beatrun_ZCity_ClimbHeaveTime", "0.55", REP, "Ledge climb: duration of the pull-up (seconds)", 0.2, 1.5)
CreateConVar("Beatrun_ZCity_ClimbCooldown", "0.45", REP, "Ledge climb: delay after a climb before the next grab can start", 0, 3)
CreateConVar("Beatrun_RollDebugLog", "0", REP, "Print landing speeds and whether the roll accepted them", 0, 1)
CreateConVar("Beatrun_ZCity_SlideSteer", "0", REP, "Allow changing the slide course with strafe keys (0 = course is fixed)", 0, 1)
CreateConVar("Beatrun_ZCity_SlideShoot", "1", REP, "Allow free aiming and shooting during a slide", 0, 1)
CreateConVar("Beatrun_ZCity_SlideYawLimit", "90", REP, "Maximum left/right look and aim angle (degrees) relative to slide direction while sliding with a weapon (0 = unlimited)", 0, 180)
CreateConVar("Beatrun_RollAnim", "0", REP, "Safety roll animation: 0 = chosen by fall height (big fall = roll, lower = knee landing), 1 = always the roll, 2 = always the knee landing", 0, 2)
CreateConVar("Beatrun_RollAlways", "1", REP, "Always play the roll animation when the safety roll triggers (0 = plain landing animation when the player is standing still)", 0, 1)

if CLIENT then
	CreateClientConVar("Beatrun_AnimSet", "0", true, false, "Beatrun animation rig (0 = new_climbanim, 1 = old_climbanim)", 0, 1)
	CreateClientConVar("Beatrun_SlideCamTilt", "1", true, false, "Enable Beatrun camera tilt & viewpunch during slide and safety roll", 0, 1)
	CreateClientConVar("Beatrun_SlideHideBody", "1", true, false, "Temporarily render Beatrun BodyAnim (with Z-City appearance & gloves) during slide/roll", 0, 1)
	CreateClientConVar("Beatrun_TrickCam", "1", true, false, "Switch the camera onto the trick (slide/safety roll) while it plays, including in third person", 0, 1)
	CreateClientConVar("Beatrun_RollCam", "0", true, false, "Safety roll / knee landing camera like Beatrun: the view rides the animation's eyes attachment with locked angles (0 = off, 1 = roll + knee landing, 2 = roll only)", 0, 2)
	CreateClientConVar("Beatrun_TrickCamOffset", "4", true, false, "How far the trick camera is pushed forward out of the character's head (units)", -16, 24)
CreateClientConVar("Beatrun_CamReport", "0", true, false, "Print camera/body measurements to the console every second during a trick", 0, 1)
CreateClientConVar("Beatrun_BodyMarkerHold", "15", true, false, "How long (seconds) the markers stay visible after a trick ends", 2, 120)
CreateClientConVar("Beatrun_BodyMarker", "0", true, false, "Draw world markers during a trick: green = animation head, blue = drawn body head, red = your eye, yellow = camera we requested", 0, 1)
CreateClientConVar("Beatrun_TrickCamTune", "0", true, false, "Live camera tuning during a trick: keypad 8/2 = height, 4/6 = forward/back", 0, 1)
CreateClientConVar("Beatrun_SnatchModel", "0", true, false, "Share the player's model instance with the trick body (better skinning, but bodygroup/bone edits can leak into your own model)", 0, 1)
CreateClientConVar("Beatrun_ForceCam", "1", true, false, "Force the rendered view onto the trick camera even if Z-City renders the scene itself", 0, 1)
CreateClientConVar("Beatrun_TrickCamAngles", "2", true, false, "Trick camera orientation: 0 = your own look angles, 1 = the animation head bone, 2 = the animation CameraJoint (attached, like Beatrun)", 0, 2)
CreateClientConVar("Beatrun_TrickCamLimits", "0", true, false, "Beatrun body-anim mouse limits while a trick plays: 0 = look freely, 1 = clamp to BodyLimitX/Y", 0, 1)
CreateClientConVar("Beatrun_TrickCamLockAng", "0", true, false, "Trick camera owns the view angles while the animation plays (same as the safety roll)", 0, 1)
CreateClientConVar("Beatrun_TrickCamMatchEye", "0", true, false, "Hold the trick camera at your own eye height (the animation only drives it horizontally)", 0, 1)
	CreateClientConVar("Beatrun_TrickCamUp", "4", true, false, "Trick camera height above the animation head, world units", -24, 24)
	CreateClientConVar("Beatrun_TrickCamAnchor", "0", true, false, "Trick camera anchor: 0 = head bone of the animation, 1 = CameraJoint, 2 = your own eye", 0, 2)
	CreateClientConVar("Beatrun_TrickCamMode", "0", true, false, "Trick camera mode: 0 = first person on the animation (like Beatrun), 1 = third person looking at the animated body", 0, 1)
	CreateClientConVar("Beatrun_TrickCamDistance", "150", true, false, "Third person trick camera distance behind the character (units)", 40, 400)
	CreateClientConVar("Beatrun_TrickCamHeight", "45", true, false, "Third person trick camera height above the character (units)", -50, 200)
	CreateClientConVar("Beatrun_ZCity_DebugHUD", "1", true, false, "Show the on-screen Beatrun Z-City camera/trick diagnostics panel", 0, 1)
end

if SERVER then
	util.AddNetworkString("Beatrun_ChangeConvar")
	util.AddNetworkString("Beatrun_ParkourEvent")
	util.AddNetworkString("sliding_spfix")
	util.AddNetworkString("sliding_spend")
	util.AddNetworkString("RollAnimSP")

	-- Server -> owning client animation triggers (multiplayer). The old code only did this in singleplayer,
	-- so on a dedicated server the animation depended on client prediction alone and could be missed.
	util.AddNetworkString("Beatrun_ZC_SlideStart")
	util.AddNetworkString("Beatrun_ZC_SlideEnd")
	util.AddNetworkString("Beatrun_ZC_RollStart")
	util.AddNetworkString("Beatrun_ZC_SlideAim")

	-- Ledge climb / hang animation triggers (server -> owning client)
	util.AddNetworkString("Beatrun_ZC_ClimbGrab")
	util.AddNetworkString("Beatrun_ZC_ClimbHeave")
	util.AddNetworkString("Beatrun_ZC_ClimbEnd")
end

function BeatrunIsZCity()
	if hg ~= nil then return true end
	if engine.ActiveGamemode then
		local gm = string.lower(engine.ActiveGamemode() or "")
		if gm == "zcity" or gm == "homigrad" then return true end
	end
	return false
end

function BeatrunHasOrganism(ply)
	return IsValid(ply) and istable(ply.organism)
end
