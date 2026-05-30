module 'aux.gui.settings'

include 'T'
include 'aux'

local gui = require 'aux.gui'

-- Widget references for OnShow syncing
local main_widgets = {}

local function ensure_tooltip_settings()
	if not _G.tooltip_settings then
		_G.tooltip_settings = character_data('tooltip', { value = true, historical = true })
	end
end

local function bool(v) return not not v end

function LOAD2()
	ensure_tooltip_settings()

	-- =====================
	-- Main Options Panel
	-- =====================
	local panel = CreateFrame("Frame", "AuxOptionsPanel", UIParent)
	panel.name = "Aux"
	panel:SetWidth(500)
	panel:SetHeight(350)

	-- Title
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Aux Options")

	-- Helper to create a checkbox
	local function create_check(name, label_text, getter, setter, anchor, y_offset)
		local cb = CreateFrame("CheckButton", name, panel, "InterfaceOptionsSmallCheckButtonTemplate")
		cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y_offset or -8)
		_G[cb:GetName() .. "Text"]:SetText(label_text)
		cb:SetScript("OnClick", function()
			setter(cb:GetChecked())
		end)
		tinsert(main_widgets, { type = "check", frame = cb, getter = getter })
		return cb
	end

	-- Checkboxes
	local cbIgnoreOwner = create_check("AuxOptionsCheckIgnoreOwner", "Ignore owner",
		function() return _G.aux_ignore_owner end,
		function(v) _G.aux_ignore_owner = v end,
		title, -16)

	local cbPostBid = create_check("AuxOptionsCheckPostBid", "Post bid",
		function() return _G.aux_post_bid end,
		function(v) _G.aux_post_bid = v end,
		cbIgnoreOwner, -8)

	local cbTooltipValue = create_check("AuxOptionsCheckTooltipValue", "Tooltip value",
		function() return _G.tooltip_settings.value end,
		function(v) _G.tooltip_settings.value = v end,
		cbPostBid, -8)

	local cbTooltipHistorical = create_check("AuxOptionsCheckTooltipHistorical", "Tooltip historical",
		function() return _G.tooltip_settings.historical end,
		function(v) _G.tooltip_settings.historical = v end,
		cbTooltipValue, -8)

	local cbTooltipMerchantBuy = create_check("AuxOptionsCheckTooltipMerchantBuy", "Tooltip merchant buy",
		function() return _G.tooltip_settings.merchant_buy end,
		function(v) _G.tooltip_settings.merchant_buy = v end,
		cbTooltipHistorical, -8)

	local cbTooltipMerchantSell = create_check("AuxOptionsCheckTooltipMerchantSell", "Tooltip merchant sell",
		function() return _G.tooltip_settings.merchant_sell end,
		function(v) _G.tooltip_settings.merchant_sell = v end,
		cbTooltipMerchantBuy, -8)

	local cbTooltipDisenchantValue = create_check("AuxOptionsCheckTooltipDisenchantValue", "Tooltip disenchant value",
		function() return _G.tooltip_settings.disenchant_value end,
		function(v) _G.tooltip_settings.disenchant_value = v end,
		cbTooltipMerchantSell, -8)

	local cbTooltipDisenchantDistribution = create_check("AuxOptionsCheckTooltipDisenchantDistribution", "Tooltip disenchant distribution",
		function() return _G.tooltip_settings.disenchant_distribution end,
		function(v) _G.tooltip_settings.disenchant_distribution = v end,
		cbTooltipDisenchantValue, -8)

	-- Scale slider
	local slider = CreateFrame("Slider", "AuxOptionsScale", panel, "OptionsSliderTemplate")
	slider:SetPoint("TOPLEFT", cbTooltipDisenchantDistribution, "BOTTOMLEFT", 0, -16)
	slider:SetWidth(250)
	slider:SetHeight(16)
	slider:SetMinMaxValues(0.50, 2.00)
	slider:SetValueStep(0.01)
	_G[slider:GetName() .. "Low"]:SetText("0.50")
	_G[slider:GetName() .. "High"]:SetText("2.00")
	_G[slider:GetName() .. "Text"]:SetText("Scale")

	local editBox = CreateFrame("EditBox", "AuxOptionsScaleEditBox", panel)
	editBox:SetWidth(52)
	editBox:SetHeight(20)
	editBox:SetPoint("LEFT", slider, "RIGHT", 12, 0)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject("GameFontHighlightSmall")
	editBox:SetNumeric(false)
	editBox:SetMaxLetters(6)
	editBox:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\ChatFrame\\ChatFrameBorder",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 3, right = 3, top = 3, bottom = 3 }
	})
	editBox:SetBackdropColor(0, 0, 0, 0.5)

	local updating
	local function apply_scale(v)
		v = tonumber(v)
		if not v then return end
		if v < 0.50 then v = 0.50 end
		if v > 2.00 then v = 2.00 end
		v = math.floor(v * 100 + 0.5) / 100
		_G.aux_scale = v
		if _G.AuxFrame then
			AuxFrame:SetScale(v)
		end
		updating = true
		editBox:SetText(string.format("%.2f", v))
		slider:SetValue(v)
		updating = false
	end

	slider:SetScript("OnValueChanged", function()
		if updating then return end
		apply_scale(slider:GetValue())
	end)

	editBox:SetScript("OnEnterPressed", function()
		apply_scale(editBox:GetText())
		editBox:ClearFocus()
	end)

	editBox:SetScript("OnEditFocusLost", function()
		apply_scale(editBox:GetText())
	end)

	tinsert(main_widgets, { type = "slider", frame = slider, editbox = editBox, getter = function() return _G.aux_scale end })

	-- Clear Item Cache button
	local btn = CreateFrame("Button", "AuxOptionsClearCache", panel, "UIPanelButtonTemplate")
	btn:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -24)
	btn:SetWidth(140)
	btn:SetHeight(22)
	btn:SetText("Clear Item Cache")
	btn:SetScript("OnClick", function()
		_G.aux_items = {}
		_G.aux_item_ids = {}
		_G.aux_auctionable_items = {}
		print("Item cache cleared.")
	end)

	-- OnShow: sync all widgets with saved variables
	panel:SetScript("OnShow", function()
		ensure_tooltip_settings()
		for _, w in ipairs(main_widgets) do
			if w.type == "check" then
				w.frame:SetChecked(bool(w.getter()))
			elseif w.type == "slider" then
				local v = w.getter() or 1
				updating = true
				w.frame:SetValue(v)
				w.editbox:SetText(string.format("%.2f", v))
				updating = false
			end
		end
	end)

	-- Default reset
	panel.default = function()
		_G.aux_ignore_owner = true
		_G.aux_post_bid = nil
		_G.aux_scale = 1
		ensure_tooltip_settings()
		_G.tooltip_settings.value = true
		_G.tooltip_settings.historical = true
		_G.tooltip_settings.merchant_buy = nil
		_G.tooltip_settings.merchant_sell = nil
		_G.tooltip_settings.disenchant_value = nil
		_G.tooltip_settings.disenchant_distribution = nil
		if _G.AuxFrame then
			AuxFrame:SetScale(1)
		end
		panel:GetScript("OnShow")(panel)
	end

	InterfaceOptions_AddCategory(panel)

	-- =====================
	-- Fonts Panel
	-- =====================
	local fontsPanel = CreateFrame("Frame", "AuxFontsPanel", UIParent)
	fontsPanel.name = "Fonts"
	fontsPanel.parent = "Aux"
	fontsPanel:SetWidth(500)
	fontsPanel:SetHeight(280)

	local LSM = LibStub and LibStub('LibSharedMedia-3.0', true) or nil

	local defaults = {
		roles = {
			title = { font_name = nil, size = gui.get_role_fonts().title.size, outline = 'NONE' },
			text = { font_name = nil, size = gui.get_role_fonts().text.size, outline = 'NONE' },
			buttons = { font_name = nil, size = gui.get_role_fonts().buttons.size, outline = 'NONE' },
			numbers = { font_name = nil, size = gui.get_role_fonts().numbers.size, outline = 'NONE' },
		},
	}
	local fonts_data = character_data('fonts', defaults)

	local font_widgets = {}
	local rows = {
		{ key = 'title', label = 'Title' },
		{ key = 'text', label = 'Text' },
		{ key = 'buttons', label = 'Buttons' },
		{ key = 'numbers', label = 'Numbers' },
	}

	local font_list
	if LSM then
		font_list = LSM:List('font')
		table.sort(font_list)
	end

	local function apply_fonts_now()
		local old_font = gui.get_font()
		local old_sizes = {
			small = gui.font_size.small,
			medium = gui.font_size.medium,
			large = gui.font_size.large,
		}
		if fonts_data and fonts_data.roles then
			for role, opts in pairs(fonts_data.roles) do
				local path
				if LSM and opts.font_name then
					path = LSM:Fetch('font', opts.font_name, true)
				end
				gui.set_role_font(role, path, opts.size, opts.outline)
			end
		end
		if _G.AuxFrame then
			gui.refresh_fonts(AuxFrame, old_font, old_sizes)
		end
	end

	if not LSM then
		local warn = fontsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		warn:SetPoint("TOPLEFT", 16, -16)
		warn:SetText("LibSharedMedia-3.0 not found")
	else
		local start_y = -16
		local row_h = 58

		for i, row in ipairs(rows) do
			local y = start_y - (i - 1) * row_h
			local role_data = fonts_data.roles[row.key]

			local lbl = fontsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
			lbl:SetPoint("TOPLEFT", 16, y)
			lbl:SetText(row.label)

			local dd = CreateFrame("Frame", "AuxFonts" .. row.key .. "DropDown", fontsPanel, "UIDropDownMenuTemplate")
			dd:SetPoint("TOPLEFT", lbl, "BOTTOMLEFT", -16, -4)
			UIDropDownMenu_SetWidth(dd, 210)

			local sizeBox = CreateFrame("EditBox", "AuxFonts" .. row.key .. "Size", fontsPanel)
			sizeBox:SetWidth(52)
			sizeBox:SetHeight(24)
			sizeBox:SetPoint("LEFT", dd, "RIGHT", 10, 0)
			sizeBox:SetAutoFocus(false)
			sizeBox:SetFontObject("GameFontHighlightSmall")
			sizeBox:SetNumeric(false)
			sizeBox:SetMaxLetters(2)
			sizeBox:SetBackdrop({
				bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
				edgeFile = "Interface\\ChatFrame\\ChatFrameBorder",
				tile = true, tileSize = 16, edgeSize = 16,
				insets = { left = 3, right = 3, top = 3, bottom = 3 }
			})
			sizeBox:SetBackdropColor(0, 0, 0, 0.5)

			local function apply_role()
				local s = tonumber(role_data.size) or 14
				if s < 8 then s = 8 end
				if s > 32 then s = 32 end
				role_data.size = s
				sizeBox:SetText(string.format("%d", s))
				apply_fonts_now()
			end

			local function set_font(name)
				role_data.font_name = name
				UIDropDownMenu_SetSelectedName(dd, name)
				apply_fonts_now()
			end

			UIDropDownMenu_Initialize(dd, function()
				for _, name in ipairs(font_list) do
					local font_name = name
					local info = {}
					info.text = font_name
					info.notCheckable = true
					info.func = function()
						set_font(font_name)
					end
					UIDropDownMenu_AddButton(info)
				end
			end)

			if role_data.font_name then
				UIDropDownMenu_SetSelectedName(dd, role_data.font_name)
			end
			sizeBox:SetText(string.format("%d", tonumber(role_data.size) or 14))

			sizeBox:SetScript("OnEnterPressed", function()
				role_data.size = tonumber(sizeBox:GetText()) or role_data.size
				apply_role()
				sizeBox:ClearFocus()
			end)

			sizeBox:SetScript("OnEditFocusLost", function()
				role_data.size = tonumber(sizeBox:GetText()) or role_data.size
				apply_role()
			end)

			tinsert(font_widgets, {
				dropdown = dd,
				sizeBox = sizeBox,
				role_key = row.key,
			})
		end
	end

	fontsPanel:SetScript("OnShow", function()
		if not LSM then return end
		for _, w in ipairs(font_widgets) do
			local role_data = fonts_data.roles[w.role_key]
			UIDropDownMenu_Initialize(w.dropdown, function()
				for _, name in ipairs(font_list) do
					local font_name = name
					local info = {}
					info.text = font_name
					info.notCheckable = true
					info.func = function()
						role_data.font_name = font_name
						UIDropDownMenu_SetSelectedName(w.dropdown, font_name)
						apply_fonts_now()
					end
					UIDropDownMenu_AddButton(info)
				end
			end)
			UIDropDownMenu_SetWidth(w.dropdown, 210)
			if role_data.font_name then
				UIDropDownMenu_SetSelectedName(w.dropdown, role_data.font_name)
			end
			w.sizeBox:SetText(string.format("%d", tonumber(role_data.size) or 14))
		end
	end)

	fontsPanel.default = function()
		for role, opts in pairs(defaults.roles) do
			if fonts_data.roles[role] then
				fonts_data.roles[role].font_name = opts.font_name
				fonts_data.roles[role].size = opts.size
				fonts_data.roles[role].outline = opts.outline
			end
		end
		apply_fonts_now()
		fontsPanel:GetScript("OnShow")(fontsPanel)
	end

	InterfaceOptions_AddCategory(fontsPanel)
end
set_LOAD2(LOAD2)
