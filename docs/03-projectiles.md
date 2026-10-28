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

## AI：位移必须自己算

原版 `Projectile.AI()` 内部会做 `position += velocity`，我们跳过原版后这一步就没了。
**只改 `velocity` 不写 `position`，弹幕会停在原地。**

```lua
ai = function(p)
    mod.quickapi.projectile_move(p)   -- position += velocity，并按速度设置 rotation
end
```

`projectile_move(p, opts)`：

- `opts.face_velocity = false`：只移动，不改 `rotation`（贴图朝右约定）；
- 需要重力/加速度时，自己改 `velocity` 后再调用。

追踪弹幕：

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

`projectile_homing(p, tx, ty, rate, max_turn)` 会在保持速率的前提下转向目标。

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
