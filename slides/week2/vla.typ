#import "@local/summer-course:0.1.0": *
#import "@preview/cetz:0.4.2": canvas, draw

#show: course-theme.with(
  config-info(
    title: [From Behavior Cloning to VLA],
    subtitle: [Week 2 · 模型、梯度、序列與多模態，看懂一個 VLA policy 的骨架],
    author: [獵奇緯],
    institution: [Summer Course],
    short-title: [Week 2 · From BC to VLA],
  ),
)

#title-slide()
#outline-slide()

= 課程地圖

== 你要能看懂什麼

#quote-card(tint: palette.iris)[一個 VLA policy 的骨架：\
  資料流、loss、token、attention、mask、encoder、decoder 各自扮演什麼角色。]

#v(0.5em)
#row(gutter: .7em)[
  #card(tint: palette.iris, title: [Vision], icon: [👁])[影像 → tokens · vision encoder]
][
  #card(tint: palette.teal, title: [Language], icon: [💬])[指令 → tokens · language encoder]
][
  #card(tint: palette.amber, title: [Action], icon: [🦾])[歷史 → 下一步 · action decoder]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[
  V + L + A 三條輸入，最後融合成一個 policy。這就是 VLA 的全名：Vision-Language-Action。
]

#speaker-note[
  今天的目標只有一個：要能看懂一個 VLA policy 的骨架，知道裡面的資料流、loss、token、attention、mask、vision encoder、language encoder、action decoder 各自扮演什麼角色。

  先講先備知識。這門課只假設你看過線性代數、機率、微積分；不假設你已經會 deep learning。線代會一直出現，尤其是矩陣乘法、向量內積、線性變換。機率只需要條件機率、機率分布和「機率加起來是 1」這些最小工具。微積分只需要一個核心直覺：斜率告訴你往哪裡改，數值會變大或變小。
]

== 依賴圖

#row(widths: (1.15fr, 1fr), gutter: 1.2em)[
  #card(title: [概念依賴鏈], icon: [🗺])[
    #set text(size: 0.72em)
    #pill(tint: palette.iris)[模型是函數] → #pill(tint: palette.iris)[loss 衡量錯誤] → #pill(tint: palette.iris)[gradient 調參數]\
    #v(.35em)
    → #pill(tint: palette.teal)[supervised learning] → #pill(tint: palette.teal)[behavior cloning]\
    #v(.35em)
    → #pill(tint: palette.amber)[tokenization] → #pill(tint: palette.amber)[sequence model] → #pill(tint: palette.amber)[attention]\
    #v(.35em)
    → #pill(tint: palette.rose)[vision encoder] → #pill(tint: palette.rose)[pretraining] → #pill(tint: palette.rose)[VLA]
  ]
][
  #card(tint: palette.teal, title: [今天的分段], icon: [✅])[
    #set text(size: 0.82em)
    #step(0, tint: palette.iris) BC 是什麼問題\
    #v(.3em)
    #step(1, tint: palette.iris) supervised learning 骨架\
    #v(.3em)
    #step(2, tint: palette.amber) 序列化 BC\
    #v(.3em)
    #step(3, tint: palette.rose) 視覺表示\
    #v(.3em)
    #step(4, tint: palette.rose) VLA-shaped BC\
    #v(.3em)
    #step(5, tint: palette.night) 真實系統定位
  ]
]

#speaker-note[
  今天的路線這樣走。先打地基：模型只是函數，loss 衡量錯誤，gradient 告訴我們往哪裡調參數，這三塊合起來就是 supervised learning，而 behavior cloning 不過是把它用在 state 到 action 的配對上。地基打完處理時間：tokenization 把動作變成模型能吃的符號，sequence model 用過去預測下一步，attention 讓每一步能回頭讀上下文。再處理感知：vision encoder 把影像變成 representation，pretraining 把通用的視覺和語言知識帶進來。最後全部接起來，把 vision、language、action history 融合成一個 policy，就是 VLA。

  右邊是今天的分段，跟左邊這條鏈一一對應。每走完一段，我們會回到這張圖把對應的格子打勾，迷路的時候就回來看這一頁。
]

= Part 0 · Behavior Cloning 是什麼問題

== 一批示範資料

#align(center)[
  #text(size: 1.35em)[$D = { (s_i, a_i) }_(i=1)^N$]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [s_i · state], icon: [🌍])[
    當時 *世界長什麼樣*：\
    相機影像、關節角度、紅綠燈的顏色……
  ]
][
  #card(tint: palette.teal, title: [a_i · action], icon: [🖐])[
    demonstrator *在那個 state 下做的動作*：\
    方向盤角度、滑鼠座標、手臂位移……
  ]
]
#v(.6em)
#callout(
  kind: "info",
  compact: true,
)[Behavior cloning 要學一個 policy：看到 *相似 state* 時，做出跟 demonstrator *相似的 action*。]

#speaker-note[
  假設我們有一批示範資料：

  ```text
  D = {(s_i, a_i)}_{i=1}^N
  ```

  `s_i` 是 state，代表當時世界長什麼樣；`a_i` 是 demonstrator 在那個 state 下做的 action。

  behavior cloning 要學一個 policy：看到相似 state 時，做出跟 demonstrator 相似的 action。就這麼一句話。今天所有的模型，不管長得多複雜，都是在解這一句話。
]

== 兩種 policy 寫法

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [action 是連續值], icon: [📐])[
    滑鼠座標、手臂末端位置
    #v(.4em)
    #align(center)[#text(size: 1.25em)[$f_theta (s) = hat(a)$]]
    #v(.4em)
    直接輸出一個 *數值*
  ]
][
  #card(tint: palette.iris, title: [action 是離散選項], icon: [🔢])[
    「下一個 action token 是哪一類」
    #v(.4em)
    #align(center)[#text(size: 1.25em)[$pi_theta (a | s)$]]
    #v(.4em)
    輸出「給定 state 之後，*每個 action 的機率*」
  ]
]
#v(.6em)
#callout(
  kind: "tip",
  compact: true,
)[這兩種形式今天都會用到：Part 1 的迴歸 vs 分類、Part 5 的 ACT vs RT-2，分野就從這裡開始。]

#speaker-note[
  如果 action 是連續值，例如滑鼠座標、機械手臂末端位置，我們可以寫成 `f_θ(s) = a_hat`：一個函數，輸入 state、輸出一個數值。

  如果 action 是離散選項，例如「下一個 action token 是哪一類」，我們寫成 `π_θ(a | s)`。它代表著「給定 state 之後，每個 action 的機率是多少？」

  這兩種寫法的分野會貫穿今天全場：迴歸還是分類、MSE 還是 cross-entropy、直接回歸 action 還是預測 action token，最後 Part 5 講 ACT 跟 RT-2 的差別，根子也在這一頁。
]

== 條件機率

#row(widths: (1.2fr, 1fr), gutter: 1.2em)[
  #table(
    columns: (auto, 1fr, 1fr),
    [state], [P(踩煞車 | s)], [P(踩油門 | s)],
    [🔴 紅燈], [*0.95*], [0.05],
    [🟢 綠燈], [0.10], [*0.90*],
  )
][
  #card(tint: palette.iris, title: [讀表規則])[
    #set text(size: 0.85em)
    - 每個 state 一列
    - 同一列對所有 action *加總為 1*
    - $pi_theta$ 跟這張表是 *同一個數學物件*
  ]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[真實機器人的 state 空間太大、甚至連續，表格枚舉不了，所以改用一個帶參數 θ 的 *函數*：輸入 state、輸出那一列機率。]

#speaker-note[
  上一頁的 `π_θ(a | s)` 值得單獨停一頁，因為「給定 state 之後每個 action 的機率」這句話，說穿了就是條件機率，但條件機率分布具體長什麼樣？用紅綠燈做一張最小條件機率表。state 是紅燈時，踩煞車的機率 0.95、踩油門 0.05；state 是綠燈時，踩煞車 0.10、踩油門 0.90。

  state 和 action 都是有限離散時，條件機率分布完整地就是一張表：每個 state 一列，同一列對所有 action 加總為 1。`π_θ` 跟這張表是同一個數學物件，差別只在表示方式：真實機器人的 state 空間太大、甚至是連續的，表格枚舉不了，所以改用一個帶參數 θ 的函數，輸入 state、輸出那一列機率。

  這是今天第一個重要的心智轉換：神經網路不是什麼神祕的東西，它就是「一張大到寫不下來的表」的函數化替身。
]

== θ：模型裡所有可訓練的旋鈕

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [小模型], icon: [📻])[
    像 *收音機*\
    只有幾顆旋鈕
  ]
][
  #card(tint: palette.iris, title: [大模型], icon: [🎛])[
    像 *錄音室控制台*\
    有幾十億顆旋鈕
  ]
]
#v(.7em)
#quote-card(tint: palette.amber)[機器再大，「根據錯誤把旋鈕轉到比較好的位置」這件事沒有變。]

#speaker-note[
  剛剛說表格枚舉不了，改用「帶參數 θ 的函數」，那 θ 到底是什麼？θ 是模型裡所有可訓練參數。小模型像收音機，只有幾顆旋鈕；大模型像錄音室控制台，有幾十億顆旋鈕。機器再大，「根據錯誤把旋鈕轉到比較好的位置」這件事沒有變。

  這句話值得停一下。等一下我們會手算一顆旋鈕的模型，最後會講到 7B 參數的 OpenVLA，中間差了十個數量級，但訓練的原理是同一句話。把這個錨點抓穩，後面看到再大的模型都不會慌。
]

== BC 的訓練目標

老師做了什麼，模型就 *提高那個答案的分數*，或讓輸出 *更接近那個 action*。

#v(.4em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [連續 action · MSE])[
    #align(center)[$L(theta) = 1/N sum_i norm(f_theta (s_i) - a_i)^2$]
    #v(.3em)
    #set text(size: 0.8em)
    預測跟示範的 *距離平方*
  ]
][
  #card(tint: palette.iris, title: [離散 action · NLL])[
    #align(center)[$L(theta) = -1/N sum_i log pi_theta (a_i | s_i)$]
    #v(.3em)
    #set text(size: 0.8em)
    模型給 `a_i` 的機率越高，loss 越小
  ]
]
#v(.5em)
#callout(
  kind: "tip",
  compact: true,
)[第二個式子現在先看精神就好，等 Part 1 講完 softmax 和 cross-entropy，它會變得完全自然。]

#speaker-note[
  BC 的訓練目標很直接：老師做了什麼，模型就提高那個答案的分數，或讓輸出更接近那個 action。

  連續 action 常用 MSE：預測值跟示範值的距離平方，取平均。

  離散 action 常用 negative log likelihood：如果老師做了 `a_i`，模型給 `a_i` 的機率越高，loss 越小。

  第二個式子現在先看精神：等 Part 1 講完 softmax 和 cross-entropy，這個式子會變得完全自然。我們今天會回來看它兩次，每次你都會多懂一層。
]

== BC 不是 RL

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [Reinforcement Learning], icon: [🎰])[
    agent 透過 *reward、trial and error、\
    policy improvement* 學策略
    #v(.3em)
    #set text(size: 0.8em)
    沒有人告訴你正確答案，只有分數
  ]
][
  #card(tint: palette.teal, title: [Behavior Cloning], icon: [📖])[
    就是 *supervised learning*：\
    每筆資料直接告訴模型「老師做了什麼」
    #v(.3em)
    #set text(size: 0.8em)
    答案已經在資料裡
  ]
]
#v(.6em)
#callout(
  kind: "info",
  compact: true,
)[很多 VLA 的第一階段訓練就是大規模 BC，之後才可能接 RL fine-tuning、preference optimization、真機修正或安全約束。]

#speaker-note[
  離開 Part 0 之前，還有一個界碑要立好：BC 跟 reinforcement learning 的分野。很多人一聽到「機器人自己學會動作」，直覺想到的就是 RL，但兩者拿到的資料完全不同。RL 是 agent 透過 reward、trial and error、policy improvement 學策略，沒有人告訴它正確答案，它只拿得到分數。BC 則是 supervised learning：資料裡已經有示範 action，每筆資料都直接告訴模型「這裡老師做了什麼」。

  很多 VLA 的第一階段訓練就是大規模 BC，先把人類或機器人示範裡的行為模式學起來，之後才可能接 RL fine-tuning、preference optimization、真機修正或安全約束。所以今天整場的主線都是 BC，它是地基，Part 5 會再回來講地基之上還有什麼。
]

= Part 1 · 最小 Supervised Learning 骨架

== Lab 1：企鵝的迴歸與分類

#row(widths: (1.2fr, 1fr), gutter: 1.2em)[
  #card(tint: palette.iris, title: [basic_regression_classification], icon: [🐧])[
    資料：*Palmer Penguins*
    #v(.3em)
    #set text(size: 0.85em)
    - 輸入：嘴喙長度、嘴喙深度、鰭長等量測值
    - 輸出：species（分類）或體重（迴歸）
  ]
][
  #card(tint: palette.teal, title: [這份 lab 只考慮一件事])[
    #v(.2em)
    #align(center)[
      #pill(tint: palette.teal)[feature vector 進] \ #v(.2em) #text(size: 1.2em)[↓] \ #v(.2em)
      #pill(tint: palette.amber)[一個答案出]
    ]
  ]
]
#v(.5em)
#callout(kind: "info", compact: true)[還沒有序列、沒有影像、沒有語言，只是把「單步輸入到輸出」的骨架搭穩。]

#speaker-note[
  Part 0 的結論是：BC 就是 supervised learning。所以在碰任何機器人資料之前，先把 supervised learning 的最小骨架搭穩，而且刻意挑一個跟機器人毫無關係、簡單到不會分心的資料集。第一個 lab 是 `basic_regression_classification`。資料是 Palmer Penguins：輸入企鵝的嘴喙長度、嘴喙深度、鰭長等量測值，預測 species 或體重。

  這份 lab 只考慮一件事：一筆 feature vector 輸入進來，輸出一個答案出去。沒有序列、沒有影像、沒有語言。很多人急著跳到 Transformer，但單步輸入到輸出這個骨架沒搭穩，後面每一層都會晃。
]

== 線性模型：一次矩陣乘法

#align(center)[
  #text(size: 1.5em)[$hat(y) = W x + b$]
]
#v(.5em)
#row(gutter: .7em)[
  #card(tint: palette.teal, title: [x])[feature vector\
    輸入的量測值]
][
  #card(tint: palette.iris, title: [W])[矩陣\
    模型的主要參數]
][
  #card(tint: palette.amber, title: [b])[bias\
    平移項]
]
#v(.5em)
#callout(kind: "info", compact: true)[嚴格說這是 *affine map*：線性變換加一個平移......習慣上大家仍叫它線性模型。]

#speaker-note[
  最簡單的模型是線性函數：y_hat 等於 W 乘 x 加 b。`x` 是 feature vector，`W` 是矩陣，`b` 是 bias。嚴格說這是 affine map：線性變換加一個平移；習慣上大家仍叫它線性模型。

  不要小看這一行。今天後面每一個「層」，MLP 的每一層、attention 的 Q/K/V 投影、embedding 查表，拆到底全部都是這一行。接下來手算一次，讓它從符號變成肌肉記憶。
]

== 手算一次 forward pass

#row(widths: (1fr, 1.25fr), gutter: 1.1em)[
  #card(tint: palette.teal, title: [輸入與參數])[
    #set text(size: 0.8em)
    $x = ["嘴喙長", "嘴喙深"] = [45, 15]$
    #v(.3em)
    $W = mat(0.20, -0.10; -0.05, 0.30; 0.10, 0.05), quad b = vec(-7.0, -2.0, -5.0)$
  ]
][
  #card(tint: palette.iris, title: [z = Wx + b])[
    #set text(size: 0.8em)
    $z_1 = 0.20 dot 45 - 0.10 dot 15 - 7.0 = bold(0.5)$\
    $z_2 = -0.05 dot 45 + 0.30 dot 15 - 2.0 = 0.25$\
    $z_3 = 0.10 dot 45 + 0.05 dot 15 - 5.0 = 0.25$
    #v(.3em)
    第一類 logit 最大 → 預測 *第一類*
  ]
]
#v(.5em)
#align(center)[
  #pill(tint: palette.iris)[矩陣乘法] #text(size: 1.1em)[→] #pill(tint: palette.teal)[加 bias] #text(size: 1.1em)[→] #pill(tint: palette.amber)[選最大值] #h(1em) = 一次 forward pass
]

#speaker-note[
  手算一次。假設輸入有兩個特徵：嘴喙長度 45、嘴喙深度 15。輸出三個 species 的 logits。

  W 是 3×2 的矩陣，b 是三維向量。算出來 z = [0.5, 0.25, 0.25]。第一類 logit 最大，所以模型預測第一類。

  這就是一次 forward pass：矩陣乘法、加 bias、選最大值。就這樣，沒有魔法。之後不管模型多深，forward pass 都是這種計算一層一層疊起來而已。
]

== W 的每一列是一個模板

#align(center)[
  #text(size: 1.2em)[$z_k = w_k dot x + b_k$, #h(1em) $w_k dot x = norm(w_k) thin norm(x) cos theta$]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [row-as-template])[
    第 $k$ 列 $w_k$ = 第 $k$ 類的 *模板向量*\
    #set text(size: 0.85em)
    norm 相當的前提下，內積大 = 輸入方向跟模板方向 *比較像*
  ]
][
  #card(tint: palette.amber, title: [這個觀念今天出現三次], icon: [🔁])[
    #set text(size: 0.85em)
    #step(1) 線性分類器：class template · 輸入\
    #v(.25em)
    #step(2) CNN：kernel · local patch\
    #v(.25em)
    #step(3) attention：query · key（$Q K^top$）
  ]
]

#speaker-note[
  再看 `W` 的每一列。第 k 列 `w_k` 可以看成第 k 類的模板向量：`z_k = w_k · x + b_k`。

  內積可以寫成 `||w_k|| ||x|| cos θ`，分數同時反映夾角和兩邊的長度；在 norm 相當的前提下比較，內積大就代表輸入方向跟模板方向比較像。

  這個 row-as-template 觀念今天會重複出現三次：線性分類器用內積比輸入跟 class template；CNN 的 kernel 是局部模板；attention 的 QK^T 也是用內積算相似度。把這一個直覺抓穩，今天三分之一的內容就通了。

  不過先不急著往後跳。模板觀點在眼前這個分類器身上，馬上就能榨出一個幾何結論，下一頁就來看。
]

== 決策邊界：一條線、一個超平面

#align(center)[
  兩個模板分數 *打平* 的地方： #text(size: 1.2em)[$(w_1 - w_2) dot x + (b_1 - b_2) = 0$]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [幾何意義])[
    2D 是一條 *線*，高維是 *hyperplane*
    #v(.3em)
    #set text(size: 0.85em)
    線性模型的假設：資料可以被平面切開
  ]
][
  #card(tint: palette.rose, title: [假設的兩面])[
    #set text(size: 0.85em)
    ✓ 假設符合資料：穩、簡單、可解釋\
    #v(.25em)
    ✗ 假設不符合：*它就會卡住*
  ]
]

#speaker-note[
  結論是這個。分類是在比較模板分數：`w_1` 的分數高就判第一類，`w_2` 的分數高就判第二類。那模型「改變主意」的位置在哪？就在兩個模板打成平手的地方。令兩類分數相等、移項，得到 (w_1 - w_2) · x + (b_1 - b_2) = 0，一條關於 x 的線性方程：2D 是一條線，高維就是 hyperplane。決策邊界不是另外設計出來的東西，它是「模板比分」這件事自帶的幾何。

  線性模型的假設：資料可以被平面切開。假設符合資料，它穩、簡單、可解釋；假設不符合，它就會卡住。

  那什麼叫「假設不符合」？下一頁給你一個只有四個點、卻讓線性模型徹底卡死的例子。
]

== XOR：線性模型的天花板

#row(widths: (1fr, 1.3fr), gutter: 1.2em)[
  #table(
    columns: (auto, auto, auto),
    [$x_1$], [$x_2$], [target],
    [0], [0], [0],
    [1], [0], [*1*],
    [0], [1], [*1*],
    [1], [1], [0],
  )
][
  #card(tint: palette.rose, title: [30 秒的挫折], icon: [✏️])[
    在平面上畫這四個點，\
    試著用 *一條直線* 把 0 和 1 分開。
    #v(.4em)
    #align(center)[#text(size: 1.1em, weight: "bold", fill: palette.rose)[畫不出來。]]
    #v(.4em)
    #set text(size: 0.85em)
    對角的兩對點，任何直線都切不開，這就是 MLP 的動機。
  ]
]

#speaker-note[
  先給線性模型一個做不到的任務：XOR。(0,0) 對 0、(1,0) 對 1、(0,1) 對 1、(1,1) 對 0。

  請大家現在真的在紙上畫四個點，試著用一條直線分開 0 和 1。給你們 30 秒。

  畫不出來。對角的兩對點，不管直線怎麼擺都切不開。這 30 秒的挫折就是 MLP 的動機，我們需要讓模型能表示「不是一條直線」的邊界。
]

== MLP：疊層，但關鍵是非線性

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [MLP：線性層 + activation 疊起來])[
    $h_1 = sigma(W_1 x + b_1)$\
    $h_2 = sigma(W_2 h_1 + b_2)$\
    $hat(y) = W_3 h_2 + b_3$
  ]
][
  #card(tint: palette.rose, title: [沒有 σ 會發生什麼])[
    #set text(size: 0.82em)
    $W_2 (W_1 x + b_1) + b_2 = (W_2 W_1) x + (W_2 b_1 + b_2)$
    #v(.3em)
    疊再多層也 *塌回單一 affine map*，\
    表達能力跟一層完全相同
  ]
]
#v(.6em)
#callout(kind: "warn", compact: true)[所以關鍵不是「深」，是 *非線性*。沒有 activation 的深度是假的深度。]

#speaker-note[
  MLP 把多個線性層和非線性 activation 疊起來：h_1 = σ(W_1 x + b_1)，h_2 = σ(W_2 h_1 + b_2)，最後一層線性輸出。

  沒有 activation 時，疊再多層也塌回單一 affine map，表達能力跟一層完全相同，右邊這行代數就是證明：兩個線性層合起來還是一個線性層。

  所以關鍵是 activation。這是新手最常見的誤解之一：以為「深」本身就有魔力。不是的，沒有非線性的深度是假的深度。
]

== ReLU 把空間摺起來

#row(widths: (1fr, 1.3fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [ReLU])[
    #align(center)[#text(size: 1.15em)[$"ReLU"(z) = max(0, z)$]]
    #v(.3em)
    #set text(size: 0.82em)
    $z < 0$ 輸出 0；$z > 0$ 原樣通過。\
    在 0 有一個 *轉折*，轉折讓模型能把空間切開、摺過去。
  ]
][
  #card(tint: palette.teal, title: [手算 XOR 摺疊：h₁ = ReLU(x₁+x₂), h₂ = ReLU(x₁+x₂−1)])[
    #set text(size: 0.78em)
    #table(
      columns: (auto, auto, auto),
      [$(x_1, x_2)$], [$h = (h_1, h_2)$], [$g(h) = h_1 - 2 h_2 - 0.5$],
      [(0,0)], [(0, 0)], [#text(fill: palette.rose)[−0.5]],
      [(1,0)], [(1, 0)], [#text(fill: palette.teal)[+0.5]],
      [(0,1)], [(1, 0)], [#text(fill: palette.teal)[+0.5]],
      [(1,1)], [(2, 1)], [#text(fill: palette.rose)[−0.5]],
    )
  ]
]
#v(.4em)
#callout(
  kind: "tip",
  compact: true,
)[原本在 x 空間不存在的分隔超平面，經過 *一次 ReLU 摺疊* 之後就存在了，正負剛好對應 XOR。]

#speaker-note[
  先只講 ReLU：ReLU(z) = max(0, z)。z 小於 0 時輸出 0，大於 0 時原樣通過。它在 0 有一個轉折，這個轉折讓模型能把空間切開、折過去，再交給下一層線性模型。

  一個可手算的 XOR 摺疊例子：h_1 = ReLU(x_1 + x_2)、h_2 = ReLU(x_1 + x_2 - 1)。四個點映射過去：(0,0) 變 (0,0)，(1,0) 和 (0,1) 都變 (1,0)，(1,1) 變 (2,1)。

  這個例子不是完整神經網路設計，而是要讓大家看到「非線性真的改變了幾何」。而且在 h 空間可以直接驗證線性可分：取 g(h) = h_1 - 2h_2 - 0.5，四個點的值依序是 -0.5, 0.5, 0.5, -0.5，正負剛好對應 XOR 的 1 和 0。原本在 x 空間不存在的分隔超平面，經過一次 ReLU 摺疊之後就存在了。
]

== 表達力夠了，θ 還是亂數

#quote-card(tint: palette.amber)[
  MLP 給了 $f_theta$ 足夠的表達力，但 $theta$ 還是亂數，它現在連企鵝都分不了。]

#v(.6em)
#row(gutter: .7em)[
  #card(tint: palette.iris, title: [① loss])[#set text(size: 0.85em)
    先定義 *什麼叫錯*]
][
  #card(tint: palette.teal, title: [② gradient])[#set text(size: 0.85em)
    錯了 *往哪裡改*]
][
  #card(tint: palette.amber, title: [③ optimizer])[#set text(size: 0.85em)
    實際 *走一步*]
][
  #card(tint: palette.rose, title: [④ validation])[#set text(size: 0.85em)
    檢查是 *學會* 還是 *背熟*]
]
#v(.5em)
#align(center)[
  #let polaroid(angle, img, cap) = rotate(angle, reflow: true, box(
    fill: palette.surface,
    stroke: 1pt + palette.ink.transparentize(80%),
    radius: 4pt,
    inset: (x: 7pt, top: 7pt, bottom: 5pt),
    {
      box(radius: 2pt, clip: true, image(img, height: 4.6em))
      v(3pt)
      text(font: font-mono, size: 0.62em, fill: palette.ink-soft, cap)
    },
  ))
  #stack(
    dir: ltr,
    spacing: 2.4em,
    polaroid(-3deg, "figs/penguin_1.jpg", [輸入 $x$：「我不是企鵝！」]),
    polaroid(2.5deg, "figs/penguin_2.jpg", [$f_theta (x)$：「企鵝。信心 97%。」]),
  )
]

#speaker-note[
  到這裡上半場結束，盤點一下手上有什麼：線性層是原子操作，activation 提供非線性，疊起來的 MLP 想多彎有多彎，表達力已經夠了。但 θ 還是亂數，這個模型現在連企鵝都分不了。

  下半場只回答一個問題：怎麼把 θ 從亂數調到會做對？路線四站：先用 loss 定義什麼叫錯；再用 gradient 找出往哪裡改；然後讓 optimizer 實際走一步；最後用 validation 檢查模型是真的學會、還是只是背熟了訓練資料。這四站走完，Part 0 那句「老師做了什麼，就提高那個答案的分數」就從口號變成可以跑的程式。
]

== Loss（迴歸）：MSE

#align(center)[
  #text(size: 1.3em)[$L(theta) = 1/N sum_i norm(f_theta (x_i) - y_i)^2$]
]
#v(.6em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [平方的效果 ①])[
    正負誤差 *不抵消*\
    #set text(size: 0.85em)
    +3 和 −3 不會互相騙過去
  ]
][
  #card(tint: palette.amber, title: [平方的效果 ②])[
    大錯被 *懲罰得更重*\
    #set text(size: 0.85em)
    錯 2 倍 → 罰 4 倍
  ]
]

#speaker-note[
  第一站，定義錯誤。預測體重時答案是連續值，用 MSE：預測減答案、平方、取平均。

  平方有兩個效果：第一，正負誤差不抵消，不然一筆多估 3、一筆少估 3，平均起來看起來零錯誤，這顯然不對。第二，大錯會被懲罰得更重：錯兩倍罰四倍，模型會優先修最離譜的預測。
]

== Loss（分類）：softmax + cross-entropy

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [softmax：logits → 機率])[
    #align(center)[$p_k = exp(z_k) / (sum_j exp(z_j))$]
    #v(.3em)
    #set text(size: 0.82em)
    所有 $p_k$ 都是正數，總和是 1
  ]
][
  #card(tint: palette.teal, title: [cross-entropy · one-hot target])[
    #align(center)[$H(q, p) = -sum_k q_k log p_k quad arrow.r.double quad L = -log p_y$]
    #v(.3em)
    #set text(size: 0.82em)
    target 在真實類別 $y$ 上機率 1，整個和 *只剩一項*
  ]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #callout(kind: "tip", compact: true)[把正確類別機率 $p_y$ 拉高 → loss 變小]
][
  #callout(kind: "danger", compact: true)[很有自信地把 $p_y$ 壓低 → loss 爆大]
]

#speaker-note[
  分類時模型先輸出 logits：z = f_θ(x)。logits 還不是機率。softmax 把它變成機率分布：每個分量取 exp、再除以總和。所有 p_k 都是正數，總和是 1。

  cross-entropy 一般定義在兩個分布之間：H(q, p) = -Σ_k q_k log p_k。分類的 target 是 one-hot 分布，真實類別 y 上機率 1，時，整個和只剩一項：L = -log p_y。

  模型把正確類別機率 p_y 拉高，loss 就變小；模型很有自信地把正確類別機率壓低，loss 就變大。log 在這裡的作用就是把「自信的錯」放大成巨額罰款。
]

== 回頭看 BC 的 loss

#align(center)[
  #text(size: 1.35em)[$L(theta) = -log pi_theta (a_i | s_i)$]
]
#v(.6em)
#row(widths: (1fr, 1.5fr), gutter: 1em)[
  #card(tint: palette.iris, title: [Part 0 回顧])[
    #set text(size: 0.85em)
    這就是 cross-entropy：\
    示範者做了 $a_i$，我們懲罰模型\
    *沒有把 $a_i$ 的機率拉高*
  ]
][
  #card(tint: palette.teal, title: [對應關係])[
    #set text(size: 0.85em)
    #table(
      columns: (1fr, 1fr),
      [分類], [BC],
      [class $y$], [demonstrator 的 $a_i$],
      [輸入 $x$], [state $s_i$],
      [$-log p_y$], [$-log pi_theta (a_i|s_i)$],
    )
  ]
]

#speaker-note[
  現在回頭看 BC 的離散 action loss：L(θ) = -log π_θ(a_i | s_i)。

  它就是同一件事：示範者做了 a_i，我們懲罰模型沒有把 a_i 的機率拉高。Part 0 說「先看精神」的那個式子，現在是精確的 cross-entropy：class 換成 demonstrator 的 action，輸入換成 state，其他一模一樣。

  BC 之所以叫 supervised learning，在數學上就體現在這裡，它跟企鵝分類用的是同一條 loss。
]

== Gradient descent：往下坡走

#align(center)[
  #text(size: 1.3em)[$theta^((t+1)) = theta^((t)) - eta nabla_theta L(theta^((t))), quad t = 0, 1, 2, dots$]
]
#v(.5em)
#row(gutter: .7em)[
  #card(tint: palette.iris, title: [∇L])[每顆參數的*偏導數*\
    排成一個向量]
][
  #card(tint: palette.teal, title: [−])[分量為正往左走\
    分量為負往右走]
][
  #card(tint: palette.amber, title: [η · learning rate])[一步跨多大\
    第一個 hyperparameter]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[這是一個*遞迴定義的數列*：給定 $theta^((0))$，反覆套用同一條公式就產生下一個 $theta^((t+1))$，這就是「訓練」。]

#speaker-note[
  有了 loss，訓練就是降低 loss。但「降低」不是一次到位，而是一個數列：從初始參數 θ^(0) 開始，反覆套用同一條更新式，產生 θ^(1)、θ^(2)、……、θ^(t)、θ^(t+1)，這才是訓練迴圈真正在做的事，不是一次性的賦值。

  更新式：`θ^(t+1) = θ^(t) − η ∇_θ L(θ^(t))`。讀法：∇L 在 θ^(t) 這一點算出來，是每顆參數各自的偏導數排成的向量；負號表示逆著這個方向走，分量為正就往左，分量為負就往右；η 是 learning rate，決定一步跨多大。

  這就是課程一開始說的「微積分只需要一個直覺」兌現的地方：偏導數告訴你往哪裡改。下一頁我們拿一顆參數的模型，把這個數列從 t=0 走到 t=1，完整手算一遍。
]

== 一顆參數的手算

#row(widths: (1fr, 1.25fr), gutter: 1.1em)[
  #card(tint: palette.teal, title: [設定])[
    #set text(size: 0.82em)
    模型 $hat(y) = w x$，資料 $(1,2), (2,4), (3,6)$\
    正確關係是 $y = 2x$
    #v(.3em)
    $L(w) = 1/3 [(w-2)^2 + (2w-4)^2 + (3w-6)^2]$
    #v(.3em)
    一條最低點在 $w = 2$ 的 *拋物線*
  ]
][
  #card(tint: palette.iris, title: [從 $w^((0)) = 0$ 走一步（η = 0.01）])[
    #set text(size: 0.82em)
    $(dif L)/(dif w) (w^((0))) = 2/3 sum_i (w^((0)) x_i - y_i) x_i$\
    $= 2/3 [(-2) dot 1 + (-4) dot 2 + (-6) dot 3] = -56\/3$
    #v(.35em)
    $w^((1)) = w^((0)) - 0.01 dot (-56\/3) approx bold(0.187)$
    #v(.3em)
    $w^((1))$ 比 $w^((0))$ 更靠近 2，loss 下降 ✓
  ]
]
#v(.4em)
#callout(
  kind: "tip",
  compact: true,
)[$L: RR^n arrow RR$ 可微時，*gradient* 是 $L$ 在 $theta$ 處所有偏導數依序排成的向量

  $nabla L(theta) = ((partial L)/(partial theta_1)(theta), ..., (partial L)/(partial theta_n)(theta)) in RR^n$。
]

#speaker-note[
  先從一顆參數開始。模型 y_hat = wx，資料 (1,2)、(2,4)、(3,6)，正確關係是 y = 2x。MSE 攤開是一條最低點在 w = 2 的拋物線。

  這是遞迴數列 θ^(t+1) = θ^(t) − η∇L(θ^(t)) 在 n=1、t=0 的具體例子。在 w^(0) = 0 算導數：dL/dw (w^(0)) = (2/3) Σ (w^(0) x_i - y_i) x_i = (2/3)[(-2)·1 + (-4)·2 + (-6)·3] = -56/3。只有一顆參數，所以這裡的導數就是對 w 的偏導數，也就是 gradient 本身；斜率是負的，表示往右走 loss 會降。

  取 η = 0.01：w^(1) = w^(0) - 0.01 × (-56/3) ≈ 0.187。這一步把數列從 w^(0) 推進到 w^(1)，w^(1) 比 w^(0) 更靠近 2，loss 下降。真正訓練時會一路算到 w^(2)、w^(3)……直到收斂。

  高維時，L 對每一顆參數各自求偏導數 ∂L/∂θ_i，把這些偏導數排成一個向量，就是 gradient：∇L = (∂L/∂θ_1, ..., ∂L/∂θ_n)。幾十億顆旋鈕的模型，每次更新做的就是這一頁的事，只是同時做幾十億份偏微分。
]

== Learning rate：第一個重要的 hyperparameter

#row(gutter: .8em)[
  #card(tint: palette.teal, title: [η 太小], icon: [🐢])[
    loss 降得 *很慢*\
    #set text(size: 0.85em)
    訓練半天沒動靜
  ]
][
  #card(tint: palette.iris, title: [η 剛好], icon: [✅])[
    穩定下降\
    #set text(size: 0.85em)
    通常要試出來
  ]
][
  #card(tint: palette.rose, title: [η 太大], icon: [💥])[
    *震盪或發散*\
    #set text(size: 0.85em)
    一步跨過谷底，越彈越高
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[對數列 $theta^((t))$ 來說：

  - η 太小 ⇒ 每步 $theta^((t+1)) - theta^((t))$ 都很小
  - η 太大 ⇒ 可能跨過最低點，出現 $L(theta^((t+1))) > L(theta^((t)))$，數列不再單調遞減，甚至發散。
]

#speaker-note[
  learning rate 是第一個重要 hyperparameter。回到數列 θ^(t+1) = θ^(t) − η∇L(θ^(t))：η 太小，每一步 θ^(t+1) 跟 θ^(t) 幾乎沒差，loss 降很慢；η 太大，這一步會跨過谷底，甚至讓 L(θ^(t+1)) 比 L(θ^(t)) 還大，loss 不再單調遞減，數列開始震盪或發散。

  loss 爆掉、變成 nan，第一個先懷疑 learning rate。不是資料壞了、不是模型寫錯，先把 η 砍十倍再說。這條規則會幫你們省下非常多小時。
]

== Chain Rule

#card(tint: palette.iris, title: [單變數 chain rule 的推導])[
  #set text(size: 0.85em)
  設 $f, g$ 可微，$y=f(u)$、$u=g(x)$：$x$ 變化 $Delta x$ 時，
  #v(.25em)
  #align(center)[$Delta u approx (dif u)/(dif x) Delta x, quad quad Delta y approx (dif y)/(dif u) Delta u$]
  #v(.25em)
  把第一式代入第二式，$u$ 的變化量直接換成 $x$ 的變化量：
  #v(.25em)
  #align(center)[$Delta y approx (dif y)/(dif u) dot (dif u)/(dif x) Delta x$]
  #v(.25em)
  兩邊除以 $Delta x$，取 $Delta x arrow 0$ 的極限，左邊剛好是 $y$ 對 $x$ 的導數定義，於是得到合成函數 $y=f(g(x))$ 也可微，且
  #v(.25em)
  #align(center)[$(dif y)/(dif x) = (dif y)/(dif u) dot (dif u)/(dif x)$]
  #v(.25em)
  本質：兩段線性近似「串接」起來，放大率直接相乘。
]

#speaker-note[
  chain rule 大家微積分都學過，但今天要重新把它「推」一遍，因為下一頁 autograd 就是這條定理的自動化執行，推導過程才是理解 backward() 在幹嘛的關鍵，不能只背 dy/dx = dy/du · du/dx。

  起點是「可微」這個詞的真正意思：一個函數在某點可微，代表在那一點附近，函數的變化可以用一條直線（線性近似）幾乎完美地取代。所以 u = g(x) 在 x 附近可微，意思是 x 動一點點 Δx，u 的變化量 Δu 幾乎精確地等於 (du/dx)·Δx，du/dx 就是這個線性近似的「放大率」或「斜率」。同樣地，y = f(u) 在 u 附近可微，意思是 u 動 Δu，y 的變化量 Δy 幾乎精確地等於 (dy/du)·Δu。

  現在把這兩段近似接起來：x 先動 Δx，透過 g 產生 Δu ≈ (du/dx)Δx，這個 Δu 又透過 f 產生 Δy ≈ (dy/du)Δu，直接代入就得到 Δy ≈ (dy/du)·(du/dx)·Δx。兩邊除以 Δx，讓 Δx 趨近於 0，左邊定義上就是 dy/dx，右邊的兩個比值在極限下就是 dy/du 和 du/dx 這兩個導數本身，這就推出了 dy/dx = dy/du · du/dx。

  所以 chain rule 完全不是一條獨立的規則，是「可微 = 局部線性近似」這件事，套用兩次、再串接起來的必然結果。接力賽的畫面只是幫助記憶：x 的變化被 g 這一棒放大 du/dx 倍，再被 f 這一棒放大 dy/du 倍，兩棒的放大率相乘就是整條接力的放大率。下一頁把 f 換成吃 k 個輸入的函數，看同一套推導怎麼自然生出「求和」這件事。
]

== Chain Rule

#card(tint: palette.teal, title: [$L(theta^((t)))$ 是多變數合成])[
  #set text(size: 0.76em)
  現在 $L$ 不是只吃一個中間變數，是吃 $k$ 個：$L=f(u_1,...,u_k)$，每個 $u_i=g_i(theta)$ 皆可微。多變數可微：

  $exists nabla L(u) in RR^k$，使得對任意 $h in RR^k$，

  $
    L(u+h) = L(u) + nabla L(u) dot h + o(norm(h)), quad nabla L(u) dot h = limits(sum)_(i=1)^k (partial L)/(partial u_i) h_i
  $
  #v(.2em)
  令 $h_i = Delta u_i$，則 $Delta L = limits(sum)_(i=1)^k (partial L)/(partial u_i) Delta u_i + o(norm(Delta u))$；當 $Delta u arrow 0$，$o(norm(Delta u))$ 項消失得比線性項快，一階近似只剩
  #v(.2em)
  #align(center)[$Delta L approx limits(sum)_(i=1)^k (partial L)/(partial u_i) Delta u_i$]
  #v(.2em)
  再把每條路徑自己的線性近似 $Delta u_i approx (dif u_i)/(dif theta) Delta theta$ 代進去、除以 $Delta theta$、取極限：
  #v(.2em)
  #align(center)[$(dif L)/(dif theta) = limits(sum)_(i=1)^k (partial L)/(partial u_i) dot (dif u_i)/(dif theta)$]
  #v(.2em)
  這就是 $nabla L(theta^((t)))$ 每個分量 $(partial L)/(partial theta_i)$ 的算法：每條路徑先各自「一路相乘」，$k$ 條路徑再「全部相加」。
]

#speaker-note[
  上一頁推出單變數 chain rule 的關鍵一步，是「Δy ≈ (dy/du)Δu」，一個中間變數，一段線性近似。這一頁把 f 換成吃 k 個中間變數的函數 L = f(u_1, ..., u_k)，每個 u_i = g_i(θ) 都可微，直接對應 L(θ^(t)) 這種一個參數同時透過好幾條路徑影響 loss 的情況。

  問題是：現在 L 同時被 k 個變數牽動，「可微」還能不能用同一招線性近似？能，但要用正式的多變數可微定義：L 在 u = (u_1, ..., u_k) 處可微，是指存在一個向量 ∇L(u) ∈ R^k，使得對任意方向的擾動 h ∈ R^k，都有 L(u+h) = L(u) + ∇L(u)·h + o(‖h‖)，也就是誤差項除以 ‖h‖ 在 h → 0 時趨近於 0。這裡 ∇L(u)·h 是兩個向量的內積，展開就是 Σ_i (∂L/∂u_i)·h_i，內積本身就是「逐分量相乘、再加總」，加總不是我們額外選擇要做的操作，是內積這個代數結構自帶的。

  把 h_i 換成 Δu_i，L(u+h)-L(u) 就是 ΔL，於是 ΔL = Σ_i (∂L/∂u_i)·Δu_i + o(‖Δu‖)。這個 o(‖Δu‖) 是定義裡明確給出的誤差項，不是隨口說的「高階小量」：它精確的意思是這一項除以 ‖Δu‖ 會趨近於 0，所以當 Δu 夠小，剩下的線性部分 Σ_i (∂L/∂u_i)·Δu_i 就是 ΔL 的一階近似，誤差可以嚴格地忽略，不是憑感覺捨去。

  接下來跟上一頁一模一樣：每個 u_i 本身是 θ 的函數，Δu_i ≈ (du_i/dθ)Δθ，代進去、除以 Δθ、取極限，就得到 dL/dθ = Σ_i (∂L/∂u_i)·(du_i/dθ)。每一項 (∂L/∂u_i)·(du_i/dθ) 對應「θ 透過第 i 條路徑影響 L」的貢獻，是上一頁那條單路徑 chain rule 原封不動的套用；k 條路徑的貢獻加起來，根源就是 ∇L(u)·h 這個內積的定義，不是憑經驗歸納出來的模式。

  這正是算 ∇L(θ^(t)) 裡每一個分量 ∂L/∂θ_i 的完整方法：θ_i 通常同時餵給很多個中間節點，每個節點各自順著自己那條路徑往下算出一段乘積，最後把所有路徑的乘積加起來，就是這個分量的值。接下來幾頁看 PyTorch 怎麼把「相乘再相加」這件事，在整張計算圖上自動化執行。
]

// Autograd 四頁共用的計算圖：trace: false 畫符號版，true 畫代入數值＋grad 的執行版
#let ag-graph(trace: false) = canvas(length: 1cm, {
  import draw: *
  let node(pos, name, label, tint) = {
    circle(pos, radius: 0.42, name: name, fill: tint.lighten(85%), stroke: 0.9pt + tint)
    content(name, text(size: 10pt, label))
  }
  node((0, 0), "x", $x$, palette.iris)
  node((5, 0), "y", $y$, palette.iris)
  node((1.2, 2.1), "a", $a$, palette.teal)
  node((3.8, 2.1), "b", $b$, palette.teal)
  node((2.5, 4.2), "L", $L$, palette.rose)

  let edge(from, to) = line(from, to, mark: (end: ">", size: 0.16), stroke: 0.8pt + palette.line.darken(20%))
  edge("x", "a")
  edge("y", "a")
  edge("x", "b")
  edge("y", "b")
  edge("a", "L")
  edge("b", "L")

  let lbl(pos, body) = content(pos, text(size: 8pt, fill: palette.ink.lighten(10%), body), fill: white, padding: .03)
  if trace {
    lbl((0.35, 0.9), $(partial a)/(partial x) = 3$)
    lbl((4.65, 0.9), $(partial b)/(partial y) = 1$)
    lbl((3.29, 0.945), $(partial a)/(partial y) = 2$)
    lbl((1.71, 0.945), $(partial b)/(partial x) = 1$)
    lbl((1.55, 3.35), $(partial L)/(partial a) = 5$)
    lbl((3.45, 3.35), $(partial L)/(partial b) = 6$)
    let grad-lbl(pos, body) = content(pos, text(size: 9pt, weight: "bold", fill: palette.rose.darken(15%), body))
    grad-lbl((3.45, 4.25), [1])
    grad-lbl((0.4, 2.1), [5])
    grad-lbl((4.6, 2.1), [6])
    grad-lbl((0, -0.72), [21])
    grad-lbl((5, -0.72), [16])
  } else {
    lbl((0.35, 0.9), $(partial a)/(partial x) = y$)
    lbl((4.65, 0.9), $(partial b)/(partial y) = 1$)
    lbl((3.29, 0.945), $(partial a)/(partial y) = x$)
    lbl((1.71, 0.945), $(partial b)/(partial x) = 1$)
    lbl((1.55, 3.35), $(partial L)/(partial a) = b$)
    lbl((3.45, 3.35), $(partial L)/(partial b) = a$)
  }
})

== Autograd ①：forward 留下一張計算圖

#row(widths: (0.95fr, 1.05fr), gutter: 1.1em)[
  #card(tint: palette.amber, title: [計算圖：$a=x y$，$b=x+y$，$L=a b$])[
    #set text(size: 0.72em)
    #align(center)[#ag-graph()]
    #v(.25em)
    #align(center)[代入 $x=2$、$y=3$：$a=6$，$b=5$，$L=30$]
  ]
][
  #card(tint: palette.teal, title: [forward pass 順便記下兩件事])[
    #set text(size: 0.7em)
    每執行一個運算就留下節點與邊：*節點* 記算出的值，*邊* $(u arrow v)$ 記局部偏導在 *當下數值* 的值：
    #v(.3em)
    #table(
      columns: (auto, 1fr, auto),
      stroke: 0.5pt + palette.line,
      inset: 4.5pt,
      table.header([*邊*], [*局部偏導*], [*記下的數值*]),
      [$x arrow a$], [$(partial a)/(partial x) = y$], [3],
      [$y arrow a$], [$(partial a)/(partial y) = x$], [2],
      [$x arrow b$], [$(partial b)/(partial x) = 1$], [1],
      [$y arrow b$], [$(partial b)/(partial y) = 1$], [1],
      [$a arrow L$], [$(partial L)/(partial a) = b$], [5],
      [$b arrow L$], [$(partial L)/(partial b) = a$], [6],
    )
    #v(.25em)
    $x$、$y$ 各分 *兩條路徑* 流向 $L$，上一頁「多路徑」的最小例子。
  ]
]

#speaker-note[
  上一頁把 chain rule 的數學推完了，接下來幾頁換個角度看同一件事：把它當一個跑在 DAG 上的圖論演算法來教，這正是 PyTorch `backward()` 底層真正做的事，不是展示 API。教法跟教任何圖論演算法一樣分三步：先講資料結構，再講演算法本體，最後在具體例子上跑一遍。這頁先講資料結構：計算圖。

  先看左邊這張圖怎麼來的。x、y 是輸入，代入具體數字 x=2、y=3；a = x·y = 6 和 b = x+y = 5 是兩個中間節點，各自同時吃 x 和 y；L = a·b = 30 是輸出。這張圖刻意讓 x 和 y 都分兩條路徑流向 L，跟上一頁的多路徑設定完全對應，等一下演算法裡的「相加」就是在處理這件事。

  重點在右邊，但這裡要先澄清一個容易講錯的細節：forward pass 當下做的不是「把導數的答案先算好存起來」，而是「留下算 backward 用得到的材料」。嚴格說，PyTorch 存的不是 ∂a/∂x = 3 這個數字本身，而是算這個數字所需要的原始 tensor：a = x·y 這個乘法的 grad_fn（`MulBackward0`）會用 `ctx.save_for_backward(x, y)` 存下 x、y 這兩個 tensor；真正「局部偏導數乘上上游梯度」這個乘法運算，是延後到之後 backward() 真的被呼叫、拿到上游傳進來的 grad[a] 時才現場算出來的，不是 forward 當下就做掉。今天投影片右邊的表格為了讓手算例子好算，直接把這個乘法「提前」寫在邊上，概念上完全等價，一樣沒有符號微分，全程都是具體數值運算，只是把 PyTorch 實際延後到 backward() 的那一步，在教學上提前攤開給大家看。資料結構備齊了（一張 DAG，邊上掛著算 backward 需要的材料），下一頁看演算法本體怎麼消費它。
]

== Autograd ②：reverse-mode 演算法本體

#row(widths: (1.02fr, 0.98fr), gutter: 1.1em)[
  #card(tint: palette.rose, title: [Backward$(G, L)$：DAG 上的一次反向掃描])[
    #set text(size: 0.78em)
    #code(numbers: false)[
      ```text
      Backward(G, L):
        for each node v in G:
          grad[v] ← 0
        grad[L] ← 1
        for v in ReverseTopoOrder(G):
          for each edge (u → v) in G:
            grad[u] ← grad[u] + grad[v]·(∂v/∂u)
        return grad
      ```
    ]
  ]
][
  #card(tint: palette.iris, title: [每一行都來自上一頁的 chain rule])[
    #set text(size: 0.74em)
    - `grad[L] ← 1`：遞推起點，$(partial L)/(partial L) = 1$
    - `ReverseTopoOrder`：$v$ 的 *所有下游* 都處理完，才輪到 $v$ 被造訪
    - `grad[v]·(∂v/∂u)`：單一路徑 *一路相乘*
    - `grad[u] + …`：多條路徑 *全部相加*
  ]
]
#v(.4em)
#callout(kind: "tip", compact: true)[
  *迴圈不變量*：$v$ 被造訪的那一刻，$"grad"[v]$ 已經等於 $(partial L)/(partial v)$，所有經過 $v$ 的路徑貢獻都累加完畢，拿它往上游推才是安全的。
]

#speaker-note[
  演算法本體就這幾行，但每一行都值得停下來講。

  第一，初始化。grad[L] 設成 1，因為 loss 對自己的導數當然是 1，這是整個反向遞推的起點；其他節點先歸零，因為等一下要往裡面「累加」。

  第二，ReverseTopoOrder 的精確意思：一個節點要等它在圖上的所有下游都處理完，才輪到它被造訪。為什麼非這樣不可？因為 grad[v] 是靠下游一筆一筆累加進來的，只有下游全部處理完，grad[v] 才是完整的 ∂L/∂v，這時候再拿它往上游推才是安全的。這就是下面那條迴圈不變量：教科書證明演算法正確性的標準寫法是「v 被造訪的那一刻，grad[v] 已經等於 ∂L/∂v」。整個演算法的正確性就掛在這條不變量上，等一下跑例子時可以隨時停下來檢查它有沒有被維持。

  第三，更新規則 grad[u] ← grad[u] + grad[v]·(∂v/∂u)。拆開看：乘法那一項是上一頁單一路徑的 chain rule：路徑上的放大率一路相乘；外面的加法是上一頁多變數版本的「多條路徑相加」，而且我們推導過，那個加法的根源是內積的定義，不是經驗法則。所以這個演算法沒有任何一步是新的數學，它只是把上一頁推出來的兩條規則，按照拓撲順序排好、機械地執行。這件事的正式名稱叫 reverse-mode automatic differentiation。下一頁把它放回那張圖上，實際跑一遍。
]

== Autograd ③：把演算法在圖上跑一遍

#row(widths: (0.9fr, 1.1fr), gutter: 1.1em)[
  #card(tint: palette.amber, title: [同一張圖，紅字＝跑完的 grad])[
    #set text(size: 0.72em)
    #align(center)[#ag-graph(trace: true)]
  ]
][
  #card(tint: palette.rose, title: [逐步執行：三次造訪、六條邊])[
    #set text(size: 0.64em)
    #table(
      columns: (auto, auto, 1fr, auto),
      stroke: 0.5pt + palette.line,
      inset: 4pt,
      table.header(
        [*造訪*], [*沿邊*], [*更新 $"grad"[u] arrow.l "grad"[u] + "grad"[v] dot (partial v)/(partial u)$*], [*結果*]
      ),
      [$L$], [–], [初始化 $"grad"[L] arrow.l 1$], [1],
      [$L$], [$a arrow L$], [$"grad"[a] arrow.l 0 + 1 times 5$], [5],
      [$L$], [$b arrow L$], [$"grad"[b] arrow.l 0 + 1 times 6$], [6],
      [$a$], [$x arrow a$], [$"grad"[x] arrow.l 0 + 5 times 3$], [15],
      [$a$], [$y arrow a$], [$"grad"[y] arrow.l 0 + 5 times 2$], [10],
      [$b$], [$x arrow b$], [$"grad"[x] arrow.l 15 + 6 times 1$], [*21*],
      [$b$], [$y arrow b$], [$"grad"[y] arrow.l 10 + 6 times 1$], [*16*],
    )
    #v(.25em)
    $x$、$y$ 各被寫入 *兩次*，「多路徑相加」在演算法裡自動發生。
    #v(.25em)
    驗算：$L = x^2 y + x y^2$，直接微分得 $(partial L)/(partial x) = 2 x y + y^2 = 21$ ✓、$(partial L)/(partial y) = x^2 + 2 x y = 16$ ✓。
  ]
]

#speaker-note[
  實際跑一遍，總共三次造訪、六條邊，右邊表格一行一行對著講。

  先造訪 L：grad[L] 初始化成 1。沿 a→L 這條邊往回推，grad[a] 累加 1 乘上 ∂L/∂a = b = 5，得到 5；沿 b→L，grad[b] 累加 1 乘上 ∂L/∂b = a = 6，得到 6。這時候 a、b 的下游都只有 L，已經處理完，迴圈不變量成立，兩個都可以造訪了。

  造訪 a：沿 x→a，grad[x] 累加 grad[a]·(∂a/∂x) = 5×3 = 15；沿 y→a，grad[y] 累加 5×2 = 10。造訪 b：沿 x→b，grad[x] 再累加 6×1，從 15 變成 21；沿 y→b，grad[y] 再累加 6×1，從 10 變成 16。注意 x 和 y 各被寫入兩次，「多路徑相加」不是誰特別去處理的 special case，它就是演算法照著拓撲順序跑，自動發生的事。

  最後驗算，確認演算法沒有魔法。把 L 展開成封閉式：L = (xy)(x+y) = x²y + xy²，直接微分，∂L/∂x = 2xy + y²，代入 x=2、y=3 得 12 + 9 = 21；∂L/∂y = x² + 2xy = 4 + 12 = 16。跟圖上紅字完全一致。所以 backward 算出來的是貨真價實的偏導數，而且它從頭到尾不需要知道 L 的封閉式，它只需要那張圖，和邊上掛著的六個數字。
]

== Autograd ④：Engine 真正怎麼跑

#row(widths: (1.05fr, 0.95fr), gutter: 1.1em)[
  #card(tint: palette.rose, title: [真實做法：入度計數 + ready queue])[
    #set text(size: 0.72em)
    #code(numbers: false)[
      ```text
      compute_dependencies(G, L):
        for each node v in G:
          deps[v] ← 0
        for each edge (u → v) in G:
          deps[u] ← deps[u] + 1

      Engine(G, L):
        queue ← [L]
        while queue not empty:
          v ← queue.pop()          # 順序任意
          run v.backward()          # 把 grad[v] 推給每個 u
          for each edge (u → v) in G:
            deps[u] ← deps[u] - 1
            if deps[u] == 0:
              queue.push(u)
      ```
    ]
  ]
][
  #card(tint: palette.iris, title: [跟 ② 是同一個演算法])[
    #set text(size: 0.76em)
    - `deps[u]` = $u$ 的 *out-degree*：有幾個下游就要等幾次貢獻到齊
    - `deps[u] == 0` 才進 queue，等價於 ② 的 *ReverseTopoOrder*：用 Kahn's algorithm 動態算出來，不是先排好一份 list
    - queue 裡不只一個 ready 節點時，彼此順序任意，甚至可以 *平行跑*
    - 圖是每次呼叫 `backward()` 才現場建的，`deps` 也是現場算，動態圖由此而來
  ]
]

#speaker-note[
  ②那頁的 `for v in ReverseTopoOrder(G)` 是理想化寫法，看起來像是先把整張圖排好序，再照著跑。PyTorch 真實的 engine（`torch/csrc/autograd/engine.cpp`）不是這樣做：它先跑一次 `compute_dependencies`，對每個節點數「它的下游有幾個」，也就是 out-degree；然後維護一個 ready queue，一開始只有根節點 L 在裡面。每次從 queue 拿一個節點出來執行它的 backward()，把梯度推給它的每個輸入 u，同時把 deps[u] 減一；deps[u] 歸零，代表 u 的所有下游都已經把貢獻送到了，這時候才把 u 放進 queue。

  這其實是 Kahn's algorithm，大家在演算法課學拓撲排序時多半學過的「入度歸零就進 queue」那個版本，只是這裡數的是反向圖的 out-degree（等於原圖裡「還有幾個下游沒交作業」）。它跟②那頁的 ReverseTopoOrder 是同一個排序，差別只在於：一個是先想好一份 list 再照著跑，一個是排序過程跟執行過程交織在一起、用計數器動態算出來。兩者對外行為完全一樣，都保證同一條迴圈不變量成立。

  套到手算的圖上：deps[x] = deps[y] = 2，因為 x、y 各自流向 a 和 b 兩個下游；deps[a] = deps[b] = 1，因為 a、b 都只流向 L；deps[L] = 0，一開始就在 queue 裡。造訪 L 之後，a 和 b 的 deps 同時歸零，一起被丟進 queue。這裡有個重要觀察：queue 裡同時有兩個以上 ready 節點時，執行順序任意：先跑 a 再跑 b，或先跑 b 再跑 a，算出來的梯度完全一樣，因為兩者互不依賴。這個「順序任意」正是 PyTorch engine 能用多執行緒平行跑不相依分支的空間。

  這頁還有一個附帶重點：dependencies + queue 這套機制是動態圖的必要條件。PyTorch 每次呼叫 backward() 時，圖本身是前一次 forward 剛建出來的，deps 也只能現場算，沒辦法像 static graph 框架那樣預先分析一次、之後重複套用同一份排序，這也是為什麼 PyTorch 可以在 for 迴圈裡用 if 動態決定要不要跑某段運算的底層原因。
]

== Autograd ⑤：為什麼是 reverse、不是 forward？

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [forward-mode], icon: [➡️])[
    #set text(size: 0.8em)
    固定 *一個輸入* $theta_i$，順著圖正向掃一遍，得到所有節點對 $theta_i$ 的導數。
    #v(.2em)
    湊齊 $nabla L$ 的 $n$ 個分量：掃 *$n$ 遍*
  ]
][
  #card(tint: palette.rose, title: [reverse-mode], icon: [⬅️])[
    #set text(size: 0.8em)
    固定 *一個輸出* $L$（純量），反向掃一遍，同時得到 $L$ 對 *所有輸入* 的偏導。
    #v(.2em)
    整個 $nabla L$：掃 *1 遍*，成本 ≈ 一次 forward
  ]
]

#v(2.45em)
#callout(kind: "info", compact: true)[
  訓練第 $t$ 步呼叫 `loss.backward()`，跑的就是這個演算法；算出的 $nabla L(theta^((t)))$ 交給 `optimizer.step()` 產生 $theta^((t+1))$。
]

#speaker-note[
  這裡值得停下來問一句：為什麼深度學習清一色用 reverse-mode，不用 forward-mode？

  forward-mode 是另一種同樣正確的自動微分：固定一個輸入 θ_i，順著圖往前掃一遍，沿途把「每個節點對 θ_i 的導數」帶著走，掃完就得到所有輸出對這個輸入的導數。問題在方向：一遍只能處理一個輸入，n 顆參數就要掃 n 遍。reverse-mode 反過來：固定一個輸出，反向掃一遍，就把這個輸出對所有輸入的偏導數同時算完：上一頁跑完那一遍，grad[x] 和 grad[y] 就是同時到手的，這就是「一遍全拿」。

  現在看深度學習的形狀：輸出是純量 loss，就一個；輸入是幾十億顆參數。這個極端的不對稱，正是 reverse-mode 是唯一划算選擇的原因：forward-mode 要掃十億遍，reverse-mode 只掃一遍，而且這一遍的成本跟一次 forward 差不多是同一個量級。付一次 forward 的價錢，換到整個 gradient 向量。

  串回今天的主線：訓練第 t 步呼叫 loss.backward()，跑的就是前面幾頁的演算法，算出來的就是 ∇L(θ^(t)) 這整個向量，交給 optimizer.step() 產生 θ^(t+1)，下一頁看這幾行怎麼串成完整的訓練 loop。
]

== 訓練 loop

#code(title: "train.py", numbers: true)[
  ```python
  optimizer.zero_grad()      # 清掉上一輪梯度
  pred = net(xb)             # forward：算預測
  loss = loss_fn(pred, yb)   # loss：算錯誤
  loss.backward()            # backward：算每個參數的梯度
  optimizer.step()           # step：更新參數
  ```
]
#v(.5em)
#align(center)[
  #pill(tint: palette.iris)[forward] #text(size: 1.1em)[→] #pill(tint: palette.teal)[loss] #text(size: 1.1em)[→] #pill(tint: palette.amber)[backward] #text(size: 1.1em)[→] #pill(tint: palette.rose)[step] #text(size: 1.1em)[→] 迴圈
]

#speaker-note[
  lab 裡訓練 loop 就這五行。`zero_grad()` 清掉上一輪梯度；forward 算預測；loss 算錯誤；`backward()` 算每個參數的梯度；`step()` 更新參數。

  這五行是接下來每一個 lab、每一個作業、以及業界每一份訓練程式碼的共同骨架。今天之後你們看到任何 training script，先找這五行；找到了，這份程式碼的主線就抓住了。順帶一提，忘了 `zero_grad()` 是新手第二常見的 bug：梯度會累加，模型會越走越歪。
]

== Mini-batch SGD

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [完整 loss vs mini-batch 估計])[
    $L(theta) = 1/N sum_i ell_i (theta)$
    #v(.3em)
    $nabla L(theta) approx 1/(|B|) sum_(i in B) nabla ell_i (theta)$
    #v(.3em)
    #set text(size: 0.82em)
    資料一大，全算太慢 → 每次 *抽一小批*
  ]
][
  #card(tint: palette.teal, title: [統計性質])[
    #set text(size: 0.85em)
    - 均勻抽樣時：完整梯度的 *無偏估計*
    - 但有 *變異數* → 訓練曲線會抖
    - batch 越小，變異數越大，曲線越毛
  ]
]
#v(.5em)
#callout(kind: "tip", compact: true)[抖動不是 bug，它是 mini-batch 訓練的自然結果。看到毛毛的 loss curve 不要慌。]

#speaker-note[
  完整 loss 是所有資料平均。資料一大，每次都用全部資料算梯度很慢。mini-batch SGD 每次抽一小批，用小批的平均梯度近似完整梯度。

  batch 是從資料均勻抽樣時，這是完整梯度的無偏估計，但有變異數，所以訓練曲線會抖。抖動不是 bug，它是 mini-batch 訓練的自然結果；batch 越小，估計的變異數越大，曲線越毛。

  lab 裡第一次看到 loss curve 毛毛的同學常會以為自己寫錯了。沒有，那是統計，不是 bug。
]

== 泛化：training set 之外的世界

#quote-card(tint: palette.amber)[把 training loss 壓低不是終點。機器學習真正關心的是 *泛化*：沒看過的新資料會不會做。]

#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [training set], icon: [🏋️])[
    用來 *更新參數*
  ]
][
  #card(tint: palette.teal, title: [validation set], icon: [🔍])[
    *不更新參數*，只檢查新資料表現
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[實務規則：用 training set 訓練；用 validation curve 決定 *何時停、選哪個 checkpoint、調哪組 hyperparameter*。]

#speaker-note[
  但把 training loss 壓低不是終點。機器學習真正關心的是泛化：沒看過的新資料會不會做。

  資料至少要切成兩塊：training set 用來更新參數；validation set 不更新參數，只檢查新資料表現。

  實務規則：用 training set 訓練，用 validation curve 決定何時停、選哪個 checkpoint、調哪組 hyperparameter。validation set 一旦被拿去更新參數，它就廢了：它的唯一價值就是「模型沒看過」。
]

== Overfitting

#row(widths: (1.1fr, 1fr), gutter: 1.1em)[
  #card(title: [訓練時要盯的兩條曲線])[
    #set text(size: 0.85em)
    #table(
      columns: (auto, 1fr),
      [training loss], [持續下降 ↘],
      [validation loss], [先下降，*後來上升* ↘↗],
    )
    #v(.3em)
    岔開的位置，就是該停的位置
  ]
][
  #card(tint: palette.rose, title: [overfitting 的診斷])[
    #set text(size: 0.85em)
    大 MLP：training accuracy 100%，\
    validation accuracy 停住甚至下降
    #v(.3em)
    模型不是學到穩定規律，\
    是在 *背訓練資料*
  ]
]
#v(.4em)
#callout(kind: "warn", compact: true)[BC 的 rollout drift 可以看成 *泛化失敗的時間版本*，Part 2 會正面遇到它。]

#speaker-note[
  如果一個大 MLP 在 training accuracy 到 100%，validation accuracy 卻停住甚至下降，這叫 overfitting。模型可能不是學到穩定規律，而是在背訓練資料。

  課堂上要看兩條曲線：training loss 持續下降；validation loss 先下降，後來上升。兩條曲線岔開，就是過擬合的典型訊號。

  這件事會直接回到機器人。BC 的 rollout drift 可以看成泛化失敗的時間版本：模型訓練時看的是老師走過的 state；部署時自己錯一步，走到沒看過的 state，就像考到練習題沒有的題型。這個伏筆 Part 2 收。
]

#focus-slide[
  模型是函數，loss 是地形，

  gradient 是下坡方向，

  optimizer 是走路規則，

  validation 是檢查是不是只背了訓練資料。
]

= Part 2 · 序列化 BC

== Lab 2：Push-T 的 action 序列

#row(widths: (1.2fr, 1fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [basic_sequence_bc · lerobot/pusht_keypoints], icon: [🕹])[
    #set text(size: 0.85em)
    Push-T：人控制推桿，把 *T 形物塊* 推到目標位置。\
    這一段先拿掉 image，*只留下 action 序列*。
  ]
][
  #card(tint: palette.teal, title: [autoregressive])[
    #set text(size: 0.85em)
    一段示範：$a_1, a_2, ..., a_T$
    #v(.3em)
    要學：給定 $a_1 ... a_t$，預測 $a_(t+1)$
  ]
]
#v(.6em)
#align(center)[
  #pill(tint: palette.iris)[過去] #text(size: 1.1em)[→] #pill(tint: palette.teal)[預測下一步] #text(size: 1.1em)[→] #pill(tint: palette.amber)[下一步變成未來的過去] #text(size: 1.1em)[→] 循環
]

#speaker-note[
  Part 1 的企鵝資料有個隱藏的方便之處：每筆資料互相獨立，這隻預測完不影響下一隻。機器人示範不是這樣，一段示範是一條時間軌跡，前後步驟彼此牽連。Part 2 要做的，就是把「時間」加回剛搭好的骨架裡。第二個 lab 是 `basic_sequence_bc`，資料是 `lerobot/pusht_keypoints`。Push-T 任務裡，人控制推桿，把 T 形物塊推到目標位置。這一段先拿掉 image，只留下 action 序列。

  一段示範是 `a_1` 到 `a_T`。我們要學：給定 `a_1` 到 `a_t`，預測 `a_{t+1}`。

  這叫 autoregressive：每一步用過去預測下一步，下一步再變成未來的過去。這個詞今天會反覆出現，它同時是 GPT 的骨架，也是 action 序列模型的骨架。
]

== 自回歸分解：一條恆等式

#align(center)[
  #text(size: 1.25em)[$p(a_1, ..., a_T) = product_(t=1)^T p(a_t | a_(1:t-1))$]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [恆等式，不是假設])[
    #set text(size: 0.82em)
    由條件機率定義 $p(x, y) = p(x) thin p(y | x)$\
    對 $a_1, ..., a_T$ 反覆展開即得。\
    對 *任何* 聯合分布都成立，沒有丟失資訊。
  ]
][
  #card(tint: palette.teal, title: [模型化發生在「條件集」])[
    #set text(size: 0.82em)
    #table(
      columns: (auto, 1fr),
      [bigram], [$pi_theta (a_(t+1) | a_t)$ · 截斷到 1 步],
      [Transformer], [$pi_theta (a_(t+1) | a_(1:t))$ · 整段前綴],
    )
    近似的好壞 = 截斷丟掉的條件相關性多寡
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[NLL 跟著分解：$-log p(a_(1:T)) = sum_(t=1)^T -log p(a_t | a_(1:t-1))$，整段序列的 loss 是 *每步條件 NLL 的和*，這條等式是之後 teacher forcing 的數學根據。]

#speaker-note[
  在切格子、寫模型之前，先把 Part 2 的數學根基立好：任何序列的聯合分布都可以精確分解成一連串條件分布的乘積。推導只用一條定義：p(x, y) = p(x)·p(y|x)。對整段序列做歸納，p(a_1, a_2) = p(a_1)·p(a_2|a_1)；再把 (a_1, a_2) 看成一個整體，p(a_1, a_2, a_3) = p(a_1, a_2)·p(a_3|a_1, a_2)；一路展開就得到 p(a_1, ..., a_T) = Π_t p(a_t | 前綴)。注意這一步完全沒有做任何近似：它是恆等式，對任何聯合分布都成立。

  那模型化發生在哪裡？發生在我們決定「條件集拿多長」。bigram 把條件集截斷到只剩上一步，Transformer 把整段可見前綴都放進條件集。所以「序列模型的好壞」有了精確的問法：你截斷掉的那些條件相關性，對預測下一步重不重要？這個問題的答案決定了 bigram 的天花板，也決定了 attention 值不值得付出代價。

  兩邊取 -log，乘積變成和：整段序列的 NLL 恰好等於每一步條件 NLL 的總和。這條等式今天會用兩次：第一次是等一下 bigram 的 MLE，第二次是 teacher forcing，「平行訓練所有位置」不是工程 trick，是這條分解式的逐項並行計算。
]

== Action tokenization：連續 → 離散

#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.teal, title: [原始 action], inset: 0.75em)[
    #set text(size: 0.85em)
    連續座標 $(x, y)$，範圍約 $0 tilde 512$
  ]
][
  #card(tint: palette.iris, title: [離散化：每軸切 16 格], inset: 0.75em)[
    #set text(size: 0.85em)
    $"vocab_size" = 16 times 16 = 256$，每個 $("bin"_x, "bin"_y)$ 對應一個 token id
  ]
]
#v(.3em)
#callout(
  kind: "info",
  compact: true,
)[action 落在哪格就變成哪個 token，Transformer 最常見的訓練形式是分類：*預測下一個 token 是 vocab 裡哪一個*。]
#v(.3em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.rose, title: [量化誤差可以算], inset: 0.75em)[#set text(size: 0.78em)
    格寬 $Delta = 512\/16 = 32$；還原到格子中心，每軸誤差至多 $Delta\/2 = 16$；bin 內均勻分布時量化 MSE $= Delta^2\/12$]
][
  #card(tint: palette.amber, title: [每軸切 k 格的兩頭代價], inset: 0.75em)[#set text(size: 0.78em)
    誤差 $prop 1\/k$ 下降；但 vocab $= k^2$ 成長、每個 token 平均樣本數 $prop 1\/k^2$ 掉，*分類問題變難*]
]

#speaker-note[
  原始 action 是連續座標 (x, y)，範圍大約 0 到 512。Transformer 最常見的訓練形式是分類：預測下一個 token 是 vocab 裡哪一個。所以我們先把連續 action 離散化。每軸切 16 格，vocab_size 就是 16 × 16 = 256，每個 (bin_x, bin_y) 對應一個 token id。

  離散化的代價不是「感覺變粗」，是可以精確計算的量化誤差。格寬 Δ = 512/16 = 32。解碼時把 token 還原成格子中心，所以每軸誤差至多 Δ/2 = 16 個像素，這是最壞情況。平均情況也算得出來：假設 action 落在 bin 內是均勻分布，誤差 e 在 [-Δ/2, Δ/2] 上均勻，E[e²] = ∫ e²·(1/Δ) de = Δ²/12。這是任何均勻量化器的標準結果：再會訓練的模型，MSE 都不可能低於這個地板，因為資訊在 tokenization 那一步就已經丟掉了。

  兩頭的代價現在都能寫成 k 的函數。每軸切 k 格：格寬 Δ = 512/k，誤差隨 1/k 下降；但 vocab = k² 成長，固定資料量 N 下每個 token 平均分到 N/k² 筆樣本，長尾 token 幾乎沒看過，分類問題變難。lab 裡調 `bins_per_dim` 就是沿著這條 1/k 對 k² 的曲線在移動。這個取捨 Part 4 講 7 維手臂時會再爆發一次，到時候指數從 2 變成 7。
]

== Bigram：最小的序列模型

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [Markov 假設：條件集截斷到 1])[
    #align(center)[#text(size: 1.05em)[$pi_theta (a_(t+1) | a_(1:t)) := pi_theta (a_(t+1) | a_t)$]]
    #v(.25em)
    #set text(size: 0.82em)
    參數就是一張 $256 times 256$ 的表：\
    `table[current_token] -> logits over next`
  ]
][
  #card(tint: palette.teal, title: [它的 MLE 有封閉解])[
    #align(center)[#text(size: 1.05em)[$hat(pi)(j | i) = N(i, j) / (sum_(j') N(i, j'))$]]
    #v(.25em)
    #set text(size: 0.82em)
    $N(i, j)$ = 資料裡 $(i arrow j)$ 出現次數。\
    數次數、逐列正規化，就是 NLL 的全域最小值。
  ]
]
#v(.5em)
#quote-card(tint: palette.rose)[天花板寫在假設裡：被截斷丟掉的 $a_(1:t-1)$，任何訓練都救不回來。]

#speaker-note[
  第一個 baseline 是 bigram，用上一頁的語言講：把自回歸分解的條件集截斷到只剩上一步，`π_θ(a_{t+1} | a_1:t)` 直接定義成 `π_θ(a_{t+1} | a_t)`。這是一階 Markov 假設。條件集只有 256 種取值、輸出也只有 256 種，所以參數就是一張 256×256 的表，程式上 `table[current_token]` 給出 next token 的 logits。

  這個模型好到可以解析地解掉。對整份資料的 NLL 是 `-Σ log π(a_{t+1}|a_t)`，按「前一個 token 是 i」分組，每組是獨立的多項分布估計問題：在 Σ_j π(j|i) = 1 的約束下最大化 Σ_j N(i,j) log π(j|i)，其中 N(i,j) 是 pair (i→j) 在資料裡出現的次數。拉格朗日乘子法：對 π(j|i) 求導、令其為零，得 π(j|i) ∝ N(i,j)，正規化後就是 N(i,j) / Σ_j' N(i,j')。所以 bigram 的最佳解不用梯度下降，數次數、逐列除以列和，就是 NLL 的全域最小值。lab 裡拿神經網路訓練 bigram，收斂後就該逼近這張計數表；這也是檢查訓練程式有沒有寫對的一個好用基準。

  它的天花板同樣寫在假設裡：condition 被截斷，`a_1` 到 `a_{t-1}` 全部丟掉。Push-T 的軌跡有階段、有方向，現在該接近、推動還是修正，取決於更早的歷史，而這些資訊 bigram 在定義上就拿不到，任何訓練都救不回來。量化這個天花板之後，你才知道 attention 到底買回了什麼：把條件集從 1 步擴回整段前綴。
]

== Embedding：查表就是矩陣乘法

#row(widths: (1fr, 1.15fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [one-hot × E = 取出第幾列])[
    #set text(size: 0.82em)
    token 3，vocab_size = 6：
    #v(.25em)
    $[0, 0, 0, 1, 0, 0] dot E = E "的第 3 列"$
    #v(.3em)
    embedding table 是一個 *可訓練矩陣*，\
    查表本質上還是矩陣乘法
  ]
][
  #card(tint: palette.teal, title: [神經版 bigram = 低秩分解])[
    #set text(size: 0.8em)
    $"logits"(i) = e_i^top E W, quad E in RR^(256 times C), thin W in RR^(C times 256)$
    #v(.25em)
    整張 $256 times 256$ logit 表被分解成 *秩 $<= C$* 的乘積\
    參數 $2 dot 256 C$ vs $256^2$：$C = 32$ 時只剩 $1\/4$
  ]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[$C >= 256$ 可精確重現計數表；$C < 256$ 是壓縮，低秩約束下要壓低 NLL，轉移行為相近的 token *必須共用方向*。「相似 token 有相似 embedding」是最佳化的結果，不是願望。]

#speaker-note[
  上一頁說 bigram 程式上像一張表。這張表值得停一頁講清楚，因為它有個正式名字：embedding，今天第一次遇到、之後每個模型裡都會有的零件。先想 token id 是什麼。token id 只是整數，模型不能直接把「137」當成有意義的連續量，136 和 137 這兩個格子在桌面上可能根本不相鄰。

  先用 one-hot 表示：token 3、vocab_size 6，就是 [0,0,0,1,0,0]。one-hot 乘上一個矩陣 E，結果就是取出 E 的第 3 列。所以 embedding table 是一個可訓練矩陣，查表本質上還是矩陣乘法，又回到 Part 1 那一行 Wx。

  那 lab 裡用神經網路寫的 bigram 到底是什麼？把式子寫穿：current token 的 one-hot 乘 E 得到 C 維 embedding，再乘輸出矩陣 W 得到 256 維 logits，所以 logits(i) = e_i 轉置乘 E 乘 W。E 是 256×C、W 是 C×256，乘起來是一個 256×256 的矩陣，跟計數表版本是同一個物件，只是被寫成兩個矩陣的乘積，秩至多 C。這給了 embedding 維度一個精確的身分：C 是這張 logit 表的秩上限。C 大於等於 256 時，任何表都能精確重現，神經版和計數版理論上等價；C 小於 256 時是壓縮，參數從 256 平方變成 2×256×C，C = 32 時只剩四分之一。

  壓縮的代價逼出一個有趣的結果：秩不夠，模型沒辦法給每個 token 一列獨立的 logits，想壓低 NLL，轉移行為相近的 token 就必須共用 E 裡相近的方向。所以「訓練後相似 token 有相似 embedding」不是願望，是低秩約束加上最佳化的必然。訓練前 E 是亂數；訓練後這個結構自己浮出來。這個「用低秩矩陣分解逼出相似性」的機制，放大一百倍就是 word embedding 和 LLM embedding 的故事。
]

== Shape discipline：B、T、C

#row(widths: (1fr, 1.2fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [序列模型的三個字母])[
    #set text(size: 0.85em)
    #table(
      columns: (auto, 1fr),
      [B], [batch size],
      [T], [sequence length],
      [C], [channel / embedding dim],
    )
  ]
][
  #card(tint: palette.teal, title: [常見形狀])[
    #set text(size: 0.85em)
    #table(
      columns: (auto, 1fr),
      [tokens], [`(B, T)`],
      [embedding], [`(B, T, C)`],
      [logits], [`(B, T, vocab_size)`],
    )
  ]
]
#v(.3em)
#callout(
  kind: "tip",
  compact: true,
)[遇到 shape mismatch，*不要猜*，先 `print(x.shape)`。深度學習除錯很大一部分是把形狀帳對齊。]

#speaker-note[
  embedding 把 token 變成向量之後，資料在模型裡的形狀就固定下來了，這裡順勢建立 shape discipline，下一頁的 attention 全是矩陣運算，形狀帳不清楚就會跟丟。序列模型最常見三個字母：B 是 batch size，T 是 sequence length，C 是 channel 或 embedding dimension。

  常見形狀：tokens 是 (B, T)，過了 embedding 變 (B, T, C)，最後 logits 是 (B, T, vocab_size)。

  lab 裡遇到 shape mismatch，不要猜，先 print(x.shape)。深度學習除錯很大一部分是把形狀帳對齊。這個習慣現在養成，之後讀任何 model 程式碼，你第一件事就是在腦中跑形狀，這是分辨「看得懂架構」跟「只是看過名詞」的試金石。
]

== Attention：可學習的加權平均

#align(center)[
  #text(size: 1.2em)[$"Attention"(Q, K, V) = "softmax"((Q K^top) / sqrt(d_k)) V$]
  #v(.15em)
  #text(
    size: 0.8em,
  )[$Q, K in RR^(T times d_k), quad V in RR^(T times d_v), quad Q K^top in RR^(T times T), quad "輸出" in RR^(T times d_v)$]
]
#v(.35em)
#row(gutter: .7em)[
  #card(tint: palette.iris, title: [QKᵀ])[
    #set text(size: 0.8em)
    query 跟每個 key 的 *內積*\
    內積 = 相似度，第三次出現]
][
  #card(tint: palette.teal, title: [÷ √d_k])[
    #set text(size: 0.8em)
    分量獨立、零均值、單位變異數時，內積變異數是 $d_k$\
    不縮放 → softmax 飽和 → 梯度消失]
][
  #card(tint: palette.amber, title: [softmax · V])[
    #set text(size: 0.8em)
    每列變成加總為 1 的權重\
    拿權重對 value *加權平均*]
]
#v(.3em)
#callout(
  kind: "info",
  compact: true,
)[核心想法：不硬選某一個過去位置，而是對 *所有可見位置做加權平均*，權重由模型自己算。]

#speaker-note[
  bigram 不夠，是因為它沒有上下文。推 T 形物塊時，模型需要知道自己是在接近、推動、修正，還是接近終點。每一步都應該能回頭讀歷史。

  attention 的核心想法：不要硬選某一個過去位置，而是對所有可見位置做加權平均，權重由模型自己算。

  先不要急著背公式。QK^T 是每個 query 跟每個 key 的內積，跟 Part 1 一樣，內積在這裡被當成相似度分數。除以 sqrt(d_k) 有具體理由：如果 q、k 的分量近似獨立、零均值、單位變異數，內積的變異數是 d_k，維度一高分數就很大，softmax 會飽和成接近 one-hot，梯度跟著消失；縮放後分數的變異數維持在 1 的量級。softmax 對每一列做，把分數變成加總為 1 的權重。最後用這些權重加權平均 value。
]

== 三個 token 的手算

#row(gutter: 1em)[
  #card(tint: palette.iris, title: [scores = QKᵀ])[
    #set text(size: 0.85em)
    $mat(2, 1, 0; 0, 2, 1; 1, 1, 2)$
  ]
][
  #card(tint: palette.teal, title: [softmax 後的 weights])[
    #set text(size: 0.85em)
    $mat(0.67, 0.24, 0.09; 0.09, 0.67, 0.24; 0.21, 0.21, 0.58)$
    #v(.2em)
    #set text(size: 0.78em)
    第一列：$(e^2, e^1, e^0) = (7.39, 2.72, 1.00)$，\
    除以和 $11.11$ → $(0.67, 0.24, 0.09)$
  ]
][
  #card(tint: palette.amber, title: [第一個輸出])[
    #set text(size: 0.85em)
    $0.67 v_1 + 0.24 v_2 + 0.09 v_3$
    #v(.2em)
    value 的加權平均
  ]
]
#v(.7em)
#quote-card(tint: palette.iris)[attention 是 *可學習的加權平均*。]

#speaker-note[
  三個 token 的手算形狀。scores 是 QK^T，一個 3×3 矩陣。softmax 對每一列做。第一列 (2, 1, 0)：取 exp 得 (7.39, 2.72, 1.00)，和是 11.11，除下去得 (0.67, 0.24, 0.09)，加總為 1，這就是第一個 query 分給三個位置的權重。另外兩列同法。

  如果 value 是 v_1、v_2、v_3，第一個輸出就是 0.67 v_1 + 0.24 v_2 + 0.09 v_3。

  所以 attention 的錨點是：attention 是可學習的加權平均。這句話記住了，公式忘了都能重推出來。「可學習」在哪？Q、K、V 都是輸入乘上可訓練的投影矩陣，又是 Part 1 那行 Wx。
]

== Transformer block 的其他零件

#row(gutter: .7em)[
  #card(tint: palette.iris, title: [position embedding])[#set text(size: 0.72em)
    $"Attn"(P X) = P thin "Attn"(X)$：重排輸入，輸出跟著重排\
    → 改餵 $x_t + p_t$，順序資訊才進得了模型]
][
  #card(tint: palette.teal, title: [multi-head])[#set text(size: 0.72em)
    $"head"_h = "Attn"(X W_Q^h, X W_K^h, X W_V^h)$\
    各 head 在 $d_k = C\/H$ 維子空間，concat 乘 $W_O$]
]
#v(.3em)
#row(gutter: .7em)[
  #card(tint: palette.amber, title: [residual + LayerNorm])[#set text(size: 0.72em)
    $y = x + f(x) => partial y \/ partial x = I + partial f \/ partial x$，連乘每項含 $I$\
    LN：$gamma (x - mu)\/sigma + beta$，逐 token 定住激活量級]
][
  #card(tint: palette.rose, title: [MLP block])[#set text(size: 0.72em)
    $W_2 thin sigma(W_1 x)$，逐 token 套用\
    attention 跨位置交換資訊，MLP 在 channel 維加工]
]
#v(.3em)
#callout(
  kind: "warn",
  compact: true,
)[序列 action *一定要有 position embedding*，沒有它，$a_3$ 和 $a_7$ 對調，輸出只是跟著對調。]

#speaker-note[
  attention 是核心，但單靠它還組不成一個能穩定訓練的模型。Transformer block 剩下的零件，每一個都有一句可以驗證的數學理由，不只是「讓訓練穩定」這種口號。

  position embedding 的理由是一條等式：attention 對輸入順序是 permutation-equivariant 的。為什麼？公式裡只用到 token 兩兩之間的內積和逐列 softmax，沒有任何一項讀取「位置索引」，把輸入乘上置換矩陣 P，Q、K、V 都跟著置換，QK 轉置變成 P Q K 轉置 P 轉置，softmax 逐列做不受影響，最後 Attn(PX) = P·Attn(X)。所以把 a_3 和 a_7 對調，模型的輸出只是跟著對調，它在結構上就分不出誰先誰後。解法是把輸入改成 x_t + p_t，p_t 是每個位置一條可訓練向量：位置不同、輸入向量就不同，這條等變性被打破，順序資訊才進得了模型。

  multi-head 就是把一次 attention 換成 H 次平行的小 attention：第 h 顆 head 用自己的投影矩陣把 X 投到 d_k = C/H 維的子空間裡做完整的 attention，H 顆的輸出 concat 回 C 維、再乘一個輸出矩陣 W_O。總計算量跟單顆大 head 同量級，但每顆 head 有自己的相似度定義，一顆可以看「空間上接近」、另一顆看「時間上剛發生」。

  residual 的理由也是一行導數：y = x + f(x)，對 x 微分得到 I + ∂f/∂x。深度堆疊 L 層時，梯度是這些 Jacobian 的連乘，每一項都含恆等矩陣 I，所以展開後永遠存在一條不經過任何非線性的直通路徑，梯度不會因為深度而指數消失。這就是「深層能訓練」的機制，不是玄學。LayerNorm 做的事一行寫完：對每個 token 的 C 維向量算平均 μ 和標準差 σ，正規化成 (x−μ)/σ 再仿射 γ、β，把每一層激活的量級定在 O(1)，softmax 和梯度都不會因為深度而尺度爆走。

  最後 MLP：兩層線性夾一個非線性，W_2·σ(W_1 x)，對每個 token 獨立套用。分工是精確的：attention 是唯一跨位置搬資訊的地方，MLP 只在 channel 維度上加工每個 token 自己的表示。讀任何 Transformer 程式碼，先找這兩類操作的交替，骨架就出來了。
]

== Causal mask：不准偷看未來

#row(widths: (1fr, 1.3fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [加法型 mask])[
    #set text(size: 0.78em)
    $"softmax"((Q K^top) / sqrt(d_k) + M)$
    #v(.25em)
    $M_(t s) = cases(0 & quad s <= t, -infinity & quad s > t), quad M = mat(0, -infinity, -infinity; 0, 0, -infinity; 0, 0, 0)$
    #v(.25em)
    $e^(-infinity) = 0$ ⇒ 未來位置權重 *恰為 0*，\
    每列仍在 $s <= t$ 上正規化、加總為 1
  ]
][
  #card(tint: palette.rose, title: [為什麼是底線], icon: [🚨])[
    #set text(size: 0.85em)
    訓練時一次把整段 sequence 丟進模型，\
    但位置 $t$ 預測 $a_(t+1)$ 時 *不能看之後的答案*。
    #v(.3em)
    偷看未來 → 訓練 loss 很好看\
    → 部署立刻露餡（rollout 時 *未來還沒發生*）
  ]
]

#speaker-note[
  causal mask 是序列 BC 的底線。訓練時我們一次把整段 sequence 丟進模型，這是效率需求；但位置 t 預測 `a_{t+1}` 時不能看 `a_{t+1}` 之後的答案。

  實作的精確寫法不是把權重矩陣乘上 0/1，而是在 softmax 之前對 scores 加一個 mask 矩陣 M：s ≤ t 的位置加 0，s > t 的位置加負無窮。這樣做的好處可以從 softmax 的定義直接讀出來：exp(-∞) = 0，所以未來位置的權重不是「很小」，是恰好等於 0；而且 softmax 的分母只剩 s ≤ t 那些項，每一列自動在可見位置上重新正規化、加總仍是 1。對照上一頁的自回歸分解：加了 causal mask 的一次 forward，等於同時對每個 t 計算 `π_θ(a_{t+1} | a_{1:t})`，條件集的邊界就是 M 裡 0 與 -∞ 的分界線。

  如果訓練時偷看未來，loss 會很好看，部署時立刻露餡，因為 rollout 時未來還沒發生。

  這是那種「寫錯了不會報錯、只會默默騙你」的 bug。訓練指標漂亮得不合理的時候，先檢查 mask。
]

== Teacher forcing：平行訓練所有位置

#code(title: "training pairs")[
  ```text
  input : a_1, a_2, ..., a_t
  target: a_2, a_3, ..., a_{t+1}
  ```
]
#v(.25em)
#align(center)[
  #text(size: 1.05em)[$-log pi_theta (a_(2:T+1) | a_1) = sum_(t=1)^T -log pi_theta (a_(t+1) | a_(1:t))$]
]
#v(.25em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.teal, title: [訓練時], inset: 0.75em)[
    #set text(size: 0.82em)
    每一項都條件在 *真實前綴* 上；causal mask 讓一次 forward *同時算出全部 $T$ 項*
  ]
][
  #card(tint: palette.rose, title: [rollout 時], inset: 0.75em)[
    #set text(size: 0.82em)
    模型吃到的是 *自己前一步生成的 action* → 前一步錯了，輸入就不再像訓練資料
  ]
]
#v(.25em)
#callout(kind: "warn", compact: true)[錯誤可能一路累積，這叫 *distribution shift* 或 *compounding error*。]

#speaker-note[
  訓練時常用 teacher forcing：input 是 `a_1` 到 `a_t`，target 是整段 shift 一步的 `a_2` 到 `a_{t+1}`。它的數學根據就是本 Part 開頭那條自回歸分解：整段序列的 NLL 恆等於每步條件 NLL 的和，`-log π_θ(a_{2:T+1} | a_1) = Σ_t -log π_θ(a_{t+1} | a_{1:t})`。右邊每一項都條件在「真實前綴」上，而 causal mask 保證位置 t 的輸出恰好只依賴 `a_{1:t}`，所以一次 forward 就同時算出這 T 項，對它們的和做一次 backward，等於對序列 NLL 做嚴格的 gradient descent。平行不是近似，是分解式的逐項並行。這就是 Transformer 訓練快的原因。

  但 rollout 時，模型吃到的是自己前一步生成的 action。前一步錯了，下一步的輸入就不再像訓練資料。錯誤可能一路累積，這叫 distribution shift 或 compounding error。

  訓練和部署之間有一條隱形的裂縫。下一頁講一個 1980 年代就撞上這條裂縫的真車。
]

== ALVINN：1989 年就撞過的牆

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [CMU · 1980 年代末], icon: [🚗])[
    #set text(size: 0.85em)
    用神經網路開真車。\
    訓練資料：人類 *正常開在車道中央* 的\
    影像 + 方向盤操作。
  ]
][
  #card(tint: palette.rose, title: [問題])[
    #set text(size: 0.85em)
    人類示範裡很少有\
    「車已經偏出車道，*該怎麼救回來*」的資料。
    #v(.3em)
    一旦偏掉 → 進入沒覆蓋的 state → 更容易再錯
  ]
]
#v(.6em)
#align(center)[
  #pill(tint: palette.rose)[錯一步] → #pill(tint: palette.amber)[進入陌生 state] → #pill(tint: palette.rose)[更容易再錯] → #pill(tint: palette.night)[state 更陌生]
]

#speaker-note[
  ALVINN 是很好的歷史例子。1980 年代末，CMU 用神經網路開真車。訓練資料多半是人類正常開在車道中央的影像和方向盤操作。問題是人類示範裡很少有「車已經偏出車道，該怎麼救回來」的資料。模型一旦偏掉，就進入訓練資料沒覆蓋的 state，接下來更容易再錯。

  底下這個迴圈請記住：錯一步 → 進入陌生 state → 更容易再錯 → state 更陌生。這不是工程細節沒做好，是 BC 這個方法論本身的結構性弱點。下一頁看它的正式版本。
]

== 錯誤的複利：O(Tε) vs O(T²ε)

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [一般 supervised])[
    錯誤 *不影響後續輸入*
    #v(.3em)
    #align(center)[#text(size: 1.3em)[$O(T epsilon)$]]
    #v(.2em)
    #set text(size: 0.82em)
    T 步期望累積 cost 線性成長
  ]
][
  #card(tint: palette.rose, title: [BC rollout · Ross & Bagnell 2010])[
    每個錯誤把 state *帶離訓練分布*
    #v(.3em)
    #align(center)[#text(size: 1.3em)[$O(T^2 epsilon)$]]
    #v(.2em)
    #set text(size: 0.82em)
    骨架：第 $t$ 步首次犯錯機率 $<= epsilon$，之後最壞每步 cost 1、共 $T - t + 1$ 步
    #v(.15em)
    $EE["cost"] <= sum_(t=1)^T epsilon (T - t + 1) = epsilon (T (T+1)) / 2$
  ]
]
#v(.5em)
#callout(
  kind: "tip",
  compact: true,
)[*DAgger*（Ross, Gordon & Bagnell 2011）：讓模型 rollout、收集它闖進的怪 state、問老師「這裡該怎麼做」、加回訓練集，可壓回 $O(T epsilon)$ 量級。]

#speaker-note[
  這件事有正式結果（Ross & Bagnell, 2010），而且平方界的來源可以在黑板上三行推完。假設 policy 在訓練分布下每一步犯錯的機率至多 ε。如果錯誤不影響後續輸入，一般 supervised 的設定，每步期望 cost 至多 ε，T 步線性加總，O(Tε)。

  BC rollout 的差別在「犯錯之後」。最壞情況的建模是：只要一犯錯，state 就離開訓練分布，之後每一步都可能全錯，cost 記 1。把期望 cost 按「第一次犯錯發生在第 t 步」分解：這個事件的機率至多 ε，發生後剩下 T - t + 1 步每步 cost 1，所以 E[cost] ≤ Σ_t ε(T - t + 1) = ε·T(T+1)/2，量級 O(T²ε)。而且這不是分析太鬆，Ross 和 Bagnell 構造了一個具體的 MDP，讓這個平方下界真的被達到。整個推導裡讓平方冒出來的，就是「首次犯錯的時間 × 犯錯後殘餘的步數」這個乘積，也就是上一頁那個四格迴圈的數學化。

  DAgger（Ross, Gordon & Bagnell, 2011）的思路是把這個迴圈打斷：讓模型 rollout，收集它自己走到的奇怪 state，再問老師「這裡該怎麼做」，把修正資料加回訓練集。也就是補上模型自己會闖進去的 state 的標註。在可以持續請 expert 標註的假設下，DAgger 能把期望累積 cost 壓回 O(Tε) 量級。
]

== Temperature：推論時的旋鈕

#align(center)[
  #text(size: 1.25em)[$p_i (tau) = exp(z_i \/ tau) / (sum_j exp(z_j \/ tau))$]
  #v(.15em)
  #text(size: 0.85em)[兩兩比值 $p_i \/ p_j = exp((z_i - z_j) \/ tau)$，全部行為由它決定]
]
#v(.4em)
#row(gutter: .7em)[
  #card(tint: palette.iris, title: [τ → 0⁺])[
    收斂到 *argmax*\
    #set text(size: 0.82em)
    $z_i < z_max$ 時 $(z_i - z_max)\/tau arrow -infinity$，比值 → 0
  ]
][
  #card(tint: palette.teal, title: [τ = 1])[
    原始 softmax\
    #set text(size: 0.82em)
    照模型信心抽樣
  ]
][
  #card(tint: palette.amber, title: [τ → ∞])[
    趨近 *uniform*\
    #set text(size: 0.82em)
    所有比值 $exp((z_i - z_j)\/tau) arrow e^0 = 1$
  ]
]
#v(.5em)
#callout(kind: "danger", compact: true)[機器人 policy 通常不能太隨機，每個抖動都可能變成 *真實世界的碰撞*。]

#speaker-note[
  compounding error 講的是 rollout 時模型「看到」的輸入會漂移；rollout 還有另一頭的問題，模型「輸出」的時候，要怎麼從 `π_θ` 的分布裡挑出一個 action？永遠選機率最大的，還是照分布抽？這個選擇由 temperature 控制：p_i(τ) = exp(z_i/τ) / Σ_j exp(z_j/τ)。

  這個式子的全部行為藏在兩兩比值裡：p_i/p_j = exp((z_i − z_j)/τ)，分母消掉了，只剩 logits 差除以 τ。兩個極限都從它直接讀出來。τ → 0⁺：對任何 z_i 小於最大 logit 的 i，(z_i − z_max)/τ 趨向負無窮，比值趨向 0，機率全部集中到 argmax。τ → ∞：所有比值都趨向 e⁰ = 1，K 個類別兩兩等比，只能是 uniform，每個 1/K。τ 小，分布尖，模型更常選最有把握的 token；τ 大，分布平，探索變多，也更可能跳出奇怪 action。

  聊天機器人調高 temperature 頂多講話比較跳，機器人 policy 通常不能太隨機，因為每個抖動都可能變成真實世界的碰撞。同一個數學旋鈕，在不同 domain 的風險完全不同。
]

= Part 3 · 視覺表示

== Lab 3：輸入是一張圖

#row(widths: (1.2fr, 1fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [basic_vision_representation · lerobot/pusht_image], icon: [📷])[
    #set text(size: 0.85em)
    任務仍是 Push-T，這次：
    #v(.25em)
    #align(center)[#pill(tint: palette.iris)[96×96 RGB image_t] → #pill(tint: palette.amber)[action_t (x, y)]]
    #v(.25em)
    先不處理 action history、不處理語言
  ]
][
  #card(tint: palette.teal, title: [專心問一件事])[
    #set text(size: 0.9em)
    影像怎麼變成\
    policy 能用的 *representation*？
  ]
]
#v(.5em)
#row(
  gutter: .8em,
  stat([96×96×3], [輸入像素]),
  stat([27648], [攤平後的數字量], tint: palette.rose),
  stat([2], [輸出維度 (x, y)], tint: palette.teal),
)

#speaker-note[
  Part 2 為了看清楚序列，把 state 整個拿掉，只剩 action 自己預測自己。現在把 state 加回來，而 Push-T 真正的 state 是一張影像。第三個 lab 是 `basic_vision_representation`，用 `lerobot/pusht_image`。任務仍然是 Push-T，這次輸入是一張 96×96 RGB 圖，輸出下一個 (x, y) action。

  這段先不處理 action history，也不處理語言，專心問一件事：影像怎麼變成 policy 能用的 representation。

  一張 96×96×3 的圖有 27648 個數字。當然可以攤平成長向量丟進 MLP，但下一頁告訴你為什麼這樣做浪費了什麼。
]

== 為什麼不能直接攤平

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [圖像有強規律])[
    #set text(size: 0.85em)
    - 相鄰像素通常 *相關*
    - 同一個局部形狀可能出現在 *不同位置*
    - 小邊緣 → 角 → 部件 → 物體
    - 物體位置會影響 action
  ]
][
  #card(tint: palette.teal, title: [兩條路把規律用起來])[
    #set text(size: 0.85em)
    *CNN*：把規律 *寫進架構*\
    （局部性、weight sharing）
    #v(.3em)
    *ViT*：把圖切成 patch tokens，\
    用 attention *學* patch 之間的關係
  ]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[攤平丟進 MLP 不是不能算，是 *浪費了圖像結構*]
// #v(.35em)
// #row(
//   gutter: .8em,
//   stat([27648 × 256 ≈ 7.1M], [攤平接一層 FC 的權重量], tint: palette.rose),
//   stat([3·3·3·32 + 32 = 896], [一層 3×3 conv (3→32)], tint: palette.teal),
//   stat([≈ 7900×], [參數量比], tint: palette.amber),
// )

#speaker-note[
  當然可以攤平成長向量丟進 MLP，但先把帳算出來：攤平後 27648 維，接一層 256 個神經元的全連接層，光這一層權重就是 27648 × 256 ≈ 7.1M 顆參數。對照一層 3×3、輸入 3 channel、輸出 32 channel 的卷積：3×3×3×32 + 32 = 896 顆。差了大約 7900 倍。而且全連接那 7.1M 顆權重裡，「左上角的邊緣偵測」跟「右下角的邊緣偵測」是兩組完全獨立的參數，同一個知識要學兩次。

  參數多不只是慢，是需要的資料量跟著多，每一組獨立權重都要有足夠樣本去約束它。圖像本身有強規律：相鄰像素通常相關；同一個局部形狀可能出現在不同位置；小邊緣組成角，角組成部件，部件組成物體；物體位置會影響 action。攤平等於把這些規律全部丟掉，逼模型用資料重新發現一遍。

  CNN 把這些規律寫進架構，上面那個 7900 倍就是這麼來的。ViT 則把圖像切成 patch tokens，再用 attention 學 patch 之間的關係。這一節就講這兩條路，最後你會看到它們殊途同歸：都是把 raw pixels 變成 representation。
]

== 一個 3×3 kernel 的手算

#row(widths: (1fr, 1fr, 1.2fr), gutter: 1em)[
  #card(tint: palette.teal, title: [灰階圖：左黑右白])[
    #set text(size: 0.8em)
    ```text
    0 0 0 1 1 1
    0 0 0 1 1 1
    0 0 0 1 1 1
    0 0 0 1 1 1
    ```
  ]
][
  #card(tint: palette.iris, title: [垂直邊緣 kernel])[
    #set text(size: 0.8em)
    ```text
    -1  0  1
    -1  0  1
    -1  0  1
    ```
  ]
][
  #card(tint: palette.amber, title: [滑過去看內積])[
    #set text(size: 0.82em)
    - 全黑區：內積 = 0
    - *黑白交界：內積變大* ✨
    - 全白區：正負抵消 → 0
  ]
]
#v(.6em)
#quote-card(tint: palette.iris)[kernel 是 *局部模板比對器*：滑過整張圖，看到像自己的局部形狀就亮。]

#speaker-note[
  先不要從四重求和公式開始。從一個 3×3 kernel 開始。

  灰階圖左半黑、右半白。垂直邊緣 kernel 是左欄 -1、中欄 0、右欄 +1。蓋在全黑區，內積是 0；蓋在黑白交界，內積變大；蓋在全白區，正負抵消又回到 0。

  kernel 是局部模板比對器，滑過整張圖，看到像自己的局部形狀就亮。

  這又是內積，注意，這是今天第三次了：線性分類器用內積比輸入跟 class template；CNN 用內積比 local patch 跟 kernel；attention 用內積比 query 跟 key。三個看起來不同的架構，共用同一個原子操作。
]

== 卷積公式、cross-correlation 與 weight sharing

#card(title: [完整公式], inset: 0.6em)[
  #align(center)[$y[u, v, c_"out"] = sum_(i, j, c_"in") K[i, j, c_"in", c_"out"] thin x[u + i, v + j, c_"in"]$]
]
#v(.3em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.amber, title: [名字的小秘密], inset: 0.7em)[
    #set text(size: 0.76em)
    嚴格說這是 *cross-correlation*：訊號處理的 convolution 會先翻轉 kernel。深度學習一律用不翻轉版，kernel 是學出來的，翻不翻只差重新參數化。
  ]
][
  #card(tint: palette.teal, title: [weight sharing ⇒ 平移等變], inset: 0.7em)[
    #set text(size: 0.76em)
    令平移 $(T_delta x)[u] = x[u - delta]$，代入公式即得
    #align(center)[$(T_delta x) star K = T_delta (x star K)$]
    輸入平移，feature map *跟著平移*，「左上角有用、右下角也有用」的精確版。
  ]
]
#v(.2em)
#callout(
  kind: "info",
  compact: true,
)[blur / sharpen / edge kernel 是 *人設計的*；CNN 的關鍵：kernel 數字 *由梯度下降學出來*。]

#speaker-note[
  卷積公式可以最後再放，它只是把「kernel 滑過圖、每個位置做內積」寫成四重求和而已，直覺都在前一頁。

  嚴格說這個式子是 cross-correlation：訊號處理定義的 convolution 會先把 kernel 翻轉再滑。深度學習框架一律用不翻轉的版本，kernel 是學出來的，翻不翻只差一個重新參數化，但名字沿用了 convolution。知道這件事，以後看訊號處理的書才不會精神錯亂。

  同一組 kernel 在整張圖上滑動，這叫 weight sharing，而它買到的性質可以寫成定理：卷積對平移是等變的。定義平移運算子 `(T_δ x)[u] = x[u − δ]`，把它代進卷積公式：`((T_δ x) ⋆ K)[u] = Σ K[i]·x[u + i − δ]`，換元 `u' = u − δ`，右邊就是 `(x ⋆ K)[u − δ]`，也就是 `T_δ(x ⋆ K)[u]`。先平移再卷積，等於先卷積再平移，輸入裡的物體移動了，feature map 上的響應原封不動地跟著移動。「偵測垂直邊緣的濾鏡在左上角有用、右下角也有用」這句話的精確版就是這條等式，而全連接層不滿足它，這正是那 7900 倍參數在補償的東西。

  傳統影像處理的 blur、sharpen、edge kernel 是人設計的。CNN 的關鍵是：kernel 數字由梯度下降學出來。
]

== SmallCNN：解析度換 channel

#row(widths: (1.1fr, 1fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [四層 stride=2])[
    #align(center)[
      #pill(tint: palette.iris)[96] → #pill(tint: palette.iris)[48] → #pill(tint: palette.teal)[24] → #pill(tint: palette.amber)[12] → #pill(tint: palette.rose)[6]
    ]
    #v(.3em)
    #set text(size: 0.78em)
    receptive field 可遞推：$r_l = r_(l-1) + (k - 1) j_(l-1)$，$j_l = s j_(l-1)$\
    3×3、stride 2 四層：$r: 1 arrow 3 arrow 7 arrow 15 arrow 31$，末層一格看 *31×31* 像素
    #v(.25em)
    最後 `AdaptiveAvgPool2d(1)`：6×6×C → C 維向量 → 線性層 → action
  ]
][
  #card(tint: palette.teal, title: [lab 的三個詞])[
    #set text(size: 0.82em)
    #table(
      columns: (auto, 1fr),
      [stride], [每次滑幾格；`stride=2` 寬高約減半],
      [padding], [邊界補 0，控制輸出大小、讓邊緣被掃到],
      [channel], [RGB 3 個 in；卷積層可輸出多個 feature channels],
    )
  ]
]

#speaker-note[
  lab 會看到三個詞。stride：每次滑幾格，stride=2 會讓寬高約減半。padding：邊界補 0，控制輸出大小，也讓邊緣被掃到。channel：RGB 有 3 個 input channel；卷積層可輸出多個 feature channels。

  `SmallCNN` 用四層 stride=2：96 → 48 → 24 → 12 → 6。解析度降低，channel 增加。「後層看得比較廣」不用停留在口號，receptive field 可以逐層遞推：令 `r_l` 是第 l 層一個 cell 對應回輸入的視野邊長，`j_l` 是相鄰兩個 cell 在輸入上的間距（jump）。每疊一層 kernel 大小 k、stride s 的卷積，視野增加 (k−1) 乘上當前 jump，因為 kernel 多蓋住的 k−1 個 cell，每個在輸入上相隔 `j_{l-1}`，所以 `r_l = r_{l-1} + (k−1)·j_{l-1}`，而 jump 每過一層乘上 stride：`j_l = s·j_{l-1}`。

  代進 SmallCNN：初始 r=1、j=1，四層 3×3、stride 2 依序給出 j = 2, 4, 8, 16，r = 3, 7, 15, 31。所以最後一層 feature map 上一格，看的是輸入上 31×31 的區域，在 96×96 的圖上大約三分之一邊長，夠覆蓋 T 形物塊加推桿的局部關係，但看不到整張桌面；整張圖的整合交給最後的 `AdaptiveAvgPool2d(1)`，把 6×6×C 平均成 C 維向量，再接線性層輸出 action。以後看到任何 CNN 架構，這兩條遞推式都能讓你在紙上直接算出它「看多遠」。
]

== Encoder 的觀念

#align(center)[
  #v(.6em)
  #text(size: 1.2em)[$pi_theta = f_psi compose phi_w, quad phi_w: RR^(27648) -> RR^C, quad f_psi: RR^C -> RR^2$]
  #v(.4em)
  #pill(tint: palette.rose)[raw pixels] #h(.6em) #text(size: 1.2em)[→] #h(.6em) #pill(
    tint: palette.iris,
  )[representation $z = phi_w (x)$] #h(.6em) #text(size: 1.2em)[→] #h(.6em) #pill(tint: palette.teal)[action]
  #v(.6em)
]
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [端到端 = 一條 chain rule])[
    #set text(size: 0.82em)
    $nabla_w L = (partial L)/(partial f) (partial f)/(partial z) (partial z)/(partial w)$
    #v(.2em)
    loss 的梯度 *穿過 $f_psi$ 傳回 encoder* ，\
    representation 是被 action loss 逼出來的，不是人工特徵
  ]
][
  #card(tint: palette.amber, title: [VLA 裡的 vision encoder])[
    #set text(size: 0.85em)
    *同一個角色*，只是更大、資料更多、\
    輸出從一個向量變成一串 tokens\
    （$RR^C arrow RR^(M times C)$）
  ]
]

#speaker-note[
  這裡真正要帶走的是 encoder 觀念，而它可以寫成一條精確的合成式：π_θ = f_ψ ∘ φ_w。φ_w 把 27648 維的 raw pixels 壓成 C 維的 representation z，f_ψ 把 z 映到 2 維 action，θ 就是 (w, ψ) 的合稱。

  「端到端訓練」這四個字的數學內容只是 chain rule：`∇_w L = (∂L/∂f)(∂f/∂z)(∂z/∂w)`。loss 對 action 頭的梯度會一路乘穿 f_ψ，傳回 encoder 的每一顆卷積 kernel。這句話的份量在於對照：傳統 pipeline 是人先設計特徵（邊緣、角點、顏色直方圖），再在特徵上訓練 policy，特徵固定，梯度傳不進去。端到端的意思是 z 本身是可微分變數的函數，「什麼特徵對預測 action 有用」由同一個 loss 決定。saliency 那頁看到模型盯著 T 塊和推桿，就是這條梯度長期作用的結果。

  VLA 裡的 vision encoder 是同一個 φ，只是更大、資料更多，而且輸出從一個 pooled 向量變成一串 M 個 tokens，從 R^C 變成 R^(M×C)，好讓後面的 attention 可以逐 patch 查詢。今天 lab 裡那個四層小 CNN 跟 OpenVLA 裡的 vision backbone，在系統圖上是同一個方塊。把方塊的型別簽名搞清楚，比記住方塊裡面用哪個架構重要。
]

== Saliency：看模型對哪些像素敏感

#row(widths: (1.15fr, 1fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [input-gradient saliency])[
    #align(center)[$"saliency"["pixel"] = |partial thin "scalar" \/ partial thin "pixel"|$]
    #v(.25em)
    #set text(size: 0.78em)
    根據是一階 Taylor：$g(x + delta) = g(x) + nabla_x g dot delta + o(norm(delta))$，saliency 讀的是 *線性項的係數大小*。
    #v(.25em)
    輸出是 2 維 action，梯度要對 *scalar* 取 →\
    lab 取 `f(x).abs().sum()`（預測 action 的 L1 norm）；\
    對每像素求偏導、取絕對值、RGB 三 channel 平均 → 一張 H×W 熱圖
  ]
][
  #card(tint: palette.amber, title: [是 debug 工具，不是真理])[
    #set text(size: 0.82em)
    ✓ 提醒模型可能在看推桿、T 塊，\
    #h(1em) 或 *背景捷徑*
    #v(.3em)
    ✗ 只回答局部問題：「目前這個輸入附近，哪些像素影響大？」
  ]
]

#speaker-note[
  encoder 訓練完，自然想問一個問題：模型做決定時，到底在看畫面的哪裡？CNN 沒有 attention 權重可以直接拿出來看，lab 改用 input-gradient saliency 回答這個問題。

  梯度要對一個 scalar 取，但模型輸出是 2 維 action，所以要先把輸出縮成一個數：lab 裡取的是 f_θ(x).abs().sum()，也就是預測 action 的 L1 norm；對每個像素求偏導、取絕對值，再對 RGB 三個 channel 取平均，得到一張 H×W 的圖。意思是：一階近似下，微調這個像素會讓預測值變動多少。變化大的地方，代表模型對那區域敏感。

  saliency 是 debug 工具，不是真理。它可以提醒模型可能看推桿、看 T 形物塊，或看背景捷徑。但它回答的是局部問題：「在目前這個輸入附近，哪些像素影響大？」不要拿它當「模型在想什麼」的完整答案。
]

== ViT：把圖像變成 patch tokens

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [patchify])[
    #set text(size: 0.85em)
    96×96 圖、`patch_size=12`：
    #v(.2em)
    #align(center)[$8 times 8 = 64 "patches"$]
    #v(.2em)
    每個 patch 攤平成 $12 dot 12 dot 3 = 432$ 維，\
    乘 $W_E in RR^(432 times C)$ → embedding\
    ，還是 Part 1 那行 $W x$
  ]
][
  #card(tint: palette.teal, title: [token 序列])[
    #set text(size: 0.85em)
    #align(center)[
      #pill(tint: palette.amber)[CLS] #pill(tint: palette.teal)[p₁] #pill(tint: palette.teal)[p₂] #text(
        size: .8em,
      )[⋯] #pill(tint: palette.teal)[p₆₄]
    ]
    #v(.25em)
    `CLS` token 負責 *總結整張圖*；\
    加上 position embedding 後進 self-attention\
    ，公式跟 Part 2 一字不差，$65^2$ 對相似度
  ]
]
#v(.5em)
#callout(kind: "info", compact: true)[到這裡，「圖像」跟「序列」在模型眼裡已經是同一種東西：*一串 tokens*。]

#speaker-note[
  CNN 是第一條路：把圖像的規律寫死在架構裡。第二條路完全不同，什麼先驗都不寫，把圖像變成 Part 2 已經很熟的東西：一串 tokens。這就是 ViT。它的第一步是 patchify，維度帳可以完整記清楚：96×96 的圖、patch_size=12，就是 8×8 = 64 個 patches；每個 patch 是 12×12×3 = 432 個數字，攤平後乘上一個 432×C 的投影矩陣 W_E 變成 C 維 embedding，注意這又是 Part 1 那行 Wx，patchify 沒有引入任何新運算。再加一個 CLS token 負責總結整張圖，共 65 個 tokens；patch 攤平後順序資訊消失，所以跟 Part 2 的 action 序列一樣要加 position embedding。

  接著進 self-attention。公式跟 Part 2 一字不差，QK^T 現在是 65×65：每個 patch 對其他每個 patch 算一次內積相似度。

  注意這件事的份量：到這裡，「圖像」跟「序列」在模型眼裡已經是同一種東西，一串 tokens。這就是為什麼 VLA 可以把影像、文字、動作丟進同一個 Transformer，它們在進模型之前都先被變成了 tokens。
]

== Mask 取決於資料，不取決於 Transformer

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.amber, title: [時間序列 · causal mask])[
    #set text(size: 0.85em)
    時間有「未來」，部署時未來還沒發生\
    → *要遮*
    #v(.25em)
    $mat(1, 0, 0; 1, 1, 0; 1, 1, 1)$
  ]
][
  #card(tint: palette.teal, title: [圖像 patch · full self-attention])[
    #set text(size: 0.85em)
    patch 7 看 patch 42 *不叫偷看答案*\
    → 不遮，每個 patch attend to 每個 patch
    #v(.25em)
    $mat(1, 1, 1; 1, 1, 1; 1, 1, 1)$
  ]
]
#v(.6em)
#quote-card(
  tint: palette.iris,
)[Transformer $eq.not$ language model，attention 不一定要 causal mask。\ mask 取決於 *資料關係*。]

#speaker-note[
  同一條 attention 公式，卻有一個地方跟 Part 2 唱反調：Part 2 說 causal mask 是底線，ViT 卻完全不遮。這個對照很重要。圖像 patch 沒有「未來」這件事，patch 7 看 patch 42 不叫偷看答案。所以 ViT 用 full self-attention：每個 patch 都可以 attend to 每個 patch。

  Transformer 不等於 language model，attention 也不一定要 causal mask。mask 取決於資料關係：時間序列有未來，所以遮；圖像 patch 沒有部署時不可見的未來，所以不遮。

  Part 4 的 VLA decoder 會把兩種 mask 用在同一個模型裡，action 對 action 是 causal，action 對影像語言是全開。現在把這個原則抓住，到時候一眼就看懂。
]

== Pretraining：真實 VLA 不從零學視覺

#row(widths: (1.1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [兩階段最佳化，同一組參數])[
    #set text(size: 0.8em)
    ① $w^* = arg min_w thin L_"pre" (w; D_"pre")$
    #v(.2em)
    ② 從 $(w^*, psi_0)$ 出發 minimize $L_"BC" (w, psi; D_"robot")$
    #v(.25em)
    fine-tune 改的是 *初始點*，不是 loss 的定義，\
    第二階段仍是 Part 0 那條 BC loss
  ]
][
  #card(tint: palette.teal, title: [為什麼非這樣不可])[
    #set text(size: 0.78em)
    #table(
      columns: (auto, 1fr),
      [$|w|$], [encoder 參數 $~10^8 tilde 10^9$],
      [$|D_"pre"|$], [圖文對 $~10^9$],
      [$|D_"robot"|$], [軌跡 $~10^3 tilde 10^6$],
    )
    每組參數都要樣本約束（Part 3 開頭那筆帳）\
    → 億級參數的 $w$ *只有 $D_"pre"$ 付得起*
  ]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[lab 從亂數練小 CNN/ViT 是教學設定。真實 VLA：pretraining 決定 $w$ 的起點，robot 資料只負責把表示 *接到 action*。]

#speaker-note[
  兩條路都講完了，離開 Part 3 之前把最後一件事對齊現實，而且這件事可以寫成式子，不必停在「先學常識再學開挖土機」的類比。用上一頁的記號：encoder 參數 w、action 頭參數 ψ。pretraining 是第一階段最佳化：在巨量資料 D_pre 上解 `w* = argmin L_pre(w)`，L_pre 可能是影像分類、圖文對比、下一個字預測，重點是它不需要機器人資料。fine-tuning 是第二階段：從初始點 `(w*, ψ_0)` 出發，在 D_robot 上 minimize 我們的 BC loss。注意 fine-tune 改變的只是最佳化的初始點，loss 還是 Part 0 那條 -log π_θ(a|s)，一個字都沒變。

  為什麼非這樣不可？把三個數量級擺在一起：現代 vision encoder 的 w 有 10^8 到 10^9 顆參數；D_pre 是 10^9 量級的圖文對；D_robot 撐死 10^3 到 10^6 條軌跡。Part 3 開頭算 7900 倍那筆帳的原則在這裡再用一次，每組獨立參數都需要足夠樣本去約束它。拿 10^4 條軌跡去約束 10^9 顆參數，等式兩邊差了五個數量級，怎麼訓練都是欠定的；只有 D_pre 付得起這筆帳。所以分工是被算術逼出來的：pretraining 用便宜的大資料把 w 定到一個好的起點，robot 資料只需要負責「把表示接到 action」這件小得多的事。

  這也回答了「ViT 小資料吃虧怎麼辦」：完整答案不是「所以不用 ViT」，而是「所以 ViT 幾乎總是先預訓練」。CNN 把局部性寫進架構、小資料穩，ViT 把先驗換成資料量，pretraining 就是那個資料量的來源。

  RT-2、OpenVLA、π0 為什麼可行，根子也在這裡。語言指令「拿起絕種的動物」能泛化到恐龍玩具，不是機器人資料裡教過每個恐龍，而是 `w*` 從 D_pre 帶進了世界知識，D_robot 只教了怎麼把它接到手臂上。
]

== Part 3 收束

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [CNN])[
    #align(center)[
      #set text(size: 0.82em)
      #pill(tint: palette.iris)[local filters] \ #v(.15em) ↓ \ #v(.15em)
      #pill(tint: palette.iris)[feature maps] \ #v(.15em) ↓ \ #v(.15em)
      #pill(tint: palette.iris)[pooled vector]
    ]
  ]
][
  #card(tint: palette.teal, title: [ViT])[
    #align(center)[
      #set text(size: 0.82em)
      #pill(tint: palette.teal)[patches] → #pill(tint: palette.teal)[tokens] \ #v(.15em) ↓ \ #v(.15em)
      #pill(tint: palette.teal)[full self-attention] \ #v(.15em) ↓ \ #v(.15em)
      #pill(tint: palette.teal)[representation]
    ]
  ]
]
#v(.5em)
#align(center)[兩者都是把 *raw pixels* 轉成 policy 可用的 *representation*。]

#speaker-note[
  Part 3 收束。CNN 這條路：local filters → feature maps → pooled vector。ViT 這條路：patches → tokens → full self-attention → representation。

  兩者都是把 raw pixels 轉成 policy 可用的 representation。架構哲學不同，CNN 把先驗寫死在架構裡，ViT 把一切交給資料，但在系統圖上，它們是同一個方塊：vision encoder。回去把依賴圖上 vision encoder 和 pretraining 打勾，我們進入最後的組裝階段。
]

= Part 4 · VLA-shaped BC

== Homework：smol-libero

#row(widths: (1.2fr, 1fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [HuggingFaceVLA/smol-libero], icon: [🤖])[
    #set text(size: 0.85em)
    影像 + 語言指令 + *7 維機械手臂 action*
    #v(.35em)
    #align(center)[#text(size: 1.05em)[$pi_theta (a_(t+1) | "image"_t, "instruction", a_(1:t))$]]
    #v(.35em)
    #align(center)[image + instruction + action_history → next_action]
  ]
][
  #card(tint: palette.amber, title: [定位要放對])[
    #set text(size: 0.85em)
    ✗ 不是要訓練可部署機器人
    #v(.25em)
    ✓ 是讓你 *看懂 VLA 的資料流*
  ]
]
#v(.5em)
#callout(kind: "info", compact: true)[它仍然是 BC。*只是 context 變大了。*]

#speaker-note[
  week2 homework 用 `HuggingFaceVLA/smol-libero`。資料裡有影像、語言指令、7 維機械手臂 action。這不是要訓練可部署機器人，而是讓你看懂 VLA 的資料流。

  形式：image + instruction + action_history → next_action。更精確：π_θ(a_{t+1} | image_t, instruction, a_{1:t})。

  它仍然是 BC。只是 context 變大了。這句話是 Part 4 的主旋律，每一頁都會回來確認一次。
]

== 三條輸入：vision、language、action history

#row(gutter: .8em)[
  #card(tint: palette.iris, title: [Vision], icon: [👁])[
    #set text(size: 0.8em)
    image → $v_1, ..., v_M$\
    #v(.2em)
    經過 vision encoder\
    變成 patch / feature tokens
    #v(.3em)
    回答：*我看到了什麼？*
  ]
][
  #card(tint: palette.teal, title: [Language], icon: [💬])[
    #set text(size: 0.8em)
    "put the red block on the plate"\
    → $l_1, ..., l_L$
    #v(.2em)
    文字進模型前也要 tokenization
    #v(.3em)
    回答：*人叫我做什麼？*
  ]
][
  #card(tint: palette.amber, title: [Action history], icon: [🦾])[
    #set text(size: 0.8em)
    $a_1, ..., a_t$\
    #v(.2em)
    tokenized 或投影成\
    action embeddings，丟進 decoder
    #v(.3em)
    回答：*我做到哪一步了？*
  ]
]
#v(.5em)
#callout(
  kind: "tip",
  compact: true,
)[進 decoder 前全部變成同一種東西：條件集是一串 tokens $[v_(1:M); thin l_(1:L); thin a_(1:t)]$，長度 $M + L + t$，拿掉哪一段，$pi_theta$ 的條件就少哪一種依據。]

#speaker-note[
  三條輸入，最後都會變成 tokens。vision：影像經過 vision encoder，變成 M 個 patch tokens 或 feature tokens。language："put the red block on the plate" 這樣的指令，進模型前也要 tokenization，變成 L 個 tokens。action history：過去 t 步 action 被 tokenized 或投影成 action embeddings。所以 decoder 面前的條件集可以精確寫下來：一串長度 M + L + t 的 token 序列 [v_1..v_M; l_1..l_L; a_1..a_t]，Part 0 那個 π_θ(a|s) 的 s，到這裡具體化成這一串。

  decoder 要同時回答三個問題：我看到了什麼？人叫我要做什麼？我剛剛做到了哪一步？三段各對應一個問題，拿掉哪一段，條件分布就退化成少一種依據的版本，這不是比喻，是條件集的集合運算。

  現場可以打開 tokenizer demo，輸入 put the red block on the plate，大家會看到句子被切成 token，每個 token 有 id。
]

== 文字 token 與 action token 完全同型

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [文字])[
    #align(center)[
      #set text(size: 0.8em)
      #pill(tint: palette.teal)[文字] → #pill(tint: palette.teal)[token id] → #pill(tint: palette.teal)[embedding table] → #pill(tint: palette.teal)[向量]
    ]
    #v(.25em)
    #set text(size: 0.82em)
    $e_i^top E_"text", quad E_"text" in RR^(V_"text" times C)$ · vocab 來自 *tokenizer*
  ]
][
  #card(tint: palette.amber, title: [action])[
    #align(center)[
      #set text(size: 0.8em)
      #pill(tint: palette.amber)[action] → #pill(tint: palette.amber)[token id] → #pill(tint: palette.amber)[embedding table] → #pill(tint: palette.amber)[向量]
    ]
    #v(.25em)
    #set text(size: 0.82em)
    $e_j^top E_"act", quad E_"act" in RR^(256 times C)$ · vocab 來自 *離散化*
  ]
]
#v(.6em)
#card(tint: palette.iris, title: [把 LLM 放回地圖], icon: [🗺])[
  #set text(size: 0.85em)
  ChatGPT 的 base model = Part 2 的「用過去 token 預測下一個 token」：token 換成文字、資料換成大規模文本、模型放大很多。產品化前還有 instruction tuning、RLHF 等 post-training，但那改變的是它 *偏好輸出什麼*，autoregressive 骨架不變。
]

#speaker-note[
  這跟 Part 2 的 action token 完全同型，而且「同型」可以寫成同一條式子：兩邊都是 one-hot 乘 embedding table，`e_i^T E`。差別只在那張表的列數，E_text 是 V_text × C，vocab 來自 tokenizer，V_text 通常幾萬；E_act 是 256 × C，vocab 來自我們對動作空間的離散化。輸出都是 C 維向量，進了 decoder 之後不分彼此。

  這裡要直接把 LLM 放回地圖裡。ChatGPT 的 base model 就是 Part 2 的「用過去 token 預測下一個 token」，token 換成文字、資料換成大規模文本、模型放大很多；產品化之前還會經過 instruction tuning、RLHF 這類 post-training，但那改變的是它偏好輸出什麼，autoregressive 骨架不變。今天已經看過這個骨架的每個零件：embedding、position、Transformer、causal mask、cross-entropy。

  真實 VLA 的 language encoder 通常是預訓練 LLM/VLM 的一部分。lab 裡的小 encoder 是教學替身，讓你看清楚資料流。
]

== 7 維 action 怎麼 tokenized

#align(center)[
  #pill(tint: palette.amber)[x] #pill(tint: palette.amber)[y] #pill(tint: palette.amber)[z] #pill(
    tint: palette.teal,
  )[roll] #pill(tint: palette.teal)[pitch] #pill(tint: palette.teal)[yaw] #pill(tint: palette.rose)[gripper]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [硬合成一個聯合 token])[
    $"vocab" = "bins"^7 = 32^7 approx 3.4 times 10^10$
    #v(.2em)
    #set text(size: 0.85em)
    大到 *不可用*
  ]
][
  #card(tint: palette.teal, title: [homework：每軸各自離散化])[
    軸 $d$ → token $in {0, ..., 31}$
    #v(.2em)
    #set text(size: 0.85em)
    輸出形狀 `(B, T, 7, bins_per_dim)`\
    loss = 7 個軸的 cross-entropy 平均
  ]
]
#v(.4em)
#row(
  gutter: .8em,
  stat([32⁷ ≈ 3.4×10¹⁰], [聯合 vocab], tint: palette.rose),
  stat([7 × 32 = 224], [per-axis 輸出], tint: palette.teal),
)

#speaker-note[
  Push-T action 是 2 維 (x, y)，可以合成一個聯合 token：vocab_size = bins_per_dim 平方。LIBERO action 是 7 維：x、y、z、roll、pitch、yaw、gripper。

  如果硬合成一個 token，vocab_size 是 bins_per_dim 的 7 次方。bins_per_dim = 32 時，這個 vocab 大到不可用，三百四十億個類別。

  所以 homework 採用每個 action 軸各自離散化：每軸一個 token，落在 0 到 31。模型輸出形狀 (B, T, 7, bins_per_dim)：每個 batch、每個時間步、每個 action 軸，各自預測一個分類分布。loss 是 7 個軸的 cross-entropy 平均。
]

== Per-axis 分解：假設了什麼、換到了什麼

#align(center)[
  #text(size: 1.2em)[$p(a | "context") = product_d p(a_d | "context")$]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [假設：給定 context 後各軸條件獨立])[
    #set text(size: 0.85em)
    不完全成立，接近物體時\
    z 和 gripper 顯然相關
  ]
][
  #card(tint: palette.teal, title: [為什麼還是划算])[
    #set text(size: 0.85em)
    相關性有一部分已被 *context 吸收*；\
    剩下的建模損失，換來輸出空間\
    從 $32^7$ 降到 $7 times 32$
  ]
]
#v(.5em)
#callout(
  kind: "tip",
  compact: true,
)[這是一次 tradeoff 分析，讀論文時這部份很重要。]

#speaker-note[
  這個取捨可以講得很精確：各軸獨立輸出分布、loss 各自算，等於把聯合分布分解成 p(a | context) = Π_d p(a_d | context)。也就是假設給定 context 之後各軸條件獨立。

  這個假設不完全成立，例如接近物體時 z 和 gripper 顯然相關，但相關性有一部分已經被 context 吸收，剩下的建模損失換來的是輸出空間從 32 的 7 次方降到 7 × 32。

  讀論文時你會一直遇到這種「分解假設」。評估的方法就是這一頁：它假設了什麼？假設哪裡會破？破掉的代價換到了什麼？三個問題問完，你就有自己的判斷。
]

== Action chunking：看一眼，做一段

#code(title: "training sample")[
  ```text
  input actions : a_t,     a_{t+1}, ..., a_{t+B-1}
  target actions: a_{t+1}, a_{t+2}, ..., a_{t+B}
  ```
]
#v(.4em)
#align(center)[
  #text(
    size: 1.05em,
  )[chunk 內第 $k$ 步：$pi_theta (a_(t+k+1) | "image"_t, "instr", a_(1:t+k))$，影像下標 *凍結在 $t$*]
]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [買到的：計算省 B 倍])[
    #set text(size: 0.85em)
    每步重看：一個 chunk 跑 *$B$ 次* vision encoder\
    開頭看一次：只跑 *1 次*\
    encoder 是全模型最貴的零件，這筆帳直接除以 $B$
  ]
][
  #card(tint: palette.rose, title: [付出的：畫面過時 $k$ 步])[
    #set text(size: 0.85em)
    真實 state 已走到 $t+k$，條件裡的影像還停在 $t$\
    → 這 $k$ 步的動態 *只能靠 $a_(t:t+k)$ 回推*，\
    $B$ 越大、要回推的越多
  ]
]

#speaker-note[
  token 的事定案了，接下來看一筆訓練樣本長什麼樣。homework 的訓練樣本拿一張影像、一句指令、一段長度 block_size 的 action history，預測 shift 一步後的 target，跟 Part 2 的 teacher forcing 完全同型。

  「影像只在 chunk 開頭看一次」這個設計，精確的寫法是把條件分布裡的影像下標凍結：chunk 內第 k 步，模型算的是 π_θ(a_{t+k+1} | image_t, instr, a_{1:t+k})，注意影像是 image_t，不是 image_{t+k}。兩邊的帳都算得出來。買到的：如果每步都重看，一個長度 B 的 chunk 要跑 B 次 vision encoder；開頭看一次就只跑 1 次。vision encoder 是整個模型參數最多、計算最貴的零件，所以這筆帳是實打實地把最大開銷除以 B。付出的：執行到第 k 步時，真實世界的 state 已經走到 t+k，但條件裡的影像還停在 t，過時了 k 步，這 k 步之間物塊被推到哪、手臂移到哪，模型只能從自己剛輸出的 a_t 到 a_{t+k} 回推。B 越大省得越多，但要靠 action history 回推的動態也越長，錯誤累積的空間跟著變大。B 就是這條 tradeoff 曲線上的操作點。

  「看一眼、做一段」這個 pattern 在真實系統裡非常普遍，Part 5 講 ACT 的時候，你會發現它的名字就叫 action chunking。
]

== Cross-attention：decoder 查詢多模態 context

#row(widths: (1.15fr, 1fr), gutter: 1.1em)[
  #card(tint: palette.iris, title: [Q 來自 action，K/V 來自 context])[
    #set text(size: 0.82em)
    $"context" = [v_1, ..., v_M, l_1, ..., l_L]$
    #v(.25em)
    $Q = "action" thin W_Q, quad K = "context" thin W_K, quad V = "context" thin W_V$
    #v(.25em)
    $"CrossAttn" = "softmax"((Q K^top) / sqrt(d_k)) V$
    #v(.25em)
    $Q in RR^(T_a times d_k)$，$K, V in RR^((M+L) times d_k)$ → 權重 $in RR^(T_a times (M+L))$，*每列在 context 上加總為 1*
  ]
][
  #card(tint: palette.teal, title: [心智圖], icon: [🗃])[
    #set text(size: 0.85em)
    action decoder 在 *問問題*，\
    影像和語言提供 *資料庫*。
    #v(.3em)
    cross-attention 權重 = 模型當下\
    從 context *借資訊的分配*
  ]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[某一步 action 問：「我現在該往哪裡移動？」影像 patch 給物體位置、語言 token 給任務目標、歷史 action 給目前進度。]

#speaker-note[
  三條輸入裡，action history 怎麼處理 Part 2 已經教過，causal self-attention。真正的新零件是這個：action tokens 對 vision/language context 做 cross-attention。先把 context 接起來：M 個影像 tokens 和 L 個語言 tokens 拼成一串。然後 Q 從 action tokens 投影，K 和 V 從 context 投影，公式跟 self-attention 一模一樣，差別全在形狀帳：Q 是 T_a×d_k，K、V 是 (M+L)×d_k，所以 QK^T 是 T_a×(M+L)，不再是方陣。softmax 對每一列做，意思是每個 action token 把 1 的注意力預算分配到 M+L 個 context tokens 上；Part 2 練的 shape discipline 在這裡直接兌現，看形狀就知道「誰在查詢誰」。

  心智圖：action decoder 在問問題，影像和語言提供資料庫。

  某一步 action 可能問：「我現在該往哪裡移動？」影像 patch 提供物體位置，語言 token 提供任務目標，歷史 action 提供目前進度。cross-attention 的權重就是模型當下從 context 借資訊的分配。
]

== 一層 VLA decoder 的三件事

#row(gutter: .8em)[
  #card(tint: palette.amber, title: [① causal self-attention])[
    #set text(size: 0.8em)
    action step $t$ attends to steps $<= t$
    #v(.25em)
    跟 Part 2 一樣：\
    保持時間方向，*不偷看未來*
  ]
][
  #card(tint: palette.iris, title: [② cross-attention])[
    #set text(size: 0.8em)
    action tokens 查詢\
    vision / language context
    #v(.25em)
    *借外部資訊*
  ]
][
  #card(tint: palette.teal, title: [③ MLP])[
    #set text(size: 0.8em)
    對每個 token 自己的表示\
    做非線性加工
    #v(.25em)
    attention 交換資訊，\
    *MLP 加工資訊*
  ]
]
#v(.6em)
#callout(
  kind: "tip",
  compact: true,
)[兩種 mask 同一層並存，寫成同一個 $M$：action 列對 context 的 $M + L$ 欄全為 $0$（可見）；對 action 欄沿用 Part 2 的 $M_(t s) = -infinity thin (s > t)$，Part 3 那條原則的實戰版。]

#speaker-note[
  把前兩頁組裝起來，一層 VLA decoder 可以拆成三件事。

  第一，action tokens 做 causal self-attention：action step t attends to action steps ≤ t。這跟 Part 2 一樣，保持時間方向，不偷看未來。

  第二，cross-attention，上一頁講過了。

  第三，MLP 對每個 token 自己的表示做非線性加工。attention 負責交換資訊，MLP 負責加工資訊。

  注意這一層裡兩種 mask 並存，而且可以寫成同一個加法型 mask 矩陣：對第 t 個 action token 那一列，context 的 M+L 個欄位全部加 0，影像和語言不是未來，永遠可見；action 欄位沿用 Part 2 的規則，s > t 加負無窮。exp(-∞) = 0 的機制一模一樣，softmax 每列自動在「context 加上可見的 action 前綴」這個集合上正規化。這正是 Part 3 那句「mask 取決於資料關係」的實戰版，決定 M 裡哪些格子是 -∞ 的，從頭到尾都是資料的因果結構，不是架構的規定。
]

== 名字叫 VLA，訓練目標還是 BC

#align(center)[
  #text(size: 1.1em)[minimize $-log pi_theta ("demonstrator_action" | "image", "instruction", "action_history")$]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [變了的])[
    #set text(size: 0.85em)
    - 名字：VLA
    - 程式碼：vision encoder、language encoder、action decoder
    - loss：`(B*T*7)` 個分類問題一起算
  ]
][
  #card(tint: palette.teal, title: [沒變的])[
    #set text(size: 0.85em)
    訓練目標仍是：\
    示範者做了什麼，\
    就把那個答案的機率拉高。
    #v(.25em)
    *這就是 BC。*
  ]
]

#speaker-note[
  模型名字變成 VLA，程式碼變成 vision encoder、language encoder、action decoder，loss 變成 (B×T×7) 個分類問題一起算。但訓練目標仍然是：minimize -log π_θ(demonstrator_action | image, instruction, action_history)。

  這就是 BC。跟 Part 0 那個紅綠燈的表、跟企鵝分類的 cross-entropy，是同一條 loss 的放大版。整場課的依賴圖到這裡閉合。
]

== Report 裡的三張圖各自證明什麼

#table(
  columns: (auto, 1fr, 1fr),
  [面板], [告訴我們什麼], [對應的理解],
  [Loss / Action L2], [訓練 *有沒有動*], [Part 1 的 loss 與曲線],
  [prediction panel], [模型 *輸出什麼*], [Part 2 的 token 分布],
  [cross-attention panel], [decoder 比較 *讀影像還是語言*], [Part 4 的 cross-attention],
)
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[這些圖不是為了證明 homework 訓練出可部署 policy，而是證明 *你看得懂資料流和訓練迴圈*。]

#speaker-note[
  report 裡的 Loss / Action L2 告訴我們訓練有沒有動；prediction panel 告訴我們模型輸出什麼；cross-attention panel 告訴我們 decoder 比較讀影像還是語言。

  這些圖不是為了證明 homework 訓練出可部署 policy，而是證明你看得懂資料流和訓練迴圈。寫 report 的時候，每張圖旁邊要能用今天的詞彙說出「這張圖在檢查依賴圖上的哪一層」，這才是這份作業真正在驗收的東西。
]

= 課後延伸

== 補充教材

#row(gutter: .8em)[
  #card(tint: palette.iris, title: [3Blue1Brown], icon: [🎬])[
    #set text(size: 0.8em)
    神經網路系列
  ]
][
  #card(tint: palette.teal, title: [Karpathy], icon: [⌨️])[
    #set text(size: 0.8em)
    "Neural Networks: Zero to Hero"
  ]
][
  #card(tint: palette.amber, title: [李宏毅], icon: [🎓])[
    #set text(size: 0.8em)
    機器學習（台大公開課）
  ]
]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.rose, title: [CS285], icon: [🧠])[
    #set text(size: 0.8em)
    Berkeley Deep RL（Sergey Levine）
  ]
][
  #card(tint: palette.green, title: [ACT], icon: [🦾])[
    #set text(size: 0.8em)
    Zhao et al. 2023，論文原文
  ]
][
  #card(tint: palette.iris, title: [OpenVLA], icon: [📄])[
    #set text(size: 0.8em)
    Kim et al. 2024，論文原文
  ]
]

#speaker-note[
  六份都值得收藏，但用途不同，可以依照今天的路線分著推薦。

  3Blue1Brown 和 Karpathy 這兩份是地基：3Blue1Brown 補視覺直覺，適合對 gradient、backprop 還沒有肌肉記憶的人；Karpathy 的「Zero to Hero」直接手刻 micrograd、bigram、GPT，形狀跟今天的 lab 和 Autograd 那幾頁幾乎一樣，是今天內容最直接的延伸練習。李宏毅老師的課是中文全地圖，從 supervised learning 一路講到生成模型，適合想要有系統地重新過一遍全貌的人。

  後面三份是往 VLA 本身深挖，程度比前三份高一截。CS285 把 Part 5 只點到為止的 DAgger、distribution shift 放回研究所等級的決策理論架構裡講，是這門課理論深度最扎實的下一步。ACT 論文是 Part 5 提過的 action chunking、temporal ensemble 的原始出處：今天投影片只講了「看一眼、做一段」這個 pattern 買到什麼、付出什麼，論文裡有完整的消融實驗和真機數據支撐這個設計。OpenVLA 論文則是今天依賴圖的終點站：一個 7B 參數、vision encoder + language + action decoder 全部接起來的真實系統，讀完會發現今天教的每一塊，在論文裡都找得到對應的段落。
]

#ending-slide(title: [Q & A])
