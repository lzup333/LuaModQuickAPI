# 图格（Tile）

> 第 6 章。通过 `mod.quickapi.register_tile` 注册自定义方块、矿石、平台、家具等图格，并用物品的 `create_tile` 放置在世界里。

## 最小方块与放置物品

```lua
require("quickapi")

function setup()
    mod.quickapi.register_tile{
        name       = "purple_ore",
        texture    = "PurpleOre.png",
        min_pick   = 35,
        mine_resist = 1.5,
        shine      = 1150,
        spelunker  = true,
        light      = { r = 0.45, g = 0.15, b = 0.65 },
        map_color  = { r = 170, g = 65, b = 225 },
        language   = { en = "Purple Ore", zh = "紫色矿石" },
    }

    mod.quickapi.register_item{
        name        = "purple_ore_item",
        texture     = "PurpleOreItem.png",
        create_tile = "purple_ore",   -- 绑定本 Mod 图格名
        useStyle    = 1,
        useTurn     = true,
        useAnimation = 15,
        useTime     = 10,
        autoReuse   = true,
        consumable  = true,
        maxStack    = 9999,
        width       = 16,
        height      = 16,
        language    = {
            en = { name = "Purple Ore" },
            zh = { name = "紫色矿石" },
        },
    }
end
```

## 常用元字段

| 键 | 说明 |
|---|---|
| `name` | 图格内部名（必填，同 Mod 内唯一） |
| `texture` | 图格贴图 PNG，需按泰拉瑞亚图格图集帧格式排版 |
| `object_style` | 多格/家具预设：`"none"`、`"torch"`、`"platform"`、`"chair"`、`"workbench"`、`"table"`、`"sapling"`、`"banner"`、`"closed_door"`、`"1x1"`、`"1x2"`、`"2x1"`、`"2x2"`、`"3x2"`、`"3x3"`、`"3x3_wall"` |
| `solid` / `solid_top` | 实心碰撞 / 仅顶部可站立（`"platform"` 与 `"closed_door"` 默认 `solid = true`，`"platform"` 默认 `solid_top = true`） |
| `block_light` / `frame_important` | 遮挡光线 / 按帧图放置（非 `"none"` 预设默认 `frame_important = true`） |
| `min_pick` / `mine_resist` | 最低镐力（`0` 为任意镐）与挖掘耐久系数（默认 `1.0`） |
| `cut` / `no_fail` / `no_attach` | 挥砍破坏 / 一击碎裂 / 不可附着 |
| `table` / `lava_death` / `water_death` | 视为桌子 / 岩浆摧毁 / 水摧毁 |
| `lava_immune_object` | 家具类物体免疫岩浆破坏 |
| `shine` / `spelunker` / `bouncy` / `blend_all` / `merge_dirt` | 闪光频率 / 洞穴探险高亮 / 弹性 / 全融合 / 与泥土融合 |
| `dust_type` | 挖掘粒子 ID |
| `hit_sound` | 敲击音效：`{ type = ..., style = ... }` |
| `drop` / `drop_stack` | 静态掉落：`false` 禁掉 / 物品 ID / 本 Mod 物品名 / `{ item = ..., count = ... }`；省略则自动关联 `create_tile == 该图格` 的物品 |
| `on_drop` | 动态掉落覆盖：`function(x, y) return "my_item", 1 end`（返回 `false` 禁掉，返回 `nil` 回落静态规则） |
| `merge_with` | 双向融合列表，可混写原版 TileID 或本 Mod 图格名 |
| `adj_tiles` | 等价合成站列表（如 `{ 18 }` 表示兼作工作台，支持自定义图格名） |
| `light` | 静态自发光 RGB（`0..1`）：`{ r = 0.65, g = 0.25, b = 0.85 }` |
| `map_color` | 小地图颜色 RGB（`0..255`）：`{ r = 170, g = 65, b = 225 }` |
| `language` | 小地图图例本地化名称：`{ en = "...", zh = "..." }` |

## 平台 / 合成站 / 运行时 ID

```lua
-- 注册平台（1x1 水平拼合图集，参考原版 Tile 19）
mod.quickapi.register_tile{
    name         = "purple_platform",
    texture      = "PurplePlatform.png",
    object_style = "platform",
    solid        = true,
    solid_top    = true,
    merge_with   = { "purple_ore", 1 },
}

-- 配方里可以直接把自定义图格名当作 station
mod.quickapi.add_recipe{
    result    = { name = "purple_ore_item", count = 2 },
    materials = { { id = 2, count = 1 } },
    station   = "my_workbench_tile",
}

-- 运行时查询 TileID 与动态修改融合
local tid = mod.quickapi.tile_id("purple_ore")
mod.quickapi.set_tile_merge("purple_ore", 1, true)
```

## 注意事项

- **光照线程限制**：游戏光照扫描可能跑在后台渲染线程上，`light` 只支持静态 RGB，不支持 Lua 每帧回调。
- **贴图图集尺寸**：普通方块需使用完整方块图集（如 288x270）；平台/火把/工作台等预设请对应原版图格的帧宽高排版。
- **`create_tile` 延时解析**：物品声明 `create_tile = "tile_name"` 或配方声明 `station = "tile_name"` 时，QuickAPI 会自动等 ID 分配完成后写入。
