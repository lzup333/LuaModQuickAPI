# 音效

TEFKernel 提供两层音频能力，QuickAPI 统一挂在 `q.audio`（即 `mod.audio`）下。

## 1. 原版音效

```lua
-- 直接播放 SoundID 里的音效
q.audio.play_vanilla("Item1")                 -- 全局播放
q.audio.play_vanilla("Item14", x, y)          -- 按世界坐标播放（带距离衰减）
q.audio.play_vanilla("NPCHit1", x, y, 0.0, 1.0) -- pitch, volume
```

`play_vanilla` 返回 `true`，失败返回 `nil, err`。

注册内容时也能声明原版音效：

```lua
-- 物品：使用音效
q.register_item{
    name = "my_sword",
    use_sound = "Item1",
    -- ...
}

-- NPC：受击 / 死亡音效
q.register_npc{
    name = "my_slime",
    hit_sound = "NPCHit1",
    death_sound = "NPCDeath1",
    -- ...
}
```

弹幕没有 per-type 音效字段；在 `on_hit_npc` / `on_kill` 里手动播放即可：

```lua
q.register_projectile{
    name = "my_bolt",
    on_hit_npc = function(p, npc, damage, dir, crit)
        q.audio.play_vanilla("Item1", p.position.X, p.position.Y)
    end,
}
```

## 2. 自定义音频文件

目前支持 **WAV**（PCM 8/16/24/32 位或 32 位 float），自动转换为混音器使用的 float32。

```lua
local snd = q.audio.load("Audio/boom.wav", {
    looping = false,   -- 可选
    volume  = 1.0,     -- 可选，默认 1.0
})

local id = snd:play()                  -- 返回 voice id
local id2 = snd:play_at(x, y, 0.8)     -- 按坐标播放 + 音量

q.audio.pause(id)
q.audio.resume(id)
q.audio.stop(id)
q.audio.set_volume(id, 0.5)
q.audio.is_playing(id)

snd:stop_all()
snd:unload()                           -- 注销并释放（停止后调用）
```

`load` 返回 userdata；Lua GC 时会自动注销。若要立即释放，先 `snd:stop_all()` 再 `snd:unload()`。

## 3. 全局音量

```lua
q.audio.set_master_volume(0.7)
```

## 注意事项

- 自定义音频不经过原版 `SoundEngine`，不受原版音效音量设置影响；用 `set_master_volume` 控制。
- 音源采样率必须与设备一致（当前内核不做重采样）；常见 44100/48000 均可。
- `unload` 后不要再使用该 voice id。
- 旧版内核 / LuaLoader 可能没有 `mod.audio`，可用 `if q.audio then ... end` 判断。
