local AH = wesnoth.require "ai/lua/ai_helper.lua"

-- QLearner functions --

function QLearner(data)
	-- load parameters and initial knowledge once
	if not data.Q then
		data.alfa, data.epsilon, data.gamma = wesnoth.dofile("~add-ons/Battle-AI/lua/battleai_params.lua")
		data.Q = wesnoth.dofile("~add-ons/Battle-AI/lua/battleai_knowledge.lua")
		-- TODO state/action
	
		data.alfa_decay = 1
		data.epsilon_decay = 0.95
		data.alfa_min = 0
		data.epsilon_min = 0.01
	end
	
	local action = pick_action(data)
	local reward = evaluate_action(action)
	update_knowledge(data, action, reward)
	
	-- update alfa and epsilon
	if data.alfa > data.alfa_min then
		data.alfa = data.alfa * data.alfa_decay
	end
	if data.epsilon > data.epsilon_min then
		data.epsilon = data.epsilon * data.epsilon_decay
	end
	
	-- print some informations
	std_print("---------------BATTLE AI---------------------------")
	print_action(action, reward)
	print_parameters(data)
	print_knowledge(data)
	
	return action
end

function pick_action(data)
	local action
	math.randomseed(os.time())
	if data.epsilon < math.random() then
		action = table.pack(best_action(data))
	else
		action = table.pack(random_action())
	end
	return action
end

function evaluate_action(action)
	local attacker, target, weapon, x, y = table.unpack(action)
	local attacker_copy = wesnoth.copy_unit(attacker)
	attacker_copy.x = x
	attacker_copy.y = y
	local att_stats, def_stats = wesnoth.simulate_combat(attacker_copy, weapon, target)
	
	-- evaluation - currently try do as much damage as possible (no matter if unit killed)
	-- TODO based on time of the day
	local reward = target.hitpoints - def_stats.average_hp
	return reward
end

function update_knowledge(data, action, reward)
	local attacker, target, weapon, x, y = table.unpack(action)
	-- key = state = attacker_defender_weapon_attDefence_defDefence
	local key = attacker.type .. "_" .. target.type .. "_" .. weapon .. "_" .. get_defence_at_location(attacker, x, y) .. "_" .. get_defence(target)
	
	local old_value = 0
	if data.Q[key] then
		old_value = data.Q[key]
	end
	local optimal_future_value = 0 -- TODO or gamma always 0
	data.Q[key] = (1 - data.alfa) * old_value + data.alfa * (reward + data.gamma * optimal_future_value)
end

-- find best possible action based on current knowledge
-- return attacker, target, n_weapon, dest.x, dest.y
function best_action(data)
	local max_rating = -1
	local attackers = AH.get_units_with_attacks {side = wesnoth.current.side}
	for _,attacker in ipairs(attackers) do -- try every possible attacker for current side
        local attacker_copy = wesnoth.copy_unit(attacker) -- copy used in simulations
		local attacks = AH.get_attacks({attacker})
		for _,attack in ipairs(attacks) do -- try every possible attack for given attacker
			local target = wesnoth.get_unit(attack.target) -- get enemy
			attacker_copy.x = attack.dst.x -- move copy to attack location
			attacker_copy.y = attack.dst.y
			for n_weapon,weapon in ipairs(attacker.attacks) do -- try every type of unit weapon
				-- simulate attack
				local att_stats, def_stats = wesnoth.simulate_combat(attacker_copy, n_weapon, target)
				-- get score for given attack from current knowledge
				local rating = data.Q[attacker.type .. "_" .. target.type .. "_" .. n_weapon .. "_" .. get_defence(attacker_copy) .. "_" .. get_defence(target)]
				
				if rating and rating >= max_rating then
					-- prioritize standing unit in one place
					if rating ~= max_rating or (rating == max_rating and attacker.x == attack.dst.x and attacker.y == attack.dst.y) then
						max_rating = rating
						best_attacker, best_target, best_weapon, best_x, best_y = attacker, target, n_weapon, attack.dst.x, attack.dst.y
					end
				end
			end
		end
	end
	-- return best found action based on knowledge or random action if no knowledge found
	if max_rating > -1 then
		return best_attacker, best_target, best_weapon, best_x, best_y
	elseif #attackers > 0 then
		return random_action()
	end
end

-- attack random enemy with random unit
function random_action()
	local attackers = AH.get_units_with_attacks {side = wesnoth.current.side}
	local attacker = attackers[math.ceil(math.random() * #attackers)]
	
	local attacks = AH.get_attacks({attacker})
	local attack = attacks[math.ceil(math.random() * #attacks)]
	local target = wesnoth.get_unit(attack.target)
	local n_weapon = math.ceil(math.random() * #attacker.attacks)
	
    local attacker_copy = wesnoth.copy_unit(attacker)
	attacker_copy.x = attack.dst.x
	attacker_copy.y = attack.dst.y
	
	local att_stats, def_stats = wesnoth.simulate_combat(attacker_copy, n_weapon, target)
	
	return attacker, target, n_weapon, attack.dst.x, attack.dst.y
end

-- end QLearner functions --

-- local functions --

-- return unit defence on current field, ingame defence = (100 - defence)% (less -> better)
function get_defence(unit)
	return wesnoth.unit_defense(unit,wesnoth.get_terrain(unit.x, unit.y))
end

-- return unit defence on given location
function get_defence_at_location(unit,x,y)
	return wesnoth.unit_defense(unit,wesnoth.get_terrain(x, y))
end

-- print information about current action and reward
function print_action(action, reward)
	local attacker, target, weapon, x, y = table.unpack(action)
	std_print('Reward: ' .. reward .. ' - ' .. attacker.type .. ' attack ' .. target.type .. ' with weapon number ' .. weapon .. ' at position (' .. x .. ',' .. y .. ') with attacker defence ' .. get_defence_at_location(attacker, x, y) .. ' and defender defence ' .. get_defence(target))
end

-- print current alfa, epsilon, gamma
function print_parameters(data)
	if data.alfa then
		std_print("Alfa: " .. data.alfa .. " Epsilon: " .. data.epsilon .. " Gamma: " .. data.gamma)
	end
end

-- print current knowledge with in ctrl+c syntax
function print_knowledge(data)
	if data.Q then 
		for key, value in pairs(data.Q) do
			std_print('["' .. key .. '"] = ' .. value .. ',')
		end
	end
end

-- end local functions --


local ca_battleai_attack = {}

function ca_battleai_attack:evaluation()
	local attackers = AH.get_units_with_attacks {
        side = wesnoth.current.side
    }
	if (not attackers[1]) then return 0 end
    return 900000
end

function ca_battleai_attack:execution(cfg, data)
	local action = QLearner(data)
	local best_attacker, best_target, best_weapon, best_x, best_y = table.unpack(action)

	AH.checked_move(ai, best_attacker, best_x, best_y)
	AH.checked_attack(ai, best_attacker, best_target, best_weapon)
end

return ca_battleai_attack