SLASH_MAGNIFY1 = '/magnify'
SlashCmdList['MAGNIFY'] = function(msg)
	local args = {}
	local i = 1
	for arg in string.gfind(string.lower(msg), '%S+') do
		args[i] = arg
		i = i + 1
	end

	if not args[1] then
		DEFAULT_CHAT_FRAME:AddMessage('|cffffdc7aMagnify |cffffffffoptions')
		DEFAULT_CHAT_FRAME:AddMessage(' ')
      DEFAULT_CHAT_FRAME:AddMessage('|cffcecece/magnify |cffffffffarrow flash - toggle player indicator arrow flash')
		DEFAULT_CHAT_FRAME:AddMessage('|cffcecece/magnify |cffffffffarrow scale [number] - set player arrow scale')
		DEFAULT_CHAT_FRAME:AddMessage('|cffcecece/magnify |cffffffffzoom reset - toggle whether to remember zoom level upon closing the map')
		DEFAULT_CHAT_FRAME:AddMessage('|cffcecece/magnify |cffffffffzoom max [number] - set max world map zoom')
		DEFAULT_CHAT_FRAME:AddMessage('|cffcecece/magnify |cfffffffffade [0.1-1] - toggle the map fading while you move, or set how opaque it fades to')
	elseif args[1] == 'arrow' then
		if args[2] == 'flash' then
			Magnify_Settings['arrow_flash'] = not Magnify_Settings['arrow_flash']

			DEFAULT_CHAT_FRAME:AddMessage('|cffffdc7aMagnify|cffffffff: World map player arrow flash ' .. (Magnify_Settings['arrow_flash'] and '|cff4dd23denabled' or '|cffce2323disabled') .. '|cffffffff.')
      elseif args[2] == 'scale' then
            if args[3] then
               Magnify_Settings['arrow_scale'] = tonumber(args[3])

               DEFAULT_CHAT_FRAME:AddMessage('|cffffdc7aMagnify|cffffffff: World map player arrow scale set to |cff3083dd' .. args[3] .. '|cffffffff. This change will be applied after you reload your interface.')
            end
      end
   elseif args[1] == 'fade' then
		local alpha = tonumber(args[2])

		if alpha then
			Magnify_Settings['fade_alpha'] = math.max(0.1, math.min(1, alpha))
			Magnify_Settings['fade'] = true
		else
			Magnify_Settings['fade'] = Magnify_Settings['fade'] == false
		end

		DEFAULT_CHAT_FRAME:AddMessage('|cffffdc7aMagnify|cffffffff: World map fade while moving ' .. (Magnify_Settings['fade'] ~= false and '|cff4dd23denabled' or '|cffce2323disabled') .. '|cffffffff (opacity |cff3083dd' .. (Magnify_Settings['fade_alpha'] or 0.35) .. '|cffffffff).')
   elseif args[1] == 'zoom' then
		if args[2] == 'reset' then
			Magnify_Settings['zoom_reset'] = not Magnify_Settings['zoom_reset']

			DEFAULT_CHAT_FRAME:AddMessage('|cffffdc7aMagnify|cffffffff: World map zoom level will be |cff3083dd' .. (Magnify_Settings['zoom_reset'] and 'reset' or 'saved') .. ' |cffffffffafter closing the map.')
		elseif args[2] == 'max' then
			if args[3] then
				Magnify_Settings['max_zoom'] = tonumber(args[3])

				DEFAULT_CHAT_FRAME:AddMessage('|cffffdc7aMagnify|cffffffff: Max world map zoom level set to |cff3083dd' .. args[3] .. '|cffffffff. This change will be applied after you reload your interface.')
			end
		end
	end
end


-- panel in the AddOns list of the settings window; every change applies at once
local panel = CreateFrame('Frame', 'MagnifyOptionsPanel')
panel.name = 'Magnify'

local widgets = {}
local top = -16

local title = panel:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
title:SetPoint('TOPLEFT', panel, 'TOPLEFT', 16, top)
title:SetText('Magnify')
top = top - 36

local function Setting(key, default)
	local value = Magnify_Settings[key]

	if value == nil then
		return default
	end

	return value
end

local function AddCheckbox(name, label, key, default)
	local box = CreateFrame('CheckButton', 'MagnifyOption' .. name, panel, 'OptionsCheckButtonTemplate')
	box:SetPoint('TOPLEFT', panel, 'TOPLEFT', 12, top)
	getglobal(box:GetName() .. 'Text'):SetText(label)

	box:SetScript('OnClick', function()
		Magnify_Settings[key] = this:GetChecked() and true or false
	end)

	box.refresh = function()
		box:SetChecked(Setting(key, default))
	end

	table.insert(widgets, box)
	top = top - 30
end

local function AddSlider(name, label, key, default, min, max, step, apply)
	local slider = CreateFrame('Slider', 'MagnifyOption' .. name, panel, 'OptionsSliderTemplate')
	slider:SetPoint('TOPLEFT', panel, 'TOPLEFT', 20, top - 18)
	slider:SetWidth(220)
	slider:SetMinMaxValues(min, max)
	slider:SetValueStep(step)
	getglobal(slider:GetName() .. 'Low'):SetText(min)
	getglobal(slider:GetName() .. 'High'):SetText(max)

	slider:SetScript('OnValueChanged', function()
		local value = tonumber(string.format('%.2f', math.floor(this:GetValue() / step + 0.5) * step))

		Magnify_Settings[key] = value
		getglobal(this:GetName() .. 'Text'):SetText(label .. ': ' .. value)

		if apply then
			apply(value)
		end
	end)

	slider.refresh = function()
		slider:SetValue(Setting(key, default))
	end

	table.insert(widgets, slider)
	top = top - 56
end

AddCheckbox('ArrowFlash', 'Flash the player arrow when the map opens', 'arrow_flash', true)
AddCheckbox('ZoomReset', 'Reset the zoom when the map closes', 'zoom_reset', false)
AddCheckbox('Fade', 'Fade the map while you move', 'fade', true)

AddSlider('FadeAlpha', 'Opacity while moving', 'fade_alpha', 0.35, 0.1, 1, 0.05)
AddSlider('ArrowScale', 'Player arrow size', 'arrow_scale', 1, 0.5, 3, 0.1, function(value)
	WorldMapPlayer.Icon:SetWidth(24 * value)
	WorldMapPlayer.Icon:SetHeight(24 * value)
end)
AddSlider('MaxZoom', 'Maximum zoom', 'max_zoom', 1.6, 1.2, 3, 0.2, function(value)
	MAGNIFY_MAX_ZOOM = value
end)

panel.refresh = function()
	for _, widget in ipairs(widgets) do
		widget.refresh()
	end
end

InterfaceOptions_AddCategory(panel)
