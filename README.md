# Forest Kingdom Platformer (MVP) 🍄

用 Godot 4.7 + GDScript 做的**平台跳跃游戏骨架**。
当前为「森林王国 World 1」最小可玩版本（能跑、能跳、能收集、能通关），
水墨山水 World 2 结构已预留。

## 快速开始

1. 安装 Godot 4.7（macOS: `brew install --cask godot`）
2. 用 Godot 打开本目录的 `project.godot`
3. 按 F5（或点右上角播放）直接运行

## 操作

| 按键 | 动作 |
|---|---|
| A / D / ← → | 左右移动 |
| 空格 / W / ↑ | 跳跃（按住跳更高，松手快速下落） |

## 目录结构

```
platformer/
├── project.godot          # 项目配置（含 输入/渲染/主场景）
├── autoload/game.gd       # 全局单例 Game：生命/金币、关卡顺序表 LEVEL_SEQUENCE
├── scenes/
│   ├── player/            # 玩家：蘑菇人（移动+变量跳跃+缓冲+土狼时间）
│   ├── levels/            # 关卡：level_1_1（森林首关），world2_ink/ 留给水墨
│   └── ui/                # （预留）HUD / 主菜单 / 结算
└── assets/                # 素材占位说明（见下）
```

## 关卡交互约定（group 约定优于硬编码信号）

| Group | 节点 | 效果 |
|---|---|---|
| `coins` | Area2D 金币 | 吃到 +1 金币 |
| `killzone` | Area2D 坠落区 | 扣一条命并重开本关 |
| `goal` | Area2D 终点旗 | 触发通关、按顺序表进下一关 |
| `hazard` | Area2D 尖刺/敌人 | **预留**，后续加伤害逻辑 |

在任意关卡场景里添加带对应 group 的 Area2D 即自动生效，关卡脚本无需改动。

## 玩法推进（Progression）

`Game.LEVEL_SEQUENCE` 数组就是推进主干：数组里按顺序追加关卡条目即可串联流程。
水墨 World 2 接入示例（追加到数组末尾，并新建对应场景）：

```gdscript
{ "scene": "res://scenes/levels/world2_ink/level_2_1.tscn", "world": "ink", "display": "水墨山水 2-1" }
```

## 素材规划（assets/）

- **森林王国**：先用多边形色块占位跑通玩法。正式素材可换 Kenney「Platformer Pack Redux」等 CC0 素材（kenney.nl / itch.io）。
- **水墨山水（World 2）**：建议自绘/外包像素水墨风，清屏色改纸色/青色即可换主题（参考 `level_1_1.gd` 中的 `RenderingServer.set_default_clear_color`）。

## Roadmap

- [x] 项目骨架 + 玩家移动跳跃手感 + 首关可玩
- [ ] 主菜单 / 关卡选择（世界地图）
- [ ] 敌人 & 尖刺（hazard 伤害逻辑）
- [ ] World 2 水墨山水关卡
- [ ] GitHub 托管 + 网页导出部署（GL Compatibility 渲染已就绪）
