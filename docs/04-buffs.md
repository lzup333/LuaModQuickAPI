# Buff（增益 / 减益）

> 第 4 章。Buff 由内核**自管理**，不占用原版 `BuffID`，也不写入 `player.buffType`。

`mod.quickapi.register_buff` 负责注册图标、名称、说明和回调；真正的效果必须写在 `update` 里，
因为原版不认识自定义 Buff 的 ID。

## 最小 Buff

```lua
require("quickapi")

local id = mod.quickapi.register_buff{
    name    = "my_regen",
    texture = "buff.png",       -- 不放就用内核占位图

    update = function(player, buff_index)
        -- 每帧调用；效果写这里
        local life = mod.quickapi.get_field_value(
            "Terraria", "Player", "statLife", player, "int32")
        -- statLife 是整数；每帧回复 1 点，避免写入 0.1 后被截断
        mod.quickapi.set_field_value(
            "Terraria", "Player", "statLife", player, life + 1, "int32")
    end,

    language = {
        en = { name = "My Regen", description = "+60 life/s" },
        zh = { name = "我的再生", description = "每秒回复 60 点生命" },
    },
}
```

## 字段

| 键 | 说明 |
|---|---|
| `name` | 注册名（必填，同 Mod 内唯一） |
| `texture` | 图标 PNG；不填用占位图 |
| `debuff` | `true` = 减益：红框、不可右键取消、护士治疗会清除 |
| `no_time` | `true` = 不显示剩余时间 |
| `pvp` | `true` = 只在 PvP 生效 |
| `light_pet` | 光源宠物（同类互斥） |
| `vanity_pet` | 观赏宠物（同类互斥） |
| `apply` | `function(player, time) end`，挂上时一次 |
| `update` | `function(player, buff_index) end`，每帧 |
| `language` | `{ en = { name, description }, zh = {...} }` |

> `time` 是剩余帧数，`60` 帧 = 1 秒。

## 挂上 / 查询 / 移除

```lua
-- 按名字挂 5 秒（内部转帧）
mod.quickapi.buff_apply(player, "my_regen", 5)

-- 自己拿 ID
local id = mod.quickapi.buff_id("my_regen")
mod.quickapi.player_add_buff(player, id, 60 * 5)   -- 帧
mod.quickapi.player_buff_time(player, id)          -- 剩余帧，未挂上返回 0

-- 立即移除
mod.buff.remove(id, player)
```

- `buff_apply` 返回 `true, 剩余帧数`，失败返回 `false, 错误信息`；`player_add_buff` 成功返回 `true`，失败返回 `false, 错误信息`。
- 重复挂同一个 Buff 会刷新时长并再次触发 `apply`。

## update 的第二个参数

`buff_index` 是内核激活列表里的下标，**不是** `player.buffType[]` 的槽位。

```lua
update = function(player, buff_index)
    -- 不要写 player.buffType[buff_index]！
end
```

自定义 Buff 不进入原版 `buffType`，也不应该拿自定义 ID 去索引 `buffImmune`、`buffNoSave`、
`TextureAssets.Buff`、`Lang` 缓存等原版定长表——内核已经绕开了这些路径。

## 减益规则

```lua
mod.quickapi.register_buff{
    name    = "my_poison",
    debuff  = true,
    texture = "poison.png",
    update = function(player)
        mod.quickapi.invoke("Terraria", "Player", "Hurt",
                player, 1, 0, false, false, false, -1)
    end,
    language = {
        en = { name = "My Poison", description = "..." },
        zh = { name = "我的中毒", description = "..." },
    },
}
```

- `debuff = true` 时玩家不能右键取消；
- 护士治疗会清除所有自定义减益（原版只清 `buffType`，内核补了这一层）；
- 死亡时是否保留沿用原版行为。

## 存档

自定义 Buff 写进 `<角色>.plr.tef` 伴生文件，按 `(loader / mod / name)` 存读：

- 卸载 Mod 后不会在存档里留下无效 ID；
- 重新装回同一 Mod 时按名字恢复；
- 不占用原版 Buff 存档字段。

## 注意事项

- **效果必须自己写**：`update` 每帧调用，属性加成、扣血、召唤都要在这里做；
- **不要写 `player.buffType`**：会绕过内核状态，且可能越界；
- **`apply` 只在成功挂上时调用**：目标免疫 / 时长为 0 不会触发；
- **图标/名称/说明走 `language`**：缺省时显示内部键名；
- **多人游戏**：自定义 Buff 目前没有联机同步，先按单机/本地测试；
- **同一 Buff 重复注册**：会按名字替换旧项，但旧 ID 上的状态需要自己清理。

## 常见问题

**Q：Buff 挂上了但没有效果？**
效果不会自动生效，必须写在 `update` 里，并且每帧都会调用。

**Q：右键取消失败？**
`debuff = true` 的 Buff 本身就不能右键取消；普通 Buff 可以。

**Q：退出重进 Buff 没了？**
确认 Mod 仍然加载，并且 `.plr.tef` 还在；卸载过 Mod 会按名字恢复失败。
