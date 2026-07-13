#import "@local/summer-course:0.1.0": *

#show: course-theme.with(
  config-info(
    title: [ROS2：架構、通訊模型與 TF],
    subtitle: [Week 4.5 · Middleware, Communication Patterns, and Coordinate Frames],
    author: [獵奇緯],
    institution: [Summer Course],
    short-title: [Week 4.5 · ROS2],
  ),
)

#let equation(body) = align(center)[#text(size: 1.15em)[#body]]
#let source-note(body) = align(center)[#text(size: .42em, fill: palette.muted)[#body]]

#title-slide()
#outline-slide()

= Part 0 · 似曾相似的架構設計

== 一台機器人，其實是十幾支獨立的程式

#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [觀察], icon: [🤖])[
    一台真正在跑的機器人，底下是十幾支各自獨立的 process 同時運作：讀 LiDAR、讀相機、做定位、做規劃、控制馬達，甚至跑在不同電腦上。
  ]
][
  #card(tint: palette.teal, title: [第一個問題], icon: [❓])[
    這些 process 要合作出一個連貫行為，第一件要解的事：一個 process 怎麼知道另一個 process 在哪裡、能提供什麼？
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[這個問題你並不陌生：作業系統課裡的主僕式（master-slave）架構，一台機器維護全域表，記錄誰擁有什麼資源，其他機器有事先去問它，你已經看過，只是場景通常是檔案系統或資源管理。]

#speaker-note[
  一台真正在跑的機器人，底下通常是十幾支各自獨立執行的程式同時運作：一支專門讀 LiDAR，一支專門讀相機，一支做定位，一支做路徑規劃，一支專門控制馬達，彼此是完全獨立的 process，甚至跑在不同的電腦上。這些 process 要合作出一個連貫的行為，第一件要解決的事就是：一個 process 怎麼知道另一個 process 在哪裡、能提供什麼。

  這個問題你並不陌生。作業系統課裡的主僕式（master-slave）架構，你已經看過：一台機器維護一張全域的表，記錄誰擁有什麼資源、誰可以提供什麼服務，其他機器有事都先去問這台機器。過去這個設計哲學出現的場景通常落在檔案系統或資源管理上。機器人的通訊中介層，剛好完整地把這個模式實作了一次，拿它當第一個具體例子，把主僕式架構在實務上長什麼樣子、代價在哪裡，精確地釘死。
]

== ROS 1：主僕式架構的具體實作

#image("assets/ros1_discovery.svg", width: 92%)

#speaker-note[
  這個中介層便是 ROS 1，它的核心是一個叫 `roscore` 的中央程序，裡面跑著 XML-RPC 的 Master，做的事情精確來說只有一件：維護一張表，記錄「誰在發布什麼 topic、誰在訂閱什麼 topic、誰提供什麼 service」。當一個 node 呼叫 `advertise("/scan", sensor_msgs/LaserScan)`，它是在對 Master 做一次 XML-RPC 呼叫，把自己的位址（host、port）登記進這張表。當另一個 node 呼叫 `subscribe("/scan")`，它先問 Master「誰在發布 `/scan`」，Master 回傳一份 publisher 位址清單，接著這個 subscriber node 直接對每一個 publisher 發起一次 TCPROS（或 UDPROS）連線，協商訊息型別、進行 handshake，然後開始收資料。

  這裡有一個經常被誤解的地方值得說清楚：Master 只負責「配對」，實際的訊息資料從來不經過 Master。一旦配對完成，publisher 跟 subscriber 之間是純粹的 peer-to-peer TCP 連線，Master 完全不在資料路徑上。這跟你熟悉的主僕架構裡「僕永遠聽主的指揮」不太一樣，這裡的主只在「介紹雙方認識」這一刻出場，認識之後兩邊直接對話，主完全退場。
]

== 主僕架構的代價

#row(widths: (1fr, 1fr, 1fr), gutter: .8em)[
  #card(tint: palette.rose, title: [單點協調者], icon: [①])[
    `roscore` 掛掉，既有連線不斷，但任何「新加入」全部停擺：新開的 node 沒有地方登記、查詢。
  ]
][
  #card(tint: palette.amber, title: [每個節點都要知道位址], icon: [②])[
    多機部署要對齊 `ROS_MASTER_URI`、`ROS_IP`/`ROS_HOSTNAME`，兜不起來是最常見的排錯來源之一。
  ]
][
  #card(tint: palette.ink-soft, title: [無法區分可靠性需求], icon: [③])[
    TCPROS 底層只有一種行為，要嘛都保證送達、要嘛都不保證，沒有語彙可以逐一挑選。
  ]
]
#v(.5em)
#callout(
  kind: "tip",
  compact: true,
)[這三件事正是主僕式架構本身在分散式系統裡固有的代價。下一節換一種解法：把「誰知道全貌」從一個特定節點，換成讓每個節點自己去認識彼此。]

#speaker-note[
  但「配對」這件事本身是中心化的，整個系統只有一個 Master，而且它是單點，這正是主僕式架構的通性。`roscore` 掛掉，不會讓已經建立的 TCP 連線斷掉，正在跑的 node 之間還能繼續收發資料，但任何「新加入」的行為全部停擺，新開一個 node 沒有地方可以登記，沒有地方可以查詢。更麻煩的是多機台場景：每一台機器上的每一個 node，都要透過環境變數 `ROS_MASTER_URI` 指向同一個 Master 位址，而且每個 node 自己還要用 `ROS_IP` 或 `ROS_HOSTNAME` 讓其他機器能反過來連上它。這組態在單機開發時毫無感覺，一旦變成多機部署，`ROS_MASTER_URI`/`ROS_IP` 兜不起來就成了最常見的排錯來源之一。除此之外，這一版的中介層也沒有替「訊息可以掉包」跟「訊息一定要送達」這兩種需求留語彙，TCPROS 底層只有一種行為。

  這三件事，單點協調者、每個節點都要知道協調者位址、無法區分訊息的可靠性需求，正是主僕式架構本身在分散式系統裡固有的代價。下一節看同一個問題换一種解法，把「誰知道全貌」這件事從一個特定節點，換成讓每個節點自己去認識彼此。
]

= Part 1 · DDS

== 去中心化的發現協定

#image("assets/dds_discovery.svg", width: 88%)

#speaker-note[
  另一種你多半也見過的模式是：不設任何中央協調者，每個節點週期性地對外廣播「我是誰、我在哪」，聽到廣播的人自己記下來，沒有人負責批准，也沒有人擁有全貌。這正是 ROS2 的通訊層底下，DDS（Data Distribution Service）採用的模式。DDS 是 OMG（Object Management Group）訂的一個既有工業標準，原本用在航空、國防、金融交易這些對即時性跟容錯要求極高的系統。ROS2 把這個已經被驗證過的去中心化 pub/sub 中介層，套上機器人常用的介面（node、topic、message type）。

  DDS 解決「誰在跟誰講話」這個配對問題的手法，精確來說是一個兩階段的發現協定（discovery protocol），底層跑在 RTPS（Real-Time Publish-Subscribe）這個標準線路協定上，而且完全不需要任何中央伺服器。第一階段叫 Participant Discovery Protocol（PDP）：每一個 DDS participant（在 ROS2 裡，大致對應一個 node）週期性地用 UDP multicast 廣播一份自我描述，內容包含自己的 GUID、監聽的位址跟 port。任何在同一個 multicast group 裡的 participant 收到這份廣播，就把發送者記進自己的本地表，這裡沒有任何一方「批准」誰可以加入，每個 participant 都是對等的觀察者，自己維護自己看到的世界。第二階段叫 Endpoint Discovery Protocol（EDP）：兩個 participant 已經透過 PDP 互相認識之後，會交換各自底下所有的 writer（publisher 端點）跟 reader（subscriber 端點）的詳細描述，包括 topic 名稱、資料型別、以及一整組 QoS policy。
]

== QoS 相容是一個偏序關係

#equation[$
  "match"(r, w) quad "iff" quad "name"(r)="name"(w) ", " "type"(r)="type"(w) ", " "QoS"(r) subset.eq.sq "QoS"(w)
$]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.green, title: [✓ 相容], icon: [])[
    reader 要求 `RELIABLE`，writer 承諾 `RELIABLE`（保證送達、必要時重傳）。writer 給得出 reader 要求的保證。
  ]
][
  #card(tint: palette.rose, title: [✕ 不相容], icon: [])[
    reader 要求 `RELIABLE`，writer 只承諾 `BEST_EFFORT`（送了就算，不重傳）。reader 要求的保證，writer 給不出來。
  ]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[現場排錯症狀：兩個 node 在 `ros2 node info` 裡互相看到對方，拓樸正常，卻死活收不到訊息，幾乎都是 QoS 不相容。「拓樸正常但沒資料」≈「去檢查 QoS」。]

#speaker-note[
  配對是否成立，由一個明確的相容關係決定：一個 reader 跟一個 writer 匹配，若且唯若三個條件同時成立，topic 名稱相等、資料型別相等，而且雙方的 QoS policy 逐項相容。QoS 相容是一個偏序關係，比相等寬鬆，舉 reliability 這條 policy 為例，writer 承諾 `RELIABLE`（保證送達、必要時重傳）比承諾 `BEST_EFFORT`（送了就算，不重傳）更強，一個要求 `RELIABLE` 的 reader 可以跟 `RELIABLE` 的 writer 配對，但不能跟只承諾 `BEST_EFFORT` 的 writer 配對，因為 reader 要求的保證，writer 給不出來。這個相容檢查在每一對 writer/reader 之間獨立進行，結果就是全系統的配對關係是一張根據名稱、型別、QoS 三個維度算出來的相容圖，沒有任何單一節點知道或需要知道這張圖的全貌。

  這個模型立刻解決了 Part 0 列出的三個問題。沒有 Master，自然沒有單點：任何一個 node 掛掉，只是這張相容圖上少了幾個頂點，發現協定會自己收斂到新的狀態。多機部署也不再需要手動指定「誰是 Master」，只要處在同一個 multicast domain（用 `ROS_DOMAIN_ID` 隔開不同的邏輯系統），機器之間互相發現是自動的。而 QoS 從「不存在的概念」變成配對協定裡的一級公民，最典型的排錯情境是一邊用預設的 `RELIABLE`、另一邊（通常是感測器 driver）為了效能刻意設成 `BEST_EFFORT`，兩者永遠配不上。這個症狀值得先記在心裡，這跟 ROS1 時代「先看 `ROS_MASTER_URI` 對不對」是同一個層級的反射動作，只是換了一個要檢查的東西。
]

== rmw 抽象層

#row(widths: (1fr, 1fr), gutter: 1em)[
  #col(gap: .5em)[
    #card(tint: palette.iris, title: [分層], icon: [🧱])[
      `rclcpp` / `rclpy` → `rcl` → `rmw` → 特定 DDS 實作（Fast-DDS、Cyclone DDS、RTI Connext ⋯）。上層寫的只是介面，跟 OS 課裡系統呼叫抽象掉裝置驅動是同一種手法。
    ]
  ]
][
  #callout(
    kind: "info",
  )[抽象不是免費的：multicast 是否可用、discovery storm 的頻寬開銷，最終仍取決於底下真正跑的是哪一個 DDS 實作。節點數超過幾十個時，discovery 流量本身會變成要調校的效能問題。]
]

#speaker-note[
  有一件事必須說清楚，免得誤會 ROS2 節點就是 DDS participant。ROS2 在 DDS 之上還有一層叫 `rmw`（ROS middleware interface）的抽象層，這一層存在的理由是讓 DDS 廠商可以被替換，而不需要改動上層的 rclcpp/rclpy 程式碼，這跟作業系統課裡系統呼叫抽象掉底層裝置驅動，是同一種設計手法，上層寫的只是介面。但這層抽象不是免費的，發現協定的細節最終還是取決於底下真正跑的是哪一個 DDS 實作，這也是為什麼在超過幾十個 node 的系統裡，discovery 流量本身開始變成一個要調校的效能問題。
]

= Part 2 · Topic

== Topic 很單薄，複雜度全下推到 DDS

#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.teal, title: [`KEEP_LAST(n)`（預設）], icon: [])[
    只保留最新的 `n` 筆，佇列滿了就丟最舊的一筆。`n` 預設 10。
  ]
][
  #card(tint: palette.amber, title: [`KEEP_ALL`], icon: [])[
    試圖保留所有還沒被消費的訊息，直到觸及 resource limit。
  ]
]
#v(.5em)
#callout(
  kind: "info",
  compact: true,
)[Depth 決定的是：subscriber 處理速度跟不上 publisher 時，哪一筆訊息會被留下來。正常運作時「最新一筆」跟「照時間順序不漏接」看起來一樣，系統過載時兩者的行為就會分岔。]

#speaker-note[
  有了 DDS 這層地基，topic 這個概念本身其實非常單薄：一個 topic 就是一個字串名稱加上一個訊息型別，publisher 呼叫 `create_publisher<T>(name)`，subscriber 呼叫 `create_subscription<T>(name, callback)`，剩下的配對工作，名稱比對、型別比對、QoS 相容檢查，全部發生在 DDS 發現層。這種「介面極簡、複雜度下推到底層」正是好中介層的標誌。

  真正需要仔細講的是 QoS policy 裡跟訊息緩衝行為直接相關的兩條。History policy 有兩種模式，`KEEP_LAST(n)` 只保留最新的 `n` 筆，新訊息進來時如果佇列已滿就丟棄最舊的一筆，這是預設值，`n` 預設是 10。`KEEP_ALL` 則試圖保留所有還沒被消費的訊息，直到觸及 resource limit 為止。Depth 這個數字，決定的是在 subscriber 處理速度跟不上 publisher 發布速度時，哪一筆訊息會被留下來。如果 callback 處理一筆感測器資料的時間，比感測器發布的週期還長，佇列會持續補進新資料、擠掉舊資料，subscriber 拿到的永遠是當下最新收到的一筆，這跟照時間順序一筆不漏地處理，在正常運作、佇列從來沒滿過的時候看起來完全一樣，一旦系統過載，兩者的行為就會分岔。
]

== Executor：誰、什麼時候真的處理這筆訊息

#image("assets/executor_queue.svg", width: 92%)

#speaker-note[
  訊息真正被消費的時機，還牽涉到 executor 這個角色。DDS 層把資料放進 subscriber 的本地佇列之後，真正決定何時、依照什麼順序，把佇列裡累積的 callback 一個一個實際執行的，是 executor 這個排程器。單執行緒 executor（`rclcpp::executors::SingleThreadedExecutor`）用一個迴圈輪流檢查所有註冊在它底下的 callback 有沒有工作要做，同一時間只執行一個。這代表如果某一個 callback 跑得很久，其他所有 topic、包括 timer，都會被這一個 callback 卡住，不會插隊。topic 的訊息什麼時候真的被處理，是由訂閱端的 executor 排程決定的。
]

= Part 3 · Service

== 建立在 pub/sub 之上的請求回應

#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [Topic], icon: [→])[單向資料流，誰發布、誰訂閱不需要對應關係。]
][
  #card(tint: palette.teal, title: [Service], icon: [⇄])[一來一往的請求回應，一個 request 對應恰好一個 response。]
]
#v(.5em)
#callout(
  kind: "info",
)[實作上，service 底層仍然建立在 DDS 的 pub/sub 之上：每個 service 背後有一對 DDS topic（request / response），透過 sequence number 跟 client GUID 互相關聯。ROS2 沒有另造 RPC 機制，是用同一套 pub/sub 語彙疊上關聯資訊，模擬出請求回應的語意。]

#speaker-note[
  Service 提供的是跟 topic 完全不同的通訊型態，topic 是單向的資料流，誰發布、誰訂閱不需要對應關係。service 是一來一往的請求回應，一個 client 發出一個 request，對應恰好一個 server 回傳恰好一個 response。實作上，ROS2 的 service 底層仍然建立在 DDS 的 pub/sub 之上，每個 service 背後其實有一對 DDS topic，一個承載 request、一個承載 response，兩者透過請求裡帶的一組 sequence number 跟 client GUID 互相關聯，server 收到 request 之後，把同一組關聯資訊原封不動地附進 response，client 才能把收到的一堆 response 正確配對回自己發出的哪一個 request。這個設計解釋了為什麼 service 呼叫看起來像函式呼叫，底層卻仍然沒有脫離「發布/訂閱」這個唯一的通訊原語。
]

== 同步呼叫在單執行緒 executor 裡的死結

#image("assets/service_deadlock.svg", width: 92%)

#speaker-note[
  Client 端呼叫 service 有同步跟非同步兩種介面，這裡的差異關係到會不會 deadlock，值得認真講。同步呼叫（`call`）會阻塞呼叫它的那個執行緒，直到 response 抵達為止。非同步呼叫（`async_send_request`）立刻回傳一個 future，呼叫端之後再自己決定何時去檢查這個 future 有沒有完成。危險的地方在於，如果你在一個 node 的 callback 裡面，對另一個（或甚至同一個）node 同步呼叫 service，而這個 node 本身是用單執行緒 executor 跑的，你就製造了一個死結。這個執行緒正卡在 `call` 裡等 response，但 response 要能被處理，前提是 executor 要能繼續跑它的迴圈去執行收到 response 之後的那個 callback，而 executor 只有這一個執行緒，已經被你手上這個尚未回傳的 `call` 佔用，永遠輪不到自己去把 response 撈出來。這是 ROS2 現場最容易踩、卻最難從錯誤訊息猜到原因的坑之一，症狀通常只是呼叫卡住，沒有任何錯誤，也沒有超時。這也是為什麼 ROS2 官方文件會建議在 callback 內部一律使用非同步呼叫，或是把該 service 的呼叫端另外配置到獨立的 callback group，跑在多執行緒 executor 上。
]

= Part 4 · Action

== 三個 service 加兩個 topic

#row(widths: (1fr, 1fr, 1fr), gutter: .6em)[
  #card(
    tint: palette.iris,
    title: [goal service],
    icon: [①],
    inset: .75em,
  )[#set text(size: .85em); client 發起，server 決定接受或拒絕。]
][
  #card(
    tint: palette.amber,
    title: [cancel service],
    icon: [②],
    inset: .75em,
  )[#set text(size: .85em); client 中途放棄，server 決定能否安全中止。]
][
  #card(
    tint: palette.rose,
    title: [get_result service],
    icon: [③],
    inset: .75em,
  )[#set text(size: .85em); 任務結束後，取得最終結果。]
]
#v(.4em)
#row(widths: (1fr, 1fr), gutter: .6em)[
  #card(
    tint: palette.teal,
    title: [feedback topic],
    icon: [~],
    inset: .75em,
  )[#set text(size: .85em); 持續發布進度資訊，純粹 pub/sub。]
][
  #card(
    tint: palette.ink-soft,
    title: [status topic],
    icon: [~],
    inset: .75em,
  )[#set text(size: .85em); 回報目前狀態機所在的狀態。]
]
#v(.35em)
#callout(
  kind: "tip",
  compact: true,
)[Action 沒有引入任何新的底層通訊機制，理解這個組合關係，比死記 API 更重要：往後 action 卡住，都可以拆回「這其實是哪一個 service 或 topic 出問題」來排查。]

#speaker-note[
  Action 是 ROS2 裡表達「長時間執行、可回報進度、可以中途取消」這種任務最自然的原語，像是「導航到某個座標」「移動手臂到某個姿態」都適合用 action 表達。Action 本身沒有引入任何新的底層通訊機制，它精確地是由前面兩節介紹過的東西組合出來的：三個 service（goal、cancel、get_result）加上兩個 topic（feedback、status）。

  Goal service 由 client 發起，帶著目標參數，server 端（action server）收到之後決定接受或拒絕這個 goal，這個接受/拒絕的判斷本身就是一次同步的請求/回應。一旦 goal 被接受，action server 就開始執行，執行期間透過一個獨立的 feedback topic，持續發布進度資訊，這是純粹的 pub/sub，client 可以選擇要不要訂閱。Client 如果想中途放棄，呼叫 cancel service，server 收到後決定能不能安全地中止。任務結束時，不管是正常完成、被取消、還是失敗，client 呼叫 get_result service 取得最終結果。
]

== Action 的有限狀態機

#image("assets/action_fsm.svg", width: 90%)

#speaker-note[
  整個生命週期，可以精確地寫成一個有限狀態機：一個 goal 進來後處在 `ACCEPTED`，action server 呼叫 `execute` 進入 `EXECUTING`。在 `EXECUTING` 期間收到 cancel 請求，轉入 `CANCELING`，這個狀態存在的理由是承認「取消」本身可能需要時間，才會需要一個過渡狀態。從 `EXECUTING` 或 `CANCELING` 最終都會落入三個終止狀態之一：`SUCCEEDED`、`ABORTED`、`CANCELED`。這三個終止狀態一旦進入就不可逆，get_result service 回傳的正是這三者之一。把 action 拆成這五個訊號、四個離散狀態來理解的好處是，當一個 action 卡住不動，你可以精確地問「它停在狀態機的哪一格」，再回頭對應到「所以是哪一個底層的 service 或 topic 沒有正確送達」。而 service 沒有正確送達的原因，往回看，常常就是 Part 3 講的那個單執行緒 executor 死結，或是 Part 1 講的 QoS 不相容，三個 Part 在這裡收斂成同一組排錯直覺。
]

= Part 5 · TF

== TF 難在兩種思考方式要同時成立

#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.iris, title: [數學], icon: [∑])[
    把每一次量測、每一個感測器安裝位置，精確地寫成 `SE(3)` 裡的一個元素，照 Week 4 的規則做合成、取逆。
  ]
][
  #card(tint: palette.teal, title: [系統實作], icon: [⚙])[
    這些 `SE(3)` 元素由不同 node、以不同頻率、在不同時刻發布出來，發布本身要遵守拓樸規則。
  ]
]
#v(.5em)
#callout(
  kind: "warn",
  compact: true,
)[一行程式碼出錯，要分辨到底是數學錯了（合成順序、取逆、旋轉慣例弄反），還是時序錯了（query 到的那筆資料根本不是你以為的那個時刻）？]

#speaker-note[
  TF 難的地方，是它同時要求兩種完全不同的思考方式同時成立。一種是數學，把每一次量測、每一個感測器安裝位置，精確地寫成 `SE(3)` 裡的一個元素，照 Week 4 教過的規則做合成、取逆。另一種是系統實作，這些 `SE(3)` 元素由不同的 node、以不同的頻率、在不同的時刻發布出來，而且發布這件事本身要遵守拓樸上的規則。這兩件事分開來看都不難，難的是同時在腦中維護兩套判斷。一行程式碼出錯，你要先分辨，是數學錯了，合成順序弄反、取逆弄錯、旋轉慣例弄反，還是時序錯了，query 到的那筆資料根本不是你以為的那個時刻。
]

== 座標系的樹，邊是 SE(3) 元素

#equation[$ T^(-1) = (R^T, - R^T p) $]
#v(.6em)
#callout(
  kind: "info",
)[TF 把機器人跟它的感測器表示成一個有向樹：每一個節點是一個座標系（frame），每一條邊是一個 rigid transform，精確來說是 Week 4 定義過的 `SE(3)` 元素，由旋轉 `R` 跟平移 `p` 構成。]
#v(.4em)
#callout(
  kind: "tip",
  compact: true,
)[要問「A 相對於 B 的 pose 是什麼」：沿著樹走到兩者的最近共同祖先，把沿途每一條邊的 `SE(3)` 元素依序合成。方向跟父子關係相反的邊，合成前先取逆，用的正是上面這條 Week 4 已經證過的公式。]

#speaker-note[
  TF 把整個機器人跟它的感測器，表示成一個有向樹：每一個節點是一個座標系（frame），每一條邊是一個 rigid transform，精確來說是 Week 4 定義過的 `SE(3)` 元素，由一個旋轉 `R` 跟一個平移 `p` 構成。要問「A 相對於 B 的 pose 是什麼」，答案是沿著樹走到兩者的最近共同祖先，把沿途每一條邊的 `SE(3)` 元素依序合成，方向跟樹的父子關係相反的邊，合成前先取逆，Week 4 已經證過的取逆公式 `T⁻¹ = (Rᵀ, −Rᵀp)` 原封不動地在這裡用。這一步全部是純數學，樹的形狀在任何一個瞬間都是固定的。
]

== AMR 的座標樹

#image("assets/tf_tree.svg", width: 88%)

#speaker-note[
  以一台典型的移動機器人為例，`map` 是根，它的子節點是 `odom`，`odom` 的子節點是 `base_link`，`base_link` 底下再分出 `laser_link`、`imu_link`、`mast_link` 三個子節點，`mast_link` 底下接 `camera_link`，`camera_link` 底下接 `camera_optical_frame`。這棵樹的形狀在任何一個瞬間都是固定的，會變的是每一條動態邊上，隨時間累積的樣本，這是下一頁要處理的問題。
]

== Static 與 Dynamic：QoS 又出場一次

#table(
  columns: (auto, 1fr, 1fr),
  [], [*Static*（`laser_link`、`imu_link`⋯）], [*Dynamic*（`odom → base_link`）],
  [Topic], [`/tf_static`], [`/tf`],
  [廣播頻率], [一次], [持續，每筆帶時間戳],
  [QoS durability], [`TRANSIENT_LOCAL`], [`VOLATILE`（預設）],
  [遲加入的訂閱者], [直接拿到最後一筆], [要等下一次廣播],
)

#speaker-note[
  真正把 TF 變複雜的是下一件事：每一條邊其實是隨時間變化的一串樣本。像 `imu_link` 相對於 `base_link` 這種邊，感測器裝上去之後位置不會再變，這種邊只需要廣播一次，叫 static transform，走一個獨立的 `/tf_static` topic，而且用 QoS 的 `TRANSIENT_LOCAL` durability 設定發布，這正是 Part 1 講過的 QoS policy 派上用場的地方，遲加入的訂閱者不需要等下一次廣播，可以直接拿到歷史上發布過的最後一筆訊息。像 `odom` 相對於 `base_link` 這種邊，機器人一直在動，這種邊要持續廣播，叫 dynamic transform，走 `/tf` 這個 topic，而且每一筆都帶一個時間戳。
]

== 時間戳把 lookup 變成一個插值問題

#equation[$ alpha = (t - t_0)/(t_1 - t_0), quad p(t) = "lerp"(p_0, p_1; alpha), quad R(t) = "slerp"(R_0, R_1; alpha) $]
#v(.6em)
#callout(kind: "info")[`slerp` 精確地是 Week 4 提過的、在 `SO(3)` 上以固定角速度沿測地線走的插值。]
#v(.4em)
#callout(
  kind: "tip",
  compact: true,
)[若 `t` 落在時間窗外，Buffer 拒絕外插，丟出例外，把「這筆資料到底存不存在」明確地交還給呼叫者，不會偷偷回傳一個瞎猜的值。]

#speaker-note[
  有時間戳的邊，把 lookup 這件事變成一個插值問題。tf2 的 Buffer 對每一條 dynamic 邊保留一段時間窗內的樣本，查詢在時刻 `t` 的 pose 時，如果 `t` 落在某兩筆樣本 `(t₀,T₀)`、`(t₁,T₁)` 之間，平移取線性插值，旋轉取 slerp，精確地是 Week 4 提過的、在 `SO(3)` 上以固定角速度沿測地線走的那個插值。如果 `t` 落在整段時間窗之外，Buffer 選擇丟出例外，拒絕外插，把「這筆資料到底存不存在」這個決定，明確地交還給呼叫者。
]

== TimePointZero 的陷阱

#row(widths: (1fr, 1fr), gutter: .9em)[
  #card(tint: palette.green, title: [✓ 正確配對], icon: [])[
    掃描匹配的答案描述 `t−150ms` 那一刻，就去 Buffer 查 `t−150ms` 時刻的里程計樣本，兩者在同一時刻為真。
  ]
][
  #card(tint: palette.rose, title: [✕ TimePointZero 陷阱], icon: [])[
    傳入 `TimePointZero`：「不管哪個時刻，給我最新一筆」，直接跳過插值，拿到的是查詢當下的最新樣本。
  ]
]
#v(.5em)
#callout(
  kind: "danger",
)[把「最新一筆」拿去跟另一個帶明確時間戳的量測合成，兩個 `SE(3)` 元素從來沒有在同一時刻為真過。合成結果型別上完全合法，數值上卻是兩個不同時刻拼出來的假象，跟 Week 4 複數平均 179° 與 −179° 的陷阱，是同一種錯誤的不同臉孔。]

#speaker-note[
  這裡有一個容易被忽略的捷徑：呼叫 lookupTransform 時傳入 `TimePointZero`，意思是「不管哪個時刻，給我目前緩衝區裡最新的一筆」，直接跳過插值邏輯。這個捷徑本身沒有錯，但如果你把這樣拿到的「最新」樣本，拿去跟另一個帶著明確時間戳的量測合成，你合成的兩個 `SE(3)` 元素，實際上從來沒有在同一個時刻為真過，合成出來的結果在型別上完全合法，數值上卻是兩個不同時刻拼出來的假象。這正是「數學上合法，物理上荒謬」在 TF 世界的版本，跟 Week 4 複數平均那個 179 度跟 -179 度的陷阱，是同一種錯誤的不同臉孔。
]

== 誰能發布哪條邊：map → odom 的修正模式

#row(widths: (1.1fr, 1fr), gutter: 1em, align: horizon)[
  #image("assets/tf_tree_example.png", width: 100%)
  #source-note[真實的 `view_frames` 輸出（turtlesim 範例），可看到每條邊各自的發布頻率與緩衝長度]
][
  #callout(
    kind: "info",
  )[同一條邊、同一時刻，只能有一個發布者。輪式里程計獨佔 `odom → base_link`（毫秒級頻率），定位獨佔 `map → odom`（慢、有處理延遲的修正量）。兩個節點各自只負責自己那條邊。]
]

#speaker-note[
  樹的拓樸還有一條容易被忽略的規則：同一條邊，同一時刻，只能有一個發布者。這條規則直接決定了 `map` 到 `base_link` 之間為什麼要拆成 `map` 到 `odom`、`odom` 到 `base_link` 兩條邊，各自只有一個發布者。輪式里程計用毫秒等級的頻率持續估計 `odom` 到 `base_link`，這條邊它自己獨佔。定位用慢得多、而且有處理延遲的頻率去估計「里程計 drift 了多少」，把這個修正量發布成 `map` 到 `odom`。兩個節點各自只負責自己那條邊，樹在任何時刻都只有一個合法的答案，下游要問「機器人在地圖上的哪裡」，系統自動把兩條邊合成起來，拿到兩者都納入的答案。這個切法本身就是把 Part 2 提過的「不同的訊息有不同的新鮮度」這件事，直接刻進樹的結構裡。
]

== 旋轉慣例的陷阱：REP-103

#image("assets/camera_optical_rotation.svg", width: 88%)

#speaker-note[
  最後回到數學那一半容易踩的坑：一條邊的旋轉部分，選錯慣例，不會讓樹斷掉，只會讓數字是錯的。相機這條邊是最典型的例子：`camera_link` 遵守機器人慣例，x 軸朝前、z 軸朝上，`camera_optical_frame` 遵守視覺慣例，z 軸朝前、y 軸朝下，兩者之間差一個固定的旋轉，這個旋轉在每一份相機驅動裡都要手動乘上去。漏掉它，TF 樹照樣是一整棵連通的樹，每個 lookup 照樣有合法的回傳值，只是這個回傳值，跟相機實際看到的方向，差了一個旋轉。這件事再一次呼應 Part 1 的教訓，拓樸正常不等於數值正確，那裡是 QoS 配對正常但資料沒送到，這裡是樹連通正常但角度是錯的，兩個症狀分屬不同的層次，但診斷的態度是同一個，永遠先確認資料真的存在、再去檢查資料是不是對的。
]

#ending-slide(title: [Q & A])
