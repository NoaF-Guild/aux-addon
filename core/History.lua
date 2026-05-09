module 'aux.core.history'

include 'T'
include 'aux'

local persistence = require 'aux.util.persistence'

local history_schema = {'tuple', '#', {next_push='number'}, {daily_min_buyout='number'}, {data_points={'list', ';', {'tuple', '@', {value='number'}, {time='number'}}}}}

local value_cache = {}
local fast_values
local fast_values_time

-- history storage (initialized early so callers before LOAD2 don't crash)
local data = {}

function LOAD2()
	local realm_hist = realm_data'history'
	if type(realm_hist) ~= 'table' then
		realm_hist = {}
		realm_data('history', realm_hist)
	end
	fast_values = realm_data'fast_values'
	fast_values_time = realm_data'fast_values_time'
	if type(fast_values) ~= 'table' then
		fast_values = {}
		realm_data('fast_values', fast_values)
	end
	local faction_hist = faction_data'history'
	local empty_realm = true
	for _ in pairs(realm_hist) do empty_realm = false break end
	if empty_realm then
		for k, v in pairs(faction_hist) do
			if realm_hist[k] == nil then realm_hist[k] = v end
		end
	end
	data = realm_hist
end

function M.set_fast_value(item_key, value)
	if not item_key or not value or value <= 0 then return end
	fast_values[item_key] = value
	fast_values_time = time()
	realm_data('fast_values_time', fast_values_time)
end

function M.fast_value(item_key)
	return fast_values and fast_values[item_key]
end

do
	local next_push = 0
	function get_next_push()
		if time() > next_push then
			local date = date('*t')
			date.hour, date.min, date.sec = 24, 0, 0
			next_push = time(date)
		end
		return next_push
	end
end

function get_new_record()
	return temp-O('next_push', next_push, 'data_points', T)
end

function read_record(item_key)
	local record = data[item_key] and persistence.read(history_schema, data[item_key]) or new_record
	if record.next_push <= time() then
		push_record(record)
		write_record(item_key, record)
	end
	return record
end

function write_record(item_key, record)
	data[item_key] = persistence.write(history_schema, record)
	if value_cache[item_key] then
		release(value_cache[item_key])
		value_cache[item_key] = nil
	end
end

function M.process_auction(auction_record)
	local item_record = read_record(auction_record.item_key)
	local unit_buyout_price = ceil(auction_record.buyout_price / auction_record.aux_quantity)
	if unit_buyout_price > 0 and unit_buyout_price < (item_record.daily_min_buyout or huge) then
		item_record.daily_min_buyout = unit_buyout_price
		write_record(auction_record.item_key, item_record)
	end
end

function M.data_points(item_key)
	return read_record(item_key).data_points
end

function M.value(item_key)
	if not value_cache[item_key] or value_cache[item_key].next_push <= time() then
		local item_record, value
		item_record = read_record(item_key)
		if getn(item_record.data_points) > 0 then
			local total_weight, weighted_values = 0, temp-T
			for _, data_point in pairs(item_record.data_points) do
				local weight = .99 ^ round((item_record.data_points[1].time - data_point.time) / (60 * 60 * 24))
				total_weight = total_weight + weight
				tinsert(weighted_values, O('value', data_point.value, 'weight', weight))
			end
			for _, weighted_value in pairs(weighted_values) do
				weighted_value.weight = weighted_value.weight / total_weight
			end
			value = weighted_median(weighted_values)
			else
				value = item_record.daily_min_buyout or (fast_values and fast_values[item_key])
			end
		value_cache[item_key] = O('value', value, 'next_push', item_record.next_push)
	end
	return value_cache[item_key].value
end

	function M.historical(item_key)
		local item_record = read_record(item_key)
		if getn(item_record.data_points) > 0 then
			local total_weight, weighted_values = 0, temp-T
			for _, data_point in pairs(item_record.data_points) do
				local weight = .99 ^ round((item_record.data_points[1].time - data_point.time) / (60 * 60 * 24))
				total_weight = total_weight + weight
				tinsert(weighted_values, O('value', data_point.value, 'weight', weight))
			end
			for _, weighted_value in pairs(weighted_values) do
				weighted_value.weight = weighted_value.weight / total_weight
			end
			return weighted_median(weighted_values)
		end
		return nil
	end

function M.market_value(item_key)
	return read_record(item_key).daily_min_buyout
end





function M.daily_value(item_key)
	local record = read_record(item_key)
	if record.daily_min_buyout then
		return record.daily_min_buyout
	end
	if getn(record.data_points) > 0 then
		return record.data_points[1].value
	end
	return fast_values and fast_values[item_key]
end

function weighted_median(list)
	sort(list, function(a,b) return a.value < b.value end)
	local weight = 0
	for _, v in ipairs(list) do
		weight = weight + v.weight
		if weight >= .5 then
			return v.value
		end
	end
end

function push_record(item_record)
	if item_record.daily_min_buyout then
		tinsert(item_record.data_points, 1, O('value', item_record.daily_min_buyout, 'time', item_record.next_push))
		while getn(item_record.data_points) > 11 do
			release(item_record.data_points[getn(item_record.data_points)])
			tremove(item_record.data_points)
		end
	end
	item_record.next_push, item_record.daily_min_buyout = next_push, nil
end