module 'aux.core.slash'

include 'aux'

local cache = require 'aux.core.cache'

function LOAD2()
	tooltip_settings = character_data'tooltip'
end

_G.aux_ignore_owner = true

function status(enabled)
	return (enabled and color.green'on' or color.red'off')
end

local function handle_command(command)
	-- Normalize input: some clients pass whitespace for "no args".
	if type(command) == 'string' then
		command = string.gsub(command, '^%s+', '')
		command = string.gsub(command, '%s+$', '')
	end

	-- When called without arguments, open the settings window.
	if not command or command == '' then
		-- Use the module system (do NOT rely on _G.aux, which is a saved-variable table
		-- and gets replaced during initialization).
		local settings = require 'aux.gui.settings'
		if settings and settings.toggle then
			settings.toggle()
		else
			print(color.red'Aux: settings UI not available')
		end
		return
	end

	local arguments = tokenize(command)

    if arguments[1] == 'scale' and tonumber(arguments[2]) then
    	local scale = tonumber(arguments[2])
	    AuxFrame:SetScale(scale)
	    _G.aux_scale = scale
    elseif arguments[1] == 'ignore' and arguments[2] == 'owner' then
	    _G.aux_ignore_owner = not aux_ignore_owner
        print('ignore owner ' .. status(aux_ignore_owner))
    elseif arguments[1] == 'post' and arguments[2] == 'bid' then
	    _G.aux_post_bid = not aux_post_bid
	    print('post bid ' .. status(aux_post_bid))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'historical' then
	    tooltip_settings.historical = not tooltip_settings.historical
        print('tooltip historical ' .. status(tooltip_settings.historical))
	    elseif arguments[1] == 'tooltip' and arguments[2] == 'value' then
		    tooltip_settings.value = not tooltip_settings.value
	        print('tooltip value ' .. status(tooltip_settings.value))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'merchant' and arguments[3] == 'buy' then
	    tooltip_settings.merchant_buy = not tooltip_settings.merchant_buy
        print('tooltip merchant buy ' .. status(tooltip_settings.merchant_buy))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'merchant' and arguments[3] == 'sell' then
	    tooltip_settings.merchant_sell = not tooltip_settings.merchant_sell
        print('tooltip merchant sell ' .. status(tooltip_settings.merchant_sell))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'disenchant' and arguments[3] == 'value' then
	    tooltip_settings.disenchant_value = not tooltip_settings.disenchant_value
        print('tooltip disenchant value ' .. status(tooltip_settings.disenchant_value))
    elseif arguments[1] == 'tooltip' and arguments[2] == 'disenchant' and arguments[3] == 'distribution' then
	    tooltip_settings.disenchant_distribution = not tooltip_settings.disenchant_distribution
        print('tooltip disenchant distribution ' .. status(tooltip_settings.disenchant_distribution))
    elseif arguments[1] == 'clear' and arguments[2] == 'item' and arguments[3] == 'cache' then
	    _G.aux_items = {}
	    _G.aux_item_ids = {}
	    _G.aux_auctionable_items = {}
        print('Item cache cleared.')
    elseif arguments[1] == 'populate' and arguments[2] == 'wdb' then
	    cache.populate_wdb()
	else
		print('Usage:')
		print('- scale [' .. color.blue(aux_scale) .. ']')
		print('- ignore owner [' .. status(aux_ignore_owner) .. ']')
		print('- post bid [' .. status(aux_post_bid) .. ']')
			print('- tooltip value [' .. status(tooltip_settings.value) .. ']')
			print('- tooltip historical [' .. status(tooltip_settings.historical) .. ']')
		print('- tooltip merchant buy [' .. status(tooltip_settings.merchant_buy) .. ']')
		print('- tooltip merchant sell [' .. status(tooltip_settings.merchant_sell) .. ']')
		print('- tooltip disenchant value [' .. status(tooltip_settings.disenchant_value) .. ']')
		print('- tooltip disenchant distribution [' .. status(tooltip_settings.disenchant_distribution) .. ']')
		print('- clear item cache')
		print('- populate wdb')
    end
end

-- Slash command registration is global and can be overwritten by other addons.
-- Register on PLAYER_LOGIN so we win after all addons are loaded.
local function register_slash()
	_G.SLASH_AUX1 = '/aux'
	_G.SLASH_AUXADDON1 = '/auxaddon'
	_G.SLASH_AUXADDON2 = '/auxo'
	SlashCmdList.AUX = handle_command
	SlashCmdList.AUXADDON = handle_command
end

-- Some UIs/addons re-register /aux after login (or swallow it).
-- Hook the chat slash dispatcher as a last-resort so /aux always works.
do
	local orig
	orig = _G.ChatFrame_OnSlashCommand
	if type(orig) == 'function' then
		_G.ChatFrame_OnSlashCommand = function(msg, ...)
			if type(msg) == 'string' then
				local s = msg
				local lower = string.lower(s)
				-- Depending on client/build, msg can be "aux ..." or "/aux ...".
				if string.find(lower, '^/aux%s*') or string.find(lower, '^aux%s*') then
					local command = s
					command = string.gsub(command, '^/aux%s*', '')
					command = string.gsub(command, '^aux%s*', '')
					handle_command(command)
					return
				end
			end
			return orig(msg, ...)
		end
	end
end

do
	local f = CreateFrame('Frame')
	f:RegisterEvent('PLAYER_LOGIN')
	f:SetScript('OnEvent', register_slash)
end