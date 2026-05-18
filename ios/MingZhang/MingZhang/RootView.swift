import SwiftUI
import Combine
import MingZhangCore
import UniformTypeIdentifiers
import UIKit

struct RootView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedTab: MZRootTab = .home
    @StateObject private var tabVisibility = MZRootTabVisibility()

    var body: some View {
        ZStack(alignment: .bottom) {
            selectedTabView
                .environmentObject(tabVisibility)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !tabVisibility.isHidden {
                MZRootTabBar(selectedTab: $selectedTab)
            }
        }
        .background(MZTheme.page.ignoresSafeArea())
        .alert("处理失败", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    @ViewBuilder
    private var selectedTabView: some View {
        switch selectedTab {
        case .home:
            HomeView()
        case .journal:
            JournalView()
        case .balance:
            BalanceView()
        case .statistics:
            StatisticsView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - 视觉系统

private final class MZRootTabVisibility: ObservableObject {
    @Published var isHidden = false
}

private enum MZRootTab: String, CaseIterable, Identifiable {
    case home
    case journal
    case balance
    case statistics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .journal: "流水"
        case .balance: "资产负债"
        case .statistics: "统计"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .journal: "list.bullet.rectangle"
        case .balance: "briefcase"
        case .statistics: "chart.bar"
        case .settings: "gearshape"
        }
    }
}

private enum MZTheme {
    static let accent = Color(red: 0.00, green: 0.62, blue: 0.57)
    static let accentDark = Color(red: 0.00, green: 0.45, blue: 0.42)
    static let ink = Color(red: 0.03, green: 0.09, blue: 0.18)
    static let secondaryInk = Color(red: 0.38, green: 0.45, blue: 0.56)
    static let tertiaryInk = Color(red: 0.58, green: 0.63, blue: 0.70)
    static let line = Color(red: 0.88, green: 0.90, blue: 0.93)
    static let page = Color(red: 0.985, green: 0.99, blue: 0.99)
    static let card = Color.white
    static let navy = Color(red: 0.06, green: 0.14, blue: 0.22)
    static let blue = Color(red: 0.18, green: 0.42, blue: 0.88)
    static let violet = Color(red: 0.53, green: 0.49, blue: 0.78)
    static let sage = Color(red: 0.55, green: 0.66, blue: 0.64)
    static let mist = Color(red: 0.82, green: 0.85, blue: 0.90)
    static let danger = Color(red: 0.86, green: 0.08, blue: 0.12)

    static let categoryColors: [Color] = [accent, blue, violet, sage, mist]
}

private struct MZRootTabBar: View {
    @Binding var selectedTab: MZRootTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MZRootTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                            .symbolVariant(selectedTab == tab ? .fill : .none)
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.caption2.weight(selectedTab == tab ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selectedTab == tab ? MZTheme.accent : MZTheme.tertiaryInk)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("tab_\(tab.title)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 7)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .background(MZTheme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MZTheme.line.opacity(0.85))
                .frame(height: 0.8)
        }
    }
}

private struct MZCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MZTheme.card)
                .shadow(color: .black.opacity(0.045), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MZTheme.line.opacity(0.8), lineWidth: 0.8)
        )
    }
}

private struct MZPage<Content: View>: View {
    var bottomInset: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, bottomInset)
        }
        .background(MZTheme.page.ignoresSafeArea())
        .scrollIndicators(.hidden)
    }
}

private struct MZTopBar: View {
    var title: String?
    var monthTitle: String?
    var showsCalendar: Bool = false
    var onMonthTap: (() -> Void)?

    var body: some View {
        if let title, monthTitle == nil {
            HStack {
                Spacer(minLength: 44)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                Spacer(minLength: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        } else {
            HStack(alignment: .center) {
                if let title {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                } else {
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 12)

                if let monthTitle {
                    Button {
                        onMonthTap?()
                    } label: {
                        HStack(spacing: 6) {
                            Text(monthTitle)
                                .font(.title2.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(MZTheme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("btn_month_picker")
                }

                Spacer(minLength: 12)

                if showsCalendar {
                    Button {
                        onMonthTap?()
                    } label: {
                        Image(systemName: "calendar")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(MZTheme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("账月范围")
                } else if title != nil {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }
}

private struct MZBackHeader: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabVisibility: MZRootTabVisibility
    let title: String
    var trailingSystemImage: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MZTheme.accent)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .accessibilityLabel("返回")

            Spacer()
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(MZTheme.ink)
            Spacer()

            if let trailingSystemImage {
                Button {
                    trailingAction?()
                } label: {
                    Image(systemName: trailingSystemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MZTheme.ink)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(MZTheme.page)
        .onAppear {
            tabVisibility.isHidden = true
        }
        .onDisappear {
            tabVisibility.isHidden = false
        }
    }
}

private struct MZMetricTriplet: View {
    let items: [(String, Decimal)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 8) {
                    Text(item.0)
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                    Text(item.1.moneyText)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(MZTheme.line)
                        .frame(width: 1, height: 42)
                }
            }
        }
    }
}

private struct CategoryDisplayItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let amount: Decimal
    let color: Color
    let sourceRecordIds: [UUID]

    static func == (lhs: CategoryDisplayItem, rhs: CategoryDisplayItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct MZStructureCard: View {
    let title: String
    let total: Decimal
    let items: [CategoryDisplayItem]
    var onItemTap: ((CategoryDisplayItem) -> Void)?

    var body: some View {
        MZCard {
            HStack {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                Spacer()
                Text(total.moneyText)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(MZTheme.ink)
            }

            MZStackedBar(items: items, total: total)

            if items.isEmpty {
                MZEmptyState(title: "暂无\(title)", systemImage: "chart.pie")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 12) {
                    ForEach(items) { item in
                        Button {
                            onItemTap?(item)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 10, height: 10)
                                Text(item.name)
                                    .foregroundStyle(MZTheme.ink)
                                Spacer()
                                Text(item.amount.moneyText)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(MZTheme.ink)
                                Text(item.percentText(of: total))
                                    .frame(width: 58, alignment: .trailing)
                                    .foregroundStyle(MZTheme.secondaryInk)
                            }
                            .font(.body)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct MZStackedBar: View {
    let items: [CategoryDisplayItem]
    let total: Decimal

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if total.doubleValue == 0 || items.isEmpty {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MZTheme.mist)
                        .frame(width: proxy.size.width)
                } else {
                    ForEach(items) { item in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(item.color)
                            .frame(width: max(4, proxy.size.width * item.percentCGFloat(of: total)))
                    }
                    if items.reduce(0.0, { $0 + $1.percentCGFloat(of: total) }) < 0.985 {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(MZTheme.mist)
                    }
                }
            }
        }
        .frame(height: 14)
    }
}

private struct MZRecordRow: View {
    let record: JournalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.occurredAt.recordListText)
                    .font(.body)
                    .foregroundStyle(MZTheme.ink)
                Spacer()
                Text(record.paymentMethodName)
                    .foregroundStyle(MZTheme.secondaryInk)
                Text(record.amount.moneyText)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(MZTheme.ink)
                    .frame(minWidth: 86, alignment: .trailing)
            }

            if record.recordKind == .carryForward {
                Label("固定", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(MZTheme.secondaryInk)
            }

            Text("\(record.paymentTypeName) / \(record.paymentDetailName)\(record.noteTextSuffix)")
                .font(.subheadline)
                .foregroundStyle(MZTheme.secondaryInk)
                .lineLimit(2)
        }
        .padding(.vertical, 14)
        .accessibilityIdentifier("journal_record_row_\(record.id.uuidString.prefix(8))")
    }
}

private struct MZDivider: View {
    var body: some View {
        Rectangle()
            .fill(MZTheme.line)
            .frame(height: 1)
    }
}

private struct MZPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fontWeight(.bold)
            }
            .font(.body)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDisabled ? MZTheme.tertiaryInk : MZTheme.navy)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct MZLightButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .fontWeight(.semibold)
            }
            .font(.body)
            .foregroundStyle(MZTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(MZTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(MZTheme.line, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MZIconRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = MZTheme.accent
    var trailing: String?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(MZTheme.secondaryInk)
        }
        .contentShape(Rectangle())
    }
}

private struct MZEmptyState: View {
    let title: String
    var systemImage: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(MZTheme.tertiaryInk)
            Text(title)
                .font(.headline)
                .foregroundStyle(MZTheme.secondaryInk)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(MZTheme.tertiaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 20)
    }
}

private struct MZFieldRow<Content: View>: View {
    let title: String
    var required = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MZTheme.ink)
                if required {
                    Text("*")
                        .foregroundStyle(MZTheme.danger)
                }
            }
            .frame(width: 104, alignment: .leading)

            Spacer(minLength: 8)

            content
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 56)
    }
}

private struct MZMenuRow: View {
    let title: String
    var required = false
    @Binding var selection: String
    let options: [String]

    var body: some View {
        MZFieldRow(title: title, required: required) {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option.isEmpty ? "未选择" : option) {
                        selection = option
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection.isEmpty ? "未选择" : selection)
                        .foregroundStyle(selection.isEmpty ? MZTheme.tertiaryInk : MZTheme.ink)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(MZTheme.accent)
                }
            }
        }
    }
}

private struct MZPlaceholderPage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: title)
            MZPage {
                MZCard {
                    MZEmptyState(title: title, systemImage: "doc.text", subtitle: message)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(MZTheme.page)
    }
}

// MARK: - 全局账月

struct MonthPickerView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "账月范围")
            MZPage {
                MZCard {
                    Text("快捷范围")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)

                    MonthOptionRow(title: "当前账月", value: store.accountMonth.displayMonth, isSelected: true) {
                        dismiss()
                    }

                    disabledOption("全部", detail: "后续支持全部历史范围")
                    disabledOption("YTD", detail: "后续支持年初至今")
                    disabledOption("自定义范围", detail: "后续支持起止账月")
                }

                MZCard {
                    Text("账月列表")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)

                    ForEach(store.availableAccountMonths, id: \.self) { month in
                        MonthOptionRow(
                            title: month.displayMonth,
                            value: month,
                            isSelected: month == store.accountMonth
                        ) {
                            if store.selectAccountMonth(month) {
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .background(MZTheme.page.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private func disabledOption(_ title: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MZTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(MZTheme.tertiaryInk)
            }
            Spacer()
            Text("暂未接入")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MZTheme.tertiaryInk)
        }
        .padding(.vertical, 8)
    }
}

private struct MonthOptionRow: View {
    let title: String
    let value: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MZTheme.ink)
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MZTheme.accent)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 首页

struct HomeView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingForm = false
    @State private var isShowingMonthPicker = false
    @State private var isShowingQuickMenu = false
    @State private var isShowingImport = false
    @State private var isShowingSearch = false
    @State private var selectedCategory: CategoryDisplayItem?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                MZPage(bottomInset: 156) {
                    MZTopBar(
                        monthTitle: store.accountMonth.displayMonth,
                        showsCalendar: true,
                        onMonthTap: { isShowingMonthPicker = true }
                    )

                    MZCard {
                        Text("收支摘要")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                        MZMetricTriplet(items: [
                            ("收入", store.homeSummary.incomeTotal),
                            ("支出", store.homeSummary.expenseTotal),
                            ("结余", store.homeSummary.balance)
                        ])
                    }

                    MZStructureCard(
                        title: "收入结构",
                        total: store.homeSummary.incomeTotal,
                        items: categoryItems(for: .income),
                        onItemTap: { selectedCategory = $0 }
                    )

                    MZStructureCard(
                        title: "支出结构",
                        total: store.homeSummary.expenseTotal,
                        items: categoryItems(for: .expense),
                        onItemTap: { selectedCategory = $0 }
                    )

                    recentRecordsCard
                }

                if isShowingQuickMenu {
                    VStack(alignment: .trailing, spacing: 10) {
                        QuickMenuButton(title: "记一笔", systemImage: "pencil") {
                            isShowingQuickMenu = false
                            isShowingForm = true
                        }
                        QuickMenuButton(title: "导入账单", systemImage: "tray.and.arrow.down") {
                            isShowingQuickMenu = false
                            isShowingImport = true
                        }
                        QuickMenuButton(title: "查找", systemImage: "magnifyingglass") {
                            isShowingQuickMenu = false
                            isShowingSearch = true
                        }
                        Button {
                            isShowingQuickMenu = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MZTheme.secondaryInk)
                                .frame(width: 54, height: 54)
                                .background(Circle().fill(MZTheme.card))
                        }
                        .accessibilityIdentifier("btn_home_quick_close")
                    }
                    .padding(.trailing, 18)
                    .padding(.bottom, 92)
                    .accessibilityElement(children: .contain)
                } else {
                    Button {
                        isShowingQuickMenu = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.largeTitle.weight(.regular))
                            .foregroundStyle(MZTheme.accent)
                            .frame(width: 62, height: 62)
                            .background(Circle().fill(MZTheme.card))
                            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                    }
                    .accessibilityIdentifier("btn_home_quick_add")
                    .padding(.trailing, 18)
                    .padding(.bottom, 92)
                }
            }
            .navigationDestination(item: $selectedCategory) { category in
                CategoryDetailView(category: category, total: categoryTotal(for: category))
            }
            .sheet(isPresented: $isShowingForm) {
                NavigationStack { JournalFormView(mode: .create) }
            }
            .sheet(isPresented: $isShowingMonthPicker) {
                MonthPickerView()
            }
            .sheet(isPresented: $isShowingImport) {
                ImportSourcePickerView()
            }
            .navigationDestination(isPresented: $isShowingSearch) {
                JournalSearchView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var recentRecordsCard: some View {
        MZCard {
            HStack {
                Text("最近账目")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                Spacer()
                NavigationLink {
                    JournalView()
                } label: {
                    HStack(spacing: 4) {
                        Text("全部")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MZTheme.secondaryInk)
                }
            }

            let records = Array(store.records.suffix(4).reversed())
            if records.isEmpty {
                MZEmptyState(title: "暂无账目", systemImage: "tray", subtitle: "可以从右下角记一笔开始")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        NavigationLink {
                            destination(for: record)
                        } label: {
                            HStack(spacing: 14) {
                                Text(record.occurredAt.recentDayText)
                                    .font(.subheadline)
                                    .foregroundStyle(MZTheme.secondaryInk)
                                    .frame(width: 70, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.note?.isEmpty == false ? record.note! : record.paymentDetailName)
                                        .font(.headline.weight(.semibold))
                                        .foregroundStyle(MZTheme.ink)
                                    Text("\(record.paymentTypeName) · \(record.paymentDetailName)")
                                        .font(.subheadline)
                                        .foregroundStyle(MZTheme.secondaryInk)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(record.amount.moneyText)
                                    .font(.headline.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(MZTheme.ink)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if index < records.count - 1 {
                            MZDivider()
                        }
                    }
                }
            }
        }
    }

    private func categoryItems(for element: AccountingElement) -> [CategoryDisplayItem] {
        let typeNames = Set(store.types.filter { $0.element == element }.map(\.name))
        let grouped = Dictionary(grouping: store.records.filter { typeNames.contains($0.paymentTypeName) }, by: \.paymentTypeName)
        return grouped.keys.sorted().enumerated().map { index, name in
            let records = grouped[name] ?? []
            return CategoryDisplayItem(
                name: name,
                amount: records.reduce(Decimal.zero) { $0 + $1.amount.absoluteValue },
                color: MZTheme.categoryColors[index % MZTheme.categoryColors.count],
                sourceRecordIds: records.map(\.id)
            )
        }
    }

    private func categoryTotal(for category: CategoryDisplayItem) -> Decimal {
        let incomeNames = Set(store.types.filter { $0.element == .income }.map(\.name))
        return incomeNames.contains(category.name) ? store.homeSummary.incomeTotal : store.homeSummary.expenseTotal
    }

    @ViewBuilder
    private func destination(for record: JournalRecord) -> some View {
        if record.isDirectlyEditable {
            JournalFormView(mode: .edit(record))
        } else {
            ReadOnlyRecordDetailView(record: record)
        }
    }
}

private struct QuickMenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
            }
            .foregroundStyle(MZTheme.ink)
            .padding(.horizontal, 18)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MZTheme.card)
                    .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CategoryDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let category: CategoryDisplayItem
    let total: Decimal

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: category.name)
            MZPage {
                MZCard {
                    Text(category.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    Text(category.amount.moneyText)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                    Text("占比 \(category.percentText(of: total))")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard {
                    Text("最近账目")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    NavigationLink {
                        SourceRecordsView(
                            title: "\(category.name) 来源",
                            filterDescription: "\(store.accountMonth.displayMonth) / \(category.name)",
                            recordIds: category.sourceRecordIds
                        )
                    } label: {
                        HStack {
                            Text("查看来源")
                            Spacer()
                            Text("\(category.sourceRecordIds.count) 条")
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(MZTheme.accent)
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - 流水

struct JournalView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingForm = false
    @State private var isShowingMonthPicker = false
    @State private var isShowingFilter = false
    @State private var isShowingImport = false
    @State private var isShowingSearch = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                MZPage(bottomInset: 188) {
                    MZTopBar(
                        monthTitle: store.accountMonth.displayMonth,
                        showsCalendar: true,
                        onMonthTap: { isShowingMonthPicker = true }
                    )

                    HStack(spacing: 10) {
                        MZLightButton(title: "导入账单", systemImage: "tray.and.arrow.down") {
                            isShowingImport = true
                        }
                        .accessibilityIdentifier("btn_journal_import_bill")

                        MZLightButton(title: "新增记录", systemImage: "plus") {
                            isShowingForm = true
                        }
                        .accessibilityIdentifier("btn_new_record_journal")
                    }

                    if store.journalFilter != JournalRecordFilter(accountMonths: [store.accountMonth]) {
                        MZCard {
                            HStack(spacing: 8) {
                                Label("当前筛选", systemImage: "line.3.horizontal.decrease.circle")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(MZTheme.ink)
                                Spacer()
                                Button("清除筛选") {
                                    _ = store.clearJournalFilter()
                                }
                                .foregroundStyle(MZTheme.accent)
                            }
                        }
                    }

                    recordsCard
                }

                bottomActionBar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 84)
            }
            .sheet(isPresented: $isShowingForm) {
                NavigationStack { JournalFormView(mode: .create) }
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
            .navigationDestination(isPresented: $isShowingSearch) {
                JournalSearchView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var recordsCard: some View {
        MZCard(padding: 0) {
            VStack(spacing: 0) {
                if store.records.isEmpty {
                    MZEmptyState(title: "当前账月暂无流水", systemImage: "tray", subtitle: "点击底部按钮记一笔或导入账单")
                        .frame(maxWidth: .infinity)
                        .padding(20)
                } else {
                    ForEach(Array(store.records.enumerated()), id: \.element.id) { index, record in
                        NavigationLink {
                            if record.isDirectlyEditable {
                                JournalFormView(mode: .edit(record))
                            } else {
                                ReadOnlyRecordDetailView(record: record)
                            }
                        } label: {
                            MZRecordRow(record: record)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        if index < store.records.count - 1 {
                            MZDivider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            Text("共 \(store.records.count) 条记录")
                .font(.subheadline)
                .foregroundStyle(MZTheme.secondaryInk)
                .offset(y: 42)
        }
        .padding(.bottom, 52)
    }

    private var bottomActionBar: some View {
        HStack(spacing: 14) {
            Button {
                isShowingSearch = true
            } label: {
                Label("搜索", systemImage: "magnifyingglass")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(MZTheme.accent)
                    .frame(width: 86, height: 52)
            }

            Button {
                isShowingForm = true
            } label: {
                Label("点击这里记一笔", systemImage: "pencil")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Capsule().fill(MZTheme.accent))
            }
            .accessibilityIdentifier("btn_new_record")

            Button {
                isShowingFilter = true
            } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(MZTheme.accent)
                    .frame(width: 86, height: 52)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MZTheme.card)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
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
        VStack(spacing: 0) {
            MZBackHeader(title: "筛选")
            MZPage {
                MZCard {
                    MZMenuRow(title: "收付手段", selection: $input.paymentMethodName, options: [""] + store.methods.map(\.name))
                    MZDivider()
                    MZMenuRow(title: "收付类型", selection: $input.paymentTypeName, options: [""] + store.types.map(\.name))
                    MZDivider()
                    MZMenuRow(title: "类型明细", selection: $input.paymentDetailName, options: [""] + filteredDetails.map(\.name))
                    MZDivider()
                    MZFieldRow(title: "最小金额") {
                        TextField("最低金额", text: $input.amountMinText)
                            .keyboardType(.decimalPad)
                    }
                    MZDivider()
                    MZFieldRow(title: "最大金额") {
                        TextField("最高金额", text: $input.amountMaxText)
                            .keyboardType(.decimalPad)
                    }
                    MZDivider()
                    MZFieldRow(title: "备注关键词") {
                        TextField("输入关键词", text: $input.noteKeyword)
                    }
                }

                HStack(spacing: 12) {
                    MZLightButton(title: "重置", systemImage: "arrow.counterclockwise") {
                        input = JournalFilterInput()
                        if store.clearJournalFilter() {
                            dismiss()
                        }
                    }
                    MZPrimaryButton(title: "应用筛选") {
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
        }
        .onChange(of: input.paymentTypeName) {
            if !filteredDetails.contains(where: { $0.name == input.paymentDetailName }) {
                input.paymentDetailName = ""
            }
        }
        .background(MZTheme.page)
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
        VStack(spacing: 0) {
            MZBackHeader(title: "搜索")
            MZPage {
                MZCard {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(MZTheme.secondaryInk)
                        TextField("搜索金额、账户、类型、备注", text: $keyword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MZTheme.page)
                    )

                    Text("\(store.accountMonth.displayMonth) · 当前账月")
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard(padding: 0) {
                    if keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MZEmptyState(title: "输入关键词", systemImage: "magnifyingglass")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else if results.isEmpty {
                        MZEmptyState(title: "没有找到流水", systemImage: "tray")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, record in
                                NavigationLink {
                                    if record.isDirectlyEditable {
                                        JournalFormView(mode: .edit(record))
                                    } else {
                                        ReadOnlyRecordDetailView(record: record)
                                    }
                                } label: {
                                    MZRecordRow(record: record)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                if index < results.count - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(MZTheme.page)
        .onChange(of: keyword) { search() }
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MZBackHeader(title: "账单导入")
                MZPage {
                    MZCard {
                        Text("选择账单来源")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MZTheme.ink)

                        NavigationLink {
                            ImportCandidateListView(source: .alipay)
                        } label: {
                            MZIconRow(title: "支付宝账单", subtitle: "整理支付宝导出的交易明细", systemImage: "creditcard")
                        }
                        .accessibilityIdentifier("import-source-alipay")

                        MZDivider()

                        NavigationLink {
                            ImportCandidateListView(source: .wechat)
                        } label: {
                            MZIconRow(title: "微信账单", subtitle: "整理微信支付账单明细", systemImage: "message")
                        }
                        .accessibilityIdentifier("import-source-wechat")
                    }

                    MZLightButton(title: "关闭", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .background(MZTheme.page)
            .navigationBarBackButtonHidden(true)
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
        VStack(spacing: 0) {
            MZBackHeader(title: "\(source.displayName)账单整理", trailingSystemImage: "questionmark.circle")
            MZPage(bottomInset: 24) {
                HStack(spacing: 12) {
                    statusPill(title: "待确认 \(pendingCandidates.count) 条", isSelected: true)
                    statusPill(title: "已忽略 \(ignoredCandidates.count) 条", isSelected: false)
                }

                if !store.importIssues.isEmpty {
                    MZCard {
                        Text("导入问题")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                        ForEach(Array(store.importIssues.enumerated()), id: \.offset) { _, issue in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.code.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MZTheme.ink)
                                Text(issue.lineNumber.map { "第 \($0) 行 · \(issue.message)" } ?? issue.message)
                                    .font(.caption)
                                    .foregroundStyle(MZTheme.secondaryInk)
                            }
                        }
                    }
                }

                candidateCard

                HStack(spacing: 12) {
                    MZLightButton(title: "选择文件", systemImage: "doc.badge.plus") {
                        isShowingFileImporter = true
                    }
                    .accessibilityIdentifier("import-file-picker-btn")

                    MZLightButton(title: "批量修改", systemImage: "slider.horizontal.3") {
                        isShowingBatchEdit = true
                    }
                    .disabled(store.selectedImportCandidateIds.isEmpty)
                    .accessibilityIdentifier("import-batch-edit-btn")
                }

                if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                    MZLightButton(title: "从剪贴板导入", systemImage: "doc.on.clipboard") {
                        if let csv = UIPasteboard.general.string {
                            _ = store.createImportBatch(source: source, fileName: "uitest-import.csv", contents: csv)
                        }
                    }
                    .accessibilityIdentifier("import-clipboard-btn")
                }

                MZCard {
                    HStack {
                        Button("全选") {
                            selectAllPending()
                        }
                        .foregroundStyle(MZTheme.accent)
                        .disabled(pendingCandidates.isEmpty)
                        .accessibilityIdentifier("import-select-all-btn")

                        Spacer()

                        Text("已选 \(store.selectedImportCandidateIds.count) 条")
                            .foregroundStyle(MZTheme.ink)

                        Spacer()

                        Button("忽略", role: .destructive) {
                            _ = store.ignoreSelectedImportCandidates()
                        }
                        .disabled(store.selectedImportCandidateIds.isEmpty)
                        .accessibilityIdentifier("import-ignore-btn")
                    }
                }

                MZPrimaryButton(title: "确认进入流水", isDisabled: store.selectedImportCandidateIds.isEmpty) {
                    if store.confirmSelectedImportCandidates() {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("import-confirm-btn")

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("导入后作为流水记录，不单独调整余额")
                }
                .font(.footnote)
                .foregroundStyle(MZTheme.secondaryInk)
                .frame(maxWidth: .infinity)
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
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

    private var candidateCard: some View {
        MZCard(padding: 0) {
            if store.importCandidates.isEmpty {
                MZEmptyState(title: "暂无候选", systemImage: "tray", subtitle: "选择文件或测试导入后会显示候选记录")
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.importCandidates.enumerated()), id: \.element.id) { index, candidate in
                        HStack(spacing: 14) {
                            Button {
                                toggleSelection(candidate.id)
                            } label: {
                                Image(systemName: store.selectedImportCandidateIds.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundStyle(candidate.status == .pending ? MZTheme.accent : MZTheme.tertiaryInk)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .disabled(candidate.status != .pending)
                            .accessibilityIdentifier("import-candidate-checkbox-\(candidate.id.uuidString.prefix(8))")

                            NavigationLink {
                                ImportCandidateEditView(candidate: candidate)
                            } label: {
                                ImportCandidateRow(candidate: candidate)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("import-candidate-nav-\(candidate.id.uuidString.prefix(8))")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        if index < store.importCandidates.count - 1 {
                            MZDivider().padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private func statusPill(title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : MZTheme.secondaryInk)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(isSelected ? MZTheme.accent : MZTheme.page))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(candidate.note ?? "候选记录")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                    .lineLimit(1)
                Spacer()
                Text(candidate.amount.moneyText)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(MZTheme.ink)
            }

            Text("\(candidate.paymentMethodName ?? "未设置") / \(candidate.paymentTypeName ?? "未设置") / \(candidate.paymentDetailName ?? "未设置")")
                .font(.subheadline)
                .foregroundStyle(MZTheme.secondaryInk)
                .accessibilityIdentifier("import-candidate-classification-\(candidate.id.uuidString.prefix(8))")

            Text("\(candidate.accountMonth.displayMonth) · \(candidate.status.displayName) · 原始第 \(candidate.rawLineNumber) 行")
                .font(.caption)
                .foregroundStyle(MZTheme.tertiaryInk)
        }
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
        VStack(spacing: 0) {
            MZBackHeader(title: "整理候选")
            MZPage {
                MZCard {
                    MZFieldRow(title: "账月", required: true) {
                        TextField("账月", text: $accountMonth)
                            .textInputAutocapitalization(.never)
                    }
                    MZDivider()
                    MZFieldRow(title: "金额", required: true) {
                        TextField("金额", text: $amountText)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    MZDivider()
                    MZMenuRow(title: "收付手段", required: true, selection: $paymentMethodName, options: paymentMethodOptions)
                    MZDivider()
                    MZMenuRow(title: "收付类型", required: true, selection: $paymentTypeName, options: [""] + store.types.map(\.name))
                        .accessibilityIdentifier("candidate-edit-type-picker")
                    MZDivider()
                    MZMenuRow(title: "类型明细", required: true, selection: $paymentDetailName, options: [""] + availableDetails.map(\.name))
                        .accessibilityIdentifier("candidate-edit-detail-picker")
                    MZDivider()
                    MZFieldRow(title: "备注") {
                        TextField("备注", text: $note, axis: .vertical)
                    }
                }

                MZCard {
                    Text("原始信息")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    SummaryLine(title: "行号", value: "\(candidate.rawLineNumber)")
                    if let transactionId = candidate.rawTransactionId {
                        SummaryLine(title: "交易号", value: transactionId)
                    }
                }

                MZPrimaryButton(title: "保存", isDisabled: candidate.status != .pending) {
                    do {
                        if store.updateImportCandidate(id: candidate.id, changes: try makeChanges()) {
                            dismiss()
                        }
                    } catch {
                        store.lastError = error.localizedDescription
                    }
                }
                .accessibilityIdentifier("candidate-edit-save-btn")
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(MZTheme.page)
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
            VStack(spacing: 0) {
                MZBackHeader(title: "批量修改")
                MZPage {
                    MZCard {
                        MZFieldRow(title: "账月") {
                            TextField("不修改", text: $accountMonth)
                                .textInputAutocapitalization(.never)
                        }
                        MZDivider()
                        MZMenuRow(title: "收付手段", selection: $paymentMethodName, options: [""] + store.methods.map(\.name))
                        MZDivider()
                        MZMenuRow(title: "收付类型", selection: $paymentTypeName, options: [""] + store.types.map(\.name))
                        MZDivider()
                        MZMenuRow(title: "类型明细", selection: $paymentDetailName, options: [""] + availableDetails.map(\.name))
                    }

                    MZPrimaryButton(title: "应用修改") {
                        if store.batchUpdateImportCandidates(ids: selectedIds, changes: changes) {
                            dismiss()
                        }
                    }
                }
            }
            .navigationBarBackButtonHidden(true)
            .background(MZTheme.page)
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
        VStack(spacing: 0) {
            MZBackHeader(title: modeTitle)
            MZPage {
                MZCard {
                    MZFieldRow(title: "账月", required: true) {
                        TextField("账月", text: $input.accountMonth)
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(MZTheme.accent)
                            .accessibilityIdentifier("field_account_month")
                    }
                    MZDivider()
                    MZFieldRow(title: "时间", required: true) {
                        DatePicker("", selection: $input.occurredAt, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .accessibilityIdentifier("picker_occurred_at")
                    }
                    MZDivider()
                    MZMenuRow(title: "收付手段", required: true, selection: $input.paymentMethodName, options: store.methods.map(\.name))
                        .accessibilityIdentifier("picker_payment_method")
                    MZDivider()
                    MZFieldRow(title: "金额", required: true) {
                        TextField("金额", text: $input.amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("field_amount")
                    }
                    MZDivider()
                    MZMenuRow(title: "收付类型", required: true, selection: $input.paymentTypeName, options: store.types.map(\.name))
                        .accessibilityIdentifier("picker_payment_type")
                    MZDivider()
                    MZMenuRow(title: "类型明细", required: true, selection: $input.paymentDetailName, options: availableDetails.map(\.name))
                        .accessibilityIdentifier("picker_payment_detail")
                }

                MZCard {
                    Text("备注")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(MZTheme.ink)
                    TextField("备注", text: $input.note, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("field_note")
                    HStack {
                        Spacer()
                        Text("\(input.note.count)/100")
                            .font(.caption)
                            .foregroundStyle(MZTheme.tertiaryInk)
                    }
                }

                if case .edit(let record) = mode, record.recordSource == .import {
                    ImportTraceSection(record: record)
                }

                MZCard {
                    SummaryLine(title: "来源", value: sourceText)
                    MZDivider()
                    SummaryLine(title: "性质", value: kindText)
                    MZDivider()
                    SummaryLine(title: "编辑边界", value: isEditableRecord ? "可直接编辑和删除" : "应回到来源修改")
                }

                MZPrimaryButton(title: "保存记录", isDisabled: !isEditableRecord) {
                    if save() {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("btn_save")

                if case .edit = mode, isEditableRecord {
                    Button("删除记录", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .accessibilityIdentifier("btn_delete_record")
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(MZTheme.page)
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

    private var sourceText: String {
        switch mode {
        case .create:
            "手工记录"
        case .edit(let record):
            record.recordSource.longDisplayName
        }
    }

    private var kindText: String {
        switch mode {
        case .create:
            "普通记录"
        case .edit(let record):
            record.recordKind == .carryForward ? "固定 / 继承记录" : "普通记录"
        }
    }

    private var isEditableRecord: Bool {
        switch mode {
        case .create:
            true
        case .edit(let record):
            record.isDirectlyEditable
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
        guard !availableDetails.isEmpty else { return }
        guard !availableDetails.contains(where: { $0.name == input.paymentDetailName }) else { return }
        input.paymentDetailName = availableDetails.first?.name ?? ""
    }
}

struct ImportTraceSection: View {
    @EnvironmentObject private var store: LedgerStore
    let record: JournalRecord
    @State private var trace: ImportTrace?

    var body: some View {
        MZCard {
            Text("导入来源")
                .font(.headline.weight(.bold))
                .foregroundStyle(MZTheme.ink)
            if let trace {
                SummaryLine(title: "来源", value: trace.batch.source.displayName)
                MZDivider()
                SummaryLine(title: "文件", value: trace.batch.fileName ?? "未命名")
                MZDivider()
                SummaryLine(title: "原始行号", value: "\(trace.candidate.rawLineNumber)")
                if let transactionId = trace.candidate.rawTransactionId {
                    MZDivider()
                    SummaryLine(title: "交易号", value: transactionId)
                }
            } else {
                MZEmptyState(title: "暂无来源", systemImage: "tray")
            }
        }
        .onAppear {
            trace = store.loadImportTrace(recordId: record.id)
        }
    }
}

struct ReadOnlyRecordDetailView: View {
    let record: JournalRecord

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "记录详情")
            MZPage {
                MZCard {
                    SummaryLine(title: "账月", value: record.accountMonth.displayMonth)
                    MZDivider()
                    SummaryLine(title: "时间", value: record.occurredAt.fullText)
                    MZDivider()
                    SummaryLine(title: "收付手段", value: record.paymentMethodName)
                    MZDivider()
                    SummaryLine(title: "金额", value: record.amount.moneyText)
                    MZDivider()
                    SummaryLine(title: "收付类型", value: record.paymentTypeName)
                    MZDivider()
                    SummaryLine(title: "类型明细", value: record.paymentDetailName)
                }

                MZCard {
                    Text("备注")
                        .font(.headline.weight(.semibold))
                    Text(record.note ?? "无备注")
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard {
                    SummaryLine(title: "来源", value: record.recordSource.longDisplayName)
                    MZDivider()
                    SummaryLine(title: "性质", value: record.recordKind == .carryForward ? "固定 / 继承记录" : "普通记录")
                    MZDivider()
                    SummaryLine(title: "编辑边界", value: "请回到来源记录、规则或投资明细修改")
                }

                MZPrimaryButton(title: "查看来源", isDisabled: true) {}
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(MZTheme.page)
    }
}

// MARK: - 资产负债

struct BalanceView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingMonthPicker = false

    var body: some View {
        NavigationStack {
            MZPage(bottomInset: 112) {
                MZTopBar(
                    monthTitle: store.accountMonth.displayMonth,
                    onMonthTap: { isShowingMonthPicker = true }
                )

                MZCard {
                    MZMetricTriplet(items: [
                        ("资产合计", assetTotal),
                        ("负债合计", liabilityTotal),
                        ("净资产", assetTotal - liabilityTotal)
                    ])
                    Text("资产合计按成本口径，不含未实现盈亏")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                MZCard {
                    sectionHeader(title: "资产（成本口径）", amount: store.balanceSummary.cashBalance)
                    NavigationLink {
                        AssetDetailView(
                            title: "现金类资产",
                            amount: store.balanceSummary.cashBalance,
                            sourceRecordIds: store.balanceSummary.cashSourceRecordIds
                        )
                    } label: {
                        listAmountRow(title: "现金", amount: store.balanceSummary.cashBalance)
                    }
                    MZDivider()
                    listAmountRow(title: "电子钱包余额", amount: store.balanceSummary.cashBalance, showChevron: false)
                    MZDivider()
                    listAmountRow(title: "长期待摊费用", amount: 0, showChevron: false)
                }

                MZCard {
                    sectionHeader(title: "负债（剩余负债）", amount: liabilityTotal)
                    if store.balanceSummary.liabilityItems.isEmpty {
                        MZEmptyState(title: "暂无负债", systemImage: "creditcard")
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(store.balanceSummary.liabilityItems.enumerated()), id: \.element.name) { index, item in
                            NavigationLink {
                                LiabilityDetailView(item: item)
                            } label: {
                                listAmountRow(title: item.name, amount: item.amount)
                            }
                            .buttonStyle(.plain)
                            if index < store.balanceSummary.liabilityItems.count - 1 {
                                MZDivider()
                            }
                        }
                    }
                }

                MZCard {
                    sectionHeader(title: "投资（成本口径）", amount: investmentBookValue)
                    NavigationLink {
                        InvestmentFundListView()
                    } label: {
                        listAmountRow(title: "基金投资成本", amount: investmentBookValue)
                    }
                    .accessibilityIdentifier("investment_asset_entry")
                    MZDivider()
                    listAmountRow(title: "PV（市值）", amount: investmentPresentValue, showChevron: false)
                    MZDivider()
                    listAmountRow(title: "未实现盈亏", amount: investmentUnrealizedGain, showChevron: false)
                }
            }
            .sheet(isPresented: $isShowingMonthPicker) {
                MonthPickerView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var assetTotal: Decimal {
        store.balanceSummary.cashBalance + investmentBookValue
    }

    private var liabilityTotal: Decimal {
        store.balanceSummary.liabilityItems.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var investmentBookValue: Decimal {
        store.balanceSummary.investmentItems.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var investmentPresentValue: Decimal {
        store.investmentHoldings.reduce(Decimal.zero) { $0 + ($1.presentValue ?? $1.bookValue) }
    }

    private var investmentUnrealizedGain: Decimal {
        store.investmentHoldings.reduce(Decimal.zero) { $0 + ($1.unrealizedGain ?? 0) }
    }

    private func sectionHeader(title: String, amount: Decimal) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(MZTheme.ink)
            Spacer()
            Text(amount.moneyText)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(MZTheme.accent)
            Image(systemName: "chevron.right")
                .foregroundStyle(MZTheme.accent)
        }
    }

    private func listAmountRow(title: String, amount: Decimal, showChevron: Bool = true) -> some View {
        HStack {
            Text(title)
                .font(.body)
                .foregroundStyle(MZTheme.ink)
            Spacer()
            Text(amount.moneyText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MZTheme.ink)
            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(MZTheme.secondaryInk)
            }
        }
        .frame(minHeight: 46)
        .contentShape(Rectangle())
    }
}

struct AssetDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let amount: Decimal
    let sourceRecordIds: [UUID]

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: title)
            MZPage {
                MZCard {
                    Text(amount.moneyText)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                    Text("当前余额")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard {
                    SummaryLine(title: "本范围增加", value: "0.00")
                    MZDivider()
                    SummaryLine(title: "本范围减少", value: "0.00")
                }

                MZCard {
                    NavigationLink {
                        SourceRecordsView(
                            title: "\(title) 来源",
                            filterDescription: "\(store.accountMonth.displayMonth) / \(title)",
                            recordIds: sourceRecordIds
                        )
                    } label: {
                        MZIconRow(title: "相关流水", subtitle: "查看构成当前余额的来源记录", systemImage: "list.bullet.rectangle", trailing: "\(sourceRecordIds.count) 条")
                    }
                    MZDivider()
                    NavigationLink {
                        AdjustBalanceView(title: title, currentAmount: amount)
                    } label: {
                        MZIconRow(title: "调整余额", subtitle: "通过生成流水调整记录修正余额", systemImage: "pencil.line")
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct AdjustBalanceView: View {
    let title: String
    let currentAmount: Decimal
    @State private var targetAmountText = ""
    @State private var note = "资产余额调整"

    private var difference: Decimal {
        guard let target = Decimal(string: targetAmountText, locale: Locale(identifier: "en_US_POSIX")) else {
            return 0
        }
        return target - currentAmount
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "调整余额")
            MZPage {
                MZCard {
                    SummaryLine(title: "账户", value: title)
                    MZDivider()
                    SummaryLine(title: "当前余额", value: currentAmount.moneyText)
                    MZDivider()
                    MZFieldRow(title: "目标余额") {
                        TextField("输入目标余额", text: $targetAmountText)
                            .keyboardType(.decimalPad)
                    }
                    MZDivider()
                    SummaryLine(title: "差额", value: difference.moneyText)
                    MZDivider()
                    MZFieldRow(title: "备注") {
                        TextField("备注", text: $note)
                    }
                }

                MZPrimaryButton(title: "生成调整记录", isDisabled: true) {}

                MZCard {
                    Text("当前仅完成 v5.1 调整余额页面结构。真实调整需要接入资产调整 Use Case 后启用。")
                        .font(.footnote)
                        .foregroundStyle(MZTheme.secondaryInk)
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct LiabilityDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let item: BalanceItem

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: item.name)
            MZPage {
                MZCard {
                    Text(item.amount.moneyText)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                    Text("剩余负债")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard {
                    SummaryLine(title: "本月新增", value: item.amount.moneyText)
                    MZDivider()
                    SummaryLine(title: "已还款", value: "0.00")
                    MZDivider()
                    SummaryLine(title: "利息成本", value: "0.00")
                }

                MZCard {
                    NavigationLink {
                        SourceRecordsView(
                            title: "\(item.name) 来源",
                            filterDescription: "\(store.accountMonth.displayMonth) / \(item.name)",
                            recordIds: item.sourceRecordIds
                        )
                    } label: {
                        MZIconRow(title: "相关流水", subtitle: "查看负债形成与变化来源", systemImage: "list.bullet.rectangle", trailing: "\(item.sourceRecordIds.count) 条")
                    }
                    MZDivider()
                    MZIconRow(title: "记还款", subtitle: "生成负债类减记流水，后续接入", systemImage: "checkmark.circle", tint: MZTheme.tertiaryInk)
                    MZDivider()
                    MZIconRow(title: "补利息", subtitle: "生成财务费用开支流水，后续接入", systemImage: "plus.circle", tint: MZTheme.tertiaryInk)
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct InvestmentFundListView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "基金投资")
            MZPage {
                MZCard(padding: 0) {
                    if store.investmentHoldings.isEmpty {
                        MZEmptyState(title: "暂无基金标的", systemImage: "briefcase")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.investmentHoldings.enumerated()), id: \.element.id) { index, holding in
                                NavigationLink {
                                    InvestmentLedgerView(fundName: holding.fundName)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(holding.fundName)
                                                .font(.body.weight(.semibold))
                                                .foregroundStyle(MZTheme.ink)
                                            Text("份额 \(holding.holdingShare.moneyText)")
                                                .font(.caption)
                                                .foregroundStyle(MZTheme.secondaryInk)
                                        }
                                        Spacer()
                                        Text(holding.bookValue.moneyText)
                                            .font(.body.weight(.semibold))
                                            .monospacedDigit()
                                            .foregroundStyle(MZTheme.ink)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(MZTheme.secondaryInk)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 56)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("investment_fund_row_\(holding.fundName)")
                                if index < store.investmentHoldings.count - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct InvestmentLedgerView: View {
    @EnvironmentObject private var store: LedgerStore
    let fundName: String
    @State private var transactions: [InvestmentTransaction] = []
    @State private var summary: InvestmentMonthlySummary?
    @State private var feedRecords: [JournalRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: fundName)
            MZPage {
                MZCard {
                    MZMetricTriplet(items: [
                        ("成本", holding?.bookValue ?? 0),
                        ("份额", holding?.holdingShare ?? 0),
                        ("PV", holding?.presentValue ?? holding?.bookValue ?? 0)
                    ])
                    Text(fundName)
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .accessibilityIdentifier("investment_ledger_fund_name")
                }

                if let summary {
                    MZCard {
                        Text("\(store.accountMonth.displayMonth) 结果")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                        SummaryLine(title: "买入入账", value: summary.buyBookAmount.moneyText)
                        MZDivider()
                        SummaryLine(title: "卖出入账", value: summary.sellBookAmount.moneyText)
                        MZDivider()
                        SummaryLine(title: "已实现收益", value: summary.realizedGain.moneyText)
                        MZDivider()
                        SummaryLine(title: "已实现亏损", value: summary.realizedLoss.moneyText)
                    }
                }

                InvestmentFeedRecordsSection(records: feedRecords)

                MZCard(padding: 0) {
                    if transactions.isEmpty {
                        MZEmptyState(title: "暂无交易", systemImage: "tray")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                                InvestmentTransactionRow(transaction: transaction)
                                    .padding(.horizontal, 16)
                                if index < transactions.count - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }

                MZPrimaryButton(title: "新增交易", isDisabled: true) {}
                .accessibilityIdentifier("investment_add_transaction_button")
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: loadData)
        .onChange(of: store.investmentHoldings.map(\.id)) {
            loadData()
        }
        .onChange(of: store.records.map(\.id)) {
            loadData()
        }
    }

    private var holding: InvestmentHolding? {
        store.investmentHoldings.first { $0.fundName == fundName }
    }

    private func loadData() {
        transactions = store.loadInvestmentTransactions(fundName: fundName)
        summary = store.loadInvestmentMonthlySummary(fundName: fundName)
        feedRecords = store.loadInvestmentFeedRecords(fundName: fundName)
    }
}

struct InvestmentFeedRecordsSection: View {
    let records: [JournalRecord]

    var body: some View {
        MZCard(padding: 0) {
            if records.isEmpty {
                MZEmptyState(title: "暂无回填流水", systemImage: "tray")
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                        NavigationLink {
                            if record.isDirectlyEditable {
                                JournalFormView(mode: .edit(record))
                            } else {
                                ReadOnlyRecordDetailView(record: record)
                            }
                        } label: {
                            MZRecordRow(record: record)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("investment_feed_row_\(record.paymentDetailName)")
                        if index < records.count - 1 {
                            MZDivider().padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
}

struct InvestmentTransactionRow: View {
    let transaction: InvestmentTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.transactionType.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(MZTheme.ink)
                Text("\(transaction.accountMonth) / 份额 \((transaction.tradeShare ?? transaction.holdingShare).moneyText)")
                    .font(.caption)
                    .foregroundStyle(MZTheme.secondaryInk)
            }
            Spacer()
            Text((transaction.tradeAmount ?? transaction.nav ?? 0).moneyText)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MZTheme.ink)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

struct SourceRecordsView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let filterDescription: String
    let recordIds: [UUID]
    @State private var records: [JournalRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: title)
            MZPage {
                MZCard {
                    Text("来源筛选")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    Text(filterDescription)
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                    Button("清除筛选") {}
                        .foregroundStyle(MZTheme.accent)
                        .disabled(true)
                }

                MZCard(padding: 0) {
                    if records.isEmpty {
                        MZEmptyState(title: "暂无来源流水", systemImage: "tray")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                NavigationLink {
                                    if record.isDirectlyEditable {
                                        JournalFormView(mode: .edit(record))
                                    } else {
                                        ReadOnlyRecordDetailView(record: record)
                                    }
                                } label: {
                                    MZRecordRow(record: record)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                if index < records.count - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
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

// MARK: - 统计

struct StatisticsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingMonthPicker = false

    var body: some View {
        NavigationStack {
            MZPage(bottomInset: 112) {
                MZTopBar(
                    title: "统计",
                    monthTitle: store.accountMonth.displayMonth,
                    onMonthTap: { isShowingMonthPicker = true }
                )

                MZCard {
                    Text("结果总览")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    MZMetricTriplet(items: [
                        ("收入", store.homeSummary.incomeTotal),
                        ("支出", store.homeSummary.expenseTotal),
                        ("结余", store.homeSummary.balance)
                    ])
                    Text("收入 - 支出 = 结余")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                MZStructureCard(
                    title: "收支结构",
                    total: store.homeSummary.expenseTotal,
                    items: expenseItems,
                    onItemTap: { _ in }
                )

                MZCard {
                    HStack {
                        Text("资产负债变化")
                            .font(.title3.weight(.bold))
                        Spacer()
                        NavigationLink {
                            BalanceChangeDetailView()
                        } label: {
                            HStack(spacing: 4) {
                                Text("查看详情")
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(MZTheme.accent)
                        }
                    }
                    SummaryLine(title: "资产增加", value: store.balanceSummary.cashBalance.moneyText)
                    MZDivider()
                    SummaryLine(title: "负债减少", value: "0.00")
                    MZDivider()
                    SummaryLine(title: "递延资产释放", value: "0.00")
                    MZDivider()
                    SummaryLine(title: "投资成本变化", value: store.investmentMonthlySummary.endingBookValue.moneyText)
                }

                MZCard {
                    HStack {
                        Text("投资结果")
                            .font(.title3.weight(.bold))
                        Spacer()
                        NavigationLink {
                            InvestmentResultDetailView()
                        } label: {
                            HStack(spacing: 4) {
                                Text("查看详情")
                                Image(systemName: "chevron.right")
                            }
                            .foregroundStyle(MZTheme.accent)
                        }
                    }
                    SummaryLine(title: "已实现收益", value: store.investmentMonthlySummary.realizedGain.moneyText)
                    MZDivider()
                    SummaryLine(title: "已实现亏损", value: store.investmentMonthlySummary.realizedLoss.moneyText)
                    MZDivider()
                    SummaryLine(title: "未实现盈亏", value: investmentUnrealizedGain.moneyText)
                }
            }
            .sheet(isPresented: $isShowingMonthPicker) {
                MonthPickerView()
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var expenseItems: [CategoryDisplayItem] {
        store.statisticsSummary.expenseByType.enumerated().map { index, item in
            CategoryDisplayItem(
                name: item.typeName,
                amount: item.amount.absoluteValue,
                color: MZTheme.categoryColors[index % MZTheme.categoryColors.count],
                sourceRecordIds: item.sourceRecordIds
            )
        }
    }

    private var investmentUnrealizedGain: Decimal {
        store.investmentHoldings.reduce(Decimal.zero) { $0 + ($1.unrealizedGain ?? 0) }
    }
}

struct ExpenseCategoryDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let item: ExpenseTypeSummary

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: item.typeName)
            MZPage {
                MZCard {
                    Text(item.amount.moneyText)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text("当前范围金额")
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard {
                    NavigationLink {
                        SourceRecordsView(
                            title: "\(item.typeName) 来源",
                            filterDescription: "\(store.accountMonth.displayMonth) / \(item.typeName)",
                            recordIds: item.sourceRecordIds
                        )
                    } label: {
                        MZIconRow(title: "查看来源", subtitle: "回到流水解释分类结果", systemImage: "list.bullet.rectangle", trailing: "\(item.sourceRecordIds.count) 条")
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct BalanceChangeDetailView: View {
    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "资产负债变化")
            MZPage {
                MZCard {
                    SummaryLine(title: "资产增加", value: "0.00")
                    MZDivider()
                    SummaryLine(title: "资产减少", value: "0.00")
                    MZDivider()
                    SummaryLine(title: "负债增加", value: "0.00")
                    MZDivider()
                    SummaryLine(title: "负债减少", value: "0.00")
                }
                MZCard {
                    MZEmptyState(title: "来源按流水回溯", systemImage: "list.bullet.rectangle", subtitle: "有真实来源记录时，从这里回到来源流水筛选态")
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct InvestmentResultDetailView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "投资结果")
            MZPage {
                MZCard {
                    MZMetricTriplet(items: [
                        ("已实现收益", store.investmentMonthlySummary.realizedGain),
                        ("已实现亏损", store.investmentMonthlySummary.realizedLoss),
                        ("未实现盈亏", investmentUnrealizedGain)
                    ])
                }

                MZCard(padding: 0) {
                    if store.investmentHoldings.isEmpty {
                        MZEmptyState(title: "暂无投资结果", systemImage: "chart.line.uptrend.xyaxis")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.investmentHoldings.enumerated()), id: \.element.id) { index, holding in
                                NavigationLink {
                                    InstrumentResultDetailView(fundName: holding.fundName)
                                } label: {
                                    MZIconRow(
                                        title: holding.fundName,
                                        subtitle: "查看标的收益和明细账",
                                        systemImage: "chart.line.uptrend.xyaxis",
                                        trailing: holding.bookValue.moneyText
                                    )
                                    .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                if index < store.investmentHoldings.count - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }

    private var investmentUnrealizedGain: Decimal {
        store.investmentHoldings.reduce(Decimal.zero) { $0 + ($1.unrealizedGain ?? 0) }
    }
}

struct InstrumentResultDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let fundName: String
    @State private var summary: InvestmentMonthlySummary?

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: fundName)
            MZPage {
                if let summary {
                    MZCard {
                        SummaryLine(title: "卖出入账", value: summary.sellBookAmount.moneyText)
                        MZDivider()
                        SummaryLine(title: "已实现收益", value: summary.realizedGain.moneyText)
                        MZDivider()
                        SummaryLine(title: "已实现亏损", value: summary.realizedLoss.moneyText)
                        MZDivider()
                        SummaryLine(title: "期末账面价值", value: summary.endingBookValue.moneyText)
                    }
                }

                MZCard {
                    NavigationLink {
                        InvestmentLedgerView(fundName: fundName)
                    } label: {
                        MZIconRow(title: "查看投资明细账", subtitle: "交易、成本、回填流水", systemImage: "list.bullet.rectangle")
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            summary = store.loadInvestmentMonthlySummary(fundName: fundName)
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        NavigationStack {
            MZPage(bottomInset: 112) {
                MZTopBar(title: "设置")

                Text("记账配置")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(MZTheme.secondaryInk)

                MZCard {
                    NavigationLink {
                        PaymentMethodsSettingsView()
                    } label: {
                        MZIconRow(title: "收付手段", subtitle: "管理资产型、负债型和账务处理型", systemImage: "wallet.pass")
                    }
                    MZDivider()
                    NavigationLink {
                        PaymentTypesSettingsView()
                    } label: {
                        MZIconRow(title: "收付类型与明细", subtitle: "维护收付类型和类型明细", systemImage: "list.bullet.rectangle")
                    }
                }

                Text("数据管理")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(MZTheme.secondaryInk)

                MZCard {
                    NavigationLink {
                        DataManagementPlaceholderView(title: "数据导出", message: "导出明账数据文件，后续接入备份格式后启用。")
                    } label: {
                        MZIconRow(title: "数据导出", subtitle: "导出明账数据文件", systemImage: "square.and.arrow.up")
                    }
                    MZDivider()
                    NavigationLink {
                        DataManagementPlaceholderView(title: "数据导入", message: "仅用于新明账自己的数据文件，不用于支付宝/微信账单。")
                    } label: {
                        MZIconRow(title: "数据导入", subtitle: "导入明账数据文件", systemImage: "square.and.arrow.down")
                    }
                    MZDivider()
                    NavigationLink {
                        DataClearConfirmView()
                    } label: {
                        MZIconRow(title: "数据清空", subtitle: "清空全部数据（慎用）", systemImage: "trash", tint: MZTheme.danger)
                    }
                }

                Text("App 设置")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(MZTheme.secondaryInk)

                MZCard {
                    NavigationLink {
                        DataManagementPlaceholderView(title: "外观", message: "主题和字体大小等设置后续接入。")
                    } label: {
                        MZIconRow(title: "外观", subtitle: "主题、字体大小等", systemImage: "tshirt")
                    }
                    MZDivider()
                    NavigationLink {
                        DataManagementPlaceholderView(title: "隐私", message: "隐私与数据权限设置后续接入。")
                    } label: {
                        MZIconRow(title: "隐私", subtitle: "隐私与数据权限", systemImage: "shield")
                    }
                    MZDivider()
                    NavigationLink {
                        DataManagementPlaceholderView(title: "安全", message: "应用锁、备份等安全设置后续接入。")
                    } label: {
                        MZIconRow(title: "安全", subtitle: "应用锁、备份等", systemImage: "lock")
                    }
                    MZDivider()
                    NavigationLink {
                        DataManagementPlaceholderView(title: "关于", message: "版本与帮助信息后续接入。")
                    } label: {
                        MZIconRow(title: "关于", subtitle: "版本与帮助", systemImage: "info.circle")
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct PaymentMethodsSettingsView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "收付手段管理", trailingSystemImage: "plus")
            MZPage {
                ForEach(PaymentMethodType.visibleOrder, id: \.self) { type in
                    MZCard {
                        Text(type.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                        let methods = store.methods.filter { $0.methodType == type }
                        if methods.isEmpty {
                            MZEmptyState(title: "暂无\(type.displayName)", systemImage: "wallet.pass")
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(methods.enumerated()), id: \.element.id) { index, method in
                                HStack {
                                    Text(method.name)
                                        .foregroundStyle(MZTheme.ink)
                                    Spacer()
                                    Text(method.isActive ? "启用" : "停用")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(method.isActive ? MZTheme.accent : MZTheme.tertiaryInk)
                                }
                                .frame(minHeight: 44)
                                if index < methods.count - 1 {
                                    MZDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct PaymentTypesSettingsView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "收付类型与明细", trailingSystemImage: "plus")
            MZPage {
                ForEach(AccountingElement.visibleOrder, id: \.self) { element in
                    MZCard {
                        Text(element.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                        let types = store.types.filter { $0.element == element }
                        if types.isEmpty {
                            MZEmptyState(title: "暂无\(element.displayName)类型", systemImage: "list.bullet")
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(types.enumerated()), id: \.element.id) { typeIndex, type in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(type.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(MZTheme.ink)
                                    let details = store.details.filter { $0.paymentTypeId == type.id }
                                    ForEach(details) { detail in
                                        NavigationLink {
                                            TypeDetailEditView(type: type, detail: detail)
                                        } label: {
                                            HStack {
                                                Text(detail.name)
                                                    .foregroundStyle(MZTheme.secondaryInk)
                                                Spacer()
                                                Text(detail.isActive ? "启用" : "停用")
                                                    .font(.caption)
                                                    .foregroundStyle(detail.isActive ? MZTheme.accent : MZTheme.tertiaryInk)
                                                Image(systemName: "chevron.right")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(MZTheme.tertiaryInk)
                                            }
                                            .padding(.leading, 12)
                                            .frame(minHeight: 34)
                                        }
                                    }
                                }
                                if typeIndex < types.count - 1 {
                                    MZDivider()
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct TypeDetailEditView: View {
    let type: PaymentType
    let detail: PaymentDetail

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "类型明细编辑")
            MZPage {
                MZCard {
                    SummaryLine(title: "名称", value: detail.name)
                    MZDivider()
                    SummaryLine(title: "所属收付类型", value: type.name)
                    MZDivider()
                    SummaryLine(title: "层级", value: "类型明细")
                    MZDivider()
                    SummaryLine(title: "状态", value: detail.isActive ? "启用" : "停用")
                }

                MZCard {
                    Text("语义描述")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    Text("用于帮助理解分类边界；第一版不作为自动规则中心。")
                        .font(.body)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZPrimaryButton(title: "保存类型明细", isDisabled: true) {}
                MZLightButton(title: "停用此类型明细", systemImage: "pause.circle") {}
                    .disabled(true)
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct DataManagementPlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        MZPlaceholderPage(title: title, message: message)
    }
}

struct DataClearConfirmView: View {
    @State private var confirmText = ""

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "数据清空确认")
            MZPage {
                MZCard {
                    Text("清空全部数据")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.danger)
                    Text("此操作会清空本机账本数据。本轮只重画确认页面壳，不接真实清空命令。")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                    MZFieldRow(title: "确认文字") {
                        TextField("输入 清空全部数据", text: $confirmText)
                    }
                }

                MZLightButton(title: "先导出数据", systemImage: "square.and.arrow.up") {}
                    .disabled(true)

                MZPrimaryButton(title: "确认清空", isDisabled: true) {}
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - 通用行

private struct SummaryLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(MZTheme.secondaryInk)
            Spacer(minLength: 16)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(MZTheme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.body)
        .frame(minHeight: 36)
    }
}

// MARK: - 扩展

private extension Decimal {
    var moneyText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? NSDecimalNumber(decimal: self).stringValue
    }

    var absoluteValue: Decimal {
        let number = NSDecimalNumber(decimal: self)
        if number.compare(NSDecimalNumber(value: 0)) == .orderedAscending {
            return number.multiplying(by: NSDecimalNumber(value: -1)).decimalValue
        }
        return self
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

private extension CategoryDisplayItem {
    func percentCGFloat(of total: Decimal) -> CGFloat {
        guard total.doubleValue != 0 else { return 0 }
        return CGFloat(max(0, amount.doubleValue / total.doubleValue))
    }

    func percentText(of total: Decimal) -> String {
        guard total.doubleValue != 0 else { return "0.0%" }
        return String(format: "%.1f%%", amount.doubleValue / total.doubleValue * 100)
    }
}

private extension Date {
    var recordListText: String {
        Self.recordListFormatter.string(from: self)
    }

    var recentDayText: String {
        let calendar = Calendar.current
        let time = Self.timeFormatter.string(from: self)
        if calendar.isDateInToday(self) {
            return "今天 \(time)"
        }
        if calendar.isDateInYesterday(self) {
            return "昨天 \(time)"
        }
        return Self.monthDayTimeFormatter.string(from: self)
    }

    var fullText: String {
        Self.fullFormatter.string(from: self)
    }

    private static let recordListFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let monthDayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static let fullFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension String {
    var displayMonth: String {
        let parts = split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]) else { return self }
        return "\(parts[0])年\(month)月"
    }
}

private extension JournalRecord {
    var isDirectlyEditable: Bool {
        recordSource == .manual || recordSource == .import
    }

    var noteTextSuffix: String {
        guard let note, !note.isEmpty else { return "" }
        return " / \(note)"
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

    var longDisplayName: String {
        switch self {
        case .manual:
            return "手工记录"
        case .import:
            return "导入记录"
        case .investmentFeed:
            return "投资回填"
        case .engine:
            return "引擎生成"
        }
    }
}

private extension InvestmentTransactionType {
    var displayName: String {
        switch self {
        case .buy:
            return "买入"
        case .sell:
            return "卖出"
        case .nav:
            return "净值"
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

private extension PaymentMethodType {
    static let visibleOrder: [PaymentMethodType] = [.asset, .liability, .accounting, .pendingRealAccount]

    var displayName: String {
        switch self {
        case .asset:
            return "资产型收付手段"
        case .liability:
            return "负债型收付手段"
        case .accounting:
            return "账务处理型收付手段"
        case .pendingRealAccount:
            return "待补真实账户"
        }
    }
}

private extension AccountingElement {
    static let visibleOrder: [AccountingElement] = [.asset, .liability, .income, .expense]

    var displayName: String {
        switch self {
        case .asset:
            return "资产"
        case .liability:
            return "负债"
        case .income:
            return "收入"
        case .expense:
            return "支出"
        }
    }
}
