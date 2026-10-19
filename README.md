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
  - [注册物品与弹幕](#注册物品与弹幕)
  - [弹幕 AI 辅助](#弹幕-ai-辅助)
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

## 注册物品与弹幕

写法刻意贴近泰拉瑞亚源码 `Item.SetDefaults` / `Projectile.SetDefaults`：**属性直接平铺在表里**，
和源码里一行一个 `damage = 25;` 一样，不用再包一层 `defaults`。

```lua
require("quickapi")

-- 新物品：等价于源码里的 case 分支
local sword_id = mod.quickapi.register_item{
    name      = "my_sword",
    texture   = "sword.png",
    tooltip   = true,
    sacrifice = 1,
    prefixes  = "sword",          -- 声明可重铸类别（不写 = 不可重铸）

    -- ↓↓↓ 这部分就是 Item.SetDefaults 的内容 ↓↓↓
    damage       = 25,
    knockBack    = 5.0,
    width        = 40,
    height       = 40,
    useStyle     = 1,
    useTime      = 20,
    useAnimation = 20,
    autoReuse    = true,
    useTurn      = true,
    melee        = true,
    noMelee      = false,
    rare         = 2,
    scale        = 1.0,
    maxStack     = 1,
    crit         = 4,
    value        = 50000,

    language  = {
        en = { name = "My Sword", tooltip = "A test sword." },
        zh = { name = "我的剑",   tooltip = "一把测试用剑。" },
    },
    recipe    = { result = 1, materials = { { id = 9, count = 10 } }, station = 18 },
}

-- 新弹幕：同样平铺
local orb_id = mod.quickapi.register_projectile{
    name    = "my_orb",
    texture = "orb.png",

    -- ↓↓↓ 这部分就是 Projectile.SetDefaults 的内容 ↓↓↓
    width        = 16,
    height       = 16,
    damage       = 18,
    knockBack    = 2.0,
    timeLeft     = 300,
    penetrate    = 1,
    maxPenetrate = 1,
    tileCollide  = false,
    ignoreWater  = true,
    friendly     = true,
    hostile      = false,
    light        = 0.7,
    scale        = 1.0,

    ai = function(p)
        -- 见下一节
    end,
}
```

取运行时 ID（内核分配后才有效）：

```lua
mod.quickapi.item_id("my_sword")        -- 等价 mod.item.runtime_id
mod.quickapi.projectile_id("my_orb")    -- 等价 mod.projectile.runtime_id
```

### 平铺写法 vs defaults 表

两种都可以，平铺优先：

```lua
-- 推荐：贴源码风格
mod.quickapi.register_item{ name = "a", damage = 25, useStyle = 1 }

-- 也支持（与 mod.item.register 原生写法一致）
mod.quickapi.register_item{ name = "b", defaults = { damage = 25, useStyle = 1 } }

-- defaults 写成函数时原样透传（适合运行时算值）
mod.quickapi.register_item{ name = "c", defaults = function(item) ... end }
```

**字段名会被校验**：拼错（例如 `useTimee`）会在注册阶段直接报错，不会像原生 API 那样
只打一条警告然后静默忽略。

### 元字段

以下键不是 Item / Projectile 的字段，quickapi 会把它们原样交给 LuaLoader：

| 类型 | 元字段 |
|---|---|
| 物品 | `name` `texture` `tooltip` `sacrifice` `prefixes` `can_use` `language` `recipe` `defaults` |
| 弹幕 | `name` `texture` `ai` `no_ai` `defaults` |

### 让武器发射自定义弹幕

物品的 `shoot` 支持**直接写弹幕名**，quickapi 会在运行时解析成内核分配的 ID
（不用自己写 `defaults = function(item)`）：

```lua
local beam = mod.quickapi.register_projectile{ name = "SwordBeam", texture = "beam.png", ... }

mod.quickapi.register_item{
    name  = "DiamondSword",
    melee = true, useStyle = 1,

    shoot      = "SwordBeam",   -- ← 弹幕名，自动解析成 ID
    shootSpeed = 12.0,
}
```

### defaults 函数里用字段代理

`defaults` 写成函数时，回调收到的是**字段代理**，可以按 `Item.SetDefaults` 的写法直接赋值，
不用记 `mod.patch.set_field_value`：

```lua
mod.quickapi.register_item{
    name     = "MySword",
    damage   = 25,                       -- 平铺属性：注册时定好
    defaults = function(item)            -- 函数：运行期才能算的再放这里
        item.shoot      = mod.quickapi.projectile_id("SomeBeam") or 0
        item.shootSpeed = 12.0
        item.crit       = item.crit + 6  -- 读也可以
    end,
}
```

也可以手动 `local item = mod.quickapi.proxy("Terraria", "Item", instance)`。

## 弹幕 AI 辅助

写了 `ai` 就由 Lua 接管，内核会**跳过原版 `Projectile.AI()`**。而原版是在 `AI()` 里做
`position += velocity` 的，所以**位移必须自己算**，否则弹幕会停在原地（看起来像没射出去）。

quickapi 提供了三个小工具：

| 函数 | 说明 |
|---|---|
| `projectile_move(p[, opts])` | `position += velocity`，并按速度设置 `rotation`（`opts.face_velocity = false` 可关） |
| `projectile_homing(p, tx, ty[, rate[, max_turn]])` | 保持速率不变，朝目标转向；`rate` 默认 `0.2` |
| `find_nearest_npc(p[, range])` | 找最近的敌对 NPC，`range` 默认 900 像素；返回 `npc, 距离` |
| `vec.get(ns, class, field, instance)` / `vec.set(...)` | 读写 `Vector2` 字段 |

追踪型弹幕：

```lua
ai = function(p)
    local npc = mod.quickapi.find_nearest_npc(p, 900)
    if npc then
        local nx, ny = mod.quickapi.vec.get("Terraria", "NPC", "position", npc)
        mod.quickapi.projectile_homing(p, nx, ny, 0.18)
    end
    mod.quickapi.projectile_move(p)
end
```

> 用 `find_nearest_npc` 而不是鼠标：手机端没有光标，`Main.mouseX/mouseY` 不是
> "准星位置"，按鼠标追踪在手机上会退化成直线。

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
