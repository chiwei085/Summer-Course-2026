# basic_vision_representation

**對應主線**：Part 3（視覺表示：把圖像變成能餵給 policy 的向量）
**資料集**：[lerobot/pusht_image](https://huggingface.co/datasets/lerobot/pusht_image)（Hugging Face LeRobot 專案，跟 Part 2 用的 `pusht_keypoints` 是同一組 206 段推 T 形物塊示範，多了一張 96x96 RGB 畫面觀測）

Part 2 把 state 和畫面都拿掉，只留一串 action 序列，練「給定歷史動作，預測下一個動作」。這一段把畫面加回來、把歷史動作拿掉：給定「這一格畫面長什麼樣子」，預測示範者這一步做了什麼動作。跟 Part 1 一樣是單步、無記憶的迴歸任務——輸入從一個現成的特徵向量，換成一張沒人先幫你算好特徵的原始圖像。感知本身（怎麼把圖像變成向量）才是這段的重點；語言指令、動作序列、跟感知的融合留到 Part 4 收尾成完整 VLA。

## 0. 環境

在 `week2/` 底下：

```bash
uv run python cli.py train basic_vision_representation --help
```

跟前兩段一樣，`--config` 指向 `configs/*.yaml` 覆蓋預設值，CLI 旗標可以再疊上去覆蓋 yaml。第一次執行會從 Hugging Face Hub 下載 `lerobot/pusht_image`（25650 張 96x96 圖片，全部載入記憶體一次，之後每個 batch 直接從記憶體切）。

## 1. 資料：同一個任務，多了一雙眼睛

打開 `src/data.py`：`TaskData` 現在裝的是 `(N, 3, 96, 96)` 的圖像張量和 `(N, 2)` 的動作張量，而不是 Part 2 的 token 序列。切 train/val 一樣按 **episode** 切（前 10% 的 episode 當 held-out），不是按照每一張圖片隨機切——同一段示範裡相鄰畫面幾乎長得一樣，如果按照圖片隨機切，val 裡會混進跟 train 幾乎一樣的畫面，讓分數看起來比實際上準。

這一段沒有 `block_size`、沒有歷史動作：一張圖進去，一個 `(x, y)` 動作出來，用的是 Part 1 的迴歸 loss（MSE），不是 Part 2 的 next-token 分類 loss。

## 2. CNN：卷積把圖像壓成向量

```bash
uv run python cli.py train basic_vision_representation --config configs/cnn.yaml
```

打開 `src/models.py` 的 `SmallCNN`：4 層 `stride=2` 的卷積，每層把空間解析度砍半（96 → 48 → 24 → 12 → 6），最後一個 `AdaptiveAvgPool2d(1)` 把 6x6xC 的 feature map 壓成一個 C 維向量，再用一層線性層預測動作——這個「壓成向量」的動作，正是這段標題「視覺表示」的字面意思。卷積層的權重在整張圖上共享、每個輸出只看得到輸入的一小塊區域（receptive field），這是 CNN 對圖像的先天假設：局部特徵到處都可能出現，不用每個位置各學一份參數。

跑完後看 `artifacts/<run_id>/report/index.html`：「每個 epoch 的預測」卡片，每張縮圖上綠色點是示範者實際做的動作，橘色點是模型的預測，訓練越久兩點應該越接近。

## 3. 加上自注意力：ViT

```bash
uv run python cli.py train basic_vision_representation --config configs/vit.yaml
```

打開 `configs/vit.yaml`：`patch_size: 12` 把 96x96 的圖切成 8x8=64 個不重疊的 12x12 小塊（patch），每個 patch 攤平後用一個線性層投影成一個 token——這一步在 `src/models.py` 的 `TinyViT.patch_embed` 裡其實就是一個 `kernel_size == stride` 的卷積，等於「每個 patch 各自過一次同一個線性層」。64 個 patch token 前面再加一個可學習的 `cls_token`，一起丟進 `SelfAttention`。

**核心機制，也是這段跟 Part 2 唯一的差別**：打開 `SelfAttention.forward`，跟 Part 2 的 `CausalSelfAttention` 幾乎一模一樣，只差一行——沒有 `causal_mask`。Part 2 的動作 token 有時間先後順序，位置 `t` 不能偷看位置 `t+1`（那是「未來」，部署時不存在）；這裡的 64 個 patch 只是把一張圖攤平的空間位置，patch 7 看得到 patch 42，跟 patch 42 看不看得到 patch 7 完全對稱，因為圖像裡沒有「先後」這個概念可言。**同一個 attention 機制，需不需要遮罩取決於 token 之間有沒有時間順序，不是取決於「這是不是語言模型」。**

跑完後一樣打開 `report/index.html`，比較跟 CNN 的 L2 誤差：ViT 通常需要比 CNN 更久才追上（self-attention 沒有 CNN 那種「附近的像素比較相關」的先天假設，得從資料裡自己學出來），這是 ViT 論文裡「ViT 在小資料集上通常不如 CNN」這個已知現象的縮小版重現。

## 4. 查詢：encoder 在看圖的哪裡？

```bash
# 訓練過程摘要
uv run python cli.py explore basic_vision_representation metrics --run <run_id>

# 用訓練好的模型對某張 held-out 圖片做預測
uv run python cli.py explore basic_vision_representation predict --run <run_id> --index 0

# 印出 ViT 的 CLS token 對每個 patch 的注意力（只對 vit run 有效）
uv run python cli.py explore basic_vision_representation attention --run <run_id> --index 0
```

`attention` 印出一個 8x8 矩陣：每一格是 `cls_token`（負責做最終預測的那個向量）對那個 patch 的注意力權重。`report/index.html` 裡「Encoder 在看哪裡？」卡片是同一份資料疊在原圖上的熱力圖版本，訓練完的最後一個 checkpoint 對固定一張 held-out 圖算出來的。

CNN 沒有注意力權重可以印——它沒有這個機制。`train.py` 改用**輸入梯度顯著圖（saliency map）**代替：把預測值對每一個輸入像素微分，微分值越大代表微調那個像素對預測的影響越大，等於是 CNN 隱含的「關注區域」，不需要模型架構裡有 attention 才能問「模型在看哪裡」這個問題。

## 5. 反思問題

1. `SmallCNN.__init__`（`src/models.py`）的 `channels` 預設是 `(16, 32, 64, 128)` 這 4 層，沒有走 `--config`，改的話要直接改這行預設值。試著改成只有兩層 `(16, 32)` 重新訓練：val L2 誤差變好還是變差？下採樣次數變少，最後一層 feature map 的空間解析度會變成多少（96 經過幾次 stride=2）？這跟「感受野夠不夠大、看不看得到整個 T 形物塊」有什麼關係？
2. 把 `vit.yaml` 的 `patch_size` 從 12 改成 24（16 個較大的 patch）或 6（256 個較小的 patch），重新訓練。patch 越大，注意力矩陣的解析度越低是為什麼？回想 Part 2 的 `bins_per_dim`：patch 數量跟 token 數量，兩者都是「切得越細，看得越精細，但每個格子分到的訓練訊號越少」這同一種權衡的具體實例嗎？
3. `report/index.html` 裡 ViT 的 attention 熱力圖，高權重的 patch 通常落在哪裡——推桿（agent）附近、T 形物塊附近，還是背景？如果落在背景，這代表模型學到了什麼樣（可能是錯誤）的捷徑？
4. 如果把 `SelfAttention.forward` 裡的 `torch.softmax(att, dim=-1)` 前面硬加一行 `causal_mask`（只允許 patch `i` 看 patch `<= i`），用跟 Part 2 一樣的下三角遮罩，重新訓練後 loss 會發生什麼變化？這個實驗想證明的是：mask 要不要加，取決於 token 之間有沒有「誰在誰的未來」這種關係，而不是「這是不是 transformer」。

## 附錄：這跟 Part 2 是同一顆 attention block

`SelfAttention`（這段）跟 `CausalSelfAttention`（Part 2）的 QKV 投影、多頭切分、`softmax(QK^T/√d)V` 完全相同，唯一差異是有沒有套用 `causal_mask`。語言模型的 causal attention、序列化 BC policy 的 causal attention、這裡圖像 patch 的 bidirectional attention，是同一套「QKV self-attention」機制的三種應用——差別只在於 token 之間有沒有時間順序，不是每次都要重新發明一個新機制。

## 附錄：CLI 參數速查

`src/train.py`：
| 參數 | 說明 | 預設（來自 `configs/default.yaml`） |
|---|---|---|
| `--config` / `-c` | 要用哪份 yaml | - |
| `--model` | `cnn` 或 `vit` | `cnn` |
| `--patch-size` | ViT 每個 patch 的邊長（像素） | `12` |
| `--n-embd` / `--n-head` / `--n-layer` / `--dropout` | ViT 專屬超參數 | `128` / `4` / `4` / `0.0` |
| `--epochs` | 訓練週期數 | `5` |
| `--steps-per-epoch` | 每個 epoch 跑幾次梯度更新 | `200` |
| `--lr` | AdamW 學習率 | `0.001` |
| `--batch-size` | 每個梯度步取幾張圖 | `64` |
| `--seed` | 影響初始化與取樣 | `0` |
| `--n-samples` | 每個 epoch 報告裡顯示幾張 held-out 預測縮圖 | `6` |
| `--run-id` | 不指定則自動用時間戳記命名 | - |

`src/explore.py` 子指令：`list` / `metrics` / `predict` / `attention`。`predict` 和 `attention` 都吃 `--run <run_id>` 與 `--index <idx>`（held-out 圖片索引），`--epoch` 預設用最新一個；`attention` 只對 `model=vit` 的 run 有效。
