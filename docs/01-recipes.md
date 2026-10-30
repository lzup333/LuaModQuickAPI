# 合成（配方）

> 本章是 QuickAPI 内容开发指南的第 1 章。建议先看 [物品](02-items.md)，因为大多数配方都挂在物品上。

配方在泰拉瑞亚里就是一条「材料 + 合成站 → 产物」的记录。QuickAPI 提供两种写法：

1. **物品自带配方**：注册物品时顺手写 `recipe = {...}`，适合「新物品 + 它的配方」；
2. **独立配方**：`mod.quickapi.add_recipe{...}`，适合给原版物品加配方、给同一个物品加多条配方。

两种写法最终都会调用 LuaLoader 的 `mod.recipe.add`，行为完全一致。

> 从 **1.4.0** 起，`result` / `materials` 里的 `id` 可以直接写**物品名**（自定义物品的内部名）。
> QuickAPI 会自动等到内核分配 `runtime_id`，在 `Main.Update` 里提前登记（登记完立即摘钩），
> 不需要自己写等待钩子。数字 ID 写法和以前完全一样。

## 1. 物品自带配方

```lua
require("quickapi")

mod.quickapi.register_item{
    name    = "my_sword",
    texture = "sword.png",
    damage  = 25,
    useTime = 20,
    melee   = true,
    width   = 40, height = 40,
    maxStack = 1,

    -- 1 把 my_sword = 10 个木材，站在工作台旁合成
    recipe = {
        result    = 1,                        -- 产物数量（物品本身已经确定）
        materials = { { id = 9, count = 10 } },
        station   = 18,                       -- 18 = 工作台；省略 = 不需要合成站
    },
}
```

材料也可以直接写物品名（自定义物品也行）：

```lua
mod.quickapi.register_item{
    name    = "my_sword",
    texture = "sword.png",
    -- ...
    recipe = {
        result    = 1,
        materials = {
            { id = "magic_shard", count = 5 },  -- 本 Mod 自定义物品名，自动等 ID 分配
            { id = 9, count = 10 },             -- 原版物品用数字 ID（9 = Wood）
        },
        station = 18,
    },
}
```

`register_item` 里的 `result` 是**产物数量**，不是物品 ID：物品 ID 由 `name` 对应的注册项决定。

## 2. 独立配方

```lua
-- 火把：1 木材 + 1 凝胶 → 3 个火把（不需要合成站）
mod.quickapi.add_recipe{
    result    = { id = 8, count = 3 },           -- 8 = 火把
    materials = {
        { id = 9,  count = 1 },                  -- 9 = 木材
        { id = 23, count = 1 },                  -- 23 = 凝胶
    },
}

-- 铁锭：3 铁矿石 → 1 铁锭（熔炉）
mod.quickapi.add_recipe{
    result    = { id = 22, count = 1 },          -- 22 = 铁锭
    materials = { { id = 11, count = 3 } },      -- 11 = 铁矿石
    station   = 17,                              -- 17 = 熔炉
}

-- 用本 Mod 自定义物品作材料：直接写名字，不用自己等 ID
mod.quickapi.add_recipe{
    result    = { id = "magic_sword", count = 1 },
    materials = {
        { id = "magic_shard", count = 5 },
        { id = 9, count = 10 },                   -- 木材仍可混用数字 ID
    },
    station = 18,
}
```

## 参数说明

| 字段 | 类型 | 说明 |
|---|---|---|
| `result` | `number` 或 `{ id, count }` | 独立配方里写物品 ID，或 `{ id = 物品ID, count = 数量 }`；`id` 也可以是自定义物品名字符串 |
| `materials` | 数组 | `{ id = 物品ID/物品名, count = 数量 }`；至少一项 |
| `station` | `number` | 合成站对应的 **tile ID**；`-1` 或省略表示无站点 |

> `id` 写字符串时，只能是**本 Mod 通过 `register_item` 注册的物品名**（`mod.item.runtime_id(name)` 能解析的内部名）。
> 原版物品仍然写数字 `ItemID`。

常用 ID（已按 1.4.5.8 源码核对）：

| 类别 | ID | 名称 |
|---|---|---|
| 物品 | 8 | 火把 `ItemID.Torch` |
| 物品 | 9 | 木材 `ItemID.Wood` |
| 物品 | 11 | 铁矿石 `ItemID.IronOre` |
| 物品 | 22 | 铁锭 `ItemID.IronBar` |
| 物品 | 23 | 凝胶 `ItemID.Gel` |
| 物品 | 24 | 木剑 `ItemID.WoodenSword` |
| 物品 | 2 | 土块 `ItemID.DirtBlock` |
| 物品 | 3 | 石块 `ItemID.StoneBlock` |
| 图格 | 16 | 铁砧 `TileID.Anvils` |
| 图格 | 17 | 熔炉 `TileID.Furnaces` |
| 图格 | 18 | 工作台 `TileID.WorkBenches` |
| 图格 | 26 | 恶魔祭坛 / 猩红祭坛 `TileID.DemonAltar` |
| 图格 | 114 | 工匠作坊 `TileID.TinkerersWorkbench` |
| 图格 | 243 | 灌注站 `TileID.ImbuingStation` |
| 图格 | 283 | 重型工作台 `TileID.HeavyWorkBench` |
| 图格 | 355 | 炼金台（Alchemy Table） |

> 注意：**物品 ID 和 tile ID 是两套编号**。`station` 要写 tile ID，不是物品 ID。

## 完整示例

```lua
require("quickapi")

function mod.init()
    -- 自定义材料：2 个魔法尘 = 1 个凝胶（工作台）
    mod.quickapi.register_item{
        name     = "magic_dust",
        texture  = "magic_dust.png",
        maxStack = 999,
        rare     = 1,
        language = {
            en = { name = "Magic Dust" },
            zh = { name = "魔法尘" },
        },
        recipe = {
            result    = 2,
            materials = { { id = 23, count = 1 } },  -- 凝胶
            station   = 18,                          -- 工作台
        },
    }

    -- 给原版木剑加一条配方：5 木材 + 3 凝胶 → 1 木剑（工作台）
    mod.quickapi.add_recipe{
        result    = { id = 24, count = 1 },          -- 木剑
        materials = {
            { id = 9,  count = 5 },
            { id = 23, count = 3 },
        },
        station = 18,
    }
end
```

> 自定义物品作为**材料**或**产物**时，直接写物品名即可：QuickAPI 会先把配方存起来，
> 等内核分配完 `runtime_id` 后自动解析并登记（`Main.Update` 提前登记，保证第一次重建配方表就生效）。
> 也可以把配方写在物品自己的 `register_item{ recipe = ... }` 里，效果一样。

## 注意事项

- **不会立刻生效**：配方由内核在「重建配方表」时统一写入，通常发生在**进入世界 / 切换语言 / 重载 Mod** 之后。
  注册完马上打开合成表看不到是正常的。
- **数量必须 > 0**：`materials` 里 `count <= 0` 的项会被忽略；没有有效材料时注册会报错。
- **物品 ID 必须有效**：原版物品请查 `ItemID`；自定义物品建议用 `mod.quickapi.item_id(name)` 取，别硬编码。
- **材料会被标记为可合成材料**：内核会自动设置 `ItemID.Sets.IsAMaterial`，不需要手动处理。
- **配方总数**：内核已经支持超过原版 3700 条上限（桌面 / 手机），大量注册不会把原版配方挤掉。
- **不要重复注册**：Mod 热重载时 `mod.init` 会重新执行；如果配方表也重建，重复调用会得到重复配方。
  需要幂等时自行加标志位去重。
- **合成站写错不会报错**：配方只是永远不出现，所以 `station` 一定要查表。

## 常见问题

**Q：配方写好了，合成表里没有？**
先确认已经重新进入世界（或切一次语言），再检查 `station` 是否是 tile ID、材料 ID 是否正确。

**Q：`register_item` 的 `recipe.result` 和 `add_recipe` 的 `result` 为什么不一样？**
`register_item` 已经知道产物的物品 ID，`result` 只表示数量；`add_recipe` 需要完整的 `{ id, count }`。

**Q：能加「无材料」配方吗？**
不建议。`materials` 至少给一项有效材料，否则注册会报错。
