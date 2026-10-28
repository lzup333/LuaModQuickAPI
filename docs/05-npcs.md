# NPC

> 第 5 章。**NPC 目前是实验性功能**：核心的注册、生成、AI、掉落、Boss 血条已经可用，
> 但名称/图鉴、城镇 NPC（对话、商店、幸福度）、联机同步还没有完整适配。

`mod.quickapi.register_npc` 和物品/弹幕一样：**NPC 字段直接平铺**，`ai` 一旦写了就接管原版 AI。

## 最小 NPC

```lua
require("quickapi")

local id = mod.quickapi.register_npc{
    name    = "my_slime",
    texture = "slime.png",
    frames  = 1,

    width   = 32, height = 32,
    lifeMax = 200, life = 200,
    damage  = 10,
    defense = 0,
    friendly = false,

    ai = function(npc)
        -- 每帧调用；不写位移就原地不动
    end,
}
```

生成（世界坐标，返回 `Main.npc` 下标）：

```lua
local index = mod.quickapi.npc_spawn("my_slime", x, y)
```

取运行时 ID：

```lua
local id = mod.quickapi.npc_id("my_slime")   -- 注册阶段通常为 -1
```

## 元字段

| 键 | 说明 |
|---|---|
| `name` | 注册名（必填，同 Mod 内唯一） |
| `texture` | PNG 文件名；不填用占位贴图 |
| `frames` | 竖向帧图帧数；写入 `Main.npcFrameCount` |
| `defaults` | 表或函数，兼容原生写法 |
| `ai` | 每帧 `function(npc) end`；定义后跳过原版 AI |
| `vanilla_ai` | `true` = 原版 AI 先跑，再调 `ai` |
| `loot` | 死亡掉落表：`{ { id = 物品ID, count = 数量 }, ... }` |
| `on_death` / `on_kill` | 死亡回调 `function(npc) end`，先于 `loot` 执行 |

其余键都当作 `Terraria.NPC` 字段，例如 `lifeMax / life / damage / defense / boss /
noGravity / noTileCollide / knockBackResist / aiStyle / friendly / townNPC`。

## 属性/AI/掉落

### 属性

```lua
mod.quickapi.register_npc{
    name    = "test_slime",
    texture = "slime.png",
    frames  = 1,

    width  = 32, height = 32,
    lifeMax = 200, life = 200,
    damage  = 10, defense = 0,
    boss    = true,              -- Boss 血条 + 小地图图标
    friendly = false,
    noGravity = true,
    noTileCollide = true,
    knockBackResist = 0.5,
    aiStyle = 0,
}
```

`boss = true` 时内核会自动补 `NPCID.Sets.BossHeadTextures`，并启用 Boss 血条/小地图图标。

### AI 与位移

写了 `ai` 就跳过原版 `NPC.AI()`，而原版 AI 里包含重力、碰撞和 `position += velocity`。
**需要移动时请自己写**：

```lua
ai = function(npc)
    local q = mod.quickapi
    local x, y     = q.vec.get("Terraria", "NPC", "position", npc)
    local vx, vy   = q.vec.get("Terraria", "NPC", "velocity", npc)

    vy = vy + 0.15                              -- 重力
    q.vec.set("Terraria", "NPC", "velocity", npc, vx, vy)
    q.vec.set("Terraria", "NPC", "position", npc, x + vx, y + vy)
end
```

> 上面是简化示例，没有做图格碰撞。需要碰撞时自己查实心块，或先 `vanilla_ai = true`
> 让原版 AI 处理移动，再在 `ai` 里做额外逻辑。

静止的测试 NPC 更简单：

```lua
ai = function(npc)
    local q = mod.quickapi
    local x, y = q.vec.get("Terraria", "NPC", "position", npc)
    q.vec.set("Terraria", "NPC", "velocity", npc, 0, 0)
    q.vec.set("Terraria", "NPC", "position", npc, x, y)
end
```

### 掉落与死亡回调

```lua
mod.quickapi.register_npc{
    name    = "loot_slime",
    texture = "slime.png",
    lifeMax = 120, life = 120,
    friendly = false,

    loot = {
        { id = 23, count = 3 },   -- 23 = 凝胶
    },

    on_death = function(npc)
        -- 先于 loot 执行；可以做条件掉落
        -- mod.npc.drop_item(23, x, y, 1)
    end,
}
```

- `loot` 在 NPC 死亡时按尸体中心掉落；
- `on_death`（`on_kill` 同义）先执行，可在里面再调 `mod.npc.drop_item(id, x, y, count)`；
- 掉落的是原版/已注册物品 ID，不要写物品名字。

## 完整示例

```lua
require("quickapi")

local function npc_ai(npc)
    -- 站着不动的测试 Boss
    local q = mod.quickapi
    local x, y = q.vec.get("Terraria", "NPC", "position", npc)
    q.vec.set("Terraria", "NPC", "velocity", npc, 0, 0)
    q.vec.set("Terraria", "NPC", "position", npc, x, y)
end

function mod.init()
    mod.quickapi.register_npc{
        name    = "TestSlime",
        texture = "TestSlime.png",
        frames  = 1,

        width = 32, height = 32,
        lifeMax = 200, life = 200,
        damage = 10, defense = 0,
        boss = true,
        friendly = false,
        aiStyle = 0,
        noGravity = true,
        noTileCollide = true,
        knockBackResist = 0.5,
        scale = 1.0,

        loot = { { id = 23, count = 3 } },   -- 凝胶 x3
        ai = npc_ai,
    }

    mod.quickapi.register_item{
        name    = "SlimeStaff",
        texture = "SlimeStaff.png",
        damage  = 1,
        useStyle = 1, useTime = 20, useAnimation = 20,
        maxStack = 1,
        use = function(player, item)
            local x, y = mod.quickapi.vec.get(
                "Terraria", "Player", "position", player)
            mod.quickapi.npc_spawn("TestSlime", x + 48, y)
        end,
    }
end
```

## 注意事项

- **实验性**：以下能力还没有完整支持，正式模组请谨慎使用：
  - 名称/图鉴：手机端 `Lang.GetNPCName` 的 const 守卫导致自定义名字取不到；
  - 城镇 NPC：商店、幸福度、入住条件没有适配，`townNPC = true` 可能触发原版越界；
  - 联机：没有 `SyncNPC` / 自定义 AI 包同步。
- **ID 不要硬编码**：注册阶段 `npc_id()` 可能返回 `-1`，生成时用名字 `npc_spawn(name, x, y)`。
- **`ai` 完全接管**：不写 `position += velocity` 就不会动；需要原版移动时用 `vanilla_ai = true`。
- **纹理帧**：`texture` 高度要能被 `frames` 整除。
- **生成位置**：`npc_spawn` 用世界坐标（像素），不是图格坐标。
- **不要一次生成太多**：`Main.npc` 槽位有限，测试时建议少量生成。

## 常见问题

**Q：NPC 生成了但看不见？**
检查 `texture` 路径、`frames` 是否与 PNG 高度匹配；手机端还要确认内核版本支持补绘制。

**Q：NPC 不动？**
自定义 `ai` 里必须自己更新 `position`；只改 `velocity` 不会移动。

**Q：打死 NPC 崩溃？**
确认内核是较新版本（掉落使用 `Item.NewItem`，旧内核可能缺少导出符号）；并把日志里的
`npc drop` / `CRITICAL` 段发给开发者。

**Q：NPC 没有名字 / 图鉴？**
目前是已知限制，等 NPC 模块转正后补。
