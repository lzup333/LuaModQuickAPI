-- LuaModQuickAPI / quickapi —— LuaLoader Mod 编写便捷层
-- Copyright (c) 2026 lzup333
--
-- MIT License
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--
-- 本文件是库本体：复制到你的 Mod 的 Resources/lib/quickapi.lua，入口脚本首行
-- require("quickapi")，之后即可使用 mod.quickapi.*。
-- 纯 Lua，无需修改 / 重新编译 LuaLoader，一份脚本全平台通用。

local mod_env = mod
if type(mod_env) ~= "table" then
    error("quickapi: 未找到全局 mod 表，请在 LuaLoader Mod 的入口脚本中使用")
end

local patch = mod_env.patch
if type(patch) ~= "table" then
    error("quickapi: mod.patch 不可用，当前 LuaLoader 版本过旧")
end

local q = {}
q.version = "1.0.0"

-- 句柄缓存：类型 / 字段 / 属性 / 方法。句柄在同一个 Lua 状态机内稳定，
-- /reload 会重建状态机，缓存随之一并重建，无需手动清理。
local type_cache = {}
local member_cache = {}
local method_cache = {}

local function key_of(...)
    return table.concat({...}, "\1")
end

local function is_handle(v)
    local t = type(v)
    return t == "userdata" or t == "lightuserdata"
end

local function fail(level, fmt, ...)
    error("quickapi: " .. string.format(fmt, ...), level)
end

-- 沿父类链查找成员：命中返回句柄，找不到返回 nil
local function walk_members(t, getter, name)
    local cur, guard = t, 0
    while cur and guard < 32 do
        local h = getter(cur, name)
        if h then return h end
        cur = patch.get_parent(cur)
        guard = guard + 1
    end
    return nil
end

-- spec 为空 / 数字 / 含 params|types|argc 的表，对应 patch 的几种选重载方式
local function resolve_spec(t, name, spec)
    if spec == nil then
        return patch.get_method(t, name)
    end
    local st = type(spec)
    if st == "number" then
        return patch.get_method(t, name, spec)
    end
    if st == "table" then
        if spec.params then return patch.get_method_by_names(t, name, spec.params) end
        if spec.types then return patch.get_method_by_param_types(t, name, spec.types) end
        if spec.argc then return patch.get_method(t, name, spec.argc) end
    end
    return patch.get_method(t, name)
end

-- ============================ 解析 ============================

-- mod.quickapi.type(ns, class) -> 类型句柄 | nil
function q.type(ns, class)
    local k = key_of("t", ns, class)
    local t = type_cache[k]
    if t ~= nil then return t end
    t = patch.get_type(ns, class)
    if t ~= nil then type_cache[k] = t end
    return t
end

-- mod.quickapi.field(ns, class, name) -> 字段句柄 | nil（自动向上找父类）
function q.field(ns, class, name)
    local k = key_of("f", ns, class, name)
    local f = member_cache[k]
    if f ~= nil then return f end
    local t = q.type(ns, class)
    if not t then return nil end
    f = walk_members(t, patch.get_field, name)
    if f then member_cache[k] = f end
    return f
end

-- mod.quickapi.property(ns, class, name) -> 属性句柄 | nil（自动向上找父类）
function q.property(ns, class, name)
    local k = key_of("p", ns, class, name)
    local p = member_cache[k]
    if p ~= nil then return p end
    local t = q.type(ns, class)
    if not t then return nil end
    p = walk_members(t, patch.get_property, name)
    if p then member_cache[k] = p end
    return p
end

-- mod.quickapi.method(ns, class, name[, spec]) -> 方法句柄 | nil
-- spec 可为：数字（参数个数）/ {argc=n} / {params={"a","b"}} / {types={类型句柄, ...}}
function q.method(ns, class, name, spec)
    local cache_key
    if spec == nil or type(spec) == "number" then
        cache_key = key_of("m", ns, class, name, tostring(spec))
        local cached = method_cache[cache_key]
        if cached ~= nil then return cached end
    end

    local t = q.type(ns, class)
    if not t then return nil end
    local m = resolve_spec(t, name, spec)
    if not m then
        local cur, guard = patch.get_parent(t), 0
        while cur and guard < 32 do
            m = resolve_spec(cur, name, spec)
            if m then break end
            cur = patch.get_parent(cur)
            guard = guard + 1
        end
    end
    if m and cache_key then method_cache[cache_key] = m end
    return m
end

-- ============================ 字段读写 ============================

local function as_field(ns, class, field)
    if is_handle(field) then return field end
    return q.field(ns, class, field)
end

-- mod.quickapi.get_field_value(ns, class, field[, instance[, type]])
-- instance 为 nil 表示静态字段；type 省略时由内核推断（Android 建议显式写）
function q.get_field_value(ns, class, field, instance, vtype)
    local f = as_field(ns, class, field)
    if not f then fail(2, "找不到字段 %s.%s.%s", ns, class, tostring(field)) end
    return patch.get_field_value(f, instance, vtype)
end

-- mod.quickapi.set_field_value(ns, class, field, instance, value[, type]) -> bool
function q.set_field_value(ns, class, field, instance, value, vtype)
    local f = as_field(ns, class, field)
    if not f then fail(2, "找不到字段 %s.%s.%s", ns, class, tostring(field)) end
    return patch.set_field_value(f, instance, value, vtype)
end

-- 引用类型字段的便捷读写（等价于 type 传 "object"）
function q.get_object(ns, class, field, instance)
    return q.get_field_value(ns, class, field, instance, "object")
end

function q.set_object(ns, class, field, instance, value)
    return q.set_field_value(ns, class, field, instance, value, "object")
end

-- ============================ 方法调用 ============================

-- 一个方法被调用时的 Lua 实参总数 = 形参个数 +（实例方法多出来的 instance）
local function total_args(m)
    local n = patch.method_param_count(m)
    if n == nil then return nil end
    if patch.method_is_instance(m) then return n + 1 end
    return n
end

-- 按实参个数在（含父类的）同名重载里挑一个：唯一匹配 -> 句柄；否则 nil, 匹配个数
local function pick_by_argcount(t, name, nargs)
    local list = patch.get_methods(t, true)
    if type(list) ~= "table" then return nil, 0 end
    local found, count = nil, 0
    for i = 1, #list do
        local m = list[i]
        if m and patch.method_name(m) == name and total_args(m) == nargs then
            found = m
            count = count + 1
        end
    end
    if count == 1 then return found end
    return nil, count
end

-- mod.quickapi.invoke(ns, class, name, ...) -> 返回值
-- 自动按实参个数选重载，并自动区分实例方法（首参为 instance）与静态方法。
function q.invoke(ns, class, name, ...)
    local nargs = select("#", ...)
    local t = q.type(ns, class)
    if not t then fail(2, "找不到类型 %s.%s", tostring(ns), tostring(class)) end

    local k = key_of("i", ns, class, name, nargs)
    local m = method_cache[k]
    if m == nil then
        local matches
        m, matches = pick_by_argcount(t, name, nargs)
        if m == nil and matches == 0 then
            -- 没有按个数精确匹配的重载时，退回内核按名字取（与裸 patch 行为一致）
            m = q.method(ns, class, name)
        end
        if m then method_cache[k] = m end
    end
    if not m then
        fail(2, "找不到能接受 %d 个实参的方法 %s.%s.%s（重载多义时请用 mod.quickapi.method + mod.patch.invoke 指定）",
                nargs, ns, class, name)
    end

    local args = table.pack(...)
    if patch.method_is_instance(m) then
        return patch.invoke(m, args[1], table.unpack(args, 2, args.n))
    end
    return patch.invoke(m, table.unpack(args, 1, args.n))
end

-- mod.quickapi.call(method, ...) -> 返回值：已持有方法句柄时，自动区分实例 / 静态
function q.call(method, ...)
    if not is_handle(method) then fail(2, "call 需要方法句柄") end
    local args = table.pack(...)
    if patch.method_is_instance(method) then
        return patch.invoke(method, args[1], table.unpack(args, 2, args.n))
    end
    return patch.invoke(method, table.unpack(args, 1, args.n))
end

-- ============================ 钩子 ============================

local function resolve_hook_method(ns, class, method, opts)
    if is_handle(method) then return method end
    local t = q.type(ns, class)
    if not t then fail(3, "找不到类型 %s.%s", tostring(ns), tostring(class)) end

    local spec
    if opts then
        if opts.params then spec = { params = opts.params }
        elseif opts.types then spec = { types = opts.types }
        elseif opts.argc ~= nil then spec = opts.argc end
    end

    local m = resolve_spec(t, method, spec)
    if not m then
        local cur, guard = patch.get_parent(t), 0
        while cur and guard < 32 do
            m = resolve_spec(cur, method, spec)
            if m then break end
            cur = patch.get_parent(cur)
            guard = guard + 1
        end
    end
    if not m then fail(3, "找不到方法 %s.%s.%s", ns, class, tostring(method)) end
    return m
end

-- mod.quickapi.install_hook(ns, class, method[, opts])
-- opts：{prefix=fn, postfix=fn, copy=bool, override_result=bool, argc/params/types 用于选重载}
-- 也可直接把 opts 写成函数（等价 postfix）。返回 hook 句柄，可 hook:remove()。
function q.install_hook(ns, class, method, opts)
    if type(opts) == "function" then opts = { postfix = opts } end
    opts = opts or {}
    local m = resolve_hook_method(ns, class, method, opts)
    return patch.install_hook(m, opts)
end

-- 复制 opts 并写入回调，避免改写调用方传入的表
local function with_callback(opts, key, fn)
    local o = {}
    if type(opts) == "table" then
        for k, v in pairs(opts) do o[k] = v end
    end
    o[key] = fn
    return o
end

-- mod.quickapi.install_hook_prefix(ns, class, method, fn[, opts])
function q.install_hook_prefix(ns, class, method, fn, opts)
    return q.install_hook(ns, class, method, with_callback(opts, "prefix", fn))
end

-- mod.quickapi.install_hook_postfix(ns, class, method, fn[, opts])
function q.install_hook_postfix(ns, class, method, fn, opts)
    return q.install_hook(ns, class, method, with_callback(opts, "postfix", fn))
end

-- 自动挂到 mod 表，require 之后 mod.quickapi.* 即可用（与直接使用 require 的返回值等价）
mod_env.quickapi = q

return q
