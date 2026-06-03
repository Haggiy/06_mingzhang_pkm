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
    @Published private(set) var isHidden = false
    private var detailDepth = 0
    private var overlayHidden = false

    func detailAppeared() {
        detailDepth += 1
        refresh()
    }

    func detailDisappeared() {
        detailDepth = max(0, detailDepth - 1)
        refresh()
    }

    func setOverlayHidden(_ hidden: Bool) {
        overlayHidden = hidden
        refresh()
    }

    private func refresh() {
        isHidden = detailDepth > 0 || overlayHidden
    }
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
    static let accentSoft = Color(red: 0.88, green: 0.97, blue: 0.96)
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
    var padding: CGFloat = 14
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MZTheme.card)
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MZTheme.line.opacity(0.8), lineWidth: 0.8)
        )
    }
}

private struct MZPage<Content: View>: View {
    var bottomInset: CGFloat = 24
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
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
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                Spacer(minLength: 44)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        } else {
            HStack(alignment: .center) {
                if let title {
                    Text(title)
                        .font(.headline.weight(.bold))
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
                                .font(.headline.weight(.semibold))
                            Image(systemName: "chevron.down")
                                .font(.footnote.weight(.bold))
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
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(MZTheme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("账月范围")
                } else if title != nil {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }
}

private struct MZBackHeader: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabVisibility: MZRootTabVisibility
    @State private var didRegisterVisibility = false
    let title: String
    var trailingSystemImage: String?
    var trailingTitle: String?
    var trailingTint: Color = MZTheme.accent
    var trailingAccessibilityIdentifier: String?
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
                .font(.title3.weight(.bold))
                .foregroundStyle(MZTheme.ink)
            Spacer()

            if let trailingTitle {
                Button {
                    trailingAction?()
                } label: {
                    Text(trailingTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(trailingTint)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .accessibilityIdentifier(trailingAccessibilityIdentifier ?? trailingTitle)
            } else if let trailingSystemImage {
                Button {
                    trailingAction?()
                } label: {
                    Image(systemName: trailingSystemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(trailingTint)
                        .frame(width: 44, height: 44, alignment: .trailing)
                }
                .accessibilityIdentifier(trailingAccessibilityIdentifier ?? trailingSystemImage)
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .background(MZTheme.page)
        .onAppear {
            if !didRegisterVisibility {
                tabVisibility.detailAppeared()
                didRegisterVisibility = true
            }
        }
        .onDisappear {
            if didRegisterVisibility {
                tabVisibility.detailDisappeared()
                didRegisterVisibility = false
            }
        }
    }
}

private struct MZMetricTriplet: View {
    let items: [(String, Decimal)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 5) {
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                    Text(item.1.moneyText)
                        .font(.callout.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(MZTheme.line)
                        .frame(width: 1, height: 34)
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
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                Spacer()
                Text(total.moneyText)
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(MZTheme.ink)
            }

            MZStackedBar(items: items, total: total)

            if items.isEmpty {
                MZEmptyState(title: "暂无\(title)", systemImage: "chart.pie")
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 7) {
                    ForEach(items) { item in
                        Button {
                            onItemTap?(item)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 8, height: 8)
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
                            .font(.footnote)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("structure_item_\(item.name)")
                    }
                }
            }
        }
    }
}

private struct MZDualStructureCard: View {
    let title: String
    let incomeTotal: Decimal
    let incomeItems: [CategoryDisplayItem]
    let expenseTotal: Decimal
    let expenseItems: [CategoryDisplayItem]
    var onItemTap: ((CategoryDisplayItem) -> Void)?

    var body: some View {
        MZCard(spacing: 0) {
            Text(title)
                .font(.headline.weight(.bold))
                .foregroundStyle(MZTheme.ink)
                .padding(.bottom, 4)

            MZCompactStructureSection(
                title: "收入结构",
                total: incomeTotal,
                items: incomeItems,
                onItemTap: onItemTap
            )

            MZDivider()
                .padding(.vertical, 8)

            MZCompactStructureSection(
                title: "支出结构",
                total: expenseTotal,
                items: expenseItems,
                onItemTap: onItemTap
            )
        }
    }
}

private struct MZMetricGrid: View {
    let items: [(String, Decimal)]

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 0),
            GridItem(.flexible(), spacing: 0)
        ], spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 6) {
                    Text(item.0)
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                    Text(item.1.moneyText)
                        .font(.headline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 74)
                .overlay(alignment: .trailing) {
                    if index % 2 == 0 {
                        Rectangle()
                            .fill(MZTheme.line)
                            .frame(width: 1, height: 54)
                    }
                }
                .overlay(alignment: .bottom) {
                    if index < items.count - 2 {
                        Rectangle()
                            .fill(MZTheme.line)
                            .frame(height: 1)
                    }
                }
            }
        }
    }
}

private struct MZCompactStructureSection: View {
    let title: String
    let total: Decimal
    let items: [CategoryDisplayItem]
    var onItemTap: ((CategoryDisplayItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MZTheme.ink)
                Spacer()
                Text(total.moneyText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MZTheme.ink)
            }

            MZStackedBar(items: items, total: total)

            if items.isEmpty {
                Text("暂无\(title)")
                    .font(.footnote)
                    .foregroundStyle(MZTheme.secondaryInk)
                    .frame(minHeight: 24)
            } else {
                VStack(spacing: 5) {
                    ForEach(items) { item in
                        Button {
                            onItemTap?(item)
                        } label: {
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 7, height: 7)
                                Text(item.name)
                                    .foregroundStyle(MZTheme.ink)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(item.amount.moneyText)
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                                    .foregroundStyle(MZTheme.ink)
                                Text(item.percentText(of: total))
                                    .frame(width: 48, alignment: .trailing)
                                    .foregroundStyle(MZTheme.secondaryInk)
                            }
                            .font(.footnote)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("structure_item_\(item.name)")
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
        .frame(height: 10)
    }
}

private struct MZRecordRow: View {
    let record: JournalRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.occurredAt.recordListText)
                    .font(.subheadline)
                    .foregroundStyle(MZTheme.ink)
                Spacer()
                Text(record.paymentMethodName)
                    .foregroundStyle(MZTheme.secondaryInk)
                Text(record.amount.moneyText)
                    .font(.callout.weight(.bold))
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
                .font(.footnote)
                .foregroundStyle(MZTheme.secondaryInk)
                .lineLimit(2)
        }
        .padding(.vertical, 11)
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
            .frame(height: 52)
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
            .font(.subheadline)
            .foregroundStyle(MZTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
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
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MZTheme.secondaryInk)
        }
        .frame(minHeight: 48)
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
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(MZTheme.ink)
                if required {
                    Text("*")
                        .foregroundStyle(MZTheme.danger)
                }
            }
            .frame(width: 96, alignment: .leading)

            Spacer(minLength: 8)

            content
                .font(.callout)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 50)
    }
}

private struct MZMenuRow: View {
    let title: String
    var required = false
    @Binding var selection: String
    let options: [String]
    var placeholder = "未选择"

    var body: some View {
        MZFieldRow(title: title, required: required) {
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option.isEmpty ? placeholder : option) {
                        selection = option
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection.isEmpty ? placeholder : selection)
                        .foregroundStyle(selection.isEmpty ? MZTheme.tertiaryInk : MZTheme.ink)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(MZTheme.accent)
                }
            }
        }
    }
}

private struct MZSheetHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var isCentered = false

    var body: some View {
        HStack {
            if isCentered {
                Color.clear.frame(width: 44, height: 44)
                Spacer()
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                Spacer()
            } else {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MZTheme.ink)
                Spacer()
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(MZTheme.ink)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

private struct MZOptionRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var trailing: String?
    var isSelected = false
    var isEnabled = true
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(isEnabled ? MZTheme.accent : MZTheme.tertiaryInk)
                        .frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isEnabled ? MZTheme.ink : MZTheme.secondaryInk)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(MZTheme.secondaryInk)
                    }
                }
                Spacer(minLength: 12)
                if let trailing {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                }
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isSelected ? MZTheme.accent : MZTheme.secondaryInk)
            }
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.72)
    }
}

private struct MZFilterChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(MZTheme.accent)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(MZTheme.accentSoft))
    }
}

private struct MZInfoCallout: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.headline)
                .foregroundStyle(Color(red: 0.02, green: 0.28, blue: 0.58))
            Text(text)
                .font(.footnote)
                .foregroundStyle(MZTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.96, green: 0.98, blue: 1.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 0.80, green: 0.88, blue: 0.98), lineWidth: 0.8)
        )
    }
}

private struct MZDestructiveButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDisabled ? MZTheme.tertiaryInk : MZTheme.danger)
                )
        }
        .disabled(isDisabled)
    }
}

private struct MZBottomToolBar: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(items, id: \.0) { item in
                Button {} label: {
                    Label(item.0, systemImage: item.1)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MZTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(MZTheme.card)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(MZTheme.line, lineWidth: 0.8)
                        )
                }
                .disabled(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(MZTheme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(MZTheme.line)
                .frame(height: 0.8)
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
    @State private var selectedMonth = ""

    var body: some View {
        VStack(spacing: 0) {
            MZSheetHeader(title: "账月范围", isCentered: true)
            MZPage(bottomInset: 18) {
                MZCard(spacing: 0) {
                    MZOptionRow(
                        title: "当前账月",
                        systemImage: "calendar",
                        trailing: selectedDisplayMonth,
                        isSelected: selectedMonth == store.accountMonth
                    ) {
                        selectedMonth = store.accountMonth
                    }
                    MZDivider()
                    MZOptionRow(
                        title: "YTD",
                        systemImage: "chart.bar",
                        trailing: "\(store.accountMonth.prefix(4))年1月 - \(store.accountMonth.displayMonth)",
                        isEnabled: false
                    )
                    MZDivider()
                    MZOptionRow(title: "全部", systemImage: "infinity", isEnabled: false)
                    MZDivider()
                    MZOptionRow(title: "自定义范围", systemImage: "slider.horizontal.3", isEnabled: false)
                    MZDivider()
                    MZOptionRow(
                        title: "账月列表",
                        systemImage: "list.bullet",
                        trailing: "\(store.availableAccountMonths.count) 个账月",
                        isEnabled: false
                    )
                }

                if !store.availableAccountMonths.isEmpty {
                    MZCard(spacing: 0) {
                        ForEach(Array(store.availableAccountMonths.enumerated()), id: \.element) { index, month in
                            MZOptionRow(
                                title: month.displayMonth,
                                subtitle: month,
                                isSelected: month == selectedMonth
                            ) {
                                selectedMonth = month
                            }
                            if index < store.availableAccountMonths.count - 1 {
                                MZDivider()
                            }
                        }
                    }
                }

                    HStack(spacing: 12) {
                        MZLightButton(title: "取消", systemImage: "xmark") {
                            dismiss()
                        }
                        .accessibilityIdentifier("month_picker_cancel")
                        MZPrimaryButton(title: "应用") {
                            if store.selectAccountMonth(selectedMonth) {
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("month_picker_apply")
                    }
                }
            }
        .onAppear {
            if selectedMonth.isEmpty {
                selectedMonth = store.accountMonth
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .background(MZTheme.page.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    private var selectedDisplayMonth: String {
        selectedMonth.isEmpty ? store.accountMonth.displayMonth : selectedMonth.displayMonth
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
    @EnvironmentObject private var tabVisibility: MZRootTabVisibility
    @State private var isShowingForm = false
    @State private var isShowingMonthPicker = false
    @State private var isShowingQuickMenu = false
    @State private var isShowingImport = false
    @State private var isShowingSearch = false
    @State private var presentedCategory: CategoryDisplayItem?
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
                            .font(.headline.weight(.bold))
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
                        onItemTap: { presentedCategory = $0 }
                    )

                    MZStructureCard(
                        title: "支出结构",
                        total: store.homeSummary.expenseTotal,
                        items: categoryItems(for: .expense),
                        onItemTap: { presentedCategory = $0 }
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

                if let category = presentedCategory {
                    Color.black.opacity(0.28)
                        .ignoresSafeArea()
                        .zIndex(2)

                    VStack {
                        Spacer()
                        CategoryBottomSheetView(
                            category: category,
                            total: categoryTotal(for: category),
                            onClose: {
                                presentedCategory = nil
                            },
                            onOpenDetail: {
                                presentedCategory = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                    selectedCategory = category
                                }
                            }
                        )
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.74)
                        .clipShape(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 28,
                                bottomLeadingRadius: 0,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 28,
                                style: .continuous
                            )
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(3)
                }
            }
            .navigationDestination(item: $selectedCategory) { category in
                CategoryDetailView(category: category, total: categoryTotal(for: category))
            }
            .onChange(of: presentedCategory != nil) {
                tabVisibility.setOverlayHidden(presentedCategory != nil)
            }
            .onDisappear {
                if presentedCategory != nil {
                    tabVisibility.setOverlayHidden(false)
                }
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
                    .font(.headline.weight(.bold))
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
                                    .font(.footnote)
                                    .foregroundStyle(MZTheme.secondaryInk)
                                    .frame(width: 62, alignment: .leading)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.note?.isEmpty == false ? record.note! : record.paymentDetailName)
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(MZTheme.ink)
                                    Text("\(record.paymentTypeName) · \(record.paymentDetailName)")
                                        .font(.footnote)
                                        .foregroundStyle(MZTheme.secondaryInk)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(record.amount.moneyText)
                                    .font(.callout.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(MZTheme.ink)
                            }
                            .padding(.vertical, 8)
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

private struct CategoryBottomSheetView: View {
    @EnvironmentObject private var store: LedgerStore
    let category: CategoryDisplayItem
    let total: Decimal
    let onClose: () -> Void
    let onOpenDetail: () -> Void
    @State private var records: [JournalRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(MZTheme.line)
                        .frame(width: 48, height: 5)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(category.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(MZTheme.ink)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            MZPage(bottomInset: 20) {
                MZCard {
                    HStack(alignment: .lastTextBaseline, spacing: 18) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(category.amount.moneyText)
                                .font(.largeTitle.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(MZTheme.ink)
                                .minimumScaleFactor(0.72)
                                .lineLimit(1)
                            Text("单位：元")
                                .font(.footnote)
                                .foregroundStyle(MZTheme.secondaryInk)
                        }

                        Rectangle()
                            .fill(MZTheme.line)
                            .frame(width: 1, height: 44)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("占当前")
                                .font(.footnote)
                                .foregroundStyle(MZTheme.secondaryInk)
                            Text(category.percentText(of: total))
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MZTheme.ink)
                        }

                        Spacer(minLength: 0)
                    }
                }

                MZCard(spacing: 0) {
                    Text("二级明细")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                        .padding(.bottom, 8)

                    if detailItems.isEmpty {
                        MZEmptyState(title: "暂无明细", systemImage: "chart.pie")
                    } else {
                        ForEach(Array(detailItems.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 8, height: 8)
                                Text(item.name)
                                    .font(.subheadline)
                                    .foregroundStyle(MZTheme.ink)
                                ProgressView(value: item.amount.doubleValue, total: max(category.amount.doubleValue, 1))
                                    .tint(item.color)
                                Text(item.amount.moneyText)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(MZTheme.ink)
                            }
                            .frame(minHeight: 38)

                            if index < detailItems.count - 1 {
                                MZDivider()
                            }
                        }
                    }
                }

                MZCard(padding: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("最近账目")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MZTheme.ink)
                            Spacer()
                            Button("查看分类详情") {
                                onOpenDetail()
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MZTheme.accent)
                            .accessibilityIdentifier("home_category_detail_button")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        if records.isEmpty {
                            MZEmptyState(title: "暂无来源流水", systemImage: "tray")
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        } else {
                            ForEach(Array(records.prefix(4).enumerated()), id: \.element.id) { index, record in
                                MZRecordRow(record: record)
                                    .padding(.horizontal, 16)
                                if index < min(records.count, 4) - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(MZTheme.card)
        .accessibilityIdentifier("home_category_bottom_sheet")
        .onAppear(perform: loadRecords)
    }

    private var detailItems: [(name: String, amount: Decimal, color: Color)] {
        Dictionary(grouping: records, by: \.paymentDetailName)
            .map { name, records in
                (name, records.reduce(Decimal.zero) { $0 + $1.amount.absoluteValue })
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .enumerated()
            .map { index, item in
                (item.0, item.1, MZTheme.categoryColors[index % MZTheme.categoryColors.count])
            }
    }

    private func loadRecords() {
        do {
            records = try store.querySourceRecords(recordIds: category.sourceRecordIds)
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}

private struct CategoryDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let category: CategoryDisplayItem
    let total: Decimal
    @State private var records: [JournalRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: category.name)
            MZPage {
                VStack(spacing: 4) {
                    Text(store.accountMonth.displayMonth)
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                    Text(category.amount.moneyText)
                        .font(.system(size: 52, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                        .minimumScaleFactor(0.64)
                        .lineLimit(1)
                    Text("单位：元")
                        .font(.footnote)
                        .foregroundStyle(MZTheme.secondaryInk)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                MZCard {
                    Text("近 6 个月趋势")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    CategoryTrendShell(color: category.color)
                    Text("跨账月趋势暂按 v5.1 视觉占位，接入历史统计后展示真实曲线。")
                        .font(.footnote)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard(spacing: 0) {
                    Text("当期明细结构")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                        .padding(.bottom, 8)
                    if detailItems.isEmpty {
                        MZEmptyState(title: "暂无明细", systemImage: "chart.pie")
                    } else {
                        ForEach(Array(detailItems.enumerated()), id: \.offset) { index, item in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 8, height: 8)
                                Text(item.name)
                                    .font(.subheadline)
                                    .foregroundStyle(MZTheme.ink)
                                ProgressView(value: item.amount.doubleValue, total: max(category.amount.doubleValue, 1))
                                    .tint(item.color)
                                Text(item.amount.moneyText)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(MZTheme.ink)
                                Text(item.amount.percentText(of: category.amount))
                                    .font(.footnote)
                                    .foregroundStyle(MZTheme.secondaryInk)
                                    .frame(width: 52, alignment: .trailing)
                            }
                            .frame(minHeight: 42)

                            if index < detailItems.count - 1 {
                                MZDivider()
                            }
                        }
                    }
                }

                MZCard(padding: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("最近账目")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MZTheme.ink)
                            Spacer()
                            Text("全部")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MZTheme.accent)
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MZTheme.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        if records.isEmpty {
                            MZEmptyState(title: "暂无来源流水", systemImage: "tray")
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        } else {
                            ForEach(Array(records.prefix(4).enumerated()), id: \.element.id) { index, record in
                                MZRecordRow(record: record)
                                    .padding(.horizontal, 16)
                                if index < min(records.count, 4) - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }

                MZCard {
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
                    .accessibilityIdentifier("category_detail_source_records_button")
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: loadRecords)
    }

    private var detailItems: [(name: String, amount: Decimal, color: Color)] {
        Dictionary(grouping: records, by: \.paymentDetailName)
            .map { name, records in
                (name, records.reduce(Decimal.zero) { $0 + $1.amount.absoluteValue })
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .enumerated()
            .map { index, item in
                (item.0, item.1, MZTheme.categoryColors[index % MZTheme.categoryColors.count])
            }
    }

    private func loadRecords() {
        do {
            records = try store.querySourceRecords(recordIds: category.sourceRecordIds)
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}

private struct CategoryTrendShell: View {
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 18) {
                ForEach(Array([0.42, 0.48, 0.56, 0.52, 0.64, 0.72].enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color.opacity(index == 5 ? 0.9 : 0.45))
                            .frame(width: 18, height: 110 * value)
                        Text(["11月", "12月", "1月", "2月", "3月", "4月"][index])
                            .font(.caption2)
                            .foregroundStyle(MZTheme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 148)

            HStack {
                ForEach(["明细", "其他", "合计"], id: \.self) { label in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(label == "合计" ? MZTheme.ink : color.opacity(label == "明细" ? 0.9 : 0.35))
                            .frame(width: 7, height: 7)
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(MZTheme.secondaryInk)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - 流水

struct JournalView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingForm = false
    @State private var isShowingMonthPicker = false
    @State private var isShowingFilter = false
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
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(MZTheme.accent)
                    .frame(width: 82, height: 48)
            }
            .accessibilityIdentifier("journal_search_button")

            Button {
                isShowingForm = true
            } label: {
                Label("点击这里记一笔", systemImage: "pencil")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(MZTheme.accent))
            }
            .accessibilityIdentifier("btn_new_record")

            Button {
                isShowingFilter = true
            } label: {
                Label("筛选", systemImage: "line.3.horizontal.decrease")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(MZTheme.accent)
                    .frame(width: 82, height: 48)
            }
            .accessibilityIdentifier("journal_filter_button")
        }
        .padding(.horizontal, 12)
        .frame(height: 66)
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
            MZSheetHeader(title: "筛选")
            MZPage {
                MZCard(spacing: 0) {
                    MZFieldRow(title: "账月范围") {
                        HStack(spacing: 6) {
                            Text(store.accountMonth.displayMonth)
                            Image(systemName: "chevron.down")
                                .foregroundStyle(MZTheme.secondaryInk)
                        }
                    }
                    MZDivider()
                    MZFieldRow(title: "时间范围") {
                        HStack(spacing: 6) {
                            Text(store.accountMonth.monthDateRangeText)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(MZTheme.secondaryInk)
                        }
                    }
                    MZDivider()
                    MZMenuRow(title: "收付手段", selection: $input.paymentMethodName, options: [""] + store.userVisibleMethods.map(\.name), placeholder: "全部收付手段")
                    MZDivider()
                    MZMenuRow(title: "收付类型", selection: $input.paymentTypeName, options: [""] + store.types.map(\.name), placeholder: "全部收付类型")
                    MZDivider()
                    MZMenuRow(title: "类型明细", selection: $input.paymentDetailName, options: [""] + filteredDetails.map(\.name), placeholder: "全部类型明细")
                    MZDivider()
                    MZFieldRow(title: "金额区间") {
                        HStack(spacing: 8) {
                            TextField("最低金额", text: $input.amountMinText)
                                .keyboardType(.decimalPad)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: 92, minHeight: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(MZTheme.page)
                                )
                            Text("~")
                                .foregroundStyle(MZTheme.secondaryInk)
                            TextField("最高金额", text: $input.amountMaxText)
                                .keyboardType(.decimalPad)
                                .padding(.horizontal, 8)
                                .frame(maxWidth: 92, minHeight: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(MZTheme.page)
                                )
                        }
                    }
                    MZDivider()
                    MZFieldRow(title: "备注关键词") {
                        TextField("输入关键词", text: $input.noteKeyword)
                            .padding(.horizontal, 8)
                            .frame(minHeight: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(MZTheme.page)
                            )
                    }
                    MZDivider()
                        .padding(.top, 8)
                    HStack(spacing: 12) {
                        MZLightButton(title: "重置", systemImage: "arrow.counterclockwise") {
                            input = JournalFilterInput()
                            if store.clearJournalFilter() {
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("journal_filter_reset")
                        MZPrimaryButton(title: "应用筛选") {
                            do {
                                if store.applyJournalFilter(try input.toFilter(accountMonth: store.accountMonth)) {
                                    dismiss()
                                }
                            } catch {
                                store.lastError = error.localizedDescription
                            }
                        }
                        .accessibilityIdentifier("journal_filter_apply")
                    }
                    .padding(.top, 12)
                }
            }
        }
        .presentationDetents([.large])
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
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.headline)
                        .foregroundStyle(MZTheme.tertiaryInk)
                    TextField("搜索流水备注、类型明细、金额", text: $keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("journal_search_field")
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MZTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MZTheme.line, lineWidth: 0.8)
                )

                HStack(alignment: .firstTextBaseline) {
                    Text("筛选条件")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    Spacer()
                    Button("清除筛选") {
                        keyword = ""
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MZTheme.accent)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        MZFilterChip(title: "\(store.accountMonth.displayMonth) ×")
                        if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            MZFilterChip(title: "关键词：\(keyword) ×")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)

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

                Text("共 \(results.count) 条结果")
                    .font(.subheadline)
                    .foregroundStyle(MZTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .center)
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
    @State private var liabilityObjectKey: String
    @State private var note: String

    init(candidate: ImportCandidateRecord) {
        self.candidate = candidate
        _accountMonth = State(initialValue: candidate.accountMonth)
        _amountText = State(initialValue: NSDecimalNumber(decimal: candidate.amount).stringValue)
        _paymentMethodName = State(initialValue: candidate.paymentMethodName ?? "待补真实账户")
        _paymentTypeName = State(initialValue: candidate.paymentTypeName ?? "")
        _paymentDetailName = State(initialValue: candidate.paymentDetailName ?? "")
        _liabilityObjectKey = State(initialValue: candidate.objectKey ?? "")
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
                    MZMenuRow(title: "收付类型", required: true, selection: $paymentTypeName, options: [""] + activeTypeOptions)
                        .accessibilityIdentifier("candidate-edit-type-picker")
                    MZDivider()
                    MZMenuRow(title: "类型明细", required: true, selection: $paymentDetailName, options: [""] + availableDetails.map(\.name))
                        .accessibilityIdentifier("candidate-edit-detail-picker")
                    if isLiabilityRepaymentCandidate {
                        MZDivider()
                        liabilityObjectMenuRow
                            .accessibilityIdentifier("candidate-edit-liability-object-picker")
                    }
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
        var names = store.activePaymentMethods.map(\.name)
        if !paymentMethodName.isEmpty, !names.contains(paymentMethodName) {
            names.insert(paymentMethodName, at: 0)
        }
        return names
    }

    private var availableDetails: [PaymentDetail] {
        guard let typeId = store.types.first(where: { $0.name == paymentTypeName })?.id else {
            return []
        }
        let active = store.activePaymentDetails.filter { $0.paymentTypeId == typeId }
        if let current = store.details.first(where: { $0.name == paymentDetailName && $0.paymentTypeId == typeId }),
           !active.contains(where: { $0.id == current.id }) {
            return active + [current]
        }
        return active
    }

    private var activeTypeOptions: [String] {
        var names = store.activePaymentTypes.map(\.name)
        if !paymentTypeName.isEmpty, !names.contains(paymentTypeName) {
            names.append(paymentTypeName)
        }
        return names
    }

    private var isLiabilityRepaymentCandidate: Bool {
        paymentTypeName == "负债类减记" || paymentDetailName.contains("还款")
    }

    private var liabilityObjectOptions: [(key: String, name: String)] {
        let options = store.userVisibleMethods
            .filter { $0.methodType == .liability }
            .map { (key: "liability:\($0.name)", name: $0.name) }
        if !liabilityObjectKey.isEmpty, !options.contains(where: { $0.key == liabilityObjectKey }) {
            return [(liabilityObjectKey, liabilityObjectKey.replacingOccurrences(of: "liability:", with: ""))] + options
        }
        return options
    }

    private var liabilityObjectMenuRow: some View {
        MZFieldRow(title: "负债对象", required: true) {
            Menu {
                ForEach(liabilityObjectOptions, id: \.key) { option in
                    Button(option.name) {
                        liabilityObjectKey = option.key
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(liabilityObjectOptions.first(where: { $0.key == liabilityObjectKey })?.name ?? "未选择")
                        .foregroundStyle(liabilityObjectKey.isEmpty ? MZTheme.tertiaryInk : MZTheme.ink)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(MZTheme.accent)
                }
            }
        }
    }

    private func makeChanges() throws -> ImportCandidateChanges {
        let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: trimmedAmount, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MingZhangError.validation("金额必须是有效数字")
        }
        return ImportCandidateChanges(
            accountMonth: accountMonth,
            amount: amount,
            paymentMethodName: paymentMethodName == (candidate.paymentMethodName ?? "待补真实账户") ? nil : paymentMethodName,
            paymentTypeName: paymentTypeName.isEmpty ? nil : paymentTypeName,
            paymentDetailName: paymentDetailName.isEmpty ? nil : paymentDetailName,
            objectKey: liabilityObjectKey.isEmpty ? nil : liabilityObjectKey,
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
    @State private var liabilityObjectKey = ""

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
                        MZMenuRow(title: "收付手段", selection: $paymentMethodName, options: [""] + store.activePaymentMethods.map(\.name))
                            .accessibilityIdentifier("batch-edit-method-picker")
                        MZDivider()
                        MZMenuRow(title: "收付类型", selection: $paymentTypeName, options: [""] + store.activePaymentTypes.map(\.name))
                            .accessibilityIdentifier("batch-edit-type-picker")
                        MZDivider()
                        MZMenuRow(title: "类型明细", selection: $paymentDetailName, options: [""] + availableDetails.map(\.name))
                            .accessibilityIdentifier("batch-edit-detail-picker")
                        if isLiabilityRepaymentBatch {
                            MZDivider()
                            MZMenuRow(title: "负债对象", selection: $liabilityObjectKey, options: [""] + liabilityObjectOptions)
                                .accessibilityIdentifier("batch-edit-liability-object-picker")
                        }
                    }

                    MZPrimaryButton(title: "应用修改") {
                        if store.batchUpdateImportCandidates(ids: selectedIds, changes: changes) {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("batch-edit-apply-btn")
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
        return store.activePaymentDetails.filter { $0.paymentTypeId == typeId }
    }

    private var isLiabilityRepaymentBatch: Bool {
        paymentTypeName == "负债类减记" || paymentDetailName.contains("还款")
    }

    private var liabilityObjectOptions: [String] {
        store.userVisibleMethods
            .filter { $0.methodType == .liability }
            .map { "liability:\($0.name)" }
    }

    private var changes: ImportCandidateChanges {
        ImportCandidateChanges(
            accountMonth: accountMonth.isEmpty ? nil : accountMonth,
            paymentMethodName: paymentMethodName.isEmpty ? nil : paymentMethodName,
            paymentTypeName: paymentTypeName.isEmpty ? nil : paymentTypeName,
            paymentDetailName: paymentDetailName.isEmpty ? nil : paymentDetailName,
            objectKey: liabilityObjectKey.isEmpty ? nil : liabilityObjectKey
        )
    }
}

struct JournalFormView: View {
    enum Mode: Equatable {
        case create
        case liabilityRepayment(item: BalanceItem, accountMonth: String)
        case liabilityCost(item: BalanceItem, accountMonth: String, kind: LiabilityCostKind)
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
        case .liabilityRepayment(let item, let accountMonth):
            _input = State(initialValue: .liabilityRepayment(item: item, accountMonth: accountMonth))
        case .liabilityCost(let item, let accountMonth, let kind):
            _input = State(initialValue: .liabilityCost(item: item, accountMonth: accountMonth, kind: kind))
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
                    MZMenuRow(title: "收付手段", required: true, selection: $input.paymentMethodName, options: paymentMethodOptions)
                        .accessibilityIdentifier("picker_payment_method")
                    MZDivider()
                    MZFieldRow(title: "金额", required: true) {
                        TextField("金额", text: $input.amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("field_amount")
                    }
                    if isLiabilityCostMode {
                        MZDivider()
                        liabilityCostKindPicker
                    }
                    MZDivider()
                    MZMenuRow(title: "收付类型", required: true, selection: $input.paymentTypeName, options: paymentTypeOptions)
                        .accessibilityIdentifier("picker_payment_type")
                    MZDivider()
                    MZMenuRow(title: "类型明细", required: true, selection: $input.paymentDetailName, options: availableDetails.map(\.name))
                        .accessibilityIdentifier("picker_payment_detail")
                    if usesLiabilityObject {
                        MZDivider()
                        liabilityObjectMenuRow
                            .accessibilityIdentifier("picker_liability_object")
                    }
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
            normalizeConfigSelection()
        }
        .onChange(of: input.paymentTypeName) {
            normalizeDetailSelection()
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create:
            "记一笔"
        case .liabilityRepayment:
            "记还款"
        case .liabilityCost:
            "补利息 / 费用"
        case .edit:
            "记录详情"
        }
    }

    private var sourceText: String {
        switch mode {
        case .create, .liabilityRepayment, .liabilityCost:
            "手工记录"
        case .edit(let record):
            record.recordSource.longDisplayName
        }
    }

    private var kindText: String {
        switch mode {
        case .create, .liabilityRepayment, .liabilityCost:
            "普通记录"
        case .edit(let record):
            record.recordKind == .carryForward ? "固定 / 继承记录" : "普通记录"
        }
    }

    private var isEditableRecord: Bool {
        switch mode {
        case .create, .liabilityRepayment, .liabilityCost:
            true
        case .edit(let record):
            record.isDirectlyEditable
        }
    }

    private func save() -> Bool {
        switch mode {
        case .create, .liabilityRepayment:
            return store.createRecord(input: input)
        case .liabilityCost:
            return store.createLiabilityCost(input: input)
        case .edit(let record):
            return store.updateRecord(id: record.id, input: input)
        }
    }

    private var paymentMethodOptions: [String] {
        let methods: [PaymentMethod]
        if isLiabilityRepaymentForm {
            methods = store.activePaymentMethods.filter { $0.methodType == .asset }
        } else if isLiabilityCostMode {
            methods = store.activePaymentMethods.filter { $0.methodType == .liability }
        } else {
            methods = store.activePaymentMethods
        }
        var names = methods.map(\.name)
        if !input.paymentMethodName.isEmpty, !names.contains(input.paymentMethodName) {
            names.append(input.paymentMethodName)
        }
        return names
    }

    private var paymentTypeOptions: [String] {
        if isLiabilityCostMode {
            return ["财务费用开支"]
        }
        var names = store.activePaymentTypes.map(\.name)
        if !input.paymentTypeName.isEmpty, !names.contains(input.paymentTypeName) {
            names.append(input.paymentTypeName)
        }
        return names
    }

    private var availableDetails: [PaymentDetail] {
        if isLiabilityCostMode {
            let names = Set(LiabilityCostKind.allCases.map(\.paymentDetailName))
            let active = store.activePaymentDetails.filter { names.contains($0.name) }
            if let current = store.details.first(where: { $0.name == input.paymentDetailName }),
               !active.contains(where: { $0.id == current.id }) {
                return active + [current]
            }
            return active
        }
        guard let typeId = store.types.first(where: { $0.name == input.paymentTypeName })?.id else {
            return store.activePaymentDetails
        }
        let active = store.activePaymentDetails.filter { $0.paymentTypeId == typeId }
        if let current = store.details.first(where: { $0.name == input.paymentDetailName && $0.paymentTypeId == typeId }),
           !active.contains(where: { $0.id == current.id }) {
            return active + [current]
        }
        return active
    }

    private var isLiabilityRepaymentForm: Bool {
        input.paymentTypeName == "负债类减记" || input.paymentDetailName.contains("还款")
    }

    private var isLiabilityCostMode: Bool {
        if case .liabilityCost = mode {
            return true
        }
        return false
    }

    private var usesLiabilityObject: Bool {
        isLiabilityRepaymentForm || isLiabilityCostMode
    }

    private var liabilityObjectOptions: [(key: String, name: String)] {
        let methods = store.userVisibleMethods.filter { $0.methodType == .liability }
        var options = methods.map { (key: "liability:\($0.name)", name: $0.name) }
        if !input.liabilityObjectKey.isEmpty,
           !options.contains(where: { $0.key == input.liabilityObjectKey }) {
            let displayName = input.liabilityObjectKey.replacingOccurrences(of: "liability:", with: "")
            options.insert((input.liabilityObjectKey, displayName), at: 0)
        }
        return options
    }

    private var liabilityObjectDisplayName: String {
        liabilityObjectOptions.first(where: { $0.key == input.liabilityObjectKey })?.name ?? "未选择"
    }

    private var liabilityObjectMenuRow: some View {
        MZFieldRow(title: "负债对象", required: true) {
            Menu {
                ForEach(liabilityObjectOptions, id: \.key) { option in
                    Button(option.name) {
                        input.liabilityObjectKey = option.key
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(liabilityObjectDisplayName)
                        .foregroundStyle(input.liabilityObjectKey.isEmpty ? MZTheme.tertiaryInk : MZTheme.ink)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(MZTheme.accent)
                }
            }
        }
    }

    private var liabilityCostKindPicker: some View {
        MZFieldRow(title: "成本类型", required: true) {
            Picker("成本类型", selection: Binding(
                get: { input.liabilityCostKind },
                set: { input.applyLiabilityCostKind($0) }
            )) {
                ForEach(LiabilityCostKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("picker_liability_cost_kind")
        }
    }

    private func normalizeConfigSelection() {
        if case .create = mode {
            if !store.activePaymentMethods.contains(where: { $0.name == input.paymentMethodName }) {
                input.paymentMethodName = store.activePaymentMethods.first?.name ?? input.paymentMethodName
            }
            if !store.activePaymentTypes.contains(where: { $0.name == input.paymentTypeName }) {
                input.paymentTypeName = store.activePaymentTypes.first?.name ?? input.paymentTypeName
            }
        }
        if case .liabilityRepayment = mode {
            if !store.activePaymentMethods.contains(where: { $0.name == input.paymentMethodName && $0.methodType == .asset }) {
                input.paymentMethodName = store.activePaymentMethods.first(where: { $0.methodType == .asset })?.name ?? input.paymentMethodName
            }
        }
        if case .liabilityCost = mode {
            input.paymentTypeName = "财务费用开支"
            if !store.activePaymentMethods.contains(where: { $0.name == input.paymentMethodName && $0.methodType == .liability }) {
                input.paymentMethodName = store.activePaymentMethods.first(where: { $0.methodType == .liability })?.name ?? input.paymentMethodName
            }
        }
        normalizeDetailSelection()
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
    @EnvironmentObject private var store: LedgerStore
    let record: JournalRecord
    @State private var investmentTrace: InvestmentFeedTrace?

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

                if record.recordSource == .investmentFeed {
                    InvestmentFeedTraceSection(trace: investmentTrace)
                } else {
                    MZPrimaryButton(title: "查看来源", isDisabled: true) {}
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(MZTheme.page)
        .onAppear(perform: loadInvestmentTraceIfNeeded)
    }

    private func loadInvestmentTraceIfNeeded() {
        guard record.recordSource == .investmentFeed else { return }
        investmentTrace = store.loadInvestmentTrace(recordId: record.id)
    }
}

struct InvestmentFeedTraceSection: View {
    let trace: InvestmentFeedTrace?

    private var transactions: [InvestmentTransaction] {
        trace?.transactions ?? []
    }

    private var fundName: String? {
        transactions.first?.fundName
    }

    var body: some View {
        MZCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("投资来源")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    Text("投资回填流水只读，修改请回到基金投资明细账")
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                }
                .padding(16)

                if transactions.isEmpty {
                    MZDivider()
                    MZEmptyState(title: "暂无投资来源", systemImage: "tray")
                        .frame(maxWidth: .infinity)
                        .padding(20)
                } else {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        MZDivider()
                        MZIconRow(
                            title: "\(transaction.transactionType.displayName) · \(transaction.fundName)",
                            subtitle: transaction.sourceExplanationText,
                            systemImage: transaction.transactionType.systemImage,
                            trailing: transaction.traceAmountText
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier("investment_feed_trace_transaction_\(index)")
                    }

                    if let fundName {
                        MZDivider()
                        NavigationLink {
                            InvestmentLedgerView(fundName: fundName)
                        } label: {
                            MZIconRow(
                                title: "查看投资明细账",
                                subtitle: "在基金投资明细账新增、编辑或删除交易",
                                systemImage: "book",
                                trailing: "进入"
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("investment_feed_trace_ledger_button")
                    }
                }
            }
        }
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

                MZCard(spacing: 0) {
                    sectionHeader(title: "资产（成本口径）", amount: store.balanceSummary.cashBalance + deferredBookValue)
                    NavigationLink {
                        AssetDetailView(
                            title: "现金类资产",
                            amount: store.balanceSummary.cashBalance,
                            sourceRecordIds: store.balanceSummary.cashSourceRecordIds
                        )
                    } label: {
                        listAmountRow(title: "现金", amount: store.balanceSummary.cashBalance)
                    }
                    .accessibilityIdentifier("asset_cash_detail_entry")
                    MZDivider()
                    listAmountRow(title: "电子钱包余额", amount: store.balanceSummary.cashBalance, showChevron: false)
                    MZDivider()
                    NavigationLink {
                        DeferredAssetListView()
                    } label: {
                        listAmountRow(title: "长期待摊费用", amount: deferredBookValue)
                    }
                    .accessibilityIdentifier("asset_deferred_detail_entry")
                }

                MZCard(spacing: 0) {
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
                            .accessibilityIdentifier("liability_row_\(item.name)")
                            if index < store.balanceSummary.liabilityItems.count - 1 {
                                MZDivider()
                            }
                        }
                    }
                }

                MZCard(spacing: 0) {
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
        store.balanceSummary.cashBalance + deferredBookValue + investmentBookValue
    }

    private var liabilityTotal: Decimal {
        store.balanceSummary.liabilityItems.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var deferredBookValue: Decimal {
        store.balanceSummary.deferredItems.reduce(Decimal.zero) { $0 + $1.amount }
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
                .font(.callout.weight(.bold))
                .foregroundStyle(MZTheme.ink)
            Spacer()
            Text(amount.moneyText)
                .font(.callout.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(MZTheme.accent)
            Image(systemName: "chevron.right")
                .foregroundStyle(MZTheme.accent)
        }
        .frame(minHeight: 42)
    }

    private func listAmountRow(title: String, amount: Decimal, showChevron: Bool = true) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(MZTheme.ink)
            Spacer()
            Text(amount.moneyText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(MZTheme.ink)
            if showChevron {
                Image(systemName: "chevron.right")
                    .foregroundStyle(MZTheme.secondaryInk)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

struct AssetDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let amount: Decimal
    let sourceRecordIds: [UUID]
    @State private var records: [JournalRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: title)
            MZPage {
                MZCard {
                    Text("当前余额（成本口径）")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(amount.moneyText)
                        .font(.system(size: 50, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                        .minimumScaleFactor(0.62)
                        .lineLimit(1)
                    Text("较上月变化")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                    Text("待接入上月余额后展示")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MZTheme.ink)
                }

                MZCard(spacing: 0) {
                    HStack {
                        Text("对象列表")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                        Spacer()
                        Text(amount.moneyText)
                            .font(.headline.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(MZTheme.accent)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(MZTheme.accent)
                    }
                    .frame(minHeight: 38)

                    if objectItems.isEmpty {
                        MZDivider()
                        MZEmptyState(title: "暂无对象拆分", systemImage: "wallet.pass", subtitle: "接入收付手段余额后展示对象列表")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(Array(objectItems.enumerated()), id: \.offset) { index, item in
                            MZDivider()
                            HStack {
                                Image(systemName: item.icon)
                                    .font(.headline)
                                    .foregroundStyle(MZTheme.accent)
                                    .frame(width: 28, height: 28)
                                Text(item.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MZTheme.ink)
                                Spacer()
                                Text(item.amount.moneyText)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(MZTheme.ink)
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(MZTheme.secondaryInk)
                            }
                            .frame(minHeight: 50)
                            .accessibilityIdentifier("asset_object_row_\(item.name)")
                        }
                    }
                }

                MZCard(padding: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("来源流水（最近4条）")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MZTheme.ink)
                            Spacer()
                            NavigationLink {
                                SourceRecordsView(
                                    title: "\(title) 来源",
                                    filterDescription: "\(store.accountMonth.displayMonth) / \(title)",
                                    recordIds: sourceRecordIds
                                )
                            } label: {
                                HStack(spacing: 4) {
                                    Text("查看来源流水")
                                    Image(systemName: "chevron.right")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MZTheme.accent)
                            }
                            .accessibilityIdentifier("asset_source_records_button")
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        if records.isEmpty {
                            MZEmptyState(title: "暂无来源流水", systemImage: "tray")
                                .frame(maxWidth: .infinity)
                                .padding(20)
                        } else {
                            ForEach(Array(records.prefix(4).enumerated()), id: \.element.id) { index, record in
                                MZRecordRow(record: record)
                                    .padding(.horizontal, 16)
                                if index < min(records.count, 4) - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }

                MZCard {
                    NavigationLink {
                        AdjustBalanceView(title: title, currentAmount: amount)
                    } label: {
                        MZIconRow(title: "调整余额", subtitle: "通过生成流水调整记录修正余额", systemImage: "pencil.line")
                    }
                    .accessibilityIdentifier("asset_adjust_balance_button")
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: loadRecords)
    }

    private var objectItems: [(name: String, amount: Decimal, icon: String)] {
        Dictionary(grouping: records, by: \.paymentMethodName)
            .map { name, records in
                (name, records.reduce(Decimal.zero) { $0 + $1.amount }, "wallet.pass")
            }
            .sorted { $0.0 < $1.0 }
    }

    private func loadRecords() {
        do {
            records = try store.querySourceRecords(recordIds: sourceRecordIds)
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}

struct DeferredAssetListView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "递延资产")
            MZPage {
                MZCard {
                    Text(totalAmount.moneyText)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                    Text("长期待摊费用未释放余额")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard(padding: 0) {
                    if items.isEmpty {
                        MZEmptyState(title: "暂无递延资产", systemImage: "tray", subtitle: "预付费用会按稳定备注形成递延对象")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.objectKey) { index, item in
                                NavigationLink {
                                    DeferredAssetDetailView(item: item)
                                } label: {
                                    MZIconRow(
                                        title: item.name,
                                        subtitle: "形成 \(item.formedAmount.moneyText) / 已释放 \(item.releasedAmount.moneyText)",
                                        systemImage: "calendar.badge.clock",
                                        trailing: item.amount.moneyText
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("deferred_asset_row_\(item.name)")
                                if index < items.count - 1 {
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

    private var items: [DeferredBalanceItem] {
        store.balanceSummary.deferredItems
    }

    private var totalAmount: Decimal {
        items.reduce(Decimal.zero) { $0 + $1.amount }
    }
}

struct DeferredAssetDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let item: DeferredBalanceItem

    private var currentItem: DeferredBalanceItem {
        store.balanceSummary.deferredItems.first { $0.objectKey == item.objectKey } ?? item
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: currentItem.name)
            MZPage {
                MZCard {
                    Text(currentItem.amount.moneyText)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                        .accessibilityIdentifier("deferred_detail_remaining_amount")
                    Text("未释放余额")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard {
                    SummaryLine(title: "形成金额", value: currentItem.formedAmount.moneyText)
                    MZDivider()
                    SummaryLine(title: "已释放", value: currentItem.releasedAmount.moneyText)
                    MZDivider()
                    SummaryLine(title: "对象标识", value: currentItem.objectKey)
                }

                MZCard {
                    NavigationLink {
                        SourceRecordsView(
                            title: "\(currentItem.name) 来源",
                            filterDescription: "\(store.accountMonth.displayMonth) / 递延资产",
                            recordIds: currentItem.sourceRecordIds
                        )
                    } label: {
                        MZIconRow(title: "相关流水", subtitle: "查看预付形成和递延释放来源", systemImage: "list.bullet.rectangle", trailing: "\(currentItem.sourceRecordIds.count) 条")
                    }
                    .accessibilityIdentifier("deferred_source_records_button")
                    if currentItem.amount > 0 {
                        MZDivider()
                        NavigationLink {
                            DeferredReleaseFormView(item: currentItem, accountMonth: store.accountMonth)
                        } label: {
                            MZIconRow(title: "释放递延资产", subtitle: "生成递延减少和消费确认流水", systemImage: "arrow.down.forward.and.arrow.up.backward.circle")
                        }
                        .accessibilityIdentifier("deferred_release_button")
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct DeferredReleaseFormView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let item: DeferredBalanceItem
    @State private var input: DeferredReleaseFormInput

    init(item: DeferredBalanceItem, accountMonth: String) {
        self.item = item
        _input = State(initialValue: .deferredRelease(item: item, accountMonth: accountMonth))
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "释放递延资产")
            MZPage {
                MZCard {
                    SummaryLine(title: "递延对象", value: item.name)
                    MZDivider()
                    SummaryLine(title: "未释放余额", value: input.remainingAmount.moneyText)
                    MZDivider()
                    SummaryLine(title: "释放方式", value: "账务处理 / 长期待摊费用减少")
                }

                MZCard {
                    MZFieldRow(title: "账月", required: true) {
                        TextField("账月", text: $input.accountMonth)
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(MZTheme.accent)
                            .accessibilityIdentifier("deferred_release_account_month_field")
                    }
                    MZDivider()
                    MZFieldRow(title: "时间", required: true) {
                        DatePicker("", selection: $input.occurredAt, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                    }
                    MZDivider()
                    MZFieldRow(title: "释放金额", required: true) {
                        TextField("金额", text: $input.amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("deferred_release_amount_field")
                    }
                    MZDivider()
                    MZMenuRow(title: "消费分类", required: true, selection: $input.expensePaymentTypeName, options: expenseTypeOptions)
                        .accessibilityIdentifier("deferred_release_type_picker")
                    MZDivider()
                    MZMenuRow(title: "类型明细", required: true, selection: $input.expensePaymentDetailName, options: availableDetails.map(\.name))
                        .accessibilityIdentifier("deferred_release_detail_picker")
                }

                MZCard {
                    Text("备注")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(MZTheme.ink)
                    TextField("备注", text: $input.note, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("deferred_release_note_field")
                }

                MZPrimaryButton(title: "保存释放", isDisabled: !canSave) {
                    if store.createDeferredRelease(input: input) {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("deferred_release_save_button")
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: normalizeSelections)
        .onChange(of: input.expensePaymentTypeName) {
            normalizeDetailSelection()
        }
    }

    private var expenseTypeOptions: [String] {
        let active = store.activePaymentTypes.filter { $0.element == .expense }.map(\.name)
        if !input.expensePaymentTypeName.isEmpty, !active.contains(input.expensePaymentTypeName) {
            return active + [input.expensePaymentTypeName]
        }
        return active
    }

    private var availableDetails: [PaymentDetail] {
        guard let typeId = store.types.first(where: { $0.name == input.expensePaymentTypeName })?.id else {
            return []
        }
        let active = store.activePaymentDetails.filter { $0.paymentTypeId == typeId }
        if let current = store.details.first(where: { $0.name == input.expensePaymentDetailName && $0.paymentTypeId == typeId }),
           !active.contains(where: { $0.id == current.id }) {
            return active + [current]
        }
        return active
    }

    private var canSave: Bool {
        guard !input.accountMonth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.deferredObjectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.expensePaymentTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !input.expensePaymentDetailName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let amount = Decimal(string: input.amountText.trimmingCharacters(in: .whitespacesAndNewlines), locale: Locale(identifier: "en_US_POSIX"))
        else {
            return false
        }
        return amount > 0 && amount <= input.remainingAmount
    }

    private func normalizeSelections() {
        if !expenseTypeOptions.contains(input.expensePaymentTypeName) {
            input.expensePaymentTypeName = expenseTypeOptions.first ?? input.expensePaymentTypeName
        }
        normalizeDetailSelection()
    }

    private func normalizeDetailSelection() {
        let names = availableDetails.map(\.name)
        if !names.contains(input.expensePaymentDetailName) {
            input.expensePaymentDetailName = names.first ?? input.expensePaymentDetailName
        }
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
                    .accessibilityIdentifier("adjust_balance_generate_button")

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

    private var currentItem: BalanceItem {
        store.balanceSummary.liabilityItems.first { candidate in
            if let objectKey = item.objectKey {
                return candidate.objectKey == objectKey
            }
            return candidate.name == item.name
        } ?? item
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: currentItem.name)
            MZPage {
                MZCard {
                    Text(currentItem.amount.moneyText)
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MZTheme.ink)
                    Text("剩余负债")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard {
                    SummaryLine(title: "形成负债", value: currentItem.formedAmount.moneyText)
                    MZDivider()
                    SummaryLine(title: "已还款", value: currentItem.repaidAmount.moneyText)
                    MZDivider()
                    SummaryLine(title: "利息/费用成本", value: currentItem.costAmount.moneyText)
                }

                MZCard {
                    NavigationLink {
                        SourceRecordsView(
                            title: "\(currentItem.name) 来源",
                            filterDescription: "\(store.accountMonth.displayMonth) / \(currentItem.name)",
                            recordIds: currentItem.sourceRecordIds
                        )
                    } label: {
                        MZIconRow(title: "相关流水", subtitle: "查看负债形成与变化来源", systemImage: "list.bullet.rectangle", trailing: "\(currentItem.sourceRecordIds.count) 条")
                    }
                    .accessibilityIdentifier("liability_source_records_button")
                    MZDivider()
                    NavigationLink {
                        JournalFormView(mode: .liabilityRepayment(item: currentItem, accountMonth: store.accountMonth))
                    } label: {
                        MZIconRow(title: "记还款", subtitle: "生成负债类减记 / 账单还款流水", systemImage: "checkmark.circle")
                    }
                    .accessibilityIdentifier("liability_repayment_button")
                    MZDivider()
                    NavigationLink {
                        JournalFormView(mode: .liabilityCost(item: currentItem, accountMonth: store.accountMonth, kind: .interest))
                    } label: {
                        MZIconRow(title: "补利息 / 费用", subtitle: "生成财务费用开支流水", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("liability_cost_button")
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
    @State private var isShowingCreateForm = false
    @State private var editingTransaction: InvestmentTransaction?

    private var isEditingTransactionPresented: Binding<Bool> {
        Binding {
            editingTransaction != nil
        } set: { isPresented in
            if !isPresented {
                editingTransaction = nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "基金投资明细账", trailingSystemImage: "book")
            MZPage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(fundName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                            .accessibilityIdentifier("investment_ledger_fund_name")
                        Text("基金")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MZTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(MZTheme.accentSoft)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(MZTheme.accent.opacity(0.25), lineWidth: 0.8)
                            )
                    }
                    Text("最新净值：\(holding?.latestNAVText ?? "-")")
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                }

                MZCard {
                    MZMetricGrid(items: [
                        ("成本（元）", holding?.bookValue ?? 0),
                        ("份额（份）", holding?.holdingShare ?? 0),
                        ("PV（元）", holding?.presentValue ?? holding?.bookValue ?? 0),
                        ("未实现盈亏（元）", holding?.unrealizedGain ?? 0)
                    ])
                }

                if let summary {
                    MZCard(spacing: 0) {
                        Text("\(store.accountMonth.displayMonth) 结果")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                            .padding(.bottom, 6)
                        SummaryLine(title: "买入入账", value: summary.buyBookAmount.moneyText)
                        MZDivider()
                        SummaryLine(title: "卖出入账", value: summary.sellBookAmount.moneyText)
                        MZDivider()
                        SummaryLine(title: "已实现收益", value: summary.realizedGain.moneyText)
                        MZDivider()
                        SummaryLine(title: "已实现亏损", value: summary.realizedLoss.moneyText)
                    }
                }

                MZCard(padding: 0) {
                    if transactions.isEmpty {
                        MZEmptyState(title: "暂无交易", systemImage: "tray")
                            .frame(maxWidth: .infinity)
                            .padding(20)
                    } else {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(["全部", "买入", "卖出", "净值记录"], id: \.self) { title in
                                    Text(title)
                                        .font(.footnote.weight(title == "全部" ? .semibold : .regular))
                                        .foregroundStyle(title == "全部" ? MZTheme.accent : MZTheme.secondaryInk)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .overlay(alignment: .bottom) {
                                            if title == "全部" {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(MZTheme.accent)
                                                    .frame(width: 46, height: 3)
                                            }
                                        }
                                }
                            }
                            MZDivider()
                            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                                Button {
                                    editingTransaction = transaction
                                } label: {
                                    InvestmentTransactionRow(transaction: transaction)
                                        .padding(.horizontal, 16)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("investment_transaction_row_\(transaction.transactionType.rawValue)_\(transaction.id.uuidString.prefix(8))")
                                if index < transactions.count - 1 {
                                    MZDivider().padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }

                InvestmentFeedRecordsSection(records: feedRecords)

                MZLightButton(title: "查看投资明细账", systemImage: "chevron.right") {}
                    .disabled(true)
                MZPrimaryButton(title: "新增交易") {
                    isShowingCreateForm = true
                }
                .accessibilityIdentifier("investment_add_transaction_button")
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $isShowingCreateForm) {
            InvestmentTransactionFormView(mode: .create(fundName: fundName, accountMonth: store.accountMonth))
        }
        .navigationDestination(isPresented: isEditingTransactionPresented) {
            if let editingTransaction {
                InvestmentTransactionFormView(mode: .edit(editingTransaction))
            }
        }
        .onAppear(perform: loadData)
        .onChange(of: store.investmentHoldings.map(\.id)) {
            loadData()
        }
        .onChange(of: store.investmentTransactions.map(\.id)) {
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

struct InvestmentTransactionFormView: View {
    enum Mode {
        case create(fundName: String, accountMonth: String)
        case edit(InvestmentTransaction)
    }

    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    @State private var input: InvestmentFormInput
    @State private var isShowingDeleteConfirmation = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create(let fundName, let accountMonth):
            var draft = InvestmentFormInput()
            draft.accountMonth = accountMonth
            draft.occurredDateText = "\(accountMonth)-10"
            draft.fundName = fundName
            _input = State(initialValue: draft)
        case .edit(let transaction):
            _input = State(initialValue: .from(transaction: transaction))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: modeTitle)
            MZPage {
                MZCard {
                    MZFieldRow(title: "账月", required: true) {
                        TextField("YYYY-MM", text: $input.accountMonth)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("investment_account_month_field")
                    }
                    MZDivider()
                    MZFieldRow(title: "日期", required: true) {
                        TextField("YYYY-MM-DD", text: $input.occurredDateText)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("investment_occurred_date_field")
                    }
                    MZDivider()
                    MZFieldRow(title: "标的名称", required: true) {
                        TextField("基金名称", text: $input.fundName)
                            .accessibilityIdentifier("investment_fund_name_field")
                    }
                    MZDivider()
                    transactionTypePicker
                }

                MZCard {
                    if input.transactionType == .buy || input.transactionType == .sell {
                        MZFieldRow(title: "交易金额", required: true) {
                            TextField("交易金额", text: $input.tradeAmountText)
                                .keyboardType(.numbersAndPunctuation)
                                .accessibilityIdentifier("investment_trade_amount_field")
                        }
                        MZDivider()
                        MZFieldRow(title: "交易份额", required: true) {
                            TextField("交易份额", text: $input.tradeShareText)
                                .keyboardType(.numbersAndPunctuation)
                                .accessibilityIdentifier("investment_trade_share_field")
                        }
                        MZDivider()
                    }
                    MZFieldRow(title: "单位净值", required: input.transactionType == .nav) {
                        TextField("单位净值", text: $input.navText)
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("investment_nav_field")
                    }
                    MZDivider()
                    MZFieldRow(title: "备注") {
                        TextField("备注", text: $input.note)
                            .accessibilityIdentifier("investment_note_field")
                    }
                }

                if let transaction = existingTransaction {
                    MZCard(spacing: 0) {
                        Text("系统计算")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                            .padding(.bottom, 6)
                        SummaryLine(title: "入账金额", value: transaction.bookAmount?.moneyText ?? "-")
                        MZDivider()
                        SummaryLine(title: "已实现收益", value: transaction.realizedGain.moneyText)
                        MZDivider()
                        SummaryLine(title: "已实现亏损", value: transaction.realizedLoss.moneyText)
                        MZDivider()
                        SummaryLine(title: "持有份额", value: transaction.holdingShare.moneyText)
                        MZDivider()
                        SummaryLine(title: "平均成本", value: transaction.averageCost?.moneyText ?? "-")
                        MZDivider()
                        SummaryLine(title: "BV", value: transaction.bookValue.moneyText)
                        MZDivider()
                        SummaryLine(title: "PV", value: transaction.presentValue?.moneyText ?? "-")
                    }
                }

                MZCard {
                    SummaryLine(title: "来源", value: "基金投资明细")
                    MZDivider()
                    SummaryLine(title: "编辑边界", value: "修改交易事实后系统重算回填流水")
                }

                MZPrimaryButton(title: "保存交易") {
                    if save() {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("investment_transaction_save_button")

                if case .edit = mode {
                    Button("删除交易", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .accessibilityIdentifier("investment_transaction_delete_button")
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .confirmationDialog("确认删除交易？", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("确认删除交易", role: .destructive) {
                if case .edit(let transaction) = mode, store.deleteInvestmentTransaction(id: transaction.id) {
                    dismiss()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后会重新计算投资明细、投资持仓和相关账月的回填流水。")
        }
        .onChange(of: input.transactionType) {
            normalizeFieldsForTransactionType()
        }
    }

    private var modeTitle: String {
        switch mode {
        case .create:
            return "新增基金交易"
        case .edit:
            return "编辑基金交易"
        }
    }

    private var existingTransaction: InvestmentTransaction? {
        if case .edit(let transaction) = mode {
            return transaction
        }
        return nil
    }

    private var transactionTypePicker: some View {
        MZFieldRow(title: "交易类别", required: true) {
            Menu {
                ForEach(InvestmentTransactionType.allCases, id: \.self) { type in
                    Button(type.displayName) {
                        input.transactionType = type
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(input.transactionType.displayName)
                        .foregroundStyle(MZTheme.ink)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(MZTheme.accent)
                }
            }
        }
        .accessibilityIdentifier("investment_transaction_type_menu")
    }

    private func save() -> Bool {
        switch mode {
        case .create:
            return store.createInvestmentTransaction(input: input)
        case .edit(let transaction):
            return store.updateInvestmentTransaction(id: transaction.id, input: input)
        }
    }

    private func normalizeFieldsForTransactionType() {
        if input.transactionType == .nav {
            input.tradeAmountText = ""
            input.tradeShareText = ""
        }
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
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .lineLimit(1)
                }
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
    @State private var keyword = ""
    @State private var allRecords: [JournalRecord] = []
    @State private var records: [JournalRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: title)
            ZStack(alignment: .bottom) {
                MZPage(bottomInset: 146) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.headline)
                            .foregroundStyle(MZTheme.tertiaryInk)
                        TextField("在当前来源中搜索", text: $keyword)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("source_records_search_field")
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MZTheme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(MZTheme.line, lineWidth: 0.8)
                    )

                    MZCard {
                        HStack {
                            Text("当前筛选")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MZTheme.ink)
                            Spacer()
                            Button("清除筛选") {}
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MZTheme.accent)
                                .disabled(true)
                        }
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                MZFilterChip(title: "\(store.accountMonth.displayMonth) ×")
                                MZFilterChip(title: "来源 ×")
                                MZFilterChip(title: filterDescription)
                                if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    MZFilterChip(title: "关键词：\(keyword) ×")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)
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

                    Text("共 \(records.count) 条来源记录")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                MZBottomToolBar(items: [
                    ("搜索", "magnifyingglass"),
                    ("点击这里记一笔", "pencil"),
                    ("筛选", "line.3.horizontal.decrease")
                ])
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .onAppear(perform: loadRecords)
        .onChange(of: keyword) {
            applyKeyword()
        }
    }

    private func loadRecords() {
        do {
            allRecords = try store.querySourceRecords(recordIds: recordIds)
            applyKeyword()
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func applyKeyword() {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            records = allRecords
            return
        }
        records = allRecords.filter { record in
            record.paymentMethodName.localizedCaseInsensitiveContains(trimmed)
                || record.paymentTypeName.localizedCaseInsensitiveContains(trimmed)
                || record.paymentDetailName.localizedCaseInsensitiveContains(trimmed)
                || (record.note?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }
}

// MARK: - 统计

struct StatisticsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingMonthPicker = false
    @State private var selectedCategory: CategoryDisplayItem?

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
                        .font(.headline.weight(.bold))
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

                MZDualStructureCard(
                    title: "收支结构",
                    incomeTotal: store.homeSummary.incomeTotal,
                    incomeItems: categoryItems(for: .income),
                    expenseTotal: store.homeSummary.expenseTotal,
                    expenseItems: categoryItems(for: .expense),
                    onItemTap: { selectedCategory = $0 }
                )

                MZCard(spacing: 0) {
                    HStack(alignment: .center) {
                        Text("资产负债变化")
                            .font(.headline.weight(.bold))
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
                        .accessibilityIdentifier("statistics_balance_change_detail")
                    }
                    .frame(minHeight: 36)
                    SummaryLine(title: "资产增加", value: store.balanceSummary.cashBalance.moneyText)
                    MZDivider()
                    SummaryLine(title: "负债减少", value: "0.00")
                    MZDivider()
                    SummaryLine(title: "递延资产释放", value: deferredReleasedAmount.moneyText)
                    MZDivider()
                    SummaryLine(title: "投资成本变化", value: store.investmentMonthlySummary.endingBookValue.moneyText)
                }

                MZCard(spacing: 0) {
                    HStack(alignment: .center) {
                        Text("投资结果")
                            .font(.headline.weight(.bold))
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
                        .accessibilityIdentifier("statistics_investment_result_detail")
                    }
                    .frame(minHeight: 36)
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
            .navigationDestination(item: $selectedCategory) { category in
                CategoryDetailView(category: category, total: categoryTotal(for: category))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func categoryItems(for element: AccountingElement) -> [CategoryDisplayItem] {
        if element == .expense {
            return store.statisticsSummary.expenseByType.enumerated().map { index, item in
                CategoryDisplayItem(
                    name: item.typeName,
                    amount: item.amount.absoluteValue,
                    color: MZTheme.categoryColors[index % MZTheme.categoryColors.count],
                    sourceRecordIds: item.sourceRecordIds
                )
            }
        }

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

    private var deferredReleasedAmount: Decimal {
        store.balanceSummary.deferredItems.reduce(Decimal.zero) { $0 + $1.releasedAmount }
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
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "资产负债变化")
            MZPage {
                MZCard {
                    SummaryLine(title: "现金资产余额", value: store.balanceSummary.cashBalance.moneyText)
                    MZDivider()
                    SummaryLine(title: "递延资产形成", value: deferredFormedAmount.moneyText)
                    MZDivider()
                    SummaryLine(title: "递延资产释放", value: deferredReleasedAmount.moneyText)
                    MZDivider()
                    SummaryLine(title: "递延资产余额", value: deferredRemainingAmount.moneyText)
                }
                MZCard {
                    if deferredSourceRecordIds.isEmpty {
                        MZEmptyState(title: "暂无递延来源", systemImage: "tray")
                    } else {
                        NavigationLink {
                            SourceRecordsView(
                                title: "递延资产来源",
                                filterDescription: "\(store.accountMonth.displayMonth) / 递延资产",
                                recordIds: deferredSourceRecordIds
                            )
                        } label: {
                            MZIconRow(title: "递延资产来源", subtitle: "查看预付形成与释放流水", systemImage: "list.bullet.rectangle", trailing: "\(deferredSourceRecordIds.count) 条")
                        }
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }

    private var deferredFormedAmount: Decimal {
        store.balanceSummary.deferredItems.reduce(Decimal.zero) { $0 + $1.formedAmount }
    }

    private var deferredReleasedAmount: Decimal {
        store.balanceSummary.deferredItems.reduce(Decimal.zero) { $0 + $1.releasedAmount }
    }

    private var deferredRemainingAmount: Decimal {
        store.balanceSummary.deferredItems.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var deferredSourceRecordIds: [UUID] {
        Array(Set(store.balanceSummary.deferredItems.flatMap(\.sourceRecordIds))).sorted { $0.uuidString < $1.uuidString }
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
                                .accessibilityIdentifier("instrument_result_row_\(holding.fundName)")
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
                    .accessibilityIdentifier("instrument_result_ledger_button")
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MZTheme.secondaryInk)

                MZCard(spacing: 0) {
                    NavigationLink {
                        PaymentMethodsSettingsView()
                    } label: {
                        MZIconRow(title: "收付手段", subtitle: "管理资产型、负债型和账务处理型", systemImage: "wallet.pass")
                    }
                    .accessibilityIdentifier("settings_payment_methods")
                    MZDivider()
                    NavigationLink {
                        PaymentTypesSettingsView()
                    } label: {
                        MZIconRow(title: "收付类型与明细", subtitle: "维护收付类型和类型明细", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityIdentifier("settings_payment_types")
                }

                Text("数据管理")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MZTheme.secondaryInk)

                MZCard(spacing: 0) {
                    NavigationLink {
                        DataExportBackupView()
                    } label: {
                        MZIconRow(title: "数据导出", subtitle: "审计 CSV 与完整备份", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings_data_export")
                    MZDivider()
                    NavigationLink {
                        DataRestoreView()
                    } label: {
                        MZIconRow(title: "数据恢复", subtitle: "从新明账备份文件恢复", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("settings_data_restore")
                    MZDivider()
                    NavigationLink {
                        DataClearConfirmView()
                    } label: {
                        MZIconRow(title: "数据清空", subtitle: "清空全部数据（慎用）", systemImage: "trash", tint: MZTheme.danger)
                    }
                    .accessibilityIdentifier("settings_data_clear")
                }

                Text("App 设置")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MZTheme.secondaryInk)

                MZCard(spacing: 0) {
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
    @State private var createType: PaymentMethodType?

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "收付手段管理")
            MZPage {
                ForEach(PaymentMethodType.visibleOrder, id: \.self) { type in
                    MZCard(spacing: 0) {
                        Text(type.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(MZTheme.ink)
                            .padding(.bottom, 6)
                        let methods = store.userVisibleMethods.filter { $0.methodType == type }
                        if methods.isEmpty {
                            MZEmptyState(title: "暂无\(type.displayName)", systemImage: "wallet.pass")
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(Array(methods.enumerated()), id: \.element.id) { index, method in
                                NavigationLink {
                                    PaymentMethodEditView(method: method, initialType: type)
                                } label: {
                                    paymentMethodRow(method)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("payment_method_row_\(method.name)")
                                if index < methods.count - 1 {
                                    MZDivider()
                                }
                            }
                            MZDivider()
                        }
                        Button {
                            createType = type
                        } label: {
                            addMethodRow(type)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("payment_method_add_\(type.rawValue)")
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .sheet(item: $createType) { type in
            NavigationStack {
                PaymentMethodEditView(method: nil, initialType: type)
                    .environmentObject(store)
            }
        }
    }

    private func paymentMethodRow(_ method: PaymentMethod) -> some View {
        HStack(spacing: 12) {
            Text(method.name)
                .font(.subheadline)
                .foregroundStyle(MZTheme.ink)
            Spacer()
            Text(method.isActive ? "启用" : "停用")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(method.isActive ? MZTheme.ink : MZTheme.tertiaryInk)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MZTheme.secondaryInk)
        }
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func addMethodRow(_ type: PaymentMethodType) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.headline.weight(.semibold))
            Text("新增\(type.displayName)")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(MZTheme.secondaryInk)
        }
        .foregroundStyle(MZTheme.accent)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
        .opacity(0.72)
    }
}

struct PaymentTypesSettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingCreateType = false
    @State private var createDetailType: PaymentType?

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "收付类型与明细", trailingSystemImage: "plus", trailingAccessibilityIdentifier: "payment_type_add", trailingAction: {
                isShowingCreateType = true
            })
            MZPage {
                Text("会计要素 → 收付类型 → 类型明细")
                    .font(.caption)
                    .foregroundStyle(MZTheme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .center)

                MZCard(spacing: 0) {
                    ForEach(Array(AccountingElement.visibleOrder.enumerated()), id: \.element) { elementIndex, element in
                        typeTreeElementRow(element)
                        let types = store.types.filter { $0.element == element }
                        if types.isEmpty {
                            Text("暂无\(element.displayName)类型")
                                .font(.footnote)
                                .foregroundStyle(MZTheme.secondaryInk)
                                .padding(.leading, 34)
                                .frame(minHeight: 36)
                        } else {
                            ForEach(Array(types.enumerated()), id: \.element.id) { _, type in
                                NavigationLink {
                                    PaymentTypeEditView(type: type)
                                } label: {
                                    typeTreeTypeRow(type)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("payment_type_row_\(type.name)")
                                let details = store.details.filter { $0.paymentTypeId == type.id }
                                ForEach(details) { detail in
                                    NavigationLink {
                                        TypeDetailEditView(type: type, detail: detail)
                                    } label: {
                                        typeTreeDetailRow(detail)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("payment_detail_row_\(detail.name)")
                                }
                                Button {
                                    createDetailType = type
                                } label: {
                                    addDetailRow(type)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("payment_detail_add_\(type.name)")
                            }
                        }
                        if elementIndex < AccountingElement.visibleOrder.count - 1 {
                            MZDivider()
                        }
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $isShowingCreateType) {
            NavigationStack {
                PaymentTypeEditView(type: nil)
                    .environmentObject(store)
            }
        }
        .sheet(item: $createDetailType) { type in
            NavigationStack {
                TypeDetailEditView(type: type, detail: nil)
                    .environmentObject(store)
            }
        }
    }

    private func typeTreeElementRow(_ element: AccountingElement) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
            Text(element.displayName)
                .font(.headline.weight(.bold))
            Spacer()
            Image(systemName: "ellipsis")
                .font(.headline.weight(.bold))
        }
        .foregroundStyle(MZTheme.ink)
        .frame(minHeight: 42)
    }

    private func typeTreeTypeRow(_ type: PaymentType) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 12)
            Rectangle()
                .fill(MZTheme.line)
                .frame(width: 1, height: 36)
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
            Text(type.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(type.isActive ? MZTheme.ink : MZTheme.tertiaryInk)
            Spacer()
            Text(type.isActive ? "启用" : "停用")
                .font(.caption.weight(.semibold))
                .foregroundStyle(type.isActive ? MZTheme.secondaryInk : MZTheme.tertiaryInk)
            Image(systemName: "chevron.right")
                .font(.headline.weight(.bold))
        }
        .frame(minHeight: 40)
    }

    private func typeTreeDetailRow(_ detail: PaymentDetail) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 34)
            Rectangle()
                .fill(MZTheme.line)
                .frame(width: 1, height: 38)
            Text(detail.name)
                .font(.subheadline)
                .foregroundStyle(detail.isActive ? MZTheme.ink : MZTheme.tertiaryInk)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.headline.weight(.bold))
                .foregroundStyle(MZTheme.ink)
        }
        .padding(.leading, 2)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }

    private func addDetailRow(_ type: PaymentType) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 34)
            Rectangle()
                .fill(MZTheme.line)
                .frame(width: 1, height: 38)
            Image(systemName: "plus")
                .font(.caption.weight(.bold))
            Text("新增\(type.name)明细")
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(MZTheme.accent)
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }
}

struct PaymentMethodEditView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let method: PaymentMethod?
    @State private var name: String
    @State private var methodTypeName: String
    @State private var semanticTagsText: String

    init(method: PaymentMethod?, initialType: PaymentMethodType) {
        self.method = method
        _name = State(initialValue: method?.name ?? "")
        _methodTypeName = State(initialValue: (method?.methodType ?? initialType).displayName)
        _semanticTagsText = State(initialValue: (method?.semanticTags ?? initialType.defaultSemanticTags).joined(separator: "，"))
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: method == nil ? "新增收付手段" : "编辑收付手段", trailingTitle: "保存", trailingAccessibilityIdentifier: "payment_method_save", trailingAction: save)
            MZPage {
                MZCard(spacing: 0) {
                    MZFieldRow(title: "名称", required: true) {
                        TextField("收付手段名称", text: $name)
                            .accessibilityIdentifier("payment_method_name_field")
                    }
                    MZDivider()
                    MZMenuRow(title: "属性", required: true, selection: $methodTypeName, options: PaymentMethodType.visibleOrder.map(\.displayName))
                        .accessibilityIdentifier("payment_method_type_picker")
                    MZDivider()
                    MZFieldRow(title: "状态") {
                        Text(method?.isActive == false ? "停用" : "启用")
                            .foregroundStyle(method?.isActive == false ? MZTheme.tertiaryInk : MZTheme.ink)
                    }
                }

                MZCard {
                    Text("语义标签")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    TextField("多个标签用逗号分隔", text: $semanticTagsText)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("payment_method_semantic_tags_field")
                }

                if let method, method.isActive {
                    MZLightButton(title: "停用此收付手段", systemImage: "pause.circle") {
                        if store.disablePaymentMethod(id: method.id) {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("payment_method_disable")
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }

    private func save() {
        guard let selectedType = PaymentMethodType.visibleOrder.first(where: { $0.displayName == methodTypeName }) else { return }
        let tags = parseSemanticTags(semanticTagsText)
        let ok: Bool
        if let method {
            ok = store.updatePaymentMethod(id: method.id, input: UpdatePaymentMethodInput(name: name, methodType: selectedType, semanticTags: tags))
        } else {
            ok = store.createPaymentMethod(input: CreatePaymentMethodInput(name: name, methodType: selectedType, semanticTags: tags))
        }
        if ok {
            dismiss()
        }
    }
}

struct PaymentTypeEditView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let type: PaymentType?
    @State private var name: String
    @State private var elementName: String
    @State private var semanticTagsText: String
    @State private var configDescription: String

    init(type: PaymentType?) {
        self.type = type
        _name = State(initialValue: type?.name ?? "")
        _elementName = State(initialValue: (type?.element ?? .expense).displayName)
        _semanticTagsText = State(initialValue: (type?.semanticTags ?? [AccountingElement.expense.defaultSemanticTag]).joined(separator: "，"))
        _configDescription = State(initialValue: type?.configDescription ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: type == nil ? "新增收付类型" : "编辑收付类型", trailingTitle: "保存", trailingAccessibilityIdentifier: "payment_type_save", trailingAction: save)
            MZPage {
                MZCard(spacing: 0) {
                    MZFieldRow(title: "名称", required: true) {
                        TextField("收付类型名称", text: $name)
                            .accessibilityIdentifier("payment_type_name_field")
                    }
                    MZDivider()
                    MZMenuRow(title: "会计要素", required: true, selection: $elementName, options: AccountingElement.visibleOrder.map(\.displayName))
                        .accessibilityIdentifier("payment_type_element_picker")
                    MZDivider()
                    MZFieldRow(title: "状态") {
                        Text(type?.isActive == false ? "停用" : "启用")
                            .foregroundStyle(type?.isActive == false ? MZTheme.tertiaryInk : MZTheme.ink)
                    }
                }

                MZCard {
                    Text("语义标签")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    TextField("多个标签用逗号分隔", text: $semanticTagsText)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("payment_type_semantic_tags_field")
                    TextField("语义描述", text: $configDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("payment_type_description_field")
                }

                if let type, type.isActive {
                    MZLightButton(title: "停用此收付类型", systemImage: "pause.circle") {
                        if store.disablePaymentType(id: type.id) {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("payment_type_disable")
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }

    private func save() {
        guard let element = AccountingElement.visibleOrder.first(where: { $0.displayName == elementName }) else { return }
        let tags = parseSemanticTags(semanticTagsText)
        let ok: Bool
        if let type {
            ok = store.updatePaymentType(
                id: type.id,
                input: UpdatePaymentTypeInput(name: name, element: element, semanticTags: tags, configDescription: configDescription)
            )
        } else {
            ok = store.createPaymentType(
                input: CreatePaymentTypeInput(name: name, element: element, semanticTags: tags, configDescription: configDescription)
            )
        }
        if ok {
            dismiss()
        }
    }
}

struct TypeDetailEditView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let type: PaymentType
    let detail: PaymentDetail?
    @State private var name: String
    @State private var paymentTypeName: String
    @State private var semanticTagsText: String
    @State private var configDescription: String

    init(type: PaymentType, detail: PaymentDetail?) {
        self.type = type
        self.detail = detail
        _name = State(initialValue: detail?.name ?? "")
        _paymentTypeName = State(initialValue: type.name)
        _semanticTagsText = State(initialValue: (detail?.semanticTags ?? []).joined(separator: "，"))
        _configDescription = State(initialValue: detail?.configDescription ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: detail == nil ? "新增类型明细" : "类型明细编辑", trailingTitle: "保存", trailingAccessibilityIdentifier: "payment_detail_save", trailingAction: save)
            MZPage {
                MZCard(spacing: 0) {
                    MZFieldRow(title: "名称", required: true) {
                        TextField("类型明细名称", text: $name)
                            .accessibilityIdentifier("payment_detail_name_field")
                    }
                    MZDivider()
                    MZMenuRow(title: "所属类型", required: true, selection: $paymentTypeName, options: paymentTypeOptions)
                        .accessibilityIdentifier("payment_detail_type_picker")
                    MZDivider()
                    SummaryLine(title: "层级", value: "类型明细")
                    MZDivider()
                    SummaryLine(title: "状态", value: detail?.isActive == false ? "停用" : "启用")
                }

                MZCard {
                    Text("语义描述（自然语言）")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    TextField("语义描述", text: $configDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("payment_detail_description_field")
                    TextField("语义标签，多个标签用逗号分隔", text: $semanticTagsText)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("payment_detail_semantic_tags_field")
                    Text("\(configDescription.count)/200")
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                MZInfoCallout(text: "语义描述用于帮助理解类型明细含义，不是自动规则中心。")

                if let detail, detail.isActive {
                    MZLightButton(title: "停用此类型明细", systemImage: "pause.circle") {
                        if store.disablePaymentDetail(id: detail.id) {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("payment_detail_disable")
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }

    private var paymentTypeOptions: [String] {
        var names = store.activePaymentTypes.map(\.name)
        if !names.contains(paymentTypeName) {
            names.append(paymentTypeName)
        }
        return names
    }

    private func save() {
        guard let selectedType = store.types.first(where: { $0.name == paymentTypeName }) else { return }
        let tags = parseSemanticTags(semanticTagsText)
        let ok: Bool
        if let detail {
            ok = store.updatePaymentDetail(
                id: detail.id,
                input: UpdatePaymentDetailInput(
                    name: name,
                    paymentTypeId: selectedType.id,
                    semanticTags: tags,
                    configDescription: configDescription
                )
            )
        } else {
            ok = store.createPaymentDetail(
                input: CreatePaymentDetailInput(
                    name: name,
                    paymentTypeId: selectedType.id,
                    semanticTags: tags,
                    configDescription: configDescription
                )
            )
        }
        if ok {
            dismiss()
        }
    }
}

private func parseSemanticTags(_ value: String) -> [String] {
    var seen: Set<String> = []
    var tags: [String] = []
    for raw in value
        .replacingOccurrences(of: "，", with: ",")
        .split(separator: ",", omittingEmptySubsequences: true) {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty, !seen.contains(tag) else { continue }
        seen.insert(tag)
        tags.append(tag)
    }
    return tags
}

struct DataExportBackupView: View {
    @EnvironmentObject private var store: LedgerStore

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "数据导出")
            MZPage {
                MZCard {
                    Text("导出审计数据")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    Text("生成 UTF-8 CSV，包含流水、来源和追溯字段。")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                    MZLightButton(title: "导出审计 CSV", systemImage: "doc.text") {
                        _ = store.exportAuditData()
                    }
                    .accessibilityIdentifier("audit_export_button")

                    if let url = store.auditExportURL {
                        ShareLink(item: url) {
                            MZIconRow(title: "分享审计 CSV", subtitle: url.lastPathComponent, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("audit_export_share")
                    }
                }

                MZCard {
                    Text("完整备份")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    Text("生成 .mzbackup 文件，包含配置、流水、导入候选和投资明细。")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                    MZLightButton(title: "创建完整备份", systemImage: "externaldrive") {
                        _ = store.createBackupPackage()
                    }
                    .accessibilityIdentifier("backup_create_button")

                    if let validation = store.backupValidation, validation.isValid, let manifest = validation.manifest {
                        MZDivider()
                        BackupManifestSummaryView(manifest: manifest)
                    }

                    if let url = store.backupPackageURL {
                        ShareLink(item: url) {
                            MZIconRow(title: "分享备份文件", subtitle: url.lastPathComponent, systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("backup_share_button")
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

struct DataRestoreView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var isShowingImporter = false

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "数据恢复")
            MZPage {
                MZCard {
                    Text("选择备份文件")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    Text("仅支持新明账 .mzbackup 或 JSON 备份文件。")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)

                    MZLightButton(title: "选择备份文件", systemImage: "folder") {
                        isShowingImporter = true
                    }
                    .accessibilityIdentifier("restore_file_picker_button")

                    if store.isUITesting {
                        HStack(spacing: 10) {
                            MZLightButton(title: "测试有效备份", systemImage: "checkmark.seal") {
                                _ = store.prepareUITestRestoreBackup(valid: true)
                            }
                            .accessibilityIdentifier("restore_test_valid_backup_button")
                            MZLightButton(title: "测试坏备份", systemImage: "xmark.octagon") {
                                _ = store.prepareUITestRestoreBackup(valid: false)
                            }
                            .accessibilityIdentifier("restore_test_invalid_backup_button")
                        }
                    }
                }

                if let fileName = store.pendingBackupFileName {
                    MZCard {
                        SummaryLine(title: "文件", value: fileName)
                    }
                }

                if let validation = store.backupValidation {
                    if validation.isValid, let manifest = validation.manifest {
                        MZCard {
                            Text("校验通过")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MZTheme.ink)
                            BackupManifestSummaryView(manifest: manifest)
                            NavigationLink {
                                DataRestoreConfirmView()
                            } label: {
                                MZIconRow(title: "进入恢复确认", subtitle: "恢复会覆盖当前本机账本", systemImage: "arrow.clockwise", tint: MZTheme.danger)
                            }
                            .accessibilityIdentifier("restore_preview_button")
                        }
                    } else {
                        MZCard {
                            Text("校验失败")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(MZTheme.danger)
                            ForEach(validation.errors, id: \.self) { error in
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(MZTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityIdentifier("restore_validation_failed")
                    }
                }
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: backupContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    _ = store.validateBackupFile(at: url)
                }
            case .failure(let error):
                store.lastError = error.localizedDescription
            }
        }
    }

    private var backupContentTypes: [UTType] {
        [UTType(filenameExtension: "mzbackup"), .json]
            .compactMap { $0 }
    }
}

struct DataRestoreConfirmView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var confirmText = ""
    @State private var isShowingResult = false
    private let requiredText = "恢复数据 继续"

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "恢复前确认")
            MZPage {
                MZCard {
                    Text("覆盖当前本机账本")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MZTheme.danger)
                    Text("恢复会替换当前配置、流水、导入候选和投资明细。恢复失败时当前数据不会被修改。")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let manifest = store.backupValidation?.manifest {
                    MZCard {
                        BackupManifestSummaryView(manifest: manifest)
                    }
                }

                MZCard {
                    Text("请输入以下文字以确认操作")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    MZFieldRow(title: "确认文字") {
                        TextField("输入 \(requiredText)", text: $confirmText, axis: .vertical)
                            .lineLimit(2, reservesSpace: true)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(MZTheme.card)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(MZTheme.line, lineWidth: 0.8)
                            )
                            .accessibilityIdentifier("restore_confirm_text_field")
                    }
                    Text("\(confirmText.count)/\(requiredText.count)")
                        .font(.caption)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                MZDestructiveButton(title: "确认恢复", isDisabled: confirmText != requiredText) {
                    _ = store.restoreValidatedBackup()
                    isShowingResult = true
                }
                .accessibilityIdentifier("restore_confirm_button")
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $isShowingResult) {
            DataRestoreResultView()
                .environmentObject(store)
        }
    }
}

struct DataRestoreResultView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "恢复结果")
            MZPage {
                if let result = store.restoreResult {
                    MZCard {
                        MZEmptyState(title: "恢复完成", systemImage: "checkmark.circle", subtitle: "核心账本、配置和追溯信息已恢复。")
                        BackupRecordCountsView(counts: result.recordCounts)
                        SummaryLine(title: "可用账月", value: result.restoredAccountMonths.joined(separator: "、"))
                    }
                    .accessibilityIdentifier("restore_result_success")
                } else {
                    MZCard {
                        MZEmptyState(
                            title: "恢复失败",
                            systemImage: "xmark.octagon",
                            subtitle: store.restoreFailureMessage ?? "恢复失败，当前数据未被修改。"
                        )
                    }
                    .accessibilityIdentifier("restore_result_failure")
                }

                MZLightButton(title: "完成", systemImage: "checkmark") {
                    dismiss()
                }
                .accessibilityIdentifier("restore_result_done_button")
            }
        }
        .background(MZTheme.page)
        .navigationBarBackButtonHidden(true)
    }
}

private struct BackupManifestSummaryView: View {
    let manifest: BackupManifest

    var body: some View {
        VStack(spacing: 8) {
            SummaryLine(title: "备份版本", value: "\(manifest.backupSchemaVersion)")
            SummaryLine(title: "数据版本", value: manifest.appDataSchemaVersion)
            SummaryLine(title: "导出时间", value: manifest.exportedAt.fullText)
            SummaryLine(title: "校验", value: manifest.payloadChecksum)
            BackupRecordCountsView(counts: manifest.recordCounts)
        }
    }
}

private struct BackupRecordCountsView: View {
    let counts: BackupRecordCounts

    var body: some View {
        VStack(spacing: 6) {
            SummaryLine(title: "配置", value: "\(counts.paymentMethods + counts.paymentTypes + counts.paymentDetails)")
            SummaryLine(title: "流水", value: "\(counts.journalRecords)")
            SummaryLine(title: "导入批次", value: "\(counts.importBatches)")
            SummaryLine(title: "导入候选", value: "\(counts.importCandidates)")
            SummaryLine(title: "投资交易", value: "\(counts.investmentTransactions)")
        }
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
    private let requiredText = "清空数据 继续"

    var body: some View {
        VStack(spacing: 0) {
            MZBackHeader(title: "数据清空确认")
            MZPage {
                MZCard {
                    Text("清空全部数据")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MZTheme.danger)
                    Text("此操作将删除所有账户、科目、流水及相关数据，且无法恢复。")
                        .font(.subheadline)
                        .foregroundStyle(MZTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                MZCard {
                    Text("建议操作")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    VStack(alignment: .leading, spacing: 10) {
                        Label("请先导出数据备份文件", systemImage: "circle.fill")
                        Label("确认不再需要当前数据", systemImage: "circle.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(MZTheme.secondaryInk)
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
                }

                MZCard {
                    Text("请输入以下文字以确认操作")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(MZTheme.ink)
                    MZFieldRow(title: "确认文字") {
                        ZStack(alignment: .bottomTrailing) {
                            TextField("输入 \(requiredText)", text: $confirmText, axis: .vertical)
                                .lineLimit(3, reservesSpace: true)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(MZTheme.card)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(MZTheme.line, lineWidth: 0.8)
                                )
                            Text("\(confirmText.count)/\(requiredText.count)")
                                .font(.caption)
                                .foregroundStyle(MZTheme.secondaryInk)
                                .padding(10)
                        }
                    }
                }

                MZLightButton(title: "先导出数据", systemImage: "square.and.arrow.up") {}
                    .disabled(true)
                    .accessibilityIdentifier("data_clear_export_button")

                MZDestructiveButton(title: "确认清空", isDisabled: confirmText != requiredText) {}
                    .accessibilityIdentifier("data_clear_confirm_button")
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
        .font(.subheadline)
        .frame(minHeight: 30)
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

    func percentText(of total: Decimal) -> String {
        guard total.doubleValue != 0 else { return "0.0%" }
        return String(format: "%.1f%%", doubleValue / total.doubleValue * 100)
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

    var monthDateRangeText: String {
        let parts = split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return self }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let firstDay = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstDay),
              let lastDay = calendar.date(byAdding: .day, value: range.count - 1, to: firstDay) else {
            return self
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: firstDay)) ~ \(formatter.string(from: lastDay))"
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

private extension InvestmentHolding {
    var latestNAVText: String {
        latestNav?.moneyText ?? "-"
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

    var systemImage: String {
        switch self {
        case .buy:
            return "plus.circle"
        case .sell:
            return "minus.circle"
        case .nav:
            return "chart.line.uptrend.xyaxis"
        }
    }
}

private extension InvestmentTransaction {
    var traceAmountText: String {
        if let bookAmount {
            return bookAmount.moneyText
        }
        if let tradeAmount {
            return tradeAmount.moneyText
        }
        if let nav {
            return nav.moneyText
        }
        return "-"
    }

    var sourceExplanationText: String {
        switch transactionType {
        case .buy:
            return "买入金额 \(tradeAmount?.moneyText ?? "-") / 份额 \(tradeShare?.moneyText ?? "-")"
        case .sell:
            let shareText = tradeShare.map { $0.absoluteValue.moneyText } ?? "-"
            return "卖出按平均成本法入账 \(bookAmount?.moneyText ?? "-") / 份额 \(shareText)"
        case .nav:
            return "净值 \(nav?.moneyText ?? "-") / 持仓份额 \(holdingShare.moneyText)"
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

extension PaymentMethodType: @retroactive Identifiable {
    public var id: String { rawValue }
}

private extension PaymentMethodType {
    static let visibleOrder: [PaymentMethodType] = [.asset, .liability, .accounting]

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

    var defaultSemanticTags: [String] {
        switch self {
        case .asset:
            return ["资产型"]
        case .liability:
            return ["负债型"]
        case .accounting:
            return ["账务处理型"]
        case .pendingRealAccount:
            return ["待补真实账户"]
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

    var defaultSemanticTag: String {
        displayName
    }
}
