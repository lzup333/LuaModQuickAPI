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
    mod.info("Terraria.Item.SetDefaults 已被调用！")
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
- [内容开发指南（推荐学习顺序）](#内容开发指南推荐学习顺序)
- [指定方法重载](#指定方法重载)
- [缓存、句柄与兼容性](#缓存句柄与兼容性)
- [联机与方块辅助](#联机与方块辅助)
- [常见问题](#常见问题)
- [更新日志](#更新日志)
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

## 内容开发指南（推荐学习顺序）

内容型 Mod 建议按下面的顺序阅读，每章都有**说明 + 完整示例 + 注意事项**：

| 顺序 | 章节 | 内容 |
|---|---|---|
| 1 | [合成](docs/01-recipes.md) | 物品配方、独立配方、材料 / 合成站、生效时机 |
| 2 | [物品](docs/02-items.md) | 注册、字段、语言、使用回调、发射弹幕、动画 |
| 3 | [弹幕](docs/03-projectiles.md) | 弹幕 AI 与位移、追踪、命中 / 撞墙 / 销毁回调 |
| 4 | [Buff](docs/04-buffs.md) | 增益 / 减益、每帧效果、挂上 / 移除、存档规则 |
| 5 | [NPC](docs/05-npcs.md) | 注册 / 生成、属性、AI 位移、掉落、Boss（实验性） |

索引页见 [docs/README.md](docs/README.md)。

最小组合示例：

```lua
require("quickapi")

function mod.init()
    -- 合成
    mod.quickapi.register_item{
        name    = "my_dust",
        texture = "dust.png",
        maxStack = 999,
        language = { zh = { name = "魔法尘" } },
        recipe = {
            result    = 2,
            materials = { { id = 23, count = 1 } },   -- 凝胶
            station   = 18,                           -- 工作台
        },
    }

    -- 物品
    mod.quickapi.register_item{
        name    = "my_sword",
        texture = "sword.png",
        damage  = 25, useTime = 20, useStyle = 1,
        melee   = true, width = 40, height = 40, maxStack = 1,
    }

    -- 弹幕
    mod.quickapi.register_projectile{
        name = "my_beam", texture = "beam.png",
        friendly = true, width = 16, height = 16,
        damage = 18, timeLeft = 180,
        ai = function(p) mod.quickapi.projectile_move(p) end,
    }

    -- Buff
    mod.quickapi.register_buff{
        name = "my_buff", texture = "buff.png",
        update = function(player) end,
        language = { zh = { name = "我的 Buff", description = "..." } },
    }

    -- NPC（实验性）
    mod.quickapi.register_npc{
        name = "my_slime", texture = "slime.png",
        width = 32, height = 32, lifeMax = 100, life = 100,
        ai = function(npc) end,
        loot = { { id = 23, count = 1 } },
    }
end
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

## 联机与方块辅助

```lua
mod.quickapi.net_mode()            -- 0 = 单机，1 = 客户端，2 = 服务端

mod.quickapi.send_to_server("my_channel", "payload")   -- 客户端 → 服务端

mod.quickapi.on_server_receive(function(channel, payload, player)
    -- 服务端收到后广播/执行
end)

mod.quickapi.tile_kill(x, y[, no_item])   -- 客户端请求服务端挖掉一格
mod.quickapi.tile_square(x, y, w, h)      -- 请求服务端同步一块区域
```

单机/服务端调用 `tile_kill` 没有副作用（本地挖掘本身就会同步），可以无脑调用。

## 常见问题

**Q：`require("quickapi")` 报 module not found？**
确认 `quickapi.lua` 与入口脚本在**同一目录**（部署后即 `<private_dir>/lib/`）。LuaLoader 会把该目录
加入 `package.path`，但不会自动扫描子目录。

**Q：报「找不到类型 / 字段 / 方法」怎么办？**
`get_field_value` / `set_field_value` / `invoke` / `install_hook*` 找不到目标会直接报错。
常见原因：类名或命名空间拼错、字段名是属性（应改用 `property` 取访问器）、方法在你使用的游戏版本里
不存在。拿不准时先用 `mod.patch.get_fields(type)` / `get_methods(type, true)` 内省确认。

**Q：会不会拖慢每帧的钩子？**
不会。解析结果被缓存，钩子回调里通常只是一次带缓存的名字查找 + `mod.patch` 调用。

## 更新日志

| 版本 | 内容 |
|---|---|
| **1.4.1** | 自定义物品配方改在 `Main.Update` 提前登记，避免 `SetupRecipes` 钩子顺序导致第一次进世界漏配方；解析完自动摘钩，不会每帧常驻 |
| **1.4.0** | 配方支持用**物品名**写结果/材料（自动等 runtime_id 分配后在 `Recipe.SetupRecipes` 解析），`register_item` 的 `recipe` 同样可用自定义物品名 |
| **1.3.6** | `use_sound` 延迟到 defaults 回调读取 SoundID，修复 Android 上静态类未初始化导致 null |
| **1.3.5** | `use_sound` 改由 QuickAPI 自己写 `Item.UseSound`，旧版 LuaLoader 也可用 |
| **1.3.4** | 物品 `use_sound`（SoundID 字段名 → `Item.UseSound`）；同步内核最新头文件 |
| **1.3.3** | 新增 `add_recipe`；NPC 支持 `loot` / `on_death`；补齐五章内容开发文档 |
| **1.3.2** | 自定义 NPC：`register_npc` / `npc_id` / `npc_spawn` |
| **1.3.1** | 弹幕 `on_hit_npc` / `on_hit_player` / `on_tile_collide` 回调 |
| **1.3.0** | 物品 `use` / `on_use`、弹幕 `on_kill` / `kill` 回调；修正 `q.proj` / `buff_apply` 在源码中的位置（行为不变，纯结构调整） |
| **1.2.0** | 弹幕上下文 `q.proj`；Buff 便捷层（`register_buff` / `buff_apply` / `buff_id` / `player_add_buff` / `player_buff_time`）；`projectile_animate`；联机与方块辅助 |
| **1.1.0** | 注册物品 / 弹幕与弹幕 AI 辅助（`projectile_move` / `projectile_homing` / `find_nearest_npc`），`rotation` 改为「贴图朝右」约定 |
| 1.0.0 | 初版：字段 / 方法 / 钩子的命名空间速查层 |

## 许可证

[MIT](LICENSE) © 2026 lzup333。

LuaModQuickAPI 作为独立库保持 MIT（模块名 `quickapi`）：它只在运行期调用 LuaLoader 的公开 API，
不含 LuaLoader 的任何代码，因此可以自由地复制进各 Mod 包而不会给 Mod 带来额外的许可负担。
