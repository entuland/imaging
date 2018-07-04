imaging = {}

local mod_path = minetest.get_modpath(minetest.get_current_modname());
local smartfs = dofile(mod_path .. "/lib/smartfs.lua")
local notify = dofile(mod_path .. "/notify.lua")

-- constants

local POS = {}
local NEG = {}
POS.Y = 0
POS.Z = 1
NEG.Z = 2
POS.X = 3
NEG.X = 4
NEG.Y = 5

-- ============================================================
-- helper variables

local rot_matrices = {}
local dir_matrices = {}

local facedir_memory = {}

-- ============================================================
-- init

local function init_transforms()
	local rot = {}
	local dir = {}

	-- no rotation
	rot[0] = matrix{{  1,  0,  0},
	                {  0,  1,  0},
	                {  0,  0,  1}}
	-- 90 degrees clockwise
	rot[1] = matrix{{  0,  0,  1},
	                {  0,  1,  0},
	                { -1,  0,  0}}
	-- 180 degrees
	rot[2] = matrix{{ -1,  0,  0},
	                {  0,  1,  0},
	                {  0,  0, -1}}
	-- 270 degrees clockwise
	rot[3] = matrix{{  0,  0, -1},
	                {  0,  1,  0},
	                {  1,  0,  0}}

	rot_matrices = rot

	-- directions
	-- Y+
	dir[0] = matrix{{  1,  0,  0},
	                {  0,  1,  0},
	                {  0,  0,  1}}
	-- Z+
	dir[1] = matrix{{  1,  0,  0},
	                {  0,  0, -1},
	                {  0,  1,  0}}
	-- Z-
	dir[2] = matrix{{  1,  0,  0},
	                {  0,  0,  1},
	                {  0, -1,  0}}
	-- X+
	dir[3] = matrix{{  0,  1,  0},
	                { -1,  0,  0},
	                {  0,  0,  1}}
	-- X-
	dir[4] = matrix{{  0, -1,  0},
	                {  1,  0,  0},
	                {  0,  0,  1}}
	-- Y-
	dir[5] = matrix{{ -1,  0,  0},
	                {  0, -1,  0},
	                {  0,  0,  1}}

	dir_matrices = dir

	imaging._facedir_transform = {}
	imaging._matrix_to_facedir = {}

	for facedir = 0, 23 do
		local direction = math.floor(facedir / 4)
		local rotation = facedir % 4
		local transform = dir[direction] * rot[rotation]
		imaging._facedir_transform[facedir] = transform
		imaging._matrix_to_facedir[transform:tostring():gsub("%-0", "0")] = facedir
	end

end

init_transforms()

-- ============================================================
-- helper functions

local function cross_product(a, b)
	return vector.new(
		a.y * b.z - a.z * b.y,
		a.z * b.x - a.x * b.z,
		a.x * b.y - a.y * b.x
	)
end

local function extract_main_axis(dir)
	local axes = { "x", "y", "z" }
	local axis = 1
	local max = 0
	for i = 1, 3 do
		local abs = math.abs(dir[axes[i]])
		if abs > max then
			axis = i
			max = abs
		end
	end
	return axes[axis]
end

local function sign(num)
	return (num < 0) and -1 or 1
end

local function extract_unit_vectors(player, pointed_thing)
	assert(pointed_thing.type == "node")
	local abs_face_pos = minetest.pointed_thing_to_face_pos(player, pointed_thing)
	local pos = pointed_thing.under
	local f = vector.subtract(abs_face_pos, pos)
	local facedir = 0
	local primary = 0

	local m1, m2

	local unit_direction = vector.new()
	local unit_rotation = vector.new()
	local rotation = vector.new()

	if math.abs(f.y) == 0.5 then
		unit_direction.y = sign(f.y)
		rotation.x = f.x
		rotation.z = f.z
	elseif math.abs(f.z) == 0.5 then
		unit_direction.z = sign(f.z)
		rotation.x = f.x
		rotation.y = f.y
	else
		unit_direction.x = sign(f.x)
		rotation.y = f.y
		rotation.z = f.z
	end

	local main_axis = extract_main_axis(rotation)

	unit_rotation[main_axis] = sign(rotation[main_axis])

	return {
		back = unit_direction,
		wrap = unit_rotation,
		thumb = cross_product(unit_direction, unit_rotation),
	}
end

local function apply_transform(pos, transform)
	return {
		x = pos.x * transform[1][1] + pos.y * transform[1][2] + pos.z * transform[1][3],
		y = pos.x * transform[2][1] + pos.y * transform[2][2] + pos.z * transform[2][3],
		z = pos.x * transform[3][1] + pos.y * transform[3][2] + pos.z * transform[3][3],
	}
end

local function get_facedir_transform(facedir)
	return imaging._facedir_transform[facedir] or imaging._facedir_transform[0]
end

local function matrix_to_facedir(mtx)
	local key = mtx:tostring():gsub("%-0", "0")
	if not imaging._matrix_to_facedir[key] then
		error("Unsupported matrix:\n" .. key)
	end
	return imaging._matrix_to_facedir[key]
end

local function vector_to_dir_index(vec)
	local main_axis = extract_main_axis(vec)
	if main_axis == "x" then return (vec.x > 0) and POS.X or NEG.X end
	if main_axis == "z" then return (vec.z > 0) and POS.Z or NEG.Z end
	return (vec.y > 0) and POS.Y or NEG.Y
end

-- ========================================================================
-- local helpers

local function copy_file(source, dest)
	local src_file = io.open(source, "rb")
	if not src_file then 
		return false, "copy_file() unable to open source for reading"
	end
	local src_data = src_file:read("*all")
	src_file:close()

	local dest_file = io.open(dest, "wb")
	if not dest_file then 
		return false, "copy_file() unable to open dest for writing"
	end
	dest_file:write(src_data)
	dest_file:close()
	return true, "files copied successfully"
end

local function custom_or_default(modname, path, filename)
	local default_filename = "default/" .. filename
	local full_filename = path .. "/custom." .. filename
	local full_default_filename = path .. "/" .. default_filename
	
	os.rename(path .. "/" .. filename, full_filename)
	
	local file = io.open(full_filename, "rb")
	if not file then
		minetest.debug("[" .. modname .. "] Copying " .. default_filename .. " to " .. filename .. " (path: " .. path .. ")")
		local success, err = copy_file(full_default_filename, full_filename)
		if not success then
			minetest.debug("[" .. modname .. "] " .. err)
			return false
		end
		file = io.open(full_filename, "rb")
		if not file then
			minetest.debug("[" .. modname .. "] Unable to load " .. filename .. " file from path " .. path)
			return false
		end
	end
	file:close()
	return full_filename
end

-- ============================================================
-- palette functions

local function textToGrid(text)
	local parts = text:split(" ")
	if #parts < 3 then
		return false, "Invalid paste data"
	end
	local width = tonumber(parts[1])
	local height = tonumber(parts[2])
	if width < 1 or height < 1 then
		return false, "Invalid sizes: " .. parts[1] .. " " .. parts[2]
	end
	local index = 2
	local rows = {}
	local x = 0
	local y = 0

	local function addPixel(paletteIndex)
		if x >= width then
			x = 0
			y = y + 1
		end
		if y >= height then
			return false, "Pixels exceed declared sizes"
		end
		if not rows[y] then
			rows[y] = {}
		end
		rows[y][x] = paletteIndex
		x = x + 1
		return true
	end
	
	local function processCell(cell)
		local includeEmpty = true
		local parts = cell:split(":", includeEmpty)
		if #parts ~= 2 then
			return false, "Invalid cell format: " .. cell
		end
		local paletteIndex = parts[1] ~= "" and tonumber(parts[1]) or false
		local count = parts[2] == "" and 1 or tonumber(parts[2])
		if paletteIndex ~= false and (paletteIndex < 0 or paletteIndex > 255) then
			return false, "Invalid cell index: " .. cell
		end
		if count == 0 then
			return false, "Invalid cell count: " .. cell
		end
		for c = 1, count do
			local success, err = addPixel(paletteIndex)
			if not success then
				return false, err
			end
		end
		return true
	end
	
	for index, cell in ipairs(parts) do
		if index > 2 then
			local success, err = processCell(cell)
			if not success then
				return false, err
			end
		end	
	end
	
	return {
		width = width,
		height = height,
		rows = rows,
	}
end

local function getPaletteNames()
	local entries = minetest.get_dir_list(mod_path .. "/textures")
	local names = {}
	for _, entry in ipairs(entries) do
		local name = entry:match("^palette%-(.+)%.png$")
		if name then
			names[name] = entry
		end
	end
	return names
end

imaging.init = function()
	imaging.palettes = getPaletteNames()
	for name, palette in pairs(imaging.palettes) do
		local def = {
			description = "Imaging " .. name,
			paramtype = "light",
			paramtype2 = "color",
			tiles = { "white.png" },
			palette = palette,
			groups = {cracky = 3, not_in_creative_inventory = 1},
		}
		minetest.register_node("imaging:palette_" .. name, def)
	end
	
	local node_box = {
		type = "fixed",
		fixed = {
			{-0.5, -0.5, -0.15, 0.5, 0.5, 0.15},
		},
	}
	
	minetest.register_node("imaging:canvas", {
		drawtype = "nodebox",
		description = "Imaging Canvas",
		tiles = {
			"black.png",
			"black.png",
			"black.png",
			"black.png",
			"back.png",
			"front.png"
		},
		paramtype = "light",
		paramtype2 = "facedir",
		node_box = node_box,
		groups = {cracky = 3 },
		on_rightclick = imaging.on_rightclick,
	})
	
	local full_recipes_filename = custom_or_default("imaging", mod_path, "recipes.lua")
	if not full_recipes_filename then return end
	local recipes = dofile(full_recipes_filename);
	
	if recipes["imaging:canvas"] then
		minetest.register_craft({
			output = "imaging:canvas",
			recipe = recipes["imaging:canvas"]
		})
	end
end

local clicked_node = {}
local main_memory = {}

imaging.on_rightclick = function(clicked_pos, node, clicker)
	local playername = clicker:get_player_name()
	node.pos = clicked_pos
	clicked_node[playername] = node
	local state = imaging.forms.main:show(playername)
	
	local memory = main_memory[playername]
	
	if not memory then return end
	
	if memory.text then state:get("paste"):setText(memory.text) end
	if memory.palette then state:get("palettes"):setSelectedItem(memory.palette) end
	state:get("replacer"):setValue(memory.replacer)
	if memory.replacement then state:get("replacement"):setText(memory.replacement) end
	if memory.bumpvalue then state:get("bumpvalue"):setText(memory.bumpvalue) end
	
end

imaging.generate = function(_, state)
	local text = state:get("paste"):getText()
	local palette = state:get("palettes"):getSelectedItem()
	local replacer = state:get("replacer"):getValue()
	local replacement = state:get("replacement"):getText()
	local bumpvalue = tonumber(state:get("bumpvalue"):getText())
		
	if replacer then
		local def = minetest.registered_nodes[replacement]
		if not def then
			notify.err(state.player, "Invalid node entered: " .. replacement)
			return
		end
	else
		replacement = false
	end
	
	if type(bumpvalue) ~= "number" or bumpvalue < 0 then
		bumpvalue = 0
	end
	
	if not imaging.palettes[palette] then
		notify.err(state.player, "Invalid palette name " .. palette)
		return
	end
	
	local grid, err = textToGrid(text)
	if not grid then
		notify.err(state.player, err)
		return
	end
	
	main_memory[state.player] = {
		palette = palette,
		replacer = replacer,
		replacement = replacement,
		bumpvalue = bumpvalue,
		text = text,
	}
	
	imaging.fillGrid(state.player, palette, grid, replacement, bumpvalue)
end

imaging.fillGrid = function(playername, palette, grid, replacement, bumpvalue)
	
	local node = clicked_node[playername]
	if not node or node.name ~= "imaging:canvas" then
		notify.err(playername, "How did you end up here?")
		return
	end
	
	local facedir = node.param2
	local transform = get_facedir_transform(facedir)
	
	local multi = bumpvalue / 255
	
	function placeNode(x, y, paletteIndex)
		local pos = {
			x = math.floor(-grid.width / 2 + x + 0.5),
			y = grid.height - y,
			z = math.floor(-multi * paletteIndex + 0.5),
		}
		local newpos = vector.add(node.pos, apply_transform(pos, transform))
		local newnode

		if replacement then
			newnode = { name = replacement }
		else		
			newnode = {
				name = "imaging:palette_" .. palette,
				param2 = paletteIndex,
			}
		end
		minetest.swap_node(newpos, newnode)
	end
	
	for y = 0, grid.height - 1 do
		for x = 0, grid.width - 1 do
			local paletteIndex = grid.rows[y][x]
			if paletteIndex ~= false then
				placeNode(x, y, paletteIndex)
			end
		end
	end
end

imaging.init()

imaging.forms = {}

imaging.forms.main = smartfs.create("imaging.forms.main", function(state)
	state:size(7.5, 8)
	
	local paste_area = state:field(0.5, 0.5, 6.95, 3.5, "paste", "Paste Imaging data here")
	paste_area:isMultiline(true)
	paste_area:setCloseOnEnter(false)

	local palettes = state:dropdown(0.2, 3.7, 5.2, 0, "palettes", {})
	for name, palette in pairs(imaging.palettes) do
		palettes:addItem(name)
	end	
	if imaging.palettes.vga then
		palettes:setSelectedItem("vga")
	else
		palettes:setSelected(1)
	end
	
	local generate_button = state:button(5.2, 3.6, 2, 1, "generate", "Build")
	generate_button:onClick(imaging.generate)
	generate_button:setClose(true)
	
	local replacer = state:checkbox(0.2, 4.5, "replacer", "Build as:")
	local replacement = state:field(0.5, 4.6, 5, 4.5, "replacement", "'air' or 'modname:nodename'")
	replacement:setText("air")
	replacement:setCloseOnEnter(false)
	
	local bumpvalue = state:field(0.5, 5.8, 5, 4.5, "bumpvalue", "Bump value (zero or positive)")
	bumpvalue:setText("0")
	
	local close_button = state:button(5.2, 7, 2, 1, "close", "Close")
	close_button:setClose(true)
end)

