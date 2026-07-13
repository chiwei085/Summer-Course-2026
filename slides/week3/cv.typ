#import "@local/summer-course:0.1.0": *

#show: course-theme.with(
  config-info(
    title: [From Photons to 3D],
    subtitle: [Week 3 · Classical Computer Vision ],
    author: [獵奇緯],
    institution: [Summer Course],
    short-title: [Week 3 · Classical Vision],
  ),
)

#let tiny = 0.72em
#let equation(body) = align(center)[#text(size: 1.22em)[#body]]

#let source-image(path, width: 100%, height: auto, credit: []) = col(gap: .08em)[
  #align(center)[#image(path, width: width, height: height, fit: "contain")]
][
  #align(center)[#text(size: .38em, fill: palette.muted)[#credit]]
]

#title-slide()
#outline-slide()

= 課程地圖

== 從 photons 到 3D，反向問題沒有唯一答案

#equation[$pi: ("geometry", "material", "illumination", "camera") arrow I(u,v)$]
#v(.55em)
#row(gutter: .75em)[
  #card(tint: palette.iris, title: [Forward · rendering], icon: [→])[給定世界與相機，物理規則決定像素。]
][
  #card(tint: palette.rose, title: [Inverse · vision], icon: [←])[只看像素，要猜回世界。不同世界可產生同一張圖。]
][
  #card(tint: palette.teal, title: [我們的策略], icon: [⚙])[限縮模型、加入假設、增加量測，然後估計。]
]
#v(.6em)
#quote-card(tint: palette.amber)[Classical vision 明確寫下：*哪些答案在目前證據下仍然可能。*]

#speaker-note[
  成像是一個嚴重損失資訊的映射。

  ```text
  π : (geometry, material, illumination, camera) -> I(u,v)
  ```

  forward 方向是物理,定義良好:給定場景的幾何、材質、光源和相機,原則上可以算出每個像素的值,電腦圖學做的就是這件事。vision 要做的是反方向,而 `π` 不是單射，不同的世界可以產生同一張影像，所以 `π⁻¹` 根本不存在。這就是 ill-posed inverse problem 的精確意思:解不唯一,而且問題本身缺少必要條件。

  缺條件的問題怎麼變成可解的?整個 classical vision 的答案只有一個模式:限縮模型類、補上假設、增加量測,然後在剩下的自由度裡做 estimation。

  投影在一開始就銷毀了深度,光度又把好幾個物理量壓縮成一個 scalar。之後的每一段,都是我們設法把被銷毀的資訊贖回來的旅程。
]

== 主線：資訊先被成像銷毀，再被我們逐段贖回

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [上半場 · 損失的帳 · Part 0 到 2], icon: [📉])[
    #set text(size: .78em)
    像素只是量測，語意不在陣列裡。\
    #v(.3em) 投影的那個除法，把深度商掉了。\
    #v(.3em) 光度把材質、法向、光源壓成一個 scalar。
  ]
][
  #card(tint: palette.teal, title: [下半場 · 贖回的代價 · Part 3 到 7], icon: [📈])[
    #set text(size: .78em)
    局部證據：gradient 撐起 edge、corner、line。\
    #v(.3em) 標定：賭棋盤是平面，換回 $K$ 與 pose。\
    #v(.3em) 雙目：用第二個視角，買回深度。\
    #v(.3em) 輪廓：量測不足之處，用 prior 補。
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[對應的 lab：① Color　② Local geometry：edge / corner / line　③ Calibration：$K$、pose、reprojection　④ Homework：Snake]

#speaker-note[
  這張頁面是導航圖。成像在一開始就欠了兩筆帳：投影銷毀深度，光度又把好幾個物理量壓縮成一個 scalar。之後的每一段，都是設法把被銷毀的資訊贖回來的旅程，而贖回從來不是免費的，每一段都付出一個假設當代價：標定賭平面棋盤、雙目賭外觀一致、snake 賭輪廓平滑。假設就是賭注，這是後面每個 Part 都會回來驗證的一句話。
]

= Part 0 · 影像作為量測

== 這張圖裡「真的」有一條白線嗎？

#align(center)[#image("figs/white-line-road.jpg", width: 46%)]
#v(.2em)
#callout(
  kind: "warn",
  compact: true,
)[相機量到的是規則網格上的 RGB 數字。車道線是我們對數字提出的世界解釋。]

#speaker-note[
  先故意問一個看似愚蠢的問題：圖裡真的有白線嗎？人當然會說有，但感測器其實只記錄規則網格上每一格的 RGB 數字；它沒有「白線」這個欄位。白線是我們根據亮色、細長、連續、位於道路上的位置等證據提出的世界解釋。

  所以從這一頁起，請把 pixel 當量測，把物體、邊界與距離當推論。後面所有演算法都不是直接在陣列裡找到語意，而是在有限的量測上加模型與假設。
]

== 一張數位影像是一個離散函數

#equation[$I: Omega subset ZZ^2 arrow [0,255]^3, quad I(u,v) = (R,G,B)$]
#v(.6em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [domain])[`(u,v)` 是 pixel index：向右、向下。]
][
  #card(tint: palette.teal, title: [range])[每個位置只存有限精度的 sensor value。]
][
  #card(tint: palette.amber, title: [語意不在陣列裡])[物體、邊界、距離都要靠模型推論。]
]

#speaker-note[
  這個函數觀點會讓之後的所有操作更清楚。定義域 Omega 是有限的 pixel index 集合，u 向右、v 向下；值域不是連續顏色，而是有限精度的 sensor value。RGB 只是每個位置的三個讀數，還沒有物體標籤。

  gradient 是估計 I 的局部變化；histogram 是忽略位置後的值分布；projection 則反過來問一個世界點如何產生某個 I(u,v)。同一張影像，但問題不同，保留與丟掉的資訊也不同。
]

== 量測不足時，先做帳

#row(widths: (1fr, 1.05fr), gutter: 1em)[
  #source-image(
    "figs/public/photometric-ambiguity-positive.png",
    width: 72%,
    height: 1.65in,
    credit: [$E_0$ ↑ · $rho$ → · red curve: fixed $I$ · Keytotime · Public domain],
  )
][
  #card(tint: palette.rose, title: [$I=rho E_0 max(0, cos theta)$：一個方程，兩個未知數], inset: .75em)[
    #set text(size: .78em)
    固定 $I$，$rho$（材質）與 $E_0$（光源強度）只被反比約束住：曲線上每一點都是合法解，單張影像的 photometric 量測天生 under-determined。
  ]
]
#v(.35em)
#card(tint: palette.teal, title: [估計問題的骨架], inset: .75em)[
  #set text(size: .78em)
  #equation[$hat(z) = op("arg min")_z D("measurement", "model"(z))$]
  constraints 與 prior 把「等高線上的一點」收斂成「唯一可信的 z」，例如假設 $rho$ 分段常數、或多視角共享同一個 $rho$。
]

#speaker-note[
  先養成一個習慣：見到一個 vision 結論，先問未知數有多少、量測有多少、缺的條件從哪來。這條等高線圖是最直接的視覺化：同一個 I 對應無窮多組 (rho, E_0)，debug 時最快的故障定位表就是問，我們額外加了什麼約束把解收斂到曲線上的一點。
]

= Part 1 · 深度如何在投影中消失

== Pinhole camera：一條 ray 對應一個像素

#source-image(
  "figs/public/central-projection-geometry.png",
  width: 47%,
  height: 1.55in,
  credit: [C: camera center · X: world point · projection ray → image plane · Olaf Peters · CC BY-SA 4.0],
)
#v(.3em)
#equation[$x = f X_c / Z_c, quad y = f Y_c / Z_c, quad Z_c > 0$]
#v(.35em)
#callout(kind: "info", compact: true)[虛擬 image plane 放在相機前方，避免倒像的負號。它在幾何上與真實 sensor 等價。]

#speaker-note[
  從針孔模型開始。世界點、相機中心與影像點共線；在 camera coordinates 裡，水平與垂直兩組相似三角形分別給出 x=fX_c/Z_c、y=fY_c/Z_c。請指著圖說明 virtual image plane 放在相機前方只是為了去掉倒像的負號，和真實 sensor 的幾何等價。

  這裡的 x、y 是 image plane 上的毫米座標，還不是 pixel；K 會在後面處理這個轉換。也請特別記住 Z_c>0：方程能對負深度做除法，物理相機卻拍不到背後的點，這個差異會在 cheirality 再次出現。
]

== 手算一次：foreshortening 只來自那個除法

#equation[$f = 20 "mm", quad X_c = (100, 50, 1000) "mm"$]
#v(.45em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [原始深度], inset: .75em)[
    #set text(size: .82em)
    $x = 20 dot 100 \/ 1000 = 2 "mm"$\
    $y = 20 dot 50 \/ 1000 = 1 "mm"$
  ]
][
  #card(tint: palette.rose, title: [移到兩倍遠 $(100,50,2000)$], inset: .75em)[
    #set text(size: .82em)
    $x = 20 dot 100 \/ 2000 = 1 "mm"$\
    $y = 0.5 "mm"$ ， 像縮成一半。
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[$(x,y)$ 仍是成像平面上的 metric 座標（mm），還不是 pixel。perspective foreshortening 整個現象，只來自 $1\/Z_c$ 這一個除法。]

#speaker-note[
  公式看過就要動手算一次,量級感是之後 debug 的本錢。焦距 20 毫米,點在一公尺外偏右偏上,投影落在 (2,1) 毫米，把點推到兩公尺,像座標直接砍半。近大遠小不是視覺心理學,是除法的代數後果。注意單位:這裡的 x、y 是 metric 座標,後面 K 才把它換成 pixel。
]

== 同一條 ray 上的點，投影完全相同

#row(widths: (1fr, 1.05fr), gutter: 1em)[
  #source-image(
    "figs/public/central-projection-ray-scale.png",
    width: 92%,
    credit: [$C arrow X arrow lambda X$: positions on one projection ray share the image point · Olaf Peters · CC BY-SA 4.0],
  )
][
  #card(tint: palette.rose, title: [尺度不變 ⇒ 深度被刪除])[
    #equation[$(X_c,Y_c,Z_c) arrow (X_c/Z_c, Y_c/Z_c)$]
    #set text(size: .8em)
    對任意 $lambda>0$，$lambda(X_c, Y_c, Z_c)$ 與原點落在同一條 ray，映到同一個像素。三維進、二維出：沿 ray 的深度是被投影方程直接消掉的自由度，不是雜訊蓋掉的。
  ]
]

#speaker-note[
  這是資訊論上的缺口。任意正的尺度 lambda 都不改變投影，所以單眼幾何的許多答案天生只有 up to scale。要把它買回來，得加入第二視角、已知尺寸或先驗，這就是後面 Part 5、6 分別在做的事。
]

== 除法還製造第二個麻煩：非線性

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [幾何損失 · 上一頁], inset: .75em)[
    #set text(size: .8em)
    深度被商掉。這是資訊論的缺口，代數救不回來。
  ]
][
  #card(tint: palette.amber, title: [代數麻煩 · 這一頁], inset: .75em)[
    #set text(size: .8em)
    $(X_c,Y_c,Z_c) arrow (X_c\/Z_c, Y_c\/Z_c)$ 含 $Z_c$ 的除法。接下來要串接座標變換、解線性方程組，除法會破壞線性結構。
  ]
]
#v(.55em)
#quote-card(tint: palette.iris)[策略：*升一維，再把尺度「商」掉。*除法不會消失，但可以被推遲到最後一步。]

#speaker-note[
  同一個除法惹出兩件事，性質完全不同。深度消失是量測缺口，只能靠第二視角或先驗買回來。非線性是表示法的問題，代數可以徹底解決，解法就是 projective space，接下來三頁把它從等價關係開始蓋起來。
]

== 齊次座標的地基：一個等價關係

#equation[$[x,y,w]^T tilde [lambda x, lambda y, lambda w]^T, quad lambda != 0, quad "in" RR^3 without \{0\}$]
#v(.5em)
#row(gutter: .7em)[
  #card(tint: palette.iris, title: [反身 reflexive])[
    #set text(size: .8em)
    取 $lambda=1$：$p = 1 dot p$，故 $p tilde p$。
  ]
][
  #card(tint: palette.teal, title: [對稱 symmetric])[
    #set text(size: .8em)
    $q=lambda p$ 且 $lambda != 0 arrow lambda^(-1)$ 存在：$p=lambda^(-1) q$。
  ]
][
  #card(tint: palette.amber, title: [傳遞 transitive])[
    #set text(size: .8em)
    $q=lambda p, r=mu q arrow r=mu lambda p$，且 $mu lambda != 0$。
  ]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[$lambda != 0$ 不是小字：對稱性的證明用到 $lambda^(-1)$。零向量也必須排除，乘任何尺度仍是零，定不出一條過原點的方向。]

#speaker-note[
  這一頁是純代數，請耐心走完。要把「相差一個尺度就算同一個」說成數學，工具是等價關係，而等價關係必須通過三個公理的檢查。三條都過，這個「當成同一個」才是合法的。注意兩個細節都掛在 lambda 不為零上：對稱性需要乘法反元素，零向量進不了任何 class。
]

== $PP^2$ 是商空間：一條過原點的直線，是一個點

#equation[$PP^2 = (RR^3 without \{0\}) \/ tilde$]
#v(.5em)
#row(widths: (1.1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [equivalence class = 過原點的直線], inset: .75em)[
    #set text(size: .8em)
    $[2,1,1]^T, [4,2,2]^T, [-2,-1,-1]^T$ 是 $RR^3$ 裡三個不同向量，卻在同一條過原點的直線上，同一個 projective point 的三個代表。
  ]
][
  #card(tint: palette.teal, title: [自由度的帳], inset: .75em)[
    #set text(size: .8em)
    三個座標，扣掉一個無意義的共同尺度，剩兩個自由度。上標 2 由此而來。
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[「商」讀作：把相差非零尺度的向量當成同一個元素。homogeneous coordinates 是從 class 裡任選的代表，代表可換，點不變。]

#speaker-note[
  上一頁的等價關係把 R³ 扣掉原點後分組：同一條過原點直線上的向量是一組，這一組叫 equivalence class。請用 [2,1,1]、[4,2,2] 與 [-2,-1,-1] 強調：它們是不同向量，卻是同一個 projective point 的不同代表。

  把每一組壓成一個元素，得到的集合就是商空間 P²。三個數扣掉一個可任意改變的共同尺度，只剩兩個自由度，這就是上標 2 的來源。之後所有 up to scale 的記號，都是在說「數值可以不同，但在同一個 class 裡」。
]

== Dehomogenize：在 class 裡選 $w=1$ 的代表

#row(widths: (1.1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [$w != 0$：取 $lambda = 1\/w$], inset: .75em)[
    #equation[$[x,y,w]^T tilde [x/w, y/w, 1]^T$]
    #set text(size: .8em)
    $[4,2,2]^T arrow (2,1)$。除法沒有消失，它被推遲成「最後選一次代表」。
  ]
][
  #card(tint: palette.rose, title: [$w = 0$：points at infinity], inset: .75em)[
    #set text(size: .8em)
    無法除，回不到有限平面。平行線因此在 projective plane 有交點，vanishing point 的伏筆。
  ]
]
#v(.5em)
#equation[$[x_n,y_n,1]^T tilde [I | 0] [X_c,Y_c,Z_c,1]^T$]
#v(.3em)
#callout(
  kind: "info",
  compact: true,
)[左右相差尺度 $Z_c$：數值不同、屬同一個 class、代表同一個 image point，equality up to scale 的完整意思。]

#speaker-note[
  現在回到相機。3×4 矩陣取出前三個座標，到這裡完全線性，dehomogenize 那一除，恰好就是相似三角形推出的 perspective projection。原本藏在投影式中間的除法，被拆成「先線性映射、最後選 w 等於 1 的代表」。後面 camera matrix、homography、fundamental matrix 全部依賴這個記號。
]

== 從 metric image plane 到 pixel

#equation[$K = mat(f_x, s, c_x; 0, f_y, c_y; 0, 0, 1), quad [u,v,1]^T tilde K[X_c,Y_c,Z_c]^T$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [f_x, f_y])[以 pixel 表示的焦距。它吸收 sensor pitch。]
][
  #card(tint: palette.teal, title: [(c_x,c_y)])[principal point，不必剛好落在影像中心。]
][
  #card(tint: palette.amber, title: [s])[pixel 軸的 skew。現代相機通常接近零。]
]

#speaker-note[
  K 是 intrinsic matrix：它描述的是同一台相機的 sensor 幾何，如何把 normalized ray 座標轉成 pixel 座標，不是相機這一刻擺在哪裡。f_x、f_y 是以 pixel 表示的焦距；principal point 是光軸打到影像平面的位置，不保證在正中央；s 描述 pixel 軸不正交造成的 skew。

  因此 K 與世界座標無關，在 zoom、focus、resolution 不變時可跨多張影像共享；每張影像不同的是 pose。這些參數都會在 calibration lab 中被估出來。
]

== 把 $K$ 展開：每個參數都有物理身分

#equation[$u = f_x x_n + s y_n + c_x, quad v = f_y y_n + c_y$]
#v(.45em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [f_x 吸收了兩個物理量], inset: .75em)[
    #set text(size: .8em)
    #equation[$f_x approx f("mm") dot W_("px") / W_("mm")$]
    物理焦距與 sensor pixel pitch 一起被打包成「以 pixel 計的焦距」。
  ]
][
  #card(tint: palette.teal, title: [f_x 順手給出視角], inset: .75em)[
    #set text(size: .8em)
    #equation[$"FOV"_x = 2 op("atan")(W / (2 f_x))$]
    $f_x$ 越大視角越窄、投影越大，這是光學幾何，digital zoom 只是裁切，與此式無關。
  ]
]
#v(.4em)
#callout(kind: "info", compact: true)[$s approx 0$ 仍照估不硬設：讓資料自己說它是零，比假設多一層驗證。]

#speaker-note[
  K 不是抽象記號,每個參數都可以拿相機規格表對帳。sensor 寬 W 毫米、影像寬 W 像素,f_x 大約就是物理焦距乘上換算比。再送一個常用結論:視角公式。手機主鏡頭 f_x 大約等於影像寬度時,水平視角約 53 度,可以自己驗算。至於 skew,現代相機幾乎是零,但 calibration 仍然估它，估出來接近零,是驗證，直接設零,是假設。
]

== Weak perspective：把 $1\/Z$ 凍結成常數的近似

#equation[$1/Z approx 1/Z_0 - (Z - Z_0)/Z_0^2, quad "當" abs(Delta Z) << Z_0$]
#v(.45em)
#row(gutter: .8em)[
  #card(tint: palette.teal, title: [近似成立時])[
    #set text(size: .8em)
    所有點共用同一個 $1\/Z_0$：投影變線性，平行線保持平行、大小不隨深度變。
  ]
][
  #card(tint: palette.iris, title: [更極端])[
    #set text(size: .8em)
    orthographic projection：直接丟掉縮放，只留 $(X, Y)$。
  ]
][
  #card(tint: palette.rose, title: [但別忘了])[
    #set text(size: .8em)
    calibration 與 stereo 賴以取得深度的，恰恰是被近似掉的那個透視除法。
  ]
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[遠距離窄視角的辨識任務可以用 weak perspective，三維重建必須用完整 perspective model。]

#speaker-note[
  這個近似值得從數學上看清楚適用範圍:把 1/Z 在平均深度附近做一階展開,物體的深度起伏遠小於平均深度時,每個點的 1/Z 幾乎是同一個常數,除法退化成統一縮放,投影變成線性映射。長焦鏡頭拍遠物就在這個 regime。但要記得一件反諷的事:深度資訊恰好藏在被我們近似掉的那一項裡,所以做重建時絕不能用這個近似，近似的方便和資訊的保留,不可兼得。
]

== 為什麼 distortion 只含 $r$ 的偶數次方？

#row(gutter: .8em)[
  #card(tint: palette.iris, title: [1 · 旋轉對稱])[
    #set text(size: .8em)
    鏡片是旋轉對稱的，畸變量只能是離 principal point 距離 $r$ 的函數。
  ]
][
  #card(tint: palette.teal, title: [2 · 光滑性])[
    #set text(size: .8em)
    要求映射在直角座標 $(x_n, y_n)$ 下光滑，而 $r = sqrt(x_n^2+y_n^2)$ 本身在原點不可微。
  ]
][
  #card(tint: palette.amber, title: [3 · 結論])[
    #set text(size: .8em)
    展開式只能含 $r^2 = x_n^2+y_n^2$ 的多項式，即 $r$ 的偶數次方。
  ]
]
#v(.5em)
#equation[$x_d = x_n (1 + k_1 r^2 + k_2 r^4 + k_3 r^6) + "tangential terms"$]
#v(.35em)
#callout(kind: "info", compact: true)[教科書模型的形狀不是湊出來的：對稱性 + 光滑性把函數空間篩到只剩這一族。]

#speaker-note[
  這是一個小而漂亮的對稱性論證,值得單獨一頁。第一步,鏡頭繞光軸旋轉對稱,所以畸變不能依賴方位角,只能是 r 的函數。第二步,整個映射用直角座標寫出來必須光滑,而 r 自己在原點是尖的，開根號不可微。兩個條件同時滿足的唯一辦法,是讓畸變量只透過 r 平方出現。這就是為什麼所有教科書的 distortion model 都長同一個樣子:不是慣例,是對稱性定理。
]

== 鏡頭模型加入 radial distortion

#row(widths: (1fr, 1.1fr), gutter: 1em)[
  #source-image(
    "figs/public/barrel-distortion.png",
    width: 68%,
    height: 1.45in,
    credit: [Barrel distortion · WolfWings · Public domain],
  )
][
  #card(tint: palette.rose, title: [半徑越大，位移越大])[
    #equation[$r^2 = x_n^2+y_n^2, quad x_d = x_n(1+k_1r^2+k_2r^4+...)$]
    #set text(size: .8em)
    位移量是 $r$ 的偶次多項式：中心不動，邊緣被系統性地往外（barrel，$k_1>0$）或往內（pincushion，$k_1<0$）推。
  ]
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[本週 calibration 刻意 pinhole-only，不估 distortion，residual 若呈上圖這種放射狀分佈，就是模型漏了這一項，不是 optimizer 壞掉。]

#speaker-note[
  請分清兩件事：calibration 是從資料估相機與畸變參數；undistortion 是拿估好的畸變模型重新取樣影像，兩者不是同一個動作。徑向模型以 principal point 為中心，r=0 的中心幾乎不移，越靠邊緣位移越大；在本課符號下，k₁ 為正時往外鼓成 barrel，為負時往內收成 pincushion。

  本週 lab 刻意只估 pinhole，不估 distortion。若 residual 在四周呈放射狀，不要先怪 optimizer；那是資料在說模型少了一項。這條伏筆會在 Part 5 收回來。
]

= Part 2 · 光如何變成亮度

== Pixel value 是一條非線性 response chain 的輸出

#equation[$I(u,v) = g(k dot E(u,v) dot Delta t), quad g "單調但非線性"$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [E · irradiance])[落在 sensor 的單位面積光功率，正比於場景 radiance L。]
][
  #card(tint: palette.teal, title: [$k, Delta t$])[gain（ISO）與曝光時間，是相機自己選的量測參數。]
][
  #card(tint: palette.amber, title: [g · response curve])[量化、tone curve、white balance，JPEG 還疊加 gamma。]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[`I(u,v)=200` 是這條鏈的輸出，不是材質亮度：同一個 E，改變 $k$、$Delta t$ 或 $g$，讀數就跟著變。]

#speaker-note[
  光度模型要先把量分清：E 是物理量，k 和 Delta t 是相機的操作參數，g 是廠商調的曲線。很多公式把 g 近似成線性，這是工作近似，不是自然定律。曝光一變，pixel value 就變，這也是後面 Lambertian consistency 要處理的第一層噪音來源。
]

== 三個常被混用的量，單位先分清

#table(
  columns: (auto, 1fr, auto),
  [量], [定義], [單位],
  [radiance $L$], [沿特定方向、單位立體角、單位投影面積的光功率], [$"W" dot "sr"^(-1) dot "m"^(-2)$],
  [irradiance $E$], [表面單位面積接收的光功率，理想透鏡下 $E prop L$], [$"W" dot "m"^(-2)$],
  [pixel value $I$], [$E$ 經曝光、gain、response curve、量化後的數值], [無單位],
)
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[classical vision 公式常假設 linear camera response：raw 影像大致成立，JPEG 已經過 tone curve，公式的保固條件從這裡開始。]

#speaker-note[
  後面所有光度假設的成立條件,都掛在這三個量的區分上。radiance 是場景朝某方向輻射的強度,單位裡帶著立體角，irradiance 是感光面實際收到的功率密度，pixel value 只是這一切經過相機加工後的讀數。理想透鏡成像時 sensor 上的 irradiance 正比於場景 radiance,這是唯一把物理和量測接起來的橋。而 linear response 是工作近似:raw 檔還算線性,JPEG 早就被 tone curve 揉過了。
]

== Lambert cosine law：入射角先決定收到多少光

#row(widths: (1fr, 1.05fr), gutter: 1em)[
  #source-image(
    "figs/public/lambert-footprint.svg",
    width: 88%,
    height: 1.25in,
    credit: [PBRT 3e · Fig. 5.7 · Pharr, Jakob, Humphreys · CC BY-NC-SA 4.0],
  )
][
  #card(tint: palette.teal, title: [幾何推導])[
    #equation[$E = E_0 max(0, n dot l)$]
    #set text(size: .8em)
    等寬平行光束斜射到表面時，照到的面積隨 $1/cos theta$ 展開，單位面積收到的功率就隨 $cos theta$ 下降，$theta>90°$ 表示背對光源，直接取 max 截斷成 0。
  ]
]
#v(.5em)
#quote-card(
  tint: palette.rose,
)[「斜著看所以變暗」不精確：這條式子裡沒有觀看方向 v，變暗首先是*入射幾何*，與你從哪個角度看無關。]

#speaker-note[
  這是純幾何，foreshortening 的標準論證：同一束等間距的平行光，投影到傾斜表面上會被拉開，單位面積分到的能量按比例縮水。theta 為零得到最大照度，九十度得到零。觀看方向是否重要，要看材質如何把收到的光重新輻射出去，這就是下一頁 BRDF 要回答的問題。
]

== $rho\/pi$ 的 $pi$ 是能量守恆逼出來的

#equation[$integral_("hemi") cos theta dif omega = integral_0^(2pi) dif phi integral_0^(pi\/2) cos theta sin theta dif theta = 2pi dot 1/2 = pi$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [BRDF 是常數])[
    #set text(size: .8em)
    Lambertian：$f_r = rho\/pi$，出射 radiance 與方向無關。
  ]
][
  #card(tint: palette.teal, title: [出射總功率])[
    #set text(size: .8em)
    radiance 對半球做 cosine-weighted 積分，常數提出，正好乘上 $pi$。
  ]
][
  #card(tint: palette.amber, title: [收支平衡])[
    #set text(size: .8em)
    反射功率恰為入射的 $rho$ 倍，$rho in [0,1]$ 才配叫 albedo。
  ]
]
#v(.4em)
#callout(kind: "warn", compact: true)[若 BRDF 直接取 $rho$ 不除 $pi$，反射功率會是入射的 $pi rho$ 倍，能量無中生有。]

#speaker-note[
  教科書的 rho 除以 pi 常被當成慣例背掉，其實是一行球座標積分。立體角元素是 sin theta d theta d phi，配上 cosine 權重，方位角積出 2 pi、極角積出二分之一，乘起來就是 pi。所以 BRDF 取 rho 除以 pi 時，反射總功率恰好是入射的 rho 倍，那個 pi 是能量守恆的除法，不是裝飾。
]

== Lambertian：跨視角一致性的假設

#equation[$I(p) prop rho(p) L max(0, n(p) dot l) + I_("ambient")$]
#v(.45em)
#row(widths: (1.65fr, 1.1fr), gutter: .8em)[
  #source-image(
    "figs/public/reflection-models.svg",
    width: 96%,
    credit: [Lambertian · glossy · specular · Vierge Marie / Grap-wh · CC BY-SA 4.0],
  )
][
  #card(tint: palette.iris, title: [兩種 BRDF 的差別])[
    #set text(size: .78em)
    Lambertian 的 BRDF 是常數 $rho/pi$，出射 radiance 對觀看方向不變（左圖是半圓）。specular 把能量集中在鏡面反射方向附近（右圖的窄瓣）。stereo matching 假設外觀左右一致，正是在賭 Lambertian 這一半。
  ]
]

#speaker-note[
  這頁把左邊 lambert 頁的伏筆接起來：入射的能量被 BRDF 重新分配到各個出射方向。Lambertian 假設分配是均勻的，於是同一世界點從不同視角看起來一樣亮，這正是後面 Part 6 photometric consistency 的地基。高光、陰影、interreflection 都是這個假設最常見的反例。
]

== 歧義的簿記：一個 scalar，五個以上的未知數

#equation[$underbrace(I(p), "1 個量測") prop underbrace(rho(p), "1") dot underbrace(L, "1") dot max(0, underbrace(n(p), "2") dot underbrace(l, "2")) + I_("ambient")$]
#v(.45em)
#row(gutter: .8em)[
  #card(tint: palette.rose, title: [「這個 pixel 比較暗」])[
    #set text(size: .78em)
    可能是材質深、表面轉開、光源弱、在陰影裡，單一 scalar 幾乎不攜帶資訊。
  ]
][
  #card(tint: palette.teal, title: [shape from shading 的存在理由])[
    #set text(size: .78em)
    假設 albedo 均勻、光源已知、表面光滑，自由度才被砍到可辨識。
  ]
][
  #card(tint: palette.amber, title: [模板第一次上場])[
    #set text(size: .78em)
    量測不夠，就得用假設補，假設哪條不成立，重建就跟著失效。
  ]
]

#speaker-note[
  這是這一段真正的重點:做歧義的簿記。左邊是一個 scalar,右邊有 albedo 一個自由度、單位法向量兩個、光源方向兩個、強度一個,還沒算陰影和 response curve。一個方程式對五個以上的未知數,所以任何從亮度直接讀出物理量的宣稱都偷渡了假設。shape from shading 不是魔法,它是把假設清單寫得夠長之後,自由度剛好可辨識的特例。Part 0 的模板在這裡第一次認真上場。
]

== Lambertian 的反例目錄：假設破產的四種方式

#row(gutter: .7em)[
  #card(tint: palette.rose, title: [specular])[
    #set text(size: .78em)
    金屬、玻璃、濕表面：亮度隨觀看方向劇烈變化，高光跟著視角跑。
  ]
][
  #card(tint: palette.amber, title: [cast shadow])[
    #set text(size: .78em)
    別的物體擋光。邊界銳利，與表面自身幾何無關。
  ]
][
  #card(tint: palette.amber, title: [attached shadow])[
    #set text(size: .78em)
    表面自己背光：$n dot l < 0$，就是 cosine law 裡的 $max(0, dot)$。
  ]
][
  #card(tint: palette.iris, title: [interreflection])[
    #set text(size: .78em)
    相鄰表面互相照亮，單一光源模型失效。
  ]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[Part 6 的 stereo 靠「同一世界點左右外觀相似」認人，一個只在左眼出現的高光，會讓 matching 在那裡直接失明。]

#speaker-note[
  現在只是名詞,但先記下:每一個都會在 Part 6 兌現成 stereo 的失敗案例。photometric consistency 的物理基礎恰恰是 Lambertian 假設,所以高光是 matching 的天敵，兩種陰影要分開,cast shadow 是幾何遮擋,attached shadow 就是那個 max 截斷，interreflection 則讓白牆角落泛出鄰面的顏色。看到 stereo 的深度圖在這些地方破洞,不要怪 optimizer,是物理假設先破產。
]

== RGB → grayscale：三種定義，三種立場

#equation[$"Average": (R+G+B)/3 quad "Lightness": (max+min)/2 quad "Luminosity": .299R+.587G+.114B$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [Average])[
    #set text(size: .8em)
    三個 channel 等權，假裝 sensor 三色同等重要。
  ]
][
  #card(tint: palette.teal, title: [Lightness])[
    #set text(size: .8em)
    只看最亮與最暗 channel 的中點，丟掉中間值。
  ]
][
  #card(tint: palette.amber, title: [Luminosity · BT.601])[
    #set text(size: .8em)
    權重反映人眼對綠敏感、對藍遲鈍。本週程式用這個。
  ]
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[三者都是實用 signal conversion，都不是 photometric calibration：後者還需要線性化與光譜響應。]

#speaker-note[
  同一張彩圖,三種轉法給出三張不同的灰階圖,差異在飽和色塊上最明顯:純綠在 Average 下是 85,在 Luminosity 下接近 150。沒有哪個「對」,它們是三種不同的立場，等權、極值中點、人眼加權。要記住的是它們全都不是 albedo、不是照度,只是把三維訊號壓一維的實用約定。lab 裡把三張圖並排,親眼看一次差異。
]

== Color lab：representation 決定「距離」的意義

#row(widths: (1.1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [RGB → intensity])[
    #equation[$Y = .299R + .587G + .114B$]
    luma 是實用轉換，不等於 albedo 或照度。
  ]
][
  #col(gap: .3em)[
    #card(tint: palette.teal, title: [HSV hue 是圓，不是線])[
      #equation[$d(h_1,h_2)=min(abs(h_1-h_2), 360°-abs(h_1-h_2))$]
    ]
  ][
    #source-image(
      "figs/public/hue-wheel-short-arc.png",
      width: 38%,
      height: .72in,
      credit: [$350° arrow.l.r 10°$: shortest arc crosses 0° · 8 leaf-clover · CC0],
    )
  ]
]
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[Color notebook 讓你比較三種 grayscale、histogram 與 RGB↔HSV。它們改變表示與操作，保留相同的場景資訊量。]

#speaker-note[
  這裡把 lab 接進來。RGB 轉 intensity 是從三維訊號降到一維，方便後續的 edge 或 histogram 操作，但不會憑空變成照度或 albedo。HSV 則是同一色彩資訊的重新參數化；特別是 hue 定義在圓上，350 度與 10 度的正確距離是跨過 0 度的 20 度，不是線性相減的 340 度。

  saturation 接近零時 hue 幾乎沒有意義，做顏色比對時不能忽略這件事。histogram 再進一步丟掉空間位置。每次改 representation，都要重問距離怎麼定義、哪些變化應該不變。
]

== Histogram 商掉了全部空間結構

#equation[$h(k) = \#{(u,v) : I(u,v) = k}$]
#v(.45em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [對 pixel 重排不變], inset: .75em)[
    #set text(size: .8em)
    任意打亂 pixel 位置，histogram 一個 bin 都不動。「對所有排列不變」的精確意思：空間結構被商掉了。
  ]
][
  #card(tint: palette.rose, title: [推論：shape 讀不回來], inset: .75em)[
    #set text(size: .8em)
    兩張幾何內容完全不同的影像可以有相同 histogram，構造法就是打亂 pixel。
  ]
]
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[它適合觀察 sensor value 的分布。Part 7 的 Otsu threshold 建在它之上，屆時要記得這個先天限制。]

#speaker-note[
  histogram 值得用一句數學說清楚表達範圍:它是值域分箱後的計數,是 pixel 位置的完全遺忘者。「商掉」這個詞和 P² 那邊是同一個用法，把一整類東西壓成一個代表,代價是類內的差異再也讀不回來。P² 商掉的是尺度,histogram 商掉的是空間排列。所以拿 histogram 做任何涉及形狀的推論都是越權，拿它看曝光、看前景背景的 intensity 可分性,才是本分。Part 7 的 Otsu 就建在這個本分上。
]

= Part 3 · 從像素變化取得局部證據

== Gradient 是局部一階模型

#row(widths: (1fr, 1.05fr), gutter: 1em)[
  #source-image(
    "figs/public/image-gradient.png",
    width: 96%,
    credit: [Blue arrows: $nabla I$ · isophotes are perpendicular · Finallymadeanaccount · CC BY-SA 4.0],
  )
][
  #card(tint: palette.iris, title: [Taylor 一階展開], inset: .75em)[
    #set text(size: .78em)
    #equation[$I(x+delta x,y+delta y) approx I(x,y) + nabla I^T delta$]
    #equation[$nabla I = [I_x,I_y]^T, quad |nabla I| = sqrt(I_x^2+I_y^2), quad phi=op("atan2")(I_y,I_x)$]
    gradient 指向最陡上升，等值線（同亮度）的切線方向與它正交，這就是圖中 edge 與 $nabla I$ 垂直的原因。
  ]
]

#speaker-note[
  局部證據從 Taylor 一階展開開始：小位移 delta 造成的亮度變化，第一階由 gradient 和 delta 的內積決定。gradient magnitude 是最大變化率，atan2 給出最陡上升方向；等亮度線的切線和 gradient 垂直，因此圖中的 edge 方向也和 gradient 垂直。

  但請保持 Part 0 的紀律：亮度不連續只是局部證據，不必然是物體邊界。材質花紋、陰影與遮擋都能產生 edge；是否是輪廓仍須結合模型判讀。
]

== Sobel：平滑與微分合在一個 kernel

#row(widths: (1.1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [先問為何要平滑])[
    微分放大高頻。sensor noise 正是高頻。\
    #v(.4em) #equation[$partial(G_sigma * I) = (partial G_sigma) * I$]
  ]
][
  #card(tint: palette.teal, title: [Sobel G_x])[
    #equation[$mat(-1, 0, 1; -2, 0, 2; -1, 0, 1)$]
    #set text(size: .78em)
    垂直方向 `[1,2,1]` 平滑，水平方向中央差分。
  ]
]

#speaker-note[
  微分會放大高頻，而 sensor noise 恰好是高頻，所以不能直接對原圖做中央差分。先用 Gaussian 平滑再微分，因為微分與 convolution 可交換，也等價於拿 Gaussian derivative 去摺積原圖。

  Sobel 是這個想法的最小整數版：垂直方向的 [1,2,1] 負責平滑，水平方向 [-1,0,1] 負責差分，得到 G_x；G_y 則交換方向。kernel 或 sigma 越大，抗雜訊越好、定位越鈍，這就是尺度選擇的代價。
]

== Separability：Sobel 是一個 outer product

#equation[$mat(-1, 0, 1; -2, 0, 2; -1, 0, 1) = mat(1; 2; 1) times.o mat(-1, 0, 1)$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [分解的讀法])[
    #set text(size: .8em)
    垂直方向做 `[1,2,1]` 平滑、水平方向做 `[-1,0,1]` 中央差分，兩個一維操作的合成。
  ]
][
  #card(tint: palette.teal, title: [計算的紅利])[
    #set text(size: .8em)
    每 pixel 成本從 $O(k^2)$ 降到 $O(k)$：3×3 差別小，大 kernel 是實質加速。
  ]
][
  #card(tint: palette.amber, title: [$G_y$])[
    #set text(size: .8em)
    就是轉置：平滑與差分交換方向，比較上下。
  ]
]
#v(.4em)
#callout(kind: "info", compact: true)[Gaussian 本身也 separable，「先平滑再微分」整條管線都能拆成一維摺積。]

#speaker-note[
  separability 不只是概念上乾淨。二維摺積要在每個 pixel 掃 k 平方個鄰居,拆成先直後橫兩趟一維摺積,成本降到 2k。對 Sobel 的 3×3 只是小便宜,對 sigma 大的 Gaussian kernel 是一個數量級的加速。而這個分解同時把 Sobel 的身世講明白了:它就是「一個方向平滑、另一個方向差分」,Gaussian derivative 的最小整數近似,不是誰拍腦袋填的九個數。
]

== Canny 的起點：把「好偵測器」寫成最佳化問題

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [detection], inset: .75em)[
    #set text(size: .8em)
    不漏掉真邊、不把 noise 撿成邊，訊噪比要高。
  ]
][
  #card(tint: palette.teal, title: [localization], inset: .75em)[
    #set text(size: .8em)
    回報的位置要貼近真實邊緣，定位方差要小。
  ]
]
#v(.5em)
#quote-card(tint: palette.amber)[Canny (1986) 證明：同時最佳化這兩個準則，最優 filter 可用 *Gaussian 的導數*逼近。]
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[所以「先 Gaussian 平滑再 Sobel」不是工程慣例的堆疊，而是最佳化問題的近似解，剩下的工作是把厚山脊變成細曲線。]

#speaker-note[
  Canny 的論文常被記成「一個 pipeline」,但它的貢獻首先是問題形式化:把 detection 和 localization 寫成兩個可以計算的準則,然後在一維訊號上求最優 filter,證明解長得非常像 Gaussian 的一階導數。這給了前面「先平滑再微分」一個超越直覺的地位，它不只是抗噪的土辦法,是最佳準則的近似解。理解這一點,後面兩步 NMS 和 hysteresis 才不會被記成魔法咒語:它們分別解決「山脊太厚」和「threshold 太脆」兩個遺留問題。
]

== Canny：把一條厚山脊壓成可追蹤曲線

#row(gutter: .7em)[
  #card(tint: palette.iris, title: [1 · magnitude])[找可能的亮度變化。]
][
  #card(tint: palette.teal, title: [2 · NMS])[沿 gradient 方向只留局部極大，thinning。]
][
  #card(tint: palette.amber, title: [3 · hysteresis])[strong seed 連到的 weak pixel 才保留。]
]
#v(.55em)
#callout(
  kind: "warn",
  compact: true,
)[low 太低會把 clutter 接進來。high 太高會讓真邊沒有 seed。hysteresis 是 connected-components 問題。]

#speaker-note[
  單一 threshold 的 edge 會又粗又脆弱。先以 magnitude 找候選，接著 NMS 沿 gradient 方向比較，只留山脊中央的局部最大，將厚邊壓成一條可追蹤曲線；最後 hysteresis 不把所有 weak pixel 當 edge，只保留能連到 strong seed 的那一群。

  low 太低時 clutter 會沿連通性接進來；high 太高時真邊沒有 seed，整個 component 都消失。下一頁把這個最後步驟明確改寫成圖論問題。
]

== Hysteresis 是一個圖論問題

#row(widths: (1.05fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [定義圖], inset: .7em)[
    #set text(size: .78em)
    頂點：strong 與 weak pixels（兩個 threshold 分出三類）。\
    邊：8-鄰接關係。\
    保留：所有*含至少一個 strong 頂點*的 connected component。
  ]
][
  #card(tint: palette.teal, title: [演算法], inset: .7em)[
    #set text(size: .76em)
    ```text
    for each strong pixel s not yet visited:
        BFS/DFS from s over strong ∪ weak
        mark the whole component as edge
    ```
    線性時間 $O(V + E)$ 完成。
  ]
]
#v(.4em)
#row(gutter: .7em)[
  #card(tint: palette.rose, title: [high 太高])[#set text(size: .78em)
    真邊沒有任何 seed，整個 component 被丟。]
][
  #card(tint: palette.rose, title: [low 太低])[#set text(size: .78em)
    大量 weak 頂點連進有 seed 的 component。]
][
  #card(tint: palette.amber, title: [high = low])[#set text(size: .78em)
    連通性資訊完全沒被用到，退化回單一 threshold。]
]

#speaker-note[
  把 hysteresis 理解成 connected components,參數的行為就可以直接推出來,不必背。兩個 threshold 把 pixel 分成 strong、weak、non-edge 三類，strong 是種子,weak 是候選,規則只有一條:連得到種子的候選才算數。從每個 strong seed 做一次 BFS,線性時間掃完。high 控制種子的資格,low 控制候選的門檻,兩個旋鈕管兩件不同的事，lab 裡調參時,先想清楚你的問題是「真邊沒種子」還是「clutter 連進來」,再動對應的那顆。
]

== Corner：移動哪個方向都應該看起來不同

#equation[$E(delta) = sum_w [I(x+delta)-I(x)]^2 approx delta^T M delta$]
#equation[$M = sum_w mat(I_x^2, I_x I_y; I_x I_y, I_y^2), quad lambda_("min") <= d^T M d <= lambda_("max"), quad ||d||=1$]
#v(.4em)
#table(
  columns: (1fr, 1fr, 1fr),
  [eigenvalues], [local geometry], [meaning],
  [both small], [flat], [no reliable localization],
  [one large], [edge], [aperture problem],
  [both large], [corner], [all directions constrained],
)

#speaker-note[
  Structure tensor 把 window 內的 gradient outer products 累加成對稱半正定的二次型，形狀由特徵值完全決定。Rayleigh quotient 說：沿單位方向移動的變化量被夾在兩個特徵值之間，極值方向就是特徵向量。aperture problem 於是有了精確版本：edge 的切線方向落在二次型的近似 null space，量測只約束法線方向的位移。corner 同時約束兩個方向，因此適合定位與匹配。
]

== Harris：不用求特徵值，也能辨認角點

#row(widths: (1fr, 1.1fr), gutter: 1em)[
  #source-image(
    "figs/public/harris-regions.png",
    width: 70%,
    height: 1.22in,
    credit: [Sánchez, Monzón, Salgado · IPOL Fig. 5 · CC BY-NC-SA 3.0],
  )
][
  #card(tint: palette.iris, title: [$R=det(M)-k op("tr")(M)^2=lambda_1lambda_2-k(lambda_1+lambda_2)^2$], inset: .75em)[
    #set text(size: .78em)
    $det, op("tr")$ 是 eigenvalue 的不變量，避免逐 pixel 做特徵分解。令 $m=lambda_2\/lambda_1$，$R=0$ 化簡成 $k m^2+(2k-1)m+k=0$：對常用 $k=.04$ 解出兩個根 $m approx .044, 22.96$（互為倒數），對應圖中兩條射線，之間才是 $R>0$ 的 corner 錐，貼近任一軸的窄帶是 $R<0$ 的 edge。
  ]
]
#v(.4em)
#callout(kind: "info", compact: true)[Harris response 後仍須 spatial NMS，讓每個真角落回傳單一局部峰值。]

#speaker-note[
  這頁把上一頁的 eigenvalue 表格量化。det(M)=lambda_1 lambda_2 與 tr(M)=lambda_1+lambda_2 都是不必做 eigendecomposition 就能計算的不變量，所以 Harris 可以逐 pixel 很快地評分。R 大且為正代表兩個特徵值都大，是角點；R 負通常是一大一小的 edge；兩者都小則接近平坦。

  k 決定 R=0 的邊界錐張多開。k 越大，corner 錐越窄、篩選越嚴格；k 越小，更多非平坦位置會被收進來。最後仍須做 spatial NMS，否則同一個角落會回傳一團高 response pixel。
]

== 直線的參數化：先選對座標

#row(widths: (1fr, 1.1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [$y = m x + b$ 不及格], inset: .75em)[
    #set text(size: .8em)
    垂直線的 $m arrow infinity$，參數空間無界，道路影像裡最重要的線剛好接近垂直。
  ]
][
  #card(tint: palette.teal, title: [normal form], inset: .75em)[
    #equation[$rho = x cos theta + y sin theta$]
    #set text(size: .8em)
    $theta$ 是法線方向、$rho$ 是原點沿法線到直線的有號距離：所有直線都被有界參數覆蓋。
  ]
]
#v(.4em)
#row(gutter: .8em)[
  #card(tint: palette.amber, title: [重複表示])[
    #set text(size: .78em)
    $(rho, theta) tilde (-rho, theta + pi)$：法線轉向、距離變號，同一條線。慣例取 $theta in [0, pi)$。
  ]
][
  #card(tint: palette.iris, title: [參數的界])[
    #set text(size: .78em)
    原點取影像左上角時 $rho_max = sqrt((W-1)^2 + (H-1)^2)$，不超過對角線。
  ]
]

#speaker-note[
  Hough 的第一個決定不是演算法,是參數化。斜率截距式對垂直線直接爆掉,而 lane detection 的目標線恰恰接近垂直,所以必須換 normal form:用法線角度和有號距離描述直線,兩個參數都有界,才能切格子。代價是一個重複表示，法線轉半圈、距離變號,是同一條線,實作要把 theta 限制在半圈裡,否則同一條線會在 accumulator 裡出現兩個峰。
]

== Hough transform：共線關係在參數空間交會

#row(widths: (1.05fr, 1fr), gutter: 1em)[
  #source-image(
    "figs/public/hough-space.png",
    width: 100%,
    credit: [Image points → sinusoidal votes → shared peak · NekoJaNekoJa · CC BY-SA 3.0],
  )
][
  #card(tint: palette.teal, title: [對偶：點 ↔ 曲線], inset: .75em)[
    #set text(size: .78em)
    #equation[$rho = x cos theta + y sin theta$]
    固定 image space 的一點 $(x,y)$，這條式子描述它「可能屬於」的所有直線，畫在 $(rho,theta)$ 空間是一條正弦曲線。左圖三個共線點各自的曲線，在同一個 $(rho,theta)$ bin 相交，共線關係被翻譯成投票峰值。
  ]
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[$(rho,theta)$ 與 $(-rho,theta+pi)$ 是同一條線。量化太粗會合併候選。量化太細會稀釋票數。]

#speaker-note[
  Hough 的觀念轉換是把「點是否共線」改成「參數空間是否有投票峰值」。固定一個 image point 時，rho=x cos theta+y sin theta 在参数空間是一條 sinusoid，因為它正在列出所有可能通過自己的線；三個共線點的三條曲線會在同一組線參數附近交會。

  這是點與曲線的對偶，而不是把點直接投到一個 bin。標準 Hough 找到的是無限長直線；道路上的有限線段仍需要收集支持點、沿線投影並依 gap 切段。量化太粗會合併不同線，太細則會把同一條線的票打散。
]

== 投票演算法：把連續對偶離散化

#row(widths: (1.15fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [Hough-Vote], inset: .7em)[
    #set text(size: .8em)
    ```text
    for each edge point (x_i, y_i):
        for j = 0, ..., N_θ - 1:
            θ_j = j·Δθ
            ρ  = x_i cos θ_j + y_i sin θ_j
            k  = floor((ρ + ρ_max) / Δρ)
            A[k, j] += 1
    ```
  ]
][
  #col(gap: .5em)[
    #card(tint: palette.teal, title: [格子], inset: .7em)[
      #set text(size: .78em)
      $Delta theta = pi \/ N_theta$，$Delta rho = 2 rho_max \/ N_rho$。
    ]
  ][
    #card(tint: palette.amber, title: [成本], inset: .7em)[
      #set text(size: .78em)
      時間 $O(N_("edges") N_theta)$、空間 $O(N_rho N_theta)$，$sin, cos$ 先建表。
    ]
  ]
]
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[一個 edge point 不知道自己屬於哪條線，所以沿它整條離散 sinusoid 逐格投票，$A[k,j]$ 最後等於支持該直線的 edge points 數。]

#speaker-note[
  演算法本體就這六行。逐行讀:外層走每個 edge point,內層走每個角度格，給定角度,ρ 由 normal form 直接算出,量化成 bin index,計數加一。每個點畫出一條離散 sinusoid,票撒在整條曲線上，它在為「所有可能通過我的直線」背書。累積完,bin 的票數就是支持度。成本是點數乘角度格數,accumulator 佔兩個格數的乘積,三角函數在內層迴圈裡重算是低級錯誤,先建表。
]

== 手算一個最小例子：峰值如何形成

#equation[$(1,2), (3,2), (5,2) quad "都在" y = 2 "上"$]
#v(.45em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [$theta = pi\/2$ 時], inset: .75em)[
    #set text(size: .8em)
    $cos theta = 0, sin theta = 1$，三點都算出 $rho = y = 2$：bin $(rho=2, theta=pi\/2)$ 收到 *3 票*。
  ]
][
  #card(tint: palette.iris, title: [其他角度], inset: .75em)[
    #set text(size: .8em)
    三點通常算出不同的 $rho$，票散進不同格子，只有真實直線的參數格會累積。
  ]
]
#v(.45em)
#callout(
  kind: "warn",
  compact: true,
)[真實影像有 noise、邊緣厚度、量化誤差：sinusoids 只會在一小片鄰域靠攏，不會精確穿過同一個 bin，這是下一頁後處理存在的理由。]

#speaker-note[
  用三個點手算一次,峰值形成的機制就再也不抽象。三個點都在水平線上，水平線的法線朝正上方,角度九十度,這時每個點的 ρ 都恰好等於它的 y 座標,三票全進同一格。轉到別的角度,三個點對 ρ 的計算結果各不相同,票就散掉。共線性被翻譯成「在正確參數處同時命中」。但真實資料的邊緣有厚度、有 noise,曲線群只會擠在一小片鄰域,所以單格 threshold 不夠,還需要在 accumulator 上做 NMS，下一頁。
]

== Accumulator 的後處理與量化取捨

#row(gutter: .75em)[
  #card(tint: palette.iris, title: [為何不能只做 threshold])[
    #set text(size: .78em)
    同一條真線在相鄰 bins 形成一團高票區，直接 threshold 會回報多條幾乎相同的線。
  ]
][
  #card(tint: palette.teal, title: [2D NMS])[
    #set text(size: .78em)
    只留 $(rho, theta)$ 鄰域內的局部最大，再依票數排序、套 vote threshold。
  ]
][
  #card(tint: palette.amber, title: [週期邊界])[
    #set text(size: .78em)
    $theta$ 的首尾是相鄰方向：NMS 要處理 $[0, pi)$ 的 wrap-around 與 $rho$ 的符號翻轉。
  ]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [格子太粗], inset: .7em)[
    #set text(size: .78em)
    不同直線的票混進同一格，參數估計也粗。
  ]
][
  #card(tint: palette.rose, title: [格子太細], inset: .7em)[
    #set text(size: .78em)
    同一條線的票被 noise 打散到相鄰格，峰值反而變低，記憶體與計算同時上升。
  ]
]

#speaker-note[
  這一頁全是 Part 3 已經見過的老朋友。accumulator 上的 NMS 和 Canny、Harris 的 NMS 是同一個動作，證據在鄰域裡糊成一團時,只留局部極大。特別的是參數空間的拓撲:theta 是半圈的圓,首尾相接,NMS 的鄰域要跨過邊界,而且跨界時 ρ 要翻符號。量化解析度的兩難也和 σ 的尺度選擇同構:太粗混票、太細散票,沒有免費的解析度。
]

== 讓 gradient orientation 替你省票

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [方向資訊], inset: .75em)[
    #set text(size: .8em)
    edge 的 gradient 方向 $phi_i$ 正是線的法線方向：只需對 $theta approx phi_i$ 附近的 $m$ 個 bins 投票，成本從每點 $N_theta$ 降到 $m$。
  ]
][
  #card(tint: palette.amber, title: [magnitude 加權], inset: .75em)[
    #equation[$A[k,j] += abs(nabla I(x_i, y_i))$]
    #set text(size: .8em)
    強 edge 影響力大，但高對比短線會壓過低對比長線。
  ]
]
#v(.5em)
#quote-card(tint: palette.iris)[投票權重的選擇，其實是在定義「*支持一條線的證據*」如何計量。]

#speaker-note[
  Canny 不只給位置還給方向,而 edge 的 gradient 方向剛好就是所屬直線的法線方向，這正是 normal form 參數化的 theta。所以一個 edge point 根本不用對全部角度投票,對自己方向附近的一小段投就夠,成本大砍一個因子。加權投票則是一個誠實的設計題:用 magnitude 加權,等於宣告「對比即證據」，用單純計數,等於宣告「長度即證據」,vote threshold 天然偏好長線。兩種都對,取決於你要找的是什麼線。
]

== 從無限長直線到影像裡的線段

#row(gutter: .75em)[
  #card(tint: palette.iris, title: [1 · 收集支持點])[
    #set text(size: .78em)
    $abs(x_i cos theta + y_i sin theta - rho) < epsilon$
  ]
][
  #card(tint: palette.teal, title: [2 · 投影到線方向])[
    #set text(size: .78em)
    $d = (-sin theta, cos theta)$，$s_i = d^T (x_i, y_i)$，排序。
  ]
][
  #card(tint: palette.amber, title: [3 · gap 切段])[
    #set text(size: .78em)
    相鄰 $s_i$ 的 gap 超過門檻就切，丟掉太短、支持點太少的 run。
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[lane marking 天生斷裂：gap threshold 決定相鄰標線合併或分開，minimum length 排除 clutter。另有 Probabilistic Hough：抽樣投票、直接輸出 endpoints，用函式庫前先確認是哪個版本。]

#speaker-note[
  峰值只給 (ρ, θ),那是一條無限長直線，道路上要的是線段。做法是把幾何降到一維:先撈出離直線夠近的支持點,再沿線方向投影成一維座標,排序後掃 gap。虛線車道的 gap threshold 是個語意決定，設大,整條虛線合併成一段，設小,每個小白塊各自成段。另外提醒:OpenCV 的 HoughLinesP 是 Probabilistic 版本,抽樣投票、直接回 endpoints,參數意義和 Standard 版不同,讀 API 文件時別張冠李戴。
]

== Local geometry lab：同一份 gradient，三種不同問題

#row(gutter: .75em)[
  #card(tint: palette.iris, title: [Canny])[Sobel → NMS → hysteresis。看 threshold 對連通性的影響。]
][
  #card(tint: palette.teal, title: [Harris])[structure tensor → response → NMS。看尺度與稀疏度。]
][
  #card(tint: palette.amber, title: [Hough])[Canny points → accumulator → peaks → segments。看量化與 vote threshold。]
]

#speaker-note[
  這個 notebook 的三個 cell 共用同一份 Sobel gradient，但問的是三個不同問題。Canny 把它當作邊的強度與方向，重點是 NMS 後的連通性；Harris 把 window 內的 gradient outer product 累成二次型，重點是兩方向是否都受約束；Hough 把 Canny edge point 轉成参数空間投票，重點是量化與峰值。

  調參時不要只看輸出漂不漂亮，而要回到它依賴的數學物件：edge 的 threshold 與連通性、corner 的尺度與稀疏度、line 的 accumulator 與 vote threshold。
]

= Part 4 · 座標系、外參與完整相機模型

== 先說清楚「誰被誰看見」

#equation[$X_c = R X_w + t, quad R in "SO"(3)$]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [rotation])[`R^T R=I`、`det R=+1`：保長度與方向，排除鏡射。]
][
  #card(tint: palette.teal, title: [translation])[相機中心在 world 是 `C_w` 時：`t=-R C_w`。]
]
#v(.45em)
#equation[$T_("cw") = mat(R, t; 0, 1), quad T_("wc")=T_("cw")^(-1)$]

#speaker-note[
  外參最常見 bug 是把 transform 方向說得含糊。這裡明定 X_c=R X_w+t，因此下標 cw 是 world 到 camera：R 旋轉世界座標到 camera frame，t 也在 camera frame 裡。R 必須滿足 R^T R=I 且 det R=+1，後者排除鏡射。

  相機在 world 的 pose 是反變換，不要把它和 [R|t] 混叫「相機位置」。用齊次矩陣時 T_cw 的逆才是 T_wc；矩陣連乘的中間 frame 名稱應該像分數一樣消掉，這是最可靠的自我檢查。
]

== $t$ 是什麼？把相機中心代進去就知道

#row(widths: (1.05fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [推導：相機中心必須映到原點], inset: .75em)[
    #equation[$0 = R C_w + t quad ==> quad t = -R C_w$]
    #set text(size: .8em)
    所以 $t$ *不是*「相機的位置」，相機在 world 的位置是 $C_w = -R^T t$。
  ]
][
  #card(tint: palette.teal, title: [下標紀律：像分數約分], inset: .75em)[
    #equation[$T_("cw") T_("wr") = T_("cr")$]
    #set text(size: .8em)
    目的地在左、來源在右，串接時中間的 $w$ 對消。矩陣從右往左作用。
  ]
]
#v(.45em)
#callout(
  kind: "warn",
  compact: true,
)[說「外參是相機的位置」之前必須先聲明變換方向，否則就是在賭五五開，多 frame 串接的 bug 大半死在這裡。]

#speaker-note[
  t 的身分值得用一行推導釘死:相機中心自己變換到 camera frame 後必須落在原點,代入就得到 t 等於負 R C_w。這說明 [R|t] 描述的是「world 的點如何被相機看見」,而「相機在世界裡的 pose」是它的逆。接著是记號紀律:下標讀成目的地在左、來源在右,連乘時中間 frame 像分數約分一樣消掉,寫完一串變換掃一眼下標就能自我檢查。這個紀律嚴格執行,多 frame 的 bug 少一大半，機器人上 world、base、end-effector、camera 四五個 frame 是常態。
]

== 完整 camera matrix 把三段流程壓成一行

#equation[$tilde(x) tilde K [R | t] tilde(X)_w = P tilde(X)_w$]
#v(.6em)
#row(gutter: .75em)[
  #card(tint: palette.iris, title: [extrinsic])[world point → camera frame]
][
  #card(tint: palette.amber, title: [perspective divide])[camera frame → normalized image]
][
  #card(tint: palette.teal, title: [intrinsic])[normalized image → pixel]
]
#v(.5em)
#callout(kind: "danger", compact: true)[矩陣式很方便，但 debug 時必須把中間的 `Z_c>0` 與 dehomogenize 明確攤開。]

#speaker-note[
  P=K[R|t] 是方便的縮寫，但不要讓一行公式藏掉三段流程。先以外參把 world point 變成 camera point；再做 perspective divide，從三維 ray 取 normalized image coordinate；最後才由 K 換成 pixel。矩陣乘到 homogeneous image coordinate 時仍是線性的，真正的除法藏在最後的 dehomogenize。

  實作時應能逐段檢查：transform 方向是否正確、Z_c 是否為正、K 是否對應目前影像的解析度與 pixel convention。把 P 當黑盒，這三類 bug 會很難定位。
]

== Cheirality：數學允許、物理不允許的正負號

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [投影方程是對稱的], inset: .75em)[
    #set text(size: .8em)
    $Z_c < 0$（點在相機後方）照樣能除出一組 $(u,v)$，方程不抱怨，但那不是影像。
  ]
][
  #card(tint: palette.teal, title: [物理不是], inset: .75em)[
    #set text(size: .8em)
    可成像的點必須在相機前方。這個「選出物理解」的約束叫 *cheirality constraint*。
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[Part 5 從 homography 分解 pose 時，$plus.minus H$ 是同一個映射，卻給出棋盤在相機前／後兩組解，靠 cheirality 挑對的那組。]

#speaker-note[
  這是「數學允許、物理不允許」最乾淨的例子。投影方程對正負深度完全對稱:把點鏡射到相機後方,除法照做,還是得到一組合法的 pixel 座標。但相機拍不到自己背後。所以每個牽涉 pose 的演算法,最後都有一個挑符號的步驟，判準只有一條,讓重建出來的點深度為正。這個約束有個拗口的名字 cheirality,來自希臘文的「手」,和 chirality 手性同源:兩組解像左右手,鏡像對稱,只有一隻符合物理。Part 5 分解 homography 時它會實戰登場。
]

== 旋轉的表示法是 optimizer 的設計選擇

#equation[$R(theta k) = exp(theta [k]_times) = I + sin theta [k]_times + (1-cos theta) [k]_times^2$]
#v(.4em)
#row(gutter: .7em)[
  #card(tint: palette.rose, title: [Euler angles])[直觀，但有順序約定與 gimbal lock。]
][
  #card(tint: palette.teal, title: [axis-angle $theta k$])[三個自由度，正好等於 $"SO"(3)$ 的切空間維度。]
][
  #card(tint: palette.iris, title: [quaternion])[組合方便，但有 unit constraint 與雙覆蓋。]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[$[k]_times$ 是反對稱矩陣（$[k]_times^T=-[k]_times$），$exp([k]_times theta)$ 的冪級數摺疊成上式（Rodrigues formula），這正是為什麼 axis-angle 的三個分量可以直接當成無約束的優化變數，而九個矩陣元素不行。]

#speaker-note[
  旋轉矩陣有九個數，只有三個自由度：多出的六個被 R^T R=I 吃掉。axis-angle 之所以好用，是因為它就是 SO(3) 在單位元附近的切空間座標，指數映射把切空間的自由向量搬回流形上，天生滿足正交約束。calibration 實作用它，讓每個優化變數都對應旋轉的自由度，這條伏筆會在下一個 Part 的 nonlinear refinement 收回來。
]

= Part 5 · 從棋盤反推相機

== 已知、共享、每張都不同

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [known observations])[棋盤平面點 `(X,Y,0)` 與影像角點 `(u,v)`。]
][
  #card(tint: palette.iris, title: [shared])[一組 intrinsics `K`：`f_x,f_y,c_x,c_y,s`。]
][
  #card(tint: palette.amber, title: [per-view])[每張各自的 pose `(R_i,t_i)`。]
]
#v(.55em)
#callout(
  kind: "info",
  compact: true,
)[這是超定 estimation：每個角點給兩個量測，資料多於未知數。多樣 view 帶來獨立約束。]

#speaker-note[
  講 calibration 前先把帳列清楚。觀測是每個棋盤平面點 (X,Y,0) 與它的 image corner (u,v)，每個角點提供兩個量測。K 是同一台相機的共享參數，所以必須固定 zoom、focus、resolution；每張棋盤的 R_i、t_i 則各自不同。

  這是超定 estimation，但「很多點」不等於「很多獨立約束」。若每張棋盤姿態近似重複，系統仍可能 rank 不足、參數互相吸收；必須收集有 tilt、位置與影像覆蓋差異的 views。
]

== 平面棋盤把 camera equation 化成 homography

#equation[$tilde(x) tilde K[r_1,r_2,r_3,t] [X,Y,0,1]^T = H[X,Y,1]^T$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [H 的自由度])[3×3 matrix，扣除整體 scale 後有 8 個。]
][
  #card(tint: palette.teal, title: [最小資料])[四組不共線平面點對應，原則上即可定出一個 H。]
][
  #card(tint: palette.amber, title: [關鍵分解])[$H tilde K[r_1,r_2,t]$：每張 H 都含同一個 K。]
]

#speaker-note[
  平面是棋盤特別好用的原因。把棋盤座標選成 Z=0 後，camera equation 中乘 r_3 的那一欄直接消失，world plane 到 image plane 便濃縮為一個 3×3 homography H。H 有九個元素但只定義到共同尺度，因此有八個自由度；四組不共線點對應原則上就能定出它。

  更關鍵的是 H 約等於 K[r_1,r_2,t]：每張 view 都有自己的 H 與 pose，卻都包含同一個 K。下一步就是把旋轉的正交性轉成跨 views 的共享約束。
]

== 消掉 up-to-scale：外積歸零的技巧

#equation[$tilde(x) tilde H tilde(X) quad <==> quad tilde(x) times (H tilde(X)) = 0$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [為什麼用外積])[
    #set text(size: .8em)
    兩個 homogeneous 向量「相等 up to scale」= 平行 = 外積為零。討厭的未知尺度被消掉了。
  ]
][
  #card(tint: palette.teal, title: [三條方程、秩 2])[
    #set text(size: .8em)
    外積給三個分量，但它們以 $tilde(x)$ 的座標為係數線性相關，每組對應只取兩條獨立方程。
  ]
][
  #card(tint: palette.amber, title: [堆成線性系統])[
    #set text(size: .8em)
    $H$ 的 9 個元素攤平成 $h$，每組對應貢獻 2 列：$A h = 0$，$A$ 是 $2n times 9$。
  ]
]
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[8 個自由度、每組對應 2 條方程 ⇒ 4 組不共線點原則上定出 $H$，棋盤給幾十組，多的全部拿去對抗 noise。]

#speaker-note[
  DLT 的前處理是一個會反覆用到的技巧:up-to-scale 的等式沒法直接進線性代數,但「相差一個尺度」就是「平行」,而平行的代數判準是外積為零，尺度在外積裡自己消掉了。細節是秩:外積的三個分量不獨立,每組對應真正貢獻兩條方程,和 homography 八個自由度一除,就得到最小四組對應的結論。棋盤上幾十個角點,多出來的方程全是抗噪的本錢。
]

== DLT：把 up-to-scale 對應變成最小奇異向量

#equation[$tilde(x) times (H tilde(X)) = 0 quad arrow quad A h = 0 quad arrow quad op("min")_(||h||=1) ||A h||^2$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [解], inset: .7em)[
    #set text(size: .78em)
    $||A h||^2=h^T (A^T A) h$ 是 Rayleigh quotient，解為 $A^T A$ 最小特徵值的特徵向量，等價於 $A$ 最小 singular value 對應的 right singular vector。
  ]
][
  #card(tint: palette.rose, title: [數值衛生], inset: .7em)[
    #set text(size: .78em)
    先平移到質心、縮放到平均距離 `sqrt(2)`，再 denormalize `H=T_x^-1 H' T_X`。
  ]
]
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[與 Harris 用 $M$ 的最大 eigenvalue 判斷角點，是同一個「二次型 + 特徵分解」骨架的兩個角落：一個取最大，一個取最小。]

#speaker-note[
  兩個 homogeneous vector 平行等價於外積為零。noise 下沒有非零精確解，因此改最小化代數誤差。Hartley normalization 不改幾何，只讓線性系統不要被 pixel 與世界單位的尺度差拖垮。這裡把 Part 3 的伏筆收回來：Harris 是對稱矩陣 M 的最大 eigenvalue 問題，DLT 是對稱矩陣 A^T A 的最小 eigenvalue 問題，兩者都是同一個 Rayleigh quotient 極值問題的不同角落。
]

== 為什麼一定要 normalize：條件數的平方懲罰

#equation[$kappa(A^T A) = kappa(A)^2$]
#v(.45em)
#row(widths: (1fr, 1.05fr), gutter: 1em)[
  #card(tint: palette.rose, title: [地雷], inset: .75em)[
    #set text(size: .8em)
    world 座標幾公分、pixel 座標幾千：$A$ 的 columns 差好幾個數量級，conditioning 在成 normal equation 的瞬間*平方惡化*。
  ]
][
  #card(tint: palette.teal, title: [Hartley normalization 處方], inset: .75em)[
    #set text(size: .8em)
    兩邊的點各自平移到質心、isotropic 縮放到平均距離 $sqrt(2)$，在規範化座標估 $H'$，再剝回：
    #equation[$H = T_x^(-1) H' T_X$]
  ]
]
#v(.4em)
#quote-card(
  tint: palette.iris,
)[幾何問題一個字都沒變，變的只是線性系統的條件數。「*先把資料擺到數值友善的位置*」在所有幾何視覺問題裡通用。]

#speaker-note[
  這是數值分析對幾何視覺最重要的一次干預。條件數衡量輸入誤差被放大的倍率,而解最小平方時實際操作的矩陣是 A 轉置 A,條件數直接平方。座標尺度差三個數量級,平方後是六個，double 的有效位數就這樣被吃掉一半。Hartley 那篇 In Defense of the Eight-Point Algorithm 講的就是這件事:被嫌棄的八點法其實沒問題,有問題的是沒 normalize 的實作。質心平移加上均距 sqrt(2) 的縮放是死記的處方,但理由要懂:讓 A 的各 column 同一個量級。
]

== Zhang：旋轉的正交性變成對 K 的線性約束

#equation[$B=K^(-T)K^(-1)$]
#equation[$h_1^T B h_2=0, quad h_1^T B h_1-h_2^T B h_2=0$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.teal, title: [每個 view])[由 `r_1 perpendicular r_2` 與等長性貢獻兩條約束。]
][
  #card(tint: palette.iris, title: [至少三個 view])[對稱 B 有 6 項、扣 scale 剩 5 個自由度。]
][
  #card(tint: palette.amber, title: [資料收集])[tilt、位置、影像覆蓋要多樣。避開近似重複姿態。]
]

#speaker-note[
  這是 Zhang method 最漂亮的地方。由 H=K[lambda r_1,lambda r_2,lambda t] 可知，先左乘 K^-1 後的前兩欄必須互相垂直、而且等長。把未知的 K 以 B=K^-T K^-1 包起來，這兩個原本看似非線性的旋轉條件，就變成投影片上的兩條對 B 元素線性的方程。

  對稱 B 有六項、扣掉尺度剩五個自由度，所以每個 view 供兩條約束，至少三個姿態多樣的 views。解出 B 後，再以 Cholesky 類型的分解取回符合上三角慣例的 K；近似重複的棋盤姿態沒有提供新的獨立資訊。
]

== 取回 pose，再把幾何誤差磨到底

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [pose from H])[
    `K^-1 H = [lambda r_1, lambda r_2, lambda t]`\
    normalize、cross product 補 `r_3`，再投影回 `SO(3)`。選正深度符號。
  ]
][
  #card(tint: palette.teal, title: [nonlinear refinement])[
    #equation[$op("min") sum_(i,j) ||op("project")(K,R_i,t_i,X_j)-x_("ij")||^2$]
    LM 在 Gauss Newton 的快與 gradient descent 的穩之間調節。
  ]
]

#speaker-note[
  線性初值先給每張 view 的 pose：K^-1 H 的三欄分別對應同尺度的 r_1、r_2、t，先正規化，再用 cross product 補出 r_3；不過 noise 會讓它不是精確旋轉，且 H 與 -H 的符號仍須靠正深度挑選。

  這個 closed-form 解最小化的是 algebraic error，任務是把答案放進正確 basin。接著 LM 同時調整 K 與所有 per-view pose，直接最小化有 pixel 單位的 reprojection error；這才是幾何上真正可驗收的目標。下一頁把 LM 這台機器拆開看。
]

== 兩個收尾細節：投影回 $"SO"(3)$、挑對符號

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [noise 讓 $r_1, r_2$ 不再正交], inset: .75em)[
    #set text(size: .8em)
    本週程式用 Gram Schmidt 修正，更一般的是 orthogonal Procrustes：SVD $M = U Sigma V^T$，Frobenius 距離最近的旋轉是 $U V^T$（修正 $det$ 符號）。
  ]
][
  #card(tint: palette.rose, title: [Part 4 的伏筆兌現], inset: .75em)[
    #set text(size: .8em)
    $-H$ 與 $H$ 是同一個映射，但兩個符號給出的 pose 一個讓棋盤在相機前方、一個在後方，*cheirality*：選深度為正的那組。
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[「數學不區分、物理區分」的兩件事在同一步出現：流形約束靠投影修復，符號歧義靠物理挑選。]

#speaker-note[
  從 K 反演 H 拿到的 r1、r2 帶著 noise,不會恰好正交,單位長也對不齊,而叉積補出來的 r3 會把誤差繼續放大，所以要投影回旋轉流形。Gram Schmidt 是順手的做法,教科書級的答案是 Procrustes 定理:對近似旋轉做 SVD,把奇異值全部拍成一,U V 轉置就是 Frobenius 意義下最近的旋轉。符號問題則是 Part 4 埋的 cheirality 正面兌現:homography 乘負一是同一個映射,分解出的兩組 pose 一前一後,深度正負一查便知。這兩步都小,漏掉任何一步,送進 LM 的初值就不在流形上或不在正確 basin。
]

== Algebraic error 與 geometric error 不是同一件事

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.amber, title: [algebraic · $||A h||$], inset: .75em)[
    #set text(size: .8em)
    為了*線性可解*而構造的量。與「影像上差幾個 pixel」沒有直接的度量關係。
  ]
][
  #card(tint: palette.teal, title: [geometric · reprojection], inset: .75em)[
    #equation[$r_("ij") = op("project")(K, R_i, t_i, X_j) - x_("ij")$]
    #set text(size: .8em)
    我們真正在乎的量，單位是 pixel，但對參數高度非線性，沒有 closed form。
  ]
]
#v(.5em)
#quote-card(
  tint: palette.iris,
)[Pattern：線性 closed-form（algebraic）拿*正確 basin 裡的初值*，非線性優化（geometric）把誤差磨到底。triangulation、pose estimation、bundle adjustment 全是變奏。]

#speaker-note[
  到這裡必須誠實面對一件事:前面整條線性道路,最小化的都是 algebraic error，它是為了讓問題塞進 SVD 而構造的,幾何意義說不清楚。真正該最小化的是 reprojection error,它有單位、有直覺、可驗收,但非線性。於是整個 calibration 的架構是一個雙人舞:線性方法犧牲目標的正確性換取全域可解,非線性方法犧牲全域性換取目標的正確性,兩者接力。這個 pattern 請直接背下來,之後三維視覺裡到處都是它。
]

== LM：在 Gauss Newton 的 normal equation 裡插入 damping

#equation[$r(x+Delta) approx r + J Delta quad arrow quad op("min")_Delta ||r+J Delta||^2 quad arrow quad (J^T J) Delta = -J^T r$]
#v(.35em)
#equation[$(J^T J + lambda D) Delta = -J^T r$]
#v(.4em)
#row(gutter: .75em)[
  #card(tint: palette.teal, title: [λ 小 → Gauss Newton])[
    #set text(size: .8em)
    信任二階近似，收斂快，$J^T J$ 病態或展開失效時亂跳。
  ]
][
  #card(tint: palette.iris, title: [λ 大 → gradient descent])[
    #set text(size: .8em)
    方向趨近負梯度、步長縮小，保守但穩。
  ]
][
  #card(tint: palette.amber, title: [自適應])[
    #set text(size: .8em)
    試走一步：cost 降 → 接受、調小 $lambda$，升 → 拒絕、調大 $lambda$。
  ]
]
#v(.35em)
#callout(
  kind: "warn",
  compact: true,
)[LM 是 local optimizer：起點錯照樣掉進錯的 basin，這正是前面整條線性 closed-form 道路存在的理由。]

#speaker-note[
  LM 的推導從 Gauss Newton 開始：residual 做一階展開，平方和變成步長 Delta 的二次函數，極小化得 normal equation。GN 在近似好的區域收斂快，但沒有任何機制保證每一步都下降。damping 項 lambda D 是在「一階方法的穩」和「二階近似的快」之間連續插值，用 cost 的實際表現決定信任區域。這個 pattern 之後 triangulation、pose estimation、bundle adjustment 全部沿用：線性拿初值、LM 磨幾何誤差。
]

== Calibration lab：把 cost function 畫到影像上

#row(gutter: .8em)[
  #card(tint: palette.teal, title: [summary])[讀 `K`、每張 pose 與 overall RMS。]
][
  #card(tint: palette.iris, title: [overlay])[綠色是觀測點。紅色是重投影點。兩者的連線就是 residual。]
][
  #card(tint: palette.rose, title: [diagnostics])[逐 view RMS 與 include/exclude。找 outlier 與系統性殘差。]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[低 RMS 仍要搭配參數與 residual 分布檢查。邊緣放射狀殘差提示 distortion。單一 view 特別差時先查觀測與影像品質。]

#speaker-note[
  驗收要同時看數字與圖。overall RMS 是所有 residual 的摘要；overlay 中綠色觀測角點與紅色重投影點的連線，才讓你看見誤差方向與空間分布。再看逐 view RMS，才能分辨是一張模糊、角點錯誤的影像拖累，還是模型在所有影像上系統性失效。

  低 RMS 仍要檢查 K 是否合理，以及殘差是否在邊緣放射狀分布；後者提示缺少 distortion。include/exclude 某一 view 不是只重算該 view 的 pose，因為 K 是共享量，移除資料後所有參數都必須重新估計。
]

== 病徵 → 病因：讀 residual 的故障定位表

#table(
  columns: (1fr, 1.4fr),
  [病徵], [先查什麼],
  [單一 view 特別差], [那張的角點觀測、motion blur、棋盤不平],
  [殘差在影像四周呈放射狀], [lens distortion 缺席的簽名，模型類太小，不是估計壞掉],
  [所有 view 共享一致偏移], [座標約定、棋盤點序、principal point],
  [RMS 低到不合理但 $f$ 很怪], [資料 degenerate、自由度互相吸收錯誤],
)
#v(.45em)
#quote-card(tint: palette.rose)[「跑完了」和「對了」是兩回事，*fit 得好從來不等於參數對。*]

#speaker-note[
  一個 scalar RMS 會藏結構,診斷要看分解後的東西:逐 view 的 RMS、error vector 的空間分布、剔除可疑 view 後 K 是否漂移。這張表是查案順序。特別注意最後一列,它最反直覺:RMS 漂亮但焦距離譜,通常是 views 姿態太單一,好幾個參數在互相打掩護，principal point 挪一點、焦距補一點,殘差一樣小,參數全錯。這就是為什麼資料多樣性排在演算法之前。
]

== 本週 dataset 的判決：殘差自己說了下一步

#row(gutter: .8em)[
  #card(tint: palette.iris, title: [13 張真實 views])[
    #set text(size: .8em)
    真實影像 + 預先抽好的角點。
  ]
][
  #card(tint: palette.teal, title: [overall RMS ≈ 1.55 px])[
    #set text(size: .8em)
    pinhole-only model 收斂後的成績。
  ]
][
  #card(tint: palette.rose, title: [邊緣殘差呈放射狀])[
    #set text(size: .8em)
    residual 的空間分布，不只是一個 scalar。
  ]
]
#v(.55em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.amber, title: [Part 1 的伏筆收回], inset: .75em)[
    #set text(size: .8em)
    當初「刻意只估 pinhole」的決定，在這裡兌現成看得見的模型缺漏，下一個該加的成分是 distortion，殘差已經替你決定了。
  ]
][
  #card(tint: palette.teal, title: [離開前自問五題], inset: .75em)[
    #set text(size: .74em)
    ① 一張 view 的 world plane → image 是哪個變換？② 多 views 間什麼共享、什麼獨立？③ $r_1 perp r_2$ 怎麼變成對 $K$ 的線性約束？④ closed-form 之後為何還要 refinement？⑤ 為何剔除一張 view 後所有參數都要重估？
  ]
]

#speaker-note[
  把數字釘死:十三張真實影像,pinhole-only,收在 1.55 pixel。這個數字不算漂亮,而且邊緣殘差確實呈放射狀，這正是我們想要的教學效果:模型的缺漏自己顯影。如果當初就把 distortion 加進去,學生只會看到一個更小的 RMS,學不到「殘差的形狀指出下一個模型成分」這件事。五個離場問題的答案全在前文,答不出哪題,就回哪一頁。
]

= Part 6 · 用第二隻眼買回深度

== Triangulation：兩條 ray 提供第二個約束

#source-image(
  "figs/public/epipolar-geometry.svg",
  width: 46%,
  height: 1.35in,
  credit: [$C_L,C_R$ are $O_L,O_R$ in the source · two rays meet at $X=P$ · ZooFari · Public domain],
)
#v(.35em)
#equation[$X(lambda_L)=C_L+lambda_L d_L, quad X(lambda_R)=C_R+lambda_R d_R$]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[有 noise 時 rays 通常是 skew lines。baseline 太短或物體太遠時夾角太小，深度會非常不穩。]

#speaker-note[
  單張圖中一個 pixel 是一條從 camera center 出發的 ray；兩眼找到同一世界點後，第二條 ray 提供了缺少的約束，理想情況兩條 ray 在 X 相交。以 X(lambda_L)=C_L+lambda_L d_L、X(lambda_R)=C_R+lambda_R d_R 寫出，就是同時解兩個沿 ray 的深度參數。

  真實資料有 pixel noise 與 calibration error，兩條 ray 多半是 skew lines，因此求的是兩線最近點的最佳近似。conditioning 取決於交角：baseline 太短、物體太遠或 rays 幾乎平行時，微小的像素誤差都會被放大成巨大的深度誤差。
]

== Epipolar geometry 把二維搜尋降成一維

#row(widths: (1.1fr, 1fr), gutter: 1em)[
  #source-image(
    "figs/public/epipolar-geometry.svg",
    width: 95%,
    credit: [$X=P$, $x_L=p_L$, $x_R=p_R$, $e_L=E_L$, $e_R=E_R$ · ZooFari · Public domain],
  )
][
  #card(tint: palette.iris, title: [平面決定線], inset: .75em)[
    #set text(size: .78em)
    $C_L, C_R, X$ 三點決定一個 epipolar plane，它與每張影像平面的交線就是 epipolar line。這條平面必過 baseline，所以每條 epipolar line 都通過該影像的 epipole（$e_L, e_R$：baseline 與影像平面的交點）。正確 match 必落在對應的線上。
  ]
]
#v(.4em)
#row(gutter: .8em)[
  #equation[$x_R^T E x_L = 0, quad E=[t]_times R$]
][
  #equation[$x_("R,pixel")^T F x_("L,pixel")=0, quad F=K_R^(-T) E K_L^(-1)$]
]

#speaker-note[
  對左圖一個 pixel 而言，未知深度讓它對應到一整條 3D ray；這條 ray 和兩個 camera center 決定一個 epipolar plane。平面切到右影像就是 epipolar line，因此正確 match 不再能在整張右圖任意找，只能在線上找，二維搜尋降成一維。每條線都經過 epipole，也就是 baseline 穿過影像平面的點。

  E 用 normalized coordinates，F 直接吃 pixel coordinates，兩者都只給候選所在的線；外觀 cost 與 matching 才從線上的候選中選出同一個世界點。幾何縮小搜尋，並沒有自己解決 correspondence。
]

== $E = [t]_times R$：從三重積讀出它的全部性質

#equation[$x_R dot (t times R x_L) = 0 quad "（三向量共面 ⟺ 純量三重積為零）"$]
#v(.45em)
#row(gutter: .75em)[
  #card(tint: palette.iris, title: [線的係數])[
    #set text(size: .78em)
    $E x_L$ 就是右圖 epipolar line，$x_R$ 在線上所以內積為零。
  ]
][
  #card(tint: palette.teal, title: [rank 2])[
    #set text(size: .78em)
    $[t]_times$ 秩為 2 ⇒ $"rank"(E) = 2$，null space 就是 epipole。
  ]
][
  #card(tint: palette.rose, title: [尺度不可觀測])[
    #set text(size: .78em)
    $t$ 與場景一起放大 $lambda$ 倍，影像一個 pixel 都不變，重建天生 up-to-scale。
  ]
]
#v(.45em)
#callout(
  kind: "warn",
  compact: true,
)[想要公尺，必須從外部注入尺度：量 baseline、放已知尺寸的物體，或上其他感測器。Part 1 的 up-to-scale 在這裡收口。]

#speaker-note[
  E 的推導只用一件事:右 ray 方向、baseline、被旋轉過來的左 ray 方向,三個向量躺在同一個 epipolar plane 上,而三向量共面若且唯若純量三重積為零。把外積寫成反對稱矩陣的乘法,就得到 E 等於 [t]x R。性質全部從這個形式讀出來:E 作用在左點上給出右圖的線，[t]x 秩二所以 E 秩二,退化方向就是 epipole，最重要的是尺度，整個宇宙連同 baseline 一起縮放,所有影像不變,所以純視覺重建拿不到公尺。機器人上的實務答案:stereo rig 出廠量好 baseline,或者 IMU、輪速計來補尺度。
]

== Rectification：把幾何重參數化成水平 scanline

#row(widths: (1.8fr, 1.1fr), gutter: .8em)[
  #source-image(
    "figs/public/stereo-rectification.png",
    width: 98%,
    credit: [Bild 1/2 = source planes · Epipolarebene = epipolar plane · green planes = rectified · CC BY-SA 3.0],
  )
][
  #card(tint: palette.teal, title: [做的事], inset: .7em)[
    #set text(size: .76em)
    對每張影像各自施一個 projective warp，虛擬地把兩台相機轉成光軸平行、影像平面共面。這是純粹的 coordinate change，不創造新資訊，代價是重採樣與 invalid border。warp 後所有 epipolar line 都變成水平線，correspondence 只需沿 `u` 搜尋。
  ]
]

#speaker-note[
  工程上幾乎總會先做 rectification。左圖是 warp 前，同一個對應點對雖然在同一條 epipolar line 上，但那條線是斜的，要沿斜線取樣，右圖 warp 後，matching 的候選從斜線變成水平 scanline，也讓 disparity 有乾淨的單一方向約定，直接對接下一頁的公式。
]

== Disparity 與深度的反比

#equation[$u_L=f X/Z+c_x, quad u_R=f(X-B)/Z+c_x$]
#equation[$d=u_L-u_R=f B/Z quad arrow quad Z=f B/d$]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.teal, title: [near])[大 disparity。]
][
  #card(tint: palette.iris, title: [far])[小 disparity。`d to 0` 時深度趨向無窮。]
][
  #card(tint: palette.rose, title: [error propagation])[$|delta Z| approx Z^2/(f B) |delta d|$。遠處誤差平方惡化。]
]

#speaker-note[
  這是 stereo 最重要的一行。rectified rig 中左右相機只有水平 baseline B，對同一個 X 相減便消去 principal point 與 X，得到 disparity d=u_L-u_R=fB/Z，因此 Z=fB/d。建議手算：f=800 px、B=.12 m、d=48 px，得到 Z=2 m。

  近物有大 disparity，遠物的 disparity 逼近零；由誤差傳遞可見 |delta Z| 約為 Z²/(fB)|delta d|，所以遠處深度誤差平方惡化。增大 fB 能改善解析度，但長焦縮小視野、大 baseline 又讓遮擋與外觀差異更嚴重，rig 設計沒有免費午餐。
]

== Correspondence 需要外觀假設，也需要知道何時拒答

#equation[$"SSD"(x,y,d)=sum_((i,j) in W) [I_L(x+i,y+j)-I_R(x-d+i,y+j)]^2$]
#v(.45em)
#row(gutter: .65em)[
  #card(tint: palette.rose, title: [textureless])[沿線 cost 幾乎不變：aperture problem。]
][
  #card(tint: palette.rose, title: [repeated texture])[多個相近極小值，答案不唯一。]
][
  #card(tint: palette.rose, title: [occlusion / specular])[另一眼沒有對應，或 Lambertian 假設失效。]
][
  #card(tint: palette.teal, title: [consistency check])[將不一致區域標為 invalid。下游可直接辨識可信的深度範圍。]
]

#speaker-note[
  幾何把搜尋縮到一維，appearance 負責挑答案。SSD 是最基本的 data term：比較左邊一個 window 與右邊候選視差 window 的平方差；window 提供 context，但太小沒有紋理辨識力，太大又會跨越深度邊界。

  textureless 區域沿線的 cost 幾乎一樣，是 aperture problem；重複紋理有多個近似極小值；occlusion 根本沒有另一眼對應；specular 則違反 Lambertian 外觀一致。left-right consistency 不應硬猜，應將不一致處標成 invalid，讓下游知道可信深度的範圍。
]

== Cost 的選擇就是不變性的選擇

#table(
  columns: (auto, 1fr, 1fr),
  [cost], [對什麼不變], [代價],
  [SSD / SAD], [什麼都不：假設 brightness constancy], [曝光差直接失效],
  [NCC], [線性亮度變化 $a I + b$], [計算較貴、小 window 不穩],
  [Census], [任何保序的亮度變換], [只剩排序資訊，弱紋理更難],
)
#v(.4em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.amber, title: [成本帳], inset: .7em)[
    #set text(size: .78em)
    逐 pixel 對視差範圍 $D$ 取 argmin：總成本 $O(H dot W dot D dot |W|)$。
  ]
][
  #card(tint: palette.teal, title: [升格成 energy], inset: .7em)[
    #set text(size: .78em)
    data term 累積 matching cost + smoothness term 懲罰視差跳變，「量測 + 先驗」，Part 7 的 snake 是同一結構的另一個化身。
  ]
]

#speaker-note[
  換 cost function 不是換口味,是換「你願意對哪種光度變化免疫」。SSD 賭兩眼曝光一致，NCC 把 window 各自減均值除標準差,線性的增益和偏移全數消掉,直接對抗曝光差，Census 更激進,只留每個 pixel 和鄰居的大小關係,任何單調的 tone curve 都動不了它,代價是把量值資訊全丟了。而逐點 argmin 再好的 cost 也容易被騙,標準解法是把問題升格成 energy minimization，data term 拉向量測,smoothness term 編碼「深度大致連續」的先驗。記住這個結構,下一個 Part 的 snake 就是它在輪廓問題上的化身,伏筆先埋好。
]

= Part 7 · 一條輪廓，補足邊緣

== Active contour 把「合理輪廓」寫成 energy

#row(widths: (1fr, 1.05fr), gutter: 1em)[
  #source-image(
    "figs/public/snake-contour-forces.png",
    width: 100%,
    credit: [Green samples: discrete contour converging to the boundary · Dake · CC BY-SA 2.5],
  )
][
  #card(tint: palette.iris, title: [三個力的分工], inset: .75em)[
    #set text(size: .76em)
    #equation[$E[v] = integral [alpha |v'(s)|^2 + beta |v''(s)|^2 + E_("ext")(v(s))] dif s$]
    影像項 $E_("ext")$（黃色箭頭）把離群的頂點拉向邊界，curvature 項 $beta|v''|^2$（紅色箭頭）把尖點拉回鄰居的平均，是平滑 prior，continuity 項 $alpha|v'|^2$ 鼓勵取樣點間距均勻，避免輪廓在某處擠成一團。
  ]
]

#speaker-note[
  Snake 把今天的模板濃縮成最小例子：資料項拉向影像、internal energy 表達我們對輪廓的先驗。只靠 edge 不足以得到一條完整曲線，因此必須有 prior，圖中那個被 image force 和 curvature 拉扯的尖點，就是這三項角力最直觀的畫面。
]

== $E[v]$ 是泛函：自變數是一整條曲線

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [function], inset: .75em)[
    #equation[$f: RR arrow RR$]
    #set text(size: .8em)
    輸入一個數。極值條件：$f'(x)=0$。
  ]
][
  #card(tint: palette.teal, title: [functional], inset: .75em)[
    #equation[$E: v(dot) arrow RR$]
    #set text(size: .8em)
    輸入一條曲線。極值條件：Euler Lagrange 方程。
  ]
]
#v(.5em)
#equation[$delta E = 0 quad <=> quad -alpha v'' + beta v'''' + nabla E_("ext") = 0$]
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[原論文以半隱式迭代解這條四階方程，本週作業改用 Williams Shah 的離散 greedy，放棄變分機械，直接在離散 energy 上做局部搜尋，極小化同一類 objective。]

#speaker-note[
  這邊我要處理的其實是泛函，定義域是整個曲線空間，每條候選輪廓對應一個實數分數。求極值不能對 x 微分，要對「曲線的擾動」微分，這就是變分法，一階條件從 f prime 等於零升級成 Euler Lagrange 方程，snake 的版本是一條四階方程：內力（拉伸與彎曲的恢復力）與影像力在極值曲線上逐點平衡。知道這個身分，下一頁的離散 greedy 才讀得懂：它只是換了一個求極小的辦法，objective 的物種沒變。
]

== 本週作業：離散 greedy snake

#equation[$E_("snake")=sum_i [alpha E_("cont")(i)+beta E_("curv")(i)+gamma E_("img")(i)]$]
#v(.45em)
#row(widths: (1.15fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [每個點的候選 window])[
    窮舉 `(2r+1) times (2r+1)` 位置。三個 energy 各自在 window 中 normalize 到 `[0,1]`，再加權選最小。
  ]
][
  #card(tint: palette.teal, title: [image energy])[
    #equation[$E_("img")(v)=-|nabla(G_sigma*I)(v)|$]
    Gaussian 同時降噪、拓寬 edge 的 attraction basin。
  ]
]

#speaker-note[
  作業採 Williams Shah 的離散 greedy 版本，而不是直接解上一頁的 Euler–Lagrange 方程。把輪廓採樣成一串點後，每次固定其他點，只在目前點附近的 (2r+1)×(2r+1) candidate window 窮舉，將三個 normalized energy 加權後選最小，因此它是 cyclic block coordinate descent。

  image energy 取負的平滑後 gradient magnitude，edge 越強 energy 越低；Gaussian 同時降噪並拓寬 attraction basin。這個非凸局部搜尋能逐輪視覺化，但也高度依賴初始輪廓與每個 energy 的尺度處理。
]

== 三項 energy 逐項推導：每一項都管一件事

#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [continuity · 反聚團], inset: .7em)[
    #equation[$E_("cont")(v) = (macron(d) - ||v - v_(i-1)||)^2$]
    #set text(size: .76em)
    $macron(d)$ 是每輪重算的平均鄰點距離：懲罰「偏離平均間距」，避免點被強 edge 吸成一團、留下大段輪廓無人處理。
  ]
][
  #card(tint: palette.teal, title: [curvature · 抗彎剛性], inset: .7em)[
    #equation[$E_("curv")(v) = ||v_(i-1) - 2v + v_(i+1)||^2$]
    #set text(size: .76em)
    二階導數的中央差分：三點等距共線時中間點恰是前後平均，此項為零，急彎時暴漲。
  ]
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[$beta$ 太小，輪廓追著 noise 長鋸齒，太大，把手、凹槽、尖角被 prior 抹掉，*prior 補足資料，也可能壓過資料。*]

#speaker-note[
  離散化不是機械翻譯,兩項都有實作的心思。continuity 項如果照連續版直接懲罰一階導數,輪廓會整體縮短，Williams Shah 改成懲罰「偏離平均間距」,每輪先算當前的平均鄰距再當目標,效果是讓取樣點沿輪廓均勻分布。curvature 項是乾淨的中央差分,幾何讀法很直觀:中間點被拉向前後兩點的平均。β 的雙面性在這裡最直白，它是我們花錢買的先驗,買太多,真實的尖角也被當成 noise 燙平了。
]

== Otsu：一個乾淨的小定理

#equation[$sigma^2 = sigma_w^2(t) + sigma_b^2(t), quad sigma^2 "與" t "無關"$]
#v(.45em)
#row(gutter: .75em)[
  #card(tint: palette.iris, title: [變異數分解])[
    #set text(size: .78em)
    把總變異數按 threshold $t$ 拆成組內 + 組間。
  ]
][
  #card(tint: palette.teal, title: [對偶])[
    #set text(size: .78em)
    總和固定 ⇒「最大化組間」=「最小化組內」，同一件事。
  ]
][
  #card(tint: palette.amber, title: [計算])[
    #set text(size: .78em)
    對 256 個 threshold 掃一遍 histogram：$O(N + 256)$。
  ]
]
#v(.45em)
#callout(
  kind: "warn",
  compact: true,
)[Otsu 繼承了 histogram 的盲點（Part 2）：看分布不看空間，假設前景背景在 intensity 上可分，它不理解物體。]

#speaker-note[
  Otsu 值得停一頁,因為它是課程裡最小的完整定理。把 pixel 按 threshold 分成兩組,總變異數恆等於組內變異加組間變異,而總變異數根本不依賴 threshold，所以「讓兩組各自緊」和「讓兩組離得遠」是同一個最佳化問題,挑好算的那個。組間變異只需要兩組的權重和均值,全部從 histogram 的累積量讀出,掃 256 個候選就完事。但別忘了它站在 histogram 上,Part 2 說過的限制全額繼承:手提箱的反光把前景亮度打穿背景的範圍時,Otsu 給出的 mask 就會斷，這正是下一頁 initializer 要收拾的爛攤子。
]

== Initializer：blur → Otsu → components → bbox

#row(gutter: .7em)[
  #card(tint: palette.iris, title: [1 · blur + Otsu])[
    #set text(size: .76em)
    Gaussian 壓噪，histogram 上取 threshold，得前景 mask。
  ]
][
  #card(tint: palette.teal, title: [2 · 8-connected components])[
    #set text(size: .76em)
    又是圖論。丟掉碰邊界的與太小的。
  ]
][
  #card(tint: palette.amber, title: [3 · bbox 聚類])[
    #set text(size: .76em)
    用鄰近性合併，對付被反光切斷成數塊的物體。
  ]
][
  #card(tint: palette.rose, title: [4 · 矩形重取樣])[
    #set text(size: .76em)
    贏家 cluster 的 bbox 內縮，沿周長均勻取 $N$ 點。
  ]
]
#v(.5em)
#quote-card(
  tint: palette.teal,
)[刻意粗糙，粗糙得有原則：它只負責把矩形放進*正確的 basin*，不負責解出輪廓。剩下的路讓 snake 自己走。]

#speaker-note[
  這條 pipeline 是經典 binary image analysis 的迷你復習:Otsu 只看 intensity 分布,connected components 補回空間關係,bbox 聚類處理 Otsu 的斷裂後遺症,最後輸出一個誠實的矩形。設計哲學值得說破:initializer 和 snake 的分工是「進對 basin」對「谷內下降」,前者不必精確,後者無法跨谷。把 initializer 做得太聰明,反而掩蓋 snake 的行為,學生就看不到局部優化的真實性格了。
]

== Initialization 決定你落在哪個 basin

#row(widths: (1.1fr, 1fr), gutter: 1em)[
  #source-image(
    "figs/public/gradient-descent-basins-labeled.png",
    width: 96%,
    height: 1.3in,
    credit: [Three initializations follow separate trajectories toward local minima · Jacopo Bertolotti · CC0],
  )
][
  #card(tint: palette.iris, title: [greedy snake 是非凸的局部搜尋], inset: .75em)[
    #set text(size: .78em)
    每輪只做 block coordinate descent，只能沿 $E_("snake")$ 這條曲面往下走一小步，走不出目前所在的 basin。init 決定初始 x 落在哪一段，粗初始化（blur → Otsu → connected components → bbox）的唯一任務，就是把它放進正確 basin，不是先把答案描好。
  ]
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[iterations 只能在同一個 basin 內多走幾步，不能修復錯的 objective、錯的 weights，或錯的 initial basin，這對應圖中琥珀色起點：它離目標輪廓不遠，卻已經越過了分隔兩個 basin 的山脊。]

#speaker-note[
  Otsu 從 histogram 取得 intensity 分布，connected components 再引入空間關係。這張圖把上一頁的「非凸局部搜尋」畫成具體的能量曲面：greedy 更新只會往下走，走到哪個谷底完全由起點決定，這就是為什麼 initialization 的品質比多跑幾輪 iteration 更關鍵。
]

== Homework notebook：用參數讀懂失敗

#table(
  columns: (auto, 1fr, 1fr),
  [parameter], [增加時的效果], [代價],
  [`alpha`], [點距更均勻], [局部伸縮更僵],
  [`beta`], [輪廓更平滑], [尖角、凹部被抹掉],
  [`gamma`], [更服從 edge], [更容易被內部紋理劫走],
  [`sigma`, `r`], [吸引範圍／單輪步幅變大], [定位變鈍／跳到錯 edge],
)
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[南瓜、印花箱、手提箱分別測試平滑性、內部 texture 與初始化斷裂。每一種失敗都能對應回 energy 的某一項。]

#speaker-note[
  參數沒有放諸四海皆準的好數字。alpha 增加會更強地維持均勻點距，代價是局部伸縮更僵；beta 增加會更平滑，也會抹掉尖角與凹部；gamma 增加讓輪廓更服從 edge，卻更容易被內部 texture 劫走；sigma 與搜尋半徑 r 則以定位精度交換吸引範圍與單輪步幅。

  南瓜、印花箱、手提箱分別刻意測試平滑性、內部紋理與初始化斷裂。請先由 energy 定義預測失敗，再到 notebook 驗證；這比背一組參數更能遷移到新資料。
]

= 收束

== 同一個 estimation template

#row(widths: (1.15fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [模型與量測])[
    pinhole：ray 與投影\
    calibration：棋盤平面與角點\
    stereo：兩眼幾何與外觀\
    snake：影像 gradient 與封閉曲線
  ]
][
  #card(tint: palette.teal, title: [假設與診斷])[
    每個解都有 error、residual 或 invalid mask。\
    #v(.35em)
    *模型失效提供下一步的建模方向。*
  ]
]
#v(.6em)
#quote-card(tint: palette.amber)[好的 vision 系統輸出答案，也暴露自己的假設、誤差與不確定性。]

#speaker-note[
  最後回到第一頁。pinhole 用 ray 與投影解釋 pixel；calibration 用平面棋盤與角點估 K、pose；stereo 用兩眼幾何與外觀買回深度；snake 用 gradient 與封閉曲線 prior 補足斷裂邊緣。它們看似不同，都是同一個 estimation template：選模型類、定義 discrepancy、加入 constraints 或 prior、求解，然後檢查 error、residual 或 invalid mask。

  最重要的產出不是一個看起來漂亮的答案，而是知道它依賴什麼假設、在哪裡不可信。殘差的形狀、invalid depth 與失敗模式不是附帶資訊，而是下一步該改資料、改模型或加量測的證據。
]

== References

#set text(size: .8em)
- Richard Szeliski, *Computer Vision: Algorithms and Applications*, 2nd ed.
- Hartley & Zisserman, *Multiple View Geometry in Computer Vision*, 2nd ed.
- Forsyth & Ponce, *Computer Vision: A Modern Approach*, 2nd ed.
- Zhang (2000), *A Flexible New Technique for Camera Calibration*.
- Canny (1986)， Harris & Stephens (1988)， Kass, Witkin & Terzopoulos (1988)， Otsu (1979).

#ending-slide(title: [Q & A])
