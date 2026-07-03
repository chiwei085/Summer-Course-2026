# basic_regression_classification

**對應主線**：Part 1（函數）+ Part 2（最佳化）   
**資料集**：[Palmer Penguins](https://huggingface.co/datasets/SIH/palmer-penguins)（344 隻企鵝，量測嘴喙長度/深度、鰭長、體重、島嶼、性別）

這份講義是線性閱讀的，但每個指令跑完都會把結果寫進 `artifacts/<run_id>/`，之後可以用 `explore.py` 用任意順序回去問問題。

## 0. 環境

在 `week2/` 底下（共用的虛擬環境，不需要先 `cd` 進這個資料夾）：

```bash
uv run python cli.py train basic_regression_classification --help
```

如果看到 usage 說明，代表環境沒問題。下面所有指令都用這個 `uv run python cli.py train/explore basic_regression_classification ...` 的形式，從 `week2/` 直接執行；不想每次都打 lab 名稱的話，也可以自己 `cd basic_regression_classification/` 之後改用 `uv run --project .. python -m src.train ...`（拿掉 `python cli.py train basic_regression_classification`、換成 `python -m src.train`），兩者完全等價。不確定要跑哪個 lab、哪個動作時，直接執行 `uv run python cli.py` 會進入互動選單。

這個 lab 的訓練參數（`task`/`model`/`epochs`…）都寫在 `configs/*.yaml`：每個指令都對應一份 yaml，跑訓練時用 `--config` 指過去就好，不用每次把一長串旗標打在指令列上。

## 1. 先跑一個最簡單的模型：線性分類器

我們要解的第一個問題：**只用兩個量測值（嘴喙長度、鰭長）能不能分出企鵝是哪個 species？**

```bash
uv run python cli.py train basic_regression_classification --config configs/linear_classify.yaml
```

打開 `basic_regression_classification/configs/linear_classify.yaml` 看看裡面寫了什麼——只有 `epochs: 30`，因為其他值（`task: classify`、`model: linear`…）都跟 `configs/default.yaml` 的預設一樣，不用重複寫。

跑完後看終端機印出的 run id（長得像 `classify_linear_20260703_201908`），記下來，後面都會用到。

打開 `basic_regression_classification/artifacts/<run_id>/config.yaml`，讀一下裡面的超參數、seed——這是這次訓練的「身分證」，之後如果結果對不上，先看這裡。

## 2. 查詢：這個模型學到了什麼？

不要只看 loss 曲線，`explore.py` 讓你問更具體的問題：

```bash
# 訓練過程的整體樣子
uv run python cli.py explore basic_regression_classification metrics --run <run_id>

# 隨便挑一筆驗證資料，看模型怎麼判斷
uv run python cli.py explore basic_regression_classification predict --run <run_id> --index 0

# 哪些企鵝被分錯了？模型多有把握？
uv run python cli.py explore basic_regression_classification misclassified --run <run_id>

# 決策邊界長什麼樣？
uv run python cli.py explore basic_regression_classification boundary --run <run_id>
```

**問自己**：`misclassified` 印出來的企鵝，是哪個 species 最常被搞混？看一眼 `boundary` 的輸出（各 class 的網格佔比），猜猜看為什麼。

## 3. 換成 MLP：非線性能多做到什麼？

```bash
uv run python cli.py train basic_regression_classification --config configs/mlp_classify.yaml
```

打開 `configs/mlp_classify.yaml`：`hidden_dims: [32, 16]` 是 `nn.Linear` 之間的隱藏層大小。`model: linear` 其實就是 `hidden_dims` 被忽略、直接首尾相連——線性模型和 MLP 是同一個 `MLP` class（見 `src/models.py`），只差在中間有沒有插層。

跑完後比較兩個 run：

```bash
uv run python cli.py explore basic_regression_classification compare --run <mlp_run_id> --epochs 1,30
```

## 4. 用瀏覽器看即時報表

```bash
uv run python cli.py explore basic_regression_classification serve --run <mlp_run_id>
```

打開 `http://localhost:8000`。畫面上有：
- loss / accuracy / grad_norm 三條曲線
- confusion matrix
- **決策邊界圖**：背景色塊是模型在整個特徵空間的預測，散點是驗證資料（圓點=預測對、叉叉=預測錯，顏色代表真實 species）

**重點觀察**：把 linear run 和 mlp run 的決策邊界圖並排看——線性模型的邊界永遠是直線（或超平面），MLP 的邊界會彎曲。這就是 Part 1「非線性 activation 讓模型能表示什麼」的具體樣子。

如果訓練還在跑（本 lab 應該不用這麼久），這個頁面會每 3 秒自動更新，不用重新整理。

## 5. 换成迴歸：從分類到迴歸

同一批企鵝資料，這次要預測連續值——體重（`body_mass_g`）：

```bash
uv run python cli.py train basic_regression_classification --config configs/linear_regress.yaml
uv run python cli.py train basic_regression_classification --config configs/mlp_regress.yaml
```

查詢方式類似，但換成迴歸專屬的指令：

```bash
uv run python cli.py explore basic_regression_classification worst-residuals --run <run_id>
uv run python cli.py explore basic_regression_classification predict --run <run_id> --index 0
```

用 `serve` 打開報表，這次看到的是殘差直方圖，而不是決策邊界——迴歸沒有「決策邊界」這種東西，取而代之的是「預測值 - 真實值」的分布，理想狀況下應該集中在 0 附近、左右對稱。

## 6. 反思問題（對應 Part 1 + Part 2 理論）

跑完以上所有 run 之後，用 `explore.py` 的資料回答這些問題（沒有標準答案，重點是能拿實驗結果佐證）：

1. `grad_norm` 曲線在訓練初期通常比較大、比較不穩定，後期會變小變平——為什麼？跟 loss landscape 的形狀有什麼關係？
2. 把 `--batch-size 0`（全批次梯度下降）跟預設的 mini-batch（`--batch-size 32`）跑同一個 task/model，比較兩者的 `grad_norm` 曲線和 loss 曲線的「毛躁程度」——這就是 SGD 的雜訊從哪裡來的。
3. Linear 模型在這兩個特徵上的決策邊界一定是直線；MLP 為什麼可以彎曲？如果把 `--hidden-dims` 拿掉隱藏層改成只有 1 層很寬的（例如 `--hidden-dims 128`），邊界會變得更彎還是更直？
4. 迴歸任務的 `worst-residuals` 通常長什麼樣的企鵝（哪個 species/哪個特徵區間）？這跟分類任務裡最常被搞混的 species 是同一群嗎？為什麼？

## 附錄：CLI 參數速查

以下表格是 `src/train.py`／`src/explore.py` 本身吃的參數；不管是透過 `week2/` 底下的 `uv run python cli.py train/explore basic_regression_classification ...`，還是直接在這個資料夾裡用 `uv run --project .. python -m src.train/explore ...`，這些參數都原封不動適用。

`src/train.py`:
| 參數 | 說明 | 預設（來自 `configs/default.yaml`） |
|---|---|---|
| `--config` / `-c` | 要用哪份 yaml（見上面每個步驟用到的 `configs/*.yaml`） | - |
| `--task` | `classify` 或 `regress` | `classify` |
| `--model` | `linear` 或 `mlp` | `linear` |
| `--hidden-dims` | 逗號分隔的隱藏層大小，`--model mlp` 才有作用 | `16` |
| `--epochs` | 訓練週期數 | `50` |
| `--lr` | SGD 學習率 | `0.05` |
| `--batch-size` | 0 表示全批次梯度下降 | `32` |
| `--seed` | 影響資料切分、初始化、洗牌順序 | `0` |
| `--run-id` | 不指定則自動用時間戳記命名 | - |

這些 CLI 旗標不是只能單獨用——它們可以疊在 `--config` 之上，臨時覆蓋 yaml 裡的某個值，不用為了改一個參數就新開一份 yaml。例如想拿 `mlp_classify.yaml` 的設定但多跑幾個 epoch：

```bash
uv run python cli.py train basic_regression_classification --config configs/mlp_classify.yaml --epochs 100
```

`src/explore.py` 子指令：`list` / `metrics` / `predict` / `misclassified`（分類）/ `worst-residuals`（迴歸）/ `boundary`（分類）/ `compare` / `serve`。每個都吃 `--run <run_id>`，多數支援 `--epoch`（預設最新一個 epoch）。
