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

struct HomeView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingForm = false

    var body: some View {
        NavigationStack {
            List {
                Section("2026-04 摘要") {
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
        }
    }
}

struct JournalView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingForm = false

    var body: some View {
        NavigationStack {
            List {
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
        }
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
                    ForEach(store.details) { detail in
                        Text(detail.name).tag(detail.name)
                    }
                }
                TextField("备注", text: $input.note, axis: .vertical)
            }

            if case .edit(let record) = mode {
                Section {
                    Button("删除记录", role: .destructive) {
                        store.deleteRecord(id: record.id)
                        dismiss()
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
                    save()
                    dismiss()
                }
            }
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

    private func save() {
        switch mode {
        case .create:
            store.createRecord(input: input)
        case .edit(let record):
            store.updateRecord(id: record.id, input: input)
        }
    }
}

struct BalanceView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        NavigationStack {
            List {
                Section("资产") {
                    SummaryRow(title: "现金类资产", value: store.balanceSummary.cashBalance)
                }

                Section("负债") {
                    if store.balanceSummary.liabilityItems.isEmpty {
                        ContentUnavailableView("暂无负债", systemImage: "creditcard")
                    } else {
                        ForEach(store.balanceSummary.liabilityItems, id: \.name) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                SummaryRow(title: item.name, value: item.amount)
                                Text("来源流水 \(item.sourceRecordIds.count) 条")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("资产负债")
        }
    }
}

struct StatisticsView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        NavigationStack {
            List {
                Section("支出结构") {
                    if store.statisticsSummary.expenseByType.isEmpty {
                        ContentUnavailableView("暂无支出", systemImage: "chart.bar")
                    } else {
                        ForEach(store.statisticsSummary.expenseByType.keys.sorted(), id: \.self) { key in
                            SummaryRow(title: key, value: store.statisticsSummary.expenseByType[key] ?? 0)
                        }
                    }
                }

                Section("来源") {
                    Text("来源流水 \(store.statisticsSummary.sourceRecordIds.count) 条")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("统计")
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
