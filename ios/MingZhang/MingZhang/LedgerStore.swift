import Foundation
import Combine
import MingZhangCore

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var accountMonth = "2026-04"
    @Published private(set) var records: [JournalRecord] = []
    @Published private(set) var methods: [PaymentMethod] = []
    @Published private(set) var types: [PaymentType] = []
    @Published private(set) var details: [PaymentDetail] = []
    @Published private(set) var homeSummary = HomeSummary(incomeTotal: 0, expenseTotal: 0, balance: 0, recentRecordIds: [])
    @Published private(set) var balanceSummary = BalanceSummary(cashBalance: 0, liabilityItems: [])
    @Published private(set) var statisticsSummary = StatisticsSummary(expenseByType: [:], sourceRecordIds: [])
    @Published var lastError: String?

    private var useCases: LedgerUseCases?

    func bootstrap() async {
        do {
            let databaseURL = try Self.databaseURL()
            let database = try LedgerDatabase.fileBacked(at: databaseURL)
            let useCases = LedgerUseCases(database: database)
            try useCases.initializeLedgerSeed()
            self.useCases = useCases
            try refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() throws {
        guard let useCases else { return }
        methods = try useCases.queryPaymentMethods()
        types = try useCases.queryPaymentTypes()
        details = try useCases.queryPaymentDetails()
        records = try useCases.queryJournalRecords(filter: JournalRecordFilter(accountMonths: [accountMonth]))
        homeSummary = try useCases.queryHomeSummary(accountMonth: accountMonth)
        balanceSummary = try useCases.queryBalanceSummary(accountMonth: accountMonth)
        statisticsSummary = try useCases.queryStatisticsSummary(accountMonth: accountMonth)
        lastError = nil
    }

    func createRecord(input: JournalFormInput) {
        do {
            guard let useCases else { return }
            _ = try useCases.createManualRecord(input: input.toCreateInput())
            try refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateRecord(id: UUID, input: JournalFormInput) {
        do {
            guard let useCases else { return }
            _ = try useCases.updateJournalRecord(
                id: id,
                changes: JournalRecordChanges(
                    accountMonth: input.accountMonth,
                    occurredAt: input.occurredAt,
                    paymentMethodName: input.paymentMethodName,
                    amount: input.amount,
                    paymentTypeName: input.paymentTypeName,
                    paymentDetailName: input.paymentDetailName,
                    note: input.note
                )
            )
            try refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func deleteRecord(id: UUID) {
        do {
            guard let useCases else { return }
            try useCases.deleteJournalRecord(id: id)
            try refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func databaseURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent("MingZhang.sqlite")
    }
}

struct JournalFormInput: Equatable {
    var accountMonth: String
    var occurredAt: Date
    var paymentMethodName: String
    var amountText: String
    var paymentTypeName: String
    var paymentDetailName: String
    var note: String

    var amount: Decimal {
        Decimal(string: amountText, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    func toCreateInput() -> CreateManualRecordInput {
        CreateManualRecordInput(
            accountMonth: accountMonth,
            occurredAt: occurredAt,
            paymentMethodName: paymentMethodName,
            amount: amount,
            paymentTypeName: paymentTypeName,
            paymentDetailName: paymentDetailName,
            note: note.isEmpty ? nil : note
        )
    }

    static func p0Default(now: Date = Date()) -> JournalFormInput {
        JournalFormInput(
            accountMonth: "2026-04",
            occurredAt: now,
            paymentMethodName: "广发卡",
            amountText: "100",
            paymentTypeName: "生活必要开支",
            paymentDetailName: "伙食费",
            note: "午餐"
        )
    }

    static func from(record: JournalRecord) -> JournalFormInput {
        JournalFormInput(
            accountMonth: record.accountMonth,
            occurredAt: record.occurredAt,
            paymentMethodName: record.paymentMethodName,
            amountText: NSDecimalNumber(decimal: record.amount).stringValue,
            paymentTypeName: record.paymentTypeName,
            paymentDetailName: record.paymentDetailName,
            note: record.note ?? ""
        )
    }
}
