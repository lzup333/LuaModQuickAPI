# 弹幕

> 第 3 章。弹幕是武器、Buff、NPC 的“表现层”，建议先掌握 [物品](02-items.md) 的 `shoot`。

`mod.quickapi.register_projectile` 的写法和物品一致：**Projectile 字段直接平铺**，
`ai` 一旦写了就由 Lua 接管，内核会跳过原版 `Projectile.AI()`。

## 最小弹幕

```lua
require("quickapi")

local id = mod.quickapi.register_projectile{
    name    = "my_orb",
    texture = "orb.png",

    width    = 16, height = 16,
    damage   = 18,
    timeLeft = 300,
    friendly = true,
    hostile  = false,
    tileCollide = false,

    ai = function(p)
        -- 每一帧调用；位移必须自己写
        mod.quickapi.projectile_move(p)
    end,
}
```

## 元字段

| 键 | 说明 |
|---|---|
| `name` | 注册名（必填，同 Mod 内唯一） |
| `texture` | PNG 文件名；不填使用占位贴图 |
| `frames` | 竖向帧图帧数；`0` = 单帧整图 |
| `ai` | 每帧回调 `function(projectile) end`；定义后跳过原版 AI |
| `no_ai` | `true` = 不接管 AI，沿用 `aiStyle` |
| `vanilla_ai` | `true` = 原版 AI 先跑，再调 `ai` |
| `on_kill` / `kill` | 销毁回调 `function(projectile) end` |
| `on_hit_npc` / `hit_npc` | `function(projectile, npc, damage, hit_direction, crit) end` |
| `on_hit_player` / `hit_player` | `function(projectile, player, damage, hit_direction, pvp, crit) end` |
| `on_tile_collide` / `tile_collide` | `function(projectile, old_vx, old_vy) end` |
| `defaults` | 表或函数，兼容原生写法 |

## AI：先搞清楚“每帧要做什么”

`ai` 不是只执行一次的初始化函数，而是弹幕存在期间**每帧执行一次**的函数。可以把它想成下面这个循环：

```text
读取当前状态 → 修改速度/角度 → 移动 → 等下一帧
```

只要自己写了 `ai`，原版的 `Projectile.AI()` 就不会执行。原版 AI 通常会负责重力、碰撞和
`position += velocity`；这些行为也会一起消失。因此最简单的自定义 AI 至少要调用一次
`projectile_move(p)`，否则只改 `velocity` 也不会真的移动。

### 1. 先让弹幕直线飞

弹幕的位置是 `position`，速度是 `velocity`。`projectile_move` 会把这一帧的速度加到位置上，
并默认让贴图朝向飞行方向：

```lua
ai = function(p)
    mod.quickapi.projectile_move(p)
end
```

这段代码的效果相当于：

```lua
-- 伪代码：每帧执行
position = position + velocity
rotation = 速度的方向
```

如果贴图不需要跟着速度旋转，可以关闭自动旋转：

```lua
ai = function(p)
    mod.quickapi.projectile_move(p, { face_velocity = false })
end
```

贴图默认按“朝右（+x）”处理。贴图朝向不同，可以用 `rotation_offset` 修正，例如贴图朝上时：

```lua
mod.quickapi.projectile_move(p, { rotation_offset = math.pi / 2 })
```

### 2. 在移动前改速度

AI 的顺序很重要：先改速度，再移动，当前帧就会使用新速度。

```lua
ai = function(p)
    local q = mod.quickapi
    local vx, vy = q.vec.get("Terraria", "Projectile", "velocity", p)

    vy = vy + 0.15       -- 重力：每帧让下落速度增加一点
    q.vec.set("Terraria", "Projectile", "velocity", p, vx, vy)
    q.projectile_move(p)
end
```

想让弹幕加速、减速或转弯，基本都是同一个套路：读取 `velocity`，算出新速度，写回去，
最后调用 `projectile_move`。只改速度、不调用移动函数，位置不会变化。

### 3. 做一个会追踪的弹幕

追踪可以拆成三步：找目标、把目标位置交给转向函数、移动。

```lua
ai = function(p)
    local q = mod.quickapi
    local npc = q.find_nearest_npc(p, 900)  -- 900 是像素范围

    if npc then
        local x, y = q.vec.get("Terraria", "NPC", "position", npc)
        q.projectile_homing(p, x, y, 0.18)
    end

    q.projectile_move(p)
end
```

`find_nearest_npc` 只会返回范围内最近的、存活且非友方 NPC；找不到时返回 `nil`。
`projectile_homing(p, x, y, rate, max_turn)` 会保持原来的速度大小，只改变飞行方向：

- `rate` 是每帧转向的比例。`0.1` 转得慢、轨迹更平滑，`1` 会直接朝向目标；通常从 `0.1 ~ 0.2` 开始调。
- `max_turn` 是单帧最大转角，单位是弧度。不传时不额外限制，想让追踪更自然时再加上它。

例如限制每帧最多转 0.12 弧度：

```lua
q.projectile_homing(p, x, y, 0.25, 0.12)
```

### 4. 用计时器做分阶段 AI

弹幕经常需要“前 30 帧直飞，之后开始追踪”之类的阶段。不要把计时变量放在 `ai` 函数外面，
否则多个弹幕会共用同一个计时器。可以把计时值放进弹幕自己的 `localAI`：

```lua
ai = function(p)
    local q = mod.quickapi
    local ctx = q.proj(p)
    local age = ctx.ai(0) + 1
    ctx.set_ai(0, age)

    if age > 30 then
        local npc = q.find_nearest_npc(p, 900)
        if npc then
            local x, y = q.vec.get("Terraria", "NPC", "position", npc)
            q.projectile_homing(p, x, y, 0.18)
        end
    end

    q.projectile_move(p)
end
```

`ctx.ai(0)`、`ctx.ai(1)`、`ctx.ai(2)` 是这个弹幕自己的三个小数计数槽，不同弹幕之间互不共享。
需要更多状态时，可以把状态编码到这些槽里，或直接读取/写入其他 Projectile 字段。

### 5. 什么时候保留原版 AI

如果只是想在原版移动基础上加一点效果，不必完全接管 AI，可以使用 `vanilla_ai = true`：

```lua
mod.quickapi.register_projectile{
    name = "spark",
    texture = "spark.png",
    vanilla_ai = true,
    ai = function(p)
        -- 原版 AI 已经先处理移动、重力等行为
        -- 这里写额外效果，例如改旋转或推进帧动画
        mod.quickapi.projectile_animate(p, 4)
    end,
}
```

需要自己控制完整运动轨迹时，不要同时依赖原版移动和 `projectile_move`，否则弹幕可能一帧移动两次。

## 弹幕上下文 q.proj

反复拼字段名很累，`mod.quickapi.proj(p)` 提供常用字段的上下文：

```lua
local ctx = mod.quickapi.proj(p)

local x, y = ctx.pos()
ctx.set_pos(x + 1, y)
ctx.add_vel(0, 0.2)

ctx.rot = ctx.vel_angle()          -- 贴图朝右
ctx.ai(0)                          -- localAI[0]
ctx.set_ai(1, ctx.ai(1) + 1)

if ctx.solid(wx, wy) then ... end
for _, t in ipairs(ctx.players(600)) do
    -- t.player / t.index / t.dist
end
ctx.kill()
```

完整成员见 README 的「弹幕上下文」表。

## 帧动画

```lua
mod.quickapi.register_projectile{
    name = "spinner",
    texture = "spinner.png",   -- 竖向帧图
    frames = 6,
    ai = function(p)
        mod.quickapi.projectile_animate(p, 6)   -- 每 6 帧推进一帧
        mod.quickapi.projectile_move(p)
    end,
}
```

`texture` 高度必须能被 `frames` 整除。

## 命中 / 撞墙 / 销毁

```lua
mod.quickapi.register_projectile{
    name = "bouncy_orb",
    texture = "orb.png",
    friendly = true,
    width = 16, height = 16,
    damage = 20,
    timeLeft = 600,

    on_hit_npc = function(projectile, npc, damage, hit_direction, crit)
        -- 穿透时会按 NPC 逐个回调；不需要手动 StrikeNPC
    end,

    on_hit_player = function(projectile, player, damage, hit_direction, pvp, crit)
        -- PvP / 敌弹命中玩家
    end,

    on_tile_collide = function(projectile, old_vx, old_vy)
        -- 想反弹就自己写回 velocity
        local ctx = mod.quickapi.proj(projectile)
        ctx.set_vel(-old_vx * 0.8, -old_vy * 0.8)
    end,

    on_kill = function(projectile)
        -- 命中、超时、手动 Kill 都会走这里
    end,

    ai = function(p)
        mod.quickapi.projectile_move(p)
    end,
}
```

## 注意事项

- **挂了 `ai` 就完全接管**：原版 AI 不会执行，重力、追踪、撞墙后的反弹都要自己写；
  需要原版先跑时用 `vanilla_ai = true`。
- **`rotation` 约定是「贴图朝右」**：`projectile_move` 和 `ctx.vel_angle()` 都按这个约定。
- **ID 不要硬编码**：用 `mod.quickapi.projectile_id(name)`；注册阶段可能还是 `-1`。
- **伤害由原版结算**：`Projectile.Damage()` 里会走 `NPC.StrikeNPC` / `Player.Hurt`，
  回调里不要重复调用，否则会双倍伤害。
- **`timeLeft` 是帧**（60 帧 = 1 秒）；超时销毁会触发 `on_kill`。
- **自定义弹幕目前没有本地化名字**：死亡消息/悬浮名可能为空，这是已知限制。
- **静态免疫分组**：如果弹幕打开 `usesIDStaticNPCImmunity`，不同自定义弹幕之间会共用同一免疫分组
  （内核的临时兜底），需要精细控制时先不要开这个字段。
- **多人游戏**：自定义弹幕没有完整联机同步，先按单机/本地测试。

## 常见问题

**Q：弹幕生成后不动？**
检查是否写了 `ai` 但没调用 `projectile_move(p)`，或者只改了 `velocity` 没改 `position`。

**Q：弹幕贴图方向不对？**
`rotation` 按“朝右”约定；如果你的贴图原本朝上，请在 PNG 里转 90 度，或在 AI 里加偏移。

**Q：`on_hit_npc` 不触发？**
确认 `friendly` / `hostile` 设置正确，并且弹幕确实造成了伤害；穿透弹幕会对每个 NPC 回调。
