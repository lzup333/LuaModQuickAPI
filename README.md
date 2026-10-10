# LuaModQuickAPI

> 给 [LuaLoader](https://github.com/lzup333/LuaLoader) 的 Mod 编写便捷层：用 **命名空间 + 类名 + 成员名**
> 直接读写字段、调用方法、安装钩子，把成套的 `get_type → get_field → 判空 → 调用` 样板压成一行。

项目名 **LuaModQuickAPI**；在 Mod 里对外的模块名 / 命名空间保持为 **`quickapi`**
（文件 `quickapi.lua`，`require("quickapi")` 后即 `mod.quickapi.*`）。

- **纯 Lua**：不改 LuaLoader，不用重新编译，一份脚本全平台通用（Android / Windows / Linux）。
- **零依赖、零侵入**：只调用 LuaLoader 已有的 `mod.patch`，不改变任何既有语义。
- **可直接内嵌**：一个文件 `quickapi.lua`，放进 Mod 包即可，MIT 许可。

```lua
require("quickapi")

mod.meta = { pkg_id = "lzup.lua.example", version = "1.0.0" }

function InvokedLog()
    mod.info("Terraria.Item.SetDefaults已被调用！")
end

function setup()
    mod.quickapi.install_hook_postfix("Terraria", "Item", "SetDefaults", InvokedLog)
end

todo_list = { "setup" }
```

## 目录

- [为什么不用改 LuaLoader](#为什么不用改-lualoader)
- [安装](#安装)
- [快速开始](#快速开始)
- [API 速查](#api-速查)
  - [解析](#解析)
  - [字段读写](#字段读写)
  - [方法调用](#方法调用)
  - [钩子](#钩子)
- [指定方法重载](#指定方法重载)
- [缓存、句柄与兼容性](#缓存句柄与兼容性)
- [对比：用 quickapi 重写一段 Mod](#对比用-quickapi-重写一段-mod)
- [常见问题](#常见问题)
- [许可证](#许可证)

## 为什么不用改 LuaLoader

LuaLoader 已经通过 `mod.patch` 暴露了内核 patchlib 的全部能力，只是用它写 Mod 时样板偏多：
取类型、取字段/方法、查父类、判空、选重载，几乎每个 Mod 都要重抄一遍。

quickapi 把这些步骤收进一个**纯 Lua 库**：它只在运行期调用 `mod.patch`，因此

- **不需要动 LuaLoader 的 C++ 源码**，也就不需要重编译六个平台；
- 老版本 LuaLoader（只要带 `mod.patch`）同样可用；
- 不引入任何不兼容更新：不用 quickapi 的 Mod 行为完全不变。

## 安装

把 [quickapi.lua](quickapi.lua) 复制到你的 Mod 目录，与入口脚本同级：

```
my_mod/
├── Info.json
├── Manifest.json
├── luamod.json
└── Resources/
    └── lib/
        ├── main.lua        # 入口
        └── quickapi.lua    # 复制进来的 quickapi
```

LuaLoader 会把 `Resources/lib/` 部署到 Mod 私有目录，并把该目录加入 `package.path`，
所以入口脚本首行 `require("quickapi")` 即可加载。`require` 之后 `mod.quickapi` 自动可用，
也可以 `local q = require("quickapi")` 用返回值。

> 完整可运行示例见 [`examples/quickapi_demo`](examples/quickapi_demo)。

## 快速开始

```lua
require("quickapi")   -- 之后用 mod.quickapi.*

mod.meta = { pkg_id = "lzup.lua.example", version = "1.0.0" }

-- 一个每帧把玩家生命锁满的小 Mod
local function lock_life(instance)
    if not instance then return end
    local max = mod.quickapi.get_field_value("Terraria", "Player", "statLifeMax2", instance, "int32")
    if max == nil then return end
    mod.quickapi.set_field_value("Terraria", "Player", "statLife", instance, max, "int32")
end

function setup()
    mod.quickapi.install_hook_postfix("Terraria", "Player", "ResetEffects", lock_life)
end

todo_list = { "setup" }
```

## API 速查

下表里 `ns` = 命名空间，`class` = 类名，`name` = 成员名；`instance` 为对象实例（省略即静态）。

### 解析

| 函数 | 返回值 | 说明 |
|---|---|---|
| `type(ns, class)` | 类型句柄 / `nil` | 等价 `mod.patch.get_type`，结果缓存 |
| `field(ns, class, name)` | 字段句柄 / `nil` | **自动沿父类链查找** |
| `property(ns, class, name)` | 属性句柄 / `nil` | 同样自动找父类 |
| `method(ns, class, name[, spec])` | 方法句柄 / `nil` | `spec` 见 [指定方法重载](#指定方法重载) |

解析类函数找不到就返回 `nil`，交给你判断；下面这些「动手」的函数找不到则**直接报错**，
消息里带清楚的名字，避免静默失效。

### 字段读写

| 函数 | 说明 |
|---|---|
| `get_field_value(ns, class, name[, instance[, type]])` | 读字段；`instance` 省略即静态字段，`type` 省略由内核推断 |
| `set_field_value(ns, class, name, instance, value[, type])` | 写字段，成功返回 `true` |
| `get_object(ns, class, name, instance)` / `set_object(ns, class, name, instance, value)` | 引用类型字段的便捷读写（等价于 `type = "object"`） |

`name` 也可以直接传**字段句柄**（例如来自 `mod.quickapi.field` 或 `mod.patch.get_field`），此时会跳过解析。

```lua
-- 静态字段：不传 instance
local my_player = mod.quickapi.get_field_value("Terraria", "Main", "myPlayer", nil, "int32")

-- 实例字段：Android 上请显式写类型（走真实指针，类型不明确会读错）
local mana = mod.quickapi.get_field_value("Terraria", "Player", "statMana", player, "int32")
mod.quickapi.set_field_value("Terraria", "Player", "statMana", player, mana + 100, "int32")
```

### 方法调用

| 函数 | 说明 |
|---|---|
| `invoke(ns, class, name, ...)` | 按名字调用：**自动按实参个数选重载**，并自动区分实例 / 静态方法 |
| `call(method, ...)` | 已持有方法句柄时调用，同样自动区分实例 / 静态 |

```lua
-- 实例方法：首参传 instance
mod.quickapi.invoke("Terraria", "Player", "Heal", player, 20)

-- 静态方法：不传 instance
mod.quickapi.invoke("Terraria", "Main", "NewText", "hello", 255, 255, 255)

-- 已持有句柄
local m = mod.quickapi.method("Terraria", "Player", "Heal", 1)
mod.quickapi.call(m, player, 20)
```

返回值与裸 `mod.patch.invoke` 一致：引用类型是**借用句柄**，`void` 为 `nil`，失败为 `false`。

### 钩子

| 函数 | 说明 |
|---|---|
| `install_hook(ns, class, name[, opts])` | 解析方法并装钩子，返回 hook 句柄（可 `:remove()`） |
| `install_hook_prefix(ns, class, name, fn[, opts])` | 只装 `prefix` |
| `install_hook_postfix(ns, class, name, fn[, opts])` | 只装 `postfix` |

回调签名与 LuaLoader 原生钩子一致：`function(instance, args, result)`（不需要的参数可不写）。
`opts` 直接透传给 `mod.patch.install_hook`，因此支持 `copy`、`override_result` 等选项；
把 `opts` 写成函数则等价于 `{ postfix = fn }`。

```lua
-- 只装 postfix
mod.quickapi.install_hook_postfix("Terraria", "Player", "ResetEffects", on_reset)

-- prefix 返回 true 跳过原方法，可再给一个返回值
mod.quickapi.install_hook_prefix("Terraria", "Recipe", "CollectedEnoughItemsToCraft",
        function() return true, true end)

-- 通用写法：prefix + postfix，允许 postfix 覆盖返回值
mod.quickapi.install_hook("Terraria", "Item", "SetDefaults", {
    prefix = function() end,
    postfix = function(instance, args, result) return 0 end,
    override_result = true,
})

-- 返回值就是 hook 句柄
local hook = mod.quickapi.install_hook_postfix("Terraria", "Item", "SetDefaults", cb)
hook:remove()
```

## 指定方法重载

同名方法有多个重载时，用 `spec`（或 `opts` 里的同名字段）消除歧义：

```lua
mod.quickapi.method(ns, class, name, 2)                              -- 按参数个数
mod.quickapi.method(ns, class, name, { argc = 2 })                   -- 同上，命名写法
mod.quickapi.method(ns, class, name, { params = {"Type", "noMatCheck"} })  -- 按参数名
mod.quickapi.method(ns, class, name, { types = {t_int, t_bool} })    -- 按参数类型句柄

mod.quickapi.install_hook_postfix(ns, class, name, cb, { params = {"Type", "variant"} })
```

`invoke` 不用 `spec`：它按你传入的**实参个数**在（含父类的）同名重载里匹配，并据此判断
首个实参是不是 `instance`。若匹配到多个（同参个数重载），会报错并提示改用
`mod.quickapi.method` + `mod.patch.invoke`。

## 缓存、句柄与兼容性

- **解析结果会缓存**（类型 / 字段 / 属性 / 方法），所以每帧在钩子里调用 `get_field_value` 之类
  的开销很小；找不到时不写缓存，等类型加载好再试即可。
- 句柄生命周期与原生 API 完全一致：类型 / 字段 / 方法句柄在同一个 Lua 状态机内可跨帧持有；
  而 **对象实例句柄是借用的**，钩子里的 `instance` / 对象参数**不要跨帧缓存**，要缓存请用
  `mod.patch.retain` 或给钩子加 `{ copy = true }`。
- quickapi 只是 `mod.patch` 的语法糖，两者可任意混用；不使用 quickapi 的 Mod 行为完全不变。
- `/reload` 热重载会重建 Lua 状态机，quickapi 的缓存随之一并重建，无需手动清理。

## 对比：用 quickapi 重写一段 Mod

裸 `mod.patch` 版（节选自 LuaMods 的 `LuaHealthLock`）：

```lua
mod.meta = { pkg_id = "lzup.lua.healthlock", version = "1.0.0" }

local stat_life
local stat_life_max

function lock_life(instance)
    local max = mod.patch.get_field_value(stat_life_max, instance, "int32")
    mod.patch.set_field_value(stat_life, instance, max, "int32")
end

function setup()
    local player = mod.patch.get_type("Terraria", "Player")
    if not player then return end
    stat_life = mod.patch.get_field(player, "statLife")
    stat_life_max = mod.patch.get_field(player, "statLifeMax2")
    mod.patch.install_hook(mod.patch.get_method(player, "ResetEffects", 0), { postfix = lock_life })
end

todo_list = { "setup" }
```

quickapi 版：

```lua
require("quickapi")
mod.meta = { pkg_id = "lzup.lua.healthlock", version = "1.0.0" }

local function lock_life(instance)
    local max = mod.quickapi.get_field_value("Terraria", "Player", "statLifeMax2", instance, "int32")
    mod.quickapi.set_field_value("Terraria", "Player", "statLife", instance, max, "int32")
end

function setup()
    mod.quickapi.install_hook_postfix("Terraria", "Player", "ResetEffects", lock_life)
end

todo_list = { "setup" }
```

## 常见问题

**Q：能只改一个字段、不改 Mod 其他部分吗？**
可以。quickapi 与 `mod.patch` 混用，逐段替换即可。

**Q：`require("quickapi")` 报 module not found？**
确认 `quickapi.lua` 与入口脚本在**同一目录**（部署后即 `<private_dir>/lib/`）。LuaLoader 会把该目录
加入 `package.path`，但不会自动扫描子目录。

**Q：报「找不到类型 / 字段 / 方法」怎么办？**
`get_field_value` / `set_field_value` / `invoke` / `install_hook*` 找不到目标会直接报错。
常见原因：类名或命名空间拼错、字段名是属性（应改用 `property` 取访问器）、方法在你使用的游戏版本里
不存在。拿不准时先用 `mod.patch.get_fields(type)` / `get_methods(type, true)` 内省确认。

**Q：会不会拖慢每帧的钩子？**
不会。解析结果被缓存，钩子回调里通常只是一次带缓存的名字查找 + `mod.patch` 调用。

## 许可证

[MIT](LICENSE) © 2026 lzup333。

LuaModQuickAPI 作为独立库保持 MIT（模块名 `quickapi`）：它只在运行期调用 LuaLoader 的公开 API，
不含 LuaLoader 的任何代码，因此可以自由地复制进各 Mod 包而不会给 Mod 带来额外的许可负担。
