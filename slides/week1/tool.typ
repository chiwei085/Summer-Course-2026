#import "@local/summer-course:0.1.0": *

#show: course-theme.with(
  config-info(
    title: [Engineering Toolbox],
    subtitle: [Week 1 · 信任、一致性與可重現性],
    author: [獵奇緯],
    institution: [Summer Course],
    short-title: [Week 1 · Engineering Toolbox],
  ),
)

#title-slide()
#outline-slide()

= 課程地圖

== 四套工具，其實是一個問題

#quote-card(tint: palette.iris)[當開發不再是一個人在一台機器上寫程式，\
  要靠什麼機制維持信任、一致性和可重現性？]

#v(0.8em)
#row(gutter: .7em)[
  #card(tint: palette.iris, title: [SSH], icon: [🔐])[信任遠端機器]
][
  #card(tint: palette.teal, title: [Git], icon: [🌿])[信任修改歷史]
][
  #card(tint: palette.amber, title: [HTTP / curl], icon: [🩺])[定位服務故障]
][
  #card(tint: palette.rose, title: [Docker], icon: [📦])[重現執行環境]
]
#v(.5em)
#callout(kind: "tip", compact: true)[不照 lab 劇本走，每節結尾提對應 lab，操作留到 lab 時間。]

#speaker-note[
  week0 打的是地基：Linux 這台機器本身怎麼運作。week1 要往上一層——講*工程師每天賴以維生的四套基礎設施*：怎麼安全地連到別人的機器（SSH）、怎麼安全地跟別人共同修改同一份程式碼（Git）、怎麼檢查網路服務真的通不通（HTTP / curl）、怎麼把「我的機器上跑得動」變成「任何機器上都跑得動」（Docker）。這四套東西表面上互不相干，實際上是同一個問題的四個切面：*當開發不再是一個人在一台機器上寫程式，要靠什麼機制維持信任、一致性和可重現性*。

  先把扎實的理論和實務講完整，不會照著 lab 的劇本走，也不會被 lab 綁住只講 lab 用得到的指令。每個小節的結尾會提一下對應的 lab，讓大家知道理論在哪裡有動手練習的位置，但操作本身留到 lab 時間。
]

== 完成這週，你應該能夠

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [建立信任], icon: [🔑])[
    #set text(size: 0.85em)
    - 公開金鑰驗證、host key 與 identity key
    - `ProxyJump` / bastion 架構
    - Git 物件模型、branch、merge / rebase / conflict
    - GitHub 如何把 repo 變成協作介面
  ]
][
  #card(tint: palette.teal, title: [診斷與交付], icon: [🛠])[
    #set text(size: 0.85em)
    - 用 `curl`、DNS、TLS 分層定位服務故障
    - container 與 VM 的本質差異
    - 寫出安全、可重現的 Dockerfile 與 `compose.yaml`
    - 審查 AI 生成部署設定是否安全、可重現、可信
  ]
]

#speaker-note[
  學生完成本週課程後應該能夠：

  - 解釋公開金鑰驗證的原理，分辨 host key 與 identity key 的角色，看懂 `known_hosts`、`ssh-agent`、`~/.ssh/config` 在做什麼
  - 使用 `ProxyJump`／bastion 架構連進多層網路，理解為什麼這是比裸密碼更安全的預設姿態
  - 解釋 Git 的物件模型（blob / tree / commit）與分支的本質，看懂 merge、rebase、fast-forward、conflict 各自在做什麼、什麼時候用哪一種
  - 解釋 GitHub 如何用 remote、SSH 金鑰、Pull Request、code review 把「個人 repo」變成「團隊協作介面」
  - 使用 `curl`、DNS 查詢與基本 TLS 診斷工具，判斷一個網路服務卡在名稱解析、連線、憑證、HTTP 狀態碼或應用層回應
  - 解釋 container 與虛擬機器的本質差異（namespace／cgroup vs hypervisor），理解 image layer、build cache、multi-stage build
  - 寫出具備非 root 使用者、資源限制、healthcheck、網路隔離的 Dockerfile 與 `compose.yaml`
  - 具備在 AI 大量產出程式碼的環境下，判斷「這段自動生成的部署設定安全嗎、可重現嗎、可信嗎」的基本審查能力
]

= SSH：跟一台不在你面前的機器建立信任

== 為什麼會有 SSH

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #card(tint: palette.rose, title: [1995 之前], icon: [📡])[
    telnet / rlogin / rsh\
    帳密與內容都是明文\
    同網段側錄工具就能看光密碼
  ]
][
  #card(tint: palette.iris, title: [Tatu Ylönen, 1995], icon: [🔐])[
    帳號被竊聽入侵後\
    寫出第一版 SSH\
    兩個承諾：加密整條連線 + 確認對方是誰
  ]
]
#v(.6em)
#align(center)[
  #pill(tint: palette.rose)[你] #text(size: 1.2em)[→] #pill(tint: palette.night)[看起來正常的加密連線] #text(
    size: 1.2em,
  )[→] #pill(tint: palette.amber)[其實是中間人架的假伺服器] #text(size: 1.2em)[→] #pill(tint: palette.iris)[真伺服器]
]
#v(.4em)
#callout(kind: "danger", compact: true)[只做到加密不夠：你可能在跟中間人「安全地」聊天，完全感覺不到差異。]

#speaker-note[
  先把時間倒回 1990 年代中期。當時遠端登入的標準工具是 `telnet`、`rlogin`、`rsh`——這些協定的共同點是*帳號密碼和所有傳輸內容都是明文*，在同一個網段上隨便一個封包截聽工具就能把密碼看得一清二楚。1995 年，芬蘭赫爾辛基理工大學的研究員 Tatu Ylönen 因為系統管理員帳號被這種方式竊聽入侵，寫出了第一版 SSH（Secure Shell）。它解決的問題很直白：*把整條連線加密，並且讓使用者能確認自己連到的真的是想連的那台機器，不是中間人假冒的*。這兩件事——加密與身份驗證——缺一不可，只做到前者不夠：如果連線是加密的，但你根本不知道對方是誰，中間人一樣可以架一台假伺服器，跟你正常交換金鑰、正常加密，然後把你的密碼原封不動轉送到真正的伺服器上，你完全感覺不到差異。這就是 man-in-the-middle attack，SSH 存在的意義有一半就是防這個。
]

== 私鑰簽名，公鑰驗證

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [Private key], icon: [🗝])[留在自己的機器\
    用來簽名 challenge\
    絕不透過網路傳送]
][
  #card(tint: palette.teal, title: [Public key], icon: [📢])[交給伺服器\
    用來驗證簽名\
    沒有機密性可言、無法反推私鑰]
]
#v(.7em)
#align(center)[伺服器 challenge #text(size: 1.2em)[→] 私鑰 sign #text(size: 1.2em)[→] 公鑰 verify]
#v(.4em)
#callout(kind: "tip", compact: true)[密碼每次登入都要「交出去」，金鑰簽名時私鑰從頭到尾沒離開過你的機器。]

#speaker-note[
  要防中間人，得先搞懂 SSH 用的密碼學形狀跟我們直覺想的不一樣。日常想到「密碼」，想到的是對稱式加密：一把鑰匙，鎖也是它、開也是它，雙方得先用某種方式偷偷交換這把鑰匙——但「怎麼在不安全的網路上安全地交換這把鑰匙」本身就是雞生蛋的問題。

  非對稱式加密（public-key cryptography）換了個做法：產生一組*數學上繫結、但功能不對等*的兩把鑰匙。私鑰（private key）留在自己手上，永遠不離開自己的機器；公鑰（public key）可以隨便給任何人、貼在任何地方，沒有機密性可言。它的核心性質是：*用公鑰加密的東西只有對應私鑰能解開；用私鑰簽名的東西，任何人拿公鑰都能驗證這確實是私鑰持有者簽的，但驗證的人沒辦法反過來偽造出同樣的簽名*。SSH 的身份驗證用的是簽名這條路：伺服器丟一段挑戰資料過來，客戶端用私鑰簽名回去，伺服器用早就登記好的公鑰驗證簽名——*全程私鑰本身從來沒有離開過你的機器，也沒有在網路上傳輸過*。這跟密碼登入是本質不同的安全等級：密碼這種東西，你每次登入都要把它交出去（不管有沒有加密包裹），代表它有無限次被攔截、被伺服器端記錄、被伺服器端洩漏的機會；金鑰簽名這種東西，私鑰永遠不出門，被攻破的唯一途徑是有人直接偷到你機器上那個私鑰檔案。
]

== 產生一組金鑰

#code(title: "terminal")[
  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/lab
  ```
]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [-t ed25519])[比 rsa 短、快\
    抗側通道攻擊設計更嚴謹]
][
  #card(tint: palette.teal, title: [passphrase])[私鑰檔案本身的密碼\
    第二層防線]
][
  #card(tint: palette.amber, title: [兩個檔案])[`lab` 私鑰，權限必須 `600`\
    `lab.pub` 公鑰，可放心公開]
]

#speaker-note[
  實務上產生一組金鑰：

  ```bash
  ssh-keygen -t ed25519 -f ~/.ssh/lab
  ```

  `-t ed25519` 指定演算法——這是目前建議的預設,比老式的 `rsa` 金鑰短、快、且抗某些側通道攻擊設計得更嚴謹；老教學常看到 `rsa` 是歷史包袱,新環境沒有相容性顧慮就直接用 ed25519。指令會問要不要加 passphrase——這是私鑰檔案本身的密碼,是*第二層防線*:就算私鑰檔案被偷走(筆電被順手牽羊、備份外流),沒有 passphrase 也解不開來用。個人開發機建議一定要加,這是用一點點打字的麻煩換一次真正的資安事故。

  生出來兩個檔案:`lab`(私鑰,權限一定要是 `600`,SSH 客戶端看到權限太寬鬆會直接拒絕使用)和 `lab.pub`(公鑰,可以放心地貼給任何人、任何伺服器)。
]

== 雙向信任：Host key 先上場

#row(widths: (1fr, .2fr, 1fr), align: horizon, gutter: .8em)[
  #card(tint: palette.amber, title: [Host key])[server → you]
][#align(center)[#text(size: 1.4em)[⇄]]][
  #card(tint: palette.teal, title: [Identity key])[you → server]
]
#v(.5em)
#code(title: "terminal")[
  ```text
  $ ssh -p 2222 field@127.0.0.1
  The authenticity of host '[127.0.0.1]:2222' can't be established.
  ED25519 key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
  Are you sure you want to continue connecting (yes/no/[fingerprint])?
  ```
]
#v(.4em)
#callout(kind: "warn", compact: true)[這一步在問：「這個 fingerprint 摸起來陌不陌生？」]

#speaker-note[
  這裡是最多人搞混的地方——SSH 的信任其實是*雙向*的,有兩組完全不同的金鑰在起作用,方向相反。

  *Host key* 是伺服器證明「我是我」用的。伺服器第一次啟動時會生成自己的 host key pair,私鑰留在伺服器上,永遠不會給任何人。你第一次連上一台新機器時:

  ```bash
  ssh -p 2222 field@127.0.0.1
  ```

  SSH 會印出一段像這樣的東西:

  ```text
  The authenticity of host '[127.0.0.1]:2222' can't be established.
  ED25519 key fingerprint is SHA256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.
  Are you sure you want to continue connecting (yes/no/[fingerprint])?
  ```

  這一步在問的是:「我從來沒見過這台機器,這個 fingerprint 摸起來陌不陌生?」這是SSH 整個信任模型裡*唯一沒有密碼學保證的一環*,業界叫它 Trust On First Use(TOFU)
]

== TOFU：known_hosts 記住了什麼

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [第一次], icon: [👀])[透過另一個 channel\
    （wiki、口頭、公司通訊軟體）\
    比對 fingerprint，不要無腦按 yes]
][
  #card(tint: palette.iris, title: [之後每次], icon: [📒])[記進 `known_hosts`\
    比對，fingerprint 變了\
    SSH 會嚇人地拒絕連線]
]
#v(.6em)
#callout(kind: "danger", compact: true)[fingerprint 改變不是 bug，先查原因，不要刪掉那行 known_hosts 草草了事。]

#speaker-note[
  ——如果第一次連線時中間人已經架好了,你會認下一把假的host key,從此每次連線都被無聲無息地轉發給攻擊者。所以正規做法是*帳號發放方要透過別的channel(內部 wiki、口頭、公司通訊軟體)先公佈正確的 fingerprint,連線前比對*,而不是看到提示就無腦按 yes——這正是 lab 裡「Mission Control 印出可信 fingerprint、連線前先比對」這個設計要練的直覺。按下 yes 之後,這把 host key 會被記進 `~/.ssh/known_hosts`,下次再連同一台機器,SSH 會拿記錄直接比對,*如果 fingerprint 變了,SSH 會用非常嚇人的警告拒絕連線*——這不是bug,這正是host key 機制在盡忠職守,通常代表機器重灌過、或者有人在搞中間人攻擊,該做的是先查清楚原因,而不是刪掉 known_hosts 裡那一行草草了事。
]

== Identity key：你證明「我是我」

#code(title: "terminal")[
  ```bash
  ssh-copy-id -i ~/.ssh/lab.pub -p 2222 field@127.0.0.1
  ```
]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.teal, title: [做的事])[用密碼登入一次\
    公鑰追加進遠端 `authorized_keys`]
][
  #card(tint: palette.amber, title: [權限地雷])[`authorized_keys` / `.ssh` 權限太寬\
    SSH 一樣直接拒絕使用]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[一次連線，兩次驗證：host key 證明「我是你要連的機器」+ identity key 證明「我是被允許登入的人」，任一邊被冒充，信任鏈就破了。]

#speaker-note[
  *Identity key*(也就是我們剛才產生的那把)方向相反,是*你*證明「我是我」用的。公鑰要預先交給伺服器,讓它記在你要登入的帳號底下的 `~/.ssh/authorized_keys` 裡。手動做是 `cat` 追加內容,但正規工具是:

  ```bash
  ssh-copy-id -i ~/.ssh/lab.pub -p 2222 field@127.0.0.1
  ```

  這支工具做的事很單純:用你現有的驗證方式(通常是密碼,這是這把新鑰匙生效前最後一次用密碼)登入一次,把公鑰內容追加進遠端的 `authorized_keys`,順便處理好檔案權限——*`authorized_keys` 和它所在的 `.ssh` 目錄權限開太寬,SSH 伺服器同樣會直接拒絕使用它*,這是新手最常撞到的「明明設定對了卻登不進去」的原因。

  把兩組鑰匙放在一起看,SSH 的一次連線其實是兩次獨立的身份驗證疊在一起:先是伺服器拿 host key 證明「我是你要連的那台機器」,再來是你拿 identity key 證明「我是被這台機器允許登入的人」。兩邊有任何一邊被冒充,整個信任鏈就破了,這也是為什麼 SSH 的安全性教學永遠要同時講這兩把鑰匙,單講一邊只講了一半的故事。
]

== ssh-agent：解鎖一次，委託簽名

#code(title: "terminal")[
  ```bash
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/lab
  ```
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [ssh-agent])[常駐小程式，解鎖一次私鑰進記憶體\
    同 session 後續連線直接向它借用]
][
  #card(tint: palette.rose, title: [agent forwarding `-A`])[傳出去的是「簽名能力」的委託\
    跳板被入侵，攻擊者可冒充你連下一台]
]
#v(.4em)
#callout(kind: "danger", compact: true)[不是私鑰外洩，但效果幾乎一樣，沒有明確需求就不要開 forwarding。]

#speaker-note[
  加了 passphrase 之後,照理每次用這把私鑰都要重打一次密碼,這在一天要連好幾次的場景下很煩人。`ssh-agent` 是常駐在你自己機器上的一個小程式,解鎖一次私鑰、放進它的記憶體裡,之後同一個 session 內的每次 SSH 連線都直接問 agent 借用,不用重打 passphrase:

  ```bash
  eval "$(ssh-agent -s)"
  ssh-add ~/.ssh/lab
  ```

  要澄清一個常見的誤會:agent 轉發私鑰的*用法*不是把私鑰檔案傳出去——私鑰物理上仍然只活在你機器的 agent 記憶體裡,傳出去的是「用私鑰簽名」這個能力的委託(agent forwarding,`-A` 引數)。這個功能在多跳連線時很方便,但也是有名的資安地雷:如果跳板機器被入侵,攻擊者能在你還連著的當下,借用你 agent 裡的簽名能力冒充你連到下一台機器——這不是私鑰外洩,但效果幾乎一樣。沒有明確需求就不要開 agent forwarding。
]

== ~/.ssh/config 與 ProxyJump：別名與唯一入口

#code(title: "~/.ssh/config")[
  ```sshconfig
  Host field-gateway
      HostName 127.0.0.1
      Port 2222
      User field
      IdentityFile ~/.ssh/lab
  Host robot-01
      HostName robot-01
      User operator
      ProxyJump field-gateway
  ```
]
#v(.4em)
#align(center)[
  #pill[你] #text(size: 1.2em)[→] #pill(tint: palette.amber)[field-gateway（加固、監控、日誌齊全）] #text(
    size: 1.2em,
  )[→] #pill(tint: palette.iris)[robot-01（完全不對外開放）]
]
#v(.3em)
#align(center)[終端機上只打一行 `ssh robot-01`，底層走的是兩段獨立、各自驗證身份的 SSH 連線。]

#speaker-note[
  裸接指令一多,`ssh -p 2222 -i ~/.ssh/lab field@127.0.0.1` 這種指令會變得難打又難記。`~/.ssh/config` 讓我們把這些細節存成別名:

  ```sshconfig
  Host field-gateway
      HostName 127.0.0.1
      Port 2222
      User field
      IdentityFile ~/.ssh/lab

  Host robot-01
      HostName robot-01
      User operator
      ProxyJump field-gateway
  ```

  寫完之後 `ssh field-gateway` 就等同剛才那串完整指令。這裡真正有意思的是第二個 host 的 `ProxyJump`——這就是*bastion / jump host* 架構,業界最標準的網路分層防線:內部機器(這裡是 `robot-01`)完全不對外開放,唯一的入口是那台被加固、被監控、日誌齊全的閘道機(`field-gateway`)。`ProxyJump` 告訴 SSH 客戶端:「先用一般方式連到 `field-gateway`,再從那台機器內部,把連線像水管一樣接到 `robot-01`」——*這一切在你的終端機上只是打一行 `ssh robot-01`,但底層走的是兩段獨立、各自驗證身份的 SSH 連線*,中間那段不會經過你的機器明文暴露。這在機器人開發和雲端環境裡是標準姿態:內網的機器人、內部的資料庫、正式環境的伺服器,幾乎都不該直接對外網開一個埠等人猜密碼,該開的洞只有一個閘道。
]

== 重用同一條隧道：檔案傳輸與埠轉發

#code(title: "terminal")[
  ```bash
  scp -P 2222 report.txt field@127.0.0.1:/home/field/
  rsync -avz -e "ssh -p 2222" ./deployment/ field@127.0.0.1:/opt/robot/config/
  ssh -L 8080:localhost:80 field-gateway
  ```
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [scp / rsync])[已有被信任的管道，就不再開新的門\
    `rsync` 增量比對，部署腳本首選]
][
  #card(tint: palette.iris, title: [port forwarding `-L`])[服務只監聽 `127.0.0.1`\
    「誰能碰到它」的責任交給 SSH 這層]
]

#speaker-note[
  SSH 除了開一個 shell,還能拿同一條已驗證、已加密的連線做別的事。最直覺的是檔案傳輸:

  ```bash
  scp -P 2222 report.txt field@127.0.0.1:/home/field/
  rsync -avz -e "ssh -p 2222" ./deployment/ field@127.0.0.1:/opt/robot/config/
  ```

  `scp` 簡單直接;`rsync` 多做了一層增量比對,只傳有變動的部分,大量檔案或反覆同步時效率差很多,這也是為什麼正式的部署指令碼幾乎都選 `rsync` 而不是 `scp`。兩者都是把 SSH 已經建立好的加密隧道直接拿來用,不需要另外架 FTP 或額外的傳輸服務——*這正是「已經有一條被信任的管道,就不要再開新的門」*這個安全原則的具體實踐。

  埠轉發是另一個方向的延伸:`ssh -L 8080:localhost:80 field-gateway` 能把遠端機器上只監聽 `127.0.0.1` 的私有服務,透過 SSH 隧道對映到自己本機的埠上——不用把那個服務真的暴露到網路上,就能在自己瀏覽器開啟它。這跟 lab 裡「機器人的診斷服務只監聽在 `127.0.0.1:8080`,只有先跳進內部才碰得到」是同一個道理:*服務本身可以對網路一無所知地保持封閉,把「誰能碰到它」的責任完全交給 SSH 這一層*。
]

= Git：管理修改歷史，而不是管理檔案

== Git 管理的不是檔案，是「有意圖的歷史」

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [直覺以為])[更潮的 Ctrl+Z\
    自動備份資料夾]
][
  #card(tint: palette.iris, title: [實際上是])[有意圖、有作者、有時間\
    彼此有因果關係的修改歷史]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[2005，BitKeeper 授權糾紛，Linus 十天寫出雛形——痛點來自管理上萬貢獻者同時修改同一批檔案。]
#v(.4em)
#align(center)[#pill(tint: palette.iris)[分散式] #pill(tint: palette.teal)[分支零成本] #pill(
    tint: palette.amber,
  )[密碼學完整性] #pill(tint: palette.rose)[大規模效能]]

#speaker-note[
  沒碰過版本控制的人,直覺會把 Git 想成「更潮的 Ctrl+Z」或「自動備份」。這個直覺會一路把人帶偏,因為 Git 真正在管理的東西是*一串有意圖、有作者、有時間、彼此有因果關係的修改歷史*,而且假設*會有很多人同時在修改同一批檔案*。

  時間拉回 2005 年,Linux kernel 社群原本用一套叫 BitKeeper 的商業版本控制系統,因為授權糾紛被收回使用權。Linus Torvalds 用大概十天寫出了 Git 的雛形。他對「管理幾千人同時貢獻的巨大專案」這件事的痛點比任何人都清楚。Git 的設計目標直接對應這些痛點:*分散式*(每個人的本機都有完整歷史,不必時時連到中央伺服器)、*分支要幾乎零成本*(不然沒人敢亂開分支實驗)、*完整性有密碼學保證*(歷史不能被悄悄篡改)、*效能要能扛住上萬個貢獻者的規模*。
]

== 內容定址的物件資料庫：四種物件

#row(gutter: .65em)[
  #card(tint: palette.teal, title: [blob])[檔案內容\
    不含檔名]
][
  #card(tint: palette.amber, title: [tree])[目錄\
    檔名 → blob / tree]
][
  #card(tint: palette.iris, title: [commit])[完整快照\
    tree + parent + metadata]
][
  #card(tint: palette.rose, title: [tag])[commit 的\
    人類名稱]
]
#v(.5em)
#callout(kind: "info", compact: true)[理解物件模型後，之後所有指令的行為都能直接推導出來，不用死背。]
#v(.4em)
#callout(
  kind: "tip",
  compact: true,
)[每個物件用內容雜湊當 ID：改一個 bit 就是全新物件。commit 是「一串快照」而非「一串差異」，未變的 blob 被原樣重用。]

#speaker-note[
  理解 Git 最值得的投資,是搞懂它的物件模型——之後所有指令的行為都能從這個模型直接推匯出來,不用死背。

  Git 倉庫本質上是一個內容定址(content-addressed)的物件資料庫,存放在 `.git` 目錄裡,只有四種物件:

  - *blob*:一份檔案的內容本身(不含檔名、不含權限,純內容)
  - *tree*:一層目錄結構,記錄一堆「檔名 → blob 或子 tree」的對應
  - *commit*:一個快照的元資訊——指向一個 tree(那一刻整個專案的樣子)、指向零到多個 parent commit、加上作者、時間、說明文字
  - *tag*:給某個 commit 掛一個人類看得懂的名字,通常用在版本釋出

  每個物件都用它*內容的 SHA-1(新版本逐步換成 SHA-256)雜湊值*當作自己的 ID——這一點解釋了很多行為。*改動內容只要差一個位元,雜湊值就完全不同,等於產生一個全新的物件*,舊物件原封不動留在那裡。這就是為什麼 Git 常被形容成「一串快照,而不是一串差異」:每個 commit 指向的 tree 是*當時整個專案的完整狀態*,不是相對上一版的 diff——只是因為多數檔案沒變,底層的 blob 會被原樣重用,儲存空間才沒有爆炸。這個模型也帶來一個副產品:*雜湊值本身就是內容的數位指紋*,只要 SHA 相同,內容保證相同,歷史要被篡改就必須讓每一個受影響的物件雜湊全部對得上,這在實務上等於不可能——這是「Git 歷史很難被悄悄改掉」這句話的真正數學基礎。
]

== 分支是會移動的指標，歷史是一個 DAG

#align(center)[
  #text(size: 1.35em)[`.git/refs/heads/main` = 一個 commit SHA]
  #v(.6em)
  #text(size: 1.5em, fill: palette.iris, weight: "bold")[HEAD → main → commit]
  #v(.7em)
  #pill[timeline] #h(.5em) #pill(tint: palette.teal)[DAG] #h(.5em) #pill(tint: palette.amber)[merge = two parents]
]
#v(.5em)
#callout(kind: "info", compact: true)[開分支瞬間完成，只是多寫一個指標；`git log --graph` 的分岔線畫的就是這個圖本身。]

#speaker-note[
  分支呢?一個分支——比如 `main`——說穿了只是 `.git/refs/heads/main` 裡的一個文字檔案,內容是一個 commit 的 SHA。*分支不是一份檔案的複製,只是一個會移動的指標*。這就是為什麼 Git 開分支是瞬間完成的操作,不管專案多大——`git branch feature/safety-limit` 只是多寫一個指向同一個 commit 的指標而已。`HEAD` 又是再包一層的指標,通常指向「目前所在分支」這個指標,所以正常狀態下移動一步、`HEAD` 跟著分支一起移動;而 `detached HEAD`——直接指向某個 commit 而不經過分支名——就是這層間接被拆開的狀態。

  把這幾件事疊起來看,Git 的歷史本質上是一個*有向無環圖(DAG)*:每個 commit 指向自己的 parent(合併出來的 commit 會有兩個 parent),分支只是這個圖上的書籤。`git log --graph` 畫出來的那些分岔線,畫的就是這個圖本身,不是什麼隱喻。
]

== 三棵樹：working directory / index / HEAD

#v(1em)
#row(widths: (1fr, auto, 1fr, auto, 1fr), align: horizon, gutter: .5em)[
  #card(tint: palette.rose, title: [working directory])[你正在編輯的檔案]
][
  #align(center)[`git add`\ #text(size: 1.4em)[→]]
][
  #card(tint: palette.amber, title: [index / staging])[下一次 commit 的內容]
][
  #align(center)[`git commit`\ #text(size: 1.4em)[→]]
][
  #card(tint: palette.iris, title: [HEAD])[目前分支最後一次 commit]
]
#v(.8em)
#callout(kind: "info", compact: true)[`git status` 報告的永遠是這三者兩兩之間的差異。]

#speaker-note[
  Git 操作讓新手困惑的另一個來源,是沒意識到同一份專案在 Git 眼裡同時存在*三個版本*:

  - *working directory*:硬碟上實際看到、編輯的檔案
  - *index(又叫 staging area)*:「下一次要提交的內容」的暫存區
  - *HEAD*:目前分支最後一次 commit 的內容

  `git add` 做的事,是把 working directory 裡的變動*複製一份進 index*;`git commit` 做的事,是把 index 目前的內容*封裝成一個新的 commit 物件*,然後把分支指標移過去。`git status` 報告的,永遠是這三者兩兩之間的差異:working directory 跟 index 不一樣,叫「已修改未暫存」;index 跟 HEAD 不一樣,叫「已暫存待提交」。搞懂這三層,才看得懂為什麼 `git add` 之後又改了檔案,還要再 `add` 一次——因為 index 裡存的是*當時那一刻*的複製,不會跟著 working directory 自動更新。
]

== merge 的兩種走法

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [fast-forward])[main 分岔後完全沒有新 commit\
    指標直接往前挪，連 merge commit 都不用生]
][
  #card(tint: palette.iris, title: [三方合併])[兩邊都往前走了（git-merge-lab 場景）\
    找共同祖先，比對兩邊各自的差異]
]
#v(.6em)
#row(gutter: .7em)[
  #card(tint: palette.teal, title: [改不同地方])[Git 有把握自動套用兩份修改\
    生出 two-parent merge commit]
][
  #card(tint: palette.rose, title: [改同一處])[Git 無法決定留哪份意圖\
    → 衝突]
]

#speaker-note[
  兩個分支各自往前走了幾個 commit,要把它們合而為一,`git merge` 有兩種走法。

  如果目標分支(比如 `main`)從分岔點之後完全沒有新的 commit——換句話說,`main` 現在的位置就是 `feature` 的某個祖先——Git 會做 *fast-forward*:什麼都不用真的合併,直接把 `main` 這個指標往前挪到 `feature` 現在指的位置就好,連一個新的 merge commit 都不用生。這是最乾淨、最沒有歷史噪音的情況,但它有個前提:兩條分支的修改沒有交錯發生。

  真正有意思的是兩邊*都*有新 commit 的情況——這正是 git-merge-lab 的場景:`main` 把 API 重構成結構化的 `VelocityReading` / `VelocityTarget` 型別,`feature/safety-limit` 保留舊的 API 但加上 `std::clamp` 安全限制,兩邊從同一個祖先各自往前走。這時候 Git 做的是*三方合併(three-way merge)*:找出共同祖先、比對祖先到 `main` 的差異、比對祖先到 `feature` 的差異,如果兩邊動的是檔案裡*不同的地方*,Git 有把握自動把兩份修改都套用,生出一個有兩個 parent 的 merge commit。但如果兩邊動的是*同一處*——這個 lab 就是故意設計成這樣:兩個分支都動了 `velocity_controller.cpp` 裡計算誤差的那幾行——Git 沒辦法替我們決定該留哪一份意圖,於是*衝突*,在檔案裡插入衝突標記停下來,把決定權交還給人:
]

== 衝突：Git 如實呈現，人負責意圖

#code(title: "velocity_controller.cpp")[
  ```text
  <<<<<<< HEAD
  main 分支目前內容
  =======
  incoming branch 內容
  >>>>>>> feature/safety-limit
  ```
]
#v(.4em)
#callout(kind: "warn", compact: true)[衝突不是「合併失敗」，是 Git 老實承認不知道兩段意圖怎麼揉合，如實呈現給人看。]

#speaker-note[
  `<<<<<<< HEAD` 到 `=======` 之間是*目前所在分支*的版本,`=======` 到 `>>>>>>> feature/safety-limit` 之間是*要並進來那個分支*的版本。這裡最重要的心法是:*衝突不是「合併失敗」,是 Git 老實地承認自己不知道兩段修改的意圖該怎麼揉合,如實呈現兩邊給人看*。三方合併演算法能自動處理「改了不同地方」,但沒辦法自動理解語意——lab 裡那道選擇題(保留新 API、保留安全限制、還是兩個意圖都要留住)正是在練這個:衝突標記只給出「兩邊各自寫了什麼」,*判斷兩段修改的意圖該怎麼正確地合而為一,是人(或將來的 AI 協作者)該做的事,不是 Git 該做的事*。解決完手動把標記刪掉、留下想要的最終內容,`git add` 那個檔案再 `git commit`,就完成了這次合併——生出的這個 commit 會記住它有兩個 parent,歷史圖上看得到那個交會的菱形。
]

== rebase：換一種改寫歷史觀感的方式

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [merge])[保留分岔又交會的痕跡\
    真實發生的樣子]
][
  #card(tint: palette.amber, title: [rebase])[commit 重新「演」一遍\
    產生全新 SHA，歷史看起來像從沒分岔過]
]
#v(.6em)
#callout(kind: "danger")[未推送的本機分支：隨意 rebase。已推上去、別人可能已拉下去的歷史：不要 rebase。]

#speaker-note[
  `merge` 保留兩條分支實際發生的樣子,歷史上會留下分岔又交會的痕跡;`git rebase` 走的是另一條路——把一條分支上的 commit,一個一個重新"演"一遍、接到另一個分支最新的位置之後,*產生的是全新的 commit(新的 SHA),歷史看起來像是這些修改從來就是按順序、乾淨地依序發生的*,沒有分岔。這也是為什麼講物件模型那段要強調「內容變了雜湊就變」——rebase 本質上是拿舊 commit 的內容當範本,造出一批新物件,舊的那些不再被任何分支指著,之後會被 Git 的垃圾回收清掉。

  要記住的實務分野很簡單:*還沒推送到共用 remote 的本機分支,想 rebase 讓歷史乾淨一點,隨意;已經推上去、別人可能已經拉下去用的歷史,不要 rebase*——因為 rebase 造出的是全新物件,一旦別人的分支還接在舊的那批 commit 上,你這邊重寫完再推上去,會跟別人的歷史對不起來,逼所有人手動收拾殘局。
]

= GitHub：把本機的 Git 變成團隊的介面

== remote：一份可推拉的另一份歷史

#quote-card(tint: palette.teal)[Git 是分散式的，GitHub 是讓團隊形成共識的場所，不是「正本」。]
#v(.5em)
#code(title: "terminal")[
  ```bash
  git remote add origin git@github.com:team/robot-controller.git
  git fetch origin
  git push origin main
  ```
]
#v(.4em)
#row(gutter: .6em)[
  #card(tint: palette.teal, title: [fetch])[抄一份歷史下來\
    不動本機工作分支]
][
  #card(tint: palette.amber, title: [pull])[fetch + merge/rebase\
    悄悄做了兩件事]
][
  #card(tint: palette.iris, title: [push])[送出本機領先 commit\
    走的正是 SSH]
]

#speaker-note[
  Git 本身是分散式的——*沒有哪一份複製天生比別人的更權威*,這跟很多人以為「GitHub 上的才是正本」的直覺不同。GitHub(以及 GitLab、Bitbucket 這些同類平台)做的事,是挑一份複製,架在一台大家都能連到的伺服器上,加上一整層協作介面——*它是共識形成的場所,不是 Git 本身的一部分*。搞懂這個分野,才不會把 GitHub 停機跟「Git 壞了」混為一談。

  一個 Git 倉庫可以登記好幾個 remote——「某個網址,是另一份可能有不同進度的同一段歷史」:

  ```bash
  git remote add origin git@github.com:team/robot-controller.git
  git fetch origin
  git push origin main
  ```

  `fetch` 只是把遠端的歷史抄一份下來,不動本機正在工作的分支;`pull` 則是 `fetch` 加上立刻 `merge`(或依設定 `rebase`)進本機分支——很多人撞到的「為什麼 `git pull` 冒出一個 merge commit」,就是因為 `pull` 悄悄做了兩件事而不是一件。`push` 反過來,把本機領先的 commit 送到遠端——這裡第一次真正用到我們剛講完的 SSH:`git@github.com:...` 這種網址,走的就是 SSH 協定,GitHub 認的是你註冊在帳號底下的公鑰,身份驗證的機制跟連一台機器人的閘道機是同一套邏輯,只是這次伺服器換成了 GitHub。
]

== Pull Request：把「要不要合併」變成可討論的決策

#row(gutter: .6em)[
  #card(tint: palette.iris, title: [protected branch])[禁止直接 push main]
][
  #card(tint: palette.teal, title: [required review])[至少一位他人核准]
][
  #card(tint: palette.amber, title: [CI])[建置與測試必須過]
][
  #card(tint: palette.rose, title: [code owner])[特定路徑由負責人核准]
]

#speaker-note[
  Git 本身沒有 Pull Request 這個概念——它完完全全是 GitHub 加上去的協作層。PR 的本質是:「我這邊有一段領先的歷史(一個分支),我想請你把它合併進你那邊的主線,在真的合併之前,給我們一個地方討論、審查、跑自動化檢查」。這一層解決的是純 Git 解決不了的問題:*誰有權把什麼東西並進 `main`、並進去之前要滿足什麼條件*。常見的團隊機制包括:

  - *protected branch*:`main` 禁止直接 `push`,所有變更都得先開 PR
  - *required review*:PR 要有至少一位其他人核准才能合併
  - *CI 檢查*:PR 會自動觸發建置與測試,紅燈不給合併——這跟 visual-relay 那份 grader 的精神一致,只是換成自動在 PR 上跑
  - *code owner*:特定路徑的修改,一定要該領域負責人核准
]

== AI 協作者進場之後，這層介面的意義變了什麼

#align(center)[
  #card(tint: palette.rose, title: [舊假設], icon: [👤])[審查者信任提交者對程式碼有基本理解]
  #v(.5em)
  #text(size: 1.3em)[↓]
  #v(.5em)
  #card(tint: palette.iris, title: [AI 打破的假設], icon: [🤖])[diff 可能是幾秒前生出來的，提交者本人都還沒完整讀過]
]
#v(.5em)
#callout(kind: "danger", compact: true)[AI 生成的 diff，審查標準不能比人寫的更鬆，反而該更謹慎。]

#speaker-note[
  這裡正是這門課一開始埋的伏筆要收的地方。以前 PR 這套機制假設的是「審查另一個人寫的程式碼」——審查者信任提交者對程式碼有基本理解、寫的時候有在思考。*AI 生成的程式碼打破了這個假設*:速度快到 PR 可以是幾秒鐘前生出來的一大批修改,提交者本人可能都還沒完整讀過。這不代表 PR 機制過時了,恰恰相反——*這套「先討論、留痕跡、要求核准」的機制,變得比以前更重要,因為它是唯一擋在"AI 生成的東西"跟"跑在正式環境的東西"之間的關卡*。養成的習慣應該是:AI 生成的 diff,審查標準不能比人寫的更松,反而該更謹慎地看——它有沒有偷偷改了不該動的檔案、有沒有引入看起來合理但語意錯誤的邏輯(想想 git-merge-lab 裡選項 D:「表面上整合了兩個意圖,行為卻是錯的」——這正是 AI 生成程式碼最容易出的一種錯)、commit message 是否誠實反映了改了什麼。GitHub 這層「協作介面」的價值,在 AI 參與度愈高的團隊裡,只會愈重。
]

= curl：確認一個網路服務到底通到哪一層

== 這一節不是為了背指令

#row(gutter: .65em)[
  #card(tint: palette.rose, title: [老實講])[ROS 2 講 DDS 不是 HTTP\
    以後不太會常打]
][
  #card(tint: palette.iris, title: [真正要教的])[curl 背後的協定\
    分層除錯思路]
][
  #card(tint: palette.amber, title: [瀏覽器])[幫你藏掉\
    太多細節]
][
  #card(tint: palette.teal, title: [curl -v])[攤開 IP、port、TLS、\
    header、status]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[之後 visual-relay 的健康檢查完全不靠 curl，直接用 nc 手打 HTTP request，看懂前提是先把這裡搞懂。]

#speaker-note[
  SSH 解決「我怎麼登入一台遠端機器」,Git 解決「我怎麼交換一段修改歷史」。這一節先老實把定位講清楚:ROS 2 節點之間講的是 DDS,不是 HTTP;訓練模型時你多半在跟檔案系統和 GPU 打交道。如果只看「以後會不會常常手動打這行指令」,答案老實說是不太會。但這一節真正要教的不是 `curl` 這個指令本身,是它背後那個協定,以及一套「服務理論上該通、卻打不通」時的分層除錯思路——這兩樣東西,才是往後每次除錯真正在用的底子。稍後 visual-relay 這份作業裡,有一支健康檢查腳本完全不靠 `curl`,直接用 `nc` 手打一段 HTTP request;看得懂那幾行在幹嘛,前提正是先把這裡搞懂。

  一個 service 說它在 `http://localhost:8080`、`https://api.github.com`、`http://robot.local:9000/health` 上提供服務,我們要確認它真的存在、真的通、真的回的是我們以為的東西。這件事最常見的入口工具是 `curl`。它看起來像「下載網址」的小工具,實際上是網路服務除錯的聽診器。瀏覽器會替我們藏掉太多細節,`curl -v` 會把連線過程攤開:解析到哪個 IP、連到哪個 port、TLS 握手有沒有成功、送了哪些 request header、伺服器回了什麼 status code 和 header。
]

== 拆開一個 URL

#card(tint: palette.iris)[`https://api.example.com:8443/v1/robots?id=42`]
#v(.6em)
#row(gutter: .5em)[
  #card(tint: palette.teal, title: [scheme])[https]
][#card(tint: palette.amber, title: [host])[需 DNS]
][#card(tint: palette.rose, title: [port])[8443]
][#card(tint: palette.iris, title: [path])[/v1/robots]
][#card(tint: palette.teal, title: [query])[id=42]
]
#v(.5em)
#callout(kind: "tip", compact: true)[把 URL 拆開，除錯才有順序。]

#speaker-note[
  先從 URL 拆起:

  ```text
  https://api.example.com:8443/v1/robots?id=42
  ```

  `https` 是 scheme,決定用 HTTP 還是 HTTPS;`api.example.com` 是 host,要先透過 DNS 變成 IP;`8443` 是 port,省略時 `http` 預設 80、`https` 預設 443;`/v1/robots` 是 path;`id=42` 是 query。很多連線問題其實卡在不同層:名字解析錯、port 沒開、TCP 被擋、TLS 憑證不被信任、HTTP path 打錯、application 回了錯誤 JSON。把 URL 拆開,除錯才有順序。
]

== DNS：把名字變 IP

#code(title: "terminal")[
  ```bash
  getent hosts api.github.com
  dig api.github.com
  ```
]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.teal, title: [getent hosts])[系統真正的解析路徑\
    `/etc/hosts`、DNS、mDNS]
][
  #card(tint: palette.amber, title: [dig])[比較像直接問 DNS]
]

#speaker-note[
  老練工程師查網路問題,通常照層次往下剝。第一步看名字解析。DNS 的工作是把名字變 IP:

  ```bash
  getent hosts api.github.com
  dig api.github.com
  ```

  `getent hosts` 走的是系統真正的解析路徑,會吃 `/etc/hosts`、DNS、mDNS 等設定;`dig` 則比較像直接問 DNS。這個差異很實用。某台機器上 `robot.local` 找得到,另一台找不到,先查名字解析,再查網路。進到 Docker compose 之後,service name 也會變成 DNS 名字:同一張 Docker network 裡,container 可以用 service name 找到彼此。這就是後面 compose network 的底層直覺。
]

== TCP port：三個常被混淆的地址

#code(title: "terminal")[
  ```bash
  curl -v http://localhost:8080/health
  curl -v http://127.0.0.1:8080/health
  curl -v http://0.0.0.0:8080/health
  ```
]
#v(.5em)
#row(gutter: .6em)[
  #card(tint: palette.iris, title: [127.0.0.1])[loopback，只指自己]
][
  #card(tint: palette.teal, title: [localhost])[通常解析到 loopback]
][
  #card(tint: palette.rose, title: [0.0.0.0])[bind 時的「所有網卡」\
    當 client 目標語意混亂]
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[Docker 裡 container 的 localhost 是 container 自己，host 的 localhost 是 host 自己，常見坑是站錯 namespace。]

#speaker-note[
  名字解析成功之後,下一層是 TCP port。服務有沒有在聽、聽在哪張網卡,week0 用過 `ss -tlnp`;客戶端這邊用 `curl` 直接試:

  ```bash
  curl -v http://localhost:8080/health
  curl -v http://127.0.0.1:8080/health
  curl -v http://0.0.0.0:8080/health
  ```

  這三個地址常被初學者混在一起。`127.0.0.1` 是 loopback,只指自己;`localhost` 通常解析到 loopback;`0.0.0.0` 在 server bind 時代表「所有網卡」,拿來當 client 目標時語意很容易混亂。Docker 裡還會多一層:container 裡的 `localhost` 是 container 自己,host 的 `localhost` 是 host 自己。很多「明明服務開在 8080,為什麼連不到」的問題,最後都是站錯 namespace。
]

== HTTP method 與 status code

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [method])[GET 拿 · POST 送\
    PUT/PATCH 更新 · DELETE 刪]
][
  #card(tint: palette.teal, title: [status code])[2xx 成功 · 3xx redirect\
    4xx client 問題 · 5xx server 問題]
]
#v(.5em)
#table(
  columns: (auto, 1fr),
  [4xx], [`404 Not Found`、`401 Unauthorized`],
  [5xx], [`500 Internal Server Error`、`503 Service Unavailable`],
)

#speaker-note[
  TCP 通了,再看 HTTP。HTTP request 最重要的幾個欄位是 method、path、header、body。`GET` 拿資料,`POST` 送資料,`PUT`/`PATCH` 更新,`DELETE` 刪除。Status code 則是伺服器回報結果的第一句話:

  - `2xx`:成功
  - `3xx`:redirect
  - `4xx`:client 這邊的 request 有問題,例如 `404 Not Found`、`401 Unauthorized`
  - `5xx`:server 這邊處理失敗,例如 `500 Internal Server Error`、`503 Service Unavailable`
]

== 常用 curl 指令

#code(title: "terminal")[
  ```bash
  curl -I https://example.com
  curl -v http://localhost:8080/health
  curl -sS http://localhost:8080/status
  curl -X POST http://localhost:8080/api \
    -H 'Content-Type: application/json' -d '{"speed": 0.2}'
  ```
]
#v(.4em)
#align(center)[#pill[-I header] #pill(tint: palette.teal)[-v 細節] #pill(tint: palette.amber)[-sS 適合 CI] #pill(
    tint: palette.rose,
  )[-H / -d]]

#speaker-note[
  常用指令長這樣:

  ```bash
  curl -I https://example.com
  curl -v http://localhost:8080/health
  curl -sS http://localhost:8080/status
  curl -X POST http://localhost:8080/api -H 'Content-Type: application/json' -d '{"speed": 0.2}'
  ```

  `-I` 只拿 header,適合快速看 status code、server、cache、redirect。`-v` 看完整連線細節。`-sS` 適合 script 和 CI,正常時安靜,出錯時印錯誤。`-H` 加 header,`-d` 送 body。之後看 Docker healthcheck,很多本質上就是「定期 curl 一個 endpoint,看退出碼和 status」。
]

== 沒裝 curl，也能手打 HTTP

#code(title: "healthcheck-service.sh")[
  ```sh
  nc -w 1 127.0.0.1 "$port" <<EOF | grep -q 'ready=true'
  GET /ready HTTP/1.1
  Host: 127.0.0.1
  Connection: close

  EOF
  ```
]
#v(.4em)
#callout(
  kind: "info",
  compact: true,
)[nc 只把文字原封不動送進 TCP，懂 HTTP 格式的是寫這段文字的人，還有另一端的 server。]

#speaker-note[
  這裡先兌現前面欠的帳。visual-relay 的 runtime image 刻意做得很精簡——精簡到裡面根本沒裝 `curl`,這其實是正確的部署直覺,跑正式服務的 image 不該背著一堆除錯工具過日子。可是 healthcheck 還是得做,`scripts/healthcheck-service.sh` 的解法是直接用 `nc` 手打一段 HTTP request:

  ```sh
  nc -w 1 127.0.0.1 "$port" <<EOF | grep -q 'ready=true'
  GET /ready HTTP/1.1
  Host: 127.0.0.1
  Connection: close

  EOF
  ```

  這幾行第一眼很陌生,但其實就是 `curl -v` 平常幫你自動組好、藏起來的那個 request 攤開來看:第一行是 request line(method、path、HTTP 版本),接著是 header,一個空行代表 header 結束、body 開始(這裡沒有 body)。`nc` 不懂 HTTP,它只負責把這段文字原封不動送進 TCP 連線;真正懂 HTTP 格式的是寫這段文字的人,還有另一端的 server。`curl` 把這一層包好,讓你打一行指令就走完;`nc` 逼你自己手刻,好處是完全不用裝 `curl`,代價是你得自己看得懂 HTTP request 長什麼樣——這正是這一節在打的底子。之後遇到任何「不用 curl、自己組 HTTP request」的腳本,都可以照這個思路拆開讀。
]

== TLS 與身份：憑證、token

#code(title: "terminal")[
  ```bash
  openssl s_client -connect api.github.com:443 -servername api.github.com
  curl -H "Authorization: Bearer $TOKEN" https://api.example.com/v1/me
  ```
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[`certificate verify failed` = 「我無法用本機信任的 CA 鏈驗證這張憑證」。`-servername` 是 SNI，少了它伺服器可能給你另一張憑證。]
#v(.3em)
#callout(
  kind: "danger",
  compact: true,
)[token 是權限：進 secret store、限制 scope、避免出現在 shell history、log、commit 裡。]

#speaker-note[
  HTTPS 多了一層 TLS。TLS 做兩件事:加密傳輸,以及透過憑證確認你連到的伺服器身份。`curl` 報 `certificate verify failed` 時,它在說「我無法用本機信任的 CA 鏈驗證這張憑證」。常見原因包括系統 CA 太舊、公司 proxy 換了憑證、自簽憑證沒被加入信任、host name 和憑證上的名字對不起來。可以用這個看 TLS 握手和憑證:

  ```bash
  openssl s_client -connect api.github.com:443 -servername api.github.com
  ```

  `-servername` 是 SNI,現代 HTTPS 很常靠它在同一個 IP 上服務多個網站。少了它,伺服器可能給你另一張憑證。這個細節平常不常想,debug 憑證問題時很值錢。

  最後是身份。HTTP API 常見身份方式有 Bearer token、cookie、basic auth、API key。Bearer token 會長這樣:

  ```bash
  curl -H "Authorization: Bearer $TOKEN" https://api.example.com/v1/me
  ```

  這裡接回 GitHub 和 CI:token 是權限,要進 secret store,要限制 scope,要避免出現在 shell history、log、commit 裡。能不能連上服務是一回事,用什麼身份連上去是另一回事。這跟 SSH key 的精神其實一樣:網路通了,還要有正確的身份和授權。
]

== jq 切開回應，照層次除錯

#code(title: "terminal")[
  ```bash
  curl -sS https://api.example.com/v1/robots | jq '.items[] | .name'
  ```
]
#v(.5em)
#align(center)[
  #pill[URL] #text(size: 1.1em)[→] #pill(tint: palette.teal)[DNS] #text(size: 1.1em)[→] #pill(
    tint: palette.amber,
  )[IP / TCP port] #text(size: 1.1em)[→] #pill(tint: palette.rose)[TLS] #text(size: 1.1em)[→] #pill[HTTP status] #text(
    size: 1.1em,
  )[→] #pill(tint: palette.iris)[body]
]
#v(.5em)
#callout(
  kind: "tip",
  compact: true,
)[Compose 裡 service name 靠 DNS 找彼此，healthcheck 常用 HTTP endpoint 判斷 readiness。]

#speaker-note[
  有 JSON 的 API,常常會接 `jq`:

  ```bash
  curl -sS https://api.example.com/v1/robots | jq '.items[] | .name'
  ```

  `curl` 負責拿回 response,`jq` 負責把 JSON 切開。這種組合非常 UNIX:一個工具負責 HTTP,一個工具負責結構化文字,中間用 pipe 接起來。CI 和 agent 都很愛這種形式,因為它可重跑、可比較、可放進 script。

  遇到「服務連不上」時,照這條順序查:

  ```text
  URL 拆對了嗎 -> DNS 名字解析對嗎 -> IP/port 通嗎 -> TLS 憑證過嗎 -> HTTP status 是什麼 -> body 說了什麼
  ```

  這套順序會一路用到 Docker。Compose 裡 service name 靠 DNS 找彼此,port publish 決定 host 能不能連進 container,healthcheck 常用 HTTP endpoint 判斷 readiness,CI 會用 curl 打 API 或等服務起來。先學會用 `curl -v` 看清楚一條 request 走到哪一層,後面看 container network 和 healthcheck 會輕鬆很多。
]

== wget 與同一排工具

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [curl])[跟一個 endpoint 對話\
    header、method、token、JSON、debug]
][
  #card(tint: palette.teal, title: [wget])[把檔案抓下來\
    release tarball、遞迴抓站、斷點續傳]
]
#v(.5em)
#code(title: "terminal")[
  ```bash
  wget -c https://example.com/large-dataset.zip
  wget -r -np https://example.com/docs/
  ```
]

#speaker-note[
  順帶把 `curl` 和 `wget` 分清楚。兩個都能抓 URL,定位不同。`curl` 是「跟一個 endpoint 對話」的工具,適合看 header、送不同 method、加 token、送 JSON、debug API 和 healthcheck。`wget` 是「把檔案抓下來」的工具,適合下載 release tarball、遞迴抓網站、斷點續傳、照著連結把一批檔案收回來。

  常見例子:

  ```bash
  wget https://example.com/releases/tool.tar.gz
  wget -c https://example.com/large-dataset.zip
  wget -r -np https://example.com/docs/
  ```

  `-c` 是 continue,下載大檔案中斷後接著抓。`-r` 是 recursive,會沿著連結抓一批檔案;`-np` 是 no parent,限制它待在目前目錄底下。下載資料集、模型權重、release artifact 時,`wget` 很順手。打 API、看 header、送 token 時,`curl` 比較自然。
]

= Docker：把「環境」本身變成可以版本控制的東西

== 「我的機器上可以」：兩條解法的路

#card(tint: palette.rose, title: [works on my machine], icon: [🤷])[
  #set text(size: 0.9em)
  OS 版本 · 函式庫版本 · 環境變數 · 系統套件 · 殘留設定檔，原因從來不是單一個。
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.amber, title: [第一條路：VM], icon: [🖥])[模擬整台假硬體，跑獨立 kernel\
    隔離徹底，代價徹底：開機慢、映象幾 GB]
][
  #card(tint: palette.teal, title: [第二條路：container], icon: [📦])[隔離的「世界」共用 host kernel\
    Docker 只是工具鏈之一：Podman 也能\
    跑同一個 image（daemonless / rootless）]
]

#speaker-note[
  任何軟體專案到一定規模,都會撞上同一句話——「在我的機器上是好的」。原因從來不是單一個,而是一整疊環境細節的總和:作業系統版本、函式庫版本、環境變數、系統套件、甚至硬碟上殘留的某個設定檔。想解決這個問題,歷史上主要試過兩條路。

  第一條路是*虛擬機器(VM)*:用 hypervisor 模擬出一整台假的硬體,在上面跑一個完整獨立的作業系統核心。這個隔離做得很徹底——連 kernel 都是獨立的——但代價也很徹底:每一台 VM 都要背一整個作業系統的開銷,開機要數十秒到數分鐘,映象動輒幾 GB 到幾十 GB,機器資源被切得七零八落。

  第二條路,也就是 container 採取的路:*不虛擬化硬體,而是讓多個隔離的"世界"共用同一個 host 的 kernel*。這個想法不是 Docker 發明的，它的貢獻是把這些底層機制包成一套好用的工具鏈。

  Docker 不是 container 的同義詞。

  同一個 image 可以被不同工具 build、pull、run。例如 Podman 是另一套常見 CLI,指令長得很像 Docker,但主打 daemonless 和 rootless。
]

== macOS / Windows 怎麼跑 Linux container

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.iris, title: [macOS])[Docker Desktop / Colima / Lima\
    幫你管理底下那台 Linux VM]
][
  #card(tint: palette.teal, title: [Windows])[Docker Desktop 長期走 WSL2 backend\
    借 WSL2 的 Linux kernel]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[近年更系統化：Apple `container` / Containerization、Microsoft WSL Containers（`wslc.exe`）。核心共通概念才是重點：image、registry、namespace、cgroup、mount、network、權限。]

#speaker-note[
  值得提的趣事：macOS 和 Windows 都不是 Linux kernel,所以它們跑 Linux container 本來就需要某種 Linux VM 當底座。macOS 上常見做法是 Docker Desktop、Colima、Lima 這類工具幫你管理那台 Linux VM;Windows 上 Docker Desktop 很長一段時間就已經走 WSL2 backend,也就是借 WSL2 裡的 Linux kernel 來跑 Linux containers。近年平台商開始把這層做得更像系統能力:Apple 開源了 `container` / Containerization,用 macOS Virtualization framework 在 Apple silicon 上跑輕量 Linux VM;Microsoft 的 WSL Containers 則是在 WSL 平台裡提供 `wslc.exe` 和 API,讓 Windows 應用和命令列能直接操作 Linux containers。

  不過呢，對我們來說這門更該學的還是 image、registry、namespace、cgroup、mount、network、權限這些共通概念。
]

== namespace：這個 process 看得到什麼

#table(
  columns: (auto, 1fr),
  [PID], [container 裡第一個 process 是 PID 1，即使 host 上其實是 PID 88213],
  [mount], [獨立的檔案系統樹，跟 host 或其他 container 互不相干],
  [network], [自己的網卡、IP、routing table、埠空間],
  [UTS], [自己的 hostname],
  [user], [container 的 root 可對應 host 上完全沒特權的一般使用者],
)

#speaker-note[
  *namespace* 。它負責讓一個 process「看不到」不屬於它的東西。Linux 有好幾種 namespace,各自切開系統的一個面向:PID namespace 讓 container 裡的 process 看到的是自己獨立的一份 PID 編號(container 裡的第一個 process 看到自己是 PID 1,即使 host 上它其實是 PID 88213);mount namespace 讓它看到自己獨立的一份檔案系統樹,跟 host 或其他 container 互不相干;network namespace 讓它有自己的一套網路介面、IP、routing table、埠空間——這就是為什麼兩個 container 都能各自監聽自己的 `8080` 而互不衝突;UTS namespace 給它自己的 hostname;user namespace 甚至能讓 container 裡的 `root` 對應到 host 上一個完全沒有特權的一般使用者。*每種 namespace 解決的是"這個 process 能看到什麼"*。
]

== cgroup：這個 process 能用多少

#v(1em)
#row(widths: (1fr, auto, 1.2fr, auto, 1.2fr), align: horizon, gutter: .5em)[
  #card(tint: palette.iris, title: [namespace])[隔開視野]
][
  #align(center)[#text(size: 1.4em)[+]]
][
  #card(tint: palette.teal, title: [cgroup])[限制配額\ （CPU / 記憶體 / I/O / 頻寬）]
][
  #align(center)[#text(size: 1.4em)[=]]
][
  #card(tint: palette.amber, title: [container])[一群被隔開又限額的\ host process]
]
#v(.8em)
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[container 之間共用同一個 host kernel，kernel 本身的漏洞能跨越這層隔離，跟 VM 是不同等級的隔離強度。]

#speaker-note[
  *cgroup*(control group) 解決的是另一半問題:「這個 process 能用多少」。它是 kernel 用來限制、記錄一群 process 共同資源使用量的機制——CPU、記憶體、磁碟 I/O、網路頻寬都能設上限。

  把兩根柱子放在一起看:*container 本質上是一群被 namespace 隔開視野、被 cgroup 限制配額的 host process*,不是別的虛擬機器。這解釋了 container 為什麼開機是毫秒級的(`docker run` 起一個 container 基本上就是 kernel 建幾個 namespace、啟動一個 process 這麼快)、為什麼映象可以做到幾十 MB(不用打包一整個 kernel,只需要打包 userland)、也解釋了它的隔離邊界在哪裡——*container 之間共用同一個 host kernel,kernel 本身的漏洞是能跨越這層隔離的*,這跟 VM「連 kernel 都分開」的隔離強度是不同等級,資安考量上要誠實面對這個差異。
]

== Image layer：內容定址的既視感

#v(1em)
#row(widths: (1fr, auto, 1fr, auto, 1fr), align: horizon, gutter: .5em)[
  #card(tint: palette.teal, title: [base])[OS / runtime]
][
  #align(center)[`layer`\ #text(size: 1.3em)[→]]
][
  #card(tint: palette.amber, title: [dependencies])[套件與第三方依賴]
][
  #align(center)[`layer`\ #text(size: 1.3em)[→]]
][
  #card(tint: palette.iris, title: [application])[你常改的程式碼]
]
#v(.8em)
#v(.5em)
#callout(
  kind: "tip",
  compact: true,
)[跟 Git 物件模型似曾相識，每層用自己內容的雜湊當 ID，輸入沒變就重用上次 build 的 layer。]

#speaker-note[
  講完 Git 的物件模型再看 image 的結構,會有一種似曾相識的感覺——*Docker image 也是一疊內容定址、可重用的層,疊起來才是完整的檔案系統*。每一條 Dockerfile 指令(幾乎每個 `RUN`、`COPY`、`ADD`)都會生出一個新的 layer,每一層只記錄「跟上一層比起來,檔案系統改動了什麼」,而且每一層用自己內容的雜湊當 ID。這帶來兩個直接的好處:*多個 image 只要共用前面幾層完全一樣,那幾層的資料在硬碟上只會存一份*;而且 build 的時候,如果某一層的輸入(前面的層加上這條指令本身)完全沒變,Docker 會直接重用上次 build 好的那層,不必重新執行——這就是 *build cache*。
]

== 讓 build 吃到快取

#align(center)[
  #text(size: 1.15em, weight: "bold", fill: palette.iris)[改動頻率低的排前面，改動頻率高的排後面]
]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.teal, title: [前面])[系統套件、編譯工具、第三方依賴]
][
  #card(tint: palette.rose, title: [後面])[`src/`、`include/`、測試檔]
]
#v(.5em)
#row(gutter: .8em)[
  #card(tint: palette.iris, title: [layer cache])[快取「這層執行完的檔案系統結果」]
][
  #card(tint: palette.teal, title: [cache mount])[快取「工具自己的工作目錄」\
    apt / ccache / pip，靠 `# syntax=docker/dockerfile:1.7`]
]

#speaker-note[
  這個機制直接決定了 Dockerfile 該怎麼寫。第一個原則是:*改動頻率低的東西排前面,改動頻率高的東西排後面*。系統套件、編譯工具、第三方依賴通常比應用程式碼少改,所以應該讓它們待在比較前面的 layer;自己的 `src/`、`include/`、測試檔則放在後面。這樣每次改一行應用程式碼重新 build,前面昂貴的安裝和編譯步驟才有機會直接吃快取,不用全部重跑。visual-relay 的 grader 會檢查 rebuild 是否真的有效率,但它要你自己從失敗訊息推回 Dockerfile 應該怎麼拆。

  除了 layer cache,Docker BuildKit 還有一個進階功能叫 *cache mount*。它跟 layer cache 是不同的機制:layer cache 快取的是「這一層執行完之後的檔案系統結果」,cache mount 快取的是「某個工具自己的工作目錄」。`apt`、`ccache`、`pip` 這類工具本來就有下載或編譯快取,cache mount 是把那個快取目錄跨 build 保留下來,即使外層那一層因為其他原因重新執行,工具自己的快取還能繼續累積。這也是為什麼 Dockerfile 第一行常看到:

  ```dockerfile
  # syntax=docker/dockerfile:1.7
  ```

  這行不是註釋,是在告訴 Docker「用哪個版本的 BuildKit 語法解析這份 Dockerfile」,cache mount 這類新語法就是靠它才能用。
]

== multi-stage build：建置期與執行期分開

#code(title: "Dockerfile")[
  ```dockerfile
  FROM build-image AS builder
  RUN make release

  FROM runtime-image
  COPY --from=builder /app/bin/service /usr/local/bin/service
  USER app
  CMD ["service"]
  ```
]
#v(.4em)
#callout(
  kind: "danger",
  compact: true,
)[新手常把編譯器、原始碼、測試框架一起打進 production image——又大又肥，還多了攻擊面。visual-relay 起始版本故意這麼糟；「能 build」不等於「設計完成」。]

#speaker-note[
  一個常見的新手錯誤,是把編譯器、原始碼、測試框架全部一起打進最終要跑在生產環境的 image 裡——image 因此又大又肥,還帶著一堆不該存在於正式環境的攻擊面(編譯器能被拿來現場編譯惡意程式、原始碼可能夾帶機密)。*multi-stage build* 解決的就是這個:一份 Dockerfile 裡可以定義多個 `FROM ... AS <階段名>`,階段之間可以互相 `COPY --from=`,只把需要的產出物挑過去,最終只有你實際拿去 `docker build` 指定的那個階段(用 `--target` 指定,或 compose 裡的 `target:`)會變成真正的 image,其餘階段用完就丟。

  visual-relay 的作業就是要你把「建置期」和「執行期」切乾淨。學生拿到的起始版本故意很糟:工具鏈、原始碼、測試、三個服務全擠在同一個 image 裡,雖然跑得起來,但完全不像一個可以交付的部署。這份回家作業會要求你做出真正的 multi-stage build、能在 container 裡跑測試的 target、以及乾淨的 runtime image。注意這裡不要把「能 build」誤會成「設計完成」:最後拿去跑服務的 image 裡,不應該留下編譯器、build tree、測試框架或原始碼。
]

== runtime 身份與最小權限

#row(widths: (1fr, 1.4fr), gutter: .8em, align: horizon)[
  #card(tint: palette.rose, title: [預設], icon: [⚠])[container process 是 root]
][
  #card(tint: palette.teal, title: [better], icon: [✓])[專用非 root 帳號：不需登入 shell、不需密碼、不需管理系統]
]
#v(.5em)
#row(gutter: .65em)[
  #card(tint: palette.iris, title: [檔案])[read-only filesystem\
    明確暫存例外]
][
  #card(tint: palette.teal, title: [權限])[no-new-privileges\
    禁止中途提權]
][
  #card(tint: palette.amber, title: [資源])[CPU · memory · PIDs\
    上限]
]
#v(.4em)
#callout(kind: "info", compact: true)[不是為了讓 YAML 好看，是最小權限原則：預設關閉一切，只開明確需要的門。]

#speaker-note[
  映象編好了,接下來是它*用什麼身份、有多少權限*跑起來。預設情況下 container 裡的 process 是 `root`——這跟前面權限那節的教訓直接接上:*沒有理由的 root 就是風險*。比較好的 runtime image 會建立專用的非 root 帳號,而且這個帳號不需要登入 shell、不需要密碼、不需要管理系統。`USER` 指令切過去之後,服務就用這個受限身份執行;就算應用程式本身被打穿一個漏洞,攻擊者拿到的也不該是 container 裡的 root。

  除了使用者身份,compose 層還可以繼續收緊權限邊界。常見方向包括:讓 runtime filesystem 盡量唯讀,只替真正需要寫入的暫存位置開例外;限制這些暫存位置不能執行程式或拿來提權;禁止 process 在執行中途取得比啟動時更高的權限;替 CPU、記憶體、process 數量設上限。這些不是為了讓 YAML 看起來華麗,而是資安裡的*最小權限原則(principle of least privilege)*:預設關閉一切,只開明確需要的那一道門。visual-relay 的 grader 會把這些要求拆成可檢查的項目,但具體要怎麼組合,就是作業的一部分。
]

== GUI container：一條很窄的門

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.amber, title: [host session])[一組 process、socket、環境變數、權限\
    `DISPLAY` / `WAYLAND_DISPLAY`]
][
  #card(tint: palette.iris, title: [container 預設])[看不到 host socket、未必有權限連\
    → `cannot open display`]
]
#v(.5em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.amber, title: [X11 除錯方向])[較老、較寬鬆：`DISPLAY`、\
    Xauthority、socket mount、權限]
][
  #card(tint: palette.teal, title: [Wayland 除錯方向])[較新、權限收斂：runtime socket、\
    `XDG_RUNTIME_DIR`、portal、支援度]
]

#speaker-note[
  這裡會用到 week0 介紹的桌面環境和顯示系統。大多數 container 跑的是本質只是 server process,它沒有畫面;但機器人開發很常需要 GUI:RViz、Gazebo、rqt、影像 viewer、debug overlay。container 裡的程式要把畫面開到 host 的桌面上。這時候 Docker 必須讓 container 穿過一條很窄的門,接到 host 正在跑的圖形 session。

  為什麼這件事麻煩?因為圖形 session 不是抽象的「螢幕」,而是一組 process、socket、環境變數和權限。week0 看過的 `DISPLAY` 是 X11 的入口,`WAYLAND_DISPLAY` 是 Wayland 的入口,`XDG_SESSION_TYPE` 告訴我們現在活在哪種 session 裡。這些值本來只存在 host 的 login session;container 是另一個 process 世界,預設看不到 host 的 socket,也不一定有權限連上去。所以同一個 GUI 程式,在 host 上能開視窗,進 container 後卻可能報 `cannot open display`、`No available video device`、`Permission denied`。那是它拿不到 host display server 或 compositor 的通行證。

  X11 和 Wayland 的除錯方向也不同。X11 比較老、比較寬鬆,常見問題是 `DISPLAY`、Xauthority、socket mount 和使用者權限。Wayland 比較新、權限模型比較收斂,常見問題是 runtime socket、`XDG_RUNTIME_DIR`、portal、以及工具本身是否真的支援 Wayland。這正好呼應 week0 那句話:GUI 工具行為怪異時,先問「現在是 X11 還是 Wayland session」。到了 Docker 裡,還要再加一問:「container 真的看得到並且有權限使用這個 session 嗎?」

  要記住:GUI container 不會自己長出一個桌面,它需要向 host 既有的桌面 session 借入口。
]

== network：service name 就是 DNS

#align(center)[
  #pill(tint: palette.iris)[camera-net] #h(.5em) #pill(tint: palette.teal)[handoff-net] #h(.5em) #pill(
    tint: palette.amber,
  )[control-net]
]
#v(.6em)
#callout(
  kind: "warn",
)[三張隔離的網，不是一張大平面網路。一個 container 只加入它真正需要通話的那幾張，能力邊界應跟職責邊界重合，跟 SSH 的 `ProxyJump` 是同一種設計哲學。]

#speaker-note[
  Container 的網路建立在我們剛講完的 network namespace 之上,Docker 在這之上再加一層:自訂的 bridge network 讓一群 container 用*服務名字*互相定位,不用記 IP。visual-relay 的公開架構圖已經告訴你它不是一張大平面網路,而是三張隔離的網:`camera-net` 負責相機資料,`handoff-net` 負責站點之間交接,`control-net` 負責控制授權。這裡要練的不是背網路名字,而是從通訊需求反推網路邊界:*一個 container 只應該加入它真正需要通話的那幾張網*。這跟 SSH 那節 `ProxyJump` 是同一種設計哲學的不同實現:*能力的邊界應該跟職責的邊界重合*,沒有理由對外連線或碰到某段內部流量的服務,就不要給它那個能力。
]

== healthcheck：活著不代表健康

#align(center)[
  #card(tint: palette.rose, title: [process 活著])[`docker ps` 照樣顯示在跑\
    就算卡死在無窮迴圈裡]
  #v(.5em)
  #text(size: 1.3em)[$eq.not$]
  #v(.5em)
  #card(tint: palette.teal, title: [服務真的健康])[healthcheck 定期執行檢查指令\
    退出碼 → healthy / unhealthy]
]
#v(.4em)
#align(center)[`interval` · `timeout` · `retries` · `start_period`]

#speaker-note[
  healthcheck 解決的是另一個問題——*process 活著,不代表服務是健康的*。一個卡死在無窮迴圈裡的服務,`docker ps` 照樣顯示它在跑。Docker 的 healthcheck 會定期執行一條你定義的檢查指令,根據退出碼把 container 標成 `healthy` 或 `unhealthy`;`interval`、`timeout`、`retries`、`start_period` 則控制檢查頻率、逾時、失敗容忍度和啟動寬限期。visual-relay 有三個長時間服務,grader 會實際啟動它們、注入網路中斷和服務重啟,所以 healthcheck 不能只是裝飾品:它必須能反映服務是否真的準備好、是否真的還能回應。
]

== compose：把系統描述成一份檔案

#quote-card(tint: palette.iris)[我要這幾個 service，接這些 network，用這些 volume，帶這些限制。]
#v(.5em)
#row(gutter: .6em)[
  #card(tint: palette.iris, title: [services])[要跑哪些東西]
][
  #card(tint: palette.teal, title: [networks])[通訊平面\
    讓不同職責流量分開]
][
  #card(tint: palette.amber, title: [volumes])[資料生命週期]
]
#v(.4em)
#callout(
  kind: "warn",
  compact: true,
)[少一個參數，系統可能看起來「有跑起來」，行為已偏離設計——部署從手動流程變成可重建的系統描述，跟 systemd unit、Kubernetes 相通。]

#speaker-note[
  單一 `docker run` 指令管一個 container 還行。系統變成多個服務之後,手動指令很快就失控。container 名字、image、build target、環境變數、port、volume、network、healthcheck、資源限制、啟動順序,每一項都要打對。少一個參數,系統可能看起來「有跑起來」,實際行為已經偏離原本設計。visual-relay 作業設計成三個 container、三張網、GUI、healthcheck 和資源限制混在一起,就是要讓大家撞到這個痛點。

  `compose.yaml` 做的事,就是把這些口頭指令收進一份檔案。最外層通常看三塊:`services`、`networks`、`volumes`。`services` 是要跑哪些東西,每個 service 可以說自己用哪個 image、是否 build、跑什麼 command、吃哪些 environment、掛哪些 volume、接到哪些 network、資源上限是多少、怎麼判斷自己健康。`networks` 是服務之間的通訊平面,讓不同職責的流量分開。`volumes` 是資料生命週期,需要跨 container 留下來的資料,就放進明確宣告的 volume。

  這裡的核心是心智模型:Compose 讓我們描述「這套系統應該長什麼樣」。你說我要這幾個 service,它們接這些 network,用這些 volume,帶這些限制;Compose 再去 build image、建 network、啟 container。這跟 systemd unit 的思路很像,也跟以後看到 Kubernetes 時會遇到的概念相通。部署從一串「先做 A、再做 B、然後做 C」的手動流程,變成一份可以重建的系統描述。
]

== depends_on 是順序，不是 readiness

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.rose, title: [depends_on])[process 起來了\
    ≠ schema 初始化完成 / 能正常回應 / 拿到 display]
][
  #card(tint: palette.teal, title: [healthcheck])[更接近「服務真的可用」的訊號]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[Compose 適合單機多服務：本機開發、作業、demo、CI job。跨機器排程、rolling update 交給 Kubernetes 這類 orchestrator。]

#speaker-note[
  `depends_on` 要特別小心。它常用來表達啟動順序。資料庫 process 起來之後還要完成 schema 初始化;HTTP server process 活著之後還要能正常回應;GUI service 開了之後還要拿到 display。這就是 healthcheck 存在的理由:我們需要一個比「process 還活著」更接近「服務真的可用」的訊號。多服務系統很多看似隨機的 bug,其實都是啟動時序和 readiness 沒處理好。

  Compose 的定位也要放對。它適合單機多服務環境:本機開發、作業、demo、integration test、CI job。跨機器排程、rolling update、auto-scaling 那些需求,會走 Kubernetes 這類更完整的 orchestrator。CI 裡常見做法就是用 compose 拉起一組測試依賴——資料庫、message broker、fake service、被測系統本身——測完整組拆掉。這比在 CI script 裡手寫一長串 `docker run` 清楚很多,也比較接近大家本機跑的環境。
]

= 收束

== 回到開場的問題

#quote-card(tint: palette.iris)[當開發不再是一個人在一台機器上寫程式，\
  要靠什麼機制維持信任、一致性和可重現性？]
#v(.6em)
#row(gutter: .65em)[
  #card(tint: palette.iris, title: [SSH 的答案])[信任要驗證\
    不要假設\
    雙向金鑰、TOFU]
][
  #card(tint: palette.teal, title: [Git 的答案])[一致性來自\
    不可篡改的歷史\
    內容定址、DAG]
][
  #card(tint: palette.amber, title: [curl 的答案])[故障要分層定位\
    DNS→TCP→\
    TLS→HTTP]
][
  #card(tint: palette.rose, title: [Docker 的答案])[環境要能\
    被描述、被重建\
    namespace、compose]
]

#speaker-note[
  收束一下。開場丟的那個問題——當開發不再是一個人在一台機器上寫程式,要靠什麼機制維持信任、一致性和可重現性——現在可以逐項回答了。SSH 給的答案是*信任要驗證,不要假設*:兩把方向相反的金鑰,伺服器證明自己、你證明自己,連第一次見面那個沒有密碼學保證的縫隙(TOFU)都被明確標出來,要求你動手比對。Git 給的答案是*一致性來自不可篡改的歷史*:內容定址讓每一段歷史有數學上的指紋,誰改了什麼、從哪裡分岔、怎麼合回來,全部攤在 DAG 上,合不回來的部分誠實地交還給人。curl 那節給的是*故障要分層定位*:名字、連線、憑證、協定、應用,一層一層剝,不用猜的。Docker 給的答案是*環境本身要能被描述、被重建*:namespace 和 cgroup 把「執行環境」變成可以打包、可以限額的東西,compose 再把整套系統寫成一份可以進版本控制的檔案。四個答案合起來,才是那個問題的完整回答——這也是為什麼一開始就說,四套工具其實是一個問題的四個切面。
]

== 帶進 lab，也帶進 AI 時代

#place(bottom + left, dx: -1.6em, dy: -0.2em)[
  #image(
    "figs/ai-think-hero-feathered.png",
    width: 42em,
  )
]

#row(widths: (1fr, 1fr), gutter: 1em)[
  #card(tint: palette.teal, title: [lab 的驗收不只是跑通], icon: [🧪])[
    #set text(size: 0.8em)
    信任、邊界、失敗、可重現，

    才算真的跑通。
  ]
][
  #card(tint: palette.rose, title: [AI 協作的把關], icon: [🤖])[
    #set text(size: 0.8em)
    AI 能生成，但安全、可重現、可信\
    仍需要人來判斷。
  ]
]

#speaker-note[
  最後把這些東西放回這門課的主線。三份 lab——SSH 的 Mission Control、git-merge-lab、visual-relay——驗收的都不只是「跑通」:操作只是入場券,真正要能回答的是左邊這四個問題。fingerprint 比對過了嗎、衝突裡兩邊的意圖都留住了嗎、runtime image 裡還藏著編譯器嗎——答得出這些,代表理解的是機制,而不是背了一串指令。

  右邊那半,是這門課從第一天就埋的伏筆。AI 已經能大量生出程式碼、Dockerfile、compose 設定,而且速度只會愈來愈快。這一週學的每一套機制——PR 審查、金鑰與憑證、分層除錯、最小權限——在 AI 參與度愈高的團隊裡,重要性只會愈高,因為它們是「生成出來的東西」跟「跑在真實系統上的東西」之間僅有的關卡。把關的人必須懂機制,這就是為什麼我們花一整週講這四套工具的原理,而不是發一張指令小抄。工具的名字會換——Git 當年取代了 BitKeeper,Podman 現在站在 Docker 旁邊——但「我信任誰、歷史從哪來、故障在哪層、能不能重現」這四個問題,不會換。
]

#ending-slide(title: [Q & A])
