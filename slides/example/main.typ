#import "@local/summer-course:0.1.0": *

#show: course-theme.with(
  config-info(
    title: [具身智慧暑期課程],
    subtitle: [從行為複製到視覺表徵 —— 動手打造你的第一個機器人學習系統],
    author: [螺旋升天奇異鳥],
    institution: [Summer Course],
    short-title: [具身智慧暑期課程],
  ),
)

#title-slide()

#outline-slide()

= 課程概覽

== 這門課在做什麼

這門課帶你從零打造一個 *機器人學習系統*，中間會經過 `dataset`、`policy`、`deployment` 三個階段。

#v(0.5em)

#row(
  card(tint: palette.iris, title: [Week 1–2], icon: [📦])[
    資料收集與行為複製，理解 *示範資料* 的價值與陷阱。
  ],
  card(tint: palette.teal, title: [Week 3–4], icon: [🧠])[
    視覺表徵學習，讓 policy 看得懂世界。
  ],
  card(tint: palette.amber, title: [Week 5–6], icon: [🤖])[
    部署到 AMR，處理真實世界的 entangled 複雜度。
  ],
)

#v(0.6em)
#callout(kind: "tip")[每週的 lab 都建立在前一週之上，跟不上請立刻找助教。]

#speaker-note[
  test
]

== 卡片系統：像寫 CSS 一樣調整

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(title: [預設卡片])[
    `fill` / `stroke` / `radius` / `inset` / `width` 全部可調，
    心智模型就是 HTML 的 `div` + CSS box model。
  ]
  #v(0.8em)
  #card(tint: palette.rose, title: [Tint 快捷], shadow: true)[
    給一個 `tint` 顏色，自動算出淡背景、同色系邊框與標題色，這張還開了 `shadow: true`。
  ]
][
  #card(fill: palette.night, stroke: none, radius: 14pt, inset: 1.3em, title: [自訂樣式], title-fill: white)[
    #set text(fill: white.transparentize(20%), size: 0.85em)
    深色卡片：`fill: palette.night`、`stroke: none`、`radius: 14pt`。
    #v(0.5em)
    #pill(tint: palette.teal)[PILL] #pill(tint: palette.amber)[BADGE] #kbd[Ctrl] + #kbd[C]
  ]
]

== 版面原語：row / col / absolute

#row(widths: (2fr, 1fr), gutter: 1.2em)[
  `#row(widths: (2fr, 1fr))` 就是 flex row，`#col` 是 flex column，
  `#absolute(x:, y:)` 對應 `position: absolute` —— 右邊那顆方塊就是這樣釘上去的。

  #v(0.6em)
  #row(
    stat([12], [週課程]),
    stat([4], [實體 Lab], tint: palette.teal),
    stat([87%], [完課率], tint: palette.amber),
  )
][
  #card(height: 9em, title: [容器])[
    #absolute(x: 4.5em, y: 3em, w: 6em)[
      #card(tint: palette.iris, inset: 0.6em, width: auto)[#text(size: 0.7em)[absolute!]]
    ]
  ]
]

#v(0.6em)
#divider(label: [其他 HELPERS])
#v(0.4em)

#quote-card(author: [Alan Kay])[The best way to predict the future is to invent it.]

= Code Block

== 暗色 VS Code 風格

行內程式碼像 `rclpy.init()` 這樣呈現，區塊則是 Dark+ 配色：

```python
import numpy as np

class PolicyRunner:
    """Behavior cloning policy runner."""

    def __init__(self, ckpt: str, rate_hz: float = 30.0):
        self.model = load_checkpoint(ckpt)  # 載入權重
        self.rate = rate_hz

    def act(self, obs) -> np.ndarray:
        feat = self.model.encode(obs["rgb"])
        return self.model.decode(feat)
```

== 帶檔名與行號的 code 卡片

#code(title: "launch/nav.launch.py", numbers: true)[
  ```python
  from launch import LaunchDescription
  from launch_ros.actions import Node

  def generate_launch_description():
      return LaunchDescription([
          Node(package="nav2_bringup", executable="bringup_launch"),
          Node(package="amr_demo", executable="policy_node",
               parameters=[{"rate_hz": 30.0}]),
      ])
  ```
]

#v(0.5em)
#callout(kind: "warn", compact: true)[`rate_hz` 設太高會讓 CPU 吃滿，部署前先跑 `week4.5` 的診斷 lab。]

= 語意元件

== Callout 四連發

#callout(kind: "info", compact: true)[一般資訊：作業繳交統一走 GitHub Classroom。]
#v(0.4em)
#callout(kind: "tip", compact: true)[小技巧：`docker compose up` 之前先確認 `.env` 存在。]
#v(0.4em)
#callout(kind: "warn", compact: true)[注意：實機操作前務必先在模擬器驗證。]
#v(0.4em)
#callout(kind: "danger", compact: true)[危險：不要在電池低於 20% 時 flash 韌體。]

== 表格與步驟

#row(widths: (3fr, 2fr), gutter: 1.5em)[
  #table(
    columns: (auto, 1fr, auto),
    [週次], [主題], [Lab],
    [W2], [Sequence Behavior Cloning], [✅],
    [W2], [Vision Representation], [✅],
    [W4.5], [TF Diagnostics], [✅],
  )
][
  #step(1) 先讀 README

  #v(0.5em)
  #step(2) 跑通 baseline

  #v(0.5em)
  #step(3) 完成 TODO 清單
]

#focus-slide[先讓它動起來，再讓它變聰明。]

#ending-slide(title: [Q & A])
