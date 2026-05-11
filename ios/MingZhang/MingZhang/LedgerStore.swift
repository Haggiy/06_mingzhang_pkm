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
    @Published private(set) var statisticsSummary = StatisticsSummary(expenseByType: [], sourceRecordIds: [])
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

    func querySourceRecords(recordIds: [UUID]) throws -> [JournalRecord] {
        guard let useCases else { return [] }
        return try useCases.queryJournalRecords(recordIds: recordIds)
    }

    func createRecord(input: JournalFormInput) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.createManualRecord(input: try input.toCreateInput())
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updateRecord(id: UUID, input: JournalFormInput) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.updateJournalRecord(
                id: id,
                changes: try input.toChanges()
            )
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func deleteRecord(id: UUID) -> Bool {
        do {
            guard let useCases else { return false }
            try useCases.deleteJournalRecord(id: id)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
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

    func parsedAmount() throws -> Decimal {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MingZhangError.validation("金额不能为空")
        }
        guard let amount = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MingZhangError.validation("金额必须是有效数字")
        }
        guard amount != Decimal(0) else {
            throw MingZhangError.validation("金额不能为 0")
        }
        return amount
    }

    func toCreateInput() throws -> CreateManualRecordInput {
        try validateRequiredFields()
        return CreateManualRecordInput(
            accountMonth: accountMonth,
            occurredAt: occurredAt,
            paymentMethodName: paymentMethodName,
            amount: try parsedAmount(),
            paymentTypeName: paymentTypeName,
            paymentDetailName: paymentDetailName,
            note: note.isEmpty ? nil : note
        )
    }

    func toChanges() throws -> JournalRecordChanges {
        try validateRequiredFields()
        return JournalRecordChanges(
            accountMonth: accountMonth,
            occurredAt: occurredAt,
            paymentMethodName: paymentMethodName,
            amount: try parsedAmount(),
            paymentTypeName: paymentTypeName,
            paymentDetailName: paymentDetailName,
            note: note
        )
    }

    private func validateRequiredFields() throws {
        if accountMonth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("账月不能为空")
        }
        if paymentMethodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("收付手段不能为空")
        }
        if paymentTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("收付类型不能为空")
        }
        if paymentDetailName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("类型明细不能为空")
        }
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
