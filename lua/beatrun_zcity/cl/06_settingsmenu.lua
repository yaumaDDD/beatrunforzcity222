-- Compact settings menu & SpawnMenu tool panel for Beatrun Slide & Safety Roll in Z-City

local function SendAdminConvar(name, value)
	net.Start("Beatrun_ChangeConvar")
		net.WriteString(name)
		net.WriteString(tostring(value))
	net.SendToServer()
end

local function AddServerCheckbox(panel, label, convarName, desc)
	local cb = panel:CheckBox(label)
	local cv = GetConVar(convarName)
	if cv then
		cb:SetChecked(cv:GetBool())
	end
	if desc then panel:ControlHelp(desc) end
	cb.OnChange = function(_, val)
		if LocalPlayer():IsAdmin() then
			SendAdminConvar(convarName, val and 1 or 0)
		end
	end
	return cb
end

local function AddServerSlider(panel, label, convarName, minVal, maxVal, decimals, desc)
	local sl = panel:NumSlider(label, "", minVal, maxVal, decimals)
	local cv = GetConVar(convarName)
	if cv then
		sl:SetValue(cv:GetFloat())
	end
	if desc then panel:ControlHelp(desc) end
	sl.OnValueChanged = function(_, val)
		if LocalPlayer():IsAdmin() then
			SendAdminConvar(convarName, math.Round(val, decimals))
		end
	end
	return sl
end

hook.Add("PopulateToolMenu", "BeatrunZCity_ToolsMenu", function()
	spawnmenu.AddToolMenuOption("Options", "Beatrun", "BeatrunZCity_SlideRoll", "#beatrun.toolsmenu.slideroll.name", "", "", function(panel)
		panel:ClearControls()

		panel:Help("#beatrun.toolsmenu.slideroll.help")

		local animCombo = panel:ComboBox("#beatrun.toolsmenu.gameplay.animset", "Beatrun_AnimSet")
		animCombo:SetSortItems(false)
		animCombo:AddChoice("#beatrun.toolsmenu.gameplay.animset1", 0)
		animCombo:AddChoice("#beatrun.toolsmenu.gameplay.animset2", 1)

		panel:CheckBox("#beatrun.toolsmenu.slideroll.hidebody", "Beatrun_SlideHideBody")
		panel:CheckBox("#beatrun.toolsmenu.slideroll.camtilt", "Beatrun_SlideCamTilt")
		panel:CheckBox("#beatrun.toolsmenu.slideroll.trickcam", "Beatrun_TrickCam")
		panel:ControlHelp("#beatrun.toolsmenu.slideroll.trickcamdesc")

		local camMode = panel:ComboBox("#beatrun.toolsmenu.slideroll.trickcammode", "Beatrun_TrickCamMode")
		camMode:SetSortItems(false)
		camMode:AddChoice("#beatrun.toolsmenu.slideroll.trickcammode0", 0)
		camMode:AddChoice("#beatrun.toolsmenu.slideroll.trickcammode1", 1)

		local anchor = panel:ComboBox("#beatrun.toolsmenu.slideroll.trickcamanchor", "Beatrun_TrickCamAnchor")
		anchor:SetSortItems(false)
		anchor:AddChoice("#beatrun.toolsmenu.slideroll.trickcamanchor0", 0)
		anchor:AddChoice("#beatrun.toolsmenu.slideroll.trickcamanchor1", 1)
		anchor:AddChoice("#beatrun.toolsmenu.slideroll.trickcamanchor2", 2)

		local camDist = panel:NumSlider("#beatrun.toolsmenu.slideroll.trickcamdist", "Beatrun_TrickCamDistance", 40, 400, 0)
		camDist:SetValue(GetConVar("Beatrun_TrickCamDistance"):GetFloat())

		panel:CheckBox("#beatrun.toolsmenu.slideroll.trickcamlock", "Beatrun_TrickCamLockAng")
		panel:ControlHelp("#beatrun.toolsmenu.slideroll.trickcamlockdesc")

		panel:CheckBox("#beatrun.toolsmenu.slideroll.trickcameye", "Beatrun_TrickCamMatchEye")
		panel:ControlHelp("#beatrun.toolsmenu.slideroll.trickcameyedesc")

		local camUp = panel:NumSlider("#beatrun.toolsmenu.slideroll.trickcamup", "Beatrun_TrickCamUp", -24, 24, 1)
		camUp:SetValue(GetConVar("Beatrun_TrickCamUp"):GetFloat())

		local offset = panel:NumSlider("#beatrun.toolsmenu.slideroll.trickcamoffset", "Beatrun_TrickCamOffset", 0, 16, 1)
		offset:SetValue(GetConVar("Beatrun_TrickCamOffset"):GetFloat())

		panel:CheckBox("#beatrun.toolsmenu.slideroll.autohold", "Beatrun_ZCity_SlideAutoHold")
		panel:ControlHelp("#beatrun.toolsmenu.slideroll.autoholddesc")

		panel:CheckBox("#beatrun.toolsmenu.slideroll.debughud", "Beatrun_ZCity_DebugHUD")

		if LocalPlayer():IsAdmin() then
			panel:Help("#beatrun.toolsmenu.zcity.name")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.slideroll.slideenabled", "Beatrun_ZCity_SlideEnabled")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.slideroll.slideaircheck", "Beatrun_ZCity_SlideAirCheck", "#beatrun.toolsmenu.slideroll.slideaircheckdesc")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.slideroll.rollenabled", "Beatrun_ZCity_RollEnabled")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.slideroll.rollholster", "Beatrun_ZCity_RollHolster", "#beatrun.toolsmenu.slideroll.rollholsterdesc")
			AddServerSlider(panel, "#beatrun.toolsmenu.slideroll.slideminspeed", "Beatrun_ZCity_SlideMinSpeed", 100, 350, 0, "#beatrun.toolsmenu.slideroll.slideminspeeddesc")
			AddServerSlider(panel, "#beatrun.toolsmenu.slideroll.slideyawlimit", "Beatrun_ZCity_SlideYawLimit", 0, 180, 0, "#beatrun.toolsmenu.slideroll.slideyawlimitdesc")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.zcity.painpenalty", "Beatrun_ZCity_OrganismImpact", "#beatrun.toolsmenu.zcity.painpenaltydesc")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.zcity.staminascale", "Beatrun_ZCity_StaminaDrain", "#beatrun.toolsmenu.zcity.staminascaledesc")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.gameplay.rollspeedloss", "Beatrun_RollSpeedLoss", "#beatrun.toolsmenu.gameplay.rollspeedlossdesc")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.gameplay.rollnodamage", "Beatrun_RollNoDamage")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.gameplay.rollanim", "Beatrun_RollAnim", "#beatrun.toolsmenu.gameplay.rollanimdesc")
			AddServerCheckbox(panel, "#beatrun.toolsmenu.gameplay.rollalways", "Beatrun_RollAlways", "#beatrun.toolsmenu.gameplay.rollalwaysdesc")
			AddServerSlider(panel, "#beatrun.toolsmenu.zcity.fallreduction", "Beatrun_ZCity_RollFallReduction", 0, 1, 2, "#beatrun.toolsmenu.zcity.fallreductiondesc")
			AddServerSlider(panel, "#beatrun.toolsmenu.zcity.maxsaferollspeed", "Beatrun_ZCity_MaxSafeRollSpeed", 500, 1400, 0, "#beatrun.toolsmenu.zcity.maxsaferollspeeddesc")
		end
	end)
end)

concommand.Add("beatrun_settings", function()
	local frame = vgui.Create("DFrame")
	frame:SetTitle("Beatrun Slide & Safety Roll (Z-City)")
	frame:SetSize(440, 480)
	frame:Center()
	frame:MakePopup()

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:Dock(FILL)

	local form = vgui.Create("DForm", scroll)
	form:Dock(TOP)
	form:SetName(language.GetPhrase("beatrun.toolsmenu.slideroll.name"))

	form:Help("#beatrun.toolsmenu.slideroll.help")

	local animCombo = form:ComboBox("#beatrun.toolsmenu.gameplay.animset", "Beatrun_AnimSet")
	animCombo:SetSortItems(false)
	animCombo:AddChoice("#beatrun.toolsmenu.gameplay.animset1", 0)
	animCombo:AddChoice("#beatrun.toolsmenu.gameplay.animset2", 1)

	form:CheckBox("#beatrun.toolsmenu.slideroll.hidebody", "Beatrun_SlideHideBody")
	form:CheckBox("#beatrun.toolsmenu.slideroll.camtilt", "Beatrun_SlideCamTilt")
	form:CheckBox("#beatrun.toolsmenu.slideroll.trickcam", "Beatrun_TrickCam")
	form:ControlHelp("#beatrun.toolsmenu.slideroll.trickcamdesc")

	local camMode = form:ComboBox("#beatrun.toolsmenu.slideroll.trickcammode", "Beatrun_TrickCamMode")
	camMode:SetSortItems(false)
	camMode:AddChoice("#beatrun.toolsmenu.slideroll.trickcammode0", 0)
	camMode:AddChoice("#beatrun.toolsmenu.slideroll.trickcammode1", 1)

	local anchor = form:ComboBox("#beatrun.toolsmenu.slideroll.trickcamanchor", "Beatrun_TrickCamAnchor")
	anchor:SetSortItems(false)
	anchor:AddChoice("#beatrun.toolsmenu.slideroll.trickcamanchor0", 0)
	anchor:AddChoice("#beatrun.toolsmenu.slideroll.trickcamanchor1", 1)
	anchor:AddChoice("#beatrun.toolsmenu.slideroll.trickcamanchor2", 2)

	local camDist = form:NumSlider("#beatrun.toolsmenu.slideroll.trickcamdist", "Beatrun_TrickCamDistance", 40, 400, 0)
	camDist:SetValue(GetConVar("Beatrun_TrickCamDistance"):GetFloat())

	form:CheckBox("#beatrun.toolsmenu.slideroll.trickcamlock", "Beatrun_TrickCamLockAng")
	form:ControlHelp("#beatrun.toolsmenu.slideroll.trickcamlockdesc")

	form:CheckBox("#beatrun.toolsmenu.slideroll.trickcameye", "Beatrun_TrickCamMatchEye")
	form:ControlHelp("#beatrun.toolsmenu.slideroll.trickcameyedesc")

	local camUp = form:NumSlider("#beatrun.toolsmenu.slideroll.trickcamup", "Beatrun_TrickCamUp", -24, 24, 1)
	camUp:SetValue(GetConVar("Beatrun_TrickCamUp"):GetFloat())

	local offset = form:NumSlider("#beatrun.toolsmenu.slideroll.trickcamoffset", "Beatrun_TrickCamOffset", 0, 16, 1)
	offset:SetValue(GetConVar("Beatrun_TrickCamOffset"):GetFloat())

	form:CheckBox("#beatrun.toolsmenu.slideroll.autohold", "Beatrun_ZCity_SlideAutoHold")
	form:ControlHelp("#beatrun.toolsmenu.slideroll.autoholddesc")

	form:CheckBox("#beatrun.toolsmenu.slideroll.debughud", "Beatrun_ZCity_DebugHUD")

	if LocalPlayer():IsAdmin() then
		AddServerCheckbox(form, "#beatrun.toolsmenu.slideroll.slideenabled", "Beatrun_ZCity_SlideEnabled")
		AddServerCheckbox(form, "#beatrun.toolsmenu.slideroll.slideaircheck", "Beatrun_ZCity_SlideAirCheck")
		AddServerCheckbox(form, "#beatrun.toolsmenu.slideroll.rollenabled", "Beatrun_ZCity_RollEnabled")
		AddServerCheckbox(form, "#beatrun.toolsmenu.slideroll.rollholster", "Beatrun_ZCity_RollHolster")
		AddServerSlider(form, "#beatrun.toolsmenu.slideroll.slideminspeed", "Beatrun_ZCity_SlideMinSpeed", 100, 350, 0)
		AddServerSlider(form, "#beatrun.toolsmenu.slideroll.slideyawlimit", "Beatrun_ZCity_SlideYawLimit", 0, 180, 0)
		AddServerCheckbox(form, "#beatrun.toolsmenu.zcity.painpenalty", "Beatrun_ZCity_OrganismImpact")
		AddServerCheckbox(form, "#beatrun.toolsmenu.zcity.staminascale", "Beatrun_ZCity_StaminaDrain")
		AddServerCheckbox(form, "#beatrun.toolsmenu.gameplay.rollspeedloss", "Beatrun_RollSpeedLoss")
		AddServerCheckbox(form, "#beatrun.toolsmenu.gameplay.rollnodamage", "Beatrun_RollNoDamage")
		AddServerCheckbox(form, "#beatrun.toolsmenu.gameplay.rollanim", "Beatrun_RollAnim")
		AddServerCheckbox(form, "#beatrun.toolsmenu.gameplay.rollalways", "Beatrun_RollAlways")
		AddServerSlider(form, "#beatrun.toolsmenu.zcity.fallreduction", "Beatrun_ZCity_RollFallReduction", 0, 1, 2)
		AddServerSlider(form, "#beatrun.toolsmenu.zcity.maxsaferollspeed", "Beatrun_ZCity_MaxSafeRollSpeed", 500, 1400, 0)
	end
end)
