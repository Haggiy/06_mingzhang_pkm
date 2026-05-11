# 明账 iOS 工程

本目录承接 P0 工程启动计划：

- App 工程：`MingZhang.xcodeproj`
- 本地核心包：`Packages/MingZhangCore`
- 技术栈：SwiftUI + iOS 18+ + SQLite/GRDB

## 当前 P0 范围

当前只实现最小纵向闭环：

```text
手工新增信用卡餐饮消费
-> 保存为流水真源记录
-> 引擎形成支出 + 负债
-> 首页、资产负债、统计同步读取真实结果
-> 修改 / 删除后重算
```

支付宝 / 微信导入、基金投资、备份恢复属于 P1，暂未进入当前代码。

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
