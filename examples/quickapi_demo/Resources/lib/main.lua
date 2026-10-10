-- QuickAPIDemo —— quickapi 最小示例（MIT）
--
-- 把 quickapi.lua 与本文件放在同目录（部署后即 <private_dir>/lib/），
-- 入口首行 require("quickapi") 之后，mod.quickapi.* 即可用。

require("quickapi")

mod.meta = { pkg_id = "lzup.lua.quickapidemo", version = "1.0.0" }

function InvokedLog()
    mod.info("Terraria.Item.SetDefaults已被调用！")
end

function setup()
    mod.quickapi.install_hook_postfix("Terraria", "Item", "SetDefaults", InvokedLog)
end

todo_list = { "setup" }
