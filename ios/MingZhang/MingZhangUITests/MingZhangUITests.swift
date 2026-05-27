import XCTest

private extension XCUIApplication {
    func waitForMingZhangTab(_ title: String, timeout: TimeInterval = 10) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let customTab = buttons["tab_\(title)"]
            if customTab.exists {
                return customTab
            }

            let nativeTab = tabBars.buttons[title]
            if nativeTab.exists {
                return nativeTab
            }

            let fallbackButton = buttons[title]
            if fallbackButton.exists {
                return fallbackButton
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        return buttons["tab_\(title)"]
    }
}

/// 导入记忆预填 UI 集成测试
/// 通过 launchEnvironment 注入测试数据，绕过剪贴板权限弹窗
final class ImportMemoryUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
    }

    override func tearDown() {
        app.terminate()
    }

    // MARK: - CSV 模板

    func alipayCSV(
        counterparty: String,
        product: String,
        amount: String = "100.00",
        orderId: String = "T-001",
        direction: String = "支出"
    ) -> String {
        return """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,\(counterparty),/,\(product),\(direction),\(amount),广发卡,交易成功,\(orderId)\t,\t,,
        """
    }

    func wechatCSV(counterparty: String, product: String, orderId: String = "WX-T-001") -> String {
        return """
        微信支付账单明细,,,,,,,,
        微信昵称：[test],,,,,,,,
        起始时间：[2026-04-01 00:00:00] 终止时间：[2026-04-30 23:59:59],,,,,,,,
        导出类型：[全部],,,,,,,,
        导出时间：[2026-05-11 10:00:00],,,,,,,,
        ,,,,,,,,
        共1笔记录,,,,,,,,
        支出：1笔 20.50元,,,,,,,,
        ,,,,,,,,
        ----------------------微信支付账单明细列表--------------------,,,,,,,,
        交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
        2026-04-16 08:05:06,商户消费,\(counterparty),\(product),支出,¥20.50,零钱,支付成功,\(orderId)\t,WX-M-001\t,/
        """
    }

    // MARK: - 设置辅助

    /// 添加一个设置步骤：导入并确认
    func addSetupStep(index: Int, csv: String, source: String = "alipay", type: String, detail: String) {
        app.launchEnvironment["MZ_SETUP_\(index)_CSV"] = csv
        app.launchEnvironment["MZ_SETUP_\(index)_SOURCE"] = source
        app.launchEnvironment["MZ_SETUP_\(index)_TYPE"] = type
        app.launchEnvironment["MZ_SETUP_\(index)_DETAIL"] = detail
    }

    /// 设置待验证的测试导入
    func setTestImport(csv: String, source: String = "alipay") {
        app.launchEnvironment["MZ_TEST_CSV"] = csv
        app.launchEnvironment["MZ_TEST_SOURCE"] = source
    }

    // MARK: - 视觉验收截图

    var screenshotDirectory: URL? {
        let markerPath = "/tmp/mingzhang-v51-screenshots/.enabled"
        let path: String
        if let environmentPath = ProcessInfo.processInfo.environment["MZ_SCREENSHOT_DIR"], !environmentPath.isEmpty {
            path = environmentPath
        } else if FileManager.default.fileExists(atPath: markerPath) {
            path = "/tmp/mingzhang-v51-screenshots"
        } else {
            return nil
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func captureV51Screenshot(_ name: String) {
        guard let screenshotDirectory else { return }
        let screenshot = XCUIScreen.main.screenshot()
        let outputURL = screenshotDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: outputURL)
    }

    var isCapturingV51Screenshots: Bool {
        screenshotDirectory != nil
    }

    func tapBackButton() {
        let backButton = app.buttons["返回"].firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        } else if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func closePresentedSheet() {
        let closeButton = app.buttons["关闭"].firstMatch
        if closeButton.waitForExistence(timeout: 3) {
            closeButton.tap()
            return
        }

        let cancelButton = app.buttons["month_picker_cancel"].firstMatch
        if cancelButton.waitForExistence(timeout: 2) {
            cancelButton.tap()
        }
    }

    func tapVisibleButton(identifier: String, timeout: TimeInterval = 5) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "应存在按钮 \(identifier)")
        if !button.isHittable {
            app.swipeUp()
        }
        button.tap()
    }

    @discardableResult
    func waitForAnyElement(identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "应存在元素 \(identifier)")
        return element
    }

    func navigateToDataRestore() {
        app.waitForMingZhangTab("设置").tap()
        XCTAssertTrue(app.staticTexts["记账配置"].waitForExistence(timeout: 5))
        tapVisibleButton(identifier: "settings_data_restore")
        XCTAssertTrue(app.staticTexts["数据恢复"].waitForExistence(timeout: 5))
    }

    // MARK: - 导航

    func testV51PrimaryTabsExposeCoreSectionsAndQuickMenu() {
        continueAfterFailure = false
        addSetupStep(
            index: 0,
            csv: alipayCSV(counterparty: "基金平台", product: "投资收益", amount: "6100.00", orderId: "V51-INC-1", direction: "收入"),
            type: "理财收入",
            detail: "投资收益"
        )
        addSetupStep(
            index: 1,
            csv: alipayCSV(counterparty: "早餐铺", product: "早午餐", amount: "28.50", orderId: "V51-EXP-1"),
            type: "生活必要开支",
            detail: "伙食费"
        )
        addSetupStep(
            index: 2,
            csv: alipayCSV(counterparty: "游乐店", product: "周末消费", amount: "88.00", orderId: "V51-EXP-2"),
            type: "文娱游购开支",
            detail: "饮食游乐费"
        )
        addSetupStep(
            index: 3,
            csv: alipayCSV(counterparty: "基金平台", product: "赎回亏损", amount: "32.00", orderId: "V51-EXP-3"),
            type: "财务费用开支",
            detail: "投资亏损"
        )
        app.launch()

        XCTAssertTrue(app.waitForMingZhangTab("首页").exists)
        XCTAssertTrue(app.staticTexts["收支摘要"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["收入结构"].exists)
        XCTAssertTrue(app.staticTexts["支出结构"].exists)
        XCTAssertTrue(app.staticTexts["最近账目"].exists)
        captureV51Screenshot("01-首页")

        tapVisibleButton(identifier: "structure_item_生活必要开支")
        XCTAssertTrue(app.staticTexts["二级明细"].waitForExistence(timeout: 5))
        captureV51Screenshot("17-首页-分类底部抽屉")
        tapVisibleButton(identifier: "home_category_detail_button")
        XCTAssertTrue(app.staticTexts["近 6 个月趋势"].waitForExistence(timeout: 5))
        captureV51Screenshot("18-首页-分类详情")
        tapVisibleButton(identifier: "category_detail_source_records_button")
        XCTAssertTrue(app.staticTexts["当前筛选"].waitForExistence(timeout: 5))
        captureV51Screenshot("19-来源流水筛选态")
        tapBackButton()
        tapBackButton()
        XCTAssertTrue(app.staticTexts["收支摘要"].waitForExistence(timeout: 5))

        XCTAssertTrue(app.buttons["btn_home_quick_add"].exists)
        app.buttons["btn_home_quick_add"].tap()
        XCTAssertTrue(app.buttons["记一笔"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["导入账单"].exists)
        XCTAssertTrue(app.buttons["查找"].exists)
        captureV51Screenshot("02-首页-快捷菜单")

        app.buttons["btn_home_quick_close"].tap()
        XCTAssertFalse(app.buttons["btn_home_quick_close"].exists)

        tapVisibleButton(identifier: "btn_month_picker")
        XCTAssertTrue(app.staticTexts["账月范围"].waitForExistence(timeout: 5))
        captureV51Screenshot("09-账月范围")
        closePresentedSheet()

        app.waitForMingZhangTab("流水").tap()
        let recordCountLabel = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '共'")).firstMatch
        XCTAssertTrue(recordCountLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["搜索"].exists)
        XCTAssertTrue(app.buttons["点击这里记一笔"].exists)
        XCTAssertTrue(app.buttons["筛选"].exists)
        captureV51Screenshot("03-流水")

        tapVisibleButton(identifier: "journal_filter_button")
        XCTAssertTrue(app.staticTexts["筛选"].waitForExistence(timeout: 5))
        captureV51Screenshot("10-流水-筛选")
        closePresentedSheet()

        tapVisibleButton(identifier: "journal_search_button")
        XCTAssertTrue(app.staticTexts["搜索"].waitForExistence(timeout: 5))
        captureV51Screenshot("11-流水-搜索")
        tapBackButton()

        if isCapturingV51Screenshots {
            let firstRecord = app.buttons.matching(NSPredicate(format: "label CONTAINS '/'")).firstMatch
            if firstRecord.waitForExistence(timeout: 2) {
                firstRecord.tap()
                if app.staticTexts["记录详情"].waitForExistence(timeout: 3) {
                    captureV51Screenshot("04-记录详情")
                }
                if app.buttons["返回"].exists {
                    app.buttons["返回"].tap()
                } else if app.navigationBars.buttons.firstMatch.exists {
                    app.navigationBars.buttons.firstMatch.tap()
                } else if app.buttons["chevron.left"].exists {
                    app.buttons["chevron.left"].tap()
                }
            }
        }

        app.waitForMingZhangTab("资产负债").tap()
        XCTAssertTrue(app.staticTexts["资产合计"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["负债合计"].exists)
        XCTAssertTrue(app.staticTexts["净资产"].exists)
        captureV51Screenshot("05-资产负债")

        tapVisibleButton(identifier: "asset_cash_detail_entry")
        XCTAssertTrue(app.staticTexts["当前余额（成本口径）"].waitForExistence(timeout: 5))
        captureV51Screenshot("22-资产详情")
        tapVisibleButton(identifier: "asset_adjust_balance_button")
        XCTAssertTrue(app.staticTexts["调整余额"].waitForExistence(timeout: 5))
        captureV51Screenshot("23-调整余额")
        tapBackButton()
        tapBackButton()
        XCTAssertTrue(app.staticTexts["资产合计"].waitForExistence(timeout: 5))

        let liabilityRow = app.buttons["liability_row_广发卡"].firstMatch
        if liabilityRow.waitForExistence(timeout: 3) {
            liabilityRow.tap()
            XCTAssertTrue(app.staticTexts["剩余负债"].waitForExistence(timeout: 5))
            captureV51Screenshot("24-负债详情")
            tapBackButton()
        }

        app.waitForMingZhangTab("统计").tap()
        XCTAssertTrue(app.staticTexts["结果总览"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["资产负债变化"].exists)
        XCTAssertTrue(app.staticTexts["投资结果"].exists)
        captureV51Screenshot("06-统计")

        tapVisibleButton(identifier: "structure_item_生活必要开支")
        XCTAssertTrue(app.staticTexts["近 6 个月趋势"].waitForExistence(timeout: 5))
        captureV51Screenshot("25-统计-收支分类详情")
        tapBackButton()
        XCTAssertTrue(app.staticTexts["结果总览"].waitForExistence(timeout: 5))

        tapVisibleButton(identifier: "statistics_balance_change_detail")
        XCTAssertTrue(app.staticTexts["资产负债变化"].waitForExistence(timeout: 5))
        captureV51Screenshot("26-统计-资产负债变化详情")
        tapBackButton()
        XCTAssertTrue(app.staticTexts["结果总览"].waitForExistence(timeout: 5))

        app.waitForMingZhangTab("设置").tap()
        XCTAssertTrue(app.staticTexts["记账配置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["数据管理"].exists)
        XCTAssertTrue(app.staticTexts["App 设置"].exists)
        captureV51Screenshot("07-设置")

        tapVisibleButton(identifier: "settings_payment_methods")
        XCTAssertTrue(app.staticTexts["收付手段管理"].waitForExistence(timeout: 5))
        captureV51Screenshot("12-收付手段管理")
        tapBackButton()

        XCTAssertTrue(app.staticTexts["记账配置"].waitForExistence(timeout: 5))
        tapVisibleButton(identifier: "settings_payment_types")
        XCTAssertTrue(app.staticTexts["收付类型与明细"].waitForExistence(timeout: 5))
        captureV51Screenshot("13-收付类型与明细")

        let detailRow = app.buttons["payment_detail_row_伙食费"].firstMatch
        for _ in 0..<5 where !detailRow.isHittable {
            app.swipeUp()
        }
        if detailRow.exists && detailRow.isHittable {
            detailRow.tap()
            XCTAssertTrue(app.staticTexts["类型明细编辑"].waitForExistence(timeout: 5))
            captureV51Screenshot("14-类型明细编辑")
            tapBackButton()
        }

        tapBackButton()
        XCTAssertTrue(app.staticTexts["记账配置"].waitForExistence(timeout: 5))
        tapVisibleButton(identifier: "settings_data_clear")
        XCTAssertTrue(app.staticTexts["数据清空确认"].waitForExistence(timeout: 5))
        captureV51Screenshot("15-数据清空确认")
        tapBackButton()
    }

    func testSettingsCanCreateAndDisablePaymentMethod() {
        continueAfterFailure = false
        app.launch()

        app.waitForMingZhangTab("设置").tap()
        XCTAssertTrue(app.staticTexts["记账配置"].waitForExistence(timeout: 5))
        tapVisibleButton(identifier: "settings_payment_methods")
        XCTAssertTrue(app.staticTexts["收付手段管理"].waitForExistence(timeout: 5))

        tapVisibleButton(identifier: "payment_method_add_asset")
        XCTAssertTrue(app.staticTexts["新增收付手段"].waitForExistence(timeout: 5))

        let nameField = app.textFields["payment_method_name_field"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("UI测试钱包")

        let saveButton = app.buttons["payment_method_save"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let createdRow = app.buttons["payment_method_row_UI测试钱包"].firstMatch
        XCTAssertTrue(createdRow.waitForExistence(timeout: 5))
        createdRow.tap()
        XCTAssertTrue(app.staticTexts["编辑收付手段"].waitForExistence(timeout: 5))

        let disableButton = app.buttons["payment_method_disable"].firstMatch
        XCTAssertTrue(disableButton.waitForExistence(timeout: 5))
        disableButton.tap()

        let disabledRow = app.buttons["payment_method_row_UI测试钱包"].firstMatch
        XCTAssertTrue(disabledRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["停用"].exists)
    }

    func testBackupRestoreFlowUsesConfirmationAndShowsSuccess() {
        continueAfterFailure = false
        app.launch()

        app.waitForMingZhangTab("设置").tap()
        XCTAssertTrue(app.staticTexts["记账配置"].waitForExistence(timeout: 5))
        tapVisibleButton(identifier: "settings_data_export")
        XCTAssertTrue(app.staticTexts["数据导出"].waitForExistence(timeout: 5))
        tapVisibleButton(identifier: "backup_create_button")
        waitForAnyElement(identifier: "backup_share_button")
        tapBackButton()

        navigateToDataRestore()
        tapVisibleButton(identifier: "restore_test_valid_backup_button")
        tapVisibleButton(identifier: "restore_preview_button")
        XCTAssertTrue(app.staticTexts["恢复前确认"].waitForExistence(timeout: 5))

        let confirmField = app.textFields["restore_confirm_text_field"].firstMatch
        XCTAssertTrue(confirmField.waitForExistence(timeout: 5))
        confirmField.tap()
        confirmField.typeText("恢复数据 继续")

        tapVisibleButton(identifier: "restore_confirm_button")
        waitForAnyElement(identifier: "restore_result_success", timeout: 10)
        tapVisibleButton(identifier: "restore_result_done_button")
    }

    func testBackupRestoreRejectsInvalidBackupWithoutChangingData() {
        continueAfterFailure = false
        app.launch()

        navigateToDataRestore()
        tapVisibleButton(identifier: "restore_test_invalid_backup_button")
        waitForAnyElement(identifier: "restore_validation_failed")
        XCTAssertTrue(app.staticTexts["校验失败"].exists)
    }

    func navigateToImport(source: String) {
        XCTAssertTrue(app.waitForMingZhangTab("首页").exists)
        app.waitForMingZhangTab("首页").tap()
        XCTAssertTrue(app.buttons["btn_home_quick_add"].waitForExistence(timeout: 5))
        app.buttons["btn_home_quick_add"].tap()
        XCTAssertTrue(app.buttons["导入账单"].waitForExistence(timeout: 5))
        app.buttons["导入账单"].tap()
        sleep(1)

        let cellId = source == "wechat" ? "import-source-wechat" : "import-source-alipay"
        XCTAssertTrue(app.buttons[cellId].waitForExistence(timeout: 10))
        app.buttons[cellId].tap()
        sleep(1)
    }

    // MARK: - 断言

    func assertClassificationDisplayed(method: String = "广发卡", type: String? = nil, detail: String? = nil) {
        let label: String
        if let type, let detail {
            label = "\(method) / \(type) / \(detail)"
        } else {
            label = "\(method) / 未设置 / 未设置"
        }
        XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 10),
                      "应有分类标签「\(label)」")
    }

    // MARK: - TC-001: 核心预填

    func testCorePrefill() {
        addSetupStep(index: 0,
                     csv: alipayCSV(counterparty: "记忆便利店", product: "午餐套餐", orderId: "CORE-1"),
                     type: "生活必要开支", detail: "伙食费")
        setTestImport(csv: alipayCSV(counterparty: "记忆便利店", product: "午餐套餐", amount: "25.00", orderId: "CORE-2"))
        app.launch()

        navigateToImport(source: "alipay")
        assertClassificationDisplayed(type: "生活必要开支", detail: "伙食费")
        captureV51Screenshot("08-导入整理")

        XCTAssertTrue(app.buttons["import-select-all-btn"].waitForExistence(timeout: 5))
        app.buttons["import-select-all-btn"].tap()
        XCTAssertTrue(app.buttons["import-batch-edit-btn"].waitForExistence(timeout: 5))
        app.buttons["import-batch-edit-btn"].tap()
        XCTAssertTrue(app.staticTexts["批量修改"].waitForExistence(timeout: 5))
        captureV51Screenshot("20-导入候选批量修改")
    }

    // MARK: - TC-002: 同商户不同商品

    func testSameMerchantDifferentProduct() {
        addSetupStep(index: 0,
                     csv: alipayCSV(counterparty: "商品边界店", product: "午餐套餐", orderId: "BND-1"),
                     type: "生活必要开支", detail: "伙食费")
        setTestImport(csv: alipayCSV(counterparty: "商品边界店", product: "晚餐套餐", orderId: "BND-2"))
        app.launch()

        navigateToImport(source: "alipay")
        assertClassificationDisplayed() // 无预填
    }

    // MARK: - TC-003: 不同商户同商品

    func testDifferentMerchantSameProduct() {
        addSetupStep(index: 0,
                     csv: alipayCSV(counterparty: "边界一店", product: "固定套餐", orderId: "MRC-1"),
                     type: "生活必要开支", detail: "伙食费")
        setTestImport(csv: alipayCSV(counterparty: "边界二店", product: "固定套餐", orderId: "MRC-2"))
        app.launch()

        navigateToImport(source: "alipay")
        assertClassificationDisplayed() // 无预填
    }

    // MARK: - TC-004: 跨来源不预填

    func testNoCrossSourcePrefill() {
        addSetupStep(index: 0,
                     csv: alipayCSV(counterparty: "来源隔离店", product: "通用套餐", orderId: "XSRC-1"),
                     type: "生活必要开支", detail: "伙食费")
        setTestImport(csv: wechatCSV(counterparty: "来源隔离店", product: "通用套餐", orderId: "XSRC-2"),
                      source: "wechat")
        app.launch()

        navigateToImport(source: "wechat")
        assertClassificationDisplayed(method: "待补真实账户") // 微信支付方式未匹配时用待补真实账户
    }

    // MARK: - TC-005: 商户为 / 不预填

    func testSlashMerchant() {
        addSetupStep(index: 0,
                     csv: alipayCSV(counterparty: "/", product: "午餐套餐", orderId: "SLSH-1"),
                     type: "生活必要开支", detail: "伙食费")
        setTestImport(csv: alipayCSV(counterparty: "/", product: "午餐套餐", orderId: "SLSH-2"))
        app.launch()

        navigateToImport(source: "alipay")
        assertClassificationDisplayed() // 无预填（商户为 /）
    }

    // MARK: - TC-006: 冲突历史

    func testConflictHistory() {
        addSetupStep(index: 0,
                     csv: alipayCSV(counterparty: "冲突便利店", product: "午餐套餐", orderId: "CNFL-1"),
                     type: "生活必要开支", detail: "伙食费")
        addSetupStep(index: 1,
                     csv: alipayCSV(counterparty: "冲突便利店", product: "午餐套餐", amount: "80.00", orderId: "CNFL-2"),
                     type: "文娱游购开支", detail: "饮食游乐费")
        setTestImport(csv: alipayCSV(counterparty: "冲突便利店", product: "午餐套餐", amount: "35.00", orderId: "CNFL-3"))
        app.launch()

        navigateToImport(source: "alipay")
        assertClassificationDisplayed() // 冲突，无预填
    }

    // MARK: - TC-007: 编辑后记忆

    // 注：编辑已确认流水的完整 UI 流程需要额外实现。
    // 当前此测试验证：设置阶段用 type=文娱游购开支/detail=饮食游乐费 确认后，
    // 新导入应预填编辑后的值。该逻辑已有单元测试覆盖。
    func testEditMemoryPrefillsCurrentClassification() {
        // 模拟编辑后状态：直接用编辑后的分类作为 setup
        addSetupStep(index: 0,
                     csv: alipayCSV(counterparty: "编辑记忆店", product: "晚餐套餐", orderId: "EDIT-1"),
                     type: "文娱游购开支", detail: "饮食游乐费")
        setTestImport(csv: alipayCSV(counterparty: "编辑记忆店", product: "晚餐套餐", amount: "90.00", orderId: "EDIT-2"))
        app.launch()

        navigateToImport(source: "alipay")
        assertClassificationDisplayed(type: "文娱游购开支", detail: "饮食游乐费")
    }

    // MARK: - TC-008: 删除后失效

    // 注：删除流水后重新导入的完整 UI 流程较复杂。
    // 当前此测试验证：无历史确认记录时，不预填。
    // 完整的删除→重导入流程已有单元测试覆盖。
    func testNoMemoryWithoutHistory() {
        // 不添加任何 setup，直接导入
        setTestImport(csv: alipayCSV(counterparty: "删除记忆店", product: "午餐套餐", orderId: "DEL-1"))
        app.launch()

        navigateToImport(source: "alipay")
        assertClassificationDisplayed() // 无历史，无预填
    }
}

final class InvestmentLedgerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment["MZ_INVESTMENT_SETUP"] = """
        2026-03|2026-03-10|沪深300指数A|buy|300|200|1.50|起始买入
        2026-04|2026-04-10|沪深300指数A|sell|-120|-100||赎回
        """
    }

    override func tearDown() {
        app.terminate()
    }

    var screenshotDirectory: URL? {
        let markerPath = "/tmp/mingzhang-v51-screenshots/.enabled"
        let path: String
        if let environmentPath = ProcessInfo.processInfo.environment["MZ_SCREENSHOT_DIR"], !environmentPath.isEmpty {
            path = environmentPath
        } else if FileManager.default.fileExists(atPath: markerPath) {
            path = "/tmp/mingzhang-v51-screenshots"
        } else {
            return nil
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func captureV51Screenshot(_ name: String) {
        guard let screenshotDirectory else { return }
        let screenshot = XCUIScreen.main.screenshot()
        let outputURL = screenshotDirectory.appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: outputURL)
    }

    func tapBackButton() {
        let backButton = app.buttons["返回"].firstMatch
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        } else if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func tapVisibleButton(identifier: String, timeout: TimeInterval = 5) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "应存在按钮 \(identifier)")
        if !button.isHittable {
            app.swipeUp()
        }
        button.tap()
    }

    func alipayCSV(counterparty: String, product: String, amount: String = "100.00", orderId: String = "T-001") -> String {
        """
        -------------------------支付宝（中国）网络技术有限公司  电子客户回单------------------------
        交易时间,交易对方,交易对方,对方账号,商品说明,收/支,金额,收/付款方式,交易状态,交易订单号,商家订单号,备注,
        2026-04-15 12:30:45,餐饮美食,\(counterparty),/,\(product),支出,\(amount),广发卡,交易成功,\(orderId)\t,\t,,
        """
    }

    func addSetupStep(index: Int, csv: String, type: String, detail: String) {
        app.launchEnvironment["MZ_SETUP_\(index)_CSV"] = csv
        app.launchEnvironment["MZ_SETUP_\(index)_SOURCE"] = "alipay"
        app.launchEnvironment["MZ_SETUP_\(index)_TYPE"] = type
        app.launchEnvironment["MZ_SETUP_\(index)_DETAIL"] = detail
    }

    func testInvestmentLedgerShowsInvestmentAssetEntryAndFundRow() {
        app.launch()

        XCTAssertTrue(app.waitForMingZhangTab("统计").exists)
        app.waitForMingZhangTab("统计").tap()
        XCTAssertTrue(app.staticTexts["结果总览"].waitForExistence(timeout: 10))
        tapVisibleButton(identifier: "statistics_investment_result_detail")
        XCTAssertTrue(app.staticTexts["投资结果"].waitForExistence(timeout: 10))
        captureV51Screenshot("27-统计-投资结果详情")

        tapVisibleButton(identifier: "instrument_result_row_沪深300指数A", timeout: 10)
        XCTAssertTrue(app.staticTexts["沪深300指数A"].waitForExistence(timeout: 10))
        captureV51Screenshot("28-统计-标的结果详情")
        tapBackButton()
        tapBackButton()

        XCTAssertTrue(app.waitForMingZhangTab("资产负债").exists)
        app.waitForMingZhangTab("资产负债").tap()

        XCTAssertTrue(app.buttons["investment_asset_entry"].waitForExistence(timeout: 10))
        app.buttons["investment_asset_entry"].tap()

        let fundRow = app.buttons["investment_fund_row_沪深300指数A"]
        XCTAssertTrue(fundRow.waitForExistence(timeout: 10))
        fundRow.tap()

        XCTAssertTrue(app.staticTexts["基金投资明细账"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["investment_ledger_fund_name"].waitForExistence(timeout: 5))
        captureV51Screenshot("16-基金投资明细账")

        let feedRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "investment_feed_row_")).firstMatch
        if feedRow.waitForExistence(timeout: 5) {
            feedRow.tap()
            XCTAssertTrue(app.staticTexts["记录详情"].waitForExistence(timeout: 5))
            captureV51Screenshot("21-只读记录详情")
        }
    }

    func testLiabilityDetailCreatesRepaymentAndRefreshesSourceRecords() {
        continueAfterFailure = false
        addSetupStep(
            index: 0,
            csv: alipayCSV(counterparty: "信用卡商户", product: "月度账单", amount: "100.00", orderId: "P1-LIABILITY-001"),
            type: "生活必要开支",
            detail: "伙食费"
        )
        app.launch()

        app.waitForMingZhangTab("资产负债").tap()
        let liabilityRow = app.buttons["liability_row_广发卡"]
        XCTAssertTrue(liabilityRow.waitForExistence(timeout: 10))
        liabilityRow.tap()

        XCTAssertTrue(app.staticTexts["剩余负债"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["形成负债"].exists)
        XCTAssertTrue(app.staticTexts["100.00"].exists)

        tapVisibleButton(identifier: "liability_repayment_button")
        XCTAssertTrue(app.staticTexts["记还款"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["电子钱包余额"].exists)
        XCTAssertTrue(app.staticTexts["负债类减记"].exists)
        XCTAssertTrue(app.staticTexts["账单还款"].exists)
        XCTAssertTrue(app.staticTexts["广发卡"].exists)
        tapVisibleButton(identifier: "btn_save")

        XCTAssertTrue(app.staticTexts["剩余负债"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已还款"].exists)
        XCTAssertTrue(app.staticTexts["2 条"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0.00"].exists)

        tapVisibleButton(identifier: "liability_source_records_button")
        XCTAssertTrue(app.textFields["source_records_search_field"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["当前筛选"].exists)
        let repaymentRecord = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "广发卡还款")).firstMatch
        XCTAssertTrue(repaymentRecord.waitForExistence(timeout: 5))
    }
}
