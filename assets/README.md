# assets 素材说明

当前版本全部使用**多边形色块占位**（Polygon2D），零外部素材，保证骨架立刻能跑。

后续替换真实美术时按目录放：

```
assets/
├── sprites/    # 角色/敌人/道具/瓦片贴图（PNG，建议像素风 + 每格16~32px）
├── audio/      # BGM / SFX（.ogg 优先，体积小）
├── fonts/      # 自定义字体（默认用系统字体）
```

## 素材来源建议

| 用途 | 来源 | 协议 |
|---|---|---|
| 森林王国素材 | kenney.nl 的 Platformer Pack Redux | CC0（免费商用） |
| 补充像素素材 | itch.io 搜索 free platformer assets | 逐个看授权 |
| 音效 | freesound.org / Kenney Audio | 注意署名要求 |
| 水墨山水（World2） | 自绘 / 约稿，或 AI 生成后手动整理 | — |

## 换素材时注意

- 把占位 Polygon2D 视觉节点换成 Sprite2D + 贴图即可，碰撞体（CollisionShape2D）不用动。
- 角色素材规格建议：宽 16~32px，跳跃/跑步各至少 2~4 帧，方便接入 AnimationPlayer。
