--[[
	Object Oriented Buttons v1.1 by Glossawy
	(Yes I know this name is creative)

	This API was created to create a coherent, flexible and easy to use
	button API using Object Oriented Programming to be used in a future 
	larger GUI Package. This was NOT  intended for widespread use until 
	recently and although I know there are tons of GUI API's out there, 
	I wanted this to be one of them. I dont see TOO many Object Oriented 
	one's anyway. 

	This Package features two Classes, Button and ButtonGroup. Button
	is the main focus with many getters and setters and other functions.
	They can be created by calling button.create. For more information on
	that, please see the comments preceding button.create. ButtonGroup was
	created to basically wrap a table of buttons and allow easier maintenance
	of these groups instead of individual groups on a button by button basis
	or as many tables in a 2D table. This is similar, to some degree, to how
	javax.swing manages JButtonGroups. As such, ButtonGroups are ENTIRELY created
	to manage A RadioButton assortment. Where only one button in a group is active
	at once and there will never be an instance where all buttons are inactive
	with the initial startup being an exception.

	Because they are two separate classes they can be handled individually MUCH more
	easily. Since each one is independent; modifying a ButtonGroup will in most cases
	leave the button's inside of them untouched.

	This API is open to additions and fixes. Testing has been done on the basics of Button
	creation and manipulation as well as Radio Buttons of size 9 with no noticeable issue...
	but that might be my programmer filter. 

	Please Use This Code and the Wiki for How to Contribute and how to Format if you decide to,
	this code is distribute using the MIT License, basically, do whatever you want. Its code
	for utilities to be used in programming inside of a game... how am I ever going to benefit
	from a Viral or Closed Source license? 

	A Contact Address for Comment is no email provided
	Issues should be reported to GitHub Issues: github.com/Glossawy/computercraft-api

	* This was inspired, to some degree, by Java's Swing Package Extension
]]

-- TODO Coroutined Timer Event Consumer

local Button = {}			-- Class Container for Button
local ButtonGroup = {}		-- Class Container for ButtonGroup
local buttons = {}			-- List of All Buttons for Intrnal Use

local setBackground = term.setBackgroundColor	-- Store REAL term.setBackgroundColor Method
local setTextCol = term.setTextColor
local prevColor = colors.black					-- Previous Color (Starts as Black)
local curColor = colors.black 					-- Current Color (Starts as Black)
local prevTextColor = colors.white
local curTextColor = colors.white
local floor = math.floor						-- Alias for math.floor
	
defaultDelay = 0.3			-- A Default Delay for Flashable Buttons (Openly Modifyable)

local button_meta = {__index = Button}
local button_group_meta = {	__index = ButtonGroup}

-- TERMINAL METHOD OVERRIDES
-- This Delegation is done to keep track of previous colors
function term.setBackgroundColor(color)
	prevColor = curColor
	curColor = color
	setBackground(color)
end

function term.setTextColor(color)
	prevTextColor = curTextColor
	curTextColor = color
	setTextCol(color)
end
--

-- A Modulus Function as a Replacement for the infix Modulus Operator (%)
local function mod(a, b)		
	return a - math.floor(a/b) * b
end

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

--[[
	Returns a new Button Instance with 4 Required Parameters and 4 Optional Parameters.

	REQUIRED:
	x - X Position of Button Origin (Origin at Top Left of Button)
	y - Y Position of Button Origin (Origin at Top Left of Button)
	width - Width of Button, distance to the right of origin in columns
	height - Height of Button, distance vertically downwards from origin in rows

	OPTIONAL:
	text - Initial Text on Button (Centered)
	on_color - Color to be Displayed when the button is "On" or Activated
	off_color - Color to be Displayed when the button is "Off" or De-activated
	text_color - Color to be Displayed for Any Button Text
	action - The initial action to be fired when the button is toggled.

	NOTE: All Actions are Fired when the button is TOGGLED, NOT ACTIVATED.
	This means all actions will fire if the button is toggled to "off" or "on"
	to allow the user to handle both states (a redstone signal for instance).

	The button is defaulted to the following:
	text = "" (empty string) if none is provided
	on_color = colors.green if none is provided
	off_color = colors.red if none is provided
	cur_color = off_color ALWAYS
	text_color = colors.white if none is provided
	actions = table consisting of either action or nothing (if no action provided)
	toggleable = true ALWAYS, this means the button will not "flash" unless this is set to false
	timer_delay = defaultDelay (which is modifyable but itself defautled to 0.25 seconds), this is the delay
				  for when the button is flashed. Determines how long it is flashed.
	group = nil ALWAYS, this is the ButtonGroup this button belongs to. This is assigned by ButtonGroup ONLY
]]
function new(x, y, width, height, text, on_color, off_color, text_color, action)
	assert(x and y and width and height, "A Button REQUIRES An X coordinate, Y coordinate, Width, and Height!", 2)
	
	-- Set Class Properties
 	local b = {
		x = x,
		y = y,
		id = getUUID(),
		width = width,
		height = height,
		text = text or "",
		on_color = on_color or colors.green,
		off_color = off_color or colors.red,
		cur_color = off_color or colors.red,
		text_color = text_color or colors.white,
		actions = action and {action} or {},
		toggleable = true,
		visible = true,
		timer_delay = defaultDelay,
		group = nil
 	}
  	
  	-- Inherit from button table
  	setmetatable(b, button_meta)
  	table.insert(buttons, b)
  	return b, b.id
end

--[[Update's All Button's, if (x, y) coordinates are given
   All button's will be "fired", checking if they contain the (x, y)
   position and toggling/flashing/firing actions if they do.

   If no parameter's are passed, all button's are redrawn.
]]
function update(x, y)
	foreach(buttons, function(btn)
		
		if(not btn.visible) then
			return
		end

		if(x and y) then
			btn:fire(x, y)
		else
			btn:draw()
		end
	end)
end	

-- Get Button for the given ButtonID
function getButtonForID(id)
	return foreach(buttons, function(btn)
		if(btn.id == id) then
			return btn
		end
	end)
end

-- Retrieve Button Object at (x, y)
function getButtonAt(x, y)
	assert(x and y, "Need An X and a Y Coordinate!", 2)

	return foreach(buttons, function(btn)
		if(btn.contains(x, y)) then
			return btn
		end
	end)
end

-- Retrieve ButtonID at (x, y)
function getIDAt(x, y)
	assert(x and y, "Need An X and a Y Coordinate!", 2)
	local btn = getButtonAt(x, y)

	return btn and btn.id or nil
end

-- Internal Method to Clear Screen
local function clearScreen()
	term.clear()
end

-- Internal Redraw Method, Can be Achieved by User via Update with no params
local function redraw()
	clearScreen()
	foreach(buttons, function(btn) btn.draw(); end)
end

local function deregister(btn)
	table.remove(buttons, foreachi(buttons, function(tmp) return tmp.id == btn.id; end))
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

Button.forceClear = forceClear

-- Will Clear this Button from the Screen
function Button:clear()
	if(not self.visible) then
		return
	end	

	self:forceClear()
end

-- Will Draw this Button with its Dimensions
function Button:draw()

	if(not self.visible) then
		return
	end

	self:clear()

	text = self.text

	self.cur_color = self.active and self.on_color or self.off_color
	term.setBackgroundColor(self.cur_color)

	--TODO Add Text Coloring

	sx = self.x
	sy = self.y
	tx = self.x + self.width
	ty = self.y + self.height

	-- This is basically what paintutils does. So why not?
	for y=sy,ty do
		term.setCursorPos(sx, y)
		for x=sx,tx do
			term.write(" ")
		end
	end

	-- Only Draw the Text if it is not nil and not empty
	if(text and #text > 0) then
		len = #text
		tx = (sx + round(self.width/2)) - floor(len/2)
		ty = (sy + floor(self.height/2))

		term.setTextColor(self.text_color)
		term.setCursorPos(tx, ty)
		term.write(text)
		term.setTextColor(prevTextColor)
	end

	-- Set Back to Previous Background Color
	term.setBackgroundColor(prevColor)
end

-- Fire All Actions for this Button
function Button:commitActions()
	foreach(self.actions, function(f) f(self); end)
end

-- Tests to see if a given point is in this Button's bounds
function Button:contains(x, y)
	if(not self.visible) then
		return false
	end

	minx = self.x
	miny = self.y
	maxx = self.x + self.width
	maxy = self.y + self.height

	return (x >= minx and x <= maxx and y >= miny and y <= maxy)
end

-- Toggle Button between On and Off
function Button:toggle()
	self.active = not self.active

	if(self.toggleable and self.group ~= nil) then
		if(self.group.active ~= self) then
			self.group:setActive(self)
		else
			return
		end
	end

	self:draw()
	self:commitActions()
end

function Button:flash(delay)
	if(not delay or type(delay) ~= "number") then
		delay = self.timer_delay
	end

	self.active = true
	self:commitActions()
	self:draw()
	sleep(delay)
	self.active = false
	self:draw()
end

function Button:fire(x, y)
	if(self:contains(x, y)) then
		if(self.toggleable) then
			self:toggle()
		else
			self:flash()
		end
	end
end

function Button:setText(text)
	self.text = text or ""
end

function Button:getText()
	return self.text
end

function Button:setX(x)
	self.x = x
end

function Button:setY(y)
	self.y = y
end

function Button:getX()
	return self.x
end

function Button:getY()
	return self.y
end

function Button:setWidth(width)
	self.width = width or self.width
end

function Button:setHeight(height)
	self.height = height or self.height
end

function Button:getWidth()
	return self.width
end

function Button:getHeight()
	return self.height
end

function Button:reposition(x, y)
	self:clear()
	self.x = x or self.x
	self.y = y or self.y
	self:draw()
end

function Button:resize(width, height)
	self:clear()
	self.width = width or self.width
	self.height = height or self.height
	self:draw()
end

function Button:setDelay(delay)
	self.timer_delay = delay
end

function Button:getDelay()
	return self.timer_delay
end

function Button:setOnColor(color)
	self.on_color = color or self.on_color
	self:draw()
end

function Button:setOffColor(color)
	self.off_color = color or self.off_color
	self:draw()
end

function Button:setTextColor(color)
	self.text_color = color or self.text_color
	self:draw()
end

function Button:getOnColor()
	return self.on_color
end

function Button:getOffColor()
	return self.off_color
end

function Button:getTextColor()
	return self.text_color
end

function Button:setColors(on, off)
	self.on_color = on or self.on_color
	self.off_color = off or self.off_color
	self:draw()
end

function Button:getColors()
	return self.on_color, self.off_color
end

function Button:getCurrentColor()
	return self.cur_color
end

function Button:addAction(action)
	table.insert(self.actions, action)
end

function Button:getActions()
	return self.actions
end

function Button:removeAction(action)
	table.remove(self.actions, foreachi(self.actions, function(other) return other == action; end))
end

function Button:clearActions()
	self.actions = {}
end

function Button:isActive()
	return self.active
end

function Button:setToToggle()
	self.toggleable = true
end

function Button:setToFlash()
	self.toggleable = false
end

function Button:setToggle(toggle)
	assert(type(toggle) == "boolean", "Parameter Must be a Boolean!", 2)
	self.toggleable = toggle
end

function Button:getToggle()
	return self.toggleable
end

function Button:isToggleable()
	return self.toggleable
end

function Button:setVisible(visible)
	if(visible == nil) then
		visible = self.visible
	end

	assert(type(visible) == "boolean", "Boolean Expected, Received "..type(visible), 2)

	self.visible = visible

	if(self.visible == true) then
		self:draw()
	else
		self:forceClear()
	end

end

function Button:isVisible()
	return self.visible
end

function Button:destroy(doUpdate)
	self:setVisible(false)
	self:forceClear()
	deregister(self)

	if(self.group) then
		self.group:removeButton(self)
	end

	self = {}

	if(doUpdate) then
		update()
	end
end

-- ButtonGroup Methods

function newButtonGroup()
	local group = {
		active = nil,
		elements = {}
	}

	setmetatable(group, button_group_meta)
	return group
end

function ButtonGroup:addButton(btn)
	table.insert(self.elements, btn)
	btn.group = self
end

function ButtonGroup:addButtons(...)
	local args = {...}

	foreach(args, function(btn) self:addButton(btn); end)
end

function ButtonGroup:removeButton(btn)
	local index = foreachi(self.elements, function(other) return other.id == btn.id; end)
	if(index) then
		table.remove(self.elements, index)
	end
end

function ButtonGroup:clear()
	foreach(self.elements, function(btn)
		btn.group = nil
	end)

	self.active = nil
	self.elements = {}
end

function ButtonGroup:contains(btn)
	for i=1,#self.elements do
		if(self.elements[i] == btn) then
			return true
		end
	end

	return false
end

function ButtonGroup:setActive(btn)
	assert(self:contains(btn), "Button Must Be a Member of this Group!", 2)
	assert(btn, "You cannot set the active button to nil!", 2)

	if(not btn.visible) then return; end

	if(self.active) then
		self.active.active = false
		self.active:draw()
	end

	self.active = btn
end

function ButtonGroup:destroy()
	self:clear()
	self = {}
end
