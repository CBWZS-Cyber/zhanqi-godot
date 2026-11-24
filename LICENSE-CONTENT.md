# 创作内容授权（与代码许可分开）

本仓库分两类内容，**许可不同**，请勿混用。

## 一、代码 —— GPL-3.0

适用范围：

- 全部 `*.gd`、`*.tscn`、`*.tres`、`*.cfg`
- `tools/` 下的 Node.js / Python 实现（含 `cloud-service`、`room-service`、`relay-service`）
- `data/*.json` 中的**数值与规则配置**
- `tests/` 下的全部测试脚本

许可全文见 [LICENSE](LICENSE)（GNU General Public License v3.0）。

要点：

- 可以自由使用、修改、分发，包括商用
- **衍生作品必须以 GPL-3.0 开源**（不能拿去做闭源商业游戏）
- 必须保留版权声明与许可文本
- 作者保留另行商业授权的权利（双许可）

## 二、创作内容 —— CC BY-NC-ND 4.0

适用范围：

- `story/` —— 剧情文本、章节、往事（含 `追猎往事——龙息.docx`）
- `art/角色设定文档/` —— 人设、世界观设定（含 `孤狼.docx` 等）
- `docs/` 下除技术接口契约外的设计文档与视觉稿
- 游戏内出现的角色名、专有名词、世界观设定

许可：[CC BY-NC-ND 4.0](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.zh-hans)

- **署名**：须注明原作者
- **非商业**：不得用于商业目的
- **禁止演绎**：不得修改后分发（可原样转载）

## 三、未包含在仓库中的资源

以下资源**不在本仓库内**（已由 `.gitignore` 排除），**保留所有权利**：

| 资源 | 说明 |
|---|---|
| `assets/heroes/*.jpg` `*.png` | 英雄立绘、头像 |
| `assets/db/*_tex.png` | DragonBones 拆解贴图 |
| `assets/fonts/*` | 字体文件（原有许可见各自 `LICENSE-*.txt`） |
| `assets/sfx/` `assets/video/` | 音效、视频 |
| `art/设定稿/` | 设定稿原图 |

想在自己的项目里用这些美术资源，请联系作者。

## 四、第三方组件

| 组件 | 许可 | 说明 |
|---|---|---|
| [Godot Engine](https://godotengine.org) 4.7.2 | MIT | 游戏引擎 |
| Noto Sans SC / Noto Serif SC | SIL OFL 1.1 | 正文字体 |
| Ma Shan Zheng（马善政毛笔楷书） | SIL OFL 1.1 | 标题字体 |
| DragonBones 运行时 | MIT | 骨骼动画 |

## 五、联系方式

- 作者：曹博文
- 仓库 Issue 优先；商业授权 / 美术素材授权请单独联系

---

_最后更新：2026-11-24_
