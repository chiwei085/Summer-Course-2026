#import "@local/summer-course:0.1.0": *

#show: course-theme.with(
  config-info(
    title: [Linux Development Foundations],
    subtitle: [Week 0 · Linux 開發環境入門],
    author: [獵奇緯],
    institution: [Summer Course],
    short-title: [Week 0 · Linux 開發環境入門],
  ),
)

#title-slide()

#outline-slide()

= 課前導覽

#focus-slide[
  碩士剛進實驗室沒有基礎，是很正常的。
]

== Week 0 的定位

#row(widths: (3fr, 2fr), gutter: 1.2em)[
  這是正式課程前的 *開發環境入門*，目標是：

  #v(0.3em)
  - 建立一套 *看得懂系統的心智模型*
  - 以 *日常工作流* 為範圍
  - 奠定日常研究除錯的能力基礎

  #v(0.5em)
  #callout(kind: "info", compact: true)[
    先修假設：修過作業系統，具備基礎觀念。

    研究所錄取不是用雞腿換來的。
  ]
][
  #card(tint: palette.iris, title: [一句話], icon: [🧭])[
    Linux 不神秘。

    #v(0.4em)
    通靈大戰不適合我們這種靈能低下的凡夫俗子，我們 debug  還是乖乖找線索吧。
  ]
]

#speaker-note[
  Linux 開發環境入門，作為 week0 課程幫助沒有任何相關基礎的同學跟上正式課程。

  目標是讓學生理解 Linux 作為開發平台時的基本結構，以日常使用的工作流為教學範圍，正經豐富補充理論知識協助建立使用習慣。
]

== 完成這堂課，你應該能夠

#row(gutter: 1em)[
  #card(tint: palette.iris, title: [分得清楚], icon: [🧠])[
    #set text(size: 0.85em)
    - kernel、發行版、桌面環境、terminal 與 shell 的差異
    - 軟體、套件的不同種安裝方法
    - PATH、環境變數、`source` 與 shell startup file
  ]
][
  #card(tint: palette.teal, title: [動得了手], icon: [🛠])[
    #set text(size: 0.85em)
    - 查系統版本、架構、使用者、shell、桌面 session
    - 用 terminal 完成檔案操作、搜尋與 log 檢查
    - 讀懂使用者、群組、檔案權限與 sudo
    - 觀察 process、port、service 與 systemd log
  ]
]

#v(0.5em)
#align(center)[
  #pill[生態] → #pill(tint: palette.teal)[桌面] → #pill(tint: palette.amber)[SHELL] → #pill(tint: palette.rose)[檔案系統] → #pill[權限] → #pill(tint: palette.teal)[套件] → #pill(tint: palette.amber)[PATH] → #pill(tint: palette.rose)[SYSTEMD]
]

#speaker-note[
  學生完成課程後應該能夠：

  - 分辨 Linux kernel、發行版、桌面環境、terminal 與 shell 的差異
  - 查詢目前系統版本、架構、使用者、shell、桌面 session
  - 理解常見 Linux 目錄結構與路徑概念
  - 使用 terminal 完成基本檔案操作、搜尋與 log 檢查
  - 理解使用者、群組、檔案權限與 sudo 的意義
  - 分辨各種軟體的安裝方式
  - 理解 PATH、環境變數、source 與 shell startup file
  - 觀察 process、port、service 與 systemd log
]

= Linux 生態與發行版

== 當我們說「Linux」，到底在指什麼？

#row(widths: (5fr, 1fr), gutter: 1em, align: horizon)[
  #col(gap: 0.55em)[
    #card(tint: palette.amber, title: [DISTRIBUTION], icon: [📦], inset: 0.7em)[
      #text(
        size: 0.85em,
      )[把 kernel 和 user space (userland) *選好、整合、打包、測試*，並提供更新與支援的系統產品 —— Ubuntu、Fedora、Arch…]
    ]
    #card(tint: palette.teal, title: [USERLAND], icon: [🧰], inset: 0.7em)[
      #text(size: 0.85em)[shell、compiler、library、coreutils、service、desktop、log system 等使用者空間工具]
    ]
    #card(tint: palette.iris, title: [KERNEL], icon: [⚙️], inset: 0.7em)[
      #text(size: 0.85em)[管理硬體、process、memory、filesystem、network、driver 與 system call]
    ]
  ]
][
  #align(center)[
    #image("figs/linux-logo.png", height: 5.5em)
  ]
]

#v(0.4em)
課本沒教的是 —— *發行版到底是什麼*。

#speaker-note[
  當我們說「Linux」，到底在指什麼？Linux 是 kernel。

  - kernel：管理硬體、process, memory, filesystem, network, driver 與 system call
  - userland：shell, compiler, library, coreutils, service, desktop, log system 等使用者空間工具
  - distribution：把 kernel 和 userland 選好、整合、打包、測試，並提供更新與支援的系統產品

  各位都修過作業系統，前兩層應該不陌生。真正在課本裡沒教的是第三層——「發行版到底是什麼」。
]

== 一段歷史：kernel 和 userland 從出身就是兩家人

#place(bottom + left, dx: 5.2em, dy: -0.15em)[
  #rotate(-23deg)[
    #image("figs/gnu-project-logo.png", height: 7.2em)
  ]
]
#place(bottom + right, dx: 2em, dy: 2.75em)[
  #image("figs/linus-torvalds-fade.png", height: 20.8em)
]

#table(
  columns: (auto, 1fr),
  [1970s], [UNIX 定下強勢慣例：多使用者、檔案抽象、小工具 pipe 組合、文字檔設定],
  [1980s], [UNIX 商業化、原始碼不再流通 → *GNU project* 立志重寫自由的 UNIX-like 系統],
  [\~1990], [GNU 做齊 userland（gcc、bash、coreutils、glibc）—— 獨缺 kernel],
  [1991–92], [Linus 發表 Linux kernel、改採 GPL → 兩個世界 *授權相容*，可以合法組裝],
  [1992–93], [Slackware、Debian 誕生 —— 「把它組起來」的角色： *發行版*],
)

#speaker-note[
  這個生態的怪癖很多其實是歷史遺留。1970 年代的 UNIX 留下一組非常強勢的設計習慣：多使用者、多程序、檔案作為統一抽象、小工具用 pipe 組合、文字檔當設定介面、shell 是可程式化的操作環境。這些觀念比任何一個 UNIX 實作都活得久。

  1980 年代的背景是 UNIX 商業化：AT&T 開始認真收授權費，各廠商的 UNIX 互相分裂，原始碼不再像早年那樣在大學間隨手流通。GNU project 就是對這件事的回應——目標是重寫一整套任何人都能自由使用、修改、散布的 UNIX-like 系統。

  到 1990 年前後，這個計畫把 userland 幾乎做齊了：gcc、bash、coreutils、gdb、glibc，唯獨 kernel 遲遲沒有能用的成果。1991 年 Linus Torvalds 發表了自己寫的 kernel，隔年改採 GPL 授權——這一步是歷史的轉捩點，因為授權相容，社群才能合法地拿 GNU userland 配上 Linux kernel，組合成一套完整可安裝的系統。而「把這兩個世界組合起來、讓一般人裝得起來」這件工作本身，就催生了發行版：1992、93 年的 Slackware、Debian 就是在做這件事。所以發行版不是後來才出現的方便包裝——kernel 和 userland 從出身就是不同社群、不同節奏在維護的專案，這個生態從第一天起就需要有人負責整合，這個角色一直存在到今天。
]

== 發行版賣的是什麼？

#quote-card[一組 *整合決策*，加上替這些決策 *負責的承諾*。]

#v(0.4em)
#row(widths: (1fr, 1.4fr), gutter: 1.2em)[
  #text(size: 0.85em)[
    - 預設採用哪些 system component
    - 套件格式與套件管理器
    - 套件版本偏新還是偏穩
    - rolling release 還是 fixed release
    - kernel / driver 更新策略
    - 安全機制、服務管理、log 預設
    - 文件、社群、商業支援、長期維護
  ]
][
  #card(title: [同一件事，多種方言], icon: [🗣])[
    #set text(size: 0.92em)
    ```bash
    sudo apt install build-essential      # Ubuntu
    sudo pacman -S base-devel             # Arch
    sudo dnf groupinstall "Development Tools"  # Fedora
    ```
  ]
  #v(0.4em)
  #text(size: 0.85em)[選發行版 = 選「要跟誰的品味和維護策略」。]
]

#speaker-note[
  kernel 的本職是資源管理與權限邊界。應用程式想碰硬碟、記憶體、網卡，都得透過 system call 跟 kernel 申請。

  但光有 kernel 什麼都做不了。還需要 bootloader、init system、C library、shell、coreutils、套件管理器、網路工具、編輯器、桌面環境……把這幾百個獨立專案挑版本、整合、打包、測試、持續更新。*發行版賣的就是這個：一組整合決策，加上替這些決策負責的承諾。* 選發行版，其實是在選「我們要跟誰的品味和維護策略」。

  發行版之間差在哪？差在這些決策：

  - 預設採用哪些 system component
  - 使用哪種套件格式與套件管理器
  - 套件版本偏新還是偏穩
  - 更新模式是 rolling release 還是 fixed release
  - kernel 與 driver 的更新策略
  - 安全機制、服務管理、log 系統的預設設定
  - 文件、社群、商業支援與長期維護能力

  這些聽起來抽象，但寫程式時會變得非常具體。同一份教學，Ubuntu 上寫 `apt install build-essential`，到了 Arch 是 `pacman -S base-devel`，Fedora 上是 `dnf groupinstall "Development Tools"`。
]

== 發行版家族

#block[
  #set text(size: 0.74em)
  #table(
    columns: (auto, 1fr, auto, 1fr),
    [家族], [成員與性格], [套件], [ ],
    [Debian 系], [Debian 保守可靠；Ubuntu = Debian 快照 + 硬體支援 + 半年一版], [`.deb`], [穩定與自由軟體傳統],
    [Red Hat 系], [RHEL 賣企業合約；Fedora 是前沿實驗場；Rocky / Alma 補免費相容位], [`.rpm`], [企業機房常客],
    [Arch 系], [簡潔、透明、rolling release，滾壞摸摸鼻子自己修], [`.pkg.tar.zst`], ["I use Arch btw"],
    [特化選手], [Alpine（musl、container 寵兒）、NixOS（宣告式）、Kali（資安工具箱）], [—], [],
  )
]

#v(0.3em)
#callout(kind: "tip", compact: true)[Arch Wiki 是全 Linux 品質最高的文件 —— *就算不用 Arch 也很推薦看 Arch Wiki*。]

#speaker-note[
  認發行版不要背名字，要認家族——就像認人先認姓氏。

  Debian 家族重穩定與自由軟體傳統。Debian 本身保守到有名，穩定版的套件常常「舊得可靠」。Ubuntu 拿 Debian 當基底（它其實是定期從 Debian 的開發分支切快照出來整理的），加上積極的硬體支援、桌面整合、商業支援和固定半年一版的節奏。

  Red Hat 家族是企業機房的常客。RHEL 賣的是長期支援、穩定 ABI 和有人接你電話的商業合約。Fedora 是它的前沿實驗場，很多新技術——systemd、Wayland、PipeWire——都是先在 Fedora 上普及，幾年後全世界跟進。Rocky、AlmaLinux 則是在 CentOS 變質之後補上「免費 RHEL 相容」這個位置的。這家族用 `rpm` 格式和 `dnf` / `yum`。

  Arch 家族是另一種人生哲學：簡潔、透明、rolling release、系統是使用者自己的責任。網路上有個梗叫「I use Arch btw」，嘲諷 Arch 使用者總忍不住告訴別人自己用 Arch——但平心而論，Arch Wiki 是全 Linux 世界品質最高的文件，*就算不用 Arch 也該學會查 Arch Wiki*。代價是滾動更新偶爾會滾壞東西，而修它的人是自己。

  再來幾個特化選手。Alpine 小到只有幾 MB，是 container image 的寵兒，但它用 musl libc 而不是 glibc 。NixOS 用宣告式設定管理整個系統，可重現性極強，學習曲線也極陡。Kali 是資安測試工具的全家桶，定位是測試環境，而不是日常桌面。
]

== 這台機器是什麼？

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  ```bash
  uname -a             # kernel 版本、CPU 架構
  cat /etc/os-release  # 發行版：ID=ubuntu ...
  lsb_release -a
  hostnamectl
  ```
  #v(0.3em)
  #text(size: 0.85em)[兩個指令答的是 *不同層*：同一版 Ubuntu 可以搭不同 kernel —— 正好驗證三層模型。]
][
  #card(tint: palette.amber, title: [套件管理器是一本帳], icon: [📒])[
    #set text(size: 0.85em)
    `apt install git` 不只把 binary 放進 `/usr/bin/git`，還 *記下這個檔案屬於誰、由誰更新*。

    #v(0.3em)
    每種安裝方式都有 *自己的管理邊界*。
  ]
]

#v(0.4em)
#callout(
  kind: "info",
  compact: true,
)[把三層模型放在心裡：後面的桌面、shell、檔案系統、權限、PATH、systemd，全都掛得回這個骨架。]

#speaker-note[
  講了這麼多，用幾個指令把模型落回我們眼前這台機器：

  ```bash
  uname -a
  cat /etc/os-release
  lsb_release -a
  hostnamectl
  ```

  `uname -a` 回答 kernel 版本與 CPU 架構；`/etc/os-release` 回答發行版，例如 `ID=ubuntu`、`VERSION_ID=24.04`。注意這是兩個不同層的答案——同一版 Ubuntu 可以搭不同 kernel，這正好驗證了我們的三層模型。

  而發行版差異最有體感的地方就是套件管理器。Ubuntu / Debian 用 `apt` 和 `.deb`；Fedora / RHEL 用 `dnf` 和 `.rpm`；Arch 用 `pacman`。套件管理器不只是下載器，它做 dependency resolution、版本比對、檔案歸屬追蹤、升級、移除、repository 簽章驗證。我們打 `apt install git`，系統不只把 binary 放進 `/usr/bin/git`，還記下「這個檔案屬於 git 這個 package，未來由它負責更新」。這個「記帳」概念很重要，因為——

  這裡先埋一個伏筆，後面講軟體安裝時會展開：*每種安裝方式都有自己的管理邊界*。`apt install`、`pip install`、`cargo install`、`make install`、Docker，各自管各自的帳本。系統套件管理器知道系統檔案，Python 工具知道 Python environment，Docker 只管 image 裡的世界。檔案壞掉時，能不能回答「這個檔案是誰的、誰負責更新它、要去哪本帳查」，決定了除錯是十分鐘的事還是重灌收場。

  把這三層模型放在心裡，後面講桌面、terminal、shell、檔案系統、權限、PATH、systemd 時，會發現它們都能掛回這個骨架上。
]

= 桌面環境與顯示系統

== 世界上絕大多數的 Linux 沒有螢幕

沿著開機路徑走一遍，看桌面出現得有多*晚*：

#v(0.4em)
#align(center)[
  #pill(tint: palette.rose)[UEFI / BIOS] → #pill(tint: palette.amber)[GRUB] → #pill(tint: palette.teal)[KERNEL + INITRAMFS] → #pill[SYSTEMD（PID 1）] → #pill(tint: palette.rose)[…桌面?]
]

#v(0.5em)
#row(gutter: 1em)[
  #card(tint: palette.teal, title: [到 PID 1 為止], icon: [✅])[
    #text(size: 0.85em)[系統已經*完整*：能跑 process、管檔案、開網路、起 service。]
  ]
][
  #card(tint: palette.iris, title: [伺服器 / 機器人 / NAS], icon: [🤖])[
    #text(size: 0.85em)[一輩子停在這一層，在純文字環境裡活得好好的。]
  ]
][
  #card(tint: palette.amber, title: [桌面], icon: [🖥])[
    #text(size: 0.85em)[很上層、*可拆*的一塊。]
  ]
]

#speaker-note[
  很多人第一次接觸 Linux 是 Ubuntu 桌面，於是自然以為「Linux 就是那個有滑鼠、有視窗、有 dock 的畫面」。這一節要先打破這個印象：桌面在整個系統裡是很上層、很可拆的一塊。*世界上絕大多數的 Linux 根本沒有螢幕*。伺服器、路由器、機器人、家裡的 NAS，全都是純文字環境裡活得好好的 Linux。

  我們順著開機的路徑走一遍，就會看到桌面出現得有多晚。按下電源，firmware 最先跑——現代機器是 UEFI，老機器是 BIOS。UEFI 初始化硬體、找到 bootloader；bootloader（通常是 GRUB）把 Linux kernel 和 initramfs 載進記憶體；kernel 起來後初始化 driver、mount root filesystem，然後啟動第一個 userspace process。現代發行版這個 PID 1 幾乎都是 `systemd`。

  注意，到這裡桌面連影子都沒有，但系統已經是完整的了：能跑 process、管檔案、開網路、起 service。伺服器和機器人上的 Linux，一輩子就停在這一層。
]

== TTY：桌面掛掉時的逃生門

#row(widths: (3fr, 2fr), gutter: 1.2em)[
  名字來自 teletype（真的電傳打字機），現在指 virtual console。

  #v(0.5em)
  現在就試：#kbd[Ctrl] + #kbd[Alt] + #kbd[F3]

  等下記得切回來 (#kbd[F1] / #kbd[F2])

  #v(0.5em)
  #callout(kind: "tip", compact: true)[桌面掛掉時，TTY 往往還活著。]
][
  #card(title: [救援常見劇本], icon: [🚑])[
    #set text(size: 0.85em)
    #step(1) 畫面凍結、 GPU driver 發瘋 ...

    #v(0.3em)
    #step(2) 切到 TTY，登入

    #v(0.3em)
    #step(3) 殺掉出問題的 process、看 log，系統救回來
  ]
]

#speaker-note[
  沒有桌面要怎麼操作？我們有 TTY。這名字來自 teletype——歷史上是真的電傳打字機，一台會打字的機器接在主機上；現在指的是 virtual console。現在就可以按 `Ctrl` + `Alt` + `F3` 試試（等下記得切回來），會看到一個純文字登入畫面。當桌面環境掛掉時，TTY 往往還活著。畫面凍結、GPU driver 發瘋、登入畫面無限循環——切到 TTY，登入，殺掉出問題的 process 或看 log，系統就救回來了。
]

== 桌面環境（DE）是「整合層」

一個 DE 打包了：window manager、panel、launcher、settings daemon、file manager、通知、鎖屏、輸入法、電源管理。

#v(0.4em)
#row(gutter: 1em)[
  #card(tint: palette.iris, title: [GNOME])[
    #text(size: 0.85em)[一致與簡化路線。Ubuntu 預設使用客製化過的 GNOME。]
  ]
][
  #card(tint: palette.teal, title: [KDE Plasma])[
    #text(size: 0.85em)[什麼都能調，自由度很高，適合想控制每個細節的人。]
  ]
][
  #card(tint: palette.amber, title: [XFCE / LXQt])[
    #text(size: 0.85em)[輕量穩定，老機器和遠端桌面的常客。]
  ]
]

#v(0.5em)
#callout(
  kind: "info",
  compact: true,
)[差異都在*使用體驗*，底下仍同一顆 kernel。同一台機器可裝多個 DE，登入時選想要的 session 就好。]

#speaker-note[
  桌面環境（desktop environment）是疊在這之上的整合層。GNOME、KDE Plasma、XFCE、LXQt 都是。一個 DE 通常打包了 window manager、panel、launcher、settings daemon、file manager、通知系統、螢幕鎖定、輸入法、電源管理這一整套。重點是「整合」二字——它不是單一程式，而是一套幫一般使用者把桌面拼好的產品。

  各家取捨不同。GNOME 走一致與簡化路線，Ubuntu 預設就是客製化過的 GNOME。KDE Plasma 什麼都能調，適合想控制每個細節的人。XFCE 輕量穩定，老機器和遠端桌面的常客。要記住的是：這些差異都在使用體驗層，底下跑的是同一顆 kernel。同一台機器可以裝好幾個 DE，登入時選哪個 session 就是哪個體驗。
]

== 另一派玩法：只裝 window manager，自己拼

#block[
  #set text(size: 0.82em)
  #table(
    columns: (auto, 1fr, 1fr),
    [角色], [X11 經典組], [Wayland 人氣組],
    [WM / compositor], [i3（tiling）], [Hyprland（華麗）、sway（i3 後繼）],
    [狀態列], [polybar], [waybar],
    [launcher], [rofi], [wofi / fuzzel],
    [通知 / 桌布], [dunst / feh], [mako / swaybg],
    [截圖 / 鎖屏], [—], [grim + slurp / swaylock],
  )
]

#v(0.3em)
#callout(
  kind: "warn",
  compact: true,
)[但是 Wi-Fi、音量、亮度、輸入法、螢幕分享……全要自己接，壞了無人可怪。

  這類玩法解釋了 Linux 桌面的*可組裝性*，但我們日常研究不用它也完全沒差。]

#speaker-note[
  既然 DE 是整合包，那能不能只拿其中一塊來用？可以。這就是另一派 Linux 桌面玩家的入口：不裝完整 DE，只裝 window manager，其餘元件一塊一塊自己挑，把桌面拼起來。

  window manager 的工作是管理視窗：視窗放哪裡、多大、誰在前面、怎麼切換。傳統桌面多半是 floating window manager，視窗可以自由疊放、拖曳、縮放；tiling window manager 則把螢幕切成不重疊的格子，新視窗自動排進去，靠鍵盤快速切換 layout、workspace 和焦點。X11 陣營最經典的組合長這樣：i3 當 WM，polybar 當狀態列，rofi 當 launcher，dunst 收通知，picom 負責透明和陰影，feh 設桌布。Wayland 陣營這幾年的人氣王是 Hyprland（動畫和視覺效果華麗，客製化空間大），另一路是 sway——i3 的 Wayland 直系後繼，設定檔幾乎相容——搭配 waybar、wofi 或 fuzzel、mako、swaybg，截圖用 grim + slurp，鎖屏用 swaylock 或 hyprlock。r/unixporn 上滿坑滿谷的桌面截圖，九成就是這幾套零件的排列組合。這種工作流很適合整天開 terminal、editor、browser、log viewer 的人，因為它把「整理視窗」這件事從手動拖拉變成快捷鍵和規則。

  但代價也很明確：完整 DE 幫忙處理好的東西，現在全要自己負責。Wi-Fi 要自己拉 nm-applet 或用 iwctl，音量要 pavucontrol 或把 pamixer 綁上快捷鍵，螢幕亮度是 brightnessctl，藍牙是 blueman，中文輸入要自己接 fcitx5，視訊會議的螢幕分享要裝對 xdg-desktop-portal 的實作——少裝一塊就少一個功能，而且壞掉時沒有整合商可以怪，除錯的是自己。知道這些可以很好解釋了 Linux 桌面的可組裝性，但對於我們日常研究來說不知道這些也不影響。
]

== 桌面底下還有一層：顯示系統

display server / compositor：讓程式把畫面畫上螢幕、分發鍵盤滑鼠 input。

#v(0.3em)
#row(gutter: 1em)[
  #card(tint: palette.amber, title: [X11 · 1984], icon: [🕰])[
    #set text(size: 0.85em)
    - network transparency：`ssh -X` 把遠端視窗開在本地
    - `DISPLAY` 環境變數是它的遺產
    - 四十年複雜度 + 安全問題（視窗可互相監聽鍵盤）
  ]
][
  #card(tint: palette.teal, title: [Wayland · 接班], icon: [🌊])[
    #set text(size: 0.85em)
    - compositor 放核心位置
    - 改善安全、HiDPI、觸控、frame timing
    - GNOME / KDE 已預設；截圖、螢幕分享的陣痛是真的
  ]
]

#v(0.4em)
登入畫面是 *display manager*：選使用者、 session。

#speaker-note[
  桌面環境的下面還有一層要分清楚：顯示系統。

  display server 或 compositor 負責讓應用程式把畫面畫到螢幕上，並分發鍵盤、滑鼠、觸控的 input。傳統上這個角色是 X11——X Window System，1984 年的設計。它有一個當年很前衛的特性叫 network transparency，所以可以 `ssh -X` 到遠端機器，把遠端的 GUI 視窗開在自己桌面上。無數教學裡會看到 `DISPLAY` 這個環境變數，那就是 X11 的遺產。

  Wayland 是接班的新協議。X11 四十年累積的複雜度和安全問題（一個經典冷知識：在 X11 底下，任何視窗程式原則上都能監聽使用者打給其他視窗的鍵盤輸入）讓社群決定砍掉重練。Wayland 把 compositor 放到核心位置，改善安全性、HiDPI、觸控和 frame timing。GNOME 和 KDE 都已經預設跑 Wayland 了。不過遷移期的陣痛是真實的：截圖、螢幕分享、自動化腳本過去常依賴 X11 那些「不安全但方便」的能力，所以遇到 GUI 工具行為怪異時，「現在是 X11 還是 Wayland session」是要先確認的事之一。

  那登入畫面又是誰？display manager——GDM、SDDM、LightDM 這些。它讓我們選使用者、打密碼，也讓我們選 session：GNOME on Wayland、GNOME on Xorg、Plasma、i3、sway……選哪個，登入後就活在哪個世界。桌面壞掉時「換一個 session 登入看看」也是很實用的除錯手段。
]

#focus-slide[
  各位手邊有 Linux 開發環境了嗎？
]

== 觀察：我現在活在哪個世界？

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  ```bash
  echo $XDG_CURRENT_DESKTOP  # GNOME / KDE / sway
  echo $XDG_SESSION_TYPE     # x11 / wayland
  echo $DISPLAY              # X11 的座標
  echo $WAYLAND_DISPLAY      # Wayland socket
  loginctl                   # 所有 login session
  ```
][
  #card(tint: palette.iris, title: [對開發者的兩個實戰價值], icon: [🎯])[
    #set text(size: 0.85em)
    #step(1) 遠端伺服器幾乎都是純文字環境 —— SSH 開 GUI 撞上 `DISPLAY` / X forwarding 是必然

    #v(0.4em)
    #step(2) 圖形程式打不開，檢查順序：*session → display protocol → permission → driver*
  ]
]

#speaker-note[
  來，觀察一下我們現在活在哪個世界：

  ```bash
  echo $XDG_CURRENT_DESKTOP
  echo $XDG_SESSION_TYPE
  echo $DISPLAY
  echo $WAYLAND_DISPLAY
  loginctl
  ```

  `XDG_CURRENT_DESKTOP` 會顯示 GNOME、KDE、sway 之類；`XDG_SESSION_TYPE` 常見值是 `x11` 或 `wayland`；`DISPLAY` 是 X11 的座標，`WAYLAND_DISPLAY` 是 Wayland socket 的名字。`loginctl` 可以看目前所有 login session，包括誰從 TTY 登入、誰從遠端進來。

  對開發者來說，這一節的實戰價值有兩個。第一，遠端伺服器幾乎都是純文字環境，SSH 進去想開 GUI 程式，會撞上 `DISPLAY`、X forwarding、permission denied，因為那裡沒有可用的圖形 session。第二，圖形程式打不開時，檢查順序是 session、display protocol、permission、driver。
]

= Terminal 與 Shell

== 黑色視窗裡其實有兩層

#align(center)[
  #pill(tint: palette.rose)[KEYBOARD] → #pill(tint: palette.amber)[TERMINAL EMULATOR] → #pill(tint: palette.teal)[PTY] → #pill[SHELL] → #pill(tint: palette.rose)[PROGRAMS]
]
#v(0.2em)
#align(center)[#text(size: 0.75em, fill: palette.muted)[（螢幕方向反著走同一條線）]]

#v(0.3em)
#row(gutter: 1em)[
  #card(tint: palette.amber, title: [terminal emulator], icon: [🖥], inset: 0.8em)[
    #set text(size: 0.8em)
    桌面上的普通應用程式（GNOME Terminal、Alacritty、Kitty…）。「模擬」當年一人一台的實體終端機：顯示文字、收輸入、處理控制序列。
  ]
][
  #card(tint: palette.iris, title: [shell], icon: [🐚], inset: 0.8em)[
    #set text(size: 0.8em)
    在 terminal「裡面」跑的程式：讀你打的字、解析指令、展開 wildcard、接 pipe 與 redirection、啟動別的程式。
  ]
]

#v(0.3em)
#callout(
  kind: "tip",
  compact: true,
)[`vim` / `less` / `top` crash 後 terminal 壞掉（打字不顯示、畫面異常）？

  盲打 `reset` + #kbd[Enter]
]

#speaker-note[
  接下來這個區分很多人從來沒想過：terminal 和 shell 是兩個東西。平常打開一個黑色視窗就開始打字，其實裡面有兩層。

  terminal emulator 是桌面上的一個普通應用程式——GNOME Terminal、Konsole、Alacritty、Kitty、WezTerm 都是。它的工作是「模擬」傳統終端機：顯示文字、收鍵盤輸入、處理顏色和游標的控制序列，然後接到一個 pseudoterminal（PTY）上。為什麼叫「模擬」？因為它模擬的是真實硬體——當年一人一台鍵盤加螢幕（再早是打字機）接到主機上的那種設備。這段歷史今天還活在系統裡：有些全螢幕終端程式，例如 `vim`、`less`、`top`、`btop`，會暫時把 terminal 切到比較底層的模式，自己接管按鍵、游標和畫面。如果程式 crash，來不及把 terminal mode 還原，可能就會出現打字不顯示、Enter 行為怪掉、畫面刷新異常這些症狀。這時候不用關視窗，盲打一個 `reset` 按 Enter，terminal 會重新初始化，畫面就回魂了。

  shell 則是在 terminal「裡面」跑的程式。它讀我們打的字，解析成指令，展開 wildcard，處理 pipe 與 redirection，然後啟動別的程式。

  所以整條線是：

  ```text
  keyboard -> terminal emulator -> PTY -> shell -> programs
  screen   <- terminal emulator <- PTY <- shell <- programs
  ```
]

== 一行指令，shell 做了多少事

```bash
ls -lah | grep ".py" > files.txt
```

#v(0.3em)
#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #text(size: 0.88em)[
    #step(1) 拆 token：`ls`、`-lah`、pipe、`grep`、字串、redirection

    #v(0.3em)
    #step(2) 生出兩個 process

    #v(0.3em)
    #step(3) 第一個的 stdout 接到第二個的 stdin

    #v(0.3em)
    #step(4) 第二個的 stdout 導進 `files.txt`
  ]
][
  #card(tint: palette.iris, title: [關鍵認知], icon: [💡])[
    #set text(size: 0.85em)
    `ls` 和 `grep` *不知道 pipe 存在* —— 管線是 shell 在啟動它們之前偷偷接好的。

    #v(0.3em)
    UNIX 哲學的具體實現：程式只管讀 stdin 寫 stdout，*組合是 shell 的事*。
  ]
]

#speaker-note[
  來看 shell 到底多會做事。輸入這一行：

  ```bash
  ls -lah | grep ".py" > files.txt
  ```

  短短一行，shell 做了：把 `ls`、`-lah`、pipe、`grep`、字串、redirection 全部拆開；生出兩個 process；把第一個的 stdout 接到第二個的 stdin；再把第二個的 stdout 導進 `files.txt`。注意一個關鍵認知：`ls` 和 `grep` 是外部程式，它們根本不知道 pipe 的存在——*pipe 和 redirection 是 shell 在啟動它們之前，偷偷幫它們接好的水管*。這就是 UNIX 哲學的具體實現：程式只管讀 stdin 寫 stdout，組合是 shell 的事。理解這一點，就理解了為什麼幾百個各自只做一件事的小工具能拼出無限的工作流。
]

== Shell 地雷區

variable、condition、loop、function、exit status、quoting rule 一應俱全。

#v(0.3em)
#card(fill: palette.night, stroke: none, title: [慘案迷因], title-fill: palette.rose, radius: 12pt)[
  #set text(fill: white.transparentize(15%), size: 0.9em)
  `rm -rf "$DIR/"` —— 變數沒設到，展開成 `rm -rf "/"`
]

#v(0.4em)
寫 script 的三個*偏執習慣*：

#step(1) 變數永遠加雙引號 #h(1.5em) #step(2) 動手前先 `echo` 看展開結果 #h(1.5em) #step(3) 寫完丟 `shellcheck`

#speaker-note[
  而且 shell 本身是一個程式語言：variable、condition、loop、function、exit status、quoting rule 一應俱全。這是它強大的地方，也是它坑人的地方——quoting、空白、特殊字元全是地雷。江湖上流傳的慘案是這種：`rm -rf "$DIR/"`，變數沒設到，展開成 `rm -rf "/"`。所以寫 script 值得養幾個偏執的習慣，每一條背後都有屍體：變數永遠加雙引號、動手前先 `echo` 一次看展開結果、寫完丟給 shellcheck 檢查。
]

== Bash: interactive & non-interactive

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  Bash：GNU 的 shell、多數發行版預設，POSIX 相容 + history / completion / array / job control。

  #v(0.3em)
  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  source ~/.bashrc
  for f in *.txt; do
    echo "$f"
  done
  ```
][
  #card(tint: palette.amber, title: [最容易撞牆的區分], icon: [🧱])[
    #set text(size: 0.85em)
    - *interactive*：打開 terminal 手動輸入 → 讀 `~/.bashrc`
    - *non-interactive*：`bash script.sh` → 規則不同
    - login shell 又是另一組（`~/.profile`、`~/.bash_profile`）
  ]
  #v(0.4em)
  #callout(
    kind: "warn",
    compact: true,
  )[「terminal 有這指令、script 裡找不到」九成是*設定寫在不會被讀的檔案*。]
]

#speaker-note[
  Shell 也有很多種，最常見的就是 Bash。它是 GNU 的 shell，長年霸佔多數發行版的預設位置，相容 POSIX shell 的概念，又補上 history、completion、array、job control 這些實用功能。教學文件裡的這些：

  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  source ~/.bashrc
  for f in *.txt; do
    echo "$f"
  done
  ```

  都是 Bash / POSIX 文化的一部分。

  這裡補一個最容易撞牆的區分：interactive shell 和 non-interactive shell。打開 terminal 手動輸入，是 interactive；跑 `bash script.sh`，shell 讀檔案執行，是 non-interactive。兩者讀的 startup file 規則不一樣：`~/.bashrc` 給 interactive Bash，`~/.profile`、`~/.bash_profile` 跟 login shell 有關。先劇透：日後遇到的 PATH 靈異事件——「terminal 裡有這個指令，但 script 裡找不到」「SSH 進去指令就消失」——九成都是「設定寫在某個這種情境下不會被讀的檔案」。後面 PATH 那節我們會把這個結清楚。
]

== Shell 圖鑑

#block[
  #set text(size: 0.85em)
  #table(
    columns: (auto, 1fr, 1fr),
    [Shell], [定位], [常見事項],
    [`zsh`],
    [開發者桌面人氣王（macOS 預設）、completion / prompt 生態豐富],
    [interactive 用 zsh 爽，*script 則寫 Bash*],

    [`fish`], [開箱即用 autosuggestion、syntax highlighting], [語法刻意非 POSIX，網路上的 Bash 片段貼進去常報錯],
    [`dash`], [小而快的純 POSIX；Ubuntu 的 `/bin/sh` 就是它], [`#!/bin/sh` + Bash 語法可能會出錯],
  )
]

#v(0.4em)
#callout(
  kind: "danger",
  compact: true,
)[要用 Bash feature 就明寫 `#!/usr/bin/env bash`。寫 `#!/bin/sh` 只准用 POSIX 語法。]

#speaker-note[
  除了 Bash，市面上還有幾個常見選手。

  zsh 是開發者桌面的人氣王，macOS 現在預設就是它。互動體驗強：completion、prompt 客製、glob 都很豐富，Oh My Zsh、Powerlevel10k 那些華麗的 prompt 生態就是它的。常見的搭配是：*interactive 用 zsh 爽，script 一律寫 Bash*——只要腳本第一行寫 `#!/usr/bin/env bash`，平常用什麼 shell 根本不影響它。

  fish 把友善做到極致，開箱就有 autosuggestion 和 syntax highlighting，但它的語法刻意跟 POSIX 分道揚鑣，所以網路上的 Bash 片段貼進去常常直接報錯。當個人 interactive shell 很棒，進團隊要注意相容性。

  dash 比較少人聽過，但我們天天在用它——Ubuntu 上 `/bin/sh` 指向的就是 dash，一個小而快的純 POSIX shell。這裡有個坑了無數人的經典：script 第一行寫 `#!/bin/sh`，卻在裡面用了 Bash 才有的語法——array、`[[ ... ]]`、`source`——在別人機器上跑得好好的（因為可能別家 `/bin/sh` 是 Bash），到 Ubuntu 上就爆。這個差異是 Ubuntu 二十年前左右為了開機速度改的，至今每年還在收割新的受害者。規則很簡單：*要 Bash 就明寫 `#!/usr/bin/env bash`，寫 `#!/bin/sh` 就只准用 POSIX 語法*。
]

= 檔案系統

== Everything is a file

#row(widths: (2fr, 3fr), gutter: 1.2em)[
  UNIX 的標誌性設計哲學：

  學會*讀寫檔案*，就能觀察和操作幾乎整個系統。

  #v(1.3em)
  #set text(size: 0.85em)
  - 鍵盤滑鼠硬碟 → `/dev` 裡是檔案
  - process 狀態 → `/proc` 裡是檔案
  - kernel / 硬體狀態 → `/sys` 裡是檔案
][
  #card(tint: palette.teal, title: [預設工具], icon: [📊])[
    #set text(size: 1.2em)
    ```bash
    ls /proc/<pid>/fd   # 它開了哪些檔案
    cat /proc/cpuinfo   # CPU 資訊
    ```
    #v(0.2em)
    檔案系統本身就是系統的儀表板。
  ]
]

#speaker-note[
  UNIX 世界有一句老話：*everything is a file*。這是其標誌性的設計哲學之一。一般檔案是檔案，目錄是檔案的組織方式，鍵盤滑鼠硬碟在 `/dev` 裡是檔案，process 狀態在 `/proc` 裡以檔案形式呈現，kernel 和硬體狀態在 `/sys` 裡也是檔案。這個設計的威力在於：只要學會讀寫檔案這一套動作，就能觀察和操作幾乎整個系統。想看某個 process 開了哪些檔案？`ls /proc/<pid>/fd`。想看 CPU 資訊？`cat /proc/cpuinfo`。不用裝任何工具，檔案系統本身就是系統的儀表板。
]

== 一棵樹，沒有 `C:\` —— 全靠 mount 拼起來

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  根是 `/`，*只有一棵樹*。那我第二顆硬碟去哪了？被 *mount* 進樹裡了。

  不同磁碟、分割區、網路 / 虛擬檔案系統，全接到某個目錄上，組成單一 namespace。

  #v(0.3em)
  ```bash
  mount ; findmnt   # 目前的 mount tree
  df -h             # 各 filesystem 容量
  lsblk             # block device 與分割區
  ```
][
  #card(tint: palette.amber, title: [鬧鬼現場], icon: [👻])[
    #set text(size: 0.85em)
    「檔案怎麼不見了／怎麼多出來了」——

    #v(0.3em)
    mount 可以把原本目錄裡的東西 *蓋住*，unmount 之後又冒出來。

    #v(0.3em)
    先 `findmnt` 確認自己站在哪個 filesystem 上。
  ]
]

#speaker-note[
  Linux 檔案系統是一棵樹，根是 `/`——注意，只有一棵。從 Windows 過來最需要轉的觀念就是這個：沒有 `C:\`、`D:\`。那第二顆硬碟去哪了？被 mount 進樹裡了。不同磁碟、分割區、網路檔案系統、虛擬檔案系統，全都接到這棵樹的某個目錄上，組合成單一 namespace。我們看到的 `/home`、`/mnt/data`、`/proc` 可能來自完全不同的裝置，但路徑外觀上毫無破綻。

  mount 是理解 Linux filesystem 的關鍵動詞——把某個 filesystem 接到樹上的某個 mount point。觀察工具：

  ```bash
  mount
  findmnt
  df -h
  lsblk
  ```

  `lsblk` 看 block device 與分割區，`findmnt` 看目前的 mount tree，`df -h` 看各 filesystem 的容量。插 USB、掛外接硬碟、用 Docker volume、連 NFS，背後全是 mount。遇到「檔案怎麼不見了／怎麼多出來了」這類靈異現象，先 `findmnt` 確認自己站在哪個 filesystem 上——因為 mount 可以把原本目錄裡的東西「蓋住」，unmount 之後又冒出來，不知道這個機制的話真的像鬧鬼。
]

== 目錄慣例

#row(widths: (1fr, 1fr), gutter: 1.5em)[
  #set text(size: 0.78em)
  #table(
    columns: (auto, 1fr),
    [路徑], [住著什麼],
    [`/bin` `/usr/bin`], [一般使用者可執行程式],
    [`/sbin` `/usr/sbin`], [系統管理程式],
    [`/etc`], [系統設定檔],
    [`/home` `/root`], [家目錄（一般 / root）],
    [`/var`], [會變動的資料：log、cache、db state],
    [`/tmp`], [暫存，重開機通常就沒],
    [`/opt`], [第三方巨獸（CUDA、ROS）],
  )
][
  #set text(size: 0.78em)
  #table(
    columns: (auto, 1fr),
    [路徑], [住著什麼],
    [`/usr`], [多數 userland 程式、library、文件],
    [`/dev`], [device file],
    [`/proc` `/sys`], [process / kernel 的虛擬檔案系統],
    [`/run`], [開機後的 runtime state(socket、pid)],
  )
  #v(0.4em)
  #card(tint: palette.iris, title: [反射動作], inset: 0.7em)[
    - 設定 → `/etc`
    - log → `/var/log`
    - 個人設定 → `$HOME` dotfiles
    - 硬碟滿了先懷疑 → `/var`
  ]
]

#speaker-note[
  目錄的命名有五十年的慣例，這套慣例本身就是一張除錯地圖：

  - `/bin`、`/usr/bin`：一般使用者可執行程式
  - `/sbin`、`/usr/sbin`：系統管理相關程式
  - `/etc`：系統設定檔（什麼服務的設定都先來這裡翻）
  - `/home`：一般使用者家目錄
  - `/root`：root 使用者家目錄
  - `/var`：會變動的資料，例如 log、cache、spool、database state
  - `/tmp`：暫存檔，重開機通常就沒了
  - `/usr`：多數 userland 程式、library、文件與資源
  - `/opt`：第三方大型軟體的地盤（CUDA、ROS 這些巨獸常住這）
  - `/dev`：device file
  - `/proc`：process 與 kernel 狀態的虛擬檔案系統
  - `/sys`：硬體、driver、kernel object 的虛擬檔案系統
  - `/run`：開機後產生的 runtime state，例如 socket、pid file

  為什麼要記這個？因為它直接決定找東西的效率。設定檔？`/etc`。log？`/var/log` 或 `journalctl`。使用者自己的設定？`$HOME` 底下的 dotfiles。service 的 socket？`/run`。硬碟滿了先懷疑誰？`/var`。靠這套慣例，到一台從沒碰過的機器上，五分鐘內就能摸清狀況。
]

== 路徑與基本操作

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  ```bash
  pwd                  # 我在哪
  ls -lah              # 權限、owner、隱藏檔
  cd /path/to/dir
  mkdir -p build/logs  # 一口氣建多層
  cp source target
  mv old new
  rm file
  find . -name "*.py"  # 找「檔案」
  ```
  #text(size: 0.8em)[找「檔案內容」用 `grep` / `rg` —— 分工要清楚。]
][
  #text(size: 0.88em)[
    - *absolute*：從 `/` 開始
    - *relative*：相對目前工作目錄；`.` 這裡、`..` 上層、`~` home
  ]
  #v(0.3em)
  #callout(
    kind: "warn",
    compact: true,
  )[relative path 相對的是 *process 的工作目錄*，不是 *script 所在位置*。]
  #v(0.3em)
  #callout(kind: "danger", compact: true)[打 `rm -rf` 前停一拍。不放心就加 `-v` 看它刪什麼。]
]

#speaker-note[
  路徑分 absolute 和 relative。absolute 從 `/` 開始，例如 `/home/rvl/project/main.py`；relative 相對於目前工作目錄。`.` 是這裡，`..` 是上一層，`~` 由 shell 展開成目前使用者的 home。順帶記住這件事：*relative path 是相對於「process 的工作目錄」，不是相對於「script 所在位置」*——這個誤解製造的 bug，每個人未來都會親手寫出好幾個，先打預防針。

  基本指令要練到不經大腦：

  ```bash
  pwd
  ls -lah
  cd /path/to/dir
  mkdir -p build/logs
  cp source target
  mv old new
  rm file
  find . -name "*.py"
  ```

  `pwd` 回答現在在哪，`ls -lah` 看權限、owner、大小和隱藏檔，`mkdir -p` 一口氣建多層目錄。`find` 是在 filesystem tree 裡找「檔案」，找「檔案內容」則用 `grep` 或 `rg`——這兩者的分工要清楚。另外一個保命建議：`rm` 沒有資源回收桶，刪了就是刪了。打 `rm -rf` 之前停一拍，看清楚路徑再按 Enter；不放心就用 `rm -rfv target` 讓它把刪除項目印出來。注意 `-v` 不是互動確認，只是 verbose；真的要逐一問你才是 `-i`。
]

== 每個檔案都帶著 metadata

#align(center)[
  #box(inset: 0.6em)[
    #text(font: ("JetBrainsMono NF", "DejaVu Sans Mono"), size: 1.6em)[
      #text(fill: palette.rose, weight: "bold")[-]#text(fill: palette.iris, weight: "bold")[rw-]#text(
        fill: palette.teal,
        weight: "bold",
      )[r--]#text(fill: palette.amber, weight: "bold")[r--]
    ]
  ]
]
#align(center)[
  #pill(tint: palette.rose)[類型：`-` 檔案 `d` 目錄 `l` symlink]
  #pill[OWNER rwx]
  #pill(tint: palette.teal)[GROUP rwx]
  #pill(tint: palette.amber)[OTHERS rwx]
]

#v(0.4em)
owner、group、size、mtime、inode —— `stat` 全看得到。

#v(0.3em)
#callout(
  kind: "warn",
  compact: true,
)[對 *目錄* 來說，execute 的真正意義是 *traverse*（能不能穿過）。

  路徑上某層目錄沒給 x，檔案本身有 r 也讀不到。]

#speaker-note[
  每個檔案還帶著 metadata：owner、group、permission、size、mtime、inode。`ls -l` 第一欄那串 `-rw-r--r--`，第一個字元是類型——`d` 是 directory，`-` 是一般檔案，`l` 是 symlink——後面九個字元三個一組，分別是 owner、group、others 的 read、write、execute。這串密碼下一節會完整解開。

  先預告一個目錄權限的反直覺點：對目錄來說，execute 不是「執行」，是 *traverse*——能不能「穿過」這個目錄。就算對檔案本身有 read 權限，路徑上某層目錄沒給 execute，照樣讀不到。這是權限除錯的常見盲點。
]

== Symlink、dotfiles，與檔案系統的「型號」

#row(gutter: 1em)[
  #card(tint: palette.iris, title: [symlink], icon: [🔗])[
    #set text(size: 0.8em)
    ```bash
    ln -s target link_name
    readlink link_name
    ```
    版本切換頻繁，但只需要換 symlink。方便，不過要注意每可能指歪。
  ]
][
  #card(tint: palette.teal, title: [dotfiles], icon: [🫥])[
    #set text(size: 0.8em)
    檔名以 `.` 開頭就隱藏，純粹只是命名慣例（源自 `ls` 一個太寬鬆的判斷）。

    #v(0.3em)
    把 dotfiles 放進 git repo，換機器一拉就是熟悉環境。
  ]
][
  #card(tint: palette.amber, title: [型號], icon: [💾])[
    #set text(size: 0.8em)
    本機 ext4 / xfs / btrfs、隨身碟 exFAT / FAT32、網路 NFS。

    #v(0.3em)
    *路徑長得一樣，底層行為可能不同* —— FAT32 沒有權限、沒有 symlink，不是壞了。
  ]
]

#speaker-note[
  symlink 是日常必備工具。symbolic link 是一個「指向另一個 path」的檔案，像捷徑，但在 filesystem 語意裡更根本：

  ```bash
  ln -s target link_name
  readlink link_name
  ```

  系統裡到處都是它。`/usr/bin/python3` 很可能是個 symlink，指向某個實際版本；很多工具的「版本切換」就是換一根 symlink 的指向。方便，但也是除錯陷阱：以為在執行某個檔案，其實中間隔了一串 symlink，每一跳都可能指歪。

  隱藏檔的規則簡單到好笑：檔名以 `.` 開頭就隱藏。就這樣，純命名慣例，沒有什麼隱藏屬性。（冷知識：這其實源自幾十年前 `ls` 為了跳過 `.` 和 `..` 寫的一個判斷太寬鬆，一個 bug 變成了全世界的 feature。）`ls -a` 就看得到。`.bashrc`、`.profile`、`.config` 全是這種 dotfiles。把自己的 dotfiles 放進 git repo，換機器一拉就是熟悉的環境——這個習慣值得早點養成。

  filesystem 還有「型號」之分：本機常見 ext4、xfs、btrfs，USB 隨身碟常是 exFAT 或 FAT32，網路上有 NFS。它們支援的權限模型、大小限制、效能特性都不同。初學階段記一個原則就好：*路徑長得一樣，底層行為可能不同*。第一次把檔案拷到 FAT32 隨身碟、發現權限全消失 symlink 全壞掉的時候，就會想起這句話——那不是壞了，是 FAT32 根本沒有這些概念。
]

= 使用者、群組與權限

== root 是什麼？

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  1970 年代：一台昂貴主機、幾十人分時共用 → 系統必須知道 *這是誰、他能碰什麼*。

  #v(0.3em)
  時至今日就算電腦只有一個人用，照樣運轉同樣的模型。

  #v(0.3em)
  #text(size: 0.88em)[每個使用者一個 *uid*、每個群組一個 *gid*；名字給人看，*kernel 認數字*。]
][
  #card(fill: palette.night, stroke: none, radius: 12pt, title: [uid 0 = root], title-fill: palette.rose)[
    #set text(fill: white.transparentize(15%), size: 0.88em)
    root 不是「權限比較多」的使用者，

    是「*權限檢查對他不生效*」的使用者。

    #v(0.4em)
    拿到 root = 拿到整台機器。

    正確態度：*敬而遠之*，需要時短暫借用。
  ]
]

#speaker-note[
  1970 年代主機時代：一台昂貴的主機，幾十個人分時共用，系統必須知道「這是誰、他能碰什麼」。今天就算整台筆電只有一個人用，這套模型仍然運轉著，而且是我們每天撞到的各種 `Permission denied` 的總根源。

  先建立身分模型。每個使用者有一個 uid，每個群組有一個 gid，名字只是給人看的，kernel 認的是數字。這裡有一個全系統最重要的特例：*uid 0，也就是 root*。root 不是「權限比較多的使用者」，而是「權限檢查對他不生效」的使用者——kernel 遇到 uid 0，大多數檢查直接放行。這就是為什麼拿到 root 等於拿到整台機器，也是為什麼對 root 的正確態度是敬而遠之：平常用一般帳號，需要時才短暫借用 root 的力量。
]

== 群組，權限的批發機制

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  ```bash
  whoami
  id        # uid、gid、所有附屬群組
  groups
  ```
  #v(0.3em)
  與其一個個使用者授權，不如把權限給群組、再把人加進群組：

  ```bash
  sudo usermod -aG dialout $USER
  ```
  #text(
    size: 0.82em,
  )[
    - `/dev/ttyUSB0` 代表透過 USB 介面連接至電腦的「USB 轉序列埠」裝置，常屬於 `dialout`
    - Docker 想要設置為免 sudo ，要把自己加進 `docker` 群組
  ]
][
  #callout(kind: "danger", compact: true)[`-aG` 忘了 `a`（append）→ 附屬群組 *全部洗掉*。]
  #v(0.35em)
  #callout(kind: "warn", compact: true)[群組變更要*重新登入*才生效。]
  #v(0.35em)
  #callout(kind: "info", compact: true)[加入 `docker` 群組 ≈ 免密碼 root。]
]

#speaker-note[
  先看看自己是誰：

  ```bash
  whoami
  id
  groups
  ```

  `id` 會列出 uid、gid 和所有附屬群組。群組是權限的批發機制——與其一個一個使用者授權，不如把權限給群組，再把人加進群組。這在開發上有非常實際的場景：之後接機器人的 USB 裝置，`/dev/ttyUSB0` 的 group 通常是 `dialout`，不在這個群組就打不開它；用 Docker 不想每次 sudo，就把自己加進 `docker` 群組。指令是：

  ```bash
  sudo usermod -aG dialout $USER
  ```

  兩個容易吃虧的細節：第一，`-aG` 的 `a` 是 append，忘了加 `a` 會把原本的附屬群組全部洗掉——這是經典事故。第二，群組變更要*重新登入才生效*，改完發現沒用不要慌，先登出。另外補一句誠實的警告：把自己加進 `docker` 群組，安全上約等於給自己免密碼 root，因為 Docker 能 mount 整個根目錄。方便和風險是同一件事的兩面，知道自己在交換什麼就好。
]

== 解碼 rwx

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  檢查順序：

  - 是 owner → 用第一組
  - 在 group → 第二組
  - 都不是 → 第三組

  *只用命中的那組*。

  #v(0.3em)
  r=4、w=2、x=1

  #set text(size: 0.85em)
  #table(
    columns: (auto, auto, 1fr),
    [數字], [展開], [慣例用途],
    [`755`], [`rwxr-xr-x`], [執行檔、目錄],
    [`644`], [`rw-r--r--`], [一般檔案],
    [`777`], [`rwxrwxrwx`], [🚫#strike[布瑠部，由良由良...]],
  )
][
  #callout(kind: "danger", title: [關於 chmod 777], compact: true)[
    意思是「這台機器上*任何程式*都能改寫這個檔案」，基本等同於把門拆了。
  ]
  #v(0.4em)
  正確動作永遠是搞清楚*誰需要什麼權限*，

  `chown` 調 owner、`chmod` 給最小必要權限。

  #v(0.3em)
  ```bash
  chmod 644 file
  chown user:group file
  umask   # 新檔案的預設權限遮罩
  ```
]

#speaker-note[
  接著把上一節那串密碼解開。`ls -l` 看到 `-rwxr-xr--`：三個一組，依序是 owner、group、others 的 read、write、execute。系統檢查的順序是：身分是 owner 就用第一組，不是 owner 但在 group 裡就用第二組，都不是就用第三組——*只匹配一組，不會疊加*。

  權限還有一套數字寫法，是全世界文件的通用語：r=4、w=2、x=1，一組加總一個數字。`chmod 755` 就是 `rwxr-xr-x`，`chmod 644` 就是 `rw-r--r--`。無數教學裡都會看到這些數字，755 給執行檔和目錄、644 給一般檔案，這兩個組合幾乎是本能。至於 `chmod 777`——網路教學的萬能膏藥，「權限有問題就 777」——直說：*這是投降，不是解法*。777 的意思是「這台機器上任何程式都能改寫這個檔案」，那不是修好權限，是把門拆了。正確的動作永遠是搞清楚「誰需要什麼權限」，用 `chown` 調 owner、用 `chmod` 給最小必要權限。

  操作工具就這三支：

  ```bash
  chmod 644 file
  chown user:group file
  umask
  ```

  `umask` 是新檔案的預設權限遮罩，解釋了「為什麼新建的檔案權限是 644」這個疑問。`chown -R` 遞迴改整棵樹的 owner 時手要穩，路徑打錯的 `chown -R` 慘案在系統管理界是有名有姓的事故類型。
]

== 三個特殊權限位

#row(gutter: 1em)[
  #card(tint: palette.rose, title: [setuid · `s`], icon: [🎭])[
    #set text(size: 0.8em)
    `passwd` 憑什麼寫 `/etc/shadow`？執行時*暫時以檔案 owner（root）身分跑*。

    #v(0.3em)
    最精巧也最危險的機關。很多提權漏洞出在這。
  ]
][
  #card(tint: palette.amber, title: [sticky · `t`], icon: [📌])[
    #set text(size: 0.8em)
    `ls -ld /tmp` 尾巴的 `t`：大家都能寫，但*只有 owner 能刪自己的檔案*。

    #v(0.3em)
    不然共用 /tmp 大家互刪，天下大亂。
  ]
][
  #card(tint: palette.teal, title: [setgid（目錄）], icon: [👥])[
    #set text(size: 0.8em)
    新檔案 *繼承目錄的 group*。

    #v(0.3em)
    共用專案目錄常用。
  ]
]

#v(0.5em)
#callout(kind: "tip", compact: true)[看到權限欄出現 `s` 和 `t`，要知道是什麼就好。]

#speaker-note[
  再講三個特殊權限位，這是分辨「背過權限」和「懂權限」的地方。第一個是 setuid。先想一個問題：改密碼要寫入 `/etc/shadow`，而那個檔案一般使用者根本不能讀，那 `passwd` 指令憑什麼成功？去看 `ls -l /usr/bin/passwd`，權限裡有個 `s`——setuid bit，意思是「執行這個程式時，暫時以檔案 owner（root）的身分跑」。這是 UNIX 設計裡最精巧也最危險的機關之一，很多提權漏洞就出在 setuid 程式寫得不夠小心。第二個是 sticky bit：`ls -ld /tmp` 最後有個 `t`，意思是「這個目錄大家都能寫，但只有檔案 owner 能刪自己的檔案」——不然共用的 /tmp 裡大家可以互刪檔案，天下大亂。第三個 setgid 在目錄上會讓新檔案繼承目錄的 group，共用專案目錄常用。這三個不用急著全記住，但看到權限欄裡出現 `s` 和 `t` 時，要知道那是機關，不是亂碼。
]

== sudo：有紀錄的借用，不是變身

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #card(title: [`su` vs `sudo`], icon: [⚖])[
    #set text(size: 0.85em)
    `su`：*變身*成 root，然後一直是 root。

    `sudo`：*借一下力量*，用完就還。
  ]
  #v(0.4em)
  #text(size: 0.85em)[
    sudo 不共享 root 密碼、每條指令有 log、`/etc/sudoers` 可細分授權。
  ]
][
  #card(tint: palette.amber, title: [品味判斷], icon: [🧘], inset: 0.8em)[
    #set text(size: 0.8em)
    看到 `Permission denied` 就無腦補 sudo —— *最該戒掉的反射*。

    #v(0.25em)
    - 裝系統套件、動 `/etc`、開 1024 以下 port → 合理
    - 在自己 home 寫檔要 sudo → *有東西壞了*，修那個
  ]
  #v(0.35em)
  #callout(kind: "danger", compact: true)[`sudo pip install` 是禁忌......]
]

#speaker-note[
  最後講 sudo。`sudo` 的意思是「以另一個身分（預設 root）執行這一條指令」。它跟 `su` 的差別是哲學性的：`su` 是「變身成 root 然後一直是 root」，`sudo` 是「借一下力量，用完就還」。現代的最佳實務全面倒向 sudo，因為它有三個優點：不用共享 root 密碼、每條指令都有 log 可查、權限可以在 `/etc/sudoers` 裡細分到「這個人只能 sudo 這幾條指令」。順帶一提，改 sudoers 永遠用 `visudo` 不要直接編輯——它會先做語法檢查，因為 sudoers 寫壞的下場是*全機沒有人能 sudo*，那真的會叫天天不應。

  關於 sudo 還有一組品味判斷，比背指令重要：看到 `Permission denied` 就無腦補 `sudo` 重打一次，是最該戒掉的反射動作。先想一秒：這個操作*應該*需要 root 嗎？裝系統套件、動 `/etc`、開 1024 以下的 port——合理，sudo。但在自己 home 目錄下寫檔案要 sudo？那代表有東西壞了（八成是之前哪次 sudo 跑了不該 sudo 的東西，把檔案 owner 變成 root），該修的是那個，不是再疊一層 sudo。特別點名一個下一節會展開的大坑：*`sudo pip install` 是禁忌*——它會拿 root 身分把檔案寫進系統 Python 的地盤，跟 apt 的帳本打架，是無數「Python 環境爛掉」慘案的第一因。

  收斂模型：每個 process 都帶著一個身分（uid + gids）在跑，每個檔案都掛著一張門禁規則（owner/group/others × rwx），kernel 在每次存取時對照兩者。root 是免檢通道，sudo 是有紀錄的借用。權限問題的除錯路徑永遠是同一條：`id` 看我是誰，`ls -l` 看規則是什麼，再想「該改的是我的群組，還是檔案的權限」。
]

= 套件管理與軟體安裝

== 1990 年代：dependency hell

當年的標準發行方式：source tarball —— 下載、解壓、`./configure && make && make install`。

#v(0.3em)
#row(gutter: 1em)[
  #card(tint: palette.rose, title: [致命傷一：沒有紀錄], icon: [🕳])[
    #set text(size: 0.85em)
    檔案散進系統各處，沒人知道哪個檔案屬於哪個軟體 —— 移除靠猜、升級靠緣分。
  ]
][
  #card(tint: palette.rose, title: [致命傷二：依賴人肉追], icon: [⛓])[
    #set text(size: 0.85em)
    A 要 libB 1.2 以上、libB 又依賴 libC…… 追錯一層就編不過。
  ]
]

#v(0.5em)
發行版套件系統的解法：帶 metadata 的 *package* ＋ 記錄檔案歸屬的 *資料庫* ＋ 集中發行、簽章驗證的 *repository*。

#speaker-note[
  裝軟體是 Linux 上最混亂的領域，但這個亂有清楚的來龍去脈，先把故事講完，混亂就會變成秩序。

  回到 1990 年代。當時軟體發行的標準形式是 source tarball：下載、解壓、`./configure && make && make install`。這個流程有兩個致命傷。第一，裝完沒有任何紀錄——檔案散進系統各處，沒人知道哪個檔案屬於哪個軟體，移除靠猜、升級靠緣分。第二，軟體之間有依賴——A 需要 libB 1.2 以上，libB 又依賴 libC——全部要人肉追，追錯一層就編不過或跑不動。這個時代的痛苦有專有名詞：dependency hell。

  發行版的套件系統就是為了解決這兩個問題發明的：把軟體做成帶 metadata 的 package，宣告名字、版本、依賴；用資料庫記錄每個檔案的歸屬；用 repository 集中發行、用簽章驗證來源。
]

== 那為什麼今天還是亂？

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #card(tint: palette.iris, title: [套件系統要的：系統整合], icon: [🏛])[
    #set text(size: 0.85em)
    全機一致、穩定、可維護 —— 版本由發行版決定、全機只有一份。
  ]
][
  #card(tint: palette.amber, title: [開發要的：剛好相反], icon: [🧪])[
    #set text(size: 0.85em)
    要新版本、要一個專案一個版本、要不用 root 就能裝。
  ]
]

#v(0.4em)
於是各語言生態長出自己的套件管理器 —— *每套各自合理，但誰也不認得別套的帳*。

#v(0.3em)
#quote-card[今天的亂，來自*好幾套各自沒錯的系統思路疊在同一個 filesystem 上*。]

#speaker-note[
  那為什麼今天還是亂？因為套件系統的設計目標是*系統整合*：全機一致、穩定、可維護——版本由發行版決定、全機只有一份。而開發的需求剛好相反：要新版本、要一個專案一個版本、要不用 root 就能裝。於是許多程式語言生態長出自己的套件管理器，每一套各自都是合理的，但每一套都不認得別套的帳。今天的「套件管理之亂」不是誰做錯了什麼，是*好幾套各自正確的系統疊在同一個 filesystem 上*。所以貫穿本節的鑰匙，就是前面埋的那個伏筆：*每一種安裝方式都是一本獨立的帳本，管理各自的地盤。出事時的問題永遠是：這個檔案記在誰的帳上？*
]

== deb & dpkg

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  `.deb` 只是一個封存檔，拆開兩塊：

  - *control*：metadata —— 名字、版本、依賴、preinst / postinst 維護腳本
  - *data*：真正要鋪進 `/` 的檔案樹

  ```bash
  dpkg-deb -I some.deb  # 看 metadata 與依賴
  dpkg-deb -c some.deb  # 看檔案會鋪到哪
  ```
][
  #card(title: [dpkg 做三件事], icon: [⚙])[
    #set text(size: 0.85em)
    鋪檔案 → 登記進 `/var/lib/dpkg` 資料庫 → 跑維護腳本
  ]
  #v(0.4em)
  #card(tint: palette.amber, title: [和兩個重要的「不會」])[
    #set text(size: 0.85em)
    *不會上網下載、不會解依賴*。777

    `dpkg -i` 卡依賴，正是分工到此為止的表現。
  ]
]

#speaker-note[
  先拆這門課天天用的一套：Debian 系的 deb + dpkg + apt。

  一個 `.deb` 檔本身只是一個封存檔，可以直接拆開看，裡面主要兩塊：control（metadata——套件名、版本、依賴清單，加上 preinst/postinst 這些安裝前後要跑的維護腳本）和 data（真正要鋪進 `/` 底下的檔案樹）：

  ```bash
  dpkg-deb -I some.deb    # 看 metadata 與依賴
  dpkg-deb -c some.deb    # 看它會把哪些檔案鋪到哪裡
  ```

  `dpkg` 是低階安裝器。給它一個 .deb，它做三件事：把 data 鋪進 filesystem、把每個檔案登記進 `/var/lib/dpkg` 的資料庫、執行維護腳本。同樣重要的是它的兩個「不會」：*不會上網下載，也不會解依賴*——依賴不滿足就直接停在半路。所以 `sudo dpkg -i some.deb` 常見卡在依賴錯誤，那不是壞掉，是 dpkg 的分工本來就到此為止。
]

== apt

```bash
sudo apt update              # 只更新套件索引，不升級任何軟體
sudo apt upgrade             # 真正升級
sudo apt install btop        # 解依賴、下載、驗簽，最後交給 dpkg
sudo apt install ./some.deb  # 對本地 deb 也能順便解依賴
dpkg -L btop                 # 查帳：這個套件擁有哪些檔案
dpkg -S /usr/bin/btop        # 反查：這個檔案屬於哪個套件
```

#v(0.3em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #callout(kind: "tip", compact: true)[`dpkg -i` 的殘局 → `sudo apt -f install` 收拾。]
][
  #callout(kind: "info", compact: true)[雙向查帳，套件系統的核心價值。限制也同源：版本偏舊、全機一份。]
]

#speaker-note[
  `apt` 是站在 dpkg 上面的高階層：管理 repository 清單（`/etc/apt/sources.list` 那一家子）、下載套件索引、做 dependency resolution、驗證簽章，最後把整批 .deb 按正確順序餵給 dpkg 執行。兩層拆開之後，很多日常指令的行為就說得通了：

  ```bash
  sudo apt update              # 只更新套件索引，不升級任何軟體
  sudo apt upgrade             # 真正升級
  sudo apt install btop        # 解依賴、下載、驗簽，最後交給 dpkg
  sudo apt install ./some.deb  # 對本地 deb 也能順便把依賴解掉
  dpkg -L btop                 # 查帳：這個套件擁有哪些檔案
  dpkg -S /usr/bin/btop        # 反查：這個檔案屬於哪個套件
  ```

  `apt update` 不更新軟體、只抄一份最新目錄，這個常見誤會用兩層模型看就很自然——索引是 apt 層的事。`dpkg -i` 卡住的殘局可以用 `sudo apt -f install` 收拾，因為 apt 看得懂 dpkg 資料庫裡「裝到一半」的狀態，會把缺的依賴補齊。而 `dpkg -L` / `dpkg -S` 這種雙向查帳，就是套件系統的核心價值：每個檔案有歸屬、有人負責更新、可以乾淨移除。它的限制也來自同一個設計：版本由發行版決定，通常偏舊，而且全機共用一份，沒辦法同時要兩個版本。
]

== 語言生態（1）：pip 的事故現場

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  pip 和 apt *都認為自己管 Python 套件*，歷史還寫同一片目錄。當我們 `sudo pip install` 之後就可能發生兩本帳對不上的情況，恭喜你的環境就出事了。

  #v(0.3em)
  #callout(kind: "info", compact: true)[新版 Ubuntu 的 `externally-managed-environment` 錯誤，*正是在擋事故*。]

  #v(0.3em)
  正解只有一條：*Python 永遠裝在 venv 或使用者層級*。
][
  ```bash
  uv venv               # 專案內建立隔離環境
  uv add numpy          # 裝進環境，跟系統無關
  uv tool install ruff  # 全域工具，各住一個私有環境
  ```
  #v(0.2em)
  #text(size: 0.82em)[
    `uv tool`：工具裝進獨立環境、指令 symlink 到 `~/.local/bin` 帳本齊全：`list` / `upgrade` / `uninstall`。

    這門課本人推薦使用 `uv`，不過很多研究會偏好用 `conda`。
  ]
]

#speaker-note[
  以上是系統級的世界。接下來是使用者層級的五花八門，它們的共同動機都是繞開「全機一份、版本偏舊」的限制，但彼此之間有微妙差異，值得分開看。

  `pip` 先講，因為它的事故最多。pip 和 apt 都認為自己管理 Python 套件，而且歷史上寫的是同一片目錄——一旦 `sudo pip install` 進系統目錄，apt 下次更新 python3 相關套件時兩本帳對不上，環境就開始崩。這個問題嚴重到 Python 社群直接改了規則：新版 Ubuntu 對系統 Python 跑 `pip install` 會吐 `externally-managed-environment` 錯誤拒絕執行——不是壞掉，是在擋事故。正解只有一條：*Python 的東西永遠裝在 virtual environment 或使用者層級*。這門課我個人推薦用 `uv` 管理隔離環境，不過很多研究會偏好 `conda`：

  ```bash
  uv venv                 # 專案內建立隔離環境
  uv add numpy            # 裝進這個環境，跟系統無關
  uv tool install ruff    # 全域工具，但每個工具各住一個私有環境
  ```

  `uv tool install` 的設計值得看一眼：每個工具裝進自己的獨立環境，只把指令 symlink 到 `~/.local/bin`（記住這個路徑，下一節講 PATH 時它是主角），而且有完整的帳——`uv tool list`、`uv tool upgrade`、`uv tool uninstall` 都有。
]

== 語言生態（2）：cargo 的世界

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #card(title: [`cargo install`], icon: [🦀])[
    #set text(size: 0.85em)
    抓原始碼 → 本機編譯 → binary 進 `~/.cargo/bin`。

    Rust binary 幾乎不依賴外部函式庫，不需要隔離環境。帳用 `cargo install --list` 查，升級要自己重跑。
  ]
][
  #card(tint: palette.teal, title: [很類似的其他語言生態], icon: [👪])[
    #set text(size: 0.85em)
    `npm install -g`、`go install` 是變體。

    共同精神：*裝在 home、不碰系統地盤、不需要 sudo*。
  ]
]

#v(0.5em)
#callout(kind: "danger", compact: true)[看到教學對 *語言套件* 下 sudo 不要傻傻照做。]

#speaker-note[
  `cargo install` 相似但更簡單粗暴：從 crates.io 抓原始碼、在本機編譯、把 binary 放進 `~/.cargo/bin`。Rust binary 幾乎不依賴外部函式庫，所以不需要隔離環境；帳用 `cargo install --list` 查，但升級要自己重跑一次 install。`npm install -g`、`go install` 是同一家族的變體。這一掛的共同精神：*裝在 home 底下、不碰系統地盤、不需要 sudo*——看到教學對語言套件下 sudo，警鈴就要響。
]

== 真正的高風險區：`sudo make install`

C/C++ 沒有預設套件管理器，大量專案至今仍是原始碼 + `sudo make install`。風險高一級的本質：*裝的常常是函式庫，而函式庫全系統共享*。

#v(0.3em)
#row(gutter: 0.9em)[
  #card(tint: palette.rose, title: [1 · 沒有帳本])[
    #set text(size: 0.8em)
    bin / lib / include 散進 `/usr/local`，沒人記錄。唯一收據 `install_manifest.txt` 躺在 build 目錄 —— 刪了就沒了。
  ]
][
  #card(tint: palette.rose, title: [2 · Shadow 全機函式庫])[
    #set text(size: 0.8em)
    `/usr/local/lib` 優先於 `/usr/lib` —— 自編 libopencv / libprotobuf 蓋掉發行版那份，*全機*程式一起吃錯版本。
  ]
][
  #card(tint: palette.rose, title: [3 · prefix 錯，跟 apt 打架])[
    #set text(size: 0.8em)
    裝進 `/usr` 就是覆寫發行版檔案，apt 升級又會再蓋回來。許多天後，你還有把握系統最後狀態是怎樣嗎？
  ]
]

#speaker-note[
  然後是這一節真正的高風險區：C/C++ 專案的 `make install`。

  C/C++ 生態沒有像 pip、cargo 那樣的預設套件管理器，大量專案的發行方式至今仍是原始碼加 `sudo make install`（或 `cmake --install`）。它的風險比其他語言高一級，原因很本質：*C/C++ 裝的常常不是工具，是函式庫，而函式庫是全系統共享的*。具體有三條：

  第一，沒有帳本。`sudo make install` 把 bin、lib、include 散進 `/usr/local` 各處，沒有任何系統在記錄。CMake 專案會在 build 目錄留一份 `install_manifest.txt`——那是唯一的收據，但是 build 目錄一刪就再也不知道當年裝了什麼。

  第二，蓋掉全機共用的函式庫。動態連結器找 library 時 `/usr/local/lib` 的優先序在 `/usr/lib` 之前，自己編的 libopencv、libprotobuf 會 shadow 發行版那一份——從此*全機所有*用到這個函式庫的程式都改吃自編版本，版本或 ABI 不合，就是一堆看起來毫無關聯的程式一起出錯。OpenCV、protobuf、Eigen 是這類事故的常客，機器人領域尤其常見，因為 ROS 底下全是這些函式庫。

  第三，prefix 設錯直接跟 apt 打架。如果裝進 `/usr` 而不是 `/usr/local`，就是覆寫發行版的檔案；之後 apt 升級再蓋回來，兩本帳互相踩，系統從此處於薛丁格狀態。
]

== 正確習慣 + 散裝流派

#step(1) 有套件就用套件 —— apt、官方 deb、PPA。原始碼編譯是最後手段

#step(2) 真要編，*不要用預設 prefix*：`-DCMAKE_INSTALL_PREFIX=$HOME/.local` 或版本化進 `/opt/opencv-4.10`。下游用 `CMAKE_PREFIX_PATH` 指過去

#step(3) 留收據：build 目錄與 `install_manifest.txt` 不刪，或用 `checkinstall` 包成 deb

#step(4) 最乾脆：不 install —— build tree 內連結，或整個進容器

#v(0.4em)
#divider(label: [散裝流派，認得就好])
#v(0.2em)
#text(size: 0.85em)[
  binary / AppImage 丟 `~/.local/bin`（更新自己來）· `curl … | bash`（rustup、uv 都這樣發行）·

  snap / flatpak（沙盒路線）—— *每一種都是一本自己的帳*。
]

#speaker-note[
  對應的正確習慣，按優先序：

  - 有套件就用套件——apt、上游官方 deb、PPA 都好，原始碼編譯是最後手段。
  - 真要編，*不要用預設 prefix*：`cmake -DCMAKE_INSTALL_PREFIX=$HOME/.local` 裝進自己家（連 sudo 都不用），或版本化裝進 `/opt/opencv-4.10` 這種一目瞭然的位置；下游專案用 `CMAKE_PREFIX_PATH`、`PKG_CONFIG_PATH` 指過去就找得到。
  - 留收據：build 目錄和 `install_manifest.txt` 不要刪；或用 `checkinstall` 把 make install 包成 deb，讓 dpkg 幫忙記帳。
  - 最乾脆的：不 install——直接在 build tree 裡連結使用，或整個進 Docker，連 host 都不碰。

  剩下幾種散裝流派認得就好。下載 binary 或 AppImage 丟 `~/.local/bin`——簡單直接，更新自己來。`curl ... | bash` 一行安裝——rustup、uv 都這樣發行，方便，但等於下載陌生腳本直接用自己的身分執行，比較穩的做法是先開 URL 瞄一眼內容。snap 和 flatpak 走沙盒路線，各有支持者和抱怨。每一種都是一本自己的帳。
]

== 容器化

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  ```bash
  docker pull ubuntu:24.04
  docker run -it --rm ubuntu:24.04 bash
  ```
  #v(0.2em)
  #text(size: 0.88em)[
    進去是另一個世界：另一套 `/usr/bin`、另一本 apt 帳，跟 host 互不相干。

    對 dependency hell 的解法：*不解決衝突，直接讓大家不見面*。
  ]
][
  #card(tint: palette.teal, title: [機器人開發的現實], icon: [🤖])[
    #set text(size: 0.85em)
    ROS 對 Ubuntu 版本綁定很緊，很多實驗室的標準做法：

    *host 保持乾淨，開發環境全部進 container*。
  ]
]

#v(0.3em)

#callout(kind: "info", compact: true)[我們下週會再介紹容器......敬請期待]

#speaker-note[
  最後一本帳最徹底：Docker。它乾脆不跟 host 共用 filesystem——整個應用連同它的 userland 打包成 image，跑在隔離環境裡：

  ```bash
  docker pull ubuntu:24.04
  docker run -it --rm ubuntu:24.04 bash
  ```

  進去之後是另一個世界：另一套 `/usr/bin`、另一本 apt 帳、跟 host 互不相干。這就是 container 對 dependency hell 的解法——不解決衝突，直接讓大家不見面。機器人開發裡它極其重要：ROS 對 Ubuntu 版本綁定很緊，很多實驗室的標準做法就是「host 保持乾淨，開發環境全部進 container」。
]

== 重點整理

#block[
  #set text(size: 0.76em)
  #table(
    columns: (auto, auto, 1fr, 1fr),
    [安裝方式], [地盤], [查帳], [注意],
    [`apt`], [`/usr` 全系統], [`dpkg -L` / `dpkg -S`], [版本偏舊、全機一份],
    [`uv` / `pip`(venv)], [venv / `~/.local`], [`uv tool list`、`pip list`], [永遠不要 `sudo pip`],
    [`cargo` / `npm -g` / `go`], [`~/.cargo/bin` 等], [`cargo install --list`], [升級自己重跑],
    [`make install`], [`/usr/local`（預設）], [`install_manifest.txt`（僅存收據）], [自訂 prefix、留收據],
    [binary / AppImage], [`~/.local/bin`], [自己記], [更新自己來],
    [Docker], [image 裡的世界], [`docker images`], [跟 host 不見面],
  )
]

#speaker-note[
  （本頁是超出講稿的整理：把整節的「帳本」模型收成一張表，讓學生之後除錯時能一眼回答「這個檔案記在誰的帳上、要去哪本帳查」。講到這裡可以帶著大家逐列掃一遍，當作本節的隨堂複習。）
]

= PATH 與環境變數

== 經典症狀

我們以後課程進到 ROS 2 之後，*每開一個新 terminal* 往往就要

```bash
source /opt/ros/<distro>/setup.bash
source install/setup.bash   # 自己的 workspace
```

為什麼呢？如果沒有做的話......

#v(0.3em)
#row(gutter: 0.9em)[
  #card(tint: palette.rose, title: [症狀一], inset: 0.8em)[#text(size: 0.82em)[`ros2: command not found`]]
][
  #card(tint: palette.amber, title: [症狀二], inset: 0.8em)[#text(
    size: 0.82em,
  )[`Package 'xxx' not found`

    （明明剛編譯成功）]]
][
  #card(tint: palette.teal, title: [症狀三], inset: 0.8em)[#text(size: 0.82em)[跑起來了，但用的是*舊版本*]]
]

#v(0.4em)
根源是*Linux 環境變數*

#speaker-note[
  正式課程進到 ROS 2 之後，有一個動作會頻繁到變成肌肉記憶：*每開一個新 terminal，先打 `source /opt/ros/humble/setup.bash`*；自己的 workspace 編譯完，還要再 `source install/setup.bash`。忘記其中一步，會撞上三種經典症狀：`ros2: command not found`、`Package 'xxx' not found`（明明剛剛才編譯成功）、或是程式跑起來了但用的是舊版本。這個儀式一天要做十幾次，部署到機器人上、開第二台電腦聯調、寫開機自動啟動時全部都會再冒出來。這一節要把它背後的機制講穿——它不是 ROS 的怪癖，是 Linux 環境變數的基本盤。搞懂之後，這三種症狀從靈異事件變成三秒可診斷的機械問題。
]

== 症狀一的謎底：PATH，先到先贏

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  shell 不搜尋整個硬碟，它看 `PATH`：

  ```bash
  echo $PATH
  # /home/rvl/.local/bin:/usr/local/bin:/usr/bin:...
  ```

  從左到右一個一個找，*找到第一個就停*。
][
  #card(tint: palette.iris, title: [謎底], icon: [🔍])[
    #set text(size: 0.85em)
    ROS 2 住在 `/opt/ros/<distro>`，它的 bin *不在預設 PATH 裡*。

    #v(0.3em)
    程式好好躺在硬碟上，只是 shell 的查找清單裡 *沒有它的地址*。

    #v(0.3em)
    `setup.bash` 做的第一件事：把這個目錄加進 PATH。
  ]
]

#v(0.3em)
查案三支：`which ros2`（會選中哪個）、`type -a python3`（同名全列出）、`command -v`。Bash 有指令位置快取。

「裝了新的還跑到舊的」用 `hash -r` 清。

#speaker-note[
  從第一個症狀開始。打 `ros2` 的時候，shell 怎麼知道要去哪裡找這個程式？它不是搜尋整個硬碟——那太慢了。它看一個環境變數叫 `PATH`：

  ```bash
  echo $PATH
  ```

  會看到一串用冒號隔開的目錄，像 `/home/rvl/.local/bin:/usr/local/bin:/usr/bin:/bin`。shell 從左到右一個一個目錄找，*找到第一個就停*。現在看謎底：ROS 2 用 apt 裝完後住在 `/opt/ros/humble`（套件那節說過，`/opt` 是大型第三方軟體的地盤），而它的 bin 目錄*不在預設的 PATH 裡*。這就是 `ros2: command not found` 的全部真相——程式好好地躺在硬碟上，只是 shell 的查找清單裡沒有它的地址。`setup.bash` 做的第一件事，就是把這個目錄加進 PATH。

  查案工具有三支：

  ```bash
  which ros2
  type -a python3
  command -v ros2
  ```

  `which` 回答 shell 會選中哪一個；`type -a` 把 PATH 上所有同名的傢伙全列出來——「跑到的到底是哪個 python、哪個 ros2」靠它裁決。這裡還有一個小機關：Bash 會把找過的指令位置記在 hash table 裡加速，偶爾會出現「新的明明裝到前面了，跑的還是舊的」——`hash -r` 清掉快取就好。
]

== setup.bash 改的遠不只 PATH

#block[
  #set text(size: 0.82em)
  #table(
    columns: (auto, 1fr),
    [變數], [誰用它、找什麼],
    [`PATH`], [shell 找可執行檔],
    [`AMENT_PREFIX_PATH`], [`ros2` 指令找 package 索引 —— *症狀二的謎底*],
    [`PYTHONPATH`], [Python 找 ROS 模組],
    [`LD_LIBRARY_PATH`], [程式啟動時找動態函式庫],
    [`CMAKE_PREFIX_PATH`], [編譯時找依賴],
  )
]

#v(0.4em)
*它們全是環境變數，一組跟著 process 走的 key-value*。

#speaker-note[
  但 `setup.bash` 改的遠不只 PATH。打開來看，它設定的是一整組變數：`AMENT_PREFIX_PATH`（`ros2` 指令去哪裡找 package 索引）、`PYTHONPATH`（Python 去哪裡 import ROS 模組）、`LD_LIBRARY_PATH`（程式啟動時去哪裡找動態函式庫）、`CMAKE_PREFIX_PATH`（編譯時去哪裡找依賴）。這解釋了第二個症狀：`ros2` 指令找得到（PATH 有了），卻 `Package 'xxx' not found`——因為 ROS2 package 索引走的是 `AMENT_PREFIX_PATH`，那是另一個變數，剛編譯好的 workspace 還沒登記進去。這些名字不用背，要看穿的是共同點：*它們全是同一種東西——環境變數，一組跟著 process 走的 key-value*。
]

== 傳遞規則：fork ＋ exec，複製而非共享

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  各位回憶作業系統所學：新 process 會 `fork` + `exec`。

  - 環境變數存在 process 自己的記憶體（`environ`）→ fork 時 *跟著複製*
  - exec 換程式，預設 *原封不動帶過去*
  - 子 process 再怎麼改自己那份，*父 process 一個位元組都不動*
][
  #card(
    fill: palette.night,
    stroke: none,
    radius: 12pt,
    title: [整棵 process tree = 環境變數的繼承樹],
    title-fill: white,
  )[
    #set text(fill: white.transparentize(15%), size: 0.72em)
    ```text
    systemd (PID 1)
    ├─ gdm ─ session ─ terminal ─ bash   ← 你 source 的在這
    │                             └─ ros2 run …（繼承自 bash）
    └─ sshd / cron ─ bash -c script      ← 另一條鏈，感覺不到
    ```
  ]
]

#v(0.3em)
shell 每執行一個指令就是一次 fork + exec。

#speaker-note[
  那環境變數的傳遞規則是什麼？這裡可以直接接回作業系統課學過的東西：Linux 產生新 process 靠 `fork` + `exec`。`fork` 把整個 process 複製一份，而環境變數就存放在 process 自己的記憶體裡（C 語言看到的 `environ`），所以會跟著被複製；`exec` 換上新程式時，預設也把這組環境原封不動帶過去。作業系統課講 fork 時，多半聚焦在 PID 和 memory 的複製語意——但對日常開發殺傷力最大的，正是環境變數也遵守*複製、而非共享*的語意：fork 完父子各拿各的一份，子 process 再怎麼改自己那份，父 process 的一個位元組都不會動。shell 每執行一個指令就是一次 fork + exec，所以整棵 process tree 就是一張環境變數的繼承樹。把這個模型放著，三個日常情境直接推出來。
]

== 情境一：為什麼要 `source`，不能直接執行？

#row(gutter: 1.2em)[
  #card(tint: palette.rose, title: [`bash setup.bash`], icon: [❌])[
    #set text(size: 0.85em)
    fork + exec 一個 *子 shell* → 子 shell 在自己的記憶體設好變數 → exit → 記憶體隨 process 消失。

    #v(0.3em)
    父 shell *什麼都沒得到*。
  ]
][
  #card(tint: palette.teal, title: [`source setup.bash`], icon: [✅])[
    #set text(size: 0.85em)
    *不 fork* —— 當前 shell 親自逐行執行檔案內容，變數寫在 *自己身上*。
  ]
]

#v(0.5em)
#callout(
  kind: "info",
  compact: true,
)[這也回答了「為什麼每開新 terminal 都要重 source」：每個 terminal 是全新 shell process，環境是 *出生那一刻複製來的*，跟上一個 terminal 毫無關係。]

#speaker-note[
  情境一：為什麼 `setup.bash` 要用 `source`，不能直接執行？`bash setup.bash` 就是 fork + exec 一個子 shell，子 shell 在自己的記憶體裡把變數設好，然後 exit——那份記憶體隨 process 一起消失，父 shell 什麼都沒得到。`source` 的差別是*不 fork*：讓當前這個 shell 親自逐行執行檔案內容，變數才寫在自己身上。這也回答了為什麼每開一個新 terminal 都要重新 source：每個新 terminal 起一個全新的 shell process，環境是出生那一刻複製來的，上一個 terminal source 過什麼，跟它毫無關係。
]

== 情境二：換條鏈就掛——systemd、cron、SSH

terminal 跑得好好的 node，寫成開機自動啟動或 SSH 進去跑就掛，就是 Shell 那節提的 *PATH 靈異事件*。

#v(0.3em)
#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #card(tint: palette.amber, title: [病理・上半：繼承鏈], icon: [🧬])[
    #set text(size: 0.85em)
    systemd / cron 生的 process 祖先是 PID 1，父鏈 *不經過你的 interactive shell*。

    #v(0.3em)
    繼承只沿父子鏈走。

    你 source 過什麼，*別條鏈上一個位元組都感覺不到*。
  ]
][
  #card(title: [所以機器人的 bringup 腳本], icon: [🤖])[
    #set text(size: 0.85em)
    開頭總要自己 `source` 一次 setup 檔，或在 service 設定裡明確給環境。

    #v(0.3em)
    病理・下半（哪些檔案什麼時候被讀）。
  ]
]

#speaker-note[
  情境二：node 在自己的 terminal 跑得好好的，寫成開機自動啟動或 SSH 進去跑就掛。認出來了嗎？這就是 Terminal & Shell 那節劇透過的 PATH 靈異事件——「terminal 裡有這個指令，但 script 裡找不到」「SSH 進去指令就消失」——當時只說了結論：「設定寫在某個這種情境下不會被讀的檔案」，欠的病理現在可以完整補上。第一半是繼承鏈：systemd 生的 process、cron 生的 process，祖先是 PID 1，父鏈根本不經過我們的 interactive shell——繼承只沿著父子鏈走，我們在自己的 shell 裡 source 過什麼，別條鏈上一個位元組都感覺不到。這就是為什麼機器人的 bringup 腳本開頭總要自己 `source` 一次 setup 檔，或在 service 設定裡明確給環境。第二半——「不會被讀的檔案」到底是哪些檔案在什麼時候被讀，為什麼寫進 `.bashrc` 有時救得了、有時救不了——就是接下來的 startup file，當時欠的結在那裡全部解開。
]

== 情境三：`export`，與平行世界的 node

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  shell 有兩種變數：

  - 純 shell 變數：只活在 shell 自己的變數表，*不會* 進交接給子 process 的 environ
  - `export`：把它標記進交接清單

  #v(0.3em)
  ```bash
  ROS_DOMAIN_ID=42         # node 看不到
  export ROS_DOMAIN_ID=42  # 傳下去 ✅
  ```
][
  #card(tint: palette.rose, title: [專屬靈異現象], icon: [👻])[
    #set text(size: 0.85em)
    兩個 terminal 一個有 export、一個沒有 → node 活在 *兩個平行世界*，`ros2 topic list` 互相看不到。

    #v(0.3em)
    症狀像網路壞了，實際只是兩個 shell 的 environ 不同。

    #v(0.3em)
    聯調前各自跑 `env | grep ROS`，省掉互相懷疑。
  ]
]

#v(0.3em)
#text(
  size: 0.85em,
)[症狀三「跑到舊版本」同理：workspace 的 setup 把自己疊在 `/opt/ros` *前面*（ROS 叫 overlay，原理就是先到先贏）。Python venv 的 activate 也是同一招。]

#speaker-note[
  情境三：`export` 在這個模型裡是什麼？shell 有兩種變數：純 shell 變數只活在 shell 自己的變數表裡，fork + exec 時*不會*被放進交接給子 process 的 environ；`export` 做的就是把它標記進去。所以 `ROS_DOMAIN_ID=42` 之後跑 `ros2 run`，node 看不到這個值；`export ROS_DOMAIN_ID=42` 才會傳下去。順帶認識這個變數：ROS 2 的節點靠它決定加入哪個通訊網域，同一網路裡 domain 相同的機器會互相看見。於是它能製造一種專屬的靈異現象：*兩個 terminal 一個有 export、一個沒有，跑起來的 node 就活在兩個平行世界，`ros2 topic list` 互相看不到對方*——症狀看起來像網路壞了，實際上只是兩個 shell 交接給子 process 的 environ 不同。`env | grep ROS` 可以直接盤點目前 shell 會交接哪些 ROS 變數，聯調前先各自跑一次，能省掉很多互相懷疑。

  第三個症狀「跑起來的是舊版本」也是同一套機制：workspace 的 `install/setup.bash` 會把自己的路徑疊在 `/opt/ros/humble` *前面*——ROS 把這叫 overlay，但原理就是那條「先到先贏」規則：排前面的蓋掉排後面的。忘了 source workspace 的 setup，清單裡只剩系統那份，自然跑到舊的。順便提一嘴，Python venv 的 activate 也是同一招的變體：把自己插到查找清單最前面。
]

== 病理・下半：startup file 對照表

#block[
  #set text(size: 0.85em)
  #table(
    columns: (auto, 1fr, 1fr),
    [shell 情境], [例子], [讀什麼],
    [login shell], [SSH 登入、TTY 登入], [`~/.profile` / `~/.bash_profile`],
    [interactive non-login], [桌面上開 terminal（最常見）], [`~/.bashrc`],
    [non-interactive], [跑 script、systemd 起的程式], [基本上 *什麼都不讀*],
  )
]

#v(0.3em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #callout(
    kind: "tip",
    compact: true,
  )[實務守則：環境設定寫進 `~/.bashrc`，並確認 `~/.profile` 有引用它（Ubuntu 預設有；鏈斷了就出現「SSH 進來 ros2 就消失」）。]
][
  #callout(
    kind: "danger",
    compact: true,
  )[`export PATH="$HOME/.local/bin:$PATH"` —— 忘記接 `$PATH` 會把整條路清空，連 `ls` 都 command not found。]
]

#speaker-note[
  shell 啟動時讀哪些設定檔，取決於它是不是 login shell、是不是 interactive shell：

  - login shell（SSH 登入、TTY 登入）：讀 `~/.profile` 或 `~/.bash_profile`
  - interactive non-login shell（桌面上開 terminal，最常見）：讀 `~/.bashrc`
  - non-interactive（跑 script、systemd 起的程式）：基本上*什麼都不讀*

  ROS 官方教學的第一課，就是叫人把 `source /opt/ros/humble/setup.bash` 寫進 `~/.bashrc`——這張表能完整解釋這一招：它讓每個新開的 interactive shell 在初始化時自動把 ROS 那組變數設進自己的環境，桌面 terminal 從此不用手動 source。但同一張表也標出它的失效範圍：systemd 和 cron 走 non-interactive 那行，什麼都不讀，`.bashrc` 寫得再好都輪不到——部署時的環境要自己備。SSH 進來走的是 login shell 那行；Ubuntu 預設讓 `.profile` 去 source `.bashrc`，所以通常沒感覺，哪天這條鏈斷了，「SSH 進來 `ros2` 就消失」的症狀就浮出來。實務守則一條：*環境設定寫進 `~/.bashrc`，並確認 `~/.profile` 有引用它*。

  標準的 PATH 追加寫法，拆解一下：

  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  ```

  新目錄放前面、把舊的 `$PATH` 接在後面——*忘記接 `$PATH` 會把整條路清空*，那一瞬間連 `ls` 都會 command not found，堪稱最壯觀的環境事故之一。
]

= 程序、服務與 systemd

== 收官：觀察活著的系統

前面全是靜態結構（檔案、權限、路徑），但我們除錯面對的是*活的系統*。

#v(0.3em)
#row(widths: (1fr, 1fr), gutter: 1.2em)[
  ```bash
  ps aux            # 全量快照，配 grep
  ps auxf           # 加家族樹縮排
  top               # 活的儀表板
  btop              # 現代版，好看好操作
  pstree            # 誰生了誰
  ```
][
  #card(tint: palette.iris, title: [前面每一節在這裡會合], icon: [🧩])[
    #set text(size: 0.85em)
    每個 process 有 PID、父 process、*owner*（權限那節的身分）、*自己的環境變數*（上一節的繼承）。

    #v(0.3em)
    `btop` 要自己裝  (`sudo apt install btop`)。
  ]
]

#speaker-note[
  最後一節，把視角拉到系統的動態面：正在跑的東西。前面講的都是靜態結構——檔案、權限、路徑——但除錯時面對的是活的系統：某個 process 失控吃 CPU、某個 port 被占走、某個 service 起不來。這一節要建的是*觀察活系統的儀表板*，也是整個 week0 的收官。

  從 process 講起。每個 process 有 PID、有父 process、有 owner（權限那節的身分就掛在這）、有自己的環境變數（上一節整節都在講它的繼承）——前面每一節在這裡全部會合。觀察工具：

  ```bash
  ps aux
  ps auxf
  top
  btop
  pstree
  ```

  `ps aux` 是全量快照，配 grep 用：`ps aux | grep python`。`ps auxf` 加上家族樹縮排，看誰生了誰。`top` 是活的儀表板，`btop` 是它的現代版，好看好操作，通常要自己裝——這也正好用上套件那節：`sudo apt install btop`。
]

== kill 這名字取得很兇，其實只是「送訊號」

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  ```bash
  kill PID          # SIGTERM，好好講
  kill -9 PID       # SIGKILL，不講了
  pkill -f pattern
  ```
  #v(0.3em)
  #set text(size: 0.85em)
  #table(
    columns: (auto, 1fr),
    [SIGTERM], [「請收拾好自行了斷」—— 可攔截、寫檔、清理再走],
    [SIGKILL], [kernel 直接抹名冊 —— *連遺言都來不及留*],
    [SIGINT], [就是天天在按的 #kbd[Ctrl] + #kbd[C]],
  )
][
  規矩：先 `kill`，等幾秒，真不走再 `-9`。

  #v(0.4em)
  #callout(kind: "info", title: [破迷思：zombie], compact: true)[
    zombie 用 `kill -9` 殺不掉 —— 它 *已經死了*，只是一筆等父親收屍（讀 exit status）的戶口紀錄。父親不收，得找父親算帳。
  ]
]

#speaker-note[
  要跟 process 溝通靠 signal。`kill` 這名字取得很兇，其實它只是「送訊號」：

  ```bash
  kill PID          # 送 SIGTERM，好好講
  kill -9 PID       # 送 SIGKILL，不講了
  pkill -f pattern
  ```

  這裡有個重要的分別：SIGTERM 是「請你收拾好東西自行了斷」，程式可以攔截它、寫完檔案、清理資源再走；SIGKILL 是 kernel 直接把它從名冊上抹掉，程式*連遺言都來不及留*——暫存檔沒清、lock file 留在原地，後患都是這樣來的。所以規矩是先 `kill`，等幾秒，真的不走再 `-9`。順帶破一個迷思：狀態欄裡的 zombie process 用 `kill -9` 是殺不掉的，因為它已經死了——那只是一筆等父親來收屍（讀取 exit status）的戶口紀錄，父親不收，得找父親算帳。平常按的 `Ctrl+C` 其實也是 signal（SIGINT），所以這套機制我們早就天天在用了。
]

== SSH 斷線，程式死光光

為什麼？程式是 SSH session 的 shell 的子孫 —— session 斷掉，整個家族樹收到一記 *SIGHUP*（hangup，來自電話掛斷的年代），預設行為就是跟著死。

#v(0.4em)
#row(gutter: 1em)[
  #card(title: [土法], icon: [🪵])[
    #set text(size: 0.85em)
    `nohup` —— 讓程式無視掛斷訊號。
  ]
][
  #card(tint: palette.teal, title: [日常必備], icon: [🧵])[
    #set text(size: 0.85em)
    `tmux` / `screen` —— 斷線後還活著、重連接得回去的 session。

    *遠端機器進門先開 tmux*，值得練成肌肉記憶。
  ]
][
  #card(tint: palette.iris, title: [正規解], icon: [🏛])[
    #set text(size: 0.85em)
    交給系統的服務管理員看護 —— 本節後半的主角，先按下不表。
  ]
]

#speaker-note[
  signal 還解釋一個人人必撞的坑：SSH 到機器上跑一個長時間程式，網路一斷，程式跟著死了。為什麼？因為那個程式是 SSH session 的 shell 的子孫，session 斷掉，整個家族樹會收到一記 SIGHUP——hangup，這名字來自電話掛斷的年代——預設行為就是跟著死。解法從土到豪華：`nohup` 讓程式無視掛斷訊號；`tmux` 或 `screen` 給我們一個斷線後還活著、重連可以接回去的 terminal session——在遠端機器上進門先開 tmux，是值得練成肌肉記憶的習慣；至於最正規的解法——把程式交給系統的服務管理員看護——就是本節後半的主角，先按下不表。
]

== Port：process 在網路上的門牌

IP 找到 *房子*（哪台機器），port 找到 *房間*（哪個 process）—— 16-bit 號碼（0–65535），程式先向 kernel 登記「我要聽 8080」（listen），之後打到 8080 的封包全歸它。

#v(0.3em)
#row(gutter: 0.9em)[
  #card(tint: palette.iris, title: [推論 1])[
    #set text(size: 0.82em)
    同一 port 同時只能一個 process 聽 —— 後到的拿到 `Address already in use`。
  ]
][
  #card(tint: palette.teal, title: [推論 2])[
    #set text(size: 0.82em)
    listen 還要選介面：`127.0.0.1` 只收本機；`0.0.0.0` 所有介面都收。
  ]
][
  #card(tint: palette.amber, title: [推論 3])[
    #set text(size: 0.82em)
    1024 以下 = privileged port，要 root（22、80/443）—— 所以測試伺服器預設 8000、8080。
  ]
]

#speaker-note[
  再來是 port，這個概念值得多花幾分鐘，因為機器人開發整天在跟它打交道。IP address 負責把封包送到「哪一台機器」，但一台機器上同時跑著幾十個程式，封包進門之後要交給誰？答案就是 port：一個 16-bit 的號碼（0–65535），kernel 用它決定把連線轉交給哪個 process。想收連線的程式先向 kernel 登記「我要聽 8080」，這個動作叫 listen；之後打到 8080 的封包就全歸它。所以 *port 本質上是 process 在網路上的門牌*——IP 找到房子，port 找到房間。

  我們可以藉此直接推出幾件事。第一，同一個 port 同時只能有一個 process 聽——兩個程式搶同一個門牌，後到的拿到 `Address already in use`。第二，listen 時還要指定「聽哪個網路介面」：綁 `127.0.0.1` 表示只收本機發起的連線，綁 `0.0.0.0` 表示所有介面都收。第三，回收權限那節的伏筆：1024 以下是 privileged port，要 root 才能聽——22（SSH）、80/443（HTTP/HTTPS）這些眾所皆知的門牌值得保護——這也是為什麼開發用的測試伺服器都預設開 8000、8080 這些高位 port。
]

== Port 查案

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  ```bash
  ss -tlnp             # 誰在聽哪些 TCP port
  ss -tulnp            # 連 UDP 一起列
  sudo lsof -i :8080   # 直接問：誰佔了 8080
  curl localhost:8080  # 本機戳一下，確認活著
  ```
  #text(size: 0.8em)[（老教學寫 `netstat` ，同一件事的老工具。）]
][
  #card(tint: palette.teal, title: [輸出現在看得懂了], icon: [👓])[
    #set text(size: 0.85em)
    `127.0.0.1:8080` vs `0.0.0.0:8080` = 門牌掛哪張網卡。

    #v(0.3em)
    查到佔用 PID → 殺它，或自己換 port。
  ]
  #v(0.4em)
  #callout(kind: "info", compact: true)[ROS 2 的 DDS 走 *UDP* —— `ros2 topic` 流量在 TCP 清單看不到，要 `-u` 才現形。]
]

#speaker-note[
  查案工具：

  ```bash
  ss -tlnp             # 誰在聽哪些 TCP port
  ss -tulnp            # 連 UDP 一起列
  sudo lsof -i :8080   # 直接問：誰佔了 8080
  curl localhost:8080  # 從本機戳一下，確認服務活著
  ```

  `ss -tlnp` 列出所有正在聽的 port 和是誰在聽（老教學會寫 `netstat`，同一件事的老工具），輸出裡的 `127.0.0.1:8080` 和 `0.0.0.0:8080` 現在看得懂了——就是門牌掛哪張網卡的差別。查到佔用的 PID，再決定是殺它還是自己換 port。順帶一提 UDP 那行的用處：ROS 2 底層的 DDS 通訊走 UDP，`ros2 topic` 的流量在 TCP 清單裡看不到，要 `-u` 才現形。
]

== PID 1：kernel 只認一個初始 process

機器上一大堆程式不是你開的：SSH server、network manager、Docker daemon…… 開機自己起、掛了有人重拉、log 有人收 —— 這個角色叫 *init system*。

#v(0.3em)
#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #card(tint: palette.iris, title: [PID 1 有多特殊], icon: [👑])[
    #set text(size: 0.85em)
    - kernel 開機只啟動 *唯一* 一個初始 process，其後全是它的子孫
    - 它死了 → kernel 直接 panic
    - 孤兒 process 最後都過繼給它收屍
  ]
][
  #card(tint: palette.amber, title: [前任：sysvinit（1980s 風格）], icon: [🗿])[
    #set text(size: 0.85em)
    按順序跑 `/etc/init.d/` 的 shell script：開機慢、腳本品質參差、daemon double fork 逃出管轄 —— *stop 常停不乾淨*。
  ]
]

#speaker-note[
  接著進入本節的主角：systemd。先從一個事實出發——機器上有一大堆程式不是我們手動開的：SSH server、network manager、Docker daemon、桌面的 display manager。它們開機自己起來、掛了有人重拉、log 有人收。負責這一切的角色叫 init system，而 kernel 開機時只做一件跟 userspace 有關的事：啟動*唯一*一個初始 process，也就是 PID 1，之後所有 process 都是它的子孫。PID 1 特殊到什麼程度？它死了 kernel 直接 panic，整台機器停擺；前面 zombie 那段說「找父親算帳」，而失去父親的孤兒 process，最後也都會被過繼給 PID 1 收屍。

  在 systemd 之前，這個位子坐的是 sysvinit，一套 1980 年代風格的設計：開機就是按順序執行 `/etc/init.d/` 底下的一串 shell script。它的問題跑久了全浮出來：服務一個接一個起，所以開機慢；每個服務的啟動、停止、重啟邏輯都是各自手寫的 shell script，品質參差；最要命的是它管不住自己的小孩——daemon 慣例上會 double fork 脫離父子鏈，init 從此不知道這個服務實際起了哪些 process，「stop」常常停不乾淨。
]

== systemd 的三個核心翻新（2010，參考 launchd）

#row(gutter: 1em)[
  #card(tint: palette.iris, title: [1 · 宣告式 unit 檔], icon: [📜])[
    #set text(size: 0.82em)
    「執行哪個程式、依賴誰、掛了怎麼辦」寫成純文字設定 —— 又見「文字檔當設定介面」的老傳統。
  ]
][
  #card(tint: palette.teal, title: [2 · 依賴圖平行啟動], icon: [🕸])[
    #set text(size: 0.82em)
    從排隊執行變成依賴圖上平行起 —— 開機速度換了一個世代。
  ]
][
  #card(tint: palette.amber, title: [3 · cgroup 記帳], icon: [🧾])[
    #set text(size: 0.82em)
    服務生出的 *每一個* process 圈在同組 —— double fork 也逃不掉，stop 是真的全停；`systemctl status` 的 process tree 靠這個。
  ]
]

#speaker-note[
  2010 年，Red Hat 的工程師 Lennart Poettering 帶著 systemd 登場，設計上大量參考 macOS 的 launchd。核心翻新有三個。第一，服務改用*宣告式*的 unit 檔描述——「執行哪個程式、依賴誰、掛了怎麼辦」寫成純文字設定（又見到「文字檔當設定介面」的老傳統），而不是每家手寫一份啟動腳本。第二，開機從「排隊執行」變成*依賴圖上的平行啟動*，互不依賴的服務同時起，開機速度直接換了一個世代。第三，用 kernel 的 cgroup 把服務生出的*每一個* process 圈在同一個群組裡記帳——double fork 也逃不出去，stop 就是真的全停；`systemctl status` 能列出一個服務底下完整的 process tree，靠的就是這個。
]

== 軼聞：近十五年吵得最兇的技術戰爭

引爆點：systemd 把分散的系統管理問題 *收進同一套模型* —— 服務 → unit、log → journal、login → logind、排程 → timer、socket activation……

#v(0.3em)
#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #card(tint: palette.teal, title: [支持者])[
    #text(size: 0.85em)[一致的依賴、狀態和查詢介面。]
  ]
  #v(0.4em)
  #card(tint: palette.rose, title: [反對者])[
    #text(size: 0.85em)[違反 UNIX「一個程式做好一件事」的版圖擴張。]
  ]
][
  #text(size: 0.85em)[
    激烈到什麼程度：

    - 2014 Debian 技術委員會投票吵到 *靠主席決定票* 定案
    - 反對派憤而出走，fork 出拔掉 systemd 的 *Devuan*

    本質是「鬆散組合 vs 集中協調」的路線之爭。結局：Fedora 2011 → Debian / Ubuntu 2015 → 現在整個現場圍著它轉。
  ]
]

#speaker-note[
  然後是軼聞：systemd 引發了 Linux 圈近十五年吵得最兇的技術戰爭。爭議不只是「換掉 init」這麼小，真正的引爆點是它把很多原本分散的系統管理問題收進同一套模型裡：服務生命週期交給 unit，log 進 journal，login session 由 logind 追蹤，排程可以寫成 timer，socket 可以先掛著等連線進來再啟動服務。支持者說這讓系統有一致的依賴、狀態和查詢介面；反對者說這是違反 UNIX「一個程式做好一件事」的版圖擴張。這場戰爭激烈到什麼程度？2014 年 Debian 為了要不要採用它，技術委員會投票吵到最後靠主席的決定票才定案；反對派憤而出走，fork 出一個把 systemd 拔掉的發行版叫 Devuan。這不是普通的工具偏好，而是整個系統應該「鬆散組合」還是「集中協調」的路線之爭。結局也很清楚：Fedora 2011 年先採用，Debian、Ubuntu 2015 年跟進，現在 Linux 開發與維運現場大量預設工具都圍著 systemd 轉。
]

== Unit 與 systemctl 日常

#row(widths: (1fr, 1fr), gutter: 1.2em)[
  #text(size: 0.85em)[
    unit 種類：`.service` 服務、`.timer` 排程、`.socket` 連線才啟動、`.target` 集合點（`multi-user.target` 純文字層 / `graphical.target` 疊桌面）。

    兩個家、後者優先：`/usr/lib/systemd/system/`（套件裝的）、`/etc/systemd/system/`（管理者覆寫）—— 跟 `/etc` 精神一脈相承。
  ]
][
  ```bash
  systemctl status ssh    # 第一反應指令
  sudo systemctl start ssh
  sudo systemctl restart ssh
  sudo systemctl enable --now ssh
  systemctl list-units --type=service
  systemctl cat ssh       # 印出 unit 設定
  ```
]

#v(0.3em)
#callout(
  kind: "warn",
  compact: true,
)[經典地雷：*`start` 和 `enable` 是兩件事* —— start 是現在跑，enable 是開機自動跑。要又跑又自動：`enable --now`。]

#speaker-note[
  回到正經的結構。systemd 的管理單位叫 unit，種類不只 service：`.service` 是服務、`.timer` 是排程、`.socket` 支援「有人連進來才啟動服務」的 socket activation、`.target` 是一組 unit 的集合點——開機「開到哪一層」就是選 target，`multi-user.target` 是純文字多使用者環境，`graphical.target` 在那之上再疊桌面，這正是桌面那節「伺服器一輩子停在純文字層」的正式說法。unit 檔有兩個家：套件裝的放 `/usr/lib/systemd/system/`，管理者自己寫的和要覆寫的放 `/etc/systemd/system/`，後者優先——「發行版給預設、管理者蓋自訂」的分層，跟 `/etc` 的精神一脈相承。想看一個服務的設定長什麼樣，`systemctl cat ssh` 直接印出來。

  日常操作全靠 `systemctl`：

  ```bash
  systemctl status ssh
  sudo systemctl start ssh
  sudo systemctl stop ssh
  sudo systemctl restart ssh
  sudo systemctl enable ssh
  systemctl list-units --type=service
  systemctl cat ssh
  ```

  一個經典地雷，先拆掉：*`start` 和 `enable` 是兩件事*。`start` 是現在給我跑起來，`enable` 是開機時自動跑——只 start 沒 enable，重開機服務就不見了；只 enable 沒 start，現在它還是沒在跑。要又跑又自動，`enable --now` 一次到位。而 `systemctl status` 是最值得養成的第一反應指令：一眼看到服務是 active 還是 failed、跑多久了、cgroup 裡完整的 process tree，還附贈最後幾行 log。
]

== journalctl：全系統 log 的統一查詢

journald 把服務的 stdout / stderr、kernel 訊息全收進同一個資料庫：

```bash
journalctl -u ssh              # 指定 service
journalctl -u ssh -f           # follow：掛一個視窗盯著滾
journalctl -b                  # 只看本次開機
journalctl -p err -b           # 只看錯誤等級以上
journalctl --since "10 min ago"
```

#v(0.3em)
#row(widths: (1fr, 1fr), gutter: 1em)[
  #callout(kind: "tip", compact: true)[這幾個組合起來，「服務為什麼掛了」的答案 *九成能自己找到*。]
][
  #callout(kind: "info", compact: true)[傳統 `/var/log`（`syslog`、`dmesg`、各應用 log）也還在 —— 兩邊都要知道去翻。]
]

#speaker-note[
  log 就是下一個主角。journald 把全系統的 log 統一收進 journal——服務的 stdout、stderr、kernel 訊息全部進同一個資料庫，查詢工具是 `journalctl`：

  ```bash
  journalctl -u ssh
  journalctl -u ssh -f
  journalctl -b
  journalctl -p err -b
  journalctl --since "10 min ago"
  ```

  `-u` 指定 service，`-f` 是 follow——像盯著儀表板一樣看 log 即時滾動，除錯時開一個視窗掛著它是標準姿勢。`-b` 只看本次開機，`-p err` 只看錯誤等級以上，`--since` 抓時間窗。這幾個組合起來，「服務為什麼掛了」的答案九成能自己找到。傳統的 `/var/log` 檔案們（`syslog`、`dmesg`、各應用自己的 log）也還在，兩邊都要知道去翻。
]

== 第 0 週課程地圖

#block[
  #set text(size: 0.8em)
  #table(
    columns: (auto, 1fr, 1fr),
    [節], [心智模型], [指令],
    [生態], [kernel / userland / 發行版三層], [`uname -a`、`cat /etc/os-release`],
    [桌面], [桌面很晚、很可拆；session 是選的], [`echo $XDG_SESSION_TYPE`],
    [shell], [pipe 是 shell 接的水管], [`type -a`、`reset`],
    [檔案], [一棵樹 + mount + symlink + metadata], [`findmnt`、`stat`、`df -h`],
    [權限], [process 身分 × 檔案門禁，root 免檢], [`id`、`ls -l`],
    [套件], [每種安裝方式一本帳], [`dpkg -S`、`uv tool list`],
    [PATH], [環境變數 = 沿 fork 複製的繼承樹], [`echo $PATH`、`env | grep ROS`],
    [systemd], [PID 1 看護一切、journal 收一切], [`systemctl status`、`journalctl -u`],
  )
]

#speaker-note[
  （本頁是超出講稿的總複習：把八節課各自的心智模型與「第一反應指令」收成一張表。帶學生從上往下走一遍，強調這張表就是之後正式課程遇到環境問題時的除錯地圖——先判斷問題落在哪一層，再用那一層的第一反應指令開始查。）
]

#ending-slide(title: [Q & A])
