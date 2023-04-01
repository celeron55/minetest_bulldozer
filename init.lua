-- Function to calculate the positions of nodes inside the box
-- box: A table containing yaw angle (in radians), dimensions, and the origin position
function get_nodes_in_box(box)
	local yaw, dimensions, origin = box.yaw, box.dimensions, box.origin
	local longitudinal, transverse, height = dimensions[1], dimensions[2], dimensions[3]
	local nodes = {}

	local sin_yaw = math.sin(yaw)
	local cos_yaw = math.cos(yaw)

	for x = -math.floor(longitudinal / 2), math.floor(longitudinal / 2) do
		for y = 0, height - 1 do
			for z = -math.floor(transverse / 2), math.floor(transverse / 2) do
				local rotated_x = origin.x + (x * cos_yaw - z * sin_yaw)
				local rotated_y = origin.y + y
				local rotated_z = origin.z + (x * sin_yaw + z * cos_yaw)

				local node_pos = {x = math.floor(rotated_x), y = math.floor(rotated_y), z = math.floor(rotated_z)}
				table.insert(nodes, node_pos)
			end
		end
	end

	return nodes
end

-- Function to get non-walkable nodes in the box
-- box: A table containing yaw angle (in radians), dimensions, and the origin position
function get_non_walkable_nodes_in_box(box)
	local all_nodes = get_nodes_in_box(box)
	local non_walkable_nodes = {}

	for _, node_pos in ipairs(all_nodes) do
		local node = minetest.get_node(node_pos)
		local node_def = minetest.registered_nodes[node.name]
		if node_def and not node_def.walkable or node_def.drawtype ~= "normal" then
			table.insert(non_walkable_nodes, node_pos)
		end
	end

	return non_walkable_nodes
end

function get_walkable_nodes_in_box(box)
	local all_nodes = get_nodes_in_box(box)
	local walkable_nodes = {}

	for _, node_pos in ipairs(all_nodes) do
		local node = minetest.get_node(node_pos)
		local node_def = minetest.registered_nodes[node.name]
		if node_def and node_def.walkable then
			table.insert(walkable_nodes, node_pos)
		end
	end

	return walkable_nodes
end

-- Function to create a virtual wall in front of the player and move nodes in front of the wall
function create_virtual_wall(player_pos_float, player_yaw, wall_dimensions, move_distance,
		placement_height, placement_depth)
	local player_pos = {
		x = player_pos_float.x + 0.5,
		y = player_pos_float.y + 0.5,
		z = player_pos_float.z + 0.5,
	}

	local wall_pos = {
		x = player_pos.x + math.cos(player_yaw) * 0,
		y = player_pos.y,
		z = player_pos.z + math.sin(player_yaw) * 0,
	}

	local wall_box = {
		yaw = player_yaw,
		dimensions = wall_dimensions,
		origin = {
			x = wall_pos.x + math.cos(player_yaw),
			y = wall_pos.y + 1.5 - 1,
			z = wall_pos.z + math.sin(player_yaw),
		},
	}

	local nodes_in_wall = get_nodes_in_box(wall_box)

	-- Main placement box in front

	local placement_box = {
		yaw = player_yaw,
		dimensions = {move_distance, wall_dimensions[2], placement_height - placement_depth},
		origin = {
			x = player_pos.x + math.cos(player_yaw) * 5,
			y = player_pos.y + 1.5 + placement_depth,
			z = player_pos.z + math.sin(player_yaw) * 5,
		},
	}

	local non_walkable_nodes_in_placement_box = get_non_walkable_nodes_in_box(placement_box)

	table.sort(non_walkable_nodes_in_placement_box, function(a, b) return a.y < b.y end)

	-- Side placement boxes

	local side_box_width = wall_dimensions[2]

	local left_box = {
		yaw = player_yaw,
		dimensions = {move_distance, side_box_width, wall_dimensions[3] + 2},
		origin = {
			x = player_pos.x + math.cos(player_yaw+math.pi/2) * side_box_width,
			y = player_pos.y + 0.5 * wall_dimensions[3] - 3,
			z = player_pos.z + math.sin(player_yaw+math.pi/2) * side_box_width,
		},
	}

	local nwn_in_left_box = get_non_walkable_nodes_in_box(left_box)

	local right_box = {
		yaw = player_yaw,
		dimensions = {move_distance, side_box_width, wall_dimensions[3] + 2},
		origin = {
			x = player_pos.x + math.cos(player_yaw-math.pi/2) * side_box_width,
			y = player_pos.y + 0.5 * wall_dimensions[3] - 3,
			z = player_pos.z + math.sin(player_yaw-math.pi/2) * side_box_width,
		},
	}

	local nwn_in_right_box = get_non_walkable_nodes_in_box(right_box)

	local nwn_left_right_combined = {}

	for i, node_pos in ipairs(nwn_in_left_box) do
		table.insert(nwn_left_right_combined, node_pos)
	end
	for i, node_pos in ipairs(nwn_in_right_box) do
		table.insert(nwn_left_right_combined, node_pos)
	end

	table.sort(nwn_left_right_combined, function(a, b) return a.y < b.y end)

	for i, node_pos in ipairs(nwn_left_right_combined) do
		table.insert(non_walkable_nodes_in_placement_box, node_pos)
	end

	for i, node_pos in ipairs(nodes_in_wall) do
		if node_pos.y >= player_pos.y - 0.9 and node_pos.y <= player_pos.y + 0.5 then
			local node = minetest.get_node(node_pos)
			local node_def = minetest.registered_nodes[node.name]
			if node_def and node_def.groups and node_def.groups["cracky"] then
				return false
			end
		end
	end

	local num_sounds_played = 0

	for i, node_pos in ipairs(nodes_in_wall) do
		local node = minetest.get_node(node_pos)
		if node.name ~= "air" then
			if #non_walkable_nodes_in_placement_box > 0 then
				minetest.set_node(non_walkable_nodes_in_placement_box[1], node)
				minetest.remove_node(node_pos)
				table.remove(non_walkable_nodes_in_placement_box, 1)

				if num_sounds_played < 1 then
					local node_def = minetest.registered_nodes[node.name]
					if node_def then
						local sounds = node_def.sounds
						if sounds and sounds.dig then
							num_sounds_played = num_sounds_played + 1
							minetest.sound_play(sounds.dig, {pos = pos, gain = 0.5})
						end
					end
				end
			end
		end
	end

	return true
end

function target_value(current, target, rate)
	if current < target - rate then
		return current + rate
	elseif current > target + rate then
		return current - rate
	else
		return target
	end
end

local BULLDOZER_SIZE = 3
local BULLDOZER_HEIGHT = 1
local CLEAR_HEIGHT = 10
local PLACEMENT_HEIGHT = 3
local PLACEMENT_DEPTH = -5

-- Register the bulldozer entity
minetest.register_entity("bulldozer:bulldozer", {
	initial_properties = {
		physical = true,
		collisionbox = {-1.4, -0.5, -1.4, 1.4, 0.8, 1.4},
		visual = "mesh",
		mesh = "bulldozer_bulldozer.obj",
		textures = {
			"bulldozer_bulldozer_blade.png",
			"bulldozer_bulldozer_track.png",
			"bulldozer_bulldozer_track.png",
			"bulldozer_bulldozer_body.png",
			"bulldozer_bulldozer_body.png",
			"bulldozer_bulldozer_body.png",
		},
	},
	driver = nil,
	wanted_sound_pitch = 0.7,
	played_sound_pitch = 0.0,
	wanted_sound_gain = 0.2,
	played_sound_gain = 0.0,

	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then
			return
		end

		local player_name = clicker:get_player_name()

		if self.driver and player_name == self.driver:get_player_name() then
			-- Detach the player
			self.driver:set_detach()
			self.driver:set_eye_offset()
			self.driver = nil
			self.object:set_properties({
				physical = true,
			})
			if self.sound_handle then minetest.sound_stop(self.sound_handle) end
		elseif not self.driver then
			-- Attach the player
			self.driver = clicker
			self.driver:set_attach(self.object, "", {x = 0, y = 0, z = 0}, {x = 0, y = -90, z = 0})
			self.driver:set_eye_offset({x = 0, y = 2, z = 0})
			self.object:set_properties({
				physical = false, -- We want to go through nodes
			})
			self.wanted_sound_pitch = 0.7
			self.wanted_sound_gain = 0.2
		end
	end,

	on_step = function(self, dtime)
		if not self.driver then
			self:update_sound()
			return
		end

		-- Get player control inputs
		local ctrl = self.driver:get_player_control()
		--local yaw = self.driver:get_look_horizontal()
		local yaw = self.object:get_yaw()

		local object_pos = self.object:get_pos()

		local y_off = -0.5

		local box = {
			yaw = yaw,
			dimensions = {(BULLDOZER_SIZE+1), (BULLDOZER_SIZE+1), 1},
			origin = {
				x = object_pos.x,
				y = object_pos.y - y_off + 0.9,
				z = object_pos.z,
			},
		}
		local nwn_tracks = get_walkable_nodes_in_box(box)

		local box = {
			yaw = yaw,
			dimensions = {(BULLDOZER_SIZE+1), (BULLDOZER_SIZE+1), 1},
			origin = {
				x = object_pos.x,
				y = object_pos.y - y_off - 0.5,
				z = object_pos.z,
			},
		}
		local nwn_support = get_walkable_nodes_in_box(box)

		local box = {
			yaw = yaw,
			dimensions = {(BULLDOZER_SIZE+1), (BULLDOZER_SIZE+1), 1},
			origin = {
				x = object_pos.x,
				y = object_pos.y - y_off - 0.15,
				z = object_pos.z,
			},
		}
		local nwn_close_support = get_walkable_nodes_in_box(box)

		local box = {
			yaw = yaw,
			dimensions = {(BULLDOZER_SIZE+1), (BULLDOZER_SIZE+1), 1},
			origin = {
				x = object_pos.x,
				y = object_pos.y - y_off - 0.05,
				z = object_pos.z,
			},
		}
		local nwn_very_close_support = get_walkable_nodes_in_box(box)

		if ctrl.up then
			local object_pos2 = self.object:get_pos()
			if ctrl.jump then
				object_pos2.y = object_pos2.y - y_off + 1.1
			elseif ctrl.sneak then
				object_pos2.y = object_pos2.y - y_off - 0.9
			else
				object_pos2.y = object_pos2.y - y_off - 0.5
			end
			local object_yaw = self.object:get_yaw()+math.pi

			local wall_dimensions = {2, (BULLDOZER_SIZE+1), CLEAR_HEIGHT}
			local move_distance = 5
			local can_move = create_virtual_wall(object_pos2, object_yaw,
					wall_dimensions, move_distance, PLACEMENT_HEIGHT, PLACEMENT_DEPTH)

			local speed = 2.0
			if not can_move then
				speed = 0.0
			end
			-- Move the bulldozer forward
			self.object:set_velocity(vector.new(
				math.cos(yaw+math.pi) * speed,
				0,
				math.sin(yaw+math.pi) * speed
			))
		elseif ctrl.down then
			local speed = 1.5
			-- Move the bulldozer backward
			self.object:set_velocity(vector.new(
				math.cos(yaw) * speed,
				0,
				math.sin(yaw) * speed
			))
		else
			self.object:set_velocity({x = 0, y = 0, z = 0})
		end

		if ctrl.left then
			self.object:set_yaw(self.object:get_yaw() + 0.020)
		elseif ctrl.right then
			self.object:set_yaw(self.object:get_yaw() - 0.020)
		end

		if (ctrl.jump and ctrl.up and (#nwn_tracks >= 1 or #nwn_very_close_support >= (BULLDOZER_SIZE*BULLDOZER_SIZE/2))) or
				(ctrl.down and #nwn_tracks > (BULLDOZER_SIZE*BULLDOZER_SIZE/3) and not ctrl.sneak) then
			local rate = 0.01
			if #nwn_very_close_support >= 9 then
				rate = 0.03
			elseif #nwn_very_close_support >= 5 then
				rate = 0.02
			end
			self.object:set_pos({
				x = self.object:get_pos().x,
				y = self.object:get_pos().y + rate,
				z = self.object:get_pos().z
			})
		elseif (ctrl.sneak and ctrl.up) then
			local rate = 0.01
			if #nwn_support <= 7 then
				rate = 0.02
			end
			self.object:set_pos({
				x = self.object:get_pos().x,
				y = self.object:get_pos().y - rate,
				z = self.object:get_pos().z
			})
		else
			if #nwn_close_support >= (BULLDOZER_SIZE*BULLDOZER_SIZE*0.8) and not ctrl.sneak then
				local off = -y_off
				local new_y = math.floor(self.object:get_pos().y + off + 0.5) - off
				if math.abs(new_y - self.object:get_pos().y) >= 0.2 then
					self.object:set_pos({
						x = self.object:get_pos().x,
						y = new_y,
						z = self.object:get_pos().z
					})
				end
			end
		end

		if not ctrl.sneak then
			if #nwn_support <= (BULLDOZER_SIZE*BULLDOZER_SIZE/3) then
				self.object:set_pos({
					x = self.object:get_pos().x,
					--y = math.floor(self.object:get_pos().y + 0.5 - 1.0),
					y = self.object:get_pos().y - 0.1,
					z = self.object:get_pos().z
				})
			elseif #nwn_close_support <= (BULLDOZER_SIZE*BULLDOZER_SIZE/3) then
				self.object:set_pos({
					x = self.object:get_pos().x,
					--y = math.floor(self.object:get_pos().y + 0.5 - 1.0),
					y = self.object:get_pos().y - 0.02,
					z = self.object:get_pos().z
				})
			end
		end

		if ctrl.up then
			self.wanted_sound_pitch = target_value(self.wanted_sound_pitch, 1.3, 0.02)
			self.wanted_sound_gain = target_value(self.wanted_sound_gain, 0.30, 0.02)
		elseif ctrl.down or ctrl.left or ctrl.right then
			self.wanted_sound_pitch = target_value(self.wanted_sound_pitch, 1.1, 0.02)
			self.wanted_sound_gain = target_value(self.wanted_sound_gain, 0.25, 0.02)
		else
			self.wanted_sound_pitch = target_value(self.wanted_sound_pitch, 0.9, 0.02)
			self.wanted_sound_gain = target_value(self.wanted_sound_gain, 0.20, 0.02)
		end
		self:update_sound()
	end,

	update_sound = function(self)
		if not self.driver then
			if self.sound_handle then minetest.sound_stop(self.sound_handle) end
			return
		end
		if math.abs(self.wanted_sound_pitch - self.played_sound_pitch) < 0.06 and
				math.abs(self.wanted_sound_gain - self.played_sound_gain) < 0.03 then
			return
		end
		if self.sound_handle then minetest.sound_stop(self.sound_handle) end
		if self.object then
			self.played_sound_pitch = self.wanted_sound_pitch
			self.played_sound_gain = self.wanted_sound_gain
			self.sound_handle = minetest.sound_play({name = "bulldozer_engine"}, {
				object = self.object, gain = self.wanted_sound_gain,
				pitch = self.wanted_sound_pitch,
				max_hear_distance = 45,
				loop = true,
			})
		end
	end,
})

-- Register the bulldozer item for spawning the entity
minetest.register_craftitem("bulldozer:bulldozer_item", {
description = "Bulldozer",
inventory_image = "bulldozer_bulldozer_item.png",
on_place = function(itemstack, placer, pointed_thing)
if pointed_thing.type ~= "node" then
return
end
	local ent = minetest.add_entity(pointed_thing.above, "bulldozer:bulldozer")
	ent:set_yaw(placer:get_look_horizontal())

	itemstack:take_item()
	return itemstack
end,
})

