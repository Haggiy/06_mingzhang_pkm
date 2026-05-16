# 明账 iOS 工程

本目录承接 P0 工程启动计划：

- App 工程：`MingZhang.xcodeproj`
- 本地核心包：`Packages/MingZhangCore`
- 技术栈：SwiftUI + iOS 18+ + SQLite/GRDB

## 当前已覆盖范围

- P0 手工流水纵向闭环。
- P1 支付宝 / 微信导入整理。
- P1 基金投资明细账：基金交易事实、平均成本法、投资回填流水、资产负债和统计入口。

基金投资当前只支持手工维护交易和净值记录，不支持实时行情、非基金品类或复杂组合分析。

## 常用命令

当前机器的 `xcode-select` 可能仍指向 Command Line Tools。CLI 执行时建议显式指定 Xcode：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

核心包测试：

```bash
cd ios/MingZhang/Packages/MingZhangCore
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

iOS 模拟器构建：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/MingZhang/MingZhang.xcodeproj \
  -scheme MingZhang \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -clonedSourcePackagesDirPath ios/MingZhang/SourcePackages \
  build
```

`-clonedSourcePackagesDirPath` 用于让 Xcode 复用本工程本地包缓存，避免默认 DerivedData 中的 SwiftPM checkout 临时失败。
