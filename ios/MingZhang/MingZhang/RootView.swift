import SwiftUI
import MingZhangCore

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
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingForm = true
                    } label: {
                        Label("记一笔", systemImage: "plus")
                    }
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingForm = true
                    } label: {
                        Label("记一笔", systemImage: "plus")
                    }
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
                    DatePicker("时间", selection: $input.occurredAt)
                Picker("收付手段", selection: $input.paymentMethodName) {
                    ForEach(store.methods) { method in
                        Text(method.name).tag(method.name)
                    }
                }
                TextField("金额", text: $input.amountText)
                    .keyboardType(.decimalPad)
                    Picker("收付类型", selection: $input.paymentTypeName) {
                        ForEach(store.types) { type in
                            Text(type.name).tag(type.name)
                        }
                    }
                    Picker("类型明细", selection: $input.paymentDetailName) {
                        ForEach(availableDetails) { detail in
                            Text(detail.name).tag(detail.name)
                        }
                    }
                    TextField("备注", text: $input.note, axis: .vertical)
                }

            if case .edit = mode {
                Section {
                    Button("删除记录", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle(modeTitle)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    if save() {
                        dismiss()
                    }
                }
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
                            SourceRecordsView(
                                title: "现金类资产来源",
                                filterDescription: "\(store.accountMonth) / 现金类资产",
                                recordIds: store.balanceSummary.cashSourceRecordIds
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
                                    SourceRecordsView(
                                        title: "\(item.name) 来源",
                                        filterDescription: "\(store.accountMonth) / \(item.name)",
                                        recordIds: item.sourceRecordIds
                                    )
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
                                    SourceRecordsView(
                                        title: "\(item.typeName) 来源",
                                        filterDescription: "\(store.accountMonth) / \(item.typeName)",
                                        recordIds: item.sourceRecordIds
                                    )
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
            if let note = record.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
