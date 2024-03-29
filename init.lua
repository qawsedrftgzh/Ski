-- ski/init.lua

-- Load support for MT game translation.
local S = minetest.get_translator("Ski")

--
-- Helper functions
--

local function is_snow(pos)
	local nn = minetest.get_node(pos).name
	return nn == "default:dirt_with_snow" or nn == "default:snowblock" or nn == "default:snow"
end


local function get_velocity(v, yaw, y)
	local x = -math.sin(yaw) * v
	local z =  math.cos(yaw) * v
	return {x = x, y = y, z = z}
end


local function get_v(v)
	return math.sqrt(v.x ^ 2 + v.z ^ 2)
end

--
-- Boat entity
--

local ski = {
	initial_properties = {
		physical = true,
		-- Warning: Do not change the position of the collisionbox top surface,
		-- lowering it causes the ski to fall through the world if underwater
		collisionbox = {-0.3, 0.2, -0.2, 0.3, 0.3, 0.2},
		visual = "mesh",
		mesh = "ski.obj",
		textures = {"default_wood.png"},
	},

	driver = nil,
	v = 0,
	last_v = 0,
	removed = false,
	auto = false
}


function ski.on_rightclick(self, clicker)
	if not clicker or not clicker:is_player() then
		return
	end
	local name = clicker:get_player_name()
	if self.driver and name == self.driver then
		self.driver = nil
		self.auto = true
		clicker:set_detach()
		player_api.player_attached[name] = false
		player_api.set_animation(clicker, "stand" , 30)
		local pos = clicker:get_pos()
		pos = {x = pos.x, y = pos.y + 0.2, z = pos.z}
		minetest.after(0.1, function()
			clicker:set_pos(pos)
		end)
	elseif not self.driver then
        self.auto = false
		local attach = clicker:get_attach()
		if attach and attach:get_luaentity() then
			local luaentity = attach:get_luaentity()
			if luaentity.driver then
				luaentity.driver = nil
			end
			clicker:set_detach()
		end
		self.driver = name
		clicker:set_attach(self.object, "",
			{x = 0.5, y = 0, z = -3}, {x = 0, y = 0, z = 0})
		player_api.player_attached[name] = true
		minetest.after(0.2, function()
			player_api.set_animation(clicker, "stand" , 30)
		end)
		clicker:set_look_horizontal(self.object:get_yaw())
	end
end


-- If driver leaves server while driving ski
function ski.on_detach_child(self, child)
	self.driver = nil
	self.auto = false
end


function ski.on_activate(self, staticdata, dtime_s)
	self.object:set_armor_groups({immortal = 1})
	if staticdata then
		self.v = tonumber(staticdata)
	end
	self.last_v = self.v
end


function ski.get_staticdata(self)
	return tostring(self.v)
end


function ski.on_punch(self, puncher)
	if not puncher or not puncher:is_player() or self.removed then
		return
	end

	local name = puncher:get_player_name()
	if self.driver and name == self.driver then
		self.driver = nil
		puncher:set_detach()
		player_api.player_attached[name] = false
	end
	if not self.driver then
		self.removed = true
		local inv = puncher:get_inventory()
		if not (creative and creative.is_enabled_for
				and creative.is_enabled_for(name))
				or not inv:contains_item("main", "ski:ski") then
			local leftover = inv:add_item("main", "ski:ski")
			-- if no room in inventory add a replacement ski to the world
			if not leftover:is_empty() then
				minetest.add_item(self.object:get_pos(), leftover)
			end
		end
		-- delay remove to ensure player is detached
		minetest.after(0.1, function()
			self.object:remove()
		end)
	end
end


function ski.on_step(self, dtime)
	self.v = get_v(self.object:get_velocity()) * math.sign(self.v)
	local drive_v = 0
	if self.driver then
		local driver_objref = minetest.get_player_by_name(self.driver)
		if driver_objref then
			local ctrl = driver_objref:get_player_control()
			if ctrl.up and ctrl.down then
				if not self.auto then
					self.auto = true
					minetest.chat_send_player(self.driver, S("Ski cruise mode on"))
				end
			elseif ctrl.down then
				drive_v = - dtime * 2.0
				if self.auto then
					self.auto = false
					minetest.chat_send_player(self.driver, S("Ski cruise mode off"))
				end
			elseif ctrl.up or self.auto then
				drive_v = dtime * 2.0
			end
			if ctrl.left then
				if self.v < -0.001 then
					self.object:set_yaw(self.object:get_yaw() - dtime * 2)
				else
					self.object:set_yaw(self.object:get_yaw() + dtime * 2)
				end
			elseif ctrl.right then
				if self.v < -0.001 then
					self.object:set_yaw(self.object:get_yaw() + dtime * 2)
				else
					self.object:set_yaw(self.object:get_yaw() - dtime * 2)
				end
			end
		end
	end
	local velo = self.object:get_velocity()
	if drive_v ==0 and self.v == 0 and velo.x == 0 and velo.y == 0 and velo.z == 0 then
		self.object:set_pos(self.object:get_pos())
		return
	end
	-- We need to preserve velocity sign to properly apply drag force
	-- while moving backward
	local drag = dtime * math.sign(self.v) * (0.01 + 0.0796 * self.v * self.v)
	-- If drag is larger than velocity, then stop horizontal movement
	if math.abs(self.v) <= math.abs(drag) then
		self.v = 0
	else
		self.v = self.v - drag
	end
	local p = self.object:get_pos()
	p.y = p.y - 0.001
	local new_velo
	local new_acce = {x = 0, y = 0, z = 0}
	if not is_snow(p) then
		local nodedef = minetest.registered_nodes[minetest.get_node(p).name]
		if nodedef.walkable then
			--self.v = 0
			new_acce = {x = 0, y = 0.01, z = 0}
			-- no snow drag
			drag = dtime*5
			if math.abs(self.v) <= math.abs(drag) then
				self.v = 0
			else
				self.v = self.v - drag
			end
		else
			new_acce = {x = 0, y = -10, z = 0}
			self.v = self.v + dtime*5
			print("add "..(dtime))
		end
		-- no snow, no drive speed add
		new_velo = get_velocity(self.v, self.object:get_yaw(),
			self.object:get_velocity().y)
		self.object:set_pos(self.object:get_pos())
	else
		-- snow, apply drive velocity
		self.v = self.v + drive_v
		p.y = p.y + 1
		if is_snow(p) then
			local y = self.object:get_velocity().y
			if y >= 10 then
				y = 10
			elseif y < 0 then
				new_acce = {x = 0, y = 20, z = 0}
			else
				new_acce = {x = 0, y = 5, z = 0}
			end
			new_velo = get_velocity(self.v, self.object:get_yaw(), y)
			self.object:set_pos(self.object:get_pos())
		else
			new_acce = {x = 0, y = 0, z = 0}
			local y = self.object:get_velocity().y
			if math.abs(y) < 1 then
				local pos = self.object:get_pos()
				pos.y = math.floor(pos.y) + 0.5
				self.object:set_pos(pos)
				new_velo = get_velocity(self.v, self.object:get_yaw(), 0)
			else
				new_velo = get_velocity(self.v, self.object:get_yaw(),
					y)
				self.object:set_pos(self.object:get_pos())
			end
		end
	end
	self.object:set_velocity(new_velo)
	self.object:set_acceleration(new_acce)
end


minetest.register_entity("ski:ski", ski)


minetest.register_craftitem("ski:ski", {
	description = S("Ski"),
	inventory_image = "ski_inventory.png",
	wield_image = "ski_wield.png",
	wield_scale = {x = 2, y = 2, z = 1},
	liquids_pointable = true,
	groups = {flammable = 2},

	on_place = function(itemstack, placer, pointed_thing)
		local under = pointed_thing.under
		local node = minetest.get_node(under)
		local udef = minetest.registered_nodes[node.name]
		if udef and udef.on_rightclick and
				not (placer and placer:is_player() and
				placer:get_player_control().sneak) then
			return udef.on_rightclick(under, node, placer, itemstack,
				pointed_thing) or itemstack
		end

		if pointed_thing.type ~= "node" then
			return itemstack
		end
		if not is_snow(pointed_thing.under) then
			return itemstack
		end
		pointed_thing.under.y = pointed_thing.under.y + 0.5
		ski = minetest.add_entity(pointed_thing.under, "ski:ski")
		if ski then
			if placer then
				ski:set_yaw(placer:get_look_horizontal())
			end
			local player_name = placer and placer:get_player_name() or ""
			if not (creative and creative.is_enabled_for and
					creative.is_enabled_for(player_name)) then
				itemstack:take_item()
			end
		end
		return itemstack
	end,
})


minetest.register_craft({
	output = "ski:ski",
	recipe = {
		{"group:wood", "", "" },
		{"", "group:wood", ""},
		{"", "", "group:wood"},
	},
})

minetest.register_craft({
	type = "fuel",
	recipe = "ski:ski",
	burntime = 20,
})
