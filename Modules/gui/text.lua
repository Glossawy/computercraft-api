--[[
	Text Module Beta by Glossawy
	In Development
]]

local TextField = {}
local TextArea = {}

local text_components = {}

local ENTER_KEY = 28
local BACKSPACE_KEY = 14
local R_SHIFT_KEY = 54
local L_SHIFT_KEY = 42
local ESCAPE_KEY = 1

local setBackgroundCol = term.setBackgroundColor
local setTextCol = term.setTextColor
local prevColor = colors.black
local curColor = colors.black
local prevTextColor = colors.white
local curTextColor = colors.white

local text_area_meta = {__index = TextArea}
setmetatable(TextField, text_area_meta)
local text_field_meta = {__index = TextField}

local AREA_TYPE = "TextArea"
local FIELD_TYPE = "TextField"

NO_CHARACTER_LIMIT = -1

-- TERMINAL METHOD OVERRIDES
-- This Delegation is done to keep track of previous colors
function term.setBackgroundColor(color)
	prevColor = curColor
	curColor = color
	setBackgroundCol(color)
end

function term.setTextColor(color)
	prevTextColor = curTextColor
	curTextColor = color
	setTextCol(color)
end
--

-- A Round Function
local function round(a)
	return math.floor(a + 0.5)
end

--[[
	Generates a Universally Unique Identifier for Buttons, used in Identifying Buttons.
	This is used as a GUID

	This method does NOT GUARANTEE a UUID, just an EXTREMELY high likelihood. This is 
	less true for extremely large data sets.
]]
math.randomseed(os.clock())
local function getUUID()
  	local template = "xyxx-yxxx-yxxyyyxx"
  	return string.gsub(template, '[xy]', function(c)
    	local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb);
    	return string.format('%x', v);
  	end)
end

--[[
	Iterates through a Table and applies a function on each element.

	This function will return a value if one is returned in the iterator function.
	Val is returned, val will be nil if no result is returned and it is finsihed
	iterating.
]]
local function foreach(tab, func, ...)
	local args = {...}
	local val = nil

	for i=1,#tab do
		if(#args > 0) then
			val = func(tab[i], unpack{args})
		else
			val = func(tab[i])
		end

		if(val ~= nil) then
			break
		end
	end

	return val
end

--[[
	This is an alternate foreach function that is aimed at returning the index
	of a specified element. 

	The iterator function, in this case, should return true or false. If true
	then that index is returned and the loop is broken. If false the loop continues
	until a true value is found. If it finishes without finding a "true" value then
	this function will return nil.
]]
local function foreachi(tab, func, ...)
	local args = {...}

	for i=1,#tab do
		if(#args > 0) then
			if(func(tab[i], unpack(args)) == true) then
				return i
			end
		else
			if(func(tab[i]) == true) then
				return i
			end
		end
	end

	return nil
end

local function emptyAction(self)
	return
end

-- Seconday Process for TextArea to break down Multi-Line Text
local function makeLines2(lines, item)
	local tmp = {}

	for word in string.gmatch(lines, '([^\n]+)') do
		table.insert(tmp, word)
	end
	

	return tmp
end

-- TODO Make Proper
local function makeLines(text, item)
	assert(type(text) == "string", "Expected String, Received " .. type(text).."!",2)
	local limit = item.width
	local lines = math.ceil(#text/limit)
	local tmp = {}

	-- If Limit is 0 or Fits on One Line then return Text
	if(lines == 1/0 or lines == 0) then
		return {text}
	end

	-- Copy String byte by byte
	for i=1,lines do
		local bytes = {}
		for j=1,#text do
			table.insert(bytes, text:byte(j))
			if((j%limit == 0) or text:sub(j,j) == "\n") then
				text = text:sub(j+1)
				break
			end
		end
		table.insert(tmp, string.char(unpack(bytes)))
		bytes = {}
	end

	-- Remove Empty Line at End if Exists
	if(#tmp[#tmp] == 0) then
		table.remove(tmp, #tmp)
	end

	return tmp
end

local function handleClick(self)
	local default_del = false
	self.hasFocus = true

	while true do
		event, bcode, x, y = os.pullEvent()
		update()
		if(event == "key") then
			if(not default_del and self.text == self.default_text) then
				default_del = true
				self.text = ""
				self:draw()
			end
			self:fireKeyActions(bcode)
			if(bcode == ENTER_KEY and self.type_id == AREA_TYPE) then
				if(self.type_id == AREA_TYPE) then
					self.text = self.text.." \n"
				end
				self.enter_action()
			elseif(bcode == L_SHIFT_KEY or bcode == R_SHIFT_KEY) then
				event, char = os.pullEvent("char")
				self.text = self.text..char
			elseif(bcode == BACKSPACE_KEY) then
				self.text = self.text:sub(1, #text-2)
			elseif(bcode == ESCAPE_KEY) then
				break
			else
				while true do
					event, char, x, y = os.pullEvent()
					if(event == "char") then
						self.text = self.text..char
						break
					elseif(event == "key") then
						self:fireKeyActions(char)
						if(char == BACKSPACE_KEY) then self.text = self.text:sub(1, #text-2) end
						if(bcode == L_SHIFT_KEY or bcode == R_SHIFT_KEY) then
							event, char = os.pullEvent("char")
							self.text = self.text..char
						end
						break
					elseif(event == "terminate") then
						os.queueEvent("terminate")
						break
					elseif(event == "mouse_click") then
						os.queueEvent("mouse_click", char, x, y)
						break
					end
				end
			end
		elseif(event == "mouse_click") then
			self.hasFocus = false
			self:draw()
			update(x, y)
			break
		elseif(event == "terminate") then
			os.queueEvent("terminate")
			update()
			break
		end

		self:draw()
	end

	self.hasFocus = false
	update()
end

local function forceClear(self)
	sx = self.x
	sy = self.y
	tx = self.x + self.width
	ty = self.y + self.height

	for y=sy,ty do
		term.setCursorPos(sx, y)
		for x=sx,tx do
			term.write(" ")
		end
	end
end

local function fire(self, x, y)
	if(self:contains(x, y)) then
		self:clickHandler()
	end
end

local function fireKeyActions(self, key)
	key = keys.getName(key)
	if(self.char_actions[key]) then
		self.char_actions[key](self)
	end
end

TextArea.forceClear = forceClear
TextArea.clickHandler = handleClick
TextArea.fire = fire
TextArea.fireKeyActions = fireKeyActions

function update(x, y)
	foreach(text_components, function(text)
		if(x and y) then
			text:fire(x, y)
		else
			text:draw()
		end
	end)
end

function newTextField(x, y, columns, default_text, background, foreground)
	assert(x and y and columns, "Bad Params! Should be newTextField(x, y, columns, [default text], [background color], [text color])!", 2)

	local tfield = {
		x = x,
		y = y,
		id = getUUID(),
		type_id = FIELD_TYPE,
		width = columns,
		height = 2,
		default_text = default_text or "",
		text = default_text or "",
		bg_color = background or colors.white,
		fg_color = foreground or colors.black,
		enter_action = emptyAction,
		char_actions = {},	-- TODO Implement Character Press Actions
		max_length = NO_CHARACTER_LIMIT, -- TODO
		visible = true,
		hasFocus = false
	}	

	setmetatable(tfield, text_field_meta)
	table.insert(text_components, tfield)

	return tfield, tfield.id
end

function newTextArea(x, y, columns, rows, default_text, background, foreground)
	assert(x and y and columns, "Bad Params! Should be newTextArea(x, y, columns, rows, [default text], [background color], [text color])", 2)

	local tarea = {
		x = x,
		y = y,
		id = getUUID(),
		type_id = AREA_TYPE,
		width = columns,
		height = rows or 2,
		default_text = default_text or "",
		text = default_text or "",
		bg_color = background or colors.white,
		fg_color = foreground or colors.black,
		max_length = NO_CHARACTER_LIMIT,
		enter_action = emptyAction,
		char_actions = {},	-- TODO Implement Character Press Actions
		visible = true,
		hasFocus = false
	}

	setmetatable(tarea, text_area_meta)
	table.insert(text_components, tarea)

	return tarea, tarea.id
end	

-- Text Area Methods
--[[
	A Clear Method, The only distinction from forceClear() is that
	this method DOES take Visibility into account. 

	Ultimately it delegates to forceClear if the Component is visible
]]
function TextArea:clear()
	if(not self.visible) then
		return
	end

	self:forceClear()
end

--[[
	A Draw Method, The only distinction between TextArea and TextField
	is in printing Text, The field does not LineWrap and displays the 
	tail end of the text should length exceed textfield width.
]]
function TextArea:draw()
	if(not self.visible) then
		return
	end

	text = self.text
	term.setBackgroundColor(self.bg_color)
	term.setTextColor(self.fg_color)

	self:clear()

	sx = self.x
	sy = self.y
	tx = self.x + self.width
	ty = self.y + self.height

	for y=sy,ty do
		term.setCursorPos(sx, y)
		for x=sx,tx do
			term.write(" ")
		end
	end

	if(text and #text > 0) then
		tx = sx
		ty = sy
		text = self.hasFocus and self.text.."_" or self.text
		len = #text
		if(self.type_id == AREA_TYPE) then
			tmp = makeLines2(text, self)
			lines = {}
			for i=1,#tmp do
				t = makeLines(tmp[i], self)
				for j=1,#t do
					lines[#lines + 1] = t[j]  
				end
			end

			while(#lines > self.height + 1) do
				table.remove(lines, #lines)
			end

			for i=0,#lines-1 do
				term.setCursorPos(tx, ty + (1 * i))
				term.write(lines[i+1])
			end
		elseif(self.type_id == FIELD_TYPE) then
			term.setCursorPos(tx, ty + 1)
			if(len > self.width) then
				term.write(text:sub(len-self.width))
			else
				term.write(text)
			end
		end
	end
	term.setBackgroundColor(prevColor)
	term.setTextColor(prevTextColor)
end

function TextArea:contains(x, y)
	minx = self.x
	miny = self.y
	maxx = self.x + self.width
	maxy = self.y + self.height

	return x >= minx and x <= maxx and y >= miny and y <= maxy
end

function TextArea:setEnterAction(func)
	if(type(func) == "function") then
		self.enter_action = func or emptyAction
	end
end

function TextArea:getEnterAction()
	return self.enter_action
end

function TextArea:addKeyAction(key, func)
	key = string.lower(key)
	assert(key and func, "Requires a String and a Function! One was Nil!", 2)
	assert(type(key) == "string" and type(func) == "function", "Expected String and Function, Received "..type(key).." and "..type(func).."!", 2)

	self.char_actions[key] = func
end

function TextArea:removeKeyAction(key)
	key = string.lower(key)
	self:addKeyAction(key, emptyAction)
end

function TextArea:getKeyActions()
	return self.char_actions
end

function TextArea:setVisible(bool)
	self.visible = (bool ~= nil) and bool or self.visible
	self:draw()
end

function TextArea:isVisible()
	return self.visible
end
