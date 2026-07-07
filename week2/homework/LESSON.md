# homework

**對應主線**：Part 4（VLA 收尾：視覺 state + 語言指令 + 動作序列，三者匯合成一個 BC policy）  
**資料集**：[HuggingFaceVLA/smol-libero](https://huggingface.co/datasets/HuggingFaceVLA/smol-libero)（LIBERO 精簡版，50 段 Franka 機械手臂遙操作示範，兩個固定機位、7 自由度關節動作、一句自然語言任務指令）

Part 1 是單步 state→action。Part 2 把 state 換成「歷史動作序列」，練 autoregressive 生成。Part 3 把 state 換成「一張影像」，練感知。這一段把三者收斂成一個模型：給定**一張影像 + 一句語言指令 + 一段動作歷史**，預測下一步（或下一小段）動作。

**動作預測正確率不是評分重點**：`smol-libero` 這個精簡子集其實只有 1 種任務、50 段示範，資料量不足以訓練出真的能用的 policy。這份作業要驗收的是**架構本身**：資料怎麼從三種模態流進模型、cross-attention 怎麼把視覺和語言融合、訓練迴圈長什麼樣子，能在 report 裡看到「模型對某張圖 + 某句指令，輸出了什麼動作」就達標。

## 0. 環境

在 `week2/` 底下：

```bash
uv run python cli.py train homework --help
```

第一次執行會從 Hugging Face Hub 下載 `HuggingFaceVLA/smol-libero`（1.79GB，含兩個機位、256x256 影像），比前兩段的資料集大。

## 1. 資料：三種模態怎麼變成一個訓練樣本

打開 `src/data.py`。跟 Part 2/Part 3 最大的不同：這裡的動作是 **7 維**（x, y, z, roll, pitch, yaw, gripper），不是 push-T 的 2 維像素座標，而且機器人關節指令沒有 push-T 那種天然的 `[0, 512)` 畫布範圍。於是動作的離散化（bin 邊界）不能像 Part 2 那樣直接假設一個固定範圍，而是從訓練集資料本身算出分位數（quantile）當 bin 邊界。

7 維動作各自獨立離散化（各自一組 `bins_per_dim` 個 bin），而不是像 Part 2 那樣把兩維合併成一個 `bins_per_dim ** 2` 大小的聯合字彙。這裡如果比照 Part 2 合併 7 維，字彙表會是 `bins_per_dim ** 7`，大到不可能訓練。RT-1/OpenVLA 等真實 VLA 論文遇到多維動作時，也是每個維度各自的 token，這裡是同一個簡化。

語言指令（`meta/tasks.jsonl`，不在 parquet 欄位裡，另外下載）用一個極簡的 word-level tokenizer 處理：切詞、建字彙表、指令補齊（padding）到固定長度。這個資料集其實只有一種指令，`word_to_id` 的字彙表很小，但程式碼本身沒有假設「只有一句指令」，換一個真正多任務的 LIBERO 子集也能直接跑。

**每個訓練樣本長什麼樣（`get_batch`）**：從某個 episode 裡挑一個起點 `t0`，拿：
- **一張影像** `images[t0]`（這個動作區塊（chunk）開始那一刻的觀測，不是每一步都重新看一次影像）
- **一句指令**（同一個 episode 全程不變）
- **`block_size` 步動作歷史**（`actions[t0:t0+block_size]`）當輸入，**shift 一步**（`actions[t0+1:t0+block_size+1]`）當 target，跟 Part 2 的 next-token 訓練完全一樣的 teacher forcing

「一張影像撐起一整個動作區塊」是 ACT/RT-2 這類「action chunking」policy 的標準做法：機器人不是每個動作都重新看一次相機畫面，而是看一眼、盲跑一小段。這既符合真實 VLA 的工程習慣，也是計算上便宜的做法：每個訓練視窗只需要跑一次影像編碼，不是跑 `block_size` 次。

## 2. 模型：三個 encoder 餵一個融合 decoder

打開 `src/models.py`。三條輸入各自有一個 encoder：

- `VisionEncoder`：Part 3 `TinyViT` 的 patch embedding 骨幹（patchify → 線性投影 → 幾層非因果 self-attention），拿掉 CLS token 和分類頭。這裡要的是一整串 patch token，不是一個壓縮向量，因為後面的 decoder 需要「東西可以 cross-attend 進去」。
- `LanguageEncoder`：同一種非因果 self-attention 骨幹，套用在文字 token 上，多一個 padding mask（指令長度不夠 `max_instruction_len` 補的 0 不該被注意力看到）。

`VLAPolicy.encode_context` 把兩者的輸出接起來，變成一個長度 = `n_patches + max_instruction_len` 的 context 序列。**這就是「VLM 式融合」的輸入**：視覺 token 和語言 token 混在同一個序列裡，讓 decoder 自己決定每一步要看影像還是看指令。

`VLAPolicy` 的主體是 `block_size` 步動作 token 的 decoder，每一層 `FusionBlock` 做三件事：
1. **因果 self-attention**（跟 Part 2 的 `CausalSelfAttention`完全相同）：動作歷史裡，每一步只能看自己與更早的步。
2. **cross-attention**（新機制）：每一個動作 token 當 query，去讀取上面那個融合後的 [視覺 token, 語言 token] context。**這裡不需要 causal mask**，因為 context 是固定的、跟 query 在哪個時間步無關（同一張影像和同一句指令，每一步都能完整看到）。跟 Part 3 學過的「有沒有時間順序決定要不要 mask」是同一個原則，只是這裡的「無時間順序」換成「context 對所有 query 一視同仁」。
3. **MLP**（跟前面每個 lab 一樣）。

7 個動作軸各自有自己的 embedding table（輸入）和分類頭（輸出）。`torch.stack([head(x) for head in self.heads], dim=2)` 把 7 個 `(B, T, bins)` logits 疊成 `(B, T, 7, bins)`，訓練時攤平成 `(B*T*7, bins)` 算 cross-entropy，一次前向傳播對整個視窗的每一步、每一軸都算出梯度訊號（跟 Part 2 一樣的「平行訓練」效率手法，不是每個位置分開跑一次）。

## 3. 訓練

```bash
uv run python cli.py train homework
```

跑完後打開 `artifacts/<run_id>/report/index.html`。留意幾件事：

- **Loss / Action L2 曲線**：這裡的 loss 是 7 個軸的 cross-entropy 平均,不是單一數字的迴歸誤差。Action L2 是把預測 token 解碼回原始單位（公尺、弧度、gripper 指令混在一起）算 L2 距離,**只是粗略指標**,7 個軸單位不同,不是一個嚴謹的誤差量測,只用來確認「訓練有沒有在動」。
- **每個 epoch 的預測面板**：每個樣本是模型在某個 held-out window 開始時看到的畫面 + 指令，表格比較「模型預測的下一步動作」跟「示範者實際動作」在 7 個軸上的數值。50 段示範、單一任務，不要預期這個數字會準，能看到訓練過程中預測值逐漸往實際值靠近的**趨勢**就達標。
- **Cross-attention 融合面板**：這是這段作業最值得看的東西。訓練完的最後一個 checkpoint，對固定一個 held-out window，把動作 decoder 每一層 cross-attention 的權重（averaged over heads 和 decode steps）畫出來，左邊是影像 patch 的熱力圖，右邊是每個字的權重深淺，下方列出「影像 vs. 指令」的權重佔比。這是「模型有沒有真的在融合兩種模態」的直接證據，不是靠猜的。

## 4. 查詢

```bash
# 訓練過程摘要
uv run python cli.py explore homework metrics --run <run_id>

# 用訓練好的模型對某個 held-out window 做預測
uv run python cli.py explore homework predict --run <run_id> --episode 0 --offset 0

# 印出 cross-attention 在視覺/語言之間的權重佔比、每個字的權重
uv run python cli.py explore homework attention --run <run_id> --episode 0 --offset 0
```

## 5. 選讀：一次 OOD（corruption）測試

**OOD（out-of-distribution，分布外）** 指的是模型在測試時看到的輸入，跟訓練時看過的資料長得不一樣，超出了訓練分布涵蓋的範圍。一個 policy 在訓練集上表現再好，只要部署環境跟訓練資料有落差（換一個房間的光線、鏡頭角度偏一點、畫面多了雜訊），都算是在測 OOD 泛化能力。這裡示範最簡單的一種 OOD：把輸入影像加上人工雜訊，模擬「這張圖片跟訓練時看過的畫面不太一樣」的情境，跟真正部署到新環境比起來，這是一個便宜、可控、不用真的換場景就能做的粗略替代品。

`explore.py` 留了一個 `corrupt` 子指令，把 conditioning 影像加上高斯雜訊，比較「乾淨影像的預測」跟「加雜訊後的預測」差多少：

```bash
uv run python cli.py explore homework corrupt --run <run_id> --episode 0 --offset 0 --noise-std 0.3
```

如果模型真的有在用影像資訊（而不是只記住那句固定不變的指令），雜訊夠大時預測應該會明顯偏移，這代表模型對輸入分布的變化很敏感，OOD 泛化能力可能不好。如果不管雜訊多大預測都紋風不動，可能代表這個訓練規模下模型幾乎沒學會依賴視覺輸入，退化成只靠語言指令背答案，考慮到只有 50 段示範、1 種任務，這其實是預期中可能發生的結果，不是程式碼的錯誤，也不算是「通過了 OOD 測試」，只是模型本來就沒在用影像做決策。想再往下延伸，可以比較 `--noise-std` 從 0 掃到 1 的預測位移量，畫出「雜訊強度 vs. 預測偏移量」的曲線，這就是一個簡化版的 OOD robustness 分析。

## 6. 反思問題

1. `data.py` 用「訓練集分位數」當 bin 邊界，而不是像 Part 2 用固定的畫布範圍。如果某個動作軸（例如 gripper，幾乎只有 -1/1 兩種值）分位數算出來大量重複，會發生什麼事？這對那一軸的 token 化品質有什麼影響？
2. 把 `configs/default.yaml` 的 `block_size` 從 8 改成 2 或 20 重新訓練。訓練速度、val loss、cross-attention 熱力圖的分布,分別會怎麼變？（提示：`block_size` 越大,同一張影像要撐起的「盲跑」步數越多,decoder 要更依賴動作歷史自己補足資訊。）
3. Report 裡「Cross-attention 融合」面板顯示的視覺/語言權重佔比，如果訓練更久，你預期會往哪個方向移動？（提示：這個資料集只有一句指令，語言訊號從頭到尾都一樣，理論上對「預測下一步動作」的邊際資訊量很低，模型有沒有可能學到「幾乎不理會語言」也是合理現象？）
4. `VLAPolicy.encode_context` 把視覺 token 和語言 token 直接 `torch.cat` 成同一個 context 序列,而不是分開兩次 cross-attention（一次對視覺、一次對語言）。這兩種寫法在計算量、可解釋性（能不能單獨看「這一步比較依賴影像還是語言」）上各有什麼取捨？

## 附錄：CLI 參數速查

`src/train.py`：
| 參數 | 說明 | 預設（來自 `configs/default.yaml`） |
|---|---|---|
| `--config` / `-c` | 要用哪份 yaml | - |
| `--camera` | `image` 或 `image2`（兩個固定機位） | `image` |
| `--image-size` / `--patch-size` | 影像縮放後的邊長 / patch 邊長 | `128` / `16` |
| `--max-instruction-len` | 指令 token 補齊/截斷長度 | `16` |
| `--bins-per-dim` | 每個動作軸的 token 化 bin 數 | `32` |
| `--block-size` | 動作區塊（chunk）長度 | `8` |
| `--n-embd` / `--n-head` | 共用 embedding 維度 / 注意力頭數 | `128` / `4` |
| `--n-vision-layer` / `--n-lang-layer` / `--n-action-layer` | 視覺 / 語言 / 融合 decoder 各自的層數 | `2` / `2` / `4` |
| `--dropout` | dropout 機率 | `0.0` |
| `--epochs` / `--steps-per-epoch` | 訓練週期數 / 每個 epoch 梯度步數 | `5` / `200` |
| `--lr` / `--batch-size` / `--seed` | AdamW 學習率 / 批次大小 / 隨機種子 | `0.001` / `32` / `0` |
| `--val-episode` / `--prompt-len` / `--gen-length` / `--temperature` | rollout 相關設定 | `0` / `4` / `16` / `0.8` |
| `--n-samples` | 每個 epoch 報告顯示幾個 held-out 樣本 | `4` |
| `--run-id` | 不指定則自動用時間戳記命名 | - |

`src/explore.py` 子指令：`list` / `metrics` / `predict` / `attention` / `corrupt`。除了 `list`/`metrics`，其餘都吃 `--run <run_id>`、`--episode <idx>`（held-out episode 索引）、`--offset <n>`（episode 內的起始 frame），`--epoch` 預設用最新一個。
