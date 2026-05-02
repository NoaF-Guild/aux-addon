module 'aux.gui.settings'

include 'T'
include 'aux'

local gui = require 'aux.gui'

local frame

local function ensure_tooltip_settings()
	-- Created in aux.core.slash:LOAD2(). If settings are opened early,
	-- fall back to the persisted character table.
	if not _G.tooltip_settings then
		-- Ensure defaults exist (mirrors aux.core.tooltip).
		_G.tooltip_settings = character_data('tooltip', { value = true, historical = true })
	end
end

local function bool(v) return not not v end

local function add_check(parent, y, text, getter, setter)
	local cb = gui.checkbox(parent)
	cb:SetPoint('TOPLEFT', 14, y)
	cb:SetScript('OnClick', function()
		setter(cb:GetChecked())
	end)
	local label = gui.label(cb, gui.font_size.small)
	label:SetPoint('LEFT', cb, 'RIGHT', 6, 1)
	label:SetText(text)
	cb._refresh = function() cb:SetChecked(bool(getter())) end
	return cb
end

local function add_scale(parent, y)
	local slider = gui.slider(parent)
	slider:SetPoint('TOPLEFT', 14, y)
	slider:SetWidth(250)
	slider:SetMinMaxValues(0.50, 2.00)
	slider:SetValueStep(0.01)
	slider.label:SetText('Scale')

	local updating
	local function apply(v)
		v = tonumber(v)
		if not v then return end
		if v < 0.50 then v = 0.50 end
		if v > 2.00 then v = 2.00 end
		v = floor(v * 100 + 0.5) / 100
		_G.aux_scale = v
		if _G.AuxFrame then
			AuxFrame:SetScale(v)
		end
		updating = true
		slider.editbox:SetText(string.format('%.2f', v))
		updating = false
	end

	slider:SetScript('OnValueChanged', function()
		if updating then return end
		apply(slider:GetValue())
	end)

	slider.editbox:SetNumeric(false)
	slider.editbox:SetMaxLetters(6)
	-- Use the same "change" convention as aux.gui.slider editboxes.
	slider.editbox.change = function()
		apply(this:GetText())
		slider:SetValue(_G.aux_scale or 1)
	end

	slider._refresh = function()
		local v = _G.aux_scale or 1
		updating = true
		slider:SetValue(v)
		slider.editbox:SetText(string.format('%.2f', v))
		updating = false
	end

	return slider
end

local function build()
	ensure_tooltip_settings()

	frame = CreateFrame('Frame', 'AuxSettingsFrame', UIParent)
	gui.set_window_style(frame)
	gui.set_size(frame, 360, 390)
	frame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag('LeftButton')
	frame:SetScript('OnDragStart', function() this:StartMoving() end)
	frame:SetScript('OnDragStop', function() this:StopMovingOrSizing() end)

		-- Allow closing the settings window with ESC (standard WoW behaviour).
		if _G.UISpecialFrames then
			for _, n in ipairs(_G.UISpecialFrames) do
				if n == 'AuxSettingsFrame' then
					frame._esc_registered = true
					break
				end
			end
			if not frame._esc_registered then
				tinsert(_G.UISpecialFrames, 'AuxSettingsFrame')
				frame._esc_registered = true
			end
		end
	frame:Hide()

	local title = gui.label(frame, gui.font_size.large)
	title:SetPoint('TOPLEFT', 12, -10)
		-- Use existing Aux color helpers (there is no color.white in this codebase).
		title:SetText(color.text.enabled'Aux Options')

	local close = gui.button(frame, gui.font_size.small)
	gui.set_size(close, 60, 22)
	close:SetPoint('TOPRIGHT', -8, -8)
	close:SetText('Close')
	close:SetScript('OnClick', function()
		local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() or nil
		if focus and focus.ClearFocus and focus:IsObjectType('EditBox') then
			focus:ClearFocus()
		end
		if frame._apply_fonts_now then frame._apply_fonts_now() end
		frame:Hide()
	end)

	local content = gui.panel(frame)
	-- Leave extra room for the window title so tab labels don't overlap it.
	content:SetPoint('TOPLEFT', 8, -56)
	content:SetPoint('BOTTOMRIGHT', -8, 8)

	-- Tabs
	local tabs = gui.tabs(content, 'UP')
	tabs:create_tab('Options')
	tabs:create_tab('Fonts')

	local options_panel = CreateFrame('Frame', nil, content)
	options_panel:SetPoint('TOPLEFT', 4, -8)
	options_panel:SetPoint('BOTTOMRIGHT', -4, 4)

	local fonts_panel = CreateFrame('Frame', nil, content)
	fonts_panel:SetPoint('TOPLEFT', 4, -8)
	fonts_panel:SetPoint('BOTTOMRIGHT', -4, 4)
	fonts_panel:Hide()

	local function show_panel(which)
		options_panel:Hide()
		fonts_panel:Hide()
		if which == 'fonts' then
			fonts_panel:Show()
		else
			options_panel:Show()
		end
	end

	tabs._on_select = function(id)
		-- 1 = Options, 2 = Fonts
		show_panel(id == 2 and 'fonts' or 'options')
	end

	-- Force initial select
	tabs:select(1)

	frame._widgets = {}

	-- =====================
	-- Options panel
	-- =====================
	local y = -14
	tinsert(frame._widgets, add_check(options_panel, y, 'Ignore owner',
		function() return _G.aux_ignore_owner end,
		function(v) _G.aux_ignore_owner = v end))
	y = y - 26

	tinsert(frame._widgets, add_check(options_panel, y, 'Post bid',
		function() return _G.aux_post_bid end,
		function(v) _G.aux_post_bid = v end))
	y = y - 26

	gui.horizontal_line(options_panel, y - 8)
	y = y - 22

	tinsert(frame._widgets, add_check(options_panel, y, 'Tooltip value',
		function() return tooltip_settings.value end,
		function(v) tooltip_settings.value = v end))
	y = y - 26

	tinsert(frame._widgets, add_check(options_panel, y, 'Tooltip historical',
		function() return tooltip_settings.historical end,
		function(v) tooltip_settings.historical = v end))
	y = y - 26

	tinsert(frame._widgets, add_check(options_panel, y, 'Tooltip merchant buy',
		function() return tooltip_settings.merchant_buy end,
		function(v) tooltip_settings.merchant_buy = v end))
	y = y - 26

	tinsert(frame._widgets, add_check(options_panel, y, 'Tooltip merchant sell',
		function() return tooltip_settings.merchant_sell end,
		function(v) tooltip_settings.merchant_sell = v end))
	y = y - 26

	tinsert(frame._widgets, add_check(options_panel, y, 'Tooltip disenchant value',
		function() return tooltip_settings.disenchant_value end,
		function(v) tooltip_settings.disenchant_value = v end))
	y = y - 26

	tinsert(frame._widgets, add_check(options_panel, y, 'Tooltip disenchant distribution',
		function() return tooltip_settings.disenchant_distribution end,
		function(v) tooltip_settings.disenchant_distribution = v end))
	y = y - 36

	gui.horizontal_line(options_panel, y + 10)

	tinsert(frame._widgets, add_scale(options_panel, y - 18))

	-- Clear item cache (same as: /aux clear item cache)
	do
		local btn = gui.button(options_panel, gui.font_size.small)
		gui.set_size(btn, 140, 22)
		btn:SetPoint('TOPLEFT', 14, y - 78)
		btn:SetText('Clear Item Cache')
		btn:SetScript('OnClick', function()
			_G.aux_items = {}
			_G.aux_item_ids = {}
			_G.aux_auctionable_items = {}
			print('Item cache cleared.')
		end)
	end

	-- =====================
	-- Fonts panel (LibSharedMedia-3.0)
	-- =====================
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

	local function apply_fonts_now()
		local old_font = gui.font
		local old_sizes = { small = gui.font_size.small, medium = gui.font_size.medium, large = gui.font_size.large }
		-- Apply per-role fonts
		if fonts_data and fonts_data.roles then
			for role, opts in pairs(fonts_data.roles) do
				local path
				if LSM and opts.font_name then
					path = LSM:Fetch('font', opts.font_name, true)
				end
				gui.set_role_font(role, path, opts.size, opts.outline)
			end
		end
		-- Refresh existing UI (settings + aux)
		gui.refresh_fonts(frame, old_font, old_sizes)
		if _G.AuxFrame then
			gui.refresh_fonts(AuxFrame, old_font, old_sizes)
		end
		-- Do not refresh UIParent: some Blizzard FontStrings report a 0 height which
		-- causes SetFont() errors. Aux widgets are refreshed via AuxFrame.
	end
	frame._apply_fonts_now = apply_fonts_now

	local header = gui.label(fonts_panel, gui.font_size.large)
	header:SetPoint('TOPLEFT', 12, -10)
	header:SetText(color.text.enabled'Fonts')

	if not LSM then
		local warn = gui.label(fonts_panel, gui.font_size.small)
		warn:SetPoint('TOPLEFT', header, 'BOTTOMLEFT', 0, -12)
		warn:SetText(color.text.disabled'LibSharedMedia-3.0 not found')
	else
		local font_list = LSM:List('font')
		table.sort(font_list)

		local rows = {
			{ key = 'title', label = 'Title' },
			{ key = 'text', label = 'Text' },
			{ key = 'buttons', label = 'Buttons' },
			{ key = 'numbers', label = 'Numbers' },
		}

		local start_y = -38
		local row_h = 58

		local function make_row(i, row)
			local y = start_y - (i - 1) * row_h
			local role_data = fonts_data.roles[row.key]

			local lbl = gui.label(fonts_panel, gui.font_size.small)
			lbl:SetPoint('TOPLEFT', 12, y)
			lbl:SetText(row.label)

			local dd = gui.dropdown(fonts_panel)
			dd:SetPoint('TOPLEFT', lbl, 'BOTTOMLEFT', -16, -4)
			gui.set_size(dd, 210, 26)

			local size_box = gui.editbox(fonts_panel)
			gui.set_size(size_box, 52, 24)
			size_box:SetPoint('LEFT', dd, 'RIGHT', 10, 0)
			size_box:SetNumeric(false)
			size_box:SetMaxLetters(2)

			local function apply_role()
				-- clamp size
				local s = tonumber(role_data.size) or 14
				if s < 8 then s = 8 end
				if s > 32 then s = 32 end
				role_data.size = s
				size_box:SetText(string.format('%d', s))
				apply_fonts_now()
			end

			local function set_font(name)
				role_data.font_name = name
				UIDropDownMenu_SetSelectedName(dd, name)
				apply_fonts_now()
			end

			UIDropDownMenu_Initialize(dd, function()
				for _, name in ipairs(font_list) do
					UIDropDownMenu_AddButton({
						text = name,
						notCheckable = true,
						func = function() set_font(name) end,
					})
				end
			end)

			if role_data.font_name then
				UIDropDownMenu_SetSelectedName(dd, role_data.font_name)
			end
			size_box:SetText(string.format('%d', tonumber(role_data.size) or 14))
			-- Do not clamp on every keystroke: typing "14" triggers an intermediate
			-- "1" which would otherwise be forced to the minimum.
			size_box.change = function()
				role_data.size = tonumber(this:GetText()) or role_data.size
			end
			size_box.enter = function() apply_role() end
			size_box.focus_loss = function() apply_role() end

			local refresh = function()
				UIDropDownMenu_SetSelectedName(dd, role_data.font_name)
				size_box:SetText(string.format('%d', tonumber(role_data.size) or 14))
			end
			return { _refresh = refresh }
		end

		for i, row in ipairs(rows) do
			local w = make_row(i, row)
			if w then tinsert(frame._widgets, w) end
		end

		apply_fonts_now()
	end

	frame:SetScript('OnShow', function()
		ensure_tooltip_settings()
		for _, w in ipairs(frame._widgets) do
			if w and w._refresh then w:_refresh() end
		end
	end)
	frame:SetScript('OnHide', function()
		if frame._apply_fonts_now then frame._apply_fonts_now() end
	end)
end

function M.toggle()
	if not frame then build() end
	if frame:IsShown() then frame:Hide() else frame:Show() end
end
