import SwiftUI
import MingZhangCore
import UniformTypeIdentifiers
import UIKit

struct RootView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house")
                }

            JournalView()
                .tabItem {
                    Label("流水", systemImage: "list.bullet.rectangle")
                }

            BalanceView()
                .tabItem {
                    Label("资产负债", systemImage: "chart.pie")
                }

            StatisticsView()
                .tabItem {
                    Label("统计", systemImage: "chart.bar")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape")
                }
        }
        .alert("处理失败", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct MonthPickerView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("账月") {
                    ForEach(store.availableAccountMonths, id: \.self) { month in
                        Button {
                            if store.selectAccountMonth(month) {
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Text(month)
                                Spacer()
                                if month == store.accountMonth {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择账月")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingForm = false
    @State private var isShowingMonthPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("\(store.accountMonth) 摘要") {
                    SummaryRow(title: "收入", value: store.homeSummary.incomeTotal)
                    SummaryRow(title: "支出", value: store.homeSummary.expenseTotal)
                    SummaryRow(title: "结余", value: store.homeSummary.balance)
                }

                Section("最近账目") {
                    if store.records.isEmpty {
                        ContentUnavailableView("暂无流水", systemImage: "tray")
                    } else {
                        ForEach(store.records.suffix(5).reversed()) { record in
                            NavigationLink {
                                JournalFormView(mode: .edit(record))
                            } label: {
                                JournalRecordRow(record: record)
                            }
                        }
                    }
                }
            }
            .navigationTitle("明账")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        isShowingMonthPicker = true
                    } label: {
                        Label(store.accountMonth, systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("btn_month_picker")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingForm = true
                    } label: {
                        Label("记一笔", systemImage: "plus")
                    }
                    .accessibilityIdentifier("btn_new_record")
                }
            }
            .sheet(isPresented: $isShowingForm) {
                NavigationStack {
                    JournalFormView(mode: .create)
                }
            }
            .sheet(isPresented: $isShowingMonthPicker) {
                MonthPickerView()
            }
        }
    }
}

struct JournalView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingForm = false
    @State private var isShowingMonthPicker = false
    @State private var isShowingFilter = false
    @State private var isShowingImport = false

    var body: some View {
        NavigationStack {
            List {
                if store.journalFilter != JournalRecordFilter(accountMonths: [store.accountMonth]) {
                    Section("当前筛选") {
                        Button {
                            _ = store.clearJournalFilter()
                        } label: {
                            Label("清除筛选", systemImage: "xmark.circle")
                        }
                    }
                }

                if store.records.isEmpty {
                    ContentUnavailableView("当前账月暂无流水", systemImage: "tray")
                } else {
                    ForEach(store.records) { record in
                        NavigationLink {
                            JournalFormView(mode: .edit(record))
                        } label: {
                            JournalRecordRow(record: record)
                        }
                    }
                }
            }
            .navigationTitle("流水")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingFilter = true
                    } label: {
                        Label("筛选", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .principal) {
                    Button {
                        isShowingMonthPicker = true
                    } label: {
                        Label(store.accountMonth, systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        isShowingImport = true
                    } label: {
                        Label("导入账单", systemImage: "square.and.arrow.down")
                    }
                    NavigationLink {
                        JournalSearchView()
                    } label: {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingForm = true
                    } label: {
                        Label("记一笔", systemImage: "plus")
                    }
                    .accessibilityIdentifier("btn_new_record_journal")
                }
            }
            .sheet(isPresented: $isShowingForm) {
                NavigationStack {
                    JournalFormView(mode: .create)
                }
            }
            .sheet(isPresented: $isShowingMonthPicker) {
                MonthPickerView()
            }
            .sheet(isPresented: $isShowingFilter) {
                JournalFilterView()
            }
            .sheet(isPresented: $isShowingImport) {
                ImportSourcePickerView()
            }
        }
    }
}

struct JournalFilterInput: Equatable {
    var paymentMethodName = ""
    var paymentTypeName = ""
    var paymentDetailName = ""
    var amountMinText = ""
    var amountMaxText = ""
    var noteKeyword = ""

    func toFilter(accountMonth: String) throws -> JournalRecordFilter {
        JournalRecordFilter(
            accountMonths: [accountMonth],
            paymentMethodNames: paymentMethodName.isEmpty ? [] : [paymentMethodName],
            paymentTypeNames: paymentTypeName.isEmpty ? [] : [paymentTypeName],
            paymentDetailNames: paymentDetailName.isEmpty ? [] : [paymentDetailName],
            amountMin: try parseOptionalDecimal(amountMinText, fieldName: "最小金额"),
            amountMax: try parseOptionalDecimal(amountMaxText, fieldName: "最大金额"),
            noteKeyword: noteKeyword.isEmpty ? nil : noteKeyword
        )
    }

    private func parseOptionalDecimal(_ value: String, fieldName: String) throws -> Decimal? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let amount = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MingZhangError.validation("\(fieldName)必须是有效数字")
        }
        return amount
    }
}

struct JournalFilterView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = JournalFilterInput()

    var body: some View {
        NavigationStack {
            Form {
                Section("条件") {
                    Picker("收付手段", selection: $input.paymentMethodName) {
                        Text("全部").tag("")
                        ForEach(store.methods) { method in
                            Text(method.name).tag(method.name)
                        }
                    }
                    Picker("收付类型", selection: $input.paymentTypeName) {
                        Text("全部").tag("")
                        ForEach(store.types) { type in
                            Text(type.name).tag(type.name)
                        }
                    }
                    Picker("类型明细", selection: $input.paymentDetailName) {
                        Text("全部").tag("")
                        ForEach(filteredDetails) { detail in
                            Text(detail.name).tag(detail.name)
                        }
                    }
                    TextField("最小金额", text: $input.amountMinText)
                        .keyboardType(.decimalPad)
                    TextField("最大金额", text: $input.amountMaxText)
                        .keyboardType(.decimalPad)
                    TextField("备注关键词", text: $input.noteKeyword)
                }

                Section {
                    Button("重置") {
                        input = JournalFilterInput()
                        if store.clearJournalFilter() {
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("筛选")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        do {
                            if store.applyJournalFilter(try input.toFilter(accountMonth: store.accountMonth)) {
                                dismiss()
                            }
                        } catch {
                            store.lastError = error.localizedDescription
                        }
                    }
                }
            }
            .onChange(of: input.paymentTypeName) {
                if !filteredDetails.contains(where: { $0.name == input.paymentDetailName }) {
                    input.paymentDetailName = ""
                }
            }
        }
    }

    private var filteredDetails: [PaymentDetail] {
        guard let typeId = store.types.first(where: { $0.name == input.paymentTypeName })?.id else {
            return store.details
        }
        return store.details.filter { $0.paymentTypeId == typeId }
    }
}

struct JournalSearchView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var keyword = ""
    @State private var results: [JournalRecord] = []

    var body: some View {
        List {
            if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("输入关键词", systemImage: "magnifyingglass")
            } else if results.isEmpty {
                ContentUnavailableView("没有找到流水", systemImage: "tray")
            } else {
                ForEach(results) { record in
                    NavigationLink {
                        JournalFormView(mode: .edit(record))
                    } label: {
                        JournalRecordRow(record: record)
                    }
                }
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $keyword, prompt: "金额、账户、分类、备注")
        .onChange(of: keyword) {
            search()
        }
        .onAppear(perform: search)
    }

    private func search() {
        do {
            let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                results = []
                return
            }
            results = try store.queryRecords(
                filter: JournalRecordFilter(accountMonths: [store.accountMonth], searchKeyword: trimmed)
            )
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}

struct ImportSourcePickerView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("来源") {
                    NavigationLink {
                        ImportCandidateListView(source: .alipay)
                    } label: {
                        Label("支付宝账单", systemImage: "creditcard")
                    }
                    .accessibilityIdentifier("import-source-alipay")
                    NavigationLink {
                        ImportCandidateListView(source: .wechat)
                    } label: {
                        Label("微信账单", systemImage: "message")
                    }
                    .accessibilityIdentifier("import-source-wechat")
                }
            }
            .navigationTitle("导入账单")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ImportCandidateListView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let source: ImportSource
    @State private var isShowingFileImporter = false
    @State private var isShowingBatchEdit = false

    var body: some View {
        List {
            Section("批次") {
                LabeledContent("来源", value: source.displayName)
                LabeledContent("待确认", value: "\(pendingCandidates.count)")
                LabeledContent("已忽略", value: "\(ignoredCandidates.count)")
                if let batch = store.activeImportBatch {
                    LabeledContent("文件", value: batch.fileName ?? "未命名")
                }
            }

            if !store.importIssues.isEmpty {
                Section("问题") {
                    ForEach(Array(store.importIssues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(issue.code.displayName)
                            if let lineNumber = issue.lineNumber {
                                Text("第 \(lineNumber) 行")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(issue.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("候选") {
                if store.importCandidates.isEmpty {
                    ContentUnavailableView("暂无候选", systemImage: "tray")
                } else {
                    ForEach(store.importCandidates) { candidate in
                        HStack(spacing: 12) {
                            Button {
                                toggleSelection(candidate.id)
                            } label: {
                                Image(systemName: store.selectedImportCandidateIds.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(candidate.status == .pending ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(candidate.status != .pending)
                            .accessibilityIdentifier("import-candidate-checkbox-\(candidate.id.uuidString.prefix(8))")

                            NavigationLink {
                                ImportCandidateEditView(candidate: candidate)
                            } label: {
                                ImportCandidateRow(candidate: candidate)
                            }
                            .accessibilityIdentifier("import-candidate-nav-\(candidate.id.uuidString.prefix(8))")
                        }
                    }
                }
            }

            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                Section("测试工具") {
                    Button {
                        if let csv = UIPasteboard.general.string {
                            _ = store.createImportBatch(source: source, fileName: "uitest-import.csv", contents: csv)
                        }
                    } label: {
                        Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                    }
                    .accessibilityIdentifier("import-clipboard-btn")
                }
            }
        }
        .navigationTitle(source.displayName)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingFileImporter = true
                } label: {
                    Label("选择文件", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("import-file-picker-btn")
                Button {
                    isShowingBatchEdit = true
                } label: {
                    Label("批量整理", systemImage: "slider.horizontal.3")
                }
                .disabled(store.selectedImportCandidateIds.isEmpty)
                .accessibilityIdentifier("import-batch-edit-btn")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    selectAllPending()
                } label: {
                    Label("全选", systemImage: "checkmark.circle")
                }
                .disabled(pendingCandidates.isEmpty)
                .accessibilityIdentifier("import-select-all-btn")

                Button(role: .destructive) {
                    _ = store.ignoreSelectedImportCandidates()
                } label: {
                    Label("忽略", systemImage: "eye.slash")
                }
                .disabled(store.selectedImportCandidateIds.isEmpty)
                .accessibilityIdentifier("import-ignore-btn")

                Spacer()

                Button {
                    if store.confirmSelectedImportCandidates() {
                        dismiss()
                    }
                } label: {
                    Label("确认进入流水", systemImage: "checkmark")
                }
                .disabled(store.selectedImportCandidateIds.isEmpty)
                .accessibilityIdentifier("import-confirm-btn")
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: importContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $isShowingBatchEdit) {
            ImportBatchEditView(selectedIds: store.selectedImportCandidateIds)
        }
        .onAppear {
            if store.activeImportSource != source {
                store.prepareImport(source: source)
            }
        }
    }

    private var pendingCandidates: [ImportCandidateRecord] {
        store.importCandidates.filter { $0.status == .pending }
    }

    private var ignoredCandidates: [ImportCandidateRecord] {
        store.importCandidates.filter { $0.status == .ignored }
    }

    private var importContentTypes: [UTType] {
        [.plainText, .text, UTType(filenameExtension: "csv"), UTType(filenameExtension: "xlsx")].compactMap { $0 }
    }

    private func toggleSelection(_ id: UUID) {
        if store.selectedImportCandidateIds.contains(id) {
            store.selectedImportCandidateIds.remove(id)
        } else {
            store.selectedImportCandidateIds.insert(id)
        }
    }

    private func selectAllPending() {
        store.selectedImportCandidateIds = Set(pendingCandidates.map(\.id))
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            _ = store.createImportBatch(source: source, fileName: url.lastPathComponent, data: data)
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}

struct ImportCandidateRow: View {
    let candidate: ImportCandidateRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(candidate.accountMonth)
                    .font(.headline)
                Spacer()
                Text(candidate.amount.mingZhangAmountText)
                    .font(.headline)
            }
            Text(candidate.note ?? "无备注")
                .foregroundStyle(.primary)
            Text("\(candidate.paymentMethodName ?? "未设置") / \(candidate.paymentTypeName ?? "未设置") / \(candidate.paymentDetailName ?? "未设置")")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("import-candidate-classification-\(candidate.id.uuidString.prefix(8))")
            Text("\(candidate.status.displayName) / 原始第 \(candidate.rawLineNumber) 行")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct ImportCandidateEditView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let candidate: ImportCandidateRecord
    @State private var accountMonth: String
    @State private var amountText: String
    @State private var paymentMethodName: String
    @State private var paymentTypeName: String
    @State private var paymentDetailName: String
    @State private var note: String

    init(candidate: ImportCandidateRecord) {
        self.candidate = candidate
        _accountMonth = State(initialValue: candidate.accountMonth)
        _amountText = State(initialValue: NSDecimalNumber(decimal: candidate.amount).stringValue)
        _paymentMethodName = State(initialValue: candidate.paymentMethodName ?? "待补真实账户")
        _paymentTypeName = State(initialValue: candidate.paymentTypeName ?? "")
        _paymentDetailName = State(initialValue: candidate.paymentDetailName ?? "")
        _note = State(initialValue: candidate.note ?? "")
    }

    var body: some View {
        Form {
            Section("候选") {
                TextField("账月", text: $accountMonth)
                    .textInputAutocapitalization(.never)
                TextField("金额", text: $amountText)
                    .keyboardType(.numbersAndPunctuation)
                Picker("收付手段", selection: $paymentMethodName) {
                    ForEach(paymentMethodOptions, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Picker("收付类型", selection: $paymentTypeName) {
                    Text("未选择").tag("")
                    ForEach(store.types) { type in
                        Text(type.name).tag(type.name)
                    }
                }
                .accessibilityIdentifier("candidate-edit-type-picker")
                Picker("类型明细", selection: $paymentDetailName) {
                    Text("未选择").tag("")
                    ForEach(availableDetails) { detail in
                        Text(detail.name).tag(detail.name)
                    }
                }
                .accessibilityIdentifier("candidate-edit-detail-picker")
                TextField("备注", text: $note, axis: .vertical)
            }

            Section("原始") {
                LabeledContent("行号", value: "\(candidate.rawLineNumber)")
                if let transactionId = candidate.rawTransactionId {
                    LabeledContent("交易号", value: transactionId)
                }
            }
        }
        .navigationTitle("整理候选")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do {
                        if store.updateImportCandidate(id: candidate.id, changes: try makeChanges()) {
                            dismiss()
                        }
                    } catch {
                        store.lastError = error.localizedDescription
                    }
                }
                .disabled(candidate.status != .pending)
                .accessibilityIdentifier("candidate-edit-save-btn")
            }
        }
        .onChange(of: paymentTypeName) {
            if !availableDetails.contains(where: { $0.name == paymentDetailName }) {
                paymentDetailName = ""
            }
        }
    }

    private var paymentMethodOptions: [String] {
        var names = store.methods.map(\.name)
        if !paymentMethodName.isEmpty, !names.contains(paymentMethodName) {
            names.insert(paymentMethodName, at: 0)
        }
        return names
    }

    private var availableDetails: [PaymentDetail] {
        guard let typeId = store.types.first(where: { $0.name == paymentTypeName })?.id else {
            return []
        }
        return store.details.filter { $0.paymentTypeId == typeId }
    }

    private func makeChanges() throws -> ImportCandidateChanges {
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: trimmedAmount, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MingZhangError.validation("金额必须是有效数字")
        }
        return ImportCandidateChanges(
            accountMonth: accountMonth,
            amount: amount,
            paymentMethodName: paymentMethodName,
            paymentTypeName: paymentTypeName.isEmpty ? nil : paymentTypeName,
            paymentDetailName: paymentDetailName.isEmpty ? nil : paymentDetailName,
            note: note
        )
    }
}

struct ImportBatchEditView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let selectedIds: Set<UUID>
    @State private var accountMonth = ""
    @State private var paymentMethodName = ""
    @State private var paymentTypeName = ""
    @State private var paymentDetailName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("批量整理") {
                    TextField("账月", text: $accountMonth)
                        .textInputAutocapitalization(.never)
                    Picker("收付手段", selection: $paymentMethodName) {
                        Text("不修改").tag("")
                        ForEach(store.methods) { method in
                            Text(method.name).tag(method.name)
                        }
                    }
                    Picker("收付类型", selection: $paymentTypeName) {
                        Text("不修改").tag("")
                        ForEach(store.types) { type in
                            Text(type.name).tag(type.name)
                        }
                    }
                    Picker("类型明细", selection: $paymentDetailName) {
                        Text("不修改").tag("")
                        ForEach(availableDetails) { detail in
                            Text(detail.name).tag(detail.name)
                        }
                    }
                }
            }
            .navigationTitle("批量整理")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        if store.batchUpdateImportCandidates(ids: selectedIds, changes: changes) {
                            dismiss()
                        }
                    }
                }
            }
            .onChange(of: paymentTypeName) {
                if !availableDetails.contains(where: { $0.name == paymentDetailName }) {
                    paymentDetailName = ""
                }
            }
        }
    }

    private var availableDetails: [PaymentDetail] {
        guard let typeId = store.types.first(where: { $0.name == paymentTypeName })?.id else {
            return []
        }
        return store.details.filter { $0.paymentTypeId == typeId }
    }

    private var changes: ImportCandidateChanges {
        ImportCandidateChanges(
            accountMonth: accountMonth.isEmpty ? nil : accountMonth,
            paymentMethodName: paymentMethodName.isEmpty ? nil : paymentMethodName,
            paymentTypeName: paymentTypeName.isEmpty ? nil : paymentTypeName,
            paymentDetailName: paymentDetailName.isEmpty ? nil : paymentDetailName
        )
    }
}

struct JournalFormView: View {
    enum Mode: Equatable {
        case create
        case edit(JournalRecord)
    }

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var input: JournalFormInput
    @State private var isShowingDeleteConfirmation = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _input = State(initialValue: .p0Default())
        case .edit(let record):
            _input = State(initialValue: .from(record: record))
        }
    }

    var body: some View {
        Form {
            Section("账目") {
                TextField("账月", text: $input.accountMonth)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("field_account_month")
                DatePicker("时间", selection: $input.occurredAt)
                    .accessibilityIdentifier("picker_occurred_at")
                Picker("收付手段", selection: $input.paymentMethodName) {
                    ForEach(store.methods) { method in
                        Text(method.name).tag(method.name)
                    }
                }
                .accessibilityIdentifier("picker_payment_method")
                TextField("金额", text: $input.amountText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("field_amount")
                    Picker("收付类型", selection: $input.paymentTypeName) {
                        ForEach(store.types) { type in
                            Text(type.name).tag(type.name)
                        }
                    }
                    .accessibilityIdentifier("picker_payment_type")
                    Picker("类型明细", selection: $input.paymentDetailName) {
                        ForEach(availableDetails) { detail in
                            Text(detail.name).tag(detail.name)
                        }
                    }
                    .accessibilityIdentifier("picker_payment_detail")
                TextField("备注", text: $input.note, axis: .vertical)
                    .accessibilityIdentifier("field_note")
            }

            if case .edit(let record) = mode, record.recordSource == .import {
                ImportTraceSection(record: record)
            }

            if case .edit = mode, isEditableRecord {
                Section {
                    Button("删除记录", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .accessibilityIdentifier("btn_delete_record")
                }
            }
        }
        .navigationTitle(modeTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
                .accessibilityIdentifier("btn_cancel")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    if save() {
                        dismiss()
                    }
                }
                .disabled(!isEditableRecord)
                .accessibilityIdentifier("btn_save")
            }
        }
        .confirmationDialog("确认删除记录？", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) {
                if case .edit(let record) = mode, store.deleteRecord(id: record.id) {
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后会重新计算当前账月结果。")
        }
        .onAppear {
            normalizeDetailSelection()
        }
        .onChange(of: input.paymentTypeName) {
            normalizeDetailSelection()
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create:
            "记一笔"
        case .edit:
            "记录详情"
        }
    }

    private var isEditableRecord: Bool {
        switch mode {
        case .create:
            return true
        case .edit(let record):
            return record.recordSource == .manual || record.recordSource == .import
        }
    }

    private func save() -> Bool {
        switch mode {
        case .create:
            return store.createRecord(input: input)
        case .edit(let record):
            return store.updateRecord(id: record.id, input: input)
        }
    }

    private var availableDetails: [PaymentDetail] {
        guard let typeId = store.types.first(where: { $0.name == input.paymentTypeName })?.id else {
            return store.details
        }
        return store.details.filter { $0.paymentTypeId == typeId }
    }

    private func normalizeDetailSelection() {
        guard !availableDetails.contains(where: { $0.name == input.paymentDetailName }) else { return }
        input.paymentDetailName = availableDetails.first?.name ?? ""
    }
}

struct ImportTraceSection: View {
    @EnvironmentObject private var store: LedgerStore
    let record: JournalRecord
    @State private var trace: ImportTrace?

    var body: some View {
        Section("导入来源") {
            if let trace {
                LabeledContent("来源", value: trace.batch.source.displayName)
                LabeledContent("文件", value: trace.batch.fileName ?? "未命名")
                LabeledContent("原始行号", value: "\(trace.candidate.rawLineNumber)")
                if let transactionId = trace.candidate.rawTransactionId {
                    LabeledContent("交易号", value: transactionId)
                }
            } else {
                ContentUnavailableView("暂无来源", systemImage: "tray")
            }
        }
        .onAppear {
            trace = store.loadImportTrace(recordId: record.id)
        }
    }
}

struct BalanceView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingMonthPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("资产") {
                    if store.balanceSummary.cashSourceRecordIds.isEmpty {
                        SummaryRow(title: "现金类资产", value: store.balanceSummary.cashBalance)
                    } else {
                        NavigationLink {
                            AssetDetailView(
                                title: "现金类资产",
                                amount: store.balanceSummary.cashBalance,
                                sourceRecordIds: store.balanceSummary.cashSourceRecordIds
                            )
                        } label: {
                            SummaryRow(title: "现金类资产", value: store.balanceSummary.cashBalance)
                        }
                    }
                }

                Section("负债") {
                    if store.balanceSummary.liabilityItems.isEmpty {
                        ContentUnavailableView("暂无负债", systemImage: "creditcard")
                    } else {
                        ForEach(store.balanceSummary.liabilityItems, id: \.name) { item in
                            if item.sourceRecordIds.isEmpty {
                                BalanceItemRow(item: item)
                            } else {
                                NavigationLink {
                                    LiabilityDetailView(item: item)
                                } label: {
                                    BalanceItemRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("资产负债")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        isShowingMonthPicker = true
                    } label: {
                        Label(store.accountMonth, systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .sheet(isPresented: $isShowingMonthPicker) {
                MonthPickerView()
            }
        }
    }
}

struct AssetDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let amount: Decimal
    let sourceRecordIds: [UUID]

    var body: some View {
        List {
            Section("余额") {
                SummaryRow(title: title, value: amount)
            }

            Section("来源") {
                if sourceRecordIds.isEmpty {
                    ContentUnavailableView("暂无来源流水", systemImage: "tray")
                } else {
                    NavigationLink {
                        SourceRecordsView(
                            title: "\(title) 来源",
                            filterDescription: "\(store.accountMonth) / \(title)",
                            recordIds: sourceRecordIds
                        )
                    } label: {
                        Text("来源流水 \(sourceRecordIds.count) 条")
                    }
                }
            }
        }
        .navigationTitle(title)
    }
}

struct LiabilityDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let item: BalanceItem

    var body: some View {
        List {
            Section("余额") {
                SummaryRow(title: "剩余负债", value: item.amount)
            }

            Section("来源") {
                NavigationLink {
                    SourceRecordsView(
                        title: "\(item.name) 来源",
                        filterDescription: "\(store.accountMonth) / \(item.name)",
                        recordIds: item.sourceRecordIds
                    )
                } label: {
                    Text("来源流水 \(item.sourceRecordIds.count) 条")
                }
            }
        }
        .navigationTitle(item.name)
    }
}

struct BalanceItemRow: View {
    let item: BalanceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SummaryRow(title: item.name, value: item.amount)
            Text("来源流水 \(item.sourceRecordIds.count) 条")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SourceRecordsView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let filterDescription: String
    let recordIds: [UUID]
    @State private var records: [JournalRecord] = []
    @State private var selectedRecordId: UUID?

    var body: some View {
        List {
            Section("筛选") {
                Text(filterDescription)
                    .foregroundStyle(.secondary)
            }

            Section("来源记录") {
                if records.isEmpty {
                    ContentUnavailableView("暂无来源流水", systemImage: "tray")
                } else {
                    ForEach(records) { record in
                        Button {
                            selectedRecordId = record.id
                        } label: {
                            HStack(spacing: 12) {
                                JournalRecordRow(record: record)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(item: $selectedRecordId) { recordId in
            if let record = records.first(where: { $0.id == recordId }) {
                JournalFormView(mode: .edit(record))
            } else {
                ContentUnavailableView("找不到来源流水", systemImage: "tray")
            }
        }
        .onAppear(perform: loadRecords)
    }

    private func loadRecords() {
        do {
            records = try store.querySourceRecords(recordIds: recordIds)
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}

struct StatisticsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingMonthPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section("支出结构") {
                    if store.statisticsSummary.expenseByType.isEmpty {
                        ContentUnavailableView("暂无支出", systemImage: "chart.bar")
                    } else {
                        ForEach(store.statisticsSummary.expenseByType, id: \.typeName) { item in
                            if item.sourceRecordIds.isEmpty {
                                SummaryRow(title: item.typeName, value: item.amount)
                            } else {
                                NavigationLink {
                                    ExpenseCategoryDetailView(item: item)
                                } label: {
                                    SummaryRow(title: item.typeName, value: item.amount)
                                }
                            }
                        }
                    }
                }

                Section("来源") {
                    Text("来源流水 \(store.statisticsSummary.sourceRecordIds.count) 条")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("统计")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        isShowingMonthPicker = true
                    } label: {
                        Label(store.accountMonth, systemImage: "calendar")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            .sheet(isPresented: $isShowingMonthPicker) {
                MonthPickerView()
            }
        }
    }
}

struct ExpenseCategoryDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let item: ExpenseTypeSummary

    var body: some View {
        List {
            Section("金额") {
                SummaryRow(title: item.typeName, value: item.amount)
            }

            Section("来源") {
                NavigationLink {
                    SourceRecordsView(
                        title: "\(item.typeName) 来源",
                        filterDescription: "\(store.accountMonth) / \(item.typeName)",
                        recordIds: item.sourceRecordIds
                    )
                } label: {
                    Text("来源流水 \(item.sourceRecordIds.count) 条")
                }
            }
        }
        .navigationTitle(item.typeName)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        NavigationStack {
            List {
                Section("P0 默认配置") {
                    LabeledContent("收付手段", value: store.methods.map(\.name).joined(separator: " / "))
                    LabeledContent("收付类型", value: store.types.map(\.name).joined(separator: " / "))
                    LabeledContent("类型明细", value: store.details.map(\.name).joined(separator: " / "))
                }

                Section("边界") {
                    Text("支付宝/微信导入、基金投资、备份恢复将在 P1 接入。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }
}

struct JournalRecordRow: View {
    let record: JournalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.paymentMethodName)
                    .font(.headline)
                Spacer()
                Text(record.amount.mingZhangAmountText)
                    .font(.headline)
            }
            Text("\(record.paymentTypeName) / \(record.paymentDetailName)")
                .foregroundStyle(.secondary)
            Text(record.recordSource.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let note = record.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("journal_record_row_\(record.id.uuidString.prefix(8))")
    }
}

struct SummaryRow: View {
    let title: String
    let value: Decimal

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.mingZhangAmountText)
                .monospacedDigit()
        }
    }
}

private extension Decimal {
    var mingZhangAmountText: String {
        let number = NSDecimalNumber(decimal: self)
        return number.stringValue
    }
}

private extension RecordSource {
    var displayName: String {
        switch self {
        case .manual:
            return "手工"
        case .import:
            return "导入"
        case .investmentFeed:
            return "投资回填"
        case .engine:
            return "引擎"
        }
    }
}

private extension ImportCandidateStatus {
    var displayName: String {
        switch self {
        case .pending:
            return "待确认"
        case .ignored:
            return "已忽略"
        case .confirmed:
            return "已入账"
        }
    }
}

private extension ImportIssueCode {
    var displayName: String {
        switch self {
        case .invalidAmount:
            return "金额异常"
        case .invalidDate:
            return "时间异常"
        case .unknownFields:
            return "字段异常"
        case .duplicate:
            return "重复记录"
        case .unsupportedDirection:
            return "非收支交易"
        }
    }
}
