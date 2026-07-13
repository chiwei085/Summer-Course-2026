#import "@local/summer-course:0.1.0": *

#show: course-theme.with(
  config-info(
    title: [Geometry of Robot Motion],
    subtitle: [Week 4 · Lie Groups, Kinematics, and Control],
    author: [獵奇緯],
    institution: [Summer Course],
    short-title: [Week 4 · Robot Kinematics],
  ),
)

#let tiny = 0.72em
#let equation(body) = align(center)[#text(size: 1.18em)[#body]]
#let theorem(title, body) = card(tint: palette.iris, title: title, inset: .7em)[
  #set text(size: .78em)
  #body
]
#let definition(title, body) = card(tint: palette.teal, title: title, inset: .7em)[
  #set text(size: .78em)
  #body
]
#let claim(body, tint: palette.amber) = block(
  width: 100%,
  fill: tint.lighten(92%),
  stroke: (left: 5pt + tint),
  radius: (right: 10pt),
  inset: (x: 1.05em, y: .85em),
  text(font: font-display, size: 1.05em, weight: "bold", fill: palette.ink, body),
)

#title-slide()
#outline-slide(columns: 3)

= Part 0 · 複數旋轉

== 一條主線：有限運動在群上，修正在切空間

#equation[$q in cal(Q) arrow.r.long F(q)=T in "SE"(3), quad dot(q) arrow J(q) dot(q)=xi$]
#v(.55em)
#claim[真正的功課是反覆回答三件事：量住在哪個空間？用哪個 frame 表示？有限運動與局部修正如何往返？]
#v(.55em)
#align(center)[
  #text(size: .9em, fill: palette.ink-soft)[
    $S^1 arrow exp/log arrow "SO"(3) arrow "SE"(3) arrow F,J arrow "IK / control"$
  ]
]

#speaker-note[
  機器人運動學說到底只回答一句話：關節在哪裡，末端就在哪裡。末端動得多快，取決於關節動得多快。`q ∈ Q --F--> T ∈ SE(3)`，`q̇ --J(q)--> ξ`。`Q` 是關節空間，`T` 是末端位姿，`ξ` 是末端瞬時速度。難度全藏在箭頭底下：`Q` 是否普通的 `R^n`？角度轉一圈跟沒轉是否同一個點？`T` 能不能直接加減？`J` 又是在哪個座標系底下寫出來的？

  這些問題有共同答案：機器人的位形空間跟位姿空間都是 Lie group，同時是群、又是光滑流形。群給我們精確的有限運動組合，流形給我們微分、速度、優化。這兩件事同時成立，才讓原本只在 `R^n` 上定義的比例控制器，合法地搬到旋轉矩陣、搬到剛體位姿上使用。

  我們會從高中就見過的複數乘法出發，它比 `SO(3)` 簡單十倍，卻已經展示了 Lie group 的每一個結構：群、流形、切空間、指數映射、週期性、線性化的陷阱。把複數的故事講清楚，`SO(2)`、`SO(3)`、`SE(3)` 只是把同一套劇本搬到更高維、更不可交換的舞台上重演一次。這條主線先說在前面：接下來公式變複雜時，其實只是同一個故事換了維度。
]

== 回憶高中複數

#row(widths: (1.3fr, 1fr), gutter: .8em, align: horizon)[
  #image("assets/complex-multiply.svg", width: 100%)
][
  #col(gap: .4em)[
    $
      z=x+i y=r(cos phi+i sin phi), \
      r=|z|, \
      phi=arg z
    $
    #card(tint: palette.iris, title: [模長相乘])[$|z_1 z_2|=|z_1||z_2|$]
    #card(tint: palette.teal, title: [幅角相加])[$op("arg")(z_1 z_2)=op("arg") z_1+op("arg") z_2$]
  ]
]

#speaker-note[
  各位高中都學過複數乘法吧？

  複數 `z = x+iy` 可以看成平面上的一個點 `(x,y)`,也可以看成一個既有長度又有方向的量:模長 `|z|=√(x²+y²)`,幅角 `arg z` 是它跟正實軸的夾角。高中課本教過一個關鍵事實，乘法在這兩個量上分別做了乾淨的事:

  ```text
  |z₁z₂| = |z₁||z₂|          (模長相乘)
  arg(z₁z₂) = arg z₁ + arg z₂ (幅角相加)
  ```

  代一組具體數字感受一下。取 `z₁=1+i`、`z₂=1+i`,直接展開相乘:

  ```text
  (1+i)(1+i) = 1+i+i+i² = 1+2i−1 = 2i
  ```

  驗證剛才那兩條規則:`|z₁|=|z₂|=√2`,乘積 `|z₁z₂|=|2i|=2=√2·√2`,模長確實相乘，`arg z₁=arg z₂=45°`,乘積 `arg(2i)=90°=45°+45°`,幅角確實相加。這就是為什麼高中老師會說「乘上一個模長 1 的複數,等於把整個平面繞原點轉一個角度」，因為模長相乘的部分被 `1` 吃掉了,只剩幅角相加在起作用,乘法退化成純旋轉。
]

== 高中複數已經藏著一個 Lie group

#equation[$z=x+i y, quad mu: G times G arrow G, quad mu(g, h)=g*h$]
#v(.25em)
#definition(
  [群公理],
  [封閉性 $a*b in G$、結合律、單位元 $e$、反元素 $a^(-1)$。四條缺一不可。],
)
#v(.3em)
#row(widths: (1fr, 1fr), gutter: .8em)[
  #card(
    tint: palette.iris,
    inset: .65em,
    title: [驗證封閉性],
  )[#set text(size: .82em); 取 $u=cos theta+i sin theta$，$S^1={u:|u|=1}$。$|u_1 u_2|=|u_1||u_2|=1$，乘積仍落在 $S^1$。]
][
  #card(
    tint: palette.teal,
    inset: .65em,
    title: [其餘三條],
  )[#set text(size: .82em); 結合律繼承自 $CC$。單位元 $e=1$。反元素 $u^(-1)=bar(u)$，因為 $u bar(u)=|u|^2=1$。]
]
#v(.3em)
#callout(kind: "info", compact: true)[$(S^1,times)$ 是 Abelian 群。同時是平滑曲線，「可微的群」正是 Lie group。]

#speaker-note[
  「`μ` 是 `G` 上的二元運算」這句話本身就在斷言一件需要驗證的事：對任意 `g,h`，乘積確實落回 `G` 裡。取 `z₁=x₁+iy₁`、`z₂=x₂+iy₂`，展開 `z₁z₂=(x₁x₂−y₁y₂)+i(x₁y₂+x₂y₁)`，實部虛部都是實數,乘積確實落回 `C` 裡。

  群只是在二元運算之上再加四條要求：封閉性、結合律、單位元、反元素。`S¹` 是 `C` 的子集,「複數乘法在 `C` 上封閉」不會自動保證「在 `S¹` 上也封閉」，必須重新驗證：`|u₁u₂|=|u₁||u₂|=1·1=1`,兩個模長 1 的數相乘還是模長 1。結合律繼承自 `C` 的環結構;單位元 `1=cos0+isin0`;反元素 `u⁻¹=ū`,因為 `|u|=1` 保證 `u·ū=|u|²=1`。四條全部成立,`S¹` 是群,而且是 Abelian 的，這件事之後會變得重要：非交換群才有的「順序影響結果」，在複數的世界完全不出現，要到 `SO(3)` 才第一次遇到。

  現在給一個還不夠嚴謹、但足夠抓住直覺的說法：`S¹` 同時是一條 smooth 的曲線，可以在上面微分，而群運算跟取逆剛好也都是光滑映射。完整定義要等 Part 1 把「流形」講清楚後才補上，這裡先記住 `S¹` 是這門課最簡單的 Lie group 例子。
]

== 複數乘法就是二維旋轉矩陣

#equation[$(cos theta+i sin theta)(x+i y)=(x cos theta-y sin theta)+i(x sin theta+y cos theta)$]
#v(.4em)
#equation[$mat(x'; y')=underbrace(mat(cos theta, -sin theta; sin theta, cos theta))_(R(theta)) mat(x; y)$]
#v(.45em)
#row(gutter: .8em)[
  #card(tint: palette.teal, title: [保長度])[$|u z|=|z|$]
][
  #card(tint: palette.iris, title: [保方向])[$det R(theta)=cos^2 theta+sin^2 theta=+1$]
][
  #card(tint: palette.amber, title: [組合])[$R(alpha)R(beta)=R(alpha+beta)$，就是和角公式。]
]

#speaker-note[
  把 `u=cosθ+isinθ` 乘上 `z=x+iy`，直接展開：`(cosθ+isinθ)(x+iy)=(xcosθ−ysinθ)+i(xsinθ+ycosθ)`。把實部虛部拆出來寫成向量方程,就是那個熟悉的旋轉矩陣，一字不差。而且矩陣立刻繼承複數乘法的所有性質：保長度是因為 `|uz|=|u||z|=|z|`,保方向是因為 `detR(θ)=cos²θ+sin²θ=+1`(不是 `-1`,所以不含鏡射)，組合律 `R(α)R(β)=R(α+β)` 直接對應複數相乘後角度相加的三角恆等式。你在高中背的和角公式,其實就是 `SO(2)` 的群結構在角度座標下的樣子。
]

== Euler 公式：指數把直線捲到圓上

#equation[$e^(i theta)=sum_(k=0)^infinity (i theta)^k/k!$]
#v(.3em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [偶次方摺成 cos])[$sum_m (-1)^m theta^(2m)/(2m)! = cos theta$]
][
  #card(tint: palette.teal, title: [奇次方摺成 sin])[$i sum_m (-1)^m theta^(2m+1)/(2m+1)! = i sin theta$]
]
#v(.35em)
#claim(tint: palette.rose)[$exp$ 是週期映射：$theta$ 與 $theta+2 pi k$ 是同一旋轉。座標可跳躍，幾何物件沒有跳。]

#speaker-note[
  把 `e^{iθ}` 用冪級數定義攤開，`i` 的偶次方是 `(-1)^k` 摺成 cosine、奇次方摺成 sine 的自然結果，這個「冪級數依奇偶項摺疊成 sin/cos」的技巧,會在 `SO(2)`、`SO(3)` 的矩陣指數裡各看到一次,是貫穿整堂課的計算引擎。

  Euler 公式把兩個看起來毫不相關的世界接了起來：等號左邊 `iθ` 活在一條直線 `iR` 上,加法輕而易舉。等號右邊 `e^{iθ}` 活在圓 `S¹` 上,乘法保持旋轉結構。指數映射就是把「加法容易」的直線,捲成「乘法有結構」的圓,這正是 Lie algebra(直線,好算)跟 Lie group(流形,精確)之間關係的縮影。

  但這個捲曲映射不是雙射：`e^{iθ}` 對 `θ` 是週期 `2π` 的,`θ` 跟 `θ+2πk` 對應同一個旋轉。把無限長的線捲到有限周長的圓上,必然出現重疊。這個「指數映射是滿射但不是單射」的事實,會在後面反覆出現：`SO(3)` 的 axis-angle 在 `θ=π` 出現 branch cut,四元數是 `SO(3)` 的雙覆蓋,Euler angle 在特定姿態發生 gimbal lock，全部是同一件事的不同症狀：群比它的座標化「大」，座標系統在某些地方必然失效。
]

== 旋轉的瞬時速度住在切線上

#equation[$u(t)=e^(i theta(t)), quad dot(u)(t)=i dot(theta)(t) u(t)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #definition([tangent at identity], [$T_1 S^1={i omega: omega in RR}$，一條穿過原點、方向為 $i$ 的直線。])
][
  #definition([angular velocity], [$omega=dot(theta)$。$u(0)=1 arrow.double dot(u)(0)=i omega$，即無窮小生成元。])
]
#v(.4em)
#quote-card(tint: palette.amber)[有限旋轉住在群，瞬時旋轉住在 Lie algebra。即使 $S^1$ 本身不是向量空間，$T_1 S^1$ 是。]

#speaker-note[
  令 `u(t)=e^{iθ(t)}`，直接對時間微分：`u̇(t)=iθ̇(t)e^{iθ(t)}=iθ̇(t)u(t)`。在 identity 附近(`t=0`,`u(0)=1`)看這個式子,`u̇(0)=iθ̇(0)`。這給出關鍵定義：identity 處的切空間 `T₁S¹={iω:ω∈R}`,是一條穿過原點、方向為 `i` 的直線，注意它是貨真價實的向量空間,即使 `S¹` 本身不是。`ω=θ̇` 是角速度,`iω` 就是「identity 附近的無窮小生成元」。
]

== Taylor 展開給出小角度近似

#equation[$e^(i delta theta)=1+i delta theta+cal(O)(delta theta^2)$]
#v(.4em)
#equation[$R(delta theta)=I+delta theta mat(0, -1; 1, 0)+cal(O)(delta theta^2)$]
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[線性化只在一個局部 chart 有效。每次更新後回到群上，再重新線性化。這是 manifold optimization 的基本節奏。]

#speaker-note[
  這句「無窮小」可以直接用 Taylor 展開驗證：`e^{iδθ}=1+iδθ+O(δθ²)`，寫回矩陣形式就是 `R(δθ)=I+δθ[0,-1;1,0]+O(δθ²)`。小角度時,旋轉矩陣近似等於「單位矩陣加上一個活在切空間裡的線性項」。這件事的重要性在於它給出一套「線性化，更新，再線性化」的節奏：任何時候只能在切空間(一個向量空間)裡做梯度下降、做最小平方，但這個線性化只在目前這一點的局部 chart 有效，每走一步就要用指數映射把更新量捲回群上，再在新的一點重新線性化。這正是 manifold optimization 的心跳，Week 4 從這個複數例子開始，到最後的 Gauss-Newton IK 求解器，節奏完全一樣。
]

== 座標可以斷裂，幾何物件不能

#equation[$theta_1=179°, quad theta_2=-179°, quad frac(theta_1+theta_2, 2)=0°$]
#v(.3em)
#equation[$op("arg")(e^(i theta_1)+e^(i theta_2))=180°$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.rose,
    title: [對座標平均：錯],
  )[$0°$ 朝正東，但兩個角度在圓上其實幾乎重合(只差 $2°$)，朝向幾乎正西。]
][
  #card(tint: palette.teal, title: [先映到群再平均：對])[把角度捲回 $S^1$ 上的點再平均，答案是 $180°$，跟幾何直覺一致。]
]
#v(.4em)
#claim(
  tint: palette.rose,
)[角度這個座標系統有一條 branch cut：$179°$ 跟 $-179°$ 數字上差 $358$，代表的旋轉只差 $2°$。凡是直接對座標做 Euclidean 算術，平均、相減、線性插值，都在偷渡「座標系統處處良好」這個假設。]

#speaker-note[
  這個陷阱值得單獨停留一張投影片，因為它會在後面用不同的臉孔反覆出現。取兩個角度 `θ₁=179°`、`θ₂=-179°`。如果天真地把角度當成普通實數做平均，`(θ₁+θ₂)/2=0°`，得到零度，方向朝正東。但這兩個角度在圓上其實幾乎重合，只差了 2 度，朝向幾乎正西。正確的平均要先把角度映到群上再做：`arg(e^{iθ₁}+e^{iθ₂})=180°`。

  問題出在角度這個座標系統本身有一條 branch cut，`179°` 跟 `-179°` 這兩個數字看起來相差 358，但它們代表的旋轉只相差 2°。座標可以在切口處斷裂，但幾何物件(這裡是 `S¹` 上的點)本身是連續的。這個陷阱在 `SO(3)` 的 Euler angle、四元數的正負號、`SE(3)` 的姿態插值裡都會用不同的臉孔再出現一次，記住這一頁，後面每次遇到「奇怪的插值 bug」，先回頭問一句：我是否在對座標做算術，而不是對群元素做算術？
]

= Part 1 · 群、流形與切空間

== 群：把「可逆的組合」抽象出來

#theorem(
  [Group axioms],
  [集合 $G$ 配上一個二元運算，滿足 closure、associativity、identity 與 inverse。群公理本身*不*包含交換律。],
)
#v(.45em)
#row(gutter: .7em)[
  #card(tint: palette.teal, title: [$S^1$])[複數乘法，Abelian，交換律是這個特例額外具備的性質。]
][
  #card(tint: palette.iris, title: [$"SO"(3)$])[旋轉矩陣乘法，non-Abelian。]
][
  #card(tint: palette.amber, title: [$"SE"(3)$])[剛體變換組合，non-Abelian。]
]

#speaker-note[
  複數的故事已經把所有直覺準備好了，現在把它們寫成正式定義，才能推廣到旋轉矩陣跟剛體變換。群公理本身不包含交換律。`S¹` 滿足交換律，是複數乘法這個特例額外具備的性質，不是群公理保證的通性，`SO(3)`、`SE(3)` 一般不滿足交換律，下一頁馬上用具體算式驗證這件事。
]

== Non-commutativity 是三維幾何的核心難題

#row(widths: (1.35fr, 1fr), gutter: .8em, align: horizon)[
  #image("assets/noncommute-rotation.svg", width: 100%)
][
  #col(gap: .35em)[
    $R_y (pi/2)R_x (pi/2) e_z=(0,-1,0)$

    $R_x (pi/2)R_y (pi/2) e_z=(1,0,0)$
  ][
    #v(.9em)
    #callout(kind: "warn", compact: true)[同一起點、同一組旋轉，只換了順序，落點就不同。]
  ]
]
#v(.3em)
#claim(
  tint: palette.rose,
)[交換子 $[A,B]=A B-B A$ 精確量化「順序有多重要」：$[A,B]=0 arrow.double$ 順序不重要。roll-pitch-yaw 必須附上 convention。body/spatial velocity 也各自對應左右乘的不同 convention。]

#speaker-note[
  讓 `R_x(π/2)` 表示繞 x 軸轉 90°、`R_y(π/2)` 表示繞 y 軸轉 90°。取沿 z 軸的單位向量 `e_z=(0,0,1)`，先繞 x 轉再繞 y 轉：`R_x(π/2)e_z=(0,-1,0)`(繞 x 轉 90° 把 z 軸轉到 -y)，`R_y(π/2)(0,-1,0)=(0,-1,0)`(繞 y 轉不影響 y 分量)。反過來，先繞 y 轉再繞 x 轉：`R_y(π/2)e_z=(1,0,0)`(繞 y 轉 90° 把 z 軸轉到 x)，`R_x(π/2)(1,0,0)=(1,0,0)`(繞 x 轉不影響 x 分量)。`(0,−1,0)≠(1,0,0)`，同一個起點、同一組旋轉，只是交換了順序，結果卻是兩個不同的點，這正是三維旋轉群的結構性質造成的。

  這個不交換性直接量化為 commutator `[A,B]=AB−BA`：當它是零矩陣，順序不重要。當它不是，順序就是模型的一部分。先把這個記號放進口袋，它會在 BCH 公式裡以主角之姿回歸：把 `exp(A)exp(B)` 用冪級數乘開到二階，`exp(A)exp(B)=I+(A+B)+(A²/2+AB+B²/2)+…`，而 `exp(A+B)` 展開到二階是 `I+(A+B)+(A²+AB+BA+B²)/2`。兩者二階項相差 `(AB−BA)/2=[A,B]/2`，這就是為什麼「先轉 x 再轉 y」跟「先轉 y 再轉 x」的差別，精確地由 commutator 的二分之一給出。這是本堂課最重要的伏筆之一，到 Part 3 的 BCH 公式時會展開得更完整。
]

== 流形：局部像 $RR^n$，全域可以彎曲

#definition(
  [Topological manifold],
  [每個點 $p in cal(M)$ 都有開鄰域 $U$ 與同胚 $phi: U arrow V subset RR^n$。同胚 = 雙射 + $phi$ 連續 + $phi^(-1)$ 連續。$n$ 稱為 dimension。],
)
#v(.35em)
#definition(
  [Smooth atlas],
  [一組 chart ${(U_alpha,phi_alpha)}$ 覆蓋 $cal(M)$，且 transition map $phi_beta compose phi_alpha^(-1)$ 與其反函數皆 $C^infinity$，才可一致地做微積分。],
)
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[單一 chart 只覆蓋 $cal(M)$ 的一部分。「chart 之間如何拼接」的條件才是能否微分的關鍵。]

#speaker-note[
  一個 topological manifold 是一個拓撲空間 `M`，滿足：對每個點 `p∈M`，存在開鄰域 `U∋p` 跟同胚 `φ:U→V`，把 `U` 映到 `R^n` 裡某個開集 `V`。同胚要求 `φ` 雙射、連續，反函數 `φ⁻¹` 也連續，三個條件合起來保證 `U` 跟 `V` 在拓撲意義下等價。`n` 稱為流形的維度。

  單一個 chart 只覆蓋 `M` 的一部分，要做微積分需要一組 atlas `{(U_α,φ_α)}` 滿足 `⋃U_α=M`。光有 atlas 還不能微分：如果同一點 `p` 落在 `U_α` 跟 `U_β` 裡，`φ_α(p)` 跟 `φ_β(p)` 是兩組不同座標數字，要讓「對座標微分」有意義，這兩組座標的轉換必須光滑。transition map `φ_β∘φ_α⁻¹` 要求 `C^∞`，反函數也 `C^∞`，合起來叫 diffeomorphism。滿足這個條件的 atlas 叫 smooth atlas，這正是接下來所有微分、切空間、指數映射建立的地基。
]

== 用 $S^1$ 具體構造一組 smooth atlas

#equation[$U_1=S^1 without {(-1,0)}, quad phi_1(cos theta,sin theta)=theta in (-pi,pi)$]
#v(.25em)
#equation[$U_2=S^1 without {(1,0)}, quad phi_2(cos theta,sin theta)=theta in (0,2pi)$]
#v(.3em)
#equation[$phi_2 compose phi_1^(-1)(theta)=theta+2pi, quad theta in (-pi,0)$]
#v(.4em)
#claim[單一個 $theta in [0,2pi)$ 想涵蓋整個圓做不到：$[0,2pi)$ 不是 $RR$ 的開集，$theta=0$ 找不到映到開區間的鄰域。一定要兩張 chart 才補得起來，球面經緯度在南北極退化，是同一個障礙以更高維重演。]

#speaker-note[
  現在用 `S¹` 具體構造一組 smooth atlas，把抽象定義釘死在算得出來的例子上。取兩個 chart：`U₁` 挖掉 `θ=π` 那一點，`U₂` 挖掉 `θ=0` 那一點，兩者聯集覆蓋整個 `S¹`。重疊區域分兩段：上半圓在兩個 chart 底下座標值相同。下半圓在 `φ₁` 底下讀作 `θ∈(-π,0)`，在 `φ₂` 底下讀作 `θ∈(π,2π)`。在下半圓算 transition map：`φ₂∘φ₁⁻¹(θ)=θ+2π`，這是仿射映射，顯然 `C^∞`，反函數也是。兩段重疊區都驗證通過，這確實是 `S¹` 的一組合法 smooth atlas。

  這個構造同時說明了為什麼一定要兩張 chart：如果只用單一個 `θ∈[0,2π)` 想涵蓋整個圓，`[0,2π)` 不是 `R` 裡的開集，`θ=0` 這一點找不到映到開區間的鄰域，不滿足同胚定義裡「開集映到開集」的要求。球面的經緯度座標在南北極退化，是同一個障礙以更高維度重演：coordinate singularity 是幾乎每一個非平凡流形必然要付的代價，不是設計失誤。
]

== Chart 提供座標，幾何物件保持獨立

#equation[$phi: U subset cal(M) arrow RR^n, quad p arrow x=phi(p)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [intrinsic])[點 $p$、切向量 $v in T_p cal(M)$、曲線 $gamma(t)$。]
][
  #card(tint: palette.rose, title: [coordinate-dependent])[$x$、向量分量 $v^i$、Euler angles。換 chart 數字會變。]
]
#v(.45em)
#quote-card(
  tint: palette.amber,
)[好的機器人公式必須區分座標分量與幾何不變量，Part 0 圓上平均的陷阱，正是把 coordinate-dependent 的量誤當 intrinsic 量處理。]

#speaker-note[
  chart 提供的是座標，幾何物件本身在換 chart 之後保持不變，這個區分是接下來所有推導能否成立的前提。映射 `φ:U⊂M→R^n`,`p↦x=φ(p)` 只是「怎麼用一串數字描述一個點」的一種選擇。真正 intrinsic、不隨 chart 改變的是點 `p` 本身、切向量 `v∈T_pM`、曲線 `γ(t)`。會隨座標改變的是座標值 `x`、向量的分量 `v^i`、Euler angle 這種具體的角度數字。機器人公式裡最常見的錯誤,是把 coordinate-dependent 的量直接拿去做只對 intrinsic 量合法的運算，Part 0 圓上平均的例子精確示範了這個錯誤:對座標(角度數值)做的線性平均,不等於對幾何物件(圓上的點)做的平均。
]

== 切向量：用「穿過點的曲線」定義

#equation[$T_p cal(M) := {gamma "穿過" p "的光滑曲線"} \/ tilde, quad v=[gamma]=:dot(gamma)(0)$]
#v(.35em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #definition(
    [等價關係],
    [$gamma_1 tilde gamma_2$ 若在某 chart 下 $dot.double(d)/(d t)|_0 phi(gamma_1(t))=dot.double(d)/(d t)|_0 phi(gamma_2(t))$。],
  )
][
  #definition(
    [向量空間結構],
    [選定 $phi$ 後 $[gamma] mapsto d/(d t)|_0 phi(gamma(t)) in RR^n$ 是雙射，把 $RR^n$ 的加法搬過來。],
  )
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[$p+v$ 沒有定義：$cal(M)$ 不是向量空間。從切空間回到流形需要 exponential map 或其他 retraction。]

#speaker-note[
  切向量到底怎麼定義，才能不依賴任何 chart？答案是用曲線，但要先處理一個微妙之處:`γ(t)` 是流形上的曲線，`γ̇(0)` 要對什麼東西微分還沒定義，`M` 不是向量空間，無法直接對 `γ(t)` 做差分取極限。標準做法是先選一個 chart `φ`，把 `γ(t)` 拉到 `R^n` 上變成 `φ(γ(t))`，對這條 `R^n` 裡的曲線取普通的微分。接著定義等價關係:兩條穿過 `p` 的曲線算「同一個切向量」，若在某個 chart 底下座標導數相等。「在某個 chart 底下相等，就在任何 chart 底下相等」直接來自 transition map `C^∞` 這條相容條件:換一個 chart `ψ`，鏈式法則給出座標導數要乘上同一個線性映射 `d(ψ∘φ⁻¹)`，兩條曲線在 `φ` 底下相等，乘上同一個線性映射後在 `ψ` 底下當然還是相等。

  `T_pM` 是這些等價類的集合，它是向量空間的原因可以直接驗證:選定一個 chart `φ` 之後，`[γ]↦d/dt|_0 φ(γ(t))∈R^n` 是雙射，直接用這個雙射把 `R^n` 的加法、純量乘法搬過來，換一個 chart 得到的結構,透過鏈式法則論證,是同一個結構的另一種座標表示。`T_pM` 的維度永遠等於 `M` 的維度,`SO(3)` 是三維流形,它每一點的切空間也是三維向量空間,即使 `SO(3)` 本身是九個矩陣元素構成的彎曲子集。有一件事必須說清楚:`p+v` 一般沒有定義,因為 `M` 不是向量空間,加法在上面沒有意義。要從切空間走回流形,需要 exponential map 這一類的 retraction,這正是為什麼 `SO(2)`、`SO(3)`、`SE(3)` 都以指數映射為核心操作。
]

== Differential：Jacobian 的座標獨立版本

#equation[$F: cal(M) arrow cal(N), quad "d"F_p: T_p cal(M) arrow T_(F(p)) cal(N)$]
#v(.4em)
#equation[$"d"F_p(v)=frac("d", "d"t)|_(t=0) F(gamma(t)), quad dot(gamma)(0)=v$]
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[選定 charts 後，$"d"F_p$ 的矩陣表示就是熟悉的 Jacobian。矩陣只是這個線性映射在某組基底下的表示，這個觀點會在 Part 6 講機器人 Jacobian 時派上用場。]

#speaker-note[
  有了切空間，微分就有座標無關的定義。給定 `F:M→N`，它的 differential `dF_p:T_pM→T_{F(p)}N` 定義為對任一條過 `p` 且 `γ̇(0)=v` 的曲線，`dF_p(v)=d/dt|_0 F(γ(t))`。選定 charts 之後，`dF_p` 的矩陣表示就是我們熟悉的 Jacobian。但這句話反過來讀更重要:Jacobian 是切空間之間的線性映射,矩陣只是這個映射在某組基底下的表示。`J(q)` 把關節速度這個切向量,映到末端速度這個切向量,座標系選擇不同,矩陣長得不同,但底下那個線性映射是同一個東西。
]

== Lie group：群運算與光滑結構相容

#definition(
  [Lie group],
  [$G$ 同時是群與 smooth manifold。把流形結構延伸到 $G times G$ 後，乘法 $mu(g, h)=g*h$ 與 inverse $iota(g)=g^(-1)$ 都必須是 $G times G arrow G$、$G arrow G$ 的光滑映射。],
)
#v(.4em)
#row(gutter: .75em)[
  #card(tint: palette.teal, title: [global])[群提供精確的有限組合與 inverse。]
][
  #card(tint: palette.iris, title: [local])[流形提供 tangent、derivative、optimization。]
][
  #card(tint: palette.amber, title: [bridge])[$exp$ / $log$ 在兩者間搬運。]
]

#speaker-note[
  現在把群跟流形疊在一起，而且要講清楚「疊在一起」精確是什麼意思:兩個結構必須相容,不能各自獨立存在。正式定義:一個 Lie group 是一個集合 `G`,同時具備群結構(封閉性、結合律、單位元、反元素)跟光滑流形結構。光是疊在同一個集合上還不夠,兩者必須相容,而「相容」有精確的檢驗標準:把 `G` 的流形結構延伸到乘積 `G×G` 上(自然繼承一個乘積流形結構,維度是 `dim G` 的兩倍)，然後要求乘法 `μ:G×G→G` 與取逆 `ι:G→G` 都是光滑(`C^∞`)映射。

  「`μ` 光滑」的意思要說清楚:`μ` 的定義域是乘積流形 `G×G`,把 `(g,h)` 當成單一一點,要求 `μ` 對這個乘積流形的座標整體可微。少了這個相容條件,`G` 只是「剛好」同時是群又是流形的兩張皮,`exp`、`log`、Jacobian 這些工具全部建立在 `μ`、`ι` 光滑這個事實上,沒有它們,切空間之間根本談不上有良好定義的線性映射。群提供 global 的精確組合跟逆元,流形提供 local 的切向量、微分、優化,指數映射 `exp` 跟對數映射 `log` 在兩者之間搬運，這個三角關係,就是整堂課接下來要反覆套用的模板。
]

== 為什麼只研究 identity 的切空間就夠？

#equation[$L_g(h)=g h$]
#v(.3em)
#equation[$("d"L_g)_e: T_e G arrow T_g G "是線性同構"$]
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[$L_g$ 有光滑逆 $L_(g^(-1))$，兩者的 differential 互為逆映射，所以 $("d"L_g)_e$ 是雙射。左乘可把 identity 的切向量搬到任何 $g$，因此所有 tangent spaces 都能由單一向量空間 $frak(g)=T_e G$ 生成，這就是 Lie algebra。]

#speaker-note[
  最後一個問題:`G` 上每一點都有自己的切空間 `T_gG`,難道要對每一點分別研究嗎?不需要。定義 left translation `L_g(h)=gh`,因為群乘法光滑,`L_g` 是一個微分同胚,它的 differential `(dL_g)_e:T_eG→T_gG` 是一個線性同構，這件事可以直接驗證:`L_g` 有光滑逆 `L_{g⁻¹}`,兩者的 differential 互為逆映射,所以 `(dL_g)_e` 是雙射線性映射,即同構。這代表 identity 處的切空間 `T_eG`,可以透過左乘,原封不動地「搬」到任何一點 `g` 的切空間。因此只需要研究單一一個向量空間 `𝔤=T_eG`,就掌握了整個群在每一點的局部結構,這個 `𝔤` 就叫 Lie algebra,它是接下來 `𝔰𝔬(2)`、`𝔰𝔬(3)`、`𝔰𝔢(3)` 的定義依據。
]

= Part 2 · $"SO"(2)$：第一個完整 Lie group

== $"SO"(2)$ 的定義來自「保內積」

#equation[$"SO"(2)={R in RR^(2 times 2): R^T R=I, det R=1}$]
#v(.35em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.teal, title: [$R^T R=I$])[$(R x)^T(R y)=x^T R^T R y=x^T y$，長度與角度保持一致。]
][
  #card(tint: palette.iris, title: [$det R=1$])[排除 reflection，保留 orientation-preserving isometry。]
]
#v(.3em)
#equation[$underbrace(4, "ambient" RR^(2 times 2)) - underbrace(3, R^T R = I "的獨立約束") = 1 "dof"$]
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[$S^1 equiv "SO"(2)$：$a+i b arrow.l.r mat(a, -b; b, a)$，約束 $R^T R=I$ 恰好對應 $|a+i b|=1$，這正是同一個群的兩種表示。]

#speaker-note[
  `SO(2)` 的定義來自「保內積」這個幾何要求。第一條約束保內積：因為 `R^TR=I`，任意兩向量 `(Rx)^T(Ry)=x^TR^TRy=x^Ty`，內積不變，連帶長度跟夾角都不變。第二條排除鏡射，只留下 orientation-preserving 的等距映射。把 `R` 對應到複數 `a+ib`，約束 `R^TR=I` 恰好對應 `|a+ib|=1`，兩邊描述的是同一個 `S¹`，這正印證了 Part 0 的直覺，兩邊是同一個群的兩種表示。

  順手把 `SO(2)` 的維度算出來，這件事之後對 `SO(3)` 會用同一套手法重做一次，先在這裡把方法立起來。`R` 有 4 個獨立元素，活在 `R^{2×2}≅R^4` 這個 ambient space 裡。`R^TR` 是一個 `2×2` 對稱矩陣，只有 3 個獨立元素(2 個對角、1 個非對角)，而 `R^TR=I` 要求這 3 個元素分別等於 `I` 對應的位置，是 3 條獨立約束。`4-3=1`，`SO(2)` 是一維流形，恰好對應「轉動角度」這一個自由度。
]

== 對 constraint 微分，Lie algebra 與 hat 字典一起出現

#equation[$R(t)^T R(t)=I, quad R(0)=I$]
#v(.3em)
#equation[$frac("d", "d"t)|_0 (R^T R)=dot(R)(0)^T+dot(R)(0)=0 quad arrow.double quad Omega:=dot(R)(0), quad Omega^T=-Omega$]
#v(.35em)
#theorem(
  [$frak("so")(2)$],
  [$Omega^T=-Omega arrow.r.double Omega=hat(omega)=omega mat(0, -1; 1, 0)$，一維向量空間，維度與 $"SO"(2)$ 的 dof 吻合。反向以 $op("vee")(hat(omega))=omega$ 讀回座標。],
)
#v(.3em)
#callout(
  kind: "info",
  compact: true,
)[有限約束「保正交」微分之後，自動退化成線性約束「反對稱」，這個手法在 Part 3 對 $"SO"(3)$ 會重做一次。]

#speaker-note[
  現在做一件 Part 0 沒做的事：直接對約束方程微分，看 Lie algebra 是否「自動出現」。設 `R(t)` 是一條滿足 `R(0)=I` 的路徑，約束恆等式 `R(t)^TR(t)=I` 兩邊對 `t` 微分，用乘積法則：`d/dt(R^TR)=Ṙ^TR+R^TṘ=0`，在 `t=0` 代入 `R(0)=I`：`Ṙ(0)^T+Ṙ(0)=0`。令 `Ω=Ṙ(0)`，這說明 `Ω^T=-Ω`，`Ω` 必須是反對稱矩陣。這個結果直接來自「保正交」這個有限約束，微分之後自動退化成「反對稱」這個線性約束。二維反對稱矩陣只有一個自由參數，`𝔰𝔬(2)={ω[0,-1;1,0]:ω∈R}` 正好是一維向量空間，跟 `SO(2)` 的維度(一維)吻合，這印證了 Part 1 的一般結論 `dim T_eG=dim G`。

  `hat`/`vee` 這對算子只是在座標向量 `ω∈R` 跟矩陣生成元 `ω̂∈𝔰𝔬(2)` 之間搭一座橋。座標向量方便存進 solver、方便做數值優化。矩陣生成元方便做指數、方便算 commutator，這組字典會在 `SO(3)`、`SE(3)` 各自升級一次維度，概念不變。
]

== Matrix exponential 保證回到群上

#equation[$J=mat(0, -1; 1, 0), quad J^2=-I$]
#v(.25em)
#equation[$exp(theta J)=underbrace(sum_m (-1)^m theta^(2m)/(2m)!, I "的係數")I+underbrace(sum_m (-1)^m theta^(2m+1)/(2m+1)!, J "的係數")J$]
#v(.25em)
#equation[$exp(theta J)=I cos theta+J sin theta=R(theta)$]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[$J^2=-I$ 把偶次冪跟奇次冪各自摺疊成 $cos$、$sin$，跟 Part 0 Euler 公式同一招。$R(theta)^T R(theta)=I$ 由三角恆等式直接驗證，正交約束自動成立，不需事後 normalize。]

#speaker-note[
  矩陣指數把生成元捲回群上，而且保證回到群上，這件事值得展開驗證。記 `J=[0,-1;1,0]`，先算 `J²=[0,-1;1,0][0,-1;1,0]=[-1,0;0,-1]=-I`。有了這個關係，冪級數 `exp(θJ)=Σ(θJ)^k/k!` 按 `k` 的奇偶性分兩組：偶數次 `J^{2m}=(J²)^m=(-1)^m I`，奇數次 `J^{2m+1}=(-1)^m J`。把偶數項跟奇數項分別收集起來，得到 `exp(θJ)=(cosθ)I+(sinθ)J=R(θ)`，這跟 Part 0 推 Euler 公式的手法一模一樣，「冪級數依奇偶項摺疊成 cos/sin」的引擎再度發動。而且因為 `exp(θJ)` 精確等於這個矩陣形式，天生滿足 `R^TR=I`(用三角恆等式驗證即可)，所以正交約束是自動成立的，不需要事後 normalize。
]

== Logarithm 回答「相差多少旋轉」

#equation[$R(theta)=mat(c, -s; s, c), quad theta="atan2"(s,c) in (-pi,pi]$]
#v(.4em)
#equation[$log R=theta J$]
#v(.45em)
#callout(
  kind: "warn",
  compact: true,
)[$theta=pi$ 是 branch cut：超出 $(-pi,pi]$ 就有不同 $theta$ 對應同一矩陣。$log$ 只能是 $exp$ 的局部反函數，這正是 Part 0「指數把無限長直線捲上有限周長圓」的必然代價。]

#speaker-note[
  反過來，`log` 回答「相差多少旋轉」。給定 `R(θ)=[c,-s;s,c]`，可以用 `θ=atan2(s,c)` 讀回角度，但這個讀回過程只在 `θ∈(-π,π]` 之間是單射，超出這個範圍，不同的 `θ` 對應同一個矩陣。`θ=π` 是這個 branch cut 的邊界，`log` 只能是 `exp` 的局部反函數，這正是 Part 0「指數映射把無限長直線捲上有限周長圓」的必然代價。
]

== $op("boxplus")$ / $op("boxminus")$：在流形上寫 update 與 error

#equation[$R op("boxplus") delta theta := R exp(hat(delta theta))$]
#v(.25em)
#equation[$R_2 op("boxminus") R_1 := op("vee")(log(R_1^T R_2))$]
#v(.45em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.teal,
    title: [update],
  )[右邊乘上 $exp(delta hat(theta))$ 保證仍在 $"SO"(2)$ 裡，不需每步做 orthogonalization 修正。]
][
  #card(tint: palette.iris, title: [error])[兩個群元素的「差」被 $log$ 映回切空間，才能乘 gain、塞進最小平方殘差。]
]

#speaker-note[
  有了 `exp`/`log`，可以定義兩個在流形上做「加法」跟「減法」的替代品：`R⊞δθ:=R exp(δθ̂)` 是 update，因為右邊乘上去的 `exp(δθ̂)` 保證仍在 `SO(2)` 裡，更新後的結果永遠合法。`R₂⊟R₁:=vee(log(R₁^TR₂))` 是 error，兩個群元素的「差」被映回切空間 `R`，這樣才能乘上一個 gain、才能塞進最小平方的殘差裡，你不能直接對兩個旋轉矩陣做減法，減法在 `SO(2)` 上沒有定義，必須先用 `log` 把差異表示成切空間裡的一個向量。
]

== 一個最小 geometric controller

#equation[$e=op("vee")(log(R^T R_d)), quad omega=k e$]
#v(.3em)
#equation[$R_(k+1)=R_k exp(hat(Delta t omega))$]
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[第一行是 error：讀進切空間、乘增益。第二行是 update：捲回群上。這兩行已包含 week4 basic lab 的全部結構，換成 $"SO"(3)$ 或 $"SE"(3)$，把 $k$ 換成矩陣增益，骨架完全不變。]

#speaker-note[
  把這兩件事拼起來，就能寫出全 Week 4 裡最短、卻涵蓋最多結構的一個控制器。第一行是 error：把目前姿態跟目標姿態的差異，透過 `log` 讀進切空間，乘上比例增益 `k`，得到一個角速度指令。第二行是 update：用 `exp` 把這個角速度指令捲回群上，合法地更新姿態。這正是 Part 0「線性化，更新，再線性化」節奏的具體實現，而且已經可以看出，只要把 `SO(2)` 換成 `SO(3)` 或 `SE(3)`，把 `k` 換成矩陣增益，這兩行公式的骨架完全不變，這就是 Week 4 basic lab 那四行程式碼的直系祖先。
]

= Part 3 · $"SO"(3)$：三維旋轉的幾何

== $"SO"(3)$ 是三維、非交換、緊緻的流形

#equation[$"SO"(3)={R in RR^(3 times 3): R^T R=I, det R=1}$]
#v(.3em)
#equation[$underbrace(9, "ambient" RR^(3 times 3)) - underbrace(6, R^T R=I "的獨立約束") = 3 "dof"$]
#v(.35em)
#row(gutter: .7em)[
  #card(tint: palette.teal, title: [ambient])[$R^T R$ 是 $3 times 3$ 對稱矩陣，只有 6 個獨立元素。]
][
  #card(tint: palette.iris, title: [constraints])[$R^T R=I$ 要求這 6 個元素各自等於 $I$，是 6 條獨立約束。]
][
  #card(tint: palette.amber, title: [dimension])[恰好對應「繞任意軸轉任意角」的三個自由度。]
]

#speaker-note[
  `SO(3)` 的定義跟 `SO(2)` 很像，只是矩陣換成三維。`R` 有 9 個獨立元素，活在 `R^9` 這個 ambient space 裡，但約束 `R^TR=I` 砍掉了自由度。`R^TR` 是一個對稱矩陣，對稱 `3×3` 矩陣只有 6 個獨立元素(對角 3 個加上上三角 3 個)，而 `R^TR=I` 要求這 6 個元素分別等於 `I` 對應的位置，所以是 6 條獨立約束。`9-6=3`，`SO(3)` 是三維流形，恰好對應「繞任意軸轉任意角度」的三個自由度，跟 Part 2 對 `SO(2)` 做的 `4-3=1` 是同一套方法。
]

== $frak("so")(3)$：反對稱矩陣就是角速度

#equation[$frak("so")(3)={Omega in RR^(3 times 3): Omega^T=-Omega}$]
#v(.25em)
#equation[$hat(omega)=mat(0, -omega_3, omega_2; omega_3, 0, -omega_1; -omega_2, omega_1, 0)$]
#v(.25em)
#equation[$hat(omega)v=(-omega_3 v_2+omega_2 v_3,thin omega_3 v_1-omega_1 v_3,thin -omega_2 v_1+omega_1 v_2)=omega times v$]
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[跟 $"SO"(2)$ 一樣對 $R(t)^T R(t)=I$ 微分即得反對稱約束，三維反對稱矩陣有 3 個自由參數。hat operator 把叉積這個雙線性運算，寫成一個線性映射。]

#speaker-note[
  跟 `SO(2)` 完全一樣的手法，對 `R(t)^TR(t)=I` 微分，在 identity 得到 `𝔰𝔬(3)` 是反對稱矩陣構成的空間。三維反對稱矩陣有 3 個自由參數(上三角三個非對角元素，對角必為零)，把它們寫成向量 `ω=(ω₁,ω₂,ω₃)`。直接展開 `ω̂v` 驗證它就是叉積，逐項比對可以確認 `ω̂v=ω×v` 對任意 `v` 成立，是一般性的代數事實。這一步轉換讓後面所有牽涉角速度的計算都能用矩陣代數處理，而不必每次都手動處理叉積的分量公式。
]

== Body 與 spatial angular velocity

#equation[$hat(omega_b)=R^T dot(R), quad hat(omega_s)=dot(R)R^T$]
#v(.3em)
#equation[$hat(omega_s)=dot(R)R^T=R(R^T dot(R))R^T=R hat(omega_b) R^T=(R omega_b)^and$]
#v(.3em)
#equation[$omega_s=R omega_b$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [body])[在旋轉物體自己的 axes 表示，right trivialization。]
][
  #card(tint: palette.teal, title: [spatial])[在固定世界 axes 表示，left trivialization。]
]

#speaker-note[
  角速度在三維世界裡出現一個新的分裂：同一個旋轉運動,可以用物體自己的座標系描述,也可以用固定的世界座標系描述,兩者不是同一個東西。定義 body angular velocity `ω̂_b=R^TṘ`,也可以定義 spatial angular velocity `ω̂_s=ṘR^T`。兩者的關係可以直接代數導出：`ω̂_s=ṘR^T=R(R^TṘ)R^T=Rω̂_bR^T`。這裡用到一個值得單獨驗證的恆等式，對任意 `R∈SO(3)`，`Rω̂R^T=(Rω)^`，證明只需要驗證 `(Rω̂R^T)v=Rω̂(R^Tv)=R(ω×R^Tv)`，而叉積在正交變換下滿足 `R(ω×u)=(Rω)×(Ru)`，取 `u=R^Tv` 就得到 `R(ω×R^Tv)=(Rω)×v=(Rω)^v`。有了這個恆等式，直接得到 `ω_s=Rω_b`。body 版本是在旋轉物體自己的軸上表示，術語叫 right trivialization。spatial 版本是在固定的世界軸上表示，叫 left trivialization。這個區分值得認真對待，Part 4 講 `SE(3)` 的 pose error 時，選錯 body 還是 spatial 會直接讓 controller 的更新方向錯誤。
]

== Rodrigues formula：$exp: frak("so")(3) arrow "SO"(3)$

#equation[$phi=theta a, quad theta=norm(phi), quad norm(a)=1, quad hat(a)^2=a a^T-I, quad hat(a)^3=-hat(a)$]
#v(.3em)
#equation[$exp(theta hat(a))=I+underbrace(sum_m (-1)^m theta^(2m+1)/(2m+1)!, sin theta)hat(a)+underbrace(sum_m (-1)^m theta^(2m+2)/(2m+2)!, 1-cos theta)hat(a)^2$]
#v(.25em)
#equation[$exp(hat(phi))=I+frac(sin theta, theta)hat(phi)+frac(1-cos theta, theta^2)hat(phi)^2$]
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[$hat(a)^2 v=a(a dot v)-v$（向量三重積），所以 $hat(a)^3=hat(a)(a a^T)-hat(a)=-hat(a)$（因為 $hat(a)a=a times a=0$）。高次方週期性摺回 $I,hat(a),hat(a)^2$，級數只剩三項。]

#speaker-note[
  接下來是這門課裡計算量最大、卻也最值得親手推一次的公式：Rodrigues formula，也就是 `exp:𝔰𝔬(3)→SO(3)` 的顯式解。設轉軸為單位向量 `a`、轉角為 `θ`，`φ=θa`。要展開 `exp(φ̂)` 的冪級數，關鍵引理是 `â` 满足一個三次方程：`â³=-â`。驗證方式是直接代數計算 `â²`：`â²v=a×(a×v)=a(a·v)-v(a·a)=a(a·v)-v`(向量三重積公式,再用 `|a|=1`)，所以 `â²=aa^T-I`。接著 `â³=â(aa^T-I)=â(aa^T)-â`。而 `âa=a×a=0`，所以 `â(aa^T)=(âa)a^T=0`，得到 `â³=-â`。這個三次方程是整個推導的樞紐：意味著 `â` 的高次方會週期性地摺回 `I、â、â²` 這三項，不會產生新的獨立矩陣。

  把 `θâ` 的冪級數按這個週期分組(跟 Part 0、Part 2「奇偶項摺成 sin/cos」是同一招,只是這次週期是 4 而不是 2)：得到 `exp(θâ)=I+sinθ·â+(1-cosθ)â²`。再用 `â²=aa^T-I`，並把 `φ=θa` 代回，就得到教科書上熟悉的形式 `exp(φ̂)=I+(sinθ/θ)φ̂+((1-cosθ)/θ²)φ̂²`，這正是矩陣指數只剩三項 `I,φ̂,φ̂²` 的原因，是 `â³=-â` 這個代數事實逼出來的結構化簡。
]

== 小角度計算採用 Taylor series

#equation[$frac(sin theta, theta)=1-theta^2/6+cal(O)(theta^4)$]
#v(.25em)
#equation[$frac(1-cos theta, theta^2)=1/2-theta^2/24+cal(O)(theta^4)$]
#v(.45em)
#callout(
  kind: "warn",
  compact: true,
)[兩個係數在 $theta arrow 0$ 都是解析函數，數學上沒問題。但浮點數 $sin theta$ 與 $theta$ 幾乎相等，直接相除會發生 catastrophic cancellation。成熟 library（Sophus、Eigen）在 $theta$ 小於閾值時切換到 Taylor series。]

#speaker-note[
  這兩個係數在 `θ→0` 時看起來要除以零，但它們其實是解析函數，可以用 Taylor 展開驗證數值穩定性。問題出在浮點數運算，不是數學本身：當 `θ` 很小，`sinθ` 跟 `θ` 兩個數值幾乎相等，相除時有效位數大量抵銷，這叫 catastrophic cancellation。成熟的 library 在 `θ` 小於某個閾值時會切換到這兩條 Taylor 展開式計算，而不是直接算 `sin(θ)/θ` 這個商。
]

== Log map：trace 給角度，skew part 給旋轉軸

#equation[$"tr"(exp(hat(phi)))=3+(1-cos theta)"tr"(hat(a)^2)=1+2cos theta$]
#v(.2em)
#equation[$arrow.double theta=op("acos")(("tr"R-1)/2)$]
#v(.25em)
#equation[$R^T=I-sin theta hat(a)+(1-cos theta)hat(a)^2 arrow.double R-R^T=2sin theta hat(a)$]
#v(.2em)
#equation[$arrow.double phi=frac(theta, 2sin theta)op("vee")(R-R^T)$]
#v(.4em)
#claim[反對稱矩陣的 trace 恆為零、$"tr"(hat(a)^2)="tr"(a a^T-I)=1-3=-2$，這兩個代數事實直接推出角度公式。skew part 的推導對稱地用 $hat(a)^T=-hat(a)$、$hat(a)^2$ 對稱抵消 $I$ 項。奇異點正好出現在這兩份資訊失去辨識力時。]

#speaker-note[
  log map 是反方向：給定 `R`，取回 `(θ,a)`。先取 `exp(φ̂)` 公式的 trace：`tr(I)+sinθ·tr(â)+(1-cosθ)tr(â²)`。反對稱矩陣的 trace 恆為零(對角線元素全為零)，`tr(â²)=tr(aa^T-I)=|a|²-3=1-3=-2`。所以 `tr(R)=3+(1-cosθ)(-2)=1+2cosθ`，解出 `θ=acos((trR-1)/2)`。

  再取 `R` 的反對稱部分。從 `exp(φ̂)=I+sinθ·â+(1-cosθ)â²` 直接算它的轉置：`I` 對稱不變。`â` 反對稱，`â^T=-â`。`â²=aa^T-I` 對稱不變。所以 `R^T=I-sinθ·â+(1-cosθ)â²`。兩式相減，`I` 跟 `â²` 的項互相抵消，只剩 `R-R^T=2sinθ·â`，不是憑空冒出的巧合。所以 `vee(logR)=θ/(2sinθ)·(R₃₂-R₂₃,R₁₃-R₃₁,R₂₁-R₁₂)`，一般位置可由 symmetric trace 與 skew part 分別取回 angle 與 axis，下一頁的奇異點也正好出現在這兩份資訊失去辨識力時。
]

== $theta approx pi$：核心問題是 axis 符號不可辨識

#equation[$theta arrow pi arrow.r.double sin theta arrow 0, quad R-R^T arrow 0, quad R=2a a^T-I quad (theta=pi)$]
#v(.3em)
#row(widths: (1fr, 1fr), gutter: .8em)[
  #card(
    tint: palette.rose,
    inset: .65em,
    title: [為何原式失效],
  )[#set text(size: .8em); $(R-R^T)/(2sin theta)$ 變成 $0/0$。$a$ 與 $-a$ 代表同一個 $pi$ rotation，軸的符號不唯一。]
][
  #card(
    tint: palette.teal,
    inset: .65em,
    title: [穩定取法],
  )[#set text(size: .8em); 利用 $R a=a$（特徵值 $1$ 的特徵向量），由 $a_i^2=(R_(i i)+1)\/2$ 先選最大對角分量，再用 off-diagonal 決定其餘符號。]
]
#v(.3em)
#callout(
  kind: "tip",
  compact: true,
)[工程上以 small-angle branch、generic branch、near-$pi$ branch 三段處理。不要讓單一 closed form 承擔所有 condition number。]

#speaker-note[
  但這條公式在 `θ≈π` 附近會出事：`sinθ→0`，分母趨近零，而且從幾何上看，轉 `π` 角度時 `R` 的反對稱部分本身也趨近零矩陣(因為 `sinθ·â→0`)，軸的方向資訊被「壓扁」了，一個接近 `π` 弧度的旋轉，正轉跟反轉在矩陣上幾乎分不出來，軸的符號因此不唯一。實作上必須換一條路：利用 `R` 在特徵值 `1` 的特徵向量就是轉軸(因為 `Ra=a`)，可以從 `R` 的對角元素跟 `(1+2cosθ)` 的關係穩定地抽出 `|a_i|` 的大小，再由非對角元素決定符號。這是 log map 在 `θ=π` 附近的標準工程處理，值得記住這個機制而不只是記住「有 bug 要小心」。
]

== Quaternion：$S^3$ 對 $"SO"(3)$ 的雙覆蓋

#equation[$q=(w,v), quad norm(q)=1, quad R(q)=R(-q)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.teal, title: [優點])[組合與 interpolation 高效，避開 Euler gimbal lock。]
][
  #card(tint: palette.rose, title: [代價])[四個數描述三維流形，伴隨 unit constraint 與 antipodal ambiguity。]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[連續軌跡中若 $q_k dot q_(k-1)<0$，常先翻號以維持同一 hemisphere，才走短弧而不是繞遠路。]

#speaker-note[
  四元數提供了另一條路：單位四元數 `q=(w,v)`、`|q|=1`，構成 `S³`(四維空間裡的三維球面)，透過一個二次映射 `R(q)` 對應到 `SO(3)`。這個映射滿足 `R(q)=R(-q)`，`q` 跟 `-q` 對應同一個旋轉，`S³` 是 `SO(3)` 的雙覆蓋(double cover)。這件事可以類比 Part 0 的 `e^{iθ}` 週期性：那裡是「一條直線捲成一個圓，無限對一」，這裡是「一個三維球面捲成 `SO(3)`，二對一」，同一種「參數化空間比被參數化的空間更大」的現象，只是覆蓋的倍數跟拓撲不同。實務後果是：在連續軌跡中插值四元數時，如果相鄰兩個時刻的 `q_k·q_{k-1}<0`，代表這兩個四元數雖然代表相近的旋轉，卻落在雙覆蓋的不同「半球」，直接插值會繞遠路甚至反向，所以要先翻號讓兩者落在同一個 hemisphere。四元數的代價是用四個數描述一個三維流形，多出的一個自由度被 unit constraint `|q|=1` 吃掉，但這個自由度不是白白浪費，它換來了組合跟插值上沒有奇異點的好處。
]

== Gimbal lock：壞掉的是 chart，不是旋轉

#row(widths: (1.3fr, 1fr), gutter: .9em, align: horizon)[
  #image("assets/gimbal-lock.svg", width: 100%)
][
  #col(gap: .5em)[
    #equation[$R=R_z(psi)R_y(theta)R_x(phi)$]
    #equation[$theta=plus.minus pi/2 arrow.r.double "rank" frac(partial R, partial (phi,theta,psi))<3$]
    #callout(kind: "warn", compact: true)[繞第一軸跟繞第三軸產生的瞬時旋轉方向重合。]
  ]
]
#v(.4em)
#claim(
  tint: palette.rose,
)[在 $theta=plus.minus pi/2$，Euler 座標的 differential 降 rank。$"SO"(3)$ 仍然是三維，跟 Part 1「$S^1$ 不能用單一 chart 覆蓋」是同一類故障：chart 壞掉，流形本身保持完好。換 representation，不是替機器人補一個自由度。]

#speaker-note[
  相對地，Euler angle `R=R_z(ψ)R_y(θ)R_x(φ)` 這種用三個數描述的參數化，天生會在某些姿態出問題，這就是 gimbal lock，而且可以精確地用秩來刻劃它。把 `R` 對 `(φ,θ,ψ)` 求偏導數排成 Jacobian，在 `θ=±π/2` 時可以直接驗證這個 `3×3` Jacobian 的其中兩欄變成線性相關(繞第一軸跟繞第三軸產生的瞬時旋轉方向重合)，導致 `rank ∂R/∂(φ,θ,ψ)<3`。這句話值得慢慢咀嚼：gimbal lock 發生在 Euler angle 這組座標系統的 differential 退化處，三個座標方向的瞬時變化在那一點變得線性相關。跟 Part 1 討論 `S¹` 不能用單一 chart 覆蓋是同一類故障：chart 壞掉，流形本身保持完好。解法是改用另一種表示。
]

== 為什麼 $exp$ 的微分不是單位映射？

#equation[$"錯誤猜測：" quad exp(hat(phi+delta phi)) = exp(hat(delta phi))exp(hat(phi))$]
#v(.45em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.teal,
    title: [$"SO"(2)$：成立],
  )[$[hat(phi),hat(delta phi)]=0$，所以指數把加法精確變成乘法（Part 2 的 $"SO"(2)$ 是交換群）。]
][
  #card(
    tint: palette.rose,
    title: [$"SO"(3)$：一般不成立],
  )[擾動方向會沿 $exp(s hat(phi))$ 被旋轉。座標增量不等於群上的瞬時增量。]
]
#v(.5em)
#claim[如果我在 $phi$ 這一點附近走一小步 $delta phi$，$exp(hat(phi+delta phi))$ 跟 $exp(hat(phi))$ 差多少？左右 Jacobian 就是把 $delta phi$ 轉成可左乘或右乘的真實小旋轉。]

#speaker-note[
  現在可以回頭處理一個被刻意留到現在的問題：`exp` 映射的微分是什麼?換句話說,如果在 `φ` 這一點附近走一小步 `δφ`,`exp(φ̂+δφ̂)` 跟 `exp(φ̂)` 差多少?在交換群(比如 `SO(2)`,或者 Part 0 的 `S¹`)裡這個問題平凡,因為 `exp(a+b)=exp(a)exp(b)` 精確成立。但 `SO(3)` 不交換,`exp` 不是群同態,這個微分必須額外算。答案的形式是 `exp((φ+δφ)^)≈exp((J_r(φ)δφ)^)exp(φ̂)`。`J_r` 叫 right Jacobian,它把「座標空間裡的微小變化 `δφ`」轉換成「真正作用在群上、可以右乘的瞬時旋轉」。因為 `SO(3)` 不交換,這個轉換不會等於單位映射,如果它交換,`J_r` 就會恆等於單位矩陣,跟 `SO(2)` 的狀況一樣。
]

== 右 Jacobian：把沿途旋轉的擾動平均起來

#equation[$exp(hat(phi+delta phi)) approx exp(hat(phi))exp(hat(J_r(phi)delta phi))$]
#v(.2em)
#equation[$J_r(phi)=integral_0^1 "Ad"_(exp(-s hat(phi))) dif s=integral_0^1 exp(-s hat(phi)) dif s$]
#v(.2em)
#equation[$integral_0^1 exp(s omega) dif s = I+frac(1-cos theta, theta^2)omega+frac(theta-sin theta, theta^3)omega^2$]
#v(.2em)
#equation[$J_r(phi)=I-frac(1-cos theta, theta^2)hat(phi)+frac(theta-sin theta, theta^3)hat(phi)^2$]
#v(.3em)
#callout(
  kind: "info",
  compact: true,
)[$"Ad"_R eta:=R hat(eta) R^T$ 在 hat/vee 字典下正好等於 $R$ 本身（Part 3 前面剛證過 $R hat(omega) R^T=(R omega)^and$）。取 $omega=-phi$ 代入積分結果即得 $J_r$。]

#speaker-note[
  這個推導分兩步。第一步是一般矩陣 Lie group 理論裡的標準結果，直接引用結論：`J_r(φ)=∫₀¹Ad_{exp(-sφ̂)}ds`。`Ad`(Adjoint)是「用群元素共軛作用在 Lie algebra 上」的線性算子，我們會在 Part 4 正式定義它，這裡先用它的意思：`Ad_R` 把 `R∈SO(3)` 對 `η̂∈𝔰𝔬(3)` 的共軛作用 `Rη̂R^T` 記成一個線性算子。

  第二步，把這個積分具體算出來，我們已經有全部需要的工具，不必再引用任何人。關鍵是一個只在 `SO(3)` 才成立的巧合：`Ad_R` 在 hat/vee 字典下,就是 `R` 這個矩陣本身。回頭看這個 Part 稍早驗證的恆等式 `Rω̂R^T=(Rω)^`，按 `Ad` 的定義,`Ad_R(η̂):=Rη̂R^T`,而這條恆等式說 `Ad_R(η̂)=(Rη)^`,翻回向量座標就是 `Ad_Rη=Rη`。`Ad_R` 不是另一個要重新計算的算子,它精確等於 `R`。代入積分：`J_r(φ)=∫₀¹exp(-sφ̂)ds`。這個積分跟 Rodrigues 公式算法一模一樣：把 `exp(sω̂)=I+sin(sθ)â+(1-cos(sθ))â²` 逐項對 `s` 從 `0` 積到 `1`，`∫₀¹sin(sθ)ds=(1-cosθ)/θ`、`∫₀¹(1-cos(sθ))ds=(θ-sinθ)/θ`，取 `ω=-φ` 代入(`hat` 線性、平方不管正負號、模長不變)，得到 `J_r(φ)=I-((1-cosθ)/θ²)φ̂+((θ-sinθ)/θ³)φ̂²`。
]

== 左右只差擾動放在哪一側

#row(widths: (1fr, 1fr), gutter: .85em)[
  #card(tint: palette.iris, title: [right / body])[
    $exp(hat(phi+delta phi)) approx exp(hat(phi))exp(hat(J_r delta phi))$
  ]
][
  #card(tint: palette.teal, title: [left / spatial])[
    $exp(hat(phi+delta phi)) approx exp(hat(J_l delta phi))exp(hat(phi))$
  ]
]
#v(.4em)
#equation[$J_l(phi)=J_r(-phi)=I+frac(1-cos theta, theta^2)hat(phi)+frac(theta-sin theta, theta^3)hat(phi)^2$]
#v(.35em)
#claim(
  tint: palette.iris,
)[Solver 算的是 axis-angle 座標增量。controller 需要的是指定 frame 的 angular velocity。$J_l,J_r$ 是兩者之間的橋，而且 $J_l(phi)$ 跟 Part 4 要推的 $"SE"(3)$ 指數映射裡的 $V$ 矩陣一字不差，是同一個線性算子在兩個語境下的化身。]

#speaker-note[
  而 `J_l(φ)=J_r(-φ)`，這個對稱關係來自 `exp(φ̂)⁻¹=exp(-φ̂)`,左右 Jacobian 分別對應把微小變化「左乘」或「右乘」到群元素上,反轉 `φ` 的正負號恰好對應反轉乘的方向。直接代入翻號,得到 `J_l(φ)=I+((1-cosθ)/θ²)φ̂+((θ-sinθ)/θ³)φ̂²`。

  拿這個結果跟 Part 4 要推的 `V(ω)=I+((1-cosθ)/θ²)ω̂+((θ-sinθ)/θ³)ω̂²` 對照，兩式一字不差，`J_l(φ)` 就是 `V(φ)`。這是同一個線性算子在兩個不同語境下出現：等到 Part 4 看到 `SE(3)` 指數映射裡的 `V` 矩陣時，我們會直接引用這裡的結果，不必重新推導一次。`J_l`、`J_r` 的作用是把 axis-angle 座標的變化率，轉換成真正的 body 或 spatial 角速度，這正是為什麼 IK 求解器在座標空間裡算出一個增量 `δφ` 後，不能直接拿去更新，必須先透過 `J_r` 或 `J_l` 轉換，才是幾何上正確的瞬時旋轉量。
]

== BCH 的二階項不是魔法：直接比較冪級數

#set text(size: .88em)
#equation[$exp A exp B=I+(A+B)+(A^2/2+A B+B^2/2)+cal(O)(3)$]
#v(.25em)
#equation[$exp(A+B)=I+(A+B)+(A^2+A B+B A+B^2)/2+cal(O)(3)$]
#v(.4em)
#equation[$exp A exp B-exp(A+B)=1/2(A B-B A)+cal(O)(3)=1/2[A,B]+cal(O)(3)$]
#v(.45em)
#claim[交換子正是「先 $A$ 後 $B$」相對於直接相加所欠缺的二階面積，精確對應 Part 1 那個具體算例 $R_x(pi/2)R_y(pi/2) != R_y(pi/2)R_x(pi/2)$ 的差別。]

#speaker-note[
  最後回到 Part 1 留下的伏筆：BCH(Baker Campbell Hausdorff)公式，正式給出「兩個 Lie algebra 元素的指數相乘，log 回來等於什麼」的完整答案。先手算二階項是否真的是 `[A,B]/2`：把 `exp(A)exp(B)` 用冪級數乘開到二階，`exp(A)exp(B)=(I+A+A²/2+…)(I+B+B²/2+…)=I+(A+B)+(A²/2+AB+B²/2)+…`。而 `exp(A+B)` 展開到二階是 `I+(A+B)+(A+B)²/2=I+(A+B)+(A²+AB+BA+B²)/2`。兩者二階項相差 `(AB−BA)/2=[A,B]/2`，這就是為什麼「先轉 A 再轉 B」跟「先轉 B 再轉 A」的差別，精確地由 commutator 的二分之一給出，正是 Part 1 `R_x(π/2)R_y(π/2)≠R_y(π/2)R_x(π/2)` 那個具體算例的一般化公式。
]

== BCH 告訴你：何時可以把旋轉增量相加

#equation[$log(exp A exp B)=A+B+1/2[A,B]+1/12([A,[A,B]]+[B,[B,A]])+dots$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.teal,
    title: [安全的一階區域],
  )[若 $norm(A),norm(B)$ 都小，commutator 是二階量。高頻、小步長更新可近似相加。]
][
  #card(
    tint: palette.rose,
    title: [該擔心的時候],
  )[DLS 一步很大、旋轉軸近乎正交，或把多個 frame 的增量直接相加時，二階項不可忽略。]
]
#v(.4em)
#callout(
  kind: "tip",
  compact: true,
)[套用在 $"SO"(2)$：$frak("so")(2)$ 是一維空間，任兩元素都交換，$[A,B]=0$，高階修正全部消失，只剩 $A+B$，這正好解釋 Part 2 為什麼角度可以直接相加。實務檢查：比較 $norm([A,B])\/2$ 與 $norm(A+B)$。比例不可忽略時，縮小 step 或直接在群上 composition。]

#speaker-note[
  看完整式子：當 `A,B` 很小，一階近似就是直接相加，這對應「小角度旋轉近似可交換」的直覺。二階開始，commutator 項記錄了先做 `A` 再做 `B` 跟反過來做的差異，跟一開始 `R_x(π/2)R_y(π/2)≠R_y(π/2)R_x(π/2)` 的具體算例是同一件事的一般化公式。順帶一提，如果把這條公式套用在 `SO(2)`，因為 `𝔰𝔬(2)` 是一維空間，任兩個元素都彼此交換，`[A,B]=0`，所有高階修正項全部消失，只剩 `log(expAexpB)=A+B`，這正好解釋了為什麼 `SO(2)`(也就是 Part 0 的複數)的角度可以直接相加，而 `SO(3)` 不行:BCH 的高階修正項,就是非交換性在數學上的具體代價。
]

= Part 4 · $"SE"(3)$：剛體運動的 Lie group

== $"SE"(3)$：homogeneous transform 與組合律

#equation[$T=mat(R, p; 0^T, 1) in "SE"(3), quad "SE"(3)={T: R in "SO"(3), p in RR^3}$]
#v(.3em)
#equation[$mat(R_1, p_1; 0, 1) mat(R_2, p_2; 0, 1) = mat(R_1 R_2, R_1 p_2+p_1; 0, 1)$]
#v(.2em)
#equation[$(R_1,p_1)(R_2,p_2)=(R_1R_2,p_1+R_1p_2), quad "SE"(3) equiv RR^3 ⋊ "SO"(3)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.iris,
    title: [記號],
  )[$A_T_B$ 表示「把 B-frame coordinates 轉成 A-frame coordinates」，notation 必須固定，之後每一次公式驗證都靠它。]
][
  #card(
    tint: palette.rose,
    title: [semidirect product],
  )[第二段平移 $p_2$ 先被第一段旋轉 $R_1$ 作用過，才跟 $p_1$ 相加，不是簡單的 $p_1+p_2$。旋轉不交換是一個原因，平移被旋轉耦合是另一個原因，兩者疊加讓 $"SE"(3)$ 的結構比 $"SO"(3)$ 更豐富。]
]

#speaker-note[
  旋轉解決了姿態，但機器人手臂末端還需要位置。把旋轉跟平移打包進一個矩陣，這個 `4×4` 齊次矩陣的結構不是排版方便而已，它讓「剛體變換的組合」變成單純的矩陣乘法：直接把兩個這樣的矩陣相乘，寫成 pair 記號，`(R₁,p₁)(R₂,p₂)=(R₁R₂,p₁+R₁p₂)`。

  注意平移的部分不是簡單的 `p₁+p₂`，第二段平移 `p₂` 在相加之前先被第一段旋轉 `R₁` 作用過。這個耦合有名字：`SE(3)≅R³⋊SO(3)`，一個 semidirect product，`SO(3)`「作用」在 `R³` 上而不只是跟它獨立地湊在一起。這正是 `SE(3)` 非交換的來源，旋轉部分本身不交換是一個原因，平移被旋轉耦合是另一個原因，兩者疊加讓 `SE(3)` 的非交換結構比 `SO(3)` 更豐富。
]

== Inverse 需要旋轉平移向量

#equation[$(R,p)(R',p')=(R R', p+R p')=(I,0) arrow.double R'=R^T, quad p'=-R^T p$]
#v(.3em)
#equation[$T^(-1)=mat(R^T, -R^T p; 0^T, 1)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.rose,
    title: [常見錯誤],
  )[猜 $(R^T,-p)$：直接把 $p$ 取負，卻忘了 $p$ 是用舊 frame 座標表示，不能直接搬到新 frame 裡用。]
][
  #card(
    tint: palette.teal,
    title: [正確理解],
  )[$-R^T p$ 是「舊原點在新 frame 裡的位置」：先把 $p$ 用 $R^T$ 轉到新座標方向，再取負，因為問的是「反過來看，原點跑到哪裡去了」。]
]

#speaker-note[
  取逆同樣不能想當然爾。從定義 `TT⁻¹=I` 直接解：若 `T⁻¹=(R',p')`，則 `(R,p)(R',p')=(RR',p+Rp')=(I,0)`，所以 `RR'=I⟹R'=R^T`，`p+Rp'=0⟹p'=-R^Tp`。一個常見的錯誤是猜 `T⁻¹` 的平移部分是 `(R^T,-p)`，直接把 `p` 取負，卻忘了 `p` 是用舊 frame 的座標表示，不能直接搬到新 frame 裡用。正確理解是 `-R^Tp` 代表「舊座標系的原點,在新座標系裡的位置」。
]

== $frak("se")(3)$ 與 twist：screw motion 的座標

#equation[$xi=mat(v; omega) in RR^6, quad hat(xi)=mat(hat(omega), v; 0^T, 0)$]
#v(.3em)
#equation[$dot(x)=omega times (x-q)+h omega, quad norm(omega)=1$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.iris,
    title: [繞軸旋轉],
  )[$omega times(x-q)$ 是點 $x$ 繞過 $q$ 的軸產生的切向速度，$v$ 的意義依 body / spatial trivialization 而變。]
][
  #card(
    tint: palette.teal,
    title: [沿軸推進],
  )[$h omega$ 對所有點相同。$h$ 是每 radian 沿軸前進的距離（pitch），Sophus tangent ordering 是 $[v,omega]$。]
]
#v(.4em)
#claim[一個 twist 代表一整個 rigid velocity field，像鎖螺絲一樣繞軸旋轉同時沿軸平移，六個數字只是它的座標。]

#speaker-note[
  跟 `SO(3)` 完全平行的手法，`SE(3)` 的 Lie algebra 由 twist 構成，`ω` 是角速度分量，`v` 是線速度分量，但 `v` 的物理意義依 body 或 spatial trivialization 而變(跟 Part 3 的 `ω_b`、`ω_s` 是同一套區分)。

  Twist 有一個漂亮的幾何圖像：每一個 twist 都對應一個螺旋運動(screw motion)，繞著某條軸旋轉，同時沿著這條軸平移，像鎖螺絲一樣。設螺旋軸方向為單位向量 `ω`、軸上任一點為 `q`、pitch 為 `h`(每轉一弧度沿軸前進多少)。剛體上通過原點的瞬時速度場，一般點 `x` 的瞬時速度是 `ω×(x-q)+hω`(繞軸 `q` 方向 `ω` 旋轉的貢獻，加上沿軸平移的貢獻)。Screw theory 的價值在於，它讓我們用三個有明確幾何意義的量，軸的位置、軸的方向、沿軸的推進速度，完整描述任何一個瞬時剛體運動，而不必逐一檢查 twist 六個座標分量各自代表什麼。
]

== Twist 公式從參考原點的速度直接讀出

#equation[$x=0 arrow.r.double dot(x)=underbrace(-omega times q+h omega, v)$]
#v(.35em)
#equation[$xi=mat(v; omega), quad v=-omega times q+h omega$]
#v(.45em)
#row(gutter: .75em)[
  #card(tint: palette.iris, title: [$h=0$])[純旋轉：$v=-omega times q$，沒有沿軸平移分量。]
][
  #card(tint: palette.teal, title: [$omega=0$])[退化為純平移：直接以 $xi=(v,0)$ 表示。]
][
  #card(tint: palette.amber, title: [軸上點])[$x=q$ 時速度只剩 $h omega$（旋轉不貢獻切向速度）。]
]

#speaker-note[
  取 `x=0`(twist 定義所在的參考點)，線速度分量就是 `v=-ω×q+hω`。`h=0` 對應純旋轉(沒有沿軸平移分量，`v=-ω×q` 恰好是「繞 `q` 軸旋轉」在原點產生的線速度)。`ω=0` 對應純平移(這個極限需要另外定義，標準做法是直接令 `ω=0,v=`平移方向)。
]

== $"SE"(3)$ 的 exp 與 log

#equation[$exp(hat(xi))=mat(exp(hat(omega)), V(omega)v; 0^T, 1), quad V(omega)=integral_0^1 exp(s hat(omega)) dif s = I+frac(1-cos theta, theta^2)hat(omega)+frac(theta-sin theta, theta^3)hat(omega)^2$]
#v(.3em)
#equation[$op("vee")(log T)=mat(v; omega), quad omega=op("vee")(log R), quad v=V(omega)^(-1)p$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.teal,
    title: [exp],
  )[跟 Part 3 右 Jacobian 積分同一算法（$hat(a)^3=-hat(a)$ 摺疊），$V(omega)$ 跟 Part 3 的 $J_l(phi)$ 是同一矩陣，一字不差。]
][
  #card(
    tint: palette.rose,
    title: [log],
  )[$p$ 是實際量到的有限位移，$v$ 是產生整段 screw motion 所需的 twist 座標。兩者只在小角度（$V approx I$）或純平移（$omega=0$）時才近似相同。]
]

#speaker-note[
  `SE(3)` 的指數映射，結構上延續 Rodrigues 公式的計算方式，但要多處理平移的耦合。`ξ̂` 分塊為 `[ω̂,v;0,0]`，冪級數 `exp(ξ̂)` 的旋轉部分自然就是 `exp(ω̂)`(跟 `SO(3)` 一致)，平移部分由 `V(ω)v` 給出。`V` 這個矩陣的來源，直覺上是「在旋轉持續發生的過程中，把瞬時線速度 `v` 積分起來」，`V(ω)=∫₀¹exp(sω̂)ds`。這個積分我們在 Part 3 推左右 Jacobian 時已經算過一次：用跟 Rodrigues 公式一樣的 `â³=-â` 摺疊技巧展開，把 `ω` 換成 `φ`，這正是 Part 3 算出來的 `J_l(φ)`，一字不差，`SE(3)` 指數映射裡負責「捲平移」的 `V`，跟 `SO(3)` 裡負責「捲座標速率」的左 Jacobian，是同一個線性算子。這條公式告訴我們一件容易被忽略的事：即使 twist 裡的 `v` 是常數,`exp(ξ̂)` 裡對應的實際平移量仍是 `Vv`，因為旋轉在同一段時間裡持續改變線速度的方向。

  反方向，`log` 要把 `p` 拆解成產生這段運動的 twist 座標。旋轉部分直接沿用 `SO(3)` 的 log，`ω=vee(logR)`，平移部分要用 `V` 的逆修正：`v=V(ω)⁻¹p`。這裡 `p` 是有限位移(你實際量到的、從起點到終點的直線距離)，`v` 是產生這整段螺旋運動所需要的 twist 座標，兩者只有在小角度(`V≈I`)或純平移(`ω=0⟹V=I`)時才近似相同，一般情形下，`p` 跟 `v` 是兩個不同的量，不能混用。
]

== Adjoint：從共軛作用推導到物理意義

#equation[$T hat(xi) T^(-1) = mat(R, p; 0, 1)mat(hat(omega), v; 0, 0)mat(R^T, -R^T p; 0, 1)=mat((R omega)^and, -(R omega) times p + R v; 0, 0)$]
#v(.3em)
#equation[$"Ad"_T=mat(R, hat(p)R; 0, R), quad mat(v'; omega')="Ad"_T mat(v; omega)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.teal,
    title: [angular],
  )[$omega'=R omega$：同一方向換一組座標基底，跟 Part 3 的 $omega_s=R omega_b$ 完全一致。]
][
  #card(
    tint: palette.iris,
    title: [linear],
  )[$v'=R v+p times R omega$：搬動觀測原點多出的槓桿臂速度，像站在地軸上跟站在赤道上，同一個角速度對應的線速度大小不同。]
]
#v(.4em)
#claim(
  tint: palette.iris,
)[$xi_s="Ad"_T xi_b$。Adjoint 不是新運動。它是同一個 twist 的 frame conversion。用 $R hat(omega) R^T=(R omega)^and$（Part 3 已證），$-(R omega)^and p=p times (R omega)=hat(p)(R omega)$，即可重新讀回 twist 座標。]

#speaker-note[
  接下來是 Adjoint，回答「同一個 twist，換一個參考 frame 表示，長什麼樣子」。設 `T=(R,p)`，想知道 `Tξ̂T⁻¹` 展開後長什麼樣。直接做分塊矩陣乘法：先算中間兩塊相乘，再右乘 `T⁻¹`。用 Part 3 證過的恆等式 `Rω̂R^T=(Rω)^`，並注意 `-Rω̂R^Tp=-(Rω)^p=-(Rω)×p=p×(Rω)=p̂(Rω)`，整理後得到 `Ad_T=[R,p̂R;0,R]`。

  這個結果值得對照解讀：角速度部分換 frame 只是單純被旋轉，`ω_new=Rω_old`，這跟 Part 3 推的 `ω_s=Rω_b` 完全一致。但線速度部分除了旋轉，還多出 `p̂Rω` 這一項，物理意義是移動觀測原點會改變旋轉貢獻出的線速度：以地球自轉為例，站在地軸上與站在赤道上，同一個角速度 `ω` 對應的線速度大小不同，差異正比於離轉軸的距離，`p̂Rω` 正是這個「距離 × 角速度」貢獻的精確表示式。
]

== Lie bracket：量化兩個 twist 的順序效應

#equation[$"ad"_xi=mat(hat(omega), hat(v); 0, hat(omega)), quad [xi,eta]="ad"_xi eta$]
#v(.25em)
#equation[$frac("d", "d"t)|_(t=0) "Ad"_(exp(t hat(xi))) eta = "ad"_xi eta$]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[$"ad"_xi$ 是 $"Ad"$ 在 identity 處的 differential：把上一頁 $"Ad"_T$ 公式裡的 $T$ 換成 $exp(t hat(xi))$，對 $t$ 微分並取 $t=0$，$hat(p)R$ 這一塊的線性化恰好摺成 $hat(v)$，這正是「有限共軛作用」與「無窮小 bracket」之間的橋。]
#v(.3em)
#claim[先做一點 $xi$ 再做一點 $eta$，與相反順序的差在二階由 $[xi,eta]$ 決定，跟 Part 1、Part 3 的 commutator 是同一個故事的六維版本，正是剛體運動的局部曲率：衡量這個群在這一點附近偏離「平坦、可交換」有多遠。]

#speaker-note[
  有了 `Ad`，Lie bracket 在 `SE(3)` 上的表示可以直接寫出來。跟 Part 1、Part 3 的 commutator 是同一個故事的六維版本：先做一點 `ξ` 再做一點 `η`，跟反過來的順序，兩者的差在二階由 `[ξ,η]` 決定，這正是剛體運動的局部曲率，衡量這個群在這一點附近偏離「平坦、可交換」有多遠。

  `ad_ξ` 不是憑空定義的新算子，它是 `Ad` 在 identity 處的 differential：把上一頁的 `Ad_T` 公式裡的 `T` 換成 `exp(tξ̂)`，對 `t` 微分、在 `t=0` 取值，旋轉部分 `R(t)=exp(tω̂)` 微分在 `t=0` 給出 `ω̂`，平移部分 `p(t)̂R(t)` 這一塊微分後摺成 `v̂`，整理後恰好得到 `ad_ξ=[ω̂,v̂;0,ω̂]`。這條線索也解釋了為什麼 `ad` 跟 `Ad` 用同一個字母：`ad` 就是 `Ad` 這個有限共軛作用，在群元素趨近 identity 時的無窮小版本，跟 Part 1「群提供有限組合、algebra 提供局部線性化」的一般原則完全一致。
]

== Pose error 有左不變與右不變兩種 convention

#equation[$E_b=T^(-1)T_d, quad e_b=op("vee")(log E_b)$]
#v(.25em)
#equation[$E_s=T_d T^(-1), quad e_s=op("vee")(log E_s)="Ad"_T e_b$]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[body-frame error 配右乘更新 $T arrow.l T exp(Delta t hat(e)_b)$（右乘對應在物體自己座標系疊加動作，呼應 $hat(omega)_b=R^T dot(R)$）。spatial-frame error 配左乘更新。混用不會讓程式當掉，卻會讓 controller 收斂方向隨姿態悄悄扭曲，這種 bug 極難從動畫肉眼抓出來，只能靠檢查 frame 下標是否前後一致。]

#speaker-note[
  最後，把這一整套工具用在 pose error 上，而且這裡藏著一個經常被寫錯的地方。同樣兩個姿態 `T`(目前)跟 `T_d`(目標)，body-frame 的誤差是 `E_b=T⁻¹T_d`，`e_b=vee(logE_b)`。spatial-frame 的誤差是 `E_s=T_dT⁻¹`，`e_s=vee(logE_s)`。這兩個誤差不是同一個東西，但彼此有精確關係：`e_s=Ad_Te_b`，這正是 Adjoint「換 frame 表示同一個 twist」的直接應用，只是這裡換的是 error 而非一般 twist。這個區分決定了控制器的更新方式必須配對：如果誤差是用 body frame 算的，更新就必須右乘 `T←Texp(Δt·e_b)`。如果指令是用 spatial frame 給的，就必須左乘。混用，比如用 body error 卻做左乘更新，不會讓程式當掉，但會讓 controller 的收斂方向隨著姿態改變而扭曲，這種 bug 極難用肉眼從動畫上抓出來，只能靠檢查 frame 的下標是否前後一致。
]

= Part 5 · Forward Kinematics

== Configuration space 具有自己的拓撲

#equation[$cal(Q)=S^1 times dots times S^1 times RR times dots$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.iris,
    title: [revolute joint],
  )[$q_i in S^1$。$q_i$ 與 $q_i+2pi$ 是同一 configuration，跟 Part 0 的圓周座標是同一件事。]
][
  #card(tint: palette.teal, title: [prismatic joint])[$q_i in RR$ 或受限 interval。]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[一個 $n$-joint robot 的 configuration manifold 通常是 product manifold，若有 closed-loop 還要再扣掉 loop-closure constraints，跟 $"SO"(3)$ 從 $RR^9$ 扣掉約束變成三維流形是同一個邏輯。]

#speaker-note[
  配置空間 `Q` 不是隨便一串實數。每一個 revolute joint 的角度 `q_i` 活在 `S¹` 上，`q_i` 跟 `q_i+2π` 是同一個物理配置，跟 Part 0 的圓周座標是同一件事。每一個 prismatic joint 的位移 `q_i` 活在 `R`(或受限的區間)上。一個 `n` 關節機器人的配置空間，通常是這些單一關節空間的乘積流形 `Q=S¹×⋯×S¹×R×⋯`，如果機器人有 closed-loop(例如四連桿)，還要再扣掉 loop-closure 約束，跟 `SO(3)` 從 `R^9` 扣掉約束變成三維流形是同一個邏輯：先寫出寬鬆的 ambient 空間，再用約束方程削掉多餘自由度。
]

== Kinematic map 把 configuration 映到 task space

#equation[$F: cal(Q) arrow "SE"(3), quad q arrow T_("world","tool")(q)$]
#v(.4em)
#row(gutter: .75em)[
  #card(tint: palette.teal, title: [forward kinematics])[給 $q$ 求 $T$，通常唯一且容易。]
][
  #card(
    tint: palette.rose,
    title: [inverse kinematics],
  )[給 $T_d$ 求 $q$：$F$ 一般不是單射（elbow-up/down 都能到達同一姿態），這正是為什麼 IK 要另闢一整個 Part 處理。]
]

#speaker-note[
  Kinematic map `F:Q→SE(3)` 把一組關節角度映到末端姿態。正向(給 `q` 求 `T`)是這個映射本身，通常唯一且直接代入計算就好。反向(給 `T_d` 求 `q`)是要解這個映射的反函數，而 `F` 一般不是單射(elbow-up/elbow-down 都能到達同一個末端姿態)，這就是為什麼 IK 要另闢一整個 Part 來處理。
]

== Frame graph：下標就是 type system

#equation[$A_T_C=A_T_B B_T_C$]
#v(.35em)
#equation[$A_p=A_T_B B_p$]
#v(.45em)
#callout(
  kind: "warn",
  compact: true,
)[配對規則類似矩陣乘法要求維度吻合：只有前一個矩陣的「輸出 frame」等於後一個矩陣的「輸入 frame」，才能相乘。$A_T_B C_T_D$（中間 $B != C$）無法相乘，也不該相乘。把 frame 名寫進變數，讓型別檢查在打字當下就被自己的直覺抓到。]

#speaker-note[
  在真正寫出 `F` 之前，先講一個看似瑣碎、卻是最便宜的除錯工具：frame 記號本身就是一套型別系統。定義 `A_T_B` 表示「把 B-frame 座標轉成 A-frame 座標」，組合律寫成 `A_T_C=A_T_B·B_T_C`。配對規則類似矩陣乘法要求維度吻合：只有當前一個矩陣的「輸出 frame」等於後一個矩陣的「輸入 frame」，才能相乘，`A_T_B·C_T_D`(中間 `B≠C`)無法相乘，也不該相乘。把 frame 名字寫進變數名稱裡，讓這個檢查在你打字的當下就會被你自己的直覺抓到，比事後在模擬器裡看姿態飄掉再回頭 debug 便宜得多。
]

== Denavit Hartenberg：四個參數描述相鄰 joint frames

#equation[$A_i=R_z(theta_i)T_z(d_i)T_x(a_i)R_x(alpha_i)$]
#v(.35em)
#row(gutter: .65em)[
  #card(tint: palette.iris, title: [$theta_i$])[joint angle]
][
  #card(tint: palette.teal, title: [$d_i$])[axis offset]
][
  #card(tint: palette.amber, title: [$a_i$])[link length]
][
  #card(tint: palette.rose, title: [$alpha_i$])[link twist]
]

#speaker-note[
  現在寫出具體的相鄰關節 frame 變換。Denavit Hartenberg 用四個參數描述：joint angle `θ_i`、axis offset `d_i`、link length `a_i`、link twist `α_i`，組合成 `A_i=R_z(θ_i)T_z(d_i)T_x(a_i)R_x(α_i)`，四個基本剛體變換的乘積(繞 z 轉、沿 z 平移、沿 x 平移、繞 x 轉)。
]

== 展開 DH matrix：每一欄都有幾何意義

#v(3.35em)
#equation[$A_i=mat(c_theta, -s_theta c_alpha, s_theta s_alpha, a c_theta; s_theta, c_theta c_alpha, -c_theta s_alpha, a s_theta; 0, s_alpha, c_alpha, d; 0, 0, 0, 1)$]
#v(.35em)
#callout(
  kind: "info",
  compact: true,
)[前三欄是 child frame 的三個座標軸在 parent frame 底下的座標。第四欄是 child 原點在 parent frame 底下的位置，跟一般旋轉矩陣「欄向量就是新基底」的解讀完全一致，只是多打包了一欄平移。]

#speaker-note[
  把四個基本變換一個一個乘開，得到展開後的顯式矩陣。這個矩陣的每一欄都有幾何意義，不是死記的排列：前三欄是 child frame 的三個座標軸(x,y,z 方向)在 parent frame 底下的座標表示，第四欄是 child frame 原點在 parent frame 底下的位置，跟一般旋轉矩陣「欄向量就是新基底」的解讀完全一致，只是這裡多打包了一欄平移。
]

== Serial chain composition

#v(1.35em)
#equation[$"base"_T_"tool"(q)=A_1(q_1)A_2(q_2)dots A_n(q_n) "flange"_T_"tool"$]
#v(.25em)
#equation[$T(q)=exp(hat(xi_1)q_1)dots exp(hat(xi_n)q_n)M$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.iris,
    title: [PoE：$xi_i$ 與 $M$],
  )[$xi_i$ 是 home pose 下、space frame 表示的第 $i$ 個 joint screw，coordinate-free，可直接從幾何讀出；$M$ 是所有 $q_i=0$ 時的 end-effector pose。]
][
  #card(
    tint: palette.rose,
    title: [DH：順序不能打亂],
  )[矩陣乘法不交換（Part 1 已驗證），UR-style 六軸手臂的 wrist offset 與固定 tool transform 都必須放在正確的乘積位置，挪動順序等於改變了物理上關節的連接方式。]
]

#speaker-note[
  一整條 serial chain 的正向運動學，就是把這些相鄰變換依序相乘。因為矩陣乘法不交換(Part 1 已經用具體算例驗證過)，這個乘積的順序不能打亂，UR-style 六軸手臂的 wrist offset 跟固定的 tool transform，都必須放在正確的乘積位置，挪動順序等於改變了物理上關節的連接方式。

  Product of Exponentials 提供另一種寫法，直接用 Part 3、Part 4 建立的指數映射。`ξ_i` 是第 `i` 個關節在 home pose(所有 `q_i=0`)下、用 space frame 表示的 screw axis，`M` 是所有關節角為零時的末端姿態。跟 DH 比較，DH 需要為每一對相鄰 frame 指定一組局部參數，規則清楚但容易在 standard/modified 兩種慣例間搞混。PoE 採用 coordinate-free 表示，每個 screw axis 可以直接從機器人的幾何(轉軸在哪裡、指向哪裡)讀出來，不需要中間 frame，而且跟 Part 6 要推的 Jacobian、跟 calibration 用的擾動模型形式一致。兩者都是同一個物理映射 `T(q)` 的 bookkeeping 方法。
]

== DH 與 PoE

#v(1.35em)
#row(widths: (1fr, 1fr), gutter: .85em)[
  #card(tint: palette.amber, title: [DH / local frames])[
    $T=R_z(q_1)T_x(l_1)R_z(q_2)T_x(l_2)$
  ]
][
  #card(tint: palette.teal, title: [PoE / home screws])[
    #set text(size: .78em)
    $T=e^(hat(xi_1)q_1)e^(hat(xi_2)q_2)M$

    $xi_1=mat(0; 0; 0; 0; 0; 1)$，
    $xi_2=mat(0; -l_1; 0; 0; 0; 1)$，
    $M=mat(I, mat(l_1+l_2; 0; 0); 0, 1)$。
  ]
]
#v(.45em)
#equation[$T arrow.r.double mat(R_z(q_1+q_2), mat(l_1 cos q_1+l_2 cos(q_1+q_2); l_1 sin q_1+l_2 sin(q_1+q_2)); 0, 1)$]
#v(.4em)
#claim[兩套方法的中間帳本不同。只要 frame 慣例一致，展開後對同一台機器人算出的 $T(q)$ 必須逐項相同，這是驗證兩套實作是否寫對的黃金標準。]

#speaker-note[
  把這一切收攏到最小、卻完整具備 serial composition 特徵的例子：二連桿平面手臂。兩套方法的中間帳本不同：DH 需要為每一對相鄰 frame 指定局部參數。PoE 用 home screw 跟 home pose `M`。但只要 frame 慣例一致，兩者對同一台機器人算出的 `T(q)` 必須完全相同，這是驗證兩套實作是否寫對的黃金標準。
]

== 貫穿例：二連桿平面臂

#equation[$x=l_1 cos q_1+l_2 cos(q_1+q_2)$]
#v(.2em)
#equation[$y=l_1 sin q_1+l_2 sin(q_1+q_2), quad phi=q_1+q_2$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [數值錨點])[$l_1=l_2=1$、$(q_1,q_2)=(0,pi/2)$，所以 $(x,y,phi)=(1,1,pi/2)$。]
][
  #card(
    tint: palette.teal,
    title: [接下來反覆使用],
  )[同一個 target 會拿來算 workspace、兩組 IK、Jacobian 與 singularity。]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[這個最小模型已經包含 serial composition（角度累加）、multiple IK solutions（肘部朝上/朝下都能到達同一點）、workspace boundary（$|l_1-l_2|<=r<=l_1+l_2$）與 singularity（伸直或折回時退化）四件事，Part 6、Part 7 會反覆回到這個例子把它們一一算完整。]

#speaker-note[
  連桿長 `l₁,l₂`，關節角 `q₁,q₂`，末端位置直接由三角關係疊加。這個最小模型已經包含了 serial composition(角度累加)、multiple IK solutions(肘部朝上跟朝下兩種姿態都能到達同一點)、workspace boundary(`(x,y)` 能到達的範圍受 `|l₁-l₂|≤r≤l₁+l₂` 限制)以及 singularity(伸直或折回時退化)，Part 6、Part 7 會反覆回到這個例子把後面三件事情算完整。
]

== Workspace 先告訴 IK：答案是否存在

#row(widths: (1.35fr, .8fr), gutter: .9em, align: horizon)[
  #image("assets/workspace-2r.svg", width: 100%)
][
  #col(gap: .55em)[
    #equation[$r=sqrt(x^2+y^2)$]
    #equation[$|l_1-l_2|<=r<=l_1+l_2$]
    #card(tint: palette.teal, title: [inside])[$0<r<2$：一般有兩個 IK branches。]
    #card(tint: palette.rose, title: [outside])[$r>2$：target 不可達。]
  ]
]
#v(.25em)
#claim[Workspace boundary、IK branch 合併與 Jacobian singularity 是同一個幾何事件。]

#speaker-note[
  Workspace 邊界正是幾何的直接推論：三角不等式給出 `|l₁-l₂|≤r≤l₁+l₂`。在邊界內部，一般有兩組 IK 解(elbow-up/down)。在邊界上，這兩組解合併成一個。在邊界外，無解。Part 6 的 Jacobian singularity 會證明這個合併點正好就是 `det J=0` 的地方，workspace boundary、IK branch 合併、Jacobian singularity 是同一個幾何事件從三個角度看到的結果。
]

== Forward kinematics 用不變量驗證

#row(gutter: .7em)[
  #card(tint: palette.teal, title: [group checks])[$R^T R approx I$、$det R approx 1$，最基本的合法性檢查。]
][
  #card(
    tint: palette.iris,
    title: [zero pose],
  )[$T(0)$ 應精確等於 CAD / URDF 的 home pose，任何偏差指向 frame 定義寫錯。]
][
  #card(
    tint: palette.amber,
    title: [finite difference],
  )[$F(q+epsilon e_i)$ 的瞬時方向應符合 joint axis，這已經預告了 Part 6 要正式推導的 Jacobian。]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[貫穿例的 zero-pose check：DH 乘積在 $q=0$ 應精確化簡回 PoE 的 $M=mat(I, (l_1+l_2\, 0\, 0)^T; 0, 1)$，兩套 bookkeeping 在這一點必須完全對齊，這正是 Part 5 前面「DH 與 PoE 算成同一式」黃金標準的最小可執行版本。]

#speaker-note[
  驗證正向運動學不能只靠肉眼看動畫像不像。三種便宜又可靠的檢查：group check，這是最基本的合法性檢查。zero pose check，任何偏差都指向 frame 定義寫錯。finite-difference check，對第 `i` 個關節做 `F(q+εe_i)`，瞬時變化的方向應該符合這個關節軸的物理方向，這個檢查其實已經預告了 Part 6 要正式推導的 Jacobian。

  對貫穿例的二連桿手臂而言，zero-pose check 有一個立即可以動手算的版本：把 `q=0` 代入 DH 乘積，應該精確化簡回 PoE 那一頁定義的 `M`，也就是旋轉部分是 `I`、平移部分是 `(l₁+l₂,0,0)`。這不只是抽象原則，是每次改動 URDF 或 DH 參數後都該立刻重新跑一次的迴歸測試。
]

= Part 6 · Differential Kinematics

== Jacobian 是 forward map 的 differential

#equation[$"d"F_q: T_q cal(Q) arrow T_(F(q)) "SE"(3), quad xi=J(q) dot(q)$]
#v(.3em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [revolute])[
    #align(center)[$J_i=mat(z_i times(p_e-p_i); z_i)$]
    #v(.25em)
    繞軸的切向線速度，加上 unit angular velocity。
  ]
][
  #card(tint: palette.teal, title: [prismatic])[
    #align(center)[$J_i=mat(z_i; 0)$]
    #v(.25em)
    沿軸平移，不產生角速度。
  ]
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[Part 1 已強調 Jacobian 是切空間之間的線性映射，$J$ 的每一欄是「只讓第 $i$ 個 joint 以 unit speed 動、其他關節固定」所產生的 end-effector twist。revolute 欄公式正是 Part 4 screw theory 純旋轉（$h=0$）公式 $v=-omega times q$ 的具體實例化，把 $q$ 換成從轉軸到末端的相對位置 $p_e-p_i$。]

#speaker-note[
  Jacobian 是 forward map 的 differential，`dF_q:T_qQ→T_{F(q)}SE(3)`，把關節速度映到末端 twist：`ξ=J(q)q̇`。Part 1 已經強調過，Jacobian 是切空間之間的線性映射，矩陣元素由偏導數給出，`J` 的每一欄，對應「只讓第 `i` 個關節以單位速度轉動、其他關節固定」時，末端產生的瞬時 twist。

  先推 revolute joint 的欄。設第 `i` 個關節的轉軸方向為 `z_i`、轉軸上一點為 `p_i`、末端位置為 `p_e`。如果只有第 `i` 個關節以單位角速度轉動，末端相對整個機構的瞬時角速度直接就是 `z_i`，末端的線速度則是「繞 `p_i` 軸旋轉」在 `p_e` 這一點產生的切向速度，套用 Part 4 screw theory 純旋轉(`h=0`)的公式 `v=-ω×q`，這裡的 `q` 要換成從轉軸到末端的相對位置 `p_e-p_i`。Prismatic joint 更簡單：沿軸方向平移，只產生線速度，不產生角速度。這兩條欄公式,就是絕大多數 geometric Jacobian 實作的計算核心，不管機器人有幾個關節，組出 `J` 的方式就是把每一關節套進這兩條公式之一，再依序排成欄。
]

== Spatial 與 body Jacobian：Adjoint 遞推與轉換

#equation[$J_s(q)=[xi_1, "Ad"_(e^(xi_1 q_1))xi_2, dots, "Ad"_(e^(xi_1q_1)dots e^(xi_(n-1)q_(n-1)))xi_n]$]
#v(.25em)
#equation[$xi_s=J_s dot(q), quad xi_b=J_b dot(q), quad J_s="Ad"_T J_b$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.teal,
    title: [遞推],
  )[第一個關節的 screw axis 直接是 home 姿態下的表示。第 $i$ 個 axis 要被前面所有關節的累積運動搬動，$"Ad"$ 正是「搬動一個 twist、換到另一個 frame 底下表示」的線性算子。]
][
  #card(
    tint: palette.rose,
    title: [不能跨 frame 混用],
  )[error twist、Jacobian 與 command 必須在同一 frame。跨 frame 混合會讓 least squares 的各列失去共同物理意義，收斂方向會悄悄歪掉，而不是讓 solver 明顯發散。]
]

#speaker-note[
  如果用 PoE 表示，Jacobian 的欄可以用 Adjoint 遞推地寫出來。直覺是:第一個關節的 screw axis `ξ₁` 直接是 home 姿態下的表示,不需要修正,但第二個關節的 axis 在機構開始運動後(第一關節轉了 `q₁`)，它在空間中的實際位置跟方向已經被第一關節的運動「搬動」過，所以要用 `Ad_{exp(ξ̂₁q₁)}` 把它從 home 姿態的座標,轉換成當下姿態的座標。以此類推,第 `i` 個 axis 要被前面所有關節的累積運動搬動。`Ad` 在這裡的角色跟 Part 4 一致，「搬動一個 twist,換到另一個 frame 底下表示」的線性算子,而這正是「前面的關節會搬動後面的 screw axis」這句話的精確數學版本。

  跟 Part 3、Part 4 一樣，body 跟 spatial 兩種 Jacobian 透過 Adjoint 互相轉換：`J_s=Ad_TJ_b`。同一套「error、Jacobian、command 必須配對在同一個 frame」的紀律在這裡完全適用，如果拿 `J_s` 去乘一個 body-frame 的 twist，得到的最小平方問題裡每一列根本不代表同一個物理量，解出來的關節速度會系統性地錯誤，而且這種錯誤通常不會讓 solver 發散，只會讓收斂方向悄悄歪掉。
]

== 二連桿 Jacobian：解析式與數值驗證

#equation[$J=mat(-l_1 s_1-l_2 s_12, -l_2 s_12; l_1 c_1+l_2 c_12, l_2 c_12), quad dot(p)=J(q)dot(q)$]
#v(.3em)
#equation[$l_1=l_2=1, quad (q_1,q_2)=(0,pi/2), quad p=(1,1) quad arrow.double quad J=mat(-1, -1; 1, 0)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [只動 shoulder])[$J(:,1)=(-1,1)^T$：末端繞原點的切線方向。]
][
  #card(tint: palette.teal, title: [只動 elbow])[$J(:,2)=(-1,0)^T$：末端繞 elbow $(1,0)$ 的切線方向。]
]
#v(.4em)
#claim[Jacobian column 不是抽象偏導數。它是「只開一顆馬達」時末端立刻往哪裡走，代入 Part 5 貫穿例的數值錨點，逐欄都能用眼睛驗證。]

#speaker-note[
  回到二連桿手臂，把 Part 5 的 `x(q),y(q)` 對 `q₁,q₂` 分別偏微分。驗證這確實是 differential map 的座標矩陣的方式，是直接檢查 `ṗ=J(q)q̇` 跟對 `x(t)=x(q(t)),y(t)=y(q(t))` 用 chain rule 直接微分的結果一致，這正是「Jacobian 是座標選定後 `dF_q` 的矩陣表示」這句抽象定義，落到具體算式上的驗證。

  代入 Part 5 貫穿例的數值錨點，逐欄用眼睛驗證。這正是「Jacobian column 是只開一顆馬達時末端立刻往哪裡走」這句抽象說法的具體印證。
]

== Singularity：Jacobian 降 rank，SVD 給出連續量化

#equation[$det J=l_1 l_2 sin q_2, quad q_2 in {0,pi} arrow.r.double "rank" J<2$]
#v(.3em)
#equation[$J=U Sigma V^T, quad Sigma="diag"(sigma_1,dots,sigma_r)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.rose,
    title: [二連桿：$det J=0$],
  )[手臂完全伸直或折回時，可達的瞬時速度空間缺少一個 Cartesian direction，對應 Part 5 workspace boundary：$q_2=0,pi$ 恰好是 $r=l_1+l_2$ 或 $r=|l_1-l_2|$ 的邊界。]
][
  #card(
    tint: palette.teal,
    title: [一般情形：SVD],
  )[$u_i$ 是 end-effector velocity space 裡的正交 task directions，$sigma_i$ 是「沿這個方向要花多少關節速度才能達到單位末端速度」的增益，$sigma_i arrow 0$ 連續逼近奇異。]
]

#speaker-note[
  奇異性直接體現在 `detJ` 上。`q₂∈{0,π}` 時 `detJ=0`，rank 掉到 2 以下，手臂完全伸直或完全折回時退化。這對應 Part 5 提到的 workspace boundary：`q₂=0,π` 恰好是能到達範圍的邊界，在邊界上，末端沿著徑向的運動已經耗盡了所有關節自由度所能提供的方向，某個 Cartesian 方向(這裡是沿臂伸展方向)無法由任何有限關節速度產生。

  但 `det J` 只在方陣情形下有意義，一般情形下(任意維度、任意關節數)，要更精細地量化「多接近奇異」，要用 SVD：`J=UΣV^T`，`Σ=diag(σ₁,…,σ_r)`。`u_i` 是末端速度空間裡的一組正交方向(task directions)，`σ_i` 是「沿這個方向要花多少關節速度才能達到單位末端速度」的增益，`σ_i→0` 正是 `det J→0` 這個離散事件的連續版本，讓我們能問「有多接近奇異」而不只是「是不是奇異」。
]

== Manipulability ellipsoid：從 $norm(dot(q))<=1$ 推出橢球

#equation[$dot(q)=V alpha, quad norm(alpha)<=1 quad ("因" V "正交")$]
#v(.2em)
#equation[$x=J dot(q)=J V alpha=U Sigma alpha, quad beta:=Sigma alpha arrow.double alpha=Sigma^(-1)beta$]
#v(.2em)
#equation[$norm(alpha)<=1 arrow.double beta^T Sigma^(-2)beta<=1, quad x=U beta arrow.double beta=U^T x$]
#v(.2em)
#equation[$arrow.double x^T underbrace(U Sigma^(-2)U^T, (J J^T)^(-1)) x<=1$]
#v(.3em)
#equation[$w(q)=sqrt(det(J J^T))=product_i sigma_i$]
#v(.3em)
#callout(
  kind: "info",
  compact: true,
)[$U Sigma^2 U^T=J J^T$ 直接由 SVD 給出，取逆即得橢球矩陣。$w arrow 0$ 表示橢球塌縮成低維。translation 與 rotation 單位不同，混合前必須先選 scaling metric。]

#speaker-note[
  假設關節速度被限制在單位球內，`‖q̇‖≤1`，用 `x=Jq̇` 代入並利用 SVD，可以推出末端速度必須落在一個橢球內。推導方式是把 `q̇` 分解到 `V` 的正交基底上，`q̇=Vα`(`‖α‖≤1` 因為 `V` 正交)，則 `x=JVα=UΣα`，設 `β=Σα`，則 `α=Σ⁻¹β` 且 `‖Σ⁻¹β‖≤1` 正是 `β^TΣ⁻²β≤1`，代回 `x=Uβ` 即 `β=U^Tx`，得到 `x^TUΣ⁻²U^Tx≤1`，而 `UΣ⁻²U^T=(UΣ²U^T)⁻¹=(JJ^T)⁻¹`(因為 `JJ^T=UΣ²U^T`)。這個橢球的體積正比於 `w(q)=√det(JJ^T)=∏σ_i`，叫 manipulability index，`w→0` 表示橢球塌縮成低維，呈現奇異性的連續衰減過程。但要注意，如果 Jacobian 的行同時混著 m 為單位的平移跟 rad 為單位的旋轉，`JJ^T` 這種混合單位量的矩陣做特徵分解沒有明確意義，必須先選定一個 scaling metric，才能公平地比較橢球在不同方向上的伸縮。
]

== 用 finite difference 驗證 Jacobian

#equation[$Delta_i=op("vee")(log(T(q)^(-1)T(q+epsilon e_i)))/epsilon$]
#v(.35em)
#equation[$Delta_i approx J_b(:,i)$]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[先用 $T(q)^(-1)T(q+epsilon e_i)$ 算出相對姿態變化，再用 $log$ 讀進切空間，跟 Part 4 pose error $E_b=T^(-1)T_d$ 是同一手法。$epsilon$ 太大有 truncation error，太小有 floating-point cancellation，要掃過好幾個數量級找誤差曲線的谷底。]

#speaker-note[
  Jacobian 的解析推導可以、也應該用數值方式驗證，而且驗證方式要跟群結構一致，不能直接對 `T` 做普通有限差分。這裡先用 `T(q)⁻¹T(q+εe_i)` 算出一個小的相對姿態變化，再用 `log` 把它讀進切空間，才能跟 `J_b` 的第 `i` 欄比較，這正是 Part 4 pose error 那套 `E_b=T⁻¹T_d` 的手法搬來做數值驗證。`ε` 太大會有 truncation error(有限差分本身只是一階近似)，太小會被浮點數的 cancellation 吃掉精度，實務上要掃過好幾個數量級的 `ε`，找出誤差曲線的谷底，而不是隨手挑一個值就相信結果。
]

= Part 7 · Inverse Kinematics 與最佳化

== IK 是 manifold-valued nonlinear equation

#v(2.35em)
#equation[$F(q)=T_d$]
#v(.4em)
#row(gutter: .7em)[
  #card(tint: palette.teal, title: [existence])[$T_d$ 是否落在 workspace 裡？（想想二連桿 $|l_1-l_2|<=r<=l_1+l_2$）]
][
  #card(tint: palette.iris, title: [uniqueness])[elbow-up / elbow-down 等多組 branch 通常同時存在。]
][
  #card(
    tint: palette.rose,
    title: [conditioning],
  )[越靠近 Part 6 的 singularity，解對目標的微小擾動就越敏感，$1/sigma_i$ 增益的直接後果。]
]

#speaker-note[
  IK 要解的是一個定義在流形上的非線性方程:`F(q)=T_d`。跟解普通非線性方程組不同，這裡要多問三個問題：existence，`T_d` 是否真的落在這台機器人的 workspace 裡。uniqueness，就算有解，elbow-up/elbow-down 這種多重 branch 通常同時存在。conditioning，越靠近 Part 6 定義的 singularity，解對目標姿態的微小擾動就越敏感，這是 `1/σ_i` 這個增益因子的直接後果，Part 6 的 SVD 分析在這裡會正式派上用場。
]

== 二連桿 IK：同一 target，兩組真的算得出的解

#equation[$l_1=l_2=1, quad (x_d,y_d)=(1,1), quad r=sqrt(2)$]
#v(.25em)
#equation[$cos q_2=frac(r^2-l_1^2-l_2^2, 2l_1l_2)=0 arrow.r.double q_2=plus.minus pi/2$]
#v(.35em)
#equation[$q_1="atan2"(y_d,x_d)-"atan2"(l_2 sin q_2,l_1+l_2 cos q_2)$]
#v(.45em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.teal, title: [elbow-down])[$(q_1,q_2)=(0,pi/2)$]
][
  #card(tint: palette.iris, title: [elbow-up])[$(q_1,q_2)=(pi/2,-pi/2)$]
]
#v(.4em)
#callout(
  kind: "tip",
  compact: true,
)[兩組代回 FK 都得到 $(1,1)$。選 branch 是額外的 posture / continuity 決策，不是 FK 方程替你決定。]

#speaker-note[
  用餘弦定理反解 `q₂`，再用兩次 atan2 反解 `q₁`：第一個 atan2 給出目標方向的絕對角，第二個 atan2 給出「肘部到目標」這段連桿相對第一連桿的夾角，兩者相減得到 `q₁`。兩組解代回 forward kinematics 都精確得到 `(1,1)`，選哪一組 branch 是額外的 posture 或軌跡連續性決策，不是 FK 方程本身替你決定的。
]

== Pose residual 應由 group difference 定義

#equation[$r(q)=op("vee")(log(F(q)^(-1)T_d)) in RR^6$]
#v(.3em)
#equation[$min_q 1/2 norm(W^(1/2)r(q))^2$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.iris,
    title: [為何要 log],
  )[殘差不能直接對 $T$ 做減法（$"SE"(3)$ 不是向量空間），必須用 $log$ 讀進切空間，這正是 Part 4 pose error 那條公式，現在被塞進優化問題裡。]
][
  #card(
    tint: palette.teal,
    title: [$W$ 是 task-space metric],
  )[例如 $W=op("diag")(1,1,1,100,100,100)$：平移用公尺、旋轉用弧度，數值尺度天差地遠，$W$ 把「一公尺」與「一弧度」的相對代價明確定義出來，不靠數學自動決定。]
]

#speaker-note[
  要把 `F(q)=T_d` 變成可以用最小平方求解的形式，殘差不能直接對 `T` 做減法(`SE(3)` 不是向量空間)，必須用 `log` 把差異讀進切空間。這正是 Part 4 pose error 那條公式，現在被塞進一個優化問題裡。`W` 不只是數值上的權重，它是 task-space 的度量，一公尺的位置誤差跟一弧度的姿態誤差，哪一個比較「嚴重」，不是數學能自己決定的，必須由任務本身的物理意義定義：舉例來說 `W=diag(1,1,1,100,100,100)` 代表姿態誤差的代價被放大一百倍，適合對末端朝向要求嚴格的任務(例如噴漆、掃描)。
]

== Newton / Gauss Newton：每個係數都從前面工具接出來

#equation[$F(q+Delta q) approx F(q)exp(hat(J)_b (q) Delta q) arrow.double F(q+Delta q)^(-1) approx exp(-hat(J)_b Delta q)F(q)^(-1)$]
#v(.2em)
#equation[$F(q+Delta q)^(-1)T_d approx exp(-hat(J)_b Delta q)underbrace(exp(hat(r)(q)), F(q)^(-1)T_d)$]
#v(.2em)
#equation[$r(q+Delta q)=op("vee")(log(dots)) approx r(q)-J_b(q)Delta q quad ("BCH 一階：" log(exp A exp B) approx A+B)$]
#v(.25em)
#equation[$Delta q=op("arg min")_delta norm(J delta-r)^2$]
#v(.3em)
#callout(
  kind: "info",
  compact: true,
)[負號正是 BCH 裡 $A=-hat(J)_b Delta q$ 這一項直接帶出來的，不是憑經驗猜的方向。解出 tangent step 後更新 $q$，對 revolute joints 再依 $S^1$ 拓撲 wrap 或 enforce limits。]

#speaker-note[
  Gauss Newton 法反覆解一連串局部線性問題，而且這條線性化公式的每個係數、每個符號都能從前面推過的工具接出來，不是套公式。Part 6 定義 body Jacobian 的方式是 `ξ_b=J_b(q)q̇`，積分一小步就是 `F(q+Δq)≈F(q)exp(Ĵ_b(q)Δq)`。取逆、乘上 `T_d`，並用 `r(q)` 的定義 `F(q)⁻¹T_d=exp(r̂(q))` 代入，現在對這個乘積取 `log`。`Δq` 很小，`r(q)` 在 Gauss-Newton 迭代收斂附近也很小，兩者都是一階小量，套用 Part 3 的 BCH 一階近似 `log(expAexpB)≈A+B`(高階項是 commutator，對兩個一階小量而言是二階小量，可以丟棄)，得到 `r(q+Δq)≈r(q)-J_b(q)Δq`。負號正是 BCH 裡 `A=-Ĵ_bΔq` 這一項的正負號直接帶出來的，不是憑經驗猜的方向。取讓這個線性近似的平方範數最小的 `Δq`，解出後要用 Part 2、Part 3 建立的更新規則把它捲回群上更新 `q`，對 revolute joint 還要記得處理 `S¹` 的週期拓撲，對受限關節還要 enforce joint limits，這是 Part 0「線性化，更新，再線性化」節奏的第 N 次重演。
]

== Moore Penrose pseudoinverse

#equation[$J^+=V Sigma^+ U^T, quad Delta q=J^+ r$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.teal, title: [overdetermined])[任務維度比關節數多：給 least-squares residual 最小的解。]
][
  #card(
    tint: palette.iris,
    title: [underdetermined],
  )[關節數比任務維度多：在所有 exact solutions 中選最小 $norm(Delta q)$。]
]

#speaker-note[
  線性最小平方的通解由 Moore Penrose pseudoinverse 給出，用 SVD `J=UΣV^T` 直接構造。當方程是 overdetermined(任務維度比關節數多，比如六維姿態任務但只有三個關節)，`J^+` 給出讓殘差最小的解。當方程是 underdetermined(關節數比任務維度多，比如七軸手臂做六維任務)，`J^+` 在所有能精確滿足 `JΔq=r` 的解裡，選出範數最小的那一個，這兩種情形，`J^+` 的定義是同一套 SVD 構造，只是矩陣的形狀決定了哪一種性質生效。
]

== 為什麼 pseudoinverse 在 singularity 爆炸？

#v(3.35em)
$
  J^+ r=sum_i (u_i^T r)/sigma_i v_i
$
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[$sigma_i arrow 0$ 時，沿困難 task direction 的微小要求會被 $1\/sigma_i$ 放大成巨大 joint velocity，這是局部幾何發出的訊號，跟 solver 的實作正確性無關：這個方向已經沒有足夠敏感的關節自由度。]

#speaker-note[
  奇異性附近的爆炸現象，現在可以用 SVD 精確寫出來。當某個 `σ_i→0`，沿著對應 task 方向 `u_i` 的一點點殘差需求，會被 `1/σ_i` 放大成巨大的關節速度指令。這是局部幾何發出的訊號，跟 solver 的實作正確性無關：這個方向已經沒有足夠敏感的關節自由度可以精確控制它，任何試圖精確控制它的嘗試都會在數值上付出無限代價。
]

== Damped least squares：用 bias 換穩定

#row(widths: (1.25fr, 1fr), gutter: .9em, align: horizon)[
  #image("assets/dls-shrinkage.svg", width: 100%)
][
  #col(gap: .5em)[
    #equation[$Delta q=J^T(J J^T+lambda^2 I)^(-1)r$]
    #equation[$frac(1, sigma_i) arrow frac(sigma_i, sigma_i^2+lambda^2)$]
    #callout(
      kind: "info",
      compact: true,
    )[$sigma_i>>lambda$ 時趨近 $1\/sigma_i$。$sigma_i arrow 0$ 時分子分母同趨 $0\/lambda^2=0$，增益壓成零而非發散。]
  ]
]
#v(.3em)
#claim(
  tint: palette.amber,
)[代價：即使遠離奇異點，$lambda$ 也讓 tracking 產生系統性偏差，因為 $sigma_i\/(sigma_i^2+lambda^2)$ 對所有有限 $sigma_i$ 都嚴格小於 $1\/sigma_i$。]

#speaker-note[
  Damped least squares 用一個 bias 換取穩定，把 normal equation 加上正則項。在 SVD 座標下，這等於把增益 `1/σ_i` 換成 `σ_i/(σ_i²+λ²)`，當 `σ_i≫λ`，這個表達式趨近 `1/σ_i`，行為跟原本的 pseudoinverse 幾乎一樣。當 `σ_i→0`，分子分母同時趨近 `0/λ²=0`，增益被壓成零而不是發散。代價是，即使遠離奇異點，`λ` 也會讓 tracking 產生一個小小的系統性偏差(因為 `σ_i/(σ_i²+λ²)` 對所有有限 `σ_i` 都嚴格小於 `1/σ_i`)。
]

== Adaptive damping：只在需要時付代價

#equation[$lambda=lambda_0 quad (sigma_min>=sigma_0)$]
#v(.2em)
#equation[$lambda=lambda_0(1+k(1-sigma_min/sigma_0)^2) quad (sigma_min<sigma_0)$]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[遠離奇異區域保持基準阻尼、盡量貼近真解。跌破閾值 $sigma_0$ 後阻尼平滑增加，$(1-sigma_min\/sigma_0)^2$ 這個平方項保證轉換是 $C^1$ 光滑的，不產生 command 的不連續。]

#speaker-note[
  這個代價可以透過 adaptive damping 縮小到只在真正需要的地方付出。遠離奇異區域時保持基準阻尼、盡量貼近真解。一旦最小奇異值跌破閾值 `σ₀`，阻尼隨著逼近奇異點平滑增加，避免指令在跨越閾值那一刻突然跳變，`(1-σ_min/σ₀)²` 這個平方項保證了這個轉換是 `C¹` 光滑的，不會產生 command 的不連續。
]

== Null space：保留主要任務的次要自由度

#equation[$dot(q)=J^+ xi+(I-J^+J)z$]
#v(.3em)
#equation[$J(I-J^+J)z=J z-underbrace(J J^+ J, =J)z=J z-J z=0$]
#v(.4em)
#row(gutter: .7em)[
  #card(tint: palette.iris, title: [primary])[$J^+xi$ 追蹤 tool twist。]
][
  #card(
    tint: palette.teal,
    title: [secondary],
  )[$(I-J^+J)z$ 投影到 $J$ 的零空間，不論 $z$ 是什麼都不影響末端 twist。可做 posture、joint-limit avoidance、manipulability。]
]

#speaker-note[
  當任務維度小於關節數(冗餘機構)，Gauss Newton 步驟不會唯一決定 `Δq`，剩下的自由度叫 null space。第一項追蹤末端 twist，第二項是任意向量 `z` 投影到 `J` 的零空間之後的結果，不影響主任務。驗證 `(I-J^+J)` 確實是零空間投影只需要一行代數：`J(I-J^+J)z=Jz-JJ^+Jz`，而 `JJ^+J=J` 是 pseudoinverse 的定義性質之一，所以 `J(I-J^+J)z=Jz-Jz=0`，不管 `z` 是什麼，經過這個投影之後的分量，乘上 `J` 一定得到零。這個自由度可以拿來做次要目標：調整姿勢、遠離 joint limit、最大化 manipulability。
]

== Joint limits 讓 IK 變成 constrained optimization

#equation[$min_(Delta q) 1/2 norm(J Delta q-r)^2+lambda^2/2 norm(Delta q)^2$]
#v(.25em)
#equation[$q_min <= q+Delta q <= q_max$]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[事後對算出來的 $Delta q$ 做 clamp 看起來簡單，但 clamp 後的 $Delta q$ 已經不是這個帶約束問題的解，會破壞 task-space 這一步原本的最佳性。嚴格處理應用 QP、barrier 或 active-set method。]

#speaker-note[
  如果任務還帶硬性的 joint limits，問題就正式變成 constrained optimization。事後對算出來的 `Δq` 做 clamp(硬把超界的分量夾回範圍)看起來簡單，但會破壞 task-space 這一步原本的最佳性，clamp 之後的 `Δq` 已經不是這個帶約束問題的解。嚴格處理需要真正求解這個帶不等式約束的 QP，或者用 barrier function、active-set method 這些考慮約束邊界的方法。
]

= Part 8 · Trajectory、控制與 Week 4 實作

== Path/trajectory 分層，quintic polynomial 給出時間尺度

#equation[$q(s), s in [0,1] quad "vs." quad q(t), t in [0,T]$]
#v(.25em)
#equation[$p(t)=a_0+a_1t+a_2t^2+a_3t^3+a_4t^4+a_5t^5, quad p(0),dot(p)(0),dot.double(p)(0),p(T),dot(p)(T),dot.double(p)(T)$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.iris,
    title: [path vs trajectory],
  )[path $q(s)$ 只描述幾何曲線；trajectory $q(t)$ 加入 time parameterization，才能檢查 velocity / acceleration / jerk。]
][
  #card(
    tint: palette.teal,
    title: [六個 boundary conditions],
  )[六個邊界條件對六個未知係數，恰好構成 $6 times 6$ 線性方程組，有唯一解，自由度數精確匹配約束數量，這就是為什麼是五次多項式。]
]

#speaker-note[
  Path 跟 trajectory 是兩個常被混用卻不同的概念。Path `q(s)`，`s∈[0,1]` 只描述一條幾何曲線，不含「多快走完」的資訊。trajectory `q(t)`，`t∈[0,T]` 加入時間參數化，才能檢查速度、加速度、jerk 是否在物理限制之內，同一條 path 可以用無限多種不同的時間參數化走完，產生完全不同的動態特性。

  要在起點跟終點同時滿足位置、速度、加速度三個邊界條件，最低次數的多項式需要 6 個自由係數。六個邊界條件對六個未知係數，恰好構成一個 `6×6` 的線性方程組(係數矩陣由 `t^k` 跟它的一二階導數在 `t=0,T` 處取值排成)，有唯一解，這就是為什麼是五次多項式，不多不少：自由度數要精確匹配約束數量。week4 homework 的 `smoothstep5` 是其 normalized 特例。
]

== Smoothstep5 的導數結構

#equation[$s(tau)=10tau^3-15tau^4+6tau^5, quad tau=t/T$]
#v(.25em)
#equation[$s'(tau)=30tau^2(1-tau)^2, quad s'(0)=s'(1)=s''(0)=s''(1)=0$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(
    tint: palette.iris,
    title: [中點數值],
  )[$s(0.5)=0.5$、$s'(0.5)=1.875$（歸一化時間裡的峰值速度），由 $s'(tau)=30tau^2(1-tau)^2$ 直接代入。]
][
  #card(
    tint: palette.rose,
    title: [段界拼接陷阱],
  )[「每段起終點都靜止」不等於「整條軌跡在段界全域平順」。jerk（三階導數）在段界是否連續，取決於相鄰 segments 各自的時間尺度跟拼接方式，不會因為每段自己滿足邊界條件就自動獲得。]
]

#speaker-note[
  week4 lab 裡的 `smoothstep5` 是這個一般解的一個 normalized 特例，固定 `T=1`、起終點速度加速度都是零。直接對 `s` 微分：`s'(τ)=30τ²-60τ³+30τ⁴=30τ²(1-τ)²`，可以驗證 `s'(0)=s'(1)=0`，再微分一次可驗證 `s''(0)=s''(1)=0`。代入中點 `τ=0.5`：`s(0.5)=10(0.125)-15(0.0625)+6(0.03125)=0.5`，`s'(0.5)=30(0.25)(0.25)=1.875`，這是歸一化時間尺度下的峰值速度，對稱性直接保證中點正好是速度最大值。

  要注意的是,「每一段的起終點都靜止」不等於「整條軌跡在段與段的接縫處全域最平順」，如果把好幾段 smoothstep5 首尾相接，jerk(三階導數)在段界是否連續，取決於相鄰兩段各自的時間尺度跟拼接方式，不會因為每段自己滿足邊界條件就自動獲得。
]

== 旋轉 interpolation 應沿 geodesic

#equation[$R(t)=R_0 exp(s(t) log(R_0^T R_1))$]
#v(.35em)
#equation[$q(t)="slerp"(q_0,q_1;s(t))$]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[先用 $log(R_0^T R_1)$ 讀出切空間座標，用 $s(t)$ 沿固定方向縮放，再 $exp$ 捲回群上，這正是 Part 0 圓上平均那個陷阱的三維版本。slerp 前要先選 $q_0 dot q_1>=0$ 的代表，才走短弧而不是繞遠路。]

#speaker-note[
  旋轉的插值不能直接對 Euler angle 或旋轉矩陣的元素做線性插值，這正是 Part 0 圓上平均那個陷阱的三維版本。正確做法是沿著群上的測地線(geodesic)插值：先用 `log(R₀^TR₁)` 讀出從 `R₀` 到 `R₁` 這段旋轉在切空間裡的座標，再用時間參數化函數 `s(t)`(可以是剛才的 smoothstep5)沿著這個固定方向縮放，最後用 `exp` 捲回群上，這保證整條路徑始終落在 `SO(3)` 上，而且是「最短」的那條路徑。四元數的 slerp 是同一個想法在雙覆蓋空間 `S³` 上的實現，但要先處理 Part 3 提過的正負號問題：選擇讓 `q₀·q₁≥0` 的那個代表，才能保證插值走的是短弧，而不是繞了雙覆蓋的另一側走遠路。
]

== Lie group integration：更新必須留在群上

#v(.35em)
#equation[$R_(k+1)=R_k+Delta t hat(Omega)R_k arrow.double R_(k+1)^T R_(k+1)=R_k^T R_k+Delta t underbrace((hat(Omega)^T+hat(Omega)), =0)R_k^T R_k+Delta t^2 R_k^T hat(Omega)^T hat(Omega) R_k$]
#v(.25em)
#equation[$= I+ cal(O)(Delta t^2), quad "累積" N=T/Delta t "步" arrow.double cal(O)(T Delta t) "誤差"$]
#v(.25em)
#equation[$T_(k+1)=T_k exp(hat(Delta t xi_(b,k))) quad "（右乘，body twist）"$]
#v(.2em)
#equation[$T_(k+1)=exp(hat(Delta t xi_(s,k)))T_k quad "（左乘，spatial twist）"$]
#v(.3em)
#callout(
  kind: "warn",
  compact: true,
)[樸素 Euler 更新每步破壞正交約束 $cal(O)(Delta t^2)$，需要不斷手動 renormalize。$exp$ 的值域精確是 $"SE"(3)$，每步都精確合法，完全不需事後修正。]

#speaker-note[
  離散時間下更新姿態時，更新公式本身也必須留在群上，不能直接對矩陣元素做 Euler 積分。想像天真地寫 `T_{k+1}=T_k+ΔtṮ_k`，把這個更新套在旋轉部分 `R_{k+1}=R_k+ΔtΩ̂R_k` 上，檢查它還滿不滿足正交約束：展開 `R_{k+1}^TR_{k+1}`，第一項是 `I`。第二項因為 `Ω̂` 反對稱，`Ω̂^T+Ω̂=0`，整項消失。但第三項 `Δt²(⋯)` 不會消失，是一個嚴格正定的量。所以每走一步，正交約束就被破壞 `O(Δt²)` 的量，單步看起來很小，但走 `N=T/Δt` 步之後累積誤差是 `O(NΔt²)=O(TΔt)`，不會隨著步數增加而消失，只會隨著 `Δt` 變小而變小，這代表樸素 Euler 積分需要不斷手動 renormalize 才能維持 `R` 合法。相對地，`T_{k+1}=T_kexp(Δtξ̂)` 這種更新，因為 `exp` 的值域精確是 `SE(3)`，每一步都精確合法，完全不需要事後修正，這正是為什麼 Lie group 積分要用指數映射當作 retraction，而不是普通的向量加法。右乘對應 body twist,左乘對應 spatial twist,這個配對規則直接繼承自 Part 4 pose error 那條「body error 配右乘、spatial error 配左乘」的紀律。
]

== Closed-loop geometric control：從公式到 code

#v(1.35em)
#equation[$e_k=op("vee")(log(T_k^(-1)T_d)), quad xi_b=K e_k, quad T_(k+1)=T_k exp(hat(Delta t xi_b))$]
#v(.35em)
```cpp
const SE3 body_T_goal = world_T_body.inverse() * world_T_goal;
const Vector6 error = body_T_goal.log();       // [upsilon, omega]
const Vector6 command = K * error;
world_T_body *= SE3::exp(command * dt);         // body-frame update
```
#v(.3em)
#callout(
  kind: "info",
  compact: true,
)[跟 Part 2 的 $e=op("vee")(log(R^T R_d)), omega=k e, R_(k+1)=R_k exp(hat(Delta t omega))$ 一字不改地對應，只是維度從一升到六。四行程式碼逐行對應：$E_b=T^(-1)T_d$、$op("vee")(log E_b)$、比例增益、右乘更新，error/command/update 全部鎖定在同一 frame（body），由幾何一致性決定，不是風格偏好。]

#speaker-note[
  把 Part 2 那個複數上的最小控制器,原封不動搬到 `SE(3)` 上。在 `log` 的 injectivity 鄰域內(也就是誤差不要大到繞過 branch cut)，這正是把 Euclidean 比例控制器搬到 Lie group 上最自然的寫法，error 是切空間裡的向量，乘上增益矩陣 `K`，再用 `exp` 捲回群上更新，跟 Part 2 的公式一字不改地對應，只是維度從一維(`SO(2)` 只有一個自由度)升到六維。

  Week 4 basic lab 的四行程式碼，現在每一行都能對上一個明確的數學物件：第一行是 Part 4 的 `E_b=T⁻¹T_d`，第二行是 `vee(logE_b)`，讀進 body-frame 切空間，第三行是比例增益，第四行是右乘更新，對應 body twist。這四行由幾何一致性決定：error、command、update 全部鎖定在同一 frame(body)。
]

== Advanced lab：geometric Jacobian 對上 spatial error

#v(1.35em)
#equation[$J_i=mat(z_i times(p_e-p_i); z_i), quad xi_s=J_s dot(q), quad dot(q)=J^T(J J^T+lambda^2 I)^(-1)xi_s$]
#v(.35em)

```cpp
const Vector6 world_error = poe_jacobian_spatial(q).transpose()
    * (poe_jacobian_spatial(q) * poe_jacobian_spatial(q).transpose()
       + lambda * lambda * Matrix6::Identity()).inverse() * xi_s;
q += world_error * dt;                          // spatial-frame update
```
#v(.3em)
#callout(
  kind: "warn",
  compact: true,
)[若 translation error 用 world frame、rotation error 也用 spatial convention，才能直接與 spatial geometric Jacobian 配對，跟 basic lab 的 body 版本剛好對稱，再次印證 Part 4、Part 6 反覆強調的配對紀律不是風格偏好。]

#speaker-note[
  Advanced lab 換成 geometric Jacobian 對上 spatial error。這裡的紀律反過來：如果 translation error 是用 world frame 算的、rotation error 也用 spatial convention，就必須配 `J_s`(spatial geometric Jacobian)才能讓 Jacobian 的每一列跟 error 的每一列代表同一個物理量，跟 basic lab 的 body 版本剛好對稱，DLS 阻尼項 `λ²I` 直接對應 Part 7 的 damped least squares。
]

== Sophus / Eigen 實作的數值契約

#v(1.35em)
#row(gutter: .7em)[
  #card(
    tint: palette.teal,
    title: [ordering],
  )[Sophus `SE3::Tangent` 是 `[upsilon, omega]`，順序反了整個 Jacobian 都會錯位。]
][
  #card(
    tint: palette.iris,
    title: [units],
  )[translation 是 m，rotation 是 rad。直接塞進同一個增益或 tolerance 會讓數值不對稱的物理量被同等對待。]
][
  #card(
    tint: palette.amber,
    title: [normalization],
  )[Quaternion / rotation matrix 輸入必須合法。不合法不會馬上讓程式當掉，卻會讓後面每一步悄悄偏離。]
]

#speaker-note[
  實作上還有一組容易被忽略、卻決定程式能不能編譯過、能不能收斂的數值契約：順序反了整個 Jacobian 都會錯位。translation 的單位是公尺、rotation 是弧度,直接把兩者塞進同一個增益或同一個 tolerance 會讓數值上完全不對稱的物理量被同等對待。quaternion 或 rotation matrix 輸入必須先驗證合法(單位模長、正交)，不合法的輸入不會馬上讓程式當掉，卻會讓後面每一步計算悄悄偏離正確答案。
]

== Debugging：用不變量定位錯誤

#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.rose, title: [幾何檢查])[
    #set text(size: .75em)
    $R^T R-I$、$det R-1$、frame-chain 下標、$log(T^(-1)T_d)$ 的 frame。
  ]
][
  #card(tint: palette.teal, title: [數值檢查])[
    #set text(size: .75em)
    $sigma_min(J)$、condition number、step norm、joint-limit margin、finite-difference Jacobian error。
  ]
]
#v(.4em)
#quote-card(
  tint: palette.amber,
)[畫面不會告訴你錯在哪一層。不變量各自對應課程裡推導過的某一段數學，一旦異常就直接指向是哪一層出了問題。]

#speaker-note[
  最後，除錯的方法論本身值得單獨說一次：動畫顯示的是「結果怪」，但它不會告訴你錯在哪一層。真正有效的除錯要靠不變量。幾何層的檢查：是否接近零，frame-chain 的下標是否首尾銜接，`log(T⁻¹T_d)` 用的是否預期的那個 frame。數值層的檢查：`σ_min(J)` 有多小、condition number 多大、每步 update 的 step norm 是否異常放大、joint-limit margin 還剩多少、finite-difference 算出來的 Jacobian 誤差落在哪個數量級。這些不變量各自對應課程裡推導過的某一段數學，一旦某個不變量異常，就直接指向是哪一層(群約束?奇異性?frame 配對?)出了問題，而不必用肉眼在動畫裡「猜」。
]

== 一張圖收回整門課

#equation[$underbrace(q in cal(Q))_"configuration" arrow^(F) underbrace(T in "SE"(3))_"pose" arrow^(log) underbrace(xi in RR^6)_"local coordinates"$]
#v(.3em)
#equation[$dot(q) arrow^(J(q)) xi, quad xi arrow^(J^+ or "DLS") dot(q)$]
#v(.45em)
#callout(
  kind: "info",
  compact: true,
)[群負責有限運動的精確組合與逆元（Part 1-4），algebra 負責局部線性化（Part 0 的複數第一次示範），Jacobian 接起 configuration 與 task tangent spaces（Part 6），optimizer 在兩者間反覆往返：線性化、求解、捲回群上、再線性化（Part 7、8）。]

#speaker-note[
  回頭看整堂課，一張圖就能收回所有內容：群負責有限運動的精確組合與逆元(Part 1-4 的核心)，algebra 負責局部線性化，讓我們能做微分、做優化(Part 0 的複數例子第一次示範這件事)，Jacobian 把 configuration space 跟 task space 的切空間接起來(Part 6)，optimizer 在兩者之間反覆往返，線性化、求解、捲回群上、再線性化(Part 7、Part 8)。這正是 Part 0 最早提出的「線性化，更新，再線性化」節奏，從一個高中複數例子開始，最後長成了完整的機器人運動學與控制框架。
]

== References

- Lynch & Park, *Modern Robotics: Mechanics, Planning, and Control*, Cambridge University Press.
- Murray, Li & Sastry, *A Mathematical Introduction to Robotic Manipulation*.
- Barfoot, *State Estimation for Robotics*, 2nd ed.
- Sola, Deray & Atchuthan, *A Micro Lie Theory for State Estimation in Robotics*.
- Bullo & Lewis, *Geometric Control of Mechanical Systems*.
- Siciliano et al., *Robotics: Modelling, Planning and Control*.
- Chirikjian, *Stochastic Models, Information Theory, and Lie Groups*.

#ending-slide(title: [Q & A])
