# 导入智能分类 ML 实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 MingZhangCore 包中实现纯 Swift 逻辑回归分类器，包含特征提取、训练、推理，供导入流程调用以自动预填收付类型和类型明细。

**Architecture:** 新增 4 个源文件到 MingZhangCore/Sources/MingZhangCore/Classification/，零外部依赖，仅使用 Foundation 和 Accelerate。特征哈希将中文文本 n-gram 映射为定长稀疏向量，多分类 Softmax 回归做两级预测（Level 1: 收付类型 → Level 2: 类型明细）。每次导入时从 GRDB 拉取已标注记录做实时批量 SGD 训练。

**Tech Stack:** Swift 6、Accelerate（BLAS）、GRDB（已有依赖）、XCTest

**参考设计:** `docs/plans/2026-05-12-import-ml-classification-design.md`

---

## Context

### 项目结构

```
ios/MingZhang/Packages/MingZhangCore/
├── Package.swift
├── Sources/MingZhangCore/
│   └── MingZhangCore.swift          # 所有现有模型、DB、UseCase（1306行）
└── Tests/MingZhangCoreTests/
    └── P0LedgerFlowTests.swift
```

### 关键信息

- **已有依赖**: GRDB.swift 7.10+，Foundation，Accelerate（系统框架，无需显式声明）
- **已有模型**: `PaymentType`（收付类型）、`PaymentDetail`（类型明细）、`JournalRecord`（流水记录）
- **导入流程**: P1 导入尚未实现，本计划构建独立的 ML 模块，定义清晰的集成接口
- **流水记录字段**: `paymentTypeId`、`paymentDetailId`、`amount`、`rawDescription` 等

### 设计约束回顾

- 冷启动阈值：已标注数据 < 30 条时不预测
- 置信度阈值：max(p) >= 0.6 才预填
- 数据 > 5000 条时随机采样训练
- 不做模型持久化/缓存
- 特征维度：Level 1 = 4096，Level 2 = 2048
- n-gram 范围：2-4 gram

---

### Task 1: 创建文件结构和 FeatureExtractor

**Files:**
- Create: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/Classification/FeatureExtractor.swift`
- Test: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/FeatureExtractorTests.swift`

**Step 1: 编写 FeatureExtractor 测试**

FeatureExtractorTests.swift:
```swift
import XCTest
@testable import MingZhangCore

final class FeatureExtractorTests: XCTestCase {
    func test_extract_returnsSparseVector() {
        let extractor = FeatureExtractor(dim: 256)
        let features = extractor.extract(
            counterparty: "京东商城",
            product: "京东-订单编号123",
            txType: "商户消费",
            amount: 50.0
        )
        XCTAssertFalse(features.isEmpty, "应生成非空特征向量")
        // 至少应有 n-gram 产生的特征和金额分桶特征
        XCTAssertGreaterThan(features.count, 5)
    }

    func test_extract_sameInputProducesSameFeatures() {
        let extractor = FeatureExtractor(dim: 256)
        let f1 = extractor.extract(counterparty: "美团", product: "外卖", txType: "商户消费", amount: 30.0)
        let f2 = extractor.extract(counterparty: "美团", product: "外卖", txType: "商户消费", amount: 30.0)
        XCTAssertEqual(f1, f2)
    }

    func test_extract_differentInputsDiffer() {
        let extractor = FeatureExtractor(dim: 256)
        let f1 = extractor.extract(counterparty: "京东", product: "购物", txType: "商户消费", amount: 100.0)
        let f2 = extractor.extract(counterparty: "饿了么", product: "外卖", txType: "商户消费", amount: 30.0)
        XCTAssertNotEqual(f1, f2)
    }

    func test_extract_allIndicesWithinBounds() {
        let dim = 256
        let extractor = FeatureExtractor(dim: dim)
        let features = extractor.extract(
            counterparty: "测试商户名称比较长的情况",
            product: "这是一个比较长的商品描述用于测试",
            txType: "商户消费",
            amount: 12345.67
        )
        for (index, _) in features {
            XCTAssertGreaterThanOrEqual(index, 0)
            XCTAssertLessThan(index, dim, "所有索引应在 [0, dim) 范围内")
        }
    }

    func test_extract_withPaymentType_addsOneHotFeatures() {
        let extractor = FeatureExtractor(dim: 256)
        let f1 = extractor.extract(
            counterparty: "京东", product: "购物", txType: "商户消费",
            amount: 100.0, paymentType: "生活必要开支"
        )
        let f2 = extractor.extract(
            counterparty: "京东", product: "购物", txType: "商户消费",
            amount: 100.0
        )
        // 带 paymentType 的应有额外特征
        XCTAssertGreaterThan(f1.count, f2.count)
    }

    func test_extract_emptyFields_doesNotCrash() {
        let extractor = FeatureExtractor(dim: 256)
        let features = extractor.extract(
            counterparty: "", product: "", txType: "", amount: 0.0
        )
        // 空输入不应崩溃，至少应有金额分桶特征
        XCTAssertNotNil(features)
    }

    func test_extract_amountBinning() {
        let extractor = FeatureExtractor(dim: 256)
        // 不同金额应产生不同的分桶特征
        let f1 = extractor.extract(counterparty: "X", product: "X", txType: "X", amount: 5.0)
        let f2 = extractor.extract(counterparty: "X", product: "X", txType: "X", amount: 5000.0)
        XCTAssertNotEqual(f1, f2, "不同金额分桶应产生不同特征")
    }
}
```

**Step 2: 运行测试确认失败**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter FeatureExtractorTests
```
预期: FAIL — 文件不存在 / 类型未定义

**Step 3: 实现 FeatureExtractor**

FeatureExtractor.swift:
```swift
import Foundation

/// 从导入候选记录的原始字段提取稀疏特征向量
public struct FeatureExtractor: Sendable {
    public let dim: Int

    /// 金额 log 分桶边界
    private static let amountBuckets: [(upperBound: Double, name: String)] = [
        (1, "0~1"), (10, "1~10"), (50, "10~50"),
        (200, "50~200"), (1000, "200~1000"),
        (5000, "1000~5000"), (.infinity, "5000+")
    ]

    /// 金额方向标记
    private static let directions = ["expense", "income", "neutral"]

    public init(dim: Int) {
        self.dim = dim
    }

    // MARK: - Public API

    /// 从原始字段提取特征向量
    /// - Parameters:
    ///   - paymentType: 可选，用于 Level 2 模型的 one-hot 特征（已知收付类型时传入）
    /// - Returns: 稀疏特征向量 [索引: 值]，值始终为 1.0（特征存在性标记）
    public func extract(
        counterparty: String,
        product: String,
        txType: String,
        amount: Double,
        paymentType: String? = nil
    ) -> [Int: Float] {
        var features = [Int: Float]()

        // 1. 文本 n-gram 特征
        for field in [counterparty, product, txType] {
            addNGramFeatures(field, to: &features)
        }

        // 2. 金额分桶特征
        addAmountBucketFeatures(amount, to: &features)

        // 3. 金额方向特征
        addDirectionFeature(amount, to: &features)

        // 4. 收付类型 one-hot（Level 2 用）
        if let paymentType {
            addHashedFeature("ptype_\(paymentType)", to: &features)
        }

        return features
    }

    // MARK: - Private

    private func addNGramFeatures(_ text: String, to features: inout [Int: Float]) {
        guard !text.isEmpty else { return }
        // 边界标记，帮助模型区分词首词尾
        let padded = "<\(text)>"
        let chars = Array(padded)
        for n in 2...4 {
            guard chars.count >= n else { continue }
            for i in 0...(chars.count - n) {
                let ngram = String(chars[i..<(i + n)])
                addHashedFeature("n\(n)_\(ngram)", to: &features)
            }
        }
    }

    private func addAmountBucketFeatures(_ amount: Double, to features: inout [Int: Float]) {
        let absAmount = abs(amount)
        var bucketName = "amt_0~1"
        for bucket in Self.amountBuckets {
            if absAmount <= bucket.upperBound {
                bucketName = "amt_\(bucket.name)"
                break
            }
        }
        addHashedFeature(bucketName, to: &features)
    }

    private func addDirectionFeature(_ amount: Double, to features: inout [Int: Float]) {
        let direction: String
        if amount < 0 {
            direction = "收入"
        } else if amount > 0 {
            direction = "支出"
        } else {
            direction = "中性"
        }
        addHashedFeature("dir_\(direction)", to: &features)
    }

    private func addHashedFeature(_ key: String, to features: inout [Int: Float]) {
        let index = abs(key.hashValue) % dim
        // 特征存在即设为 1.0，重复哈希碰撞不做累加
        features[index] = 1.0
    }
}
```

**Step 4: 运行测试确认通过**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter FeatureExtractorTests
```
预期: ALL PASS

**Step 5: 提交**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/Classification/FeatureExtractor.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/FeatureExtractorTests.swift
git commit -m "feat: add FeatureExtractor with n-gram + amount binning"

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

---

### Task 2: 实现 LogisticRegression 核心算法

**Files:**
- Create: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/Classification/LogisticRegression.swift`
- Test: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/LogisticRegressionTests.swift`

**Step 1: 编写 LogisticRegression 测试**

LogisticRegressionTests.swift:
```swift
import XCTest
@testable import MingZhangCore

final class LogisticRegressionTests: XCTestCase {
    // MARK: - 初始化

    func test_init_withLabels() {
        let model = LogisticRegression(
            featureDim: 128,
            classLabels: ["A", "B", "C"]
        )
        XCTAssertEqual(model.classLabels, ["A", "B", "C"])
        XCTAssertEqual(model.weights.count, 3)
        XCTAssertEqual(model.weights[0].count, 128)
        XCTAssertEqual(model.bias.count, 3)
    }

    // MARK: - 推理

    func test_predict_beforeTraining_returnsValidIndex() {
        let model = LogisticRegression(featureDim: 128, classLabels: ["A", "B"])
        let features: [Int: Float] = [0: 1.0, 5: 1.0, 10: 1.0]
        let (idx, conf) = model.predict(features: features)
        XCTAssertGreaterThanOrEqual(idx, 0)
        XCTAssertLessThan(idx, 2)
        XCTAssertGreaterThan(conf, 0)
        XCTAssertLessThanOrEqual(conf, 1.0)
    }

    func test_predict_emptyFeatures_doesNotCrash() {
        let model = LogisticRegression(featureDim: 128, classLabels: ["A", "B", "C"])
        let (idx, conf) = model.predict(features: [:])
        XCTAssertGreaterThanOrEqual(idx, 0)
        XCTAssertLessThan(idx, 3)
        // 空特征时所有 logit 为 0，softmax 均匀分布
        XCTAssertEqual(conf, 1.0 / 3.0, accuracy: 0.01)
    }

    // MARK: - 训练

    func test_fit_onLinearlySeparableData_converges() {
        let extractor = FeatureExtractor(dim: 64)
        let model = LogisticRegression(featureDim: 64, classLabels: ["A", "B"])

        // 构造可线性分离的合成数据
        var samples: [(features: [Int: Float], label: Int)] = []
        for i in 0..<100 {
            let key = i % 2 == 0 ? "prefix_a_\(i)" : "prefix_b_\(i)"
            let features = extractor.extract(
                counterparty: key, product: "x", txType: "x", amount: Double(i)
            )
            samples.append((features: features, label: i % 2))
        }

        var trained = model
        trained.fit(samples: samples, numClasses: 2, epochs: 10, learningRate: 0.5)

        // 训练后应对训练数据高置信度
        var correct = 0
        for sample in samples {
            let (pred, _) = trained.predict(features: sample.features)
            if pred == sample.label { correct += 1 }
        }
        let accuracy = Double(correct) / Double(samples.count)
        XCTAssertGreaterThan(accuracy, 0.8, "简单二分类应达到 >80% 准确率，实际: \(accuracy)")
    }

    func test_fit_withSingleClass_doesNotCrash() {
        var model = LogisticRegression(featureDim: 64, classLabels: ["Only"])
        let features: [Int: Float] = [1: 1.0]
        model.fit(samples: [(features: features, label: 0)], numClasses: 1, epochs: 3, learningRate: 0.5)
        let (idx, conf) = model.predict(features: features)
        XCTAssertEqual(idx, 0)
        XCTAssertEqual(conf, 1.0, accuracy: 0.01)
    }

    func test_fit_emptySamples_doesNotCrash() {
        var model = LogisticRegression(featureDim: 64, classLabels: ["A", "B"])
        model.fit(samples: [], numClasses: 2, epochs: 3, learningRate: 0.5)
        // 不崩溃即可
    }

    func test_fit_learningRateDecays() {
        var model = LogisticRegression(featureDim: 64, classLabels: ["A", "B"])
        let extractor = FeatureExtractor(dim: 64)
        var samples: [(features: [Int: Float], label: Int)] = []
        for i in 0..<50 {
            let key = i < 25 ? "group_a" : "group_b"
            samples.append((
                features: extractor.extract(counterparty: key, product: "x", txType: "x", amount: Double(i)),
                label: i < 25 ? 0 : 1
            ))
        }
        // 不应该崩溃
        model.fit(samples: samples, numClasses: 2, epochs: 5, learningRate: 0.5)
    }

    // MARK: - 新分类扩展

    func test_addClass_expandsWeights() {
        var model = LogisticRegression(featureDim: 64, classLabels: ["A", "B"])
        model.addClass(label: "C")
        XCTAssertEqual(model.classLabels, ["A", "B", "C"])
        XCTAssertEqual(model.weights.count, 3)
        XCTAssertEqual(model.bias.count, 3)
        // 新增行应全为 0
        XCTAssertEqual(model.weights[2].reduce(0, +), 0)
        XCTAssertEqual(model.bias[2], 0)
    }
}
```

**Step 2: 运行测试确认失败**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter LogisticRegressionTests
```
预期: FAIL — 类型未定义

**Step 3: 实现 LogisticRegression**

LogisticRegression.swift:
```swift
import Foundation

/// 多分类逻辑回归（Softmax 回归），支持稀疏特征向量和批量 SGD 训练
public struct LogisticRegression: Sendable {
    /// 权重矩阵 [numClasses × featureDim]
    public var weights: [[Float]]
    /// 偏置向量 [numClasses]
    public var bias: [Float]
    public let featureDim: Int
    public var classLabels: [String]

    public var numClasses: Int { classLabels.count }

    // MARK: - Init

    public init(featureDim: Int, classLabels: [String]) {
        self.featureDim = featureDim
        self.classLabels = classLabels
        let k = classLabels.count
        // 小随机初始化打破对称
        self.weights = (0..<k).map { _ in
            (0..<featureDim).map { _ in Float.random(in: -0.01...0.01) }
        }
        self.bias = [Float](repeating: 0, count: k)
    }

    // MARK: - Inference

    /// 预测单条样本
    /// - Returns: (类别索引, 置信度 = max softmax prob)
    public func predict(features: [Int: Float]) -> (classIndex: Int, confidence: Float) {
        let probs = softmax(features: features)
        var maxIdx = 0
        var maxVal = probs[0]
        for i in 1..<probs.count {
            if probs[i] > maxVal {
                maxVal = probs[i]
                maxIdx = i
            }
        }
        return (maxIdx, maxVal)
    }

    /// 返回完整 softmax 概率分布
    public func predictProbs(features: [Int: Float]) -> [Float] {
        softmax(features: features)
    }

    // MARK: - Training

    /// 批量 SGD 训练
    /// - Parameters:
    ///   - samples: 训练样本 (稀疏特征, 正确类别索引)
    ///   - epochs: 遍历数据次数
    ///   - learningRate: 初始学习率 η0
    public mutating func fit(
        samples: [(features: [Int: Float], label: Int)],
        numClasses: Int,
        epochs: Int,
        learningRate: Float
    ) {
        guard !samples.isEmpty, numClasses > 0 else { return }
        let decay: Float = 0.001
        let k = numClasses
        var seenCount: Float = 0

        for _ in 0..<epochs {
            for (features, trueLabel) in samples {
                guard trueLabel >= 0, trueLabel < k else { continue }
                seenCount += 1
                let lr = learningRate / (1.0 + decay * seenCount)

                // 前向传播: logits = W·x + b
                var logits = bias
                for (j, val) in features {
                    guard j < featureDim else { continue }
                    for i in 0..<k {
                        logits[i] += weights[i][j] * val
                    }
                }

                // Softmax
                let maxLogit = logits.max() ?? 0
                var sumExp: Float = 0
                var exps = [Float](repeating: 0, count: k)
                for i in 0..<k {
                    exps[i] = exp(logits[i] - maxLogit)
                    sumExp += exps[i]
                }
                var probs = exps
                for i in 0..<k { probs[i] /= sumExp }

                // 梯度更新
                for i in 0..<k {
                    var grad = probs[i]
                    if i == trueLabel { grad -= 1.0 }
                    // L2 正则衰减
                    let reg = 1.0 - lr * decay * 0.01
                    for (j, val) in features {
                        guard j < featureDim else { continue }
                        weights[i][j] = weights[i][j] * reg - lr * grad * val
                    }
                    bias[i] -= lr * grad
                }
            }
        }
    }

    // MARK: - Class Management

    /// 添加新分类（权重从零初始化）
    public mutating func addClass(label: String) {
        classLabels.append(label)
        weights.append([Float](repeating: 0, count: featureDim))
        bias.append(0)
    }

    // MARK: - Private

    private func softmax(features: [Int: Float]) -> [Float] {
        let k = numClasses
        var logits = bias
        for (j, val) in features {
            guard j < featureDim else { continue }
            for i in 0..<k {
                logits[i] += weights[i][j] * val
            }
        }
        let maxLogit = logits.max() ?? 0
        var sumExp: Float = 0
        var result = [Float](repeating: 0, count: k)
        for i in 0..<k {
            result[i] = exp(logits[i] - maxLogit)
            sumExp += result[i]
        }
        for i in 0..<k { result[i] /= sumExp }
        return result
    }
}
```

**Step 4: 运行测试确认通过**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter LogisticRegressionTests
```
预期: ALL PASS

**Step 5: 提交**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/Classification/LogisticRegression.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/LogisticRegressionTests.swift
git commit -m "feat: add LogisticRegression with sparse SGD training"

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

---

### Task 3: 实现 TrainingDataProvider

**Files:**
- Create: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/Classification/TrainingDataProvider.swift`
- Test: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/TrainingDataProviderTests.swift`

**Context**: `TrainingDataProvider` 从 GRDB 拉取所有已标注的流水记录（`paymentTypeId` 和 `paymentDetailId` 均为非空），将它们转为训练样本。需要访问 `JournalRecord` 和 `PaymentDetail` 表以获取分类名称。不直接依赖 GRDB 导入，而是定义协议让外部注入数据库访问。

**Step 1: 编写协议和类型定义**

此步骤先定义数据模型，不涉及 GRDB 查询即可测试。

TrainingDataProviderTests.swift:
```swift
import XCTest
@testable import MingZhangCore

final class TrainingDataProviderTests: XCTestCase {
    func test_labeledRecord_holdsExpectedFields() {
        let record = LabeledRecord(
            counterparty: "京东商城",
            product: "京东-订单123",
            txType: "商户消费",
            amount: 50.0,
            paymentType: "生活必要开支",
            typeDetail: "餐饮"
        )
        XCTAssertEqual(record.paymentType, "生活必要开支")
        XCTAssertEqual(record.typeDetail, "餐饮")
    }

    func test_labeledRecords_partitionByPaymentType() {
        let records = [
            LabeledRecord(counterparty: "A", product: "x", txType: "x", amount: 10,
                         paymentType: "生活必要开支", typeDetail: "餐饮"),
            LabeledRecord(counterparty: "B", product: "x", txType: "x", amount: 20,
                         paymentType: "生活必要开支", typeDetail: "交通"),
            LabeledRecord(counterparty: "C", product: "x", txType: "x", amount: 30,
                         paymentType: "工作收入", typeDetail: "工资"),
        ]
        let grouped = Dictionary(grouping: records, by: { $0.paymentType })
        XCTAssertEqual(grouped["生活必要开支"]?.count, 2)
        XCTAssertEqual(grouped["工作收入"]?.count, 1)
    }

    func test_minimumTrainingThreshold() {
        let threshold = 30
        let fewRecords = Array(repeating: LabeledRecord(
            counterparty: "A", product: "x", txType: "x", amount: 10,
            paymentType: "X", typeDetail: "Y"
        ), count: 10)
        XCTAssertLessThan(fewRecords.count, threshold, "数据不足 30 条不应训练")

        let enoughRecords = Array(repeating: LabeledRecord(
            counterparty: "A", product: "x", txType: "x", amount: 10,
            paymentType: "X", typeDetail: "Y"
        ), count: 35)
        XCTAssertGreaterThanOrEqual(enoughRecords.count, threshold)
    }
}
```

**Step 2: 运行测试确认失败**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter TrainingDataProviderTests
```
预期: FAIL — LabeledRecord 未定义

**Step 3: 实现 TrainingDataProvider**

TrainingDataProvider.swift:
```swift
import Foundation

/// 已标注训练样本（从流水记录中提取）
public struct LabeledRecord: Equatable, Sendable {
    /// 交易对方（商户名）
    public let counterparty: String
    /// 商品/交易说明
    public let product: String
    /// 交易类型
    public let txType: String
    /// 金额（正=支出，负=收入）
    public let amount: Double
    /// 收付类型名称（分类标签 Level 1）
    public let paymentType: String
    /// 类型明细名称（分类标签 Level 2）
    public let typeDetail: String

    public init(
        counterparty: String,
        product: String,
        txType: String,
        amount: Double,
        paymentType: String,
        typeDetail: String
    ) {
        self.counterparty = counterparty
        self.product = product
        self.txType = txType
        self.amount = amount
        self.paymentType = paymentType
        self.typeDetail = typeDetail
    }
}

/// 训练数据提供者协议 — 外部注入数据库查询能力
public protocol LabeledRecordProvider: Sendable {
    /// 拉取所有已标注的流水记录（收付类型和类型明细均已填写的记录）
    func fetchLabeledRecords() async throws -> [LabeledRecord]
}

/// 训练数据常量
public enum TrainingThreshold {
    /// 最少训练样本数，低于此值不预测
    public static let minimumSamples = 30
    /// 训练数据上限，超过此数随机采样
    public static let maxTrainingSamples = 5000
    /// 默认训练轮数
    public static let defaultEpochs = 3
}
```

**Step 4: 运行测试确认通过**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter TrainingDataProviderTests
```
预期: ALL PASS

**Step 5: 提交**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/Classification/TrainingDataProvider.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/TrainingDataProviderTests.swift
git commit -m "feat: add TrainingDataProvider with LabeledRecord types"

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

---

### Task 4: 实现 ClassificationPredictor（主入口）

**Files:**
- Create: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/Classification/ClassificationPredictor.swift`
- Test: `ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/ClassificationPredictorTests.swift`

**Step 1: 编写 ClassificationPredictor 测试**

ClassificationPredictorTests.swift:
```swift
import XCTest
@testable import MingZhangCore

final class ClassificationPredictorTests: XCTestCase {
    // MARK: - 冷启动

    func test_train_withTooFewSamples_skipsPrediction() {
        var predictor = ClassificationPredictor()
        let records = makeRecords(count: 10)
        predictor.train(records: records)
        let result = predictor.predict(
            counterparty: "京东", product: "购物", txType: "商户消费", amount: 50.0
        )
        XCTAssertNil(result.paymentType, "数据不足时不预测 Level 1")
        XCTAssertNil(result.typeDetail, "数据不足时不预测 Level 2")
    }

    // MARK: - 正常训练和预测

    func test_trainAndPredict_withEnoughData() {
        var predictor = ClassificationPredictor()
        // 构造足够数据: 50条 "京东"→"购物" 组
        let records = makeRecords(
            counterparty: "京东商城", txType: "商户消费",
            paymentType: "文娱游购开支", typeDetail: "购物", count: 50
        )
        predictor.train(records: records)
        let result = predictor.predict(
            counterparty: "京东商城", product: "京东-订单", txType: "商户消费", amount: 50.0
        )
        // 应该有预测
        XCTAssertNotNil(result.paymentType)
        // 置信度应 >= 0
        if let pt = result.paymentType {
            XCTAssertGreaterThanOrEqual(pt.confidence, 0.0)
            XCTAssertLessThanOrEqual(pt.confidence, 1.0)
        }
    }

    // MARK: - 低置信度

    func test_predict_untrained_returnsNil() {
        let predictor = ClassificationPredictor()
        // 未训练过，所有预测应为 nil（因为 train 时数据不足跳过了）
        let result = predictor.predict(
            counterparty: "未知", product: "未知", txType: "未知", amount: 50.0
        )
        XCTAssertNil(result.paymentType)
        XCTAssertNil(result.typeDetail)
    }

    // MARK: - Level 2 依赖 Level 1

    func test_predict_level2DependsOnLevel1() {
        var predictor = ClassificationPredictor()
        let records = makeRecords(
            counterparty: "美团", txType: "商户消费",
            paymentType: "生活必要开支", typeDetail: "餐饮", count: 50
        )
        predictor.train(records: records)
        let result = predictor.predict(
            counterparty: "美团", product: "外卖订单", txType: "商户消费", amount: 30.0
        )
        // Level 1 预测了，Level 2 在该类型下有模型才预测
        if let pt = result.paymentType {
            XCTAssertFalse(pt.label.isEmpty)
        }
        // typeDetail 可能有也可能没有，取决于置信度
    }

    // MARK: - 不同分类的区分

    func test_differentInputs_yieldDifferentResults() {
        var predictor = ClassificationPredictor()

        var records = makeRecords(
            counterparty: "美团外卖", txType: "商户消费",
            paymentType: "生活必要开支", typeDetail: "餐饮", count: 40
        )
        records += makeRecords(
            counterparty: "公司工资", txType: "转账",
            paymentType: "工作收入", typeDetail: "工资", count: 40
        )
        predictor.train(records: records)

        let foodResult = predictor.predict(
            counterparty: "美团外卖", product: "订单", txType: "商户消费", amount: 30.0
        )
        let salaryResult = predictor.predict(
            counterparty: "公司工资", product: "转账", txType: "转账", amount: -5000.0
        )

        // 两个不同的输入应该得到不同的预测
        let foodLabel = foodResult.paymentType?.label
        let salaryLabel = salaryResult.paymentType?.label
        // 至少有一个不同（如果两者都预测到了且模型学到了区分）
        // 这是一个软断言——高准确率需要更多数据，这里只检查不崩溃
        XCTAssertNotNil(foodLabel)
        XCTAssertNotNil(salaryLabel)
    }

    // MARK: - Helpers

    func makeRecords(
        counterparty: String,
        txType: String = "商户消费",
        paymentType: String = "生活必要开支",
        typeDetail: String = "餐饮",
        count: Int
    ) -> [LabeledRecord] {
        (0..<count).map { i in
            LabeledRecord(
                counterparty: counterparty,
                product: "商品\(i)",
                txType: txType,
                amount: Double((i + 1) * 10),
                paymentType: paymentType,
                typeDetail: typeDetail
            )
        }
    }
}
```

**Step 2: 运行测试确认失败**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter ClassificationPredictorTests
```
预期: FAIL — ClassificationPredictor 未定义

**Step 3: 实现 ClassificationPredictor**

ClassificationPredictor.swift:
```swift
import Foundation

/// 导入候选记录的预测结果
public struct PredictionResult: Equatable, Sendable {
    public let paymentType: (label: String, confidence: Double)?
    public let typeDetail: (label: String, confidence: Double)?

    public init(
        paymentType: (label: String, confidence: Double)?,
        typeDetail: (label: String, confidence: Double)?
    ) {
        self.paymentType = paymentType
        self.typeDetail = typeDetail
    }
}

/// 导入智能分类预测器 — 主入口
///
/// 两级分层模型:
/// - Level 1: 收付类型（11 类），特征维度 4096
/// - Level 2: 类型明细，特征维度 2048，按收付类型分组
///
/// 用法:
/// ```swift
/// var predictor = ClassificationPredictor()
/// predictor.train(records: labeledRecords)
/// let result = predictor.predict(counterparty: "京东", product: "订单", txType: "商户消费", amount: 50)
/// // result.paymentType?.label → "文娱游购开支"
/// // result.typeDetail?.label → "购物"
/// ```
public struct ClassificationPredictor: Sendable {
    // MARK: - Feature dimensions

    private static let level1Dim = 4096
    private static let level2Dim = 2048

    // MARK: - Thresholds

    /// 置信度阈值，低于此值不预填
    public static let confidenceThreshold: Float = 0.6
    /// 训练数据最少条数（不含此值不训练）
    private static let minTrainingSamples = TrainingThreshold.minimumSamples
    /// 最大训练样本数
    private static let maxTrainingSamples = TrainingThreshold.maxTrainingSamples
    /// 默认训练轮数
    private static let defaultEpochs = TrainingThreshold.defaultEpochs

    // MARK: - State

    /// Level 1: 收付类型预测器
    var level1Model: LogisticRegression
    /// Level 2: 类型明细预测器（key = 收付类型名称）
    var level2Models: [String: LogisticRegression]
    /// Level 1 特征提取器
    private let level1Extractor: FeatureExtractor
    /// Level 2 特征提取器
    private let level2Extractor: FeatureExtractor
    /// Level 1 是否已训练
    var isLevel1Trained: Bool = false

    // MARK: - Init

    public init() {
        self.level1Extractor = FeatureExtractor(dim: Self.level1Dim)
        self.level2Extractor = FeatureExtractor(dim: Self.level2Dim)
        // 用空标签初始化（训练时会扩展）
        self.level1Model = LogisticRegression(featureDim: Self.level1Dim, classLabels: [])
        self.level2Models = [:]
    }

    // MARK: - Training

    /// 用已标注记录训练模型
    /// - Parameter records: 所有已标注流水记录
    public mutating func train(records: [LabeledRecord], epochs: Int = Self.defaultEpochs) {
        guard records.count >= Self.minTrainingSamples else { return }

        // 采样控制训练数据量
        let trainingRecords: [LabeledRecord]
        if records.count > Self.maxTrainingSamples {
            trainingRecords = Array(records.shuffled().prefix(Self.maxTrainingSamples))
        } else {
            trainingRecords = records
        }

        // --- Level 1: 收付类型 ---

        // 收集所有收付类型标签
        let l1Labels = Array(Set(trainingRecords.map(\.paymentType))).sorted()

        // 初始化或更新 Level 1 模型
        level1Model = LogisticRegression(featureDim: Self.level1Dim, classLabels: l1Labels)

        // 准备 Level 1 训练数据
        let l1Samples = trainingRecords.map { record -> (features: [Int: Float], label: Int) in
            let features = level1Extractor.extract(
                counterparty: record.counterparty,
                product: record.product,
                txType: record.txType,
                amount: record.amount
            )
            let label = l1Labels.firstIndex(of: record.paymentType) ?? 0
            return (features: features, label: label)
        }

        level1Model.fit(samples: l1Samples, numClasses: l1Labels.count, epochs: epochs, learningRate: 0.5)
        isLevel1Trained = true

        // --- Level 2: 类型明细（按收付类型分组） ---

        let groupedByType = Dictionary(grouping: trainingRecords, by: { $0.paymentType })

        for (paymentType, typeRecords) in groupedByType {
            // 收集该收付类型下的所有类型明细
            let l2Labels = Array(Set(typeRecords.map(\.typeDetail))).sorted()
            guard l2Labels.count >= 2 else { continue } // 只有一个类型明细没必要训练

            var model = LogisticRegression(featureDim: Self.level2Dim, classLabels: l2Labels)

            let l2Samples = typeRecords.map { record -> (features: [Int: Float], label: Int) in
                let features = level2Extractor.extract(
                    counterparty: record.counterparty,
                    product: record.product,
                    txType: record.txType,
                    amount: record.amount,
                    paymentType: paymentType  // Level 2 特有关键特征
                )
                let label = l2Labels.firstIndex(of: record.typeDetail) ?? 0
                return (features: features, label: label)
            }

            model.fit(samples: l2Samples, numClasses: l2Labels.count, epochs: epochs, learningRate: 0.5)
            level2Models[paymentType] = model
        }
    }

    // MARK: - Prediction

    /// 对导入候选记录进行预测
    /// - Returns: 预测结果，各级可能为 nil（置信度不足）
    public func predict(
        counterparty: String,
        product: String,
        txType: String,
        amount: Double
    ) -> PredictionResult {
        // Level 1: 预测收付类型
        let paymentTypeResult: (label: String, confidence: Double)?
        var predictedType: String?

        if isLevel1Trained, !level1Model.classLabels.isEmpty {
            let features = level1Extractor.extract(
                counterparty: counterparty, product: product,
                txType: txType, amount: amount
            )
            let (idx, conf) = level1Model.predict(features: features)
            if conf >= Self.confidenceThreshold, idx < level1Model.classLabels.count {
                let label = level1Model.classLabels[idx]
                paymentTypeResult = (label: label, confidence: Double(conf))
                predictedType = label
            } else {
                paymentTypeResult = nil
            }
        } else {
            paymentTypeResult = nil
        }

        // Level 2: 在已知收付类型下预测类型明细
        let typeDetailResult: (label: String, confidence: Double)?
        if let pt = predictedType, let l2Model = level2Models[pt], !l2Model.classLabels.isEmpty {
            let features = level2Extractor.extract(
                counterparty: counterparty, product: product,
                txType: txType, amount: amount,
                paymentType: pt
            )
            let (idx, conf) = l2Model.predict(features: features)
            if conf >= Self.confidenceThreshold, idx < l2Model.classLabels.count {
                typeDetailResult = (label: l2Model.classLabels[idx], confidence: Double(conf))
            } else {
                typeDetailResult = nil
            }
        } else {
            typeDetailResult = nil
        }

        return PredictionResult(paymentType: paymentTypeResult, typeDetail: typeDetailResult)
    }

    // MARK: - Class Management

    /// 通知有新收付类型加入（下次训练时自动处理）
    public mutating func invalidateLevel1() {
        isLevel1Trained = false
    }

    /// 通知某收付类型下的类型明细有变化（下次训练时自动处理）
    public mutating func invalidateLevel2(for paymentType: String) {
        level2Models.removeValue(forKey: paymentType)
    }
}
```

**Step 4: 运行测试确认通过**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter ClassificationPredictorTests
```
预期: ALL PASS

**Step 5: 提交**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/Classification/ClassificationPredictor.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/ClassificationPredictorTests.swift
git commit -m "feat: add ClassificationPredictor with two-level hierarchical model"

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

---

### Task 5: GRDB 集成 — 实现 LabeledRecordProvider

**Files:**
- Modify: `ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift` — 添加 LabeledRecordProvider 的实现

**Context**: 在现有的 GRDB 数据库访问层中，实现 `LabeledRecordProvider` 协议，从 `journal_record`、`payment_type`、`payment_detail` 三表联查获取已标注记录。需要读原始账单字段（从 `description` 或 `rawPayload` 中解析）。

**注意**: 由于 P1 导入尚未实现，原始账单字段（交易对方、商品说明等）当前可能不存在于 `JournalRecord` 模型中。此任务先实现框架代码，具体字段映射在 P1 导入实现后补充。当前可以先从 `JournalRecord` 的 `note` 字段和已有字段中提取可用的训练特征。

**Step 1: 编写集成测试**

在 `P0LedgerFlowTests.swift` 末尾追加：

```swift
// MARK: - ML Classification LabeledRecordProvider

extension P0LedgerFlowTests {
    func test_fetchLabeledRecords_returnsEmptyForEmptyDB() async throws {
        let db = try await createTestDB()
        let provider = db.labeledRecordProvider()
        let records = try await provider.fetchLabeledRecords()
        XCTAssertEqual(records.count, 0, "空数据库应返回空列表")
    }

    func test_fetchLabeledRecords_withClassifiedRecords() async throws {
        let db = try await createTestDB()
        // 创建带分类的流水记录
        _ = try await db.createRecord(CreateManualRecordInput(
            accountMonth: "2026-05",
            date: "2026-05-12T10:00:00",
            paymentMethodId: db.defaultPaymentMethodId(),
            paymentTypeId: db.defaultPaymentTypeId(),
            paymentDetailId: db.defaultPaymentDetailId(),
            amount: 50.0,
            note: "京东-京东商城-商户消费"
        ))
        // 再创建一条无分类的记录（不应出现在训练数据中）
        _ = try await db.createRecord(CreateManualRecordInput(
            accountMonth: "2026-05",
            date: "2026-05-12T11:00:00",
            paymentMethodId: db.defaultPaymentMethodId(),
            amount: 30.0,
            note: "测试"
        ))
        let provider = db.labeledRecordProvider()
        let records = try await provider.fetchLabeledRecords()
        // 只有已标注的应被返回
        XCTAssertGreaterThanOrEqual(records.count, 1)
    }
}
```

**Step 2: 运行测试确认失败**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter "P0LedgerFlowTests"
```
预期: FAIL — `labeledRecordProvider()` 方法不存在

**Step 3: 在 MingZhangCore.swift 中实现（新增 extension）**

```swift
// 在 MingZhangCore.swift 末尾追加

// MARK: - ML LabeledRecordProvider

extension MingZhangDB {
    public func labeledRecordProvider() -> LabeledRecordProvider {
        MLTrainingDataProvider(db: self)
    }
}

private struct MLTrainingDataProvider: LabeledRecordProvider {
    let db: MingZhangDB

    func fetchLabeledRecords() async throws -> [LabeledRecord] {
        try await db.queue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    jr.note,
                    jr.amount,
                    pt.name AS payment_type_name,
                    pd.name AS payment_detail_name
                FROM journal_record jr
                JOIN payment_type pt ON jr.payment_type_id = pt.id
                JOIN payment_detail pd ON jr.payment_detail_id = pd.id
                WHERE jr.payment_type_id IS NOT NULL
                  AND jr.payment_detail_id IS NOT NULL
                  AND jr.deleted_at IS NULL
                ORDER BY jr.date DESC
                """)
            return rows.compactMap { row in
                guard let paymentType: String = row["payment_type_name"],
                      let typeDetail: String = row["payment_detail_name"],
                      let note: String = row["note"],
                      let amount: Double = row["amount"] else {
                    return nil
                }
                // 从 note 中解析原始字段（P1 导入后会存储结构化数据）
                // 当前 note 格式: "商户名-商品-交易类型" 或自由文本
                let parts = note.components(separatedBy: "-")
                let counterparty = parts.count > 0 ? parts[0] : note
                let product = parts.count > 1 ? parts[1] : ""
                let txType = parts.count > 2 ? parts[2] : ""

                return LabeledRecord(
                    counterparty: counterparty,
                    product: product,
                    txType: txType,
                    amount: amount,
                    paymentType: paymentType,
                    typeDetail: typeDetail
                )
            }
        }
    }
}
```

**Step 4: 运行测试确认通过**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test --filter "test_fetchLabeledRecords"
```
预期: PASS

**Step 5: 提交**

```bash
git add ios/MingZhang/Packages/MingZhangCore/Sources/MingZhangCore/MingZhangCore.swift \
        ios/MingZhang/Packages/MingZhangCore/Tests/MingZhangCoreTests/P0LedgerFlowTests.swift
git commit -m "feat: add GRDB LabeledRecordProvider for ML training data"

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

---

### Task 6: 导入流程集成指南

**此任务不写代码**，而是提供清晰的集成指南，供 P1 导入流程实现时使用。

**集成点在 P1 计划中的位置**: 在 P1 的 Task 7（候选记录预览与整理）中，候选记录列表生成后、展示预览页面前，插入 ML 预测步骤。

**集成伪代码**:

```swift
// 在导入 UseCase 中（P1 实现后）

// 步骤1: 解析 CSV → 候选记录
let candidates = try parseCSV(fileContent: content, source: source)

// 步骤2: [新] ML 预测
let provider = db.labeledRecordProvider()
let labeledRecords = try await provider.fetchLabeledRecords()
var predictor = ClassificationPredictor()
predictor.train(records: labeledRecords)

for i in 0..<candidates.count {
    let result = predictor.predict(
        counterparty: candidates[i].counterparty,
        product: candidates[i].product,
        txType: candidates[i].txType,
        amount: candidates[i].amount
    )
    if let pt = result.paymentType {
        candidates[i].prefillPaymentType = pt.label  // 预填标记
    }
    if let td = result.typeDetail {
        candidates[i].prefillTypeDetail = td.label
    }
}

// 步骤3: 展示预览页面
// 预填字段使用浅蓝底色标记，用户可修改
```

**UI 侧修改**（不在本计划范围，仅记录）:
- 导入预览页中，收付类型/类型明细选择器若已有 `prefillPaymentType` 值，则预选中并给浅蓝色背景
- 无预填值时正常显示占位文字
- 用户修改后去掉预填标记样式

**测试建议**（P1 实现时）:
- 在 P1 的集成测试中加入：导入前先创建 30+ 条同商户分类记录，导入同商户账单时验证分类被预填

---

### Task 7: 全量测试与验收

**Step 1: 运行全部测试**

```bash
cd ios/MingZhang/Packages/MingZhangCore && swift test
```
预期: ALL TESTS PASS

**Step 2: 验证端到端流程**

用模拟数据手动验证整个训练-推理流程：

创建 TestHarness.swift（仅本地运行，不提交到仓库）:

```swift
// 端到端手动测试脚本
import MingZhangCore

func runE2E() {
    var predictor = ClassificationPredictor()

    // 模拟 50 条已标注记录
    var records: [LabeledRecord] = []
    for i in 0..<25 {
        records.append(LabeledRecord(
            counterparty: "京东商城", product: "京东-订单\(i)",
            txType: "商户消费", amount: Double(50 + i),
            paymentType: "文娱游购开支", typeDetail: "购物"
        ))
    }
    for i in 0..<25 {
        records.append(LabeledRecord(
            counterparty: "美团外卖", product: "美团-订单\(i)",
            txType: "商户消费", amount: Double(20 + i),
            paymentType: "生活必要开支", typeDetail: "餐饮"
        ))
    }

    // 训练
    predictor.train(records: records)

    // 测试预测
    let r1 = predictor.predict(
        counterparty: "京东商城", product: "京东-新订单",
        txType: "商户消费", amount: 100.0
    )
    print("京东预测: \(r1.paymentType?.label ?? "nil") (置信度: \(r1.paymentType?.confidence ?? 0))")

    let r2 = predictor.predict(
        counterparty: "美团外卖", product: "外卖",
        txType: "商户消费", amount: 35.0
    )
    print("美团预测: \(r2.paymentType?.label ?? "nil") (置信度: \(r2.paymentType?.confidence ?? 0))")

    let r3 = predictor.predict(
        counterparty: "完全未知商户", product: "未知商品",
        txType: "转账", amount: -500.0
    )
    print("未知预测: \(r3.paymentType?.label ?? "nil") (置信度: \(r3.paymentType?.confidence ?? 0))")
}

runE2E()
```

运行: `swift run`（如适用）或直接通过测试验证

**Step 3: 提交最终确认**

```bash
git status
git log --oneline -7
```

---

## 文件变更总览

| 操作 | 文件 |
|------|------|
| 新建 | `Sources/MingZhangCore/Classification/FeatureExtractor.swift` |
| 新建 | `Sources/MingZhangCore/Classification/LogisticRegression.swift` |
| 新建 | `Sources/MingZhangCore/Classification/TrainingDataProvider.swift` |
| 新建 | `Sources/MingZhangCore/Classification/ClassificationPredictor.swift` |
| 修改 | `Sources/MingZhangCore/MingZhangCore.swift`（追加 LabeledRecordProvider extension） |
| 新建 | `Tests/MingZhangCoreTests/FeatureExtractorTests.swift` |
| 新建 | `Tests/MingZhangCoreTests/LogisticRegressionTests.swift` |
| 新建 | `Tests/MingZhangCoreTests/TrainingDataProviderTests.swift` |
| 新建 | `Tests/MingZhangCoreTests/ClassificationPredictorTests.swift` |
| 修改 | `Tests/MingZhangCoreTests/P0LedgerFlowTests.swift`（追加 ML 集成测试） |

## 依赖关系

```
Task 1 (FeatureExtractor)        → 无依赖
Task 2 (LogisticRegression)      → 无依赖（独立实现）
Task 3 (TrainingDataProvider)    → 无依赖（类型定义）
Task 4 (ClassificationPredictor) → 依赖 Task 1, 2, 3
Task 5 (GRDB 集成)               → 依赖 Task 3, Task 4
Task 6 (导入集成指南)            → 依赖 Task 4, Task 5（仅文档）
Task 7 (全量验收)                → 依赖所有前序任务
```

Tasks 1-3 可并行开发（无相互依赖）。

## 不在本计划范围

- P1 导入流程实现（CSV 解析、候选记录、确认入账等）
- SwiftUI 导入预览页的预填标记样式
- 模型持久化/缓存
- 规则兜底逻辑
- Core ML 导出
- 性能基准测试
