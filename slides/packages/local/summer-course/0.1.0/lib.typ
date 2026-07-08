// =============================================================================
// summer-course Typst package — 課程共用簡報主題（based on touying）
//
// 設計語言：大量留白、襯線標題 + 無襯線內文、細線分隔、柔和圓角卡片、
// 冷色 Graphite & Iris 配色（非米色系）。
//
// 用法：
//   #import "@local/summer-course:0.1.0": *
//   #show: course-theme.with(
//     config-info(title: [...], subtitle: [...], author: [...], date: datetime.today()),
//   )
//   #title-slide()
//   #outline-slide()
//   = 章節            // 自動產生分隔頁
//   == 頁面標題       // 自動產生內容頁
//   #ending-slide()
// =============================================================================

#import "@preview/touying:0.6.1": *

// =============================================================================
// 1. Design tokens：配色與字型
// =============================================================================

/// Graphite & Iris 配色。可整包 import 使用，如 `palette.iris`。
#let palette = (
  // 基底
  paper: rgb("#F5F6F9"), // 頁面底色：冷調瓷白
  surface: rgb("#FFFFFF"), // 卡片底色
  ink: rgb("#1A1D26"), // 主文字
  ink-soft: rgb("#3D4357"), // 次要文字
  muted: rgb("#6B7186"), // 弱化文字（頁腳、eyebrow）
  line: rgb("#E2E5EC"), // 細線、卡片邊框
  // 主題色
  iris: rgb("#4A57C8"), // 主色：鳶尾靛
  iris-dark: rgb("#343D93"),
  teal: rgb("#0F7E88"), // 輔色：深青
  amber: rgb("#B45309"), // 強調：琥珀
  rose: rgb("#C2495D"), // 強調：玫紅
  green: rgb("#2F855A"), // 語意：成功
  // 深色面
  night: rgb("#14161D"), // 分隔頁 / 封底底色
  night-soft: rgb("#232734"), // 深色面上的卡片
  code-bg: rgb("#1E1E1E"), // VS Code Dark+ 背景
  code-fg: rgb("#D4D4D4"),
)

/// 裝飾用的色彩序列（封面 / 封底的幾何元素、進度點）
#let accent-seq = (palette.iris, palette.teal, palette.amber, palette.rose)

#let font-display = ("Noto Serif", "Noto Serif CJK TC") // 襯線：標題
#let font-sans = ("Noto Sans", "Noto Sans TC", "Liberation Sans") // 無襯線：內文
#let font-mono = ("JetBrainsMono NF", "Noto Sans Mono CJK TC", "DejaVu Sans Mono")

// =============================================================================
// 2. HTML + CSS 心智模型的版面原語
// =============================================================================

/// 卡片：對應 HTML 的 <div> + CSS box model。
///
/// - fill: 背景色（background-color）
/// - stroke: 邊框（border），`auto` 時為 1pt 細線
/// - radius: 圓角（border-radius）
/// - inset: 內距（padding）
/// - width / height: 尺寸
/// - tint: 快捷主題色 —— 給一個顏色自動算出淡背景 + 同色系邊框與標題
/// - title / icon: 卡片頂部的小標題列
/// - shadow: 陰影（box-shadow 的簡化版）
#let card(
  fill: auto,
  stroke: auto,
  radius: 10pt,
  inset: 1em,
  width: 100%,
  height: auto,
  tint: none,
  title: none,
  icon: none,
  title-fill: auto,
  shadow: false,
  align: top + left,
  body,
) = {
  let _fill = fill
  let _stroke = stroke
  let _title-fill = title-fill
  if tint != none {
    if _fill == auto { _fill = tint.lighten(93%) }
    if _stroke == auto { _stroke = 0.8pt + tint.lighten(55%) }
    if _title-fill == auto { _title-fill = tint.darken(15%) }
  }
  if _fill == auto { _fill = palette.surface }
  if _stroke == auto { _stroke = 1pt + palette.line }
  if _title-fill == auto { _title-fill = palette.ink }

  let inner = block(
    fill: _fill,
    stroke: _stroke,
    radius: radius,
    inset: inset,
    width: width,
    height: height,
    breakable: false,
    std.align(align, {
      if title != none {
        block(below: 0.7em, text(
          size: 0.78em,
          weight: "bold",
          fill: _title-fill,
          tracking: 0.4pt,
          if icon != none { icon + h(0.45em) } + title,
        ))
      }
      body
    }),
  )

  if shadow {
    layout(bounds => {
      let size = measure(width: bounds.width, height: bounds.height, inner)
      box(width: size.width, height: size.height, {
        place(top + left, dx: 0pt, dy: 3.5pt, block(
          width: size.width,
          height: size.height,
          radius: radius,
          fill: palette.ink.transparentize(90%),
        ))
        place(top + left, inner)
      })
    })
  } else {
    inner
  }
}

/// 水平排版：對應 CSS 的 flex row / grid。
///
/// - widths: `auto` 時每欄均分（1fr），或傳 `(1fr, 2fr)` 這種比例
/// - gutter: 欄距（gap）
/// - align: 各欄對齊
///
/// 例：`#row(widths: (2fr, 1fr))[左邊][右邊]`
#let row(widths: auto, gutter: 0.9em, align: top, ..cells) = {
  let items = cells.pos()
  let cols = if widths == auto { (1fr,) * items.len() } else { widths }
  grid(columns: cols, column-gutter: gutter, align: align, ..items)
}

/// 垂直排版：對應 CSS 的 flex column。`#col(gap: 1em)[a][b][c]`
#let col(gap: 0.8em, ..items) = stack(dir: ttb, spacing: gap, ..items.pos())

/// 絕對定位：對應 CSS 的 `position: absolute`。
/// x / y 為相對目前容器左上角的位移，w 可限制寬度。
#let absolute(x: 0pt, y: 0pt, w: auto, body) = place(
  top + left,
  dx: x,
  dy: y,
  block(width: w, body),
)

/// 彈性留白：對應 CSS 的 `margin: auto` / spacer。
#let spacer = h(1fr)

// =============================================================================
// 3. UI helpers
// =============================================================================

/// 圓角膠囊標籤（badge / chip）。`#pill[NEW]`、`#pill(tint: palette.rose)[重點]`
#let pill(tint: palette.iris, size: 0.62em, body) = box(
  fill: tint.lighten(88%),
  stroke: 0.6pt + tint.lighten(50%),
  radius: 99pt,
  inset: (x: 0.75em, y: 0.38em),
  baseline: 0.32em,
  text(size: size, weight: "bold", fill: tint.darken(18%), tracking: 0.6pt, body),
)

/// 語意提示框（callout）。kind: "info" | "tip" | "warn" | "danger"
#let callout(kind: "info", title: auto, compact: false, body) = {
  let spec = (
    info: (tint: palette.iris, icon: [🛈], name: [Info]),
    tip: (tint: palette.green, icon: [✓], name: [Tip]),
    warn: (tint: palette.amber, icon: [⚠], name: [注意]),
    danger: (tint: palette.rose, icon: [✕], name: [危險]),
  ).at(kind)
  let _title = if title == auto { spec.name } else { title }
  block(
    width: 100%,
    fill: spec.tint.lighten(93%),
    stroke: (left: 3pt + spec.tint),
    radius: (right: 8pt),
    inset: if compact { (x: 0.9em, y: 0.6em) } else { 1em },
    breakable: false,
    {
      if _title != none {
        block(below: 0.55em, text(
          size: 0.78em,
          weight: "bold",
          fill: spec.tint.darken(15%),
          spec.icon + h(0.45em) + _title,
        ))
      }
      body
    },
  )
}

/// 大數字統計（KPI tile）。`#stat([87%], [測試通過率])`
#let stat(value, label, tint: palette.iris) = std.align(center, {
  text(font: font-display, size: 2.1em, weight: "bold", fill: tint, value)
  v(0.15em, weak: true)
  text(size: 0.68em, fill: palette.muted, tracking: 0.6pt, label)
})

/// 細分隔線，可帶置中小標。`#divider()` 或 `#divider[或者]`
#let divider(label: none, tint: palette.line) = if label == none {
  line(length: 100%, stroke: 0.6pt + tint)
} else {
  grid(
    columns: (1fr, auto, 1fr),
    column-gutter: 0.8em,
    align: horizon,
    line(length: 100%, stroke: 0.6pt + tint),
    text(size: 0.65em, fill: palette.muted, tracking: 1pt, label),
    line(length: 100%, stroke: 0.6pt + tint),
  )
}

/// 引言卡片。`#quote-card(author: [Alan Kay])[...]`
#let quote-card(author: none, tint: palette.iris, body) = block(
  width: 100%,
  inset: (left: 1.2em, y: 0.4em),
  stroke: (left: 3pt + tint),
  {
    text(font: font-display, size: 1.05em, style: "italic", fill: palette.ink-soft, body)
    if author != none {
      v(0.5em, weak: true)
      text(size: 0.7em, fill: palette.muted, [— ] + author)
    }
  },
)

/// 鍵盤按鍵。`#kbd[Ctrl]`
#let kbd(body) = box(
  fill: palette.surface,
  stroke: 1pt + palette.line,
  radius: 4pt,
  inset: (x: 0.45em, y: 0.25em),
  baseline: 0.25em,
  text(font: font-mono, size: 0.75em, fill: palette.ink-soft, body),
)

/// 步驟編號圓點。`#step(1)` 產生一個圓形序號
#let step(n, tint: palette.iris) = box(
  fill: tint,
  radius: 99pt,
  width: 1.5em,
  height: 1.5em,
  baseline: 0.4em,
  std.align(center + horizon, text(size: 0.75em, weight: "bold", fill: white, str(n))),
)

// =============================================================================
// 4. Code block（VS Code Dark+）
// =============================================================================

// code() 透過 state 把「檔名標題列 / 行號」的設定傳給全域 raw show rule，
// 避免巢狀 show rule 造成雙重包框。
#let _code-meta = state("course-theme-code-meta", (:))

/// 帶視窗外框的 code block。直接寫 ```lang ...``` 也會套暗色底，
/// 用 `#code(title: "train.py")[...]` 則多一條 macOS 風格的標題列。
///
/// - title: 檔名 / 標題列文字，none 則不顯示標題列
/// - numbers: 是否顯示行號
/// - size: 程式碼字級
#let code(title: none, numbers: false, size: auto, body) = {
  _code-meta.update((title: title, numbers: numbers, size: size))
  body
  _code-meta.update((:))
}

// 實際渲染（由主題的 init 註冊到 show raw）
#let _render-code-block(meta, it) = {
  let title = meta.at("title", default: none)
  let numbers = meta.at("numbers", default: false)
  let size = meta.at("size", default: auto)
  let radius = 9pt

  block(width: 100%, breakable: false, grid(
    columns: 1,
    row-gutter: 0pt,
    if title != none {
      block(
        width: 100%,
        fill: palette.night-soft,
        radius: (top: radius),
        inset: (x: 1em, y: 0.55em),
        {
          for c in (palette.rose, palette.amber, palette.green) {
            box(fill: c, radius: 99pt, width: 0.55em, height: 0.55em)
            h(0.4em)
          }
          h(0.5em)
          text(font: font-mono, size: 0.62em, fill: palette.code-fg.transparentize(25%), title)
        },
      )
    },
    block(
      width: 100%,
      fill: palette.code-bg,
      radius: if title == none { radius } else { (bottom: radius) },
      inset: (x: 1em, y: 0.85em),
      breakable: false,
      {
        set text(size: if size == auto { 0.78em } else { size }, fill: palette.code-fg)
        if numbers {
          set block(spacing: 0.62em)
          show raw.line: l => grid(
            columns: (1.6em, 1fr),
            column-gutter: 0.9em,
            std.align(right, text(fill: palette.code-fg.transparentize(65%), str(l.number))),
            l.body,
          )
          it
        } else {
          it
        }
      },
    ),
  ))
}

// =============================================================================
// 5. 頁面模板
// =============================================================================

// ---- 內容頁 -----------------------------------------------------------------

/// 內容頁。通常由 `== 標題` 自動觸發，也可手動呼叫：
/// `#slide(title: [自訂標題])[...]`
///
/// - title: 頁面標題，`auto` 時取目前 heading
/// - eyebrow: 標題上方的小節名，`auto` 時取目前 level-1 heading
/// - footer / header: 覆寫頁腳 / 頁首
/// - align: 內容對齊（預設 top）
#let slide(
  title: auto,
  eyebrow: auto,
  header: auto,
  footer: auto,
  align: auto,
  config: (:),
  repeat: auto,
  setting: body => body,
  composer: auto,
  ..bodies,
) = touying-slide-wrapper(self => {
  if title != auto { self.store.title = title }
  if eyebrow != auto { self.store.eyebrow = eyebrow }
  if header != auto { self.store.header = header }
  if footer != auto { self.store.footer = footer }
  if align != auto { self.store.align = align }
  let new-setting = body => {
    show: std.align.with(self.store.align)
    show: setting
    body
  }
  touying-slide(self: self, config: config, repeat: repeat, setting: new-setting, composer: composer, ..bodies)
})

// ---- 封面頁 -----------------------------------------------------------------

/// 封面頁。資訊來自 `config-info`，也可直接傳參覆寫：
/// `#title-slide(subtitle: [...])`
#let title-slide(config: (:), ..args) = touying-slide-wrapper(self => {
  self = utils.merge-dicts(
    self,
    config,
    config-common(freeze-slide-counter: true),
    config-page(fill: palette.paper, header: none, footer: none, margin: 0em),
  )
  let info = self.info + args.named()
  let body = {
    set text(fill: palette.ink)
    // 頂部光譜色帶
    place(top, block(width: 100%, height: 5pt, fill: gradient.linear(..accent-seq)))
    // 右下幾何裝飾
    place(bottom + right, dx: -2.2em, dy: -2.2em, {
      let sq(c, s) = box(fill: c, radius: 26%, width: s, height: s)
      stack(
        dir: ltr,
        spacing: 0.5em,
        move(dy: 1.6em, sq(palette.rose.lighten(20%), 1.1em)),
        move(dy: 0.8em, sq(palette.amber.lighten(10%), 1.6em)),
        move(dy: 0.2em, sq(palette.teal, 2.2em)),
        sq(palette.iris, 3em),
      )
    })
    // 主要文字區
    block(width: 100%, height: 100%, inset: (x: 3.2em, y: 2.6em), {
      set std.align(left)
      if info.at("institution", default: none) != none {
        pill(size: 0.55em, upper(info.institution))
      }
      v(1fr)
      block(text(font: font-display, size: 2.5em, weight: "bold", info.title))
      if info.at("subtitle", default: none) != none {
        v(0.9em, weak: true)
        block(text(size: 1.05em, fill: palette.ink-soft, info.subtitle))
      }
      v(1.4em, weak: true)
      line(length: 5em, stroke: 2.5pt + palette.iris)
      v(1fr)
      set text(size: 0.75em, fill: palette.muted)
      let meta = ()
      if info.at("author", default: none) != none { meta.push([#info.author]) }
      if info.at("date", default: none) != none { meta.push(utils.display-info-date(self)) }
      meta.join([#h(0.8em) · #h(0.8em)])
    })
  }
  touying-slide(self: self, body)
})

// ---- 目錄頁 -----------------------------------------------------------------

/// 目錄頁：列出所有 level-1 章節，超過 5 個自動分兩欄。
#let outline-slide(title: [目錄], config: (:), columns: auto) = touying-slide-wrapper(self => {
  self = utils.merge-dicts(
    self,
    config,
    config-page(fill: palette.paper, header: none, margin: (x: 3.2em, top: 2.6em, bottom: 2.4em)),
  )
  self.store.title = none
  let body = {
    text(size: 0.6em, fill: palette.muted, tracking: 2pt, upper[Contents])
    v(0.3em)
    text(font: font-display, size: 1.7em, weight: "bold", title)
    v(0.4em)
    line(length: 3.5em, stroke: 2.5pt + palette.iris)
    v(1.3em)
    context {
      let secs = query(heading.where(level: 1, outlined: true))
      let n-cols = if columns == auto { if secs.len() > 5 { 2 } else { 1 } } else { columns }
      let entry(i, sec) = link(sec.location(), grid(
        columns: (auto, 1fr),
        column-gutter: 0.9em,
        align: horizon,
        text(font: font-display, size: 1.05em, weight: "bold", fill: palette.iris, numbering("01", i + 1)),
        text(fill: palette.ink, sec.body),
      ))
      grid(
        columns: (1fr,) * n-cols,
        column-gutter: 2.5em,
        row-gutter: 1.05em,
        ..secs.enumerate().map(((i, sec)) => entry(i, sec)),
      )
    }
  }
  touying-slide(self: self, body)
})

// ---- 分隔頁 -----------------------------------------------------------------

/// 章節分隔頁：由 `= 章節` 自動觸發（深色底 + 大章節號）。
#let new-section-slide(config: (:), level: 1, body) = touying-slide-wrapper(self => {
  self = utils.merge-dicts(
    self,
    config,
    config-page(fill: palette.night, header: none, footer: none, margin: 0em),
  )
  self.store.title = none
  let content = {
    set text(fill: white)
    place(top, block(width: 100%, height: 5pt, fill: gradient.linear(..accent-seq)))
    // 右側大章節號（淡化）
    context {
      let past = query(selector(heading.where(level: 1, outlined: true)).before(here(), inclusive: true))
      let all = query(heading.where(level: 1, outlined: true))
      let n = calc.max(past.len(), 1)
      place(right + horizon, dx: -0.4em, text(
        font: font-display,
        size: 17em,
        weight: "bold",
        fill: white.transparentize(93%),
        numbering("01", n),
      ))
      block(width: 100%, height: 100%, inset: (x: 3.2em), {
        set std.align(left + horizon)
        text(size: 0.62em, fill: white.transparentize(45%), tracking: 2.5pt, upper[Section #numbering("01", n)])
        v(0.5em)
        text(font: font-display, size: 2.1em, weight: "bold", utils.display-current-heading(level: level))
        v(1em)
        // 章節進度點
        for i in range(all.len()) {
          box(
            fill: if i + 1 == n { palette.iris.lighten(20%) } else { white.transparentize(80%) },
            radius: 99pt,
            width: if i + 1 == n { 1.6em } else { 0.5em },
            height: 0.5em,
          )
          h(0.45em)
        }
      })
    }
  }
  touying-slide(self: self, content)
})

// ---- 重點頁 -----------------------------------------------------------------

/// 全版重點頁：`#focus-slide[一句話重點]`
#let focus-slide(config: (:), fill: palette.iris-dark, align: horizon + center, body) = touying-slide-wrapper(self => {
  self = utils.merge-dicts(
    self,
    config,
    config-common(freeze-slide-counter: true),
    config-page(fill: fill, header: none, footer: none, margin: 2.5em),
  )
  set text(fill: white, font: font-display, weight: "bold", size: 1.7em)
  touying-slide(self: self, std.align(align, body))
})

// ---- 封底頁 -----------------------------------------------------------------

/// 封底頁：`#ending-slide()` 或 `#ending-slide(title: [Q & A])[聯絡方式]`
#let ending-slide(config: (:), title: [Thanks!], ..args) = touying-slide-wrapper(self => {
  self = utils.merge-dicts(
    self,
    config,
    config-common(freeze-slide-counter: true),
    config-page(fill: palette.night, header: none, footer: none, margin: 0em),
  )
  let info = self.info + args.named()
  let extra = args.pos().at(0, default: none)
  let body = {
    set text(fill: white)
    place(bottom, block(width: 100%, height: 5pt, fill: gradient.linear(..accent-seq)))
    place(top + right, dx: -2.2em, dy: 2.2em, {
      let sq(c, s) = box(fill: c, radius: 26%, width: s, height: s)
      stack(dir: ltr, spacing: 0.5em, move(dy: 0.9em, sq(palette.teal, 1.3em)), sq(palette.iris, 2em))
    })
    block(width: 100%, height: 100%, inset: (x: 3.2em, y: 2.6em), {
      set std.align(left + horizon)
      text(font: font-display, size: 2.6em, weight: "bold", title)
      v(1em)
      line(length: 5em, stroke: 2.5pt + palette.iris.lighten(20%))
      v(1em)
      set text(size: 0.8em, fill: white.transparentize(30%))
      if extra != none { extra } else {
        let meta = ()
        if info.at("author", default: none) != none { meta.push([#info.author]) }
        if info.at("institution", default: none) != none { meta.push([#info.institution]) }
        meta.join([ · ])
      }
    })
  }
  touying-slide(self: self, body)
})

// =============================================================================
// 6. 主題入口
// =============================================================================

/// 課程簡報主題。
///
/// - aspect-ratio: 長寬比，預設 16-9
/// - progress-bar: 頁腳是否顯示進度條
/// - footer-left: 頁腳左側內容，`auto` 時顯示 short-title / title
#let course-theme(
  aspect-ratio: "16-9",
  align: top,
  progress-bar: true,
  footer-left: auto,
  ..args,
  body,
) = {
  let header(self) = {
    set std.align(top)
    block(width: 100%, inset: (top: 1.5em, x: 2.4em), {
      set text(fill: palette.ink)
      let eyebrow = if self.store.eyebrow != none { utils.call-or-display(self, self.store.eyebrow) }
      let title = if self.store.title != none { utils.call-or-display(self, self.store.title) }
      if eyebrow != none {
        block(below: 0.5em, text(
          size: 0.52em,
          fill: palette.muted,
          tracking: 1.8pt,
          upper(eyebrow),
        ))
      }
      if title != none {
        grid(
          columns: (auto, 1fr),
          column-gutter: 0.55em,
          align: horizon,
          box(fill: palette.iris, radius: 2pt, width: 0.28em, height: 1.15em),
          text(font: font-display, size: 1.25em, weight: "bold", title),
        )
      }
    })
  }
  let footer(self) = {
    set std.align(bottom)
    set text(size: 0.48em, fill: palette.muted)
    grid(
      rows: (auto, auto),
      row-gutter: 0.7em,
      block(width: 100%, inset: (x: 2.4em), {
        utils.call-or-display(self, self.store.footer-left)
        h(1fr)
        context utils.slide-counter.display() + " / " + utils.last-slide-number
      }),
      if self.store.progress-bar {
        components.progress-bar(height: 2.5pt, palette.iris, palette.line)
      } else {
        v(2.5pt)
      },
    )
  }

  show: touying-slides.with(
    config-page(
      paper: "presentation-" + aspect-ratio,
      fill: palette.paper,
      header: header,
      footer: footer,
      header-ascent: 0em,
      footer-descent: 0em,
      margin: (top: 4.6em, bottom: 2.2em, x: 2.4em),
    ),
    config-common(
      slide-fn: slide,
      new-section-slide-fn: new-section-slide,
      slide-level: 2,
    ),
    config-methods(
      alert: (self: none, it) => text(fill: palette.iris, weight: "bold", it),
      init: (self: none, body) => {
        set text(font: font-sans, size: 19pt, fill: palette.ink, lang: "zh", region: "TW")
        set par(leading: 0.7em, spacing: 1.1em)
        set list(marker: (
          box(fill: palette.iris, radius: 1.2pt, width: 0.4em, height: 0.4em, baseline: -0.12em),
          box(stroke: 1pt + palette.iris, radius: 1.2pt, width: 0.34em, height: 0.34em, baseline: -0.12em),
        ), indent: 0.3em)
        set enum(numbering: n => text(fill: palette.iris, weight: "bold", str(n) + "."), indent: 0.3em)
        show heading: set text(font: font-display, fill: palette.ink)
        show heading.where(level: 3): it => block(
          above: 1em,
          below: 0.6em,
          text(size: 0.85em, fill: palette.ink-soft, it.body),
        )
        show link: it => if type(it.dest) == str {
          text(fill: palette.teal, underline(offset: 2.5pt, stroke: 0.6pt + palette.teal.lighten(50%), it))
        } else { it }
        show emph: set text(fill: palette.ink-soft)
        show figure.caption: set text(size: 0.62em, fill: palette.muted)
        show footnote.entry: set text(size: 0.6em)
        // 表格：無縱線、首列粗底線
        set table(
          stroke: (x, y) => (
            bottom: if y == 0 { 1.2pt + palette.ink-soft } else { 0.5pt + palette.line },
          ),
          inset: (x: 0.7em, y: 0.55em),
        )
        show table.cell.where(y: 0): set text(weight: "bold", size: 0.82em)
        // Code：VS Code Dark+
        set raw(theme: "dark-plus.tmTheme")
        show raw: set text(font: font-mono)
        show raw.where(block: false): it => box(
          fill: palette.line.lighten(35%),
          stroke: 0.5pt + palette.line,
          radius: 4pt,
          inset: (x: 0.35em),
          outset: (y: 0.3em),
          text(fill: palette.iris-dark, size: 0.92em, it),
        )
        show raw.where(block: true): it => context {
          _render-code-block(_code-meta.get(), it)
        }
        body
      },
    ),
    config-colors(
      primary: palette.iris,
      primary-dark: palette.iris-dark,
      secondary: palette.teal,
      tertiary: palette.amber,
      neutral-lightest: palette.paper,
      neutral-darkest: palette.ink,
    ),
    config-store(
      align: align,
      progress-bar: progress-bar,
      title: self => utils.display-current-heading(depth: self.slide-level),
      eyebrow: self => utils.display-current-heading(level: 1),
      footer-left: if footer-left == auto {
        self => if self.info.short-title == auto { self.info.title } else { self.info.short-title }
      } else { footer-left },
      header: none,
      footer: none,
    ),
    ..args,
  )

  body
}
