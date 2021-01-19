-- based on move_to_any_target.lua, but without "canrecruit = 'no'"
local AH = wesnoth.require "ai/lua/ai_helper.lua"
local ca_battleai_move = {}

function ca_battleai_move:evaluation(cfg, data)
	local units = wesnoth.get_units {
		side = wesnoth.current.side,
		formula = 'movement_left > 0'
	}

	if (not units[1]) then
		-- No units with moves left
		return 0
	end

	local unit, destination
	-- Find a unit that has a path to an space close to an enemy
	for i,u in ipairs(units) do
		local distance, target = AH.get_closest_enemy({u.x, u.y})
		if target then
			unit = u

			local x, y = wesnoth.find_vacant_tile(target.x, target.y)
			destination = AH.next_hop(unit, x, y)

			if destination then
				break
			end
		end
	end

	if (not destination) then
		-- No path was found
		return 0
	end

	data.move_destination = destination
	data.move_unit = unit

	return 100000
end

function ca_battleai_move:execution(cfg, data)
	AH.checked_move(ai, data.move_unit, data.move_destination[1], data.move_destination[2])
end

return ca_battleai_move
