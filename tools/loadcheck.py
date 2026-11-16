import lupa, glob, sys

LUA = r'''
cvars = setmetatable({}, {__index = function(t, k) local c = {v = "0"}; rawset(t, k, c); return c end})
local function wrap(c)
	return setmetatable(c, {__index = function(self, key)
		if key == "GetBool" then return function() return self.v ~= "0" end end
		if key == "GetInt" then return function() return tonumber(self.v) or 0 end end
		if key == "GetFloat" then return function() return tonumber(self.v) or 0 end end
		if key == "GetString" then return function() return self.v end end
		return function() return self.v end
	end})
end
function GetConVar(name)
	local c = cvars[name]
	return wrap(c)
end
function CreateConVar(name, default)
	cvars[name] = rawget(cvars, name) or {v = default or "0"}
	return wrap(cvars[name])
end
CreateClientConVar = CreateConVar
CreateClientCVar = CreateConVar
hook = setmetatable({}, {__index = function() return function() end end})
concommand = setmetatable({}, {__index = function() return function() end end})
list = setmetatable({}, {__index = function() return function() return {} end end})
timer = setmetatable({}, {__index = function() return function() return 1 end end})
file = setmetatable({}, {__index = function() return function() return {}, {} end end})
util = setmetatable({}, {__index = function() return function() return {} end end})
net = setmetatable({}, {__index = function() return function() end end})
surface = setmetatable({}, {__index = function() return function() end end})
draw = setmetatable({}, {__index = function() return function() end end})
render = setmetatable({}, {__index = function() return function() end end})
function IsValid() return false end
function LocalPlayer() return nil end
function CurTime() return 0 end
function RealTime() return 0 end
function FrameTime() return 0 end
function SysTime() return 0 end
function clamp(v, a, b) if v < a then return a end if v > b then return b end return v end
math.Clamp = clamp
function AngleDifference(a, b) return ((a - b + 180) % 360) - 180 end
math.AngleDifference = AngleDifference
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function isentity() return false end
function IsColorTable() return false end

local function stubtable()
	return setmetatable({}, {__index = function(t, k)
		local f = function() return stubtable() end
		rawset(t, k, f)
		return f
	end})
end
function FindMetaTable() return stubtable() end
function Vector(x, y, z)
	local v = {x = x or 0, y = y or 0, z = z or 0}
	return setmetatable(v, {
		__index = function(t, k)
			if k == "Length" then return function() return 0 end end
			if k == "LengthSqr" then return function() return 0 end end
			if k == "Forward" or k == "Up" or k == "Right" then return function() return Vector() end end
			if k == "Distance" then return function() return 0 end end
			if k == "ToScreen" then return function() return {x = 0, y = 0, visible = false} end end
			return function() return Vector() end
		end,
		__add = function(a, b) return Vector() end,
		__sub = function(a, b) return Vector() end,
		__mul = function(a, b) return Vector() end,
		__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
	})
end
function Angle(p, y, r)
	local a = {p = p or 0, y = y or 0, r = r or 0}
	return setmetatable(a, {
		__index = function(t, k)
			if k == "Forward" or k == "Up" or k == "Right" then return function() return Vector() end end
			return function() return Angle() end
		end,
		__add = function(a2, b2) return Angle() end,
		__sub = function(a2, b2) return Angle() end
	})
end
angle_zero = Angle(0, 0, 0)
vector_origin = Vector(0, 0, 0)

for i, n in ipairs({"MAT_CONCRETE","MAT_SAND","MAT_DIRT","MAT_SNOW","MAT_GRASS","MAT_METAL","MAT_VENT","MAT_TILE","MAT_GLASS","MAT_GRATE","MAT_PLASTIC","MAT_SLOSH","MAT_WOOD","MAT_SKY","MAT_FLESH","MAT_BLOOD","MAT_ALIENFLESH","MAT_CLIP","MAT_ANTLION","MAT_EGGSHELL","MAT_WARPSHIELD","MAT_GUNSHIP","MAT_FOLIAGE","MAT_COMPUTER","MAT_CONCRETE_BLOCK","MAT_PLASTIC_BARREL","MAT_GLASS_BLOCK","MAT_WATER"}) do
	_G[n] = i
end
game = stubtable()
sound = stubtable()
weapons = stubtable()
team = stubtable()
player_manager = stubtable()
scripted_ents = stubtable()

'''

import re

def local_order_check(paths):
    '''A local function defined BELOW its call site resolves to a global and blows up at runtime.
    That bug shipped in 2.14.2 (StartBodyAnim went nil), so it is checked explicitly here.'''
    problems = 0
    for path in paths:
        lines = open(path, encoding='utf-8', errors='replace').read().split('\n')
        defined = {}
        forward = set()
        for i, line in enumerate(lines, 1):
            m = re.match(r'\s*local function\s+(\w+)', line)
            if m:
                defined.setdefault(m.group(1), i)
                continue
            m = re.match(r'\s*local\s+(\w+)(\s*=|\s*$)', line)
            if m:
                forward.add(m.group(1))
                if m.group(2).startswith('='):
                    defined.setdefault(m.group(1), i)
        for i, line in enumerate(lines, 1):
            for name in defined:
                if name in forward and defined[name] > i:
                    continue
                if defined[name] > i and re.search(r'(?<![\w.:])' + re.escape(name) + r'\s*\(', line) \
                   and not line.strip().startswith('--') and 'local function' not in line \
                   and not re.match(r'\s*function\s+' + re.escape(name), line):
                    print('ORDER', path, 'line', i, 'calls', name, 'defined at', defined[name])
                    problems += 1
    return problems

SERVER_EXTRAS = r'''
SERVER = true
hg = {Fake = function() end, LightStunPlayer = function() end}
hg.organism = {}
util.AddNetworkString = function() end
game.SinglePlayer = function() return false end
hooktable = {OnPlayerHitGround = {fallStun = function() end}}
hook.GetTable = function() return hooktable end
net = setmetatable({}, {__index = function() return function() end end})
resource = setmetatable({}, {__index = function() return function() end end})
team = setmetatable({}, {__index = function() return function() end end})
'''

def load_paths(server):
    paths = sorted(glob.glob('lua/beatrun_zcity/sh/*.lua'))
    if server:
        paths += sorted(glob.glob('lua/beatrun_zcity/sv/*.lua'))
    paths += sorted(glob.glob('lua/beatrun_zcity/cl/*.lua'))
    paths += sorted(glob.glob('lua/autorun/*.lua'))
    return paths


def check_realm(server):
    lua = lupa.LuaRuntime()
    lua.execute(LUA)
    if server:
        lua.execute(SERVER_EXTRAS)
    runner = lua.eval(
        'function(src, name) local f, err = load(src, "@" .. name); '
        'if not f then return "SYNTAX: " .. tostring(err) end '
        'local ok, err2 = pcall(f); if not ok then return "RUNTIME: " .. tostring(err2) end return nil end'
    )
    label = 'SERVER' if server else 'CLIENT'
    paths = load_paths(server)
    failures = 0
    for path in paths:
        src = open(path, encoding='utf-8', errors='replace').read()
        err = runner(src, path)
        if err:
            failures += 1
            print('%s FAIL %s -> %s' % (label, path, err))
    print('%s files: %d, failures: %d' % (label, len(paths), failures))
    order = local_order_check(paths)
    print('%s order problems: %d' % (label, order))
    if not server:
        print('StartBodyAnim:', lua.eval('function() return type(StartBodyAnim) end')())
        print('BeatrunRollAnimStart:', lua.eval('function() return type(BeatrunRollAnimStart) end')())
    return failures + order


def main():
    return check_realm(False) + check_realm(True)


sys.exit(1 if main() else 0)
