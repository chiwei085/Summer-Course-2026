# basic_sequence_bc

**對應主線**：Part 2（序列化：predict 下一步）
**資料集**：[lerobot/pusht_keypoints](https://huggingface.co/datasets/lerobot/pusht_keypoints)（Hugging Face LeRobot 專案，206 段真人遙操作示範，任務是把一個 T 形物塊推到畫面上的固定目標位置）

Part 1 學的是「單步 state→action」：一筆特徵向量進去，一個預測值出來，資料點彼此獨立。這一段把同一個 BC 骨架換成**序列**：給定「目前為止示範者做過的所有動作」，預測他下一步會做什麼動作。

我們先把 `state`（物塊/推桿的位置）和畫面（image）都拿掉，只留下這一串 action 序列，感知（視覺）留給 Part 3，加回 state/語言、完整 VLA 留給 Part 4；Part 2 只練「給定歷史動作，預測下一個動作」這一個機制本身。

## 0. 環境

在 `week2/` 底下：

```bash
uv run python cli.py train basic_sequence_bc --help
```

跟 `basic_regression_classification` 一樣，`--config` 指向 `configs/*.yaml` 覆蓋預設值，CLI 旗標可以再疊上去覆蓋 yaml。第一次執行會從 Hugging Face Hub 下載 `lerobot/pusht_keypoints`（只有低維數值資料，不含影片，下載很快）。

## 1. Action tokenization：把連續動作變成離散字彙

`action` 是連續的 2 維座標（$x, y \in [0, 512)$）。要用跟語言模型完全一樣的「預測下一個 token」機制去預測它，得先把它離散化成有限字彙——這正是 RT-1/RT-2/OpenVLA 等真實 VLA 論文處理連續動作的手法（action tokenization）：把每一維切成固定數量的區間（bin），每個 (bin_x, bin_y) 組合對應一個 token id。

打開 `src/data.py` 的 `TaskData.encode`/`decode`：`bins_per_dim: 16`（見 `configs/default.yaml`）代表每一軸切成 16 格，字彙表大小 = 16×16 = 256——跟 Part 1 拿掉的那句「語言模型只是方便的載體」不同，這裡的 256 個 token 貨真價實地就是「256 種被離散化的推桿目標位置」，不是字母。

## 2. 沒有上下文的基準線：bigram 模型

先跑一個刻意退化的版本：只看「示範者剛剛做的這一個動作」，完全不看更早的歷史，去預測下一個動作。

```bash
uv run python cli.py train basic_sequence_bc --config configs/bigram.yaml
```

打開 `src/models.py` 的 `BigramLM`：整個模型就是一張 `nn.Embedding(vocab_size, vocab_size)` 查表，等於 Part 1 的線性模型把「輸入」換成一個動作 token id。這是「BC policy 拿掉歷史動作」之後會退化成的樣子——一個完全沒有記憶的 policy。

跑完後看 `artifacts/<run_id>/report/index.html`（直接用瀏覽器打開這個檔案路徑即可，不用啟動 server——所有資料都內嵌在頁面裡）。留意「每個 epoch 的 rollout」卡片：灰色線是餵給模型的真實 prompt 動作，綠色實線是示範者接下來實際做的動作，橘色虛線是模型自己 rollout 出來的動作。bigram 模型的橘色虛線通常很快就偏離綠色實線——因為它每一步都只看得到「上一步在哪」，完全不知道這條軌跡整體要往哪裡去。

## 3. 加上因果注意力：transformer 模型

```bash
uv run python cli.py train basic_sequence_bc --config configs/transformer.yaml
```

打開 `configs/transformer.yaml`：`block_size: 32` 是上下文視窗長度（動作步數，206 段示範中最短的一段也有 49 步，所以每段示範都用得到），`n_head`/`n_layer`/`n_embd` 是注意力頭數、層數、embedding 維度。`src/models.py` 的 `CausalSelfAttention` 是手刻的（沒有用 `nn.MultiheadAttention`），方便直接把 attention 權重取出來看。

**核心機制**：`causal_mask`（`torch.tril`，下三角矩陣）把每個位置的注意力限制在「自己與更早的位置」——如果拿掉這個 mask，模型在訓練時就能直接看到「示範者下一步做了什麼」，等於作弊，訓練出來的 policy 在真正部署時（只能看到已經發生的歷史動作，看不到未來）就會完全失效。這正是為什麼 BC 的「歷史動作」輸入必須套用因果限制——不只是語言模型的慣例，是任何 autoregressive policy 的硬性要求。

跑完後一樣打開 `report/index.html`，比較跟 bigram 的 rollout 樣本：transformer 的橘色虛線應該比 bigram 更貼近綠色實線的真實軌跡（不追求完全重合，能看出「明顯比 bigram 準」就達標），rollout 卡片也會印出 L2 誤差（像素）方便量化比較。

## 4. 查詢：模型在關注什麼？

```bash
# 訓練過程摘要
uv run python cli.py explore basic_sequence_bc metrics --run <run_id>

# 用訓練好的模型從某個held-out episode做rollout，跟示範者實際動作比較
uv run python cli.py explore basic_sequence_bc generate --run <run_id> --episode 0 --prompt-len 8 --length 50

# 印出因果注意力矩陣（只對 transformer run 有效）
uv run python cli.py explore basic_sequence_bc attention --run <run_id> --episode 0 --start 0
```

`attention` 印出的矩陣：橫軸是被關注的動作步（key），縱軸是正在預測的動作步（query），數字是注意力權重（一列加總為 1）。**看一下右上角是不是全部是 0**——這就是 causal mask 的直接證據：每一步只能往「更早發生」的動作看，看不到自己之後才發生的動作。

`report/index.html` 裡的「Causal attention」卡片是同一份資料的表格版本，訓練完的最後一個 checkpoint 對固定一段 held-out 示範算出來的。

## 5. temperature 如何影響 rollout

用同一個 checkpoint、不同的 `--temperature` 比較 rollout 結果：

```bash
uv run python cli.py explore basic_sequence_bc generate --run <run_id> --episode 0 --temperature 0.3
uv run python cli.py explore basic_sequence_bc generate --run <run_id> --episode 0 --temperature 1.2
```

`temperature` 越低，`softmax` 前的 logits 被放大、機率分布越尖銳，模型幾乎每次都選最可能的下一個動作 token（軌跡更平滑保守，但遇到分岔路口容易卡住不動）；`temperature` 越高，分布越平坦，rollout 越容易跳出去、走出不合理的軌跡（例如推桿瞬間跳到很遠的位置）。

## 6. 反思問題

1. bigram 跟 transformer 的 `val_loss` 曲線，哪個能降得更低？如果把 `transformer.yaml` 的 `block_size` 從 32 改成 8 重跑，`val_loss` 和 rollout 的 L2 誤差會變好還是變差？為什麼上下文長度會影響「預測下一個動作」這件事？
2. `attention` 印出來的矩陣裡，越靠近對角線（也就是越接近「剛做過的動作」）的權重是不是通常比較大？這跟推 T 形物塊這個任務的「動作局部連續性」（下一步的推桿位置通常離上一步不遠）有什麼關係？
3. 把 causal mask 拿掉（在 `src/models.py` 的 `CausalSelfAttention.forward` 裡把 `att.masked_fill(...)` 那行註解掉）重新訓練，`train_loss` 會變得異常低——為什麼？這種「訓練時看得到答案、部署時看不到」的落差，在 BC 裡對應到什麼問題？
4. 把 `bins_per_dim` 從 16 改成 4（字彙變小）或 64（字彙變大）重跑，觀察 rollout 的 L2 誤差怎麼變。bin 太少會發生什麼問題（提示：同一個 bin 裡的動作會被視為完全相同）？bin 太多呢（提示：每個 bin 分到的訓練資料變少）？這正是 RT-2 論文選擇「每個維度 256 個 bin」時要權衡的真實設計問題。

## 附錄：這跟語言模型是同一套機制

上面整段課沒有用到任何語言模型的比喻——但如果把 `src/data.py` 換成一個字元 tokenizer（每個字元對應一個 token，而不是每個離散化的座標對應一個 token），`src/models.py`/`src/train.py` 可以完全不改，直接拿去訓練一個字元級語言模型（這就是 nanoGPT 這類教學實作的做法）。這也是 DESIGN.md 想強調的重點：語言模型和序列化 BC policy 用的是同一套「離散 token + 因果注意力 + autoregressive 生成」機制，差別只在字彙表的意義——一個是字元，一個是機器人動作。

## 附錄：CLI 參數速查

`src/train.py`：
| 參數 | 說明 | 預設（來自 `configs/default.yaml`） |
|---|---|---|
| `--config` / `-c` | 要用哪份 yaml | - |
| `--model` | `bigram` 或 `transformer` | `bigram` |
| `--bins-per-dim` | action tokenizer 每一軸切幾格（字彙表 = bins²） | `16` |
| `--block-size` | 上下文視窗長度（動作步數） | `16` |
| `--n-embd` / `--n-head` / `--n-layer` / `--dropout` | transformer 專屬超參數 | `64` / `4` / `2` / `0.0` |
| `--epochs` | 訓練週期數 | `5` |
| `--steps-per-epoch` | 每個 epoch 跑幾次梯度更新（示範沒有固定「一輪」的概念，所以用步數定義 epoch） | `200` |
| `--lr` | AdamW 學習率 | `0.01` |
| `--batch-size` | 每個梯度步取幾個隨機視窗 | `64` |
| `--seed` | 影響初始化與取樣 | `0` |
| `--val-episode` | 每個 epoch 產生 rollout 樣本時用哪個 held-out episode | `0` |
| `--prompt-len` | 餵給模型當上下文的真實動作步數 | `8` |
| `--gen-length` | rollout 要預測幾步 | `50` |
| `--temperature` | rollout 取樣溫度 | `0.8` |
| `--run-id` | 不指定則自動用時間戳記命名 | - |

`src/explore.py` 子指令：`list` / `metrics` / `generate` / `attention`。`generate` 和 `attention` 都吃 `--run <run_id>` 與 `--episode <idx>`（held-out episode 索引），`--epoch` 預設用最新一個。
