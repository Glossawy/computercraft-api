--[[
	CC Config API v1.0.0 by Glossawy (Glossawy@GitHub, no email provided)

	An API port of the RoboLib Configuration API that is heavily inspired by MinecraftForge's 
	Configuration implementation, faithful to it's style. The API is meant to be a bit more stripped down but 
	just as functional. 

	The API revolves around the Configuration object which is created calling cc_config.new, all organization is handled
	internally, although the ConfigValue objects can be accessed using the Configuration:get method. The GET methods also
	act to SET the value to the default if the value does not yet exist.

	It is worth note that the default parent directory (if none is provided as the second parameter) is /.config-tmp/VERSION
	(i.e. /.config-tmp/1.0.0 for v1.0.0 of this API).
]]--

_API_NAME = 'CC Config'
_CONFIG_VERSION = '1.0.0'
_CONFIG_DEBUG = false

-- Bit API unused since these can be used with floating point and the vlaues ARE greater than 2^32 - 1
_MAX_NUMBER = math.pow(2, 53)
_MIN_NUMBER = -1 * _MAX_NUMBER

local infotag, warntag, errtag = 'INFO', 'WARN', 'ERR'

LogLevels = {
	INFO = infotag,
	info = infotag,
	INFORMATION = infotag,
	information = infotag,
	WARN = warntag,
	warn = warntag,
	WARNING = warntag,
	warning = warntag,
	ERR = errtag,
	err = errtag,
	ERROR = errtag,
	error = errtag
}

local function toboolean(x)
	if type(x) == 'boolean' then return x end
	assert(x and (type(x) == 'string' or type(x) == 'number'), 'toboolean parameter must be a string or number!')

	if type(x) == 'string' then
       return x:lower() == 'true' 
    else
        return x > 0
    end
end

-- Initial Type Declarations
local Configuration = {}
local ConfigCategory = {}
local ConfigValue = {
	Type = {
		STRING  = {id = function() return 'S' end, 
					typename = function() return 'string' end,
					cast = function(x) return tostring(x) end
					},
		NUMBER  = {id = function() return 'N' end, 
					typename = function() return 'number' end,
					cast = function(x) return tonumber(x) end
					},
		BOOLEAN = {id = function() return 'B' end, 
					typename = function() return 'boolean' end,
					cast = function(x) return toboolean(x) end
					}
	}
}

-- Metatables
local c_meta = {__index = Configuration}
local cc_meta = {__index = ConfigCategory}
local cv_meta = {__index = ConfigValue}

-- Constants
local GLOBALS_LOADED_NAME = '__cc_config_globals_loaded'
local CONFIG_SEPARATOR = '##############################################################'
local DEFAULT_HOME = '/.config-tmp/'.._CONFIG_VERSION
local LOG_PATH = DEFAULT_HOME..'/log.txt'
local SUFFIX = '.cfg'
local ALLOWED_CHARS = '._-'

-- Helper Functions

function _CC_CONFIG_VERSION()
	return _CC_CONFIG_VERSION
end

function _IS_DEBUG()
	return _CONFIG_DEBUG
end

function _INIT_DEBUG(logtag)
	-- Reserved for future usage for any reason,
	-- such as initializing a mutlishell tab for debugging
	_CONFIG_DEBUG = true

	if logtag then 
		cc_config_log_tag(logtag)
	end
end

-- Internal Use, Prints Entire table. Extensive prints all sub-tables as well.
local function _debug_print_table(tbl, extensive)
	assert(tbl and type(tbl) == 'table', 'not table', 2)

	extensive = extensive or false
	assert(type(extensive) == 'boolean', 'not boolean', 2)

	local res
	if extensive then
		res = '[ '
		for k, v in pairs(tbl) do
			if res ~= '[ ' then
				res = res..'. '
			end

			if type(v) == 'table' then
				res = res..string.format('%s: %s', tostring(k), _debug_print_table(v, true))
			else 
				res = res..string.format('%s: %s', tostring(k), tostring(v))
			end
		end
		res = res..' ]'
	else
		res = '['..table.concat(tbl, ', ')..']'
	end

	return res
end

-- Split string into parts delimited by 'sep' or whitespace if'sep' is undefined
local function split_str(self, sep)
	if not sep then sep = '%s' end

	local parts = {}
	for s in self:gmatch('([^'..sep..']+)') do
		table.insert(parts, s)
	end

	return parts
end

-- Log Only Variables
local _internal_caller = _API_NAME:upper()
local _default_caller = 'USER'
local log_opened = false
local log_time = os.clock()
local log_caller_max_width = #_internal_caller > 8 and #_internal_caller or 8
local log_caller_padding = log_caller_max_width

-- Print a Formatted Log Message to the log file
local function _log(f, msg, caller, level)
	caller = caller or _internal_caller
	level = level or LogLevels.INFO

	if #caller > log_caller_max_width then
		caller = caller:sub(1, log_caller_max_width)
	end

	while #caller < log_caller_padding do
		caller = caller ..' '
	end

	f:write(string.format('[%s][ %4d s ]: %s: %s\n', caller:upper(), os.clock() - log_time, level:upper(), msg))	
end

-- Either retuns the pre-existing loaded log file, or initializes a new file
local function openLogFile()
	local mode = log_opened and 'a' or 'w'
	local f = io.open(LOG_PATH, mode)

	if not log_opened then
		-- Print System Information
		local comp_type = pocket and 'Pocket Computer' or (commands and 'Command Computer' or 'Computer')
		local tech_type = (not commands and colors) and 'an Advanced ' or 'a '
		local mc_version = _G['_MC_VERSION'] or '[undefined]'
		local cc_version = _G['_CC_VERSION'] or '[undefined]'
		local luaj_version = _G['_LUAJ_VERSION'] or '[undefined]'

		f:write('# Log File for '.._API_NAME..' v'.._CONFIG_VERSION..'\n')
		f:write('# by Glossawy (Glossawy@GitHub, no email provided)\n')
		f:write(string.format('# Using LuaJ %s in CC %s for MC %s\n', luaj_version, cc_version, mc_version))
		f:write(string.format('# This is %s%s running %s | %s ID %d <-- Sanity Check\n\n', tech_type, comp_type, os.version(), os.getComputerLabel(), os.getComputerID()))
		_log(f, 'Opened log file', _internal_caller)
		f:flush()
		log_opened = true
	end

	return f
end


-- Log a message to desired debug 
local do_close = true
local function _debug(opts)
	if not _CONFIG_DEBUG then
		return
	end

	-- Options:
	-- __plog: internally used to provide a log file for recursive use, should NOT be specified
	--
	-- B:test: [REQUIRED] whether or not to print
	-- S:msg: [REQUIRED OR msgf w/ fvars] message to log
	-- S:msgf: [REQUIRED w/ fvars or msg] message format to log
	-- T:fvars: [REQUIRED w/msgf or msg] Format Data for msgf 
	-- T:lines: [OPTIONAL] a table of Debug Options (as defined above), must be non-mapped

	local lf = (not do_close) and opts.__plog or openLogFile()

	if not opts.lines then
		assert(opts.msg or (opts.msgf and opts.fvars), 'Missing Error Message'..((opts.msgf and not opts.fvars) and ' - fvars not provided!' or ''))

		if opts.msgf then
			opts.msg = string.format(opts.msgf, unpack(opts.fvars))
		end

		opts.caller = opts.caller or _internal_caller
		opts.level = opts.level or 'INFO'

		_log(lf, opts.msg, opts.caller, opts.level)
	else
		local prev_do_close = do_close
		do_close = false

		for i, v in ipairs(opts.lines) do
			v.__plog = lf
			_debug(v)
		end

		do_close = prev_do_close
	end

	if do_close then
		lf:flush()
		lf:close()
	end
end

local function _error(message, level, caller) 
	_debug({ msg=table.concat(split_str(message, '\r?\n'), ' | '), caller=caller, level=LogLevels.ERROR})
	error(message, level)
end

-- Trim Leading and Trailing whitespace
local function trim_str(s)
  return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
end

-- Returns true if is alphanumeric or one of the allowed characters
local function isValidChar(c)
	return c:match('%w') or ALLOWED_CHARS:find(c, 1, true) 
end

-- Returns true if all characters pass the test used in isValidChar
local function isValid(str)

	for s in str:gmatch('.') do
		if not isValidChar(s) then
			return false
		end
	end

	return true
end

-- Gets true length of table (as opposed to index-based when using the '#' operator)
local function len(table)
	local count = 0

	for k,_ in pairs(table) do
		if table[k] ~= nil then
			count = count + 1
		end
	end

	return count
end

--[[
	Applies a function to each value of a table, if a value is returned by this
	function, that value is returned and the iteration stops. A function that returns nothing
	WILL apply to ALL elements.

	This function uses pairs() since only the value matters and the key is ignored, therefore
	this works for all tables. Even tables with non-numeric indices.
]]--
local function foreach(table, func, ...)
	local args = {...}
	local val = nil

	for _, v in pairs(table) do
		if len(args) > 0 then
			val = func(v, unpack(args))
		else
			val = func(v)
		end

		if val ~= nil then
			break
		end
	end

	return val
end

--[[
	Applies a function to each value of a table, if a value is returned by
	this function, the index of the element on which the function returned a value
	will be returned. Otherwise -1 is returned and the function applies to ALL elements.

	This function only works for tables where ipairs works properly.
]]--
local function iforeach(table, func, ...)
	local args = {...}
	local idx

	for i, v in ipairs(table) do
		if len(args) > 0 and func(v, unpack(args)) then
			idx = i
		elseif  len(args) == 0 and func(v, unpack(args)) then
			idx = i
		end

		if idx then
			break
		end
	end

	return idx or -1
end

-- Returns true if the table contains a key-value pair that uses the given key
local function containsKey(table, key)
	assert(table and key, 'missing parameter', 2)
	assert(type(table) == 'table' and type(key) == 'string', 'type mismatch', 2)

	for k, v in pairs(table) do
		if k == key and not not v then
			return true
		end
	end

	return false
end

-- Simply Opens and Closes a file, ensures creation
local function touch(path)
	io.open(path, 'w'):close()
end

-- Returns the remainder of division of a by b.
local function mod(a, b)
	return a - math.floor(a/b)*b
end

-- Determines the ConfigValue.Type value represented by id
local function getTypeFor(id) 
	return foreach(ConfigValue.Type, function(val) return val.id() == id and val or nil end)
end

-- Determines if 'values' is of the given type. If table, checks all elements.
local function isType(typename, values)
	assert(type(typename) == 'string', 'isType\'s typename parameter MUST be a string!', 2)
	assert(values ~= nil, 'values must NOT be nil!', 2)

	if type(values) == 'table' then
		for i=1,#values do
			if type(values[i]) ~= typename then
				return false
			end
		end

		return true
	else
		return type(values) == typename
	end
end

-- Checks if two objects are of the same type, delegates to isType
local function typeEquals(x, y)
	return type(x) == type(y)
end

-- Checks if ALL parameters are of type 'table'
local function isTable(...) 
	return isType('table', {...})
end

-- Checks if ALL parameters are of type 'string'
local function isString(...)
	return isType('string', {...})
end

-- Checks if ALL parameters are of type 'number'
local function isNumber(...)
	return isType('number', {...})
end

-- Checks if ALL parameters are a number (via isNumber) and whole.
local function isInteger(...)
	local params = {...}

	if not isNumber(unpack(params)) then
		return false
	end

	for i=1,#params do
		if mod(params[i], 1) ~= 0 then
			return false
		end
	end

	return true
end

local function table_to_string(tbl, sep, deep)
	local first = true
	local res

	for _, v in ipairs(tbl) do
		local cur
		if deep and isTable(v) then
			cur = '[ '..table_to_string(v, sep, deep)..' ]'
		else
			cur = tostring(v)
		end

		res = first and cur or (res..', '..cur)
		first = false
	end

	if #tbl == 0 then
		res = ''
	end

	return res
end

-- Returns a shallow copy of a table, sub-tables are not copied.
local function shallow_copy(orig)
	local copy
	if type(orig) == 'table' then
		copy = {}
		for k, v in pairs(orig) do
			copy[k] = v
		end
	else
		copy = orig
	end

	return copy
end

-- Returns a deep copy of a table, sub-tables ARE copied
local function deep_copy(orig)
	local copy
	if type(orig) == 'table' then
		copy = {}
		for k, v in pairs(orig) do
			copy[deep_copy(k)] = deep_copy(v)
		end
	else
		copy = orig
	end

	return copy
end

-- A map of tables to read-only proxies (views)
local _proxies = setmetatable({}, {__mode = 'k'})

-- API Functions

--[[
	Returns the value type related to the descriptor as found in the ids of ConfigValue.Type tables. 

	'string'  or 's' or 1 = ConfigValue.Type.STRING
	'number'  or 'n' or 2 = ConfigValue.Type.NUMBER
	'boolean' or 'b' or 3 = ConfigValue.Type.BOOLEAN
]]--
function getValueType(descriptor)
	local res

	if isString(descriptor) then

		-- 1 char id
		if #descriptor == 1 then
			for _, v in pairs(ConfigValue.Type) do
				if descriptor:upper() == v.id() then
					res = v
				end
			end
		else
			res = ConfigValue.Type[descriptor:upper()]
		end
	elseif isInteger(descriptor) then
		local idx = mod(descriptor, len(ConfigValue.Type))
		local tmp = 1

		for _, v in pairs(ConfigValue.Type) do
			if tmp == idx then
				res = v
				break
			end

			tmp = tmp + 1
		end
	end

	assert(res, 'Invalid Descriptor! Must either be a typename of string, number or boolean or must be an integer.', 2)
	return res
end

function new(name, homeDirectory, fileHeaderDescription)

	local args = {name, homeDirectory, fileHeaderDescription}

	name = table.remove(args, 1)
	fileHeaderDescription = table.remove(args)
	homeDirectory = #args > 0 and table.remove(args) or DEFAULT_HOME

	local obj = {
		filename = name..SUFFIX,
		path = string.format('%s/%s', homeDirectory, name..SUFFIX),
		categories = {},
		changed = false,
		_p_file_name = nil,
		_header_desc = fileHeaderDescription or '',
		_cfg_log_id = name:upper()
	}

	setmetatable(obj, c_meta)
	obj:load()

	_debug({msgf='Config File \'%s\' [%s]', fvars={name, obj.path}})
	return obj
end

local function determineValueType(val)
	if not isTable(val) then
		_debug({ msgf='Determining Identifier of "%s" to \'%s\'', fvars={tostring(val), type(val):sub(1,1)}})
		return type(val):sub(1,1)
	else
		_debug({ msg='Determining Identifier for table: [ '..table_to_string(val, ', ')..' ]'})
		local t
		for _, v in pairs(val) do
			if isTable(v) then
				t = determineValueType(v)
			else
				t = type(v):sub(1,1)
			end

			if t then return t end
		end
	end

	return nil
end

function Configuration:getName()
	return self.filename:sub(1, #self.filename - 4)
end

function Configuration:getFileName()
	return self.filename
end

function Configuration:_logid()
	return self._cfg_log_id
end

function Configuration:get(category, key, defaultValue, comment, min, max, valids)
	assert(category and key and defaultValue ~= nil, 'Settings require at least a Category, Key/Name and default value')

	category = category:lower()

	local v_type = determineValueType(defaultValue)
	local cat = self:getCategory(category)
	
	if not isTable(valids) then 
		valdis = not not valids and {v_vals} or nil 
	end 

	local prop
	if cat:containsKey(key) then
		prop = cat:get(key)

		if not prop:getType() then
			prop = _cvalue(key, v_type, prop:getRaw(), prop:getValidValues())
			cat:put(key, prop)
		end
	else
		prop = _cvalue(key, v_type, defaultValue, valids)
		
		prop:setValue(defaultValue)
		cat:put(key, prop)
	end

	prop:setDefault(defaultValue)

	if comment then 
		prop:setComment(comment)
	end

	if min then prop:setMin(min) end
	if max then prop:setMax(max) end


	if _CONFIG_DEBUG then
		if prop:isListValue() then
			_debug({msgf=self:_logid()..' GET [Cat: %s, Key: %s, val: %s]', fvars={category, key, prop:getString()}})
		end
	end

	return prop
end

function Configuration:resetChanged() 
	self.changed = false
	foreach(self.categories, function(cat) cat:_reset_changed() end)
end

function Configuration:hasChanged()
	if self.changed then return true end

	for _, v in pairs(self.categories) do
		if v:hasChanged() then
			return true
		end
	end

	return false
end

local function matchAndFirst(s, pattern)
	local res
	local matches = 0

	for match in s:gmatch(pattern) do
		if not res then
			res = match
		end

		matches = matches + 1
	end

	return not not res, res, matches
end

local function getQualifiedName(name, parentNode)
	return parentNode and getQualifiedName(parentNode.id, parentNode.parent)..'.'..name or name
end

function Configuration:load()
	if not fs.exists(self.path) then 
		self.categories = {}
		touch(self.path)

		return
	end

	local out = io.open(self.path, 'r')

	-- Parsing
	local cur_cat
	local cur_type
	local cur_name
	local tmp_list
	local line_num = 0

	for cline in out:lines() do
		line_num = line_num + 1

		local s_success, s_match, s_count = matchAndFirst(cline, 'START: \"([^\"]+)\"')
		local e_success, e_match, e_count = matchAndFirst(cline, 'END: \"([^\"]+)\"')

		if s_success then
			self._p_file_name = s_match
			self.categories = {}
		elseif e_success then
			self._p_file_name = e_match
		else

			local n_start = -1
			local n_end = -1
			local skip = false
			local quoted = false
			local is_first_nonwhitespace = true

			local i = 0
			for c in cline:gmatch('.') do
				i = i + 1
				if isValidChar(c) or (quoted and c ~= '"') then
					if n_start == -1 then
						n_start = i
					end

					n_end = i
					is_first_nonwhitespace = false
				elseif c:match('%s+') then

				else
					if c == '#' then
						if not tmp_list then
							skip = true
						end
					elseif c == '"' then
						if not tmp_list then
							if quoted then
								quoted = false
							end

							if not quoted and n_start == -1 then
								quoted = true
							end
						end
					elseif c == '{' then
						if not tmp_list then
							cur_name = cline:sub(n_start, n_end)
							local qual_name = getQualifiedName(cur_name, cur_cat)

							local tmp_cat = self.categories[qual_name]
							if not tmp_cat then
								cur_cat = _ccategory(cur_name, cur_cat)
								self.categories[qual_name] = cur_cat
							else
								cur_cat = cat
							end
							cur_name = nil
						end 
					elseif c == '}' then
						if not tmp_list then
							if not cur_cat then
								out:close()
								_error(string.format('Corrupt Config! Attempt to close too many categories: %s:%s', self._p_file_name, tostring(line_num)), 2)
							end

							cur_cat = cur_cat.parent
						end

					elseif c == '=' then
						if not tmp_list then
							cur_name = cline:sub(n_start, n_end)

							if not cur_cat then
								out:close()
								_error(string.format("'%s' has no scope in '%s:%s'", cur_name, self._p_file_name, tostring(line_num)), 2)
							end

							local prop = _cvalue(cur_name, cur_type, cline:sub(i + 1))
							cur_cat:put(cur_name, prop)
							break
						end
					elseif c == ':' then
						if not tmp_list then
							cur_type = getTypeFor(cline:sub(n_start, n_end):sub(1, 1))
							n_start = -1
							n_end = -1
						end
					elseif c == '<' then
						if (tmp_list and i == #cline) or (not tmp_list and i ~= #cline) then
							out:close()
							_error(string.format('Malformed list "%s:%s"', self._p_file_name, tostring(line_num)), 2)
						elseif i == #cline then
							cur_name = cline:sub(n_start, n_end)

							if not cur_cat then
								out:close()
								_error(string.format("'%s' has no scope in '%s:%s'", cur_name, self._p_file_name, tostring(line_num)), 2)
							end

							tmp_list = {}
							skip = true
						end

					elseif c == '>' then
						if not tmp_list then
							out:close()
							_error(string.format('Malformed list "%s:%s"', self._p_file_name, tostring(line_num)), 2)
						end

						if is_first_nonwhitespace then
							cur_cat:put(cur_name, _cvalue(cur_name, cur_type, deep_copy(tmp_list)))
							cur_name = nil
							tmp_list = nil
							cur_type = nil
						end
					elseif c == '~' then
					
					else
						if not tmp_list then
							out:close()
							_error(string.format('Unknown character "%s" in %s:%s', c, self._p_file_name, tostring(line_num)), 2)
						end
					end

					is_first_nonwhitespace = false
				end

				if skip then break end
			end

			if quoted then
				out:close()
				_error(string.format('Unmatched quote in %s:%s', self._p_file_name, tostring(line_num)), 2)
			elseif tmp_list and not skip then
				table.insert(tmp_list, trim_str(cline))
			end

		end
	end

	self:resetChanged()
	out:close()
end

function Configuration:_save(output)
	for k, v in pairs(self.categories) do
		if not v:isChild() then
			v:writeOut(output, 0)
			v:write('\n')
		end
	end
end

function Configuration:save()
	local out = io.open(self.path, 'w')

	out:write('# '..self._header_desc..' Configuration File\n\n')
	self:_save(out)

	out:close()
end

local function contains_str(str, c)
	for ch in str:gmatch('.') do
		if ch == c then
			return true
		end
	end

	return false
end

function Configuration:getCategory(category)
	local res = self.categories[category]

	if not res then
		if contains_str(category, '.') then
			local hierarchy = split_str(category, '\\.')
			local parent = self.categories[hierarchy[1]]

			if not parent then
				parent = _ccategory(hierarchy[1])
				self.categories[parent:getQualifiedName()] = parent
				self.changed = true
			end

			for i=2,#hierarchy do
				local n = getQualifiedName(hierarchy[i], parent)
				local nchild = self.categories[n]
				
				if not nchild then
					nchild = _ccategory(hierarchy[i], parent)
					self.categories[n] = nchild
					self.changed = true
				end

				res = nchild
				parent = nchild
			end
		else
			res = _ccategory(category)
			self.categories[category] = res
			changed = true
		end
	end

	return res
end

function Configuration:removeCategory(category_obj)
	local _self = self
	foreach(category_obj:getChildren(), function(c) _self:removeCategory(c) end)

	if containsKey(self.categories, category_obj:getQualifiedName()) then
		self.categories[category_obj:getQualifiedName()] = nil

		if category_obj.parent then
			category_obj.parent:removeChild(category_obj)
		end

		changed = true
	end
end

function Configuration:setCategoryComment(category, comment)
	self.categories[category]:setComment(comment)
end

function Configuration:getCategoryNames()
	local names = {}

	for k, _ in pairs(self.categories) do
		table.insert(names, k)
	end

	return names
end

function Configuration:getString(name, category, defaultValue, comment, v_vals)
	local prop = self:get(category, name, defaultValue)

	if not isTable(v_vals) then 
		v_vals = not not v_vals and {v_vals} or nil 
	end 

	comment = comment or ''

	prop:setValids(v_vals)
	prop:setComment(comment..' [default: '..defaultValue..']')

	local _p_valids = prop:getValidValues()

	if isTable(_p_valids) then
		_p_valids = '< '..table.concat(_p_valids, ', ')..' >'
	else
		_p_valids = '< '..tostring(_p_valids)..' >'
	end


	_debug({msgf=self:_logid()..' GET Valid Values: < %s >',fvars={(_p_valids == '<  >' or _p_valids == '< nil >') and 'any' or _p_valids}})

	return prop:getString()
end

function Configuration:getNumber(name, category, defaultValue, comment, min, max)
	local prop = self:get(category, name, defaultValue)
	
	if not isTable(v_vals) then 
		v_vals = not not v_vals and {v_vals} or nil
	end 

	comment = comment or ''

	prop:setComment(comment..' [default: '..tostring(defaultValue)..']')

	if max then prop:setMax(max) end
	if min then prop:setMin(min) end

	_debug({msgf=self:_logid()..' GET [Cat: %s, Key: %s, val: %d, range: [%f, %f]]', fvars={category, name, prop:getNumber(), prop:getMin(), prop:getMax()}})

	return prop:getNumber()
end

function Configuration:getBoolean(name, category, defaultValue, comment)
	local prop = self:get(category, name, defaultValue)
	
	if not isTable(v_vals) then 
		v_vals = not not v_vals and {v_vals} or nil
	end 

	comment = comment or ''

	prop:setComment(comment..' [default: '..tostring(defaultValue)..']')

	_debug({msgf=self:_logid()..' GET [Cat: %s, Key: %s, val: %s]', fvars={category, name, prop:getString()}})

	return prop:getBoolean()
end

function Configuration:getList(name, category, defaultValue, comment, v_vals)
	local prop = self:get(category, name, defaultValue)
	
	if not isTable(v_vals) then 
		v_vals = not not v_vals and {v_vals} or nil
	end 

	comment = comment or ''

	local default_str = '[ '

	for i, v in ipairs(defaultValue) do
		if i ~= 1 then
			default_str = default_str..', '
		end

		default_str = default_str..tostring(v)
	end
	default_str = default_str..' ]'

	prop:setValids(v_vals)
	prop:setComment(comment..' [default: '..default_str..']')

	local _p_valids = prop:getValidValues()

	if isTable(_p_valids) then
		_p_valids = '< '..table_to_string(_p_valids, ', ')..' >'
	else
		_p_valids = '< '..tostring(_p_valids)..' >'
	end

	_debug({msgf=self:_logid()..' GET Valid Values: %s',fvars={(_p_valids == '<  >' or _p_valids == '< nil >') and 'any' or _p_valids}})

	return prop:getList()
end

function Configuration:getPath()
	return self.path
end

-- Config Category Declarations

function _ccategory(name, parent)
	assert(name, 'Config Category MUST have a name!')

	local cc = {
		id = name,
		parent = parent,
		comment = nil,
		children = {},
		settings = {},
		s_count = 0,
		changed = false
	}

	if parent then
		table.insert(parent.children, cc)
	end

	setmetatable(cc, cc_meta)
	return cc
end

local function getRoot(cur)
	return cur.parent and getRoot(cur.parent) or cur
end

local function indent(i)
	local res = ''
	for s=1,i do
		res = res..'   '
	end

	return res
end

function ConfigCategory:setComment(comment)
	assert(isString(comment), 'Comment must be a string!', 2)

	self.comment = comment
	return self
end

function ConfigCategory:getName()
	return self.id
end

function ConfigCategory:getComment()
	return self.comment
end

function ConfigCategory:getQualifiedName()
	return getQualifiedName(self.id, self.parent)
end

function ConfigCategory:getRoot()
	return getRoot(self)
end

function ConfigCategory:isChild()
	return self.parent ~= nil
end

function ConfigCategory:getValues()
	return shallow_copy(self.settings)
end

function ConfigCategory:get(key)
	return self.settings[key]
end

function ConfigCategory:containsKey(key)
	return containsKey(self.settings, key)
end

function ConfigCategory:write(file, newLine, ...)
	assert(file, 'File must not be null!', 2)

	local data = {...}
	for _, v in pairs(data) do
		file:write(tostring(v))
	end

	if newLine then
		file:write('\n')
	end
end

function ConfigCategory:writeOut(file, indentation)
	local p0 = indent(indentation)
	local p1 = indent(indentation + 1)
	local p2 = indent(indentation + 2)

	if self.comment and #self.comment ~= 0 then
		self:write(file, true, p0, CONFIG_SEPARATOR)
		self:write(file, true, p0, '# ', self:getName())
		self:write(file, true, p0, '#------------------------------------------------------------#')

		foreach(split_str(self.comment, '\r?\n'), function(str)
			self:write(file, true, p0, '# ', str)
		end)

		self:write(file, true, p0, CONFIG_SEPARATOR, '\n')
	end

	local name = self.id
	if not isValid(name) then
		name = '"'..name..'"'
	end

	self:write(file, true, p0, name, ' {')
	for _, v in pairs(self.settings) do
		local val = v

		if val.comment then
			if i ~= 1 then
				self:write(file, true)
			end

			for i, line in ipairs(split_str(val.comment, '\r?\n')) do
				self:write(file, true, p1, '# ', line)
			end
		end

		local val_name = val:getName()
		if not isValid(val_name) then
			val_name = '"'..val_name..'"'
		end

		if val:isListValue() then
			self:write(file, true, p1, val:getType().id(), ':', val_name, ' <')

			for _, v in pairs(val:getList()) do
				self:write(file, true, p2, v)
			end

			self:write(file, true, p1, ' >')
		elseif not val:getType() then
			self:write(file, true, p1, val_name, '=', val:getString())
		else
			self:write(file, true, p1, val:getType().id(), ':', val_name, '=', val:getString())
		end
	end

	if #self.children > 0 then
		self:write(file, true)
	end

	for _, child in pairs(self.children) do child:writeOut(file, indentation + 1) end
	self:write(file, true, p0, '}', '\n')
end

function ConfigCategory:hasChanged()
	if self.changed then return true end

	for _, v in pairs(self.settings) do
		if v:hasChanged() then
			return true
		end
	end

	return false
end

function ConfigCategory:_reset_changed()
	self.changed = false

	for _, v in pairs(self.settings) do
		v:resetChanged()
	end
end

function ConfigCategory:put(key, setting)
	assert(isString(key), 'Key must be a string!', 2)

	self.changed = true
	self.settings[key] = setting
end

function ConfigCategory:remove(key)
	self.changed = true

	local idx = 1
	local val
	for k, v in pairs(self.settings) do
		if k == key then
			val = self.settings[k]
			self.settings[k] = nil
			break
		end

		idx = idx + 1
	end

	return val
end

function ConfigCategory:clear()
	self.changed = true

	while len(self.settings) > 0 do
		table.remove(self.settings)
	end
end

function ConfigCategory:contains(setting)
	assert(setting, 'Setting is Nil', 2)
	
	for _,v in pairs(self.settings) do
		if v == setting then
			return true
		end
	end

	return false
end

function ConfigCategory:keys()
	local _keys = {}

	for k, _ in pairs(self.settings) do
		table.insert(_keys, k)
	end

	return _keys
end

function ConfigCategory:settings()
	local _entries = {}

	for k, v in pairs(self.settings) do
		table.insert(_entires, {k, v})
	end

	return _entries
end

function ConfigCategory:getChildren()
	return deep_copy(self.children)
end

function ConfigCategory:removeChild(child)
	local idx = iforeach(self.children, function(v) return v == child end)

	if idx > 0 then
		table.remove(self.children, idx)
		self.changed = true
	end
end

-- Config Value Declarations

function _cvalue(name, valueType, values, validValues)
	assert(name and valueType and values ~= nil, 'A ConfigValue must start with AT LEAST a name, type and value!', 2)

	if isString(valueType) or isNumber(valueType) then
		valueType = getValueType(valueType)
	end

	assert(isTable(valueType), 'ValueType must be a valid ConfigValue.Type table or a typename... (e.g. \'string\', \'number\' or \'boolean\'', 2)

	validValues = validValues or {}

	if not isTable(validValues) then
		validValues = {validValues}
	end

	local cv = {
		id = name,
		comment = nil,
		value = values,
		default = deep_copy(values),
		value_type = valueType,
		is_list = isTable(values),
		valid_values = shallow_copy(validValues),
		min_val = _MIN_NUMBER,
		max_val = _MAX_NUMBER,
		changed = false
	}

	setmetatable(cv, cv_meta)
	return cv
end

function ConfigValue:setName(new_name)
	self.id = new_name

	return self
end

function ConfigValue:setComment(comment)
	self.comment = comment

	return self
end

function ConfigValue:setValue(value)
	if typeEquals(self.value, value) then
		if self.is_list then
			self.value = deep_copy(value)
		else
			self.value = value
		end
	else
		self.value = self.value_type.cast(value)
	end

	self.changed = true

	return self
end

function ConfigValue:set(value)
	self:setValue(value)
end

function ConfigValue:setDefault(new_default)
	assert(new_default ~= nil, 'new default value must be non-nil', 2)
	assert(self:isListValue() or isType(self.value_type.typename(), new_default), 'new default vlaue must be of the appropriate type: '..self.value_type.typename(), 2)

	if isTable(new_default) then
		self.default = deep_copy(new_default)
	else
		self.default = new_default
	end

	return self
end

function ConfigValue:setToDefault()
	if self.is_list then
		self.value = shallow_copy(self.default)
	else
		self.value = self.default
	end

	return self
end

function ConfigValue:isDefault()
	if self.is_list then
		for key, val in pair(self.default) do
			if val ~= self.value[key] then
				return false
			end
		end

		return true
	else
		return self.default == self.value
	end
end

function ConfigValue:hasChanged()
	return self.changed
end

function ConfigValue:setMin(minimum)
	assert(isNumber(minimum), 'min and max MUST be numbers!', 2)

	self.min_val = minimum
	return self
end

function ConfigValue:setMax(maximum)
	assert(isNumber(minimum), 'min and max MUST be numbers!', 2)

	self.max_val = maximum
	return self
end

function ConfigValue:setValids(valids)
	if not valids or (isTable(valids) and #valids == 0) then return end

	self.valid_values = isTable(valids) and valids or {valids}

	return self
end

function ConfigValue:getName()
	return self.id
end

function ConfigValue:getMin()
	return self.min_val
end

function ConfigValue:getMax()
	return self.max_val
end

function ConfigValue:getValidValues()
	return deep_copy(self.valid_values)
end

function ConfigValue:isListValue()
	return self.is_list
end

function ConfigValue:getRaw()
	if self.valid_values and len(self.valid_values) > 0 then
		local success = false
		for i, v in ipairs(self.valid_values) do
			if v == self.value then
				success = true
				break
			end
		end

		if not success then
			_error(string.format('"%s" is not a valid value for option \'%s\':\n\nValid Values:\n[ %s ]', self.value, self.id, table.concat(self.valid_values, ',\n  ')), 2)
		end
	end

	return self.value
end

function ConfigValue:getString()
	local err, val

	if self.is_list then
		err, val = pcall(table_to_string, self:getRaw(), ', ')
	else
		err, val = pcall(tostring, self:getRaw())
	end

	assert(err, val, 2)

	return self.is_list and '< '..val..' >' or val
end

function ConfigValue:inRange(num)
	return num >= self:getMin() and num <= self:getMax()
end

function ConfigValue:getNumber()
	local err, val = pcall(tonumber, self:getRaw())
	assert(err and val ~= nil, 'Cannot get \''..self:getRaw()..'\' as', 2)

	if not self:inRange(val) then
		_error(string.format('number value \'%f\' is not within range for \'%s\'\n\nValue Range: [%f, %f]', 
			val,
			self:getName(), 
			self:getMin(), 
			self:getMax()), 2)
	end

	return val
end

function ConfigValue:getBoolean()
	local err, val = pcall(toboolean, self:getRaw())
	assert(err, val, 2)

	return val
end

function ConfigValue:getList()
	assert(self.is_list, 'value is not a list!', 2)

	if self.valid_values and len(self.valid_values) > 0 then
		for _, v in ipairs(self.value) do
			local success = false
			for _2, v2 in ipairs(self.valid_values) do
				if tostring(v) == tostring(v2) then
					success = true
					break
				end
			end

			if not success then 
				_error(string.format('"%s" is not a valid value in list \'%s\':\n\n Valid Values: [ %s ]', v, self.id, table_to_string(self.valid_values, ', ')), 2)
			end
		end
	end

	return self.value
end

function ConfigValue:getType()
	return self.value_type
end

function ConfigValue:getTypename()
	return self.value_type.typename()
end

function ConfigValue:resetChanged()
	self.changed = false
end


-- Dirty Global Stuff and Function Overriding


local _log_tag_func = 'cc_config_log_tag'
local _log_debug_func = 'cc_config_debug'
local _log_error_func = 'cc_config_error'
local _log_debug_enable_func = 'cc_config_init_debug'
local _log_levels_tbl = 'LogLevels'

_G[_log_levels_tbl] = LogLevels

_G[_log_debug_enable_func] = _INIT_DEBUG

_G[_log_tag_func] = function(new_caller)
	assert(new_caller, 'Please provide a log tag to be used! Nil was provided...')
	assert(isString(new_caller), 'Please provide a log tag to be used! Must be string, '..type(new_caller)..' was provided...')

	_default_caller = new_caller
end

_G[_log_debug_func] = function(level, message, ...)
	if #{...} ~= 0 then
		_debug({ msgf=message, fvars={...}, caller=_default_caller, level=level})
	else
		_debug({ msg=message, caller=_default_caller, level=level})
	end
end

_G[_log_error_func] = function(message, ...)
	if #{...} ~= 0 then
		message = string.format(message, ...)
	end

	_error(message, 2, _default_caller)
end

-- Unloading override to unload our globals. Restore on unload.
if not _G[GLOBALS_LOADED_NAME] then

	local nativeUnloadAPI = os.unloadAPI
	local nativeConcat = table.concat
	os.unloadAPI = function(api)
		if not _G[GLOBALS_LOADED_NAME] then nativeUnloadAPI(api) end
		if not _G[api] then return end

		local obj = _G[api]
		if obj['_API_NAME'] and obj._API_NAME == _API_NAME then
			_debug({msg='Unloading Global APIs...'})

			_G[_log_levels_tbl] = nil
			_G[_log_debug_enable_func] = nil
			_G[_log_tag_func] = nil
			_G[_log_debug_func] = nil
			_G[_log_error_func] = nil

			_debug({msg='Globals Unloaded! Restoring original os.unloadAPI...'})
			os.unloadAPI = nativeUnloadAPI
			table.concat = nativeConcat
			_G[GLOBALS_LOADED_NAME] = false
		end

		nativeUnloadAPI(api)
	end

	table.concat = function(tbl, sep)
		local success, val = pcall(table_to_string, tbl, sep, false)

		if not success then
			_debug({msgf='Failed to concatenate table using table_to_string! [tostring(tbl): %s, sep: %s]', fvars={tostring(tbl), tostring(sep)}, level=LogLevels.WARN})
			val = table.concat(tbl, sep)
		end

		return val
	end

	_G[GLOBALS_LOADED_NAME] = true

end
