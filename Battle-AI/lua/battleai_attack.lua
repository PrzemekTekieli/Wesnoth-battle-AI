local AH = wesnoth.require "ai/lua/ai_helper.lua"

-- QLearner functions --

function QLearner(data)
	-- load parameters and initial knowledge once
	if not data.Q then
		data.alfa, data.epsilon, data.gamma = wesnoth.dofile("~add-ons/Battle-AI/lua/battleai_params.lua")
		data.Q = wesnoth.dofile("~add-ons/Battle-AI/lua/battleai_knowledge.lua")
		-- TODO state/action
	
		data.alfa_decay = 0.95
		data.epsilon_decay = 0.95
		data.alfa_min = 0.1
		data.epsilon_min = 0.05
	end
	
	local action = pick_action(data)
	local reward, attacker_copy, target_copy = evaluate_action(action)
	update_knowledge(data, action, reward, attacker_copy, target_copy)
	
	-- update alfa and epsilon
	if data.alfa > data.alfa_min then
		data.alfa = data.alfa * data.alfa_decay
	end
	if data.epsilon > data.epsilon_min then
		data.epsilon = data.epsilon * data.epsilon_decay
	end
	
	-- print some informations
	std_print("---------------BATTLE AI---------------------------")
	print_action(action, reward, attacker_copy, target_copy)
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

	attacker_hp = attacker.hitpoints
	
	local attacker_copy = wesnoth.copy_unit(attacker)
	local target_copy = wesnoth.copy_unit(target)

	AH.checked_move(ai, attacker, x, y)
	AH.checked_attack(ai, attacker, target, weapon)
	
	-- evaluation - currently try do as much damage as possible (bonus for kill)
	-- TODO based on time of the day
	local reward = 0
	if wesnoth.get_unit(target_copy.x, target_copy.y) == nil then
		reward = reward + 50
	else
		reward = reward + (target_copy.hitpoints - target.hitpoints)
	end
	return reward, attacker_copy, target_copy
end

function update_knowledge(data, action, reward, attacker_copy, target_copy)
	local attacker, target, weapon, x, y = table.unpack(action)
	
	local disc_value = 5
	
	local old_attacker_hp, attacker_dmg_1, attacker_dmg_2 = discretize_unit(attacker_copy, disc_value, disc_value)
	local state = old_attacker_hp .. "_" .. attacker_dmg_1 .. "_" .. attacker_dmg_2
	local new_state = nil
	if wesnoth.get_unit(attacker_copy.x, attacker_copy.y) ~= nil then
		local new_attacker_hp = discretize(attacker.hitpoints, disc_value)
		new_state = new_attacker_hp .. "_" .. attacker_dmg_1 .. "_" .. attacker_dmg_2
	end
		
	local old_target_hp, target_dmg_1, target_dmg_2 = discretize_unit(target_copy, disc_value, disc_value)
	local action_value = old_target_hp .. "_" .. target_dmg_1 .. "_" .. target_dmg_2 .. "_" .. get_defence(attacker_copy) .. "_" .. get_defence(target_copy)
		
	local old_value = 0
	if data.Q[state] then
		if data.Q[state][action_value] then
			old_value = data.Q[state][action_value]
		end
	else
		data.Q[state] = {}
	end
	local optimal_future_value = 0 
	
	if new_state ~= nil then
		for _, Q_state in ipairs(data.Q) do
			-- if new state exists in knowledge
			if new_state == Q_state then
			
				local attacks = AH.get_attacks({attacker_copy})
				for _,attack in ipairs(attacks) do -- try every possible attack for given attacker
					local new_target = wesnoth.get_unit(attack.target) -- get enemy
					new_target_hp, new_target_dmg_1, new_target_dmg_2 = discretize_unit(new_target, disc_value, disc_value)
					
					new_action = new_target_hp .. "_" .. new_target_dmg_1 .. "_" .. new_target_dmg_2 .. "_" .. get_defence(attacker_copy) .. "_" .. get_defence(target_copy)
			
					for _, Q_action in ipairs(data.Q[Q_state]) do
						if new_action == Q_action then
							if data.Q[Q_state][Q_action] > optimal_future_value then
								optimal_future_value = data.Q[Q_state][Q_action]
							end
						end
					end
				end
			end
		end
	end

	data.Q[state][action_value] = (1 - data.alfa) * old_value + data.alfa * (reward + data.gamma * optimal_future_value)
end

-- find best possible action based on current knowledge
-- return attacker, target, n_weapon, dest.x, dest.y
function best_action(data)
	local max_rating = -1
	local attackers = AH.get_units_with_attacks {side = wesnoth.current.side}
	for _,attacker in ipairs(attackers) do -- try every possible attacker for current side
		local attacks = AH.get_attacks({attacker})
		for _,attack in ipairs(attacks) do -- try every possible attack for given attacker
			local target = wesnoth.get_unit(attack.target) -- get enemy
			for n_weapon,weapon in ipairs(attacker.attacks) do -- try every type of unit weapon
				-- get score for given attack from current knowledge
				local rating = data.Q[attacker.type .. "_" .. target.type .. "_" .. n_weapon .. "_" .. get_defence_at_location(attacker, attack.dst.x, attack.dst.y) .. "_" .. get_defence(target)]
				
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
	
	-- find attacker with possible targets
	while #attacks == 0 do
		attacker = attackers[math.ceil(math.random() * #attackers)]
		attacks = AH.get_attacks({attacker})
	end
	
	local attack = attacks[math.ceil(math.random() * #attacks)]
	local target = wesnoth.get_unit(attack.target)
	local n_weapon = math.ceil(math.random() * #attacker.attacks)
		
	return attacker, target, n_weapon, attack.dst.x, attack.dst.y
end

-- end QLearner functions --

-- local functions --

-- discretize value with given step
function discretize(value, step)
	i = 0
	while i < value do
		i = i + step
	end
	if i == 0 then
		i = step
	end
	return (i - step) .. "_" .. i
end

function discretize_unit(unit, hp_step, dmg_step)
	local unit_hp = unit.hitpoints
	local unit_dmg_1 = unit.attacks[1].damage * unit.attacks[1].number
	local unit_dmg_2 = 0
	if unit.attacks[2] ~= nil then
		unit_dmg_2 = unit.attacks[2].damage * unit.attacks[2].number
	end
	
	return discretize(unit_hp, hp_step), discretize(unit_dmg_1, dmg_step), discretize(unit_dmg_2, dmg_step)
end

-- return unit defence on current field, ingame defence = (100 - defence)% (less -> better)
function get_defence(unit)
	return wesnoth.unit_defense(unit,wesnoth.get_terrain(unit.x, unit.y))
end

-- return unit defence on given location
function get_defence_at_location(unit,x,y)
	return wesnoth.unit_defense(unit,wesnoth.get_terrain(x, y))
end

-- print information about current action and reward
function print_action(action, reward, attacker_copy, target_copy)
	local attacker, target, weapon, x, y = table.unpack(action)
	std_print('Reward: ' .. reward .. ' - ' .. attacker_copy.type .. ' attack ' .. target_copy.type .. ' with weapon number ' .. weapon .. ' at position (' .. x .. ',' .. y .. ') with attacker defence ' .. get_defence_at_location(attacker_copy, x, y) .. ' and defender defence ' .. get_defence(target_copy))
end

-- print current alfa, epsilon, gamma
function print_parameters(data)
	if data.alfa then
		std_print("Alfa: " .. data.alfa .. " Epsilon: " .. data.epsilon .. " Gamma: " .. data.gamma)
	end
end

-- print current knowledge with in ctrl+c syntax
function print_knowledge(data)
	message = ' >>> {'
	if data.Q then
		for state, action_list in pairs(data.Q) do
			message = message .. '["' .. state .. '"] = {'
			for action, value in pairs(action_list) do
				message = message .. '["' .. action .. '"] = ' .. value .. ','
			end
			message = message .. '},'
		end
	end
	message = string.sub(message, 1, -2) .. '}'
	std_print(message)
end

-- end local functions --


local ca_battleai_attack = {}

function ca_battleai_attack:evaluation()
	local attackers = AH.get_units_with_attacks {
        side = wesnoth.current.side
    }
	if (not attackers[1]) then 
		return 0 
	else
		local any_target = false
		for _,attacker in ipairs(attackers) do
			attacks = AH.get_attacks({attacker})
			if #attacks ~= 0 then
				any_target = true
			end
		end
		if any_target == false then
			return 0
		end
	end
    return 900000
end

function ca_battleai_attack:execution(cfg, data)
	QLearner(data)
end

return ca_battleai_attack