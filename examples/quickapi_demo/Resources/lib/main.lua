-- QuickAPIDemo —— quickapi 最小示例（MIT）
--
-- 把 quickapi.lua 与本文件放在同目录（部署后即 <private_dir>/lib/），
-- 入口首行 require("quickapi") 之后，mod.quickapi.* 即可用。
--
-- 演示内容：
--   · 安装一个 postfix 钩子
--   · 注册 Buff（update 里回血）
--   · 注册物品：木头 x1 合成；use 回调挂 Buff；shoot 发射自定义弹幕
--   · 注册弹幕：q.proj 上下文 + on_kill 回调

require("quickapi")

local q = mod.quickapi

mod.meta = { pkg_id = "lzup.lua.quickapidemo", version = "1.1.0" }

local function InvokedLog()
    mod.info("Terraria.Item.SetDefaults 已被调用！")
end

local heal_tick = 0

local function demo_buff_update(player)
    heal_tick = heal_tick + 1
    if heal_tick < 30 then return end
    heal_tick = 0

    local life = q.get_field_value("Terraria", "Player", "statLife", player, "int32") or 0
    local max = q.get_field_value("Terraria", "Player", "statLifeMax2", player, "int32") or life
    if life < max then
        q.set_field_value("Terraria", "Player", "statLife", player, math.min(life + 2, max), "int32")
    end
end

function setup()
    q.install_hook_postfix("Terraria", "Item", "SetDefaults", InvokedLog)

    q.register_buff{
        name = "demo_buff",
        language = {
            en = { name = "Demo Buff", description = "Regenerates 2 life every 30 ticks" },
            zh = { name = "演示 Buff", description = "每 30 tick 回复 2 点生命" },
        },
        update = demo_buff_update,
    }

    q.register_projectile{
        name = "demo_orb",
        width = 16, height = 16,
        damage = 20, knockBack = 2.0, timeLeft = 300,
        friendly = true, tileCollide = false, light = 0.6,

        ai = function(p)
            local ctx = q.proj(p)
            ctx.set_ai(0, ctx.ai(0) + 1)
            q.projectile_move(p)
        end,

        on_kill = function(p)
            mod.info("演示弹幕已销毁")
        end,
    }

    q.register_item{
        name = "demo_charm",
        tooltip = true,

        width = 24, height = 24,
        useStyle = 1, useTime = 20, useAnimation = 20, maxStack = 1,
        shoot = "demo_orb", shootSpeed = 10.0,

        language = {
            en = { name = "Demo Charm", tooltip = "Use: fires an orb and applies Demo Buff" },
            zh = { name = "演示护符", tooltip = "使用：发射演示弹幕并挂上演示 Buff" },
        },
        recipe = { result = 1, materials = { { id = 9, count = 1 } }, station = 18 },

        use = function(player)
            q.buff_apply(player, "demo_buff", 5)
        end,
    }
end

todo_list = { "setup" }
