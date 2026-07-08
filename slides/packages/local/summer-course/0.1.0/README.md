# 課程簡報主題

基於 [touying](https://typst.app/universe/package/touying) 的共用簡報主題。設計語言：大量留白、襯線標題 + 無襯線內文、細線與圓角卡片、冷色 **Graphite & Iris** 配色。編譯只需要系統有 `typst`（0.13+）與 Noto Sans/Serif TC、JetBrains Mono 字型，無編輯器依賴。

```bash
make -C slides pdf
make -C slides pptx
make -C slides png PNG_PPI=216
make -C slides cheatsheet CHEATSHEET_COLUMNS=3
```

## 最小骨架

```typst
#import "@local/summer-course:0.1.0": *

#show: course-theme.with(
  config-info(
    title: [課程名稱], subtitle: [副標], author: [講者],
    institution: [單位], short-title: [頁腳短標], date: datetime.today(),
  ),
)

#title-slide()      // 封面
#outline-slide()    // 目錄（自動蒐集所有 `=` 章節）

= 章節名             // 自動產生深色分隔頁
== 頁面標題          // 自動產生內容頁
內容…

#focus-slide[全版重點頁]
#ending-slide(title: [Q & A])   // 封底
```

## 卡片與版面（HTML + CSS 心智模型）

| 元件 | 對應概念 | 例子 |
|---|---|---|
| `card(..)[..]` | `div` + box model | `#card(tint: palette.teal, title: [標題], shadow: true)[內容]`；可調 `fill / stroke / radius / inset / width / height` |
| `row(..)[..][..]` | flex row | `#row(widths: (2fr, 1fr), gutter: 1em)[左][右]` |
| `col(..)[..][..]` | flex column | `#col(gap: 1em)[上][下]` |
| `absolute(x:, y:)[..]` | `position: absolute` | 在任何容器內釘死位置 |

`tint:` 給一個主題色就自動算出淡背景、同色系邊框與標題色。

## Code block（VS Code Dark+）

- ` ```python … ``` ` 直接得到暗色圓角面板（配色來自 `dark-plus.tmTheme`）
- 加檔名標題列與行號：

```typst
#code(title: "train.py", numbers: true)[
```python
...
```
]
```

## 其他 helpers

`pill[..]`（膠囊標籤）、`callout(kind: "info"|"tip"|"warn"|"danger", compact: true)[..]`、`stat(值, 標籤)`（KPI 大數字）、`divider(label: [..])`、`quote-card(author: [..])[..]`、`kbd[..]`、`step(n)`（圓形步驟號）。

## 配色

所有顏色都在 `palette` 字典（`lib.typ` 開頭），要換品牌色改那一處即可；`accent-seq` 控制封面/封底的裝飾色帶。
