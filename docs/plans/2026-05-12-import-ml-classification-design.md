# 导入智能分类 ML 设计

> 状态：设计文档（已确认）
> 来源：2026-05-12 头脑风暴，用户确认所有设计决策
> 范围：导入时用机器学习从已标注记录学习，自动推断新导入记录的收付类型和类型明细

> 执行裁剪（2026-05-14）：v1.0 / MVP 不执行完整 ML 分类。当前只实现保守记忆预填：同来源、同商户、同商品且历史确认分类完全一致时，预填 `收付类型` 和 `类型明细`；冲突或无历史时留空。逻辑回归、实时训练、置信度阈值和 LLM 链路保留为后续实验方案，不作为 MVP 验收条件。

## 1. 目标

在支付宝/微信账单导入流程中，利用用户历史已标注数据训练轻量分类模型，自动预填新导入记录的 `收付类型` 和 `类型明细`，减少手动分类操作。

## 2. 设计决策汇总

| 决策项 | 选择 |
|--------|------|
| 算法 | 多分类逻辑回归 + 特征哈希 |
| 预测目标 | 收付类型 + 类型明细（两级分层预测） |
| 输入特征 | 交易对方、商品说明、交易类型、金额（全部可用字段） |
| 训练策略 | 每次导入时拉取当前最新已标注数据，实时批量 SGD 训练 |
| 推理呈现 | 导入预览阶段自动填入，置信度 < 0.6 时留空，用户可修改 |
| 冷启动 | 已标注数据 < 30 条时不预测 |
| 模型持久化 | 不做缓存，每次导入实时训练 |
| 平台 | 纯 Swift + Accelerate 框架，零外部依赖 |

## 3. 整体架构

```
支付宝/微信 CSV → 解析 → 候选记录列表
                            ↓
              已标注记录（从数据库拉取最新）
                            ↓
              实时训练 → Level 1 模型（收付类型）
                       → Level 2 模型（类型明细，按收付类型分组）
                            ↓
              逐条推理 → 置信度 >= 0.6 预填
                       → 置信度 < 0.6 留空
                            ↓
              导入预览页面（预填字段有视觉标记）
                            ↓
              用户确认/修改 → 记录入库
```

两级分层预测保证 `类型明细` 永远归属正确的 `收付类型`，符合 Spec 约束。

## 4. 特征工程

### 4.1 文本特征（交易对方、商品说明、交易类型）

三个文本字段分别提取字符级 n-gram（2-gram、3-gram、4-gram），通过特征哈希映射到固定维度向量：

```text
"京东商城" → 补边界: "<京东商城>" 
→ 2-gram: "<京", "京东", "东商", "商城", "城>"
→ 3-gram: "<京东", "京东商", "东商城", "商城>"
→ 4-gram: "<京东商", "京东商城", "东商城>"
```

每个 n-gram 哈希到固定维度索引：

```swift
func hashFeature(_ ngram: String, dim: Int) -> Int {
    abs(ngram.hashValue) % dim
}
```

不处理哈希冲突（特征哈希标准做法）。

### 4.2 数值特征（金额）

- 金额取绝对值后 log 分桶：`0~1, 1~10, 10~50, 50~200, 200~1000, 1000~5000, 5000+`（7 桶）
- 收/支/中性方向标记（3 个二值特征）
- 桶编码同样做特征哈希，写入同一向量

### 4.3 特征维度

| 模型 | 维度 | 典型非零特征数 |
|------|------|---------------|
| Level 1（收付类型） | 4096 | 20-80 |
| Level 2（类型明细） | 2048 + 11（收付类型 one-hot） | 30-100 |

## 5. 算法

### 5.1 模型：多分类逻辑回归（Softmax 回归）

```
z = W · x + b          (W: [k × d], x: 稀疏特征向量, b: [k])
p = softmax(z)          p[i] = exp(z[i]) / Σexp(z[j])
预测类别 = argmax(p)
置信度 = max(p)
```

推理复杂度：O(nonzero_features × num_classes)，约 80 × 11 = 880 次乘法，微秒级。

### 5.2 批量 SGD 训练

每次导入时，用当前所有已标注记录做全量批量 SGD：

```
for epoch in 1...epochs:
    for (x, y_true) in labeledRecords:
        p = softmax(W · x + b)
        for each class i: grad[i] = p[i] - (i == y_true ? 1 : 0)
        for each nonzero feature j in x:
            W[i][j] -= lr × grad[i] × x[j]
        b[i] -= lr × grad[i]
        W[i] *= (1 - lr × decay)    // L2 正则
```

学习率：`η = η0 / (1 + decay × sampleCount)`，初始 0.5，衰减 0.001。

### 5.3 训练性能

假设 2000 条已标注记录，3 epoch：
- 2000 × 50 × 11 × 3 = 3,300,000 次乘法
- 用 Accelerate BLAS 预计 20-50ms

若数据 > 5000 条，随机采样 5000 条训练以保证速度。

## 6. Swift 模块设计

```
Sources/
├── ClassificationPredictor/
│   ├── ClassificationPredictor.swift    # 主入口，协调训练和推理
│   ├── FeatureExtractor.swift           # n-gram 提取 + 特征哈希
│   ├── LogisticRegression.swift         # 多分类逻辑回归（训练+推理）
│   └── TrainingDataProvider.swift       # 从数据库拉取已标注记录
```

### ClassificationPredictor

```swift
struct ClassificationPredictor {
    var level1Model: LogisticRegression
    var level2Models: [String: LogisticRegression]  // key=收付类型

    mutating func train(records: [LabeledRecord], epochs: Int = 3)
    func predict(record: ImportCandidate) -> PredictionResult
}

struct PredictionResult {
    let paymentType: (label: String, confidence: Double)?
    let typeDetail: (label: String, confidence: Double)?
}
```

### FeatureExtractor

```swift
struct FeatureExtractor {
    let dim: Int

    func extract(counterparty: String, product: String,
                 txType: String, amount: Double,
                 paymentType: String? = nil) -> [Int: Float]
}
```

### LogisticRegression

```swift
struct LogisticRegression {
    var weights: [[Float]]     // [numClasses × featureDim]
    var bias: [Float]
    let featureDim: Int
    let classLabels: [String]

    mutating func fit(samples: [(features: [Int: Float], label: Int)],
                      numClasses: Int, epochs: Int, learningRate: Float)
    func predict(features: [Int: Float]) -> (classIndex: Int, confidence: Float)
}
```

## 7. 导入流程集成

```
1. 用户点击导入，选择支付宝/微信 CSV 文件
2. 系统解析 CSV，生成候选记录列表
3. [新] TrainingDataProvider 从数据库拉取所有已标注记录
4. [新] 已标注数据 >= 30 条时，实时训练模型
5. [新] 逐条推理，高置信度（>= 0.6）自动填入收付类型和类型明细
6. 展示导入预览页面，预填字段有视觉标记（如浅蓝底色）
7. 用户逐条或批量修改，补充收付手段、备注、账月
8. 用户确认导入
9. 记录入库，下次导入时自动成为训练数据
```

## 8. 边缘情况

| 场景 | 处理 |
|------|------|
| 训练数据 < 30 条 | 跳过预测，全部留空 |
| 某收付类型下无类型明细数据 | Level 2 对该类型不预测 |
| 用户新增收付类型 | 自动扩展 Level 1 输出维度 |
| 用户新增类型明细 | 自动扩展对应 Level 2 模型输出维度 |
| 单条置信度 < 0.6 | 留空，不做猜测 |
| 训练数据 > 5000 条 | 随机采样 5000 条训练 |
| CSV 字段缺失/乱码 | 对应特征置零，仍可基于其他特征预测 |
| 新分类无历史数据 | 权重随机初始化，随 SGD 逐步学习 |

## 9. 不做

- 不做模型缓存/持久化（每次实时训练）
- 不做规则兜底（纯 ML）
- 不做预训练基础模型
- 不做收付手段、备注、账月的 ML 预测
- 不接入外部 AI API
- 不使用 Core ML 导出管线
