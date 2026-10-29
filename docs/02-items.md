# 物品

> 第 2 章。建议从最小物品开始，再按需要加语言、使用回调、动画和配方。

`mod.quickapi.register_item` 是 `mod.item.register` 的便捷写法：**Item 的字段直接平铺在表里**，
不需要再包一层 `defaults`。字段名会在注册阶段校验，拼错会直接报错，而不是静默忽略。

## 最小物品

```lua
require("quickapi")

local id = mod.quickapi.register_item{
    name    = "my_sword",
    texture = "sword.png",
    width   = 40,
    height  = 40,
    damage  = 25,
    useTime = 20,
    useStyle = 1,       -- 1 = 挥砍
    melee    = true,
    maxStack = 1,
}
```

- `name` 必填，同一个 Mod 内唯一；
- `texture` 是 PNG 文件名，放在 `Resources/Image/` 或 `Resources/lib/Image/`；
- 其余键就是 `Terraria.Item` 的字段（见 `Item.SetDefaults`）。

## 平铺写法 vs defaults 表

```lua
-- 推荐：贴近源码
mod.quickapi.register_item{ name = "a", damage = 25, useStyle = 1 }

-- 也支持原生写法
mod.quickapi.register_item{ name = "b", defaults = { damage = 25, useStyle = 1 } }

-- defaults 写成函数：适合运行期才能算的值
mod.quickapi.register_item{
    name = "c",
    defaults = function(item)
        item.damage = item.damage + 5
    end,
}
```

平铺和 `defaults` 同时写时，两者都会生效；`defaults` 函数在最后执行。

## 元字段

以下键不是 Item 字段，QuickAPI 会原样交给 LuaLoader：

| 键 | 说明 |
|---|---|
| `name` | 注册名（必填，同 Mod 内唯一） |
| `texture` | PNG 文件名；不填使用内核占位贴图 |
| `tooltip` | `true` 时显示简介 |
| `sacrifice` | 研究所需数量；`0` = 不可研究 |
| `prefixes` | 可重铸类别（例如 `"sword"`）；不写 = 不可重铸 |
| `can_use` | `function(player, item, ignore_cursed) return true end` |
| `use` / `on_use` | 每次真正使用触发一次：`function(player, item) end` |
| `use_sound` | `SoundID` 字段名（如 `"Item1"`），写入 `Item.UseSound` |
| `language` | 多语言名称/简介，见下 |
| `animation` | 竖向帧图：`{ ticks = 8, frames = 9 }` |
| `recipe` | 配方，见 [合成](01-recipes.md) |
| `defaults` | 表或函数，见上 |

## 名称与简介

```lua
language = {
    en = { name = "My Sword", tooltip = "A test sword." },
    zh = { name = "我的剑",   tooltip = "一把测试用剑。" },
}
```

- 不写 `language` 时显示内部注册名；
- 支持的语言键：`en / de / it / fr / es / ru / zh / pt / pl / ja / ko / zh-tw`；
- `tooltip = true` 时才会显示 tooltip 文本。

## 使用回调

```lua
mod.quickapi.register_item{
    name = "healing_charm",
    texture = "charm.png",
    useStyle = 2,
    useTime = 30,

    can_use = function(player, item, ignore_cursed)
        -- 返回 false 时这一下不会开始使用（不消耗、不播动画）
        return true
    end,

    use = function(player, item)
        -- 一次挥动/使用只回调一次
        mod.quickapi.invoke("Terraria", "Player", "Heal", player, 20)
    end,
}
```

- `use` 由内核在 `Player.ItemCheck_StartActualUse` 之后触发，**每次使用一次**；
- 不要在这里再判断动画帧，内核已经处理；
- `on_use` 是 `use` 的别名。

## 让武器发射自定义弹幕

`shoot` 可以直接写**弹幕名**，QuickAPI 会在运行时解析成内核分配的 ID：

```lua
mod.quickapi.register_projectile{
    name = "SwordBeam",
    texture = "beam.png",
    friendly = true,
    width = 16, height = 16,
    damage = 18,
    timeLeft = 180,
}

mod.quickapi.register_item{
    name = "DiamondSword",
    melee = true, useStyle = 1,
    shoot = "SwordBeam",     -- ← 弹幕名，不用写 item_id
    shootSpeed = 12.0,
}
```

> 弹幕名必须在物品注册之前已经注册，或者至少在第一次使用前完成注册。

## 物品音效

使用 `use_sound` 指定 `Terraria.ID.SoundID` 里的字段名：

```lua
mod.quickapi.register_item{
    name = "my_sword",
    texture = "sword.png",
    useStyle = 1, useTime = 20,
    use_sound = "Item1",        -- SoundID 里的字段名
}
```

- `use_sound` 只是 `Terraria.ID.SoundID` 的字段名，具体音色以游戏内实际试听为准；
- QuickAPI 会自己把它写进 `Item.UseSound`，所以**旧版 LuaLoader 也能用**（不依赖新版原生的 `use_sound`）；
- 不写就沿用原版默认（原版 `SetDefaults` 设置的值）；
- 需要微调音高时再平铺 `useSoundPitch = 0.5` 之类的 `Item` 字段。

## 动画物品
```lua
mod.quickapi.register_item{
    name = "spinning_coin",
    texture = "coin.png",             -- 竖向帧图
    animation = { ticks = 8, frames = 9 },
}
```

`texture` 的高度必须能被 `frames` 整除，否则帧会错位。

## 注意事项

- **注册阶段返回的 ID 是 `-1`**：内核要等所有 Mod 注册完才分配。需要 ID 时用
  `mod.quickapi.item_id("my_sword")` 在游戏内实时取。
- **不要缓存对象句柄**：`player` / `item` 是借用句柄，只在当前回调有效。
- **字段名区分大小写**：`useTime` 不是 `usetime`；QuickAPI 会直接报错。
- **数值类型**：QuickAPI 会按字段真实类型写入；Android 上不要手动传错误的类型。
- **纹理**：PNG 必须是 RGBA；手机端会自动做 Y 翻转。
- **存档**：自定义物品按「加载器 / Mod / 物品名」写进 `.plr.tef` / `.wld.tef` 伴生文件；
  卸载 Mod 后物品会变成 UNKNOWN 占位物，重新装回可恢复（前提是伴生文件还在）。
- **多人游戏**：自定义物品目前没有完整的联机同步，单机/本地测试优先。

## 常见问题

**Q：物品图标是紫色占位图？**
检查 `texture` 文件名和路径（`Resources/Image/` 或 `Resources/lib/Image/`），以及 PNG 是否能正常解码。

**Q：注册成功但物品不在合成表？**
配方需要重新进世界才会重建；见 [合成](01-recipes.md) 的“生效时机”。

**Q：`use` 不触发？**
确认物品的 `useStyle` / `useTime` / `useAnimation` 是合法组合，并且 `can_use` 返回了 `true`。
