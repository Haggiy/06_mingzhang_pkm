import Foundation
import GRDB

public enum MingZhangError: Error, Equatable {
    case missingSeed(String)
    case recordNotFound(UUID)
    case recordNotEditable(UUID)
    case invalidDate(String)
}

public enum PaymentMethodType: String, Codable, Equatable, Sendable {
    case asset
    case liability
    case accounting
    case pendingRealAccount = "pending_real_account"
}

public enum AccountingElement: String, Codable, Equatable, Sendable {
    case asset
    case liability
    case income
    case expense
}

public enum RecordSource: String, Codable, Equatable, Sendable {
    case manual
    case `import`
    case investmentFeed = "investment_feed"
    case engine

    var triggersEngine: Bool {
        self != .engine
    }
}

public enum RecordKind: String, Codable, Equatable, Sendable {
    case normal
    case carryForward = "carry_forward"
}

public enum CarryForwardRole: String, Codable, Equatable, Sendable {
    case none
    case accountingSkeleton = "accounting_skeleton"
    case recurringRecord = "recurring_record"
}

public enum EngineFamily: String, Codable, Equatable, Sendable {
    case cash
    case liability
    case deferred
    case investment
}

public enum MutationType: String, Codable, Equatable, Sendable {
    case create
    case update
    case delete
    case investmentReflow = "investment_reflow"
    case configChange = "config_change"
}

public struct PaymentMethod: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var methodType: PaymentMethodType
    public var isActive: Bool
}

public struct PaymentType: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var element: AccountingElement
    public var isActive: Bool
}

public struct PaymentDetail: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var paymentTypeId: UUID
    public var isActive: Bool
}

public struct JournalRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var accountMonth: String
    public var occurredAt: Date
    public var paymentMethodId: UUID
    public var paymentMethodName: String
    public var amount: Decimal
    public var paymentTypeId: UUID
    public var paymentTypeName: String
    public var paymentDetailId: UUID
    public var paymentDetailName: String
    public var note: String?
    public var recordSource: RecordSource
    public var recordKind: RecordKind
    public var carryForwardRole: CarryForwardRole
    public var engineFamily: EngineFamily?
    public var engineKey: String?
    public var objectKey: String?
    public var sourceRecordIds: [UUID]
    public var createdAt: Date
    public var updatedAt: Date
}

public struct CreateManualRecordInput: Equatable, Sendable {
    public var accountMonth: String
    public var occurredAt: Date
    public var paymentMethodName: String
    public var amount: Decimal
    public var paymentTypeName: String
    public var paymentDetailName: String
    public var note: String?

    public init(
        accountMonth: String,
        occurredAt: Date,
        paymentMethodName: String,
        amount: Decimal,
        paymentTypeName: String,
        paymentDetailName: String,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.paymentMethodName = paymentMethodName
        self.amount = amount
        self.paymentTypeName = paymentTypeName
        self.paymentDetailName = paymentDetailName
        self.note = note
    }
}

public struct JournalRecordChanges: Equatable, Sendable {
    public var accountMonth: String?
    public var occurredAt: Date?
    public var paymentMethodName: String?
    public var amount: Decimal?
    public var paymentTypeName: String?
    public var paymentDetailName: String?
    public var note: String?

    public init(
        accountMonth: String? = nil,
        occurredAt: Date? = nil,
        paymentMethodName: String? = nil,
        amount: Decimal? = nil,
        paymentTypeName: String? = nil,
        paymentDetailName: String? = nil,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.paymentMethodName = paymentMethodName
        self.amount = amount
        self.paymentTypeName = paymentTypeName
        self.paymentDetailName = paymentDetailName
        self.note = note
    }
}

public struct JournalRecordFilter: Equatable, Sendable {
    public var accountMonths: [String]
    public var includeEngineRecords: Bool

    public init(accountMonths: [String], includeEngineRecords: Bool = false) {
        self.accountMonths = accountMonths
        self.includeEngineRecords = includeEngineRecords
    }
}

public struct HomeSummary: Equatable, Sendable {
    public var incomeTotal: Decimal
    public var expenseTotal: Decimal
    public var balance: Decimal
    public var recentRecordIds: [UUID]

    public init(incomeTotal: Decimal, expenseTotal: Decimal, balance: Decimal, recentRecordIds: [UUID]) {
        self.incomeTotal = incomeTotal
        self.expenseTotal = expenseTotal
        self.balance = balance
        self.recentRecordIds = recentRecordIds
    }
}

public struct BalanceItem: Equatable, Sendable {
    public var name: String
    public var amount: Decimal
    public var sourceRecordIds: [UUID]

    public init(name: String, amount: Decimal, sourceRecordIds: [UUID]) {
        self.name = name
        self.amount = amount
        self.sourceRecordIds = sourceRecordIds
    }
}

public struct BalanceSummary: Equatable, Sendable {
    public var cashBalance: Decimal
    public var cashSourceRecordIds: [UUID]
    public var liabilityItems: [BalanceItem]

    public init(cashBalance: Decimal, cashSourceRecordIds: [UUID] = [], liabilityItems: [BalanceItem]) {
        self.cashBalance = cashBalance
        self.cashSourceRecordIds = cashSourceRecordIds
        self.liabilityItems = liabilityItems
    }
}

public struct ExpenseTypeSummary: Equatable, Sendable {
    public var typeName: String
    public var amount: Decimal
    public var sourceRecordIds: [UUID]

    public init(typeName: String, amount: Decimal, sourceRecordIds: [UUID]) {
        self.typeName = typeName
        self.amount = amount
        self.sourceRecordIds = sourceRecordIds
    }
}

public struct StatisticsSummary: Equatable, Sendable {
    public var expenseByType: [ExpenseTypeSummary]
    public var sourceRecordIds: [UUID]

    public init(expenseByType: [ExpenseTypeSummary], sourceRecordIds: [UUID]) {
        self.expenseByType = expenseByType
        self.sourceRecordIds = sourceRecordIds
    }
}

public struct Mutation: Equatable, Sendable {
    public var recordId: UUID
    public var mutationType: MutationType

    public init(recordId: UUID, mutationType: MutationType) {
        self.recordId = recordId
        self.mutationType = mutationType
    }
}

public struct EngineRecalculationResult: Equatable, Sendable {
    public var recalculatedMonths: [String]
    public var createdEngineRecordIds: [UUID]
    public var updatedEngineRecordIds: [UUID]
    public var deletedEngineRecordIds: [UUID]
    public var warnings: [String]

    public static let empty = EngineRecalculationResult(
        recalculatedMonths: [],
        createdEngineRecordIds: [],
        updatedEngineRecordIds: [],
        deletedEngineRecordIds: [],
        warnings: []
    )
}

public final class LedgerDatabase: @unchecked Sendable {
    let writer: DatabaseWriter

    init(writer: DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    public static func inMemory() throws -> LedgerDatabase {
        try LedgerDatabase(writer: DatabaseQueue())
    }

    public static func fileBacked(at url: URL) throws -> LedgerDatabase {
        try LedgerDatabase(writer: DatabaseQueue(path: url.path))
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_p0_ledger") { db in
            try db.create(table: "payment_methods", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull().unique()
                table.column("method_type", .text).notNull()
                table.column("is_active", .boolean).notNull()
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "payment_types", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull().unique()
                table.column("element", .text).notNull()
                table.column("is_active", .boolean).notNull()
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(table: "payment_details", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("payment_type_id", .text).notNull().references("payment_types", onDelete: .restrict)
                table.column("is_active", .boolean).notNull()
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
                table.uniqueKey(["name", "payment_type_id"])
            }

            try db.create(table: "journal_records", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("account_month", .text).notNull().indexed()
                table.column("occurred_at", .text).notNull()
                table.column("payment_method_id", .text).notNull().references("payment_methods", onDelete: .restrict)
                table.column("amount", .text).notNull()
                table.column("payment_type_id", .text).notNull().references("payment_types", onDelete: .restrict)
                table.column("payment_detail_id", .text).notNull().references("payment_details", onDelete: .restrict)
                table.column("note", .text)
                table.column("record_source", .text).notNull().indexed()
                table.column("record_kind", .text).notNull()
                table.column("carry_forward_role", .text).notNull()
                table.column("engine_family", .text)
                table.column("engine_key", .text).unique()
                table.column("object_key", .text)
                table.column("source_record_ids", .text).notNull()
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
        return migrator
    }
}

public final class LedgerUseCases: @unchecked Sendable {
    private let database: LedgerDatabase

    public init(database: LedgerDatabase) {
        self.database = database
    }

    public func initializeLedgerSeed() throws {
        try database.writer.write { db in
            let now = Date()
            try insertPaymentMethodIfNeeded(db, name: "电子钱包余额", methodType: .asset, now: now)
            try insertPaymentMethodIfNeeded(db, name: "广发卡", methodType: .liability, now: now)
            try insertPaymentMethodIfNeeded(db, name: "账务处理", methodType: .accounting, now: now)

            let type = try insertPaymentTypeIfNeeded(db, name: "生活必要开支", element: .expense, now: now)
            try insertPaymentDetailIfNeeded(db, name: "伙食费", paymentTypeId: type.id, now: now)
        }
    }

    public func queryPaymentMethods() throws -> [PaymentMethod] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, method_type, is_active
                FROM payment_methods
                ORDER BY name
                """).map(paymentMethod(from:))
        }
    }

    public func queryPaymentTypes() throws -> [PaymentType] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, element, is_active
                FROM payment_types
                ORDER BY name
                """).map(paymentType(from:))
        }
    }

    public func queryPaymentDetails() throws -> [PaymentDetail] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, payment_type_id, is_active
                FROM payment_details
                ORDER BY name
                """).map(paymentDetail(from:))
        }
    }

    @discardableResult
    public func createManualRecord(input: CreateManualRecordInput) throws -> JournalRecord {
        let record = try database.writer.write { db in
            let method = try requirePaymentMethod(db, name: input.paymentMethodName)
            let type = try requirePaymentType(db, name: input.paymentTypeName)
            let detail = try requirePaymentDetail(db, name: input.paymentDetailName, paymentTypeId: type.id)
            let now = Date()
            let record = JournalRecord(
                id: UUID(),
                accountMonth: input.accountMonth,
                occurredAt: input.occurredAt,
                paymentMethodId: method.id,
                paymentMethodName: method.name,
                amount: input.amount,
                paymentTypeId: type.id,
                paymentTypeName: type.name,
                paymentDetailId: detail.id,
                paymentDetailName: detail.name,
                note: input.note,
                recordSource: .manual,
                recordKind: .normal,
                carryForwardRole: .none,
                engineFamily: nil,
                engineKey: nil,
                objectKey: nil,
                sourceRecordIds: [],
                createdAt: now,
                updatedAt: now
            )
            try insertJournalRecord(db, record: record)
            return record
        }

        _ = try recalculateAccountMonth(record.accountMonth)
        return record
    }

    @discardableResult
    public func updateJournalRecord(id: UUID, changes: JournalRecordChanges) throws -> JournalRecord {
        let updateContext = try database.writer.write { db in
            var record = try requireJournalRecord(db, id: id)
            guard record.recordSource == .manual || record.recordSource == .import else {
                throw MingZhangError.recordNotEditable(id)
            }

            let originalMonth = record.accountMonth
            if let accountMonth = changes.accountMonth {
                record.accountMonth = accountMonth
            }
            if let occurredAt = changes.occurredAt {
                record.occurredAt = occurredAt
            }
            if let paymentMethodName = changes.paymentMethodName {
                let method = try requirePaymentMethod(db, name: paymentMethodName)
                record.paymentMethodId = method.id
                record.paymentMethodName = method.name
            }
            if let amount = changes.amount {
                record.amount = amount
            }
            if let paymentTypeName = changes.paymentTypeName {
                let type = try requirePaymentType(db, name: paymentTypeName)
                record.paymentTypeId = type.id
                record.paymentTypeName = type.name
            }
            if let paymentDetailName = changes.paymentDetailName {
                let detail = try requirePaymentDetail(db, name: paymentDetailName, paymentTypeId: record.paymentTypeId)
                record.paymentDetailId = detail.id
                record.paymentDetailName = detail.name
            }
            if let note = changes.note {
                record.note = note
            }
            record.updatedAt = Date()
            try persistJournalRecordUpdate(db, record: record)
            return (record: record, originalMonth: originalMonth)
        }

        _ = try recalculateAccountMonth(updateContext.originalMonth)
        if updateContext.record.accountMonth != updateContext.originalMonth {
            _ = try recalculateAccountMonth(updateContext.record.accountMonth)
        }
        return updateContext.record
    }

    public func deleteJournalRecord(id: UUID) throws {
        let month = try database.writer.write { db in
            let record = try requireJournalRecord(db, id: id)
            guard record.recordSource == .manual || record.recordSource == .import else {
                throw MingZhangError.recordNotEditable(id)
            }
            try db.execute(sql: "DELETE FROM journal_records WHERE id = ?", arguments: [id.uuidString])
            return record.accountMonth
        }

        _ = try recalculateAccountMonth(month)
    }

    public func queryJournalRecords(filter: JournalRecordFilter) throws -> [JournalRecord] {
        try database.writer.read { db in
            var sql = selectJournalRecordSQL + " WHERE journal_records.account_month IN \(sqlPlaceholders(filter.accountMonths.count))"
            var arguments = StatementArguments(filter.accountMonths)
            if !filter.includeEngineRecords {
                sql += " AND journal_records.record_source != ?"
                arguments += [RecordSource.engine.rawValue]
            }
            sql += " ORDER BY journal_records.occurred_at ASC, journal_records.created_at ASC"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(journalRecord(from:))
        }
    }

    public func queryJournalRecords(recordIds: [UUID], includeEngineRecords: Bool = false) throws -> [JournalRecord] {
        guard !recordIds.isEmpty else { return [] }

        return try database.writer.read { db in
            var sql = selectJournalRecordSQL + " WHERE journal_records.id IN \(sqlPlaceholders(recordIds.count))"
            var arguments = StatementArguments(recordIds.map(\.uuidString))
            if !includeEngineRecords {
                sql += " AND journal_records.record_source != ?"
                arguments += [RecordSource.engine.rawValue]
            }

            let records = try Row.fetchAll(db, sql: sql, arguments: arguments).map(journalRecord(from:))
            let recordsById = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
            return recordIds.compactMap { recordsById[$0] }
        }
    }

    public func getJournalRecordDetail(id: UUID) throws -> JournalRecord {
        try database.writer.read { db in
            try requireJournalRecord(db, id: id)
        }
    }

    public func queryHomeSummary(accountMonth: String) throws -> HomeSummary {
        let rows = try sourceRecordsWithSemantics(accountMonth: accountMonth)
        let income = rows
            .filter { $0.paymentType.element == .income }
            .reduce(Decimal(0)) { $0 + $1.record.amount }
        let expense = rows
            .filter { $0.paymentType.element == .expense }
            .reduce(Decimal(0)) { $0 + $1.record.amount }
        let recent = rows
            .sorted { $0.record.occurredAt > $1.record.occurredAt }
            .prefix(5)
            .map(\.record.id)

        return HomeSummary(
            incomeTotal: income,
            expenseTotal: expense,
            balance: income - expense,
            recentRecordIds: Array(recent)
        )
    }

    public func queryBalanceSummary(accountMonth: String) throws -> BalanceSummary {
        let engineRecords = try queryJournalRecords(
            filter: JournalRecordFilter(accountMonths: [accountMonth], includeEngineRecords: true)
        ).filter { $0.recordSource == .engine }

        let cashBalance = engineRecords
            .filter { $0.engineFamily == .cash }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let cashSourceRecordIds = engineRecords
            .filter { $0.engineFamily == .cash }
            .flatMap(\.sourceRecordIds)
            .sorted { $0.uuidString < $1.uuidString }

        let liabilities = engineRecords
            .filter { $0.engineFamily == .liability }
            .map { record in
                BalanceItem(
                    name: record.objectKey?.replacingOccurrences(of: "liability:", with: "") ?? record.paymentMethodName,
                    amount: record.amount,
                    sourceRecordIds: record.sourceRecordIds
                )
            }
            .sorted { $0.name < $1.name }

        return BalanceSummary(
            cashBalance: cashBalance,
            cashSourceRecordIds: cashSourceRecordIds,
            liabilityItems: liabilities
        )
    }

    public func queryStatisticsSummary(accountMonth: String) throws -> StatisticsSummary {
        let rows = try sourceRecordsWithSemantics(accountMonth: accountMonth)
            .filter { $0.paymentType.element == .expense }

        var expenseByType: [String: Decimal] = [:]
        var sourceIdsByType: [String: [UUID]] = [:]
        var sourceRecordIds: [UUID] = []
        for row in rows {
            expenseByType[row.paymentType.name, default: Decimal(0)] += row.record.amount
            sourceIdsByType[row.paymentType.name, default: []].append(row.record.id)
            sourceRecordIds.append(row.record.id)
        }
        let expenseSummaries = expenseByType
            .filter { $0.value != Decimal(0) }
            .map { typeName, amount in
                ExpenseTypeSummary(
                    typeName: typeName,
                    amount: amount,
                    sourceRecordIds: (sourceIdsByType[typeName] ?? []).sorted { $0.uuidString < $1.uuidString }
                )
            }
            .sorted { $0.typeName < $1.typeName }

        return StatisticsSummary(
            expenseByType: expenseSummaries,
            sourceRecordIds: sourceRecordIds.sorted { $0.uuidString < $1.uuidString }
        )
    }

    public func recalculateAfterMutation(_ mutation: Mutation) throws -> EngineRecalculationResult {
        let record = try database.writer.read { db in
            try requireJournalRecord(db, id: mutation.recordId)
        }

        guard record.recordSource.triggersEngine else {
            return .empty
        }

        return try recalculateAccountMonth(record.accountMonth)
    }

    @discardableResult
    private func recalculateAccountMonth(_ accountMonth: String) throws -> EngineRecalculationResult {
        try database.writer.write { db in
            let deletedIds = try String.fetchAll(
                db,
                sql: "SELECT id FROM journal_records WHERE account_month = ? AND record_source = ?",
                arguments: [accountMonth, RecordSource.engine.rawValue]
            ).compactMap(UUID.init(uuidString:))

            try db.execute(
                sql: "DELETE FROM journal_records WHERE account_month = ? AND record_source = ?",
                arguments: [accountMonth, RecordSource.engine.rawValue]
            )

            let rows = try fetchSourceRecordsWithSemantics(db, accountMonth: accountMonth)
            let now = Date()
            let accountingMethod = try requirePaymentMethod(db, name: "账务处理")
            let defaultType = try requirePaymentType(db, name: "生活必要开支")
            let defaultDetail = try requirePaymentDetail(db, name: "伙食费", paymentTypeId: defaultType.id)
            var createdIds: [UUID] = []

            let liabilityGroups = Dictionary(grouping: rows) { row in
                row.paymentMethod.methodType == .liability && row.paymentType.element == .expense
                    ? row.paymentMethod.name
                    : ""
            }.filter { !$0.key.isEmpty }

            for (methodName, groupedRows) in liabilityGroups {
                let amount = groupedRows.reduce(Decimal(0)) { $0 + $1.record.amount }
                guard amount != Decimal(0) else { continue }
                let sourceIds = groupedRows.map(\.record.id).sorted { $0.uuidString < $1.uuidString }
                let id = UUID()
                let objectKey = "liability:\(methodName)"
                let engineKey = "\(accountMonth):liability:ending_balance:\(objectKey)"
                let record = JournalRecord(
                    id: id,
                    accountMonth: accountMonth,
                    occurredAt: monthEndPlaceholder(accountMonth),
                    paymentMethodId: accountingMethod.id,
                    paymentMethodName: accountingMethod.name,
                    amount: amount,
                    paymentTypeId: defaultType.id,
                    paymentTypeName: defaultType.name,
                    paymentDetailId: defaultDetail.id,
                    paymentDetailName: defaultDetail.name,
                    note: "\(methodName) 负债期末余额",
                    recordSource: .engine,
                    recordKind: .carryForward,
                    carryForwardRole: .accountingSkeleton,
                    engineFamily: .liability,
                    engineKey: engineKey,
                    objectKey: objectKey,
                    sourceRecordIds: sourceIds,
                    createdAt: now,
                    updatedAt: now
                )
                try insertJournalRecord(db, record: record)
                createdIds.append(id)
            }

            let cashRows = rows.filter {
                $0.paymentMethod.methodType == .asset && $0.paymentType.element == .expense
            }
            let cashAmount = cashRows.reduce(Decimal(0)) { $0 - $1.record.amount }
            if cashAmount != Decimal(0) {
                let sourceIds = cashRows.map(\.record.id).sorted { $0.uuidString < $1.uuidString }
                let id = UUID()
                let objectKey = "cash_pool:电子钱包余额"
                let record = JournalRecord(
                    id: id,
                    accountMonth: accountMonth,
                    occurredAt: monthEndPlaceholder(accountMonth),
                    paymentMethodId: accountingMethod.id,
                    paymentMethodName: accountingMethod.name,
                    amount: cashAmount,
                    paymentTypeId: defaultType.id,
                    paymentTypeName: defaultType.name,
                    paymentDetailId: defaultDetail.id,
                    paymentDetailName: defaultDetail.name,
                    note: "现金池期末余额",
                    recordSource: .engine,
                    recordKind: .carryForward,
                    carryForwardRole: .accountingSkeleton,
                    engineFamily: .cash,
                    engineKey: "\(accountMonth):cash:ending_balance:\(objectKey)",
                    objectKey: objectKey,
                    sourceRecordIds: sourceIds,
                    createdAt: now,
                    updatedAt: now
                )
                try insertJournalRecord(db, record: record)
                createdIds.append(id)
            }

            return EngineRecalculationResult(
                recalculatedMonths: [accountMonth],
                createdEngineRecordIds: createdIds,
                updatedEngineRecordIds: [],
                deletedEngineRecordIds: deletedIds,
                warnings: []
            )
        }
    }

    private func sourceRecordsWithSemantics(accountMonth: String) throws -> [SemanticRecordRow] {
        try database.writer.read { db in
            try fetchSourceRecordsWithSemantics(db, accountMonth: accountMonth)
        }
    }
}

private struct SemanticRecordRow {
    var record: JournalRecord
    var paymentMethod: PaymentMethod
    var paymentType: PaymentType
    var paymentDetail: PaymentDetail
}

private let selectJournalRecordSQL = """
    SELECT
        journal_records.id,
        journal_records.account_month,
        journal_records.occurred_at,
        journal_records.payment_method_id,
        payment_methods.name AS payment_method_name,
        journal_records.amount,
        journal_records.payment_type_id,
        payment_types.name AS payment_type_name,
        journal_records.payment_detail_id,
        payment_details.name AS payment_detail_name,
        journal_records.note,
        journal_records.record_source,
        journal_records.record_kind,
        journal_records.carry_forward_role,
        journal_records.engine_family,
        journal_records.engine_key,
        journal_records.object_key,
        journal_records.source_record_ids,
        journal_records.created_at,
        journal_records.updated_at
    FROM journal_records
    JOIN payment_methods ON payment_methods.id = journal_records.payment_method_id
    JOIN payment_types ON payment_types.id = journal_records.payment_type_id
    JOIN payment_details ON payment_details.id = journal_records.payment_detail_id
    """

private func sqlPlaceholders(_ count: Int) -> String {
    "(\(Array(repeating: "?", count: count).joined(separator: ",")))"
}

private func insertPaymentMethodIfNeeded(
    _ db: Database,
    name: String,
    methodType: PaymentMethodType,
    now: Date
) throws {
    try db.execute(sql: """
        INSERT OR IGNORE INTO payment_methods (id, name, method_type, is_active, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """, arguments: [
            UUID().uuidString,
            name,
            methodType.rawValue,
            true,
            encodeDate(now),
            encodeDate(now)
        ])
}

@discardableResult
private func insertPaymentTypeIfNeeded(
    _ db: Database,
    name: String,
    element: AccountingElement,
    now: Date
) throws -> PaymentType {
    try db.execute(sql: """
        INSERT OR IGNORE INTO payment_types (id, name, element, is_active, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """, arguments: [
            UUID().uuidString,
            name,
            element.rawValue,
            true,
            encodeDate(now),
            encodeDate(now)
        ])
    return try requirePaymentType(db, name: name)
}

private func insertPaymentDetailIfNeeded(
    _ db: Database,
    name: String,
    paymentTypeId: UUID,
    now: Date
) throws {
    try db.execute(sql: """
        INSERT OR IGNORE INTO payment_details (id, name, payment_type_id, is_active, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """, arguments: [
            UUID().uuidString,
            name,
            paymentTypeId.uuidString,
            true,
            encodeDate(now),
            encodeDate(now)
        ])
}

private func insertJournalRecord(_ db: Database, record: JournalRecord) throws {
    try db.execute(sql: """
        INSERT INTO journal_records (
            id, account_month, occurred_at, payment_method_id, amount, payment_type_id,
            payment_detail_id, note, record_source, record_kind, carry_forward_role,
            engine_family, engine_key, object_key, source_record_ids, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: journalRecordArguments(record))
}

private func persistJournalRecordUpdate(_ db: Database, record: JournalRecord) throws {
    var arguments = journalRecordArguments(record)
    arguments += [record.id.uuidString]
    try db.execute(sql: """
        UPDATE journal_records SET
            id = ?, account_month = ?, occurred_at = ?, payment_method_id = ?, amount = ?,
            payment_type_id = ?, payment_detail_id = ?, note = ?, record_source = ?,
            record_kind = ?, carry_forward_role = ?, engine_family = ?, engine_key = ?,
            object_key = ?, source_record_ids = ?, created_at = ?, updated_at = ?
        WHERE id = ?
        """, arguments: arguments)
}

private func journalRecordArguments(_ record: JournalRecord) -> StatementArguments {
    [
        record.id.uuidString,
        record.accountMonth,
        encodeDate(record.occurredAt),
        record.paymentMethodId.uuidString,
        encodeDecimal(record.amount),
        record.paymentTypeId.uuidString,
        record.paymentDetailId.uuidString,
        record.note,
        record.recordSource.rawValue,
        record.recordKind.rawValue,
        record.carryForwardRole.rawValue,
        record.engineFamily?.rawValue,
        record.engineKey,
        record.objectKey,
        encodeUUIDList(record.sourceRecordIds),
        encodeDate(record.createdAt),
        encodeDate(record.updatedAt)
    ]
}

private func fetchSourceRecordsWithSemantics(_ db: Database, accountMonth: String) throws -> [SemanticRecordRow] {
    let rows = try Row.fetchAll(db, sql: """
        \(selectJournalRecordSQL)
        WHERE journal_records.account_month = ?
          AND journal_records.record_source != ?
        ORDER BY journal_records.occurred_at ASC, journal_records.created_at ASC
        """, arguments: [accountMonth, RecordSource.engine.rawValue])

    return try rows.map { row in
        let record = try journalRecord(from: row)
        return SemanticRecordRow(
            record: record,
            paymentMethod: try requirePaymentMethod(db, id: record.paymentMethodId),
            paymentType: try requirePaymentType(db, id: record.paymentTypeId),
            paymentDetail: try requirePaymentDetail(db, id: record.paymentDetailId)
        )
    }
}

private func requirePaymentMethod(_ db: Database, name: String) throws -> PaymentMethod {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, method_type, is_active FROM payment_methods WHERE name = ?",
        arguments: [name]
    ) else {
        throw MingZhangError.missingSeed("收付手段：\(name)")
    }
    return try paymentMethod(from: row)
}

private func requirePaymentMethod(_ db: Database, id: UUID) throws -> PaymentMethod {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, method_type, is_active FROM payment_methods WHERE id = ?",
        arguments: [id.uuidString]
    ) else {
        throw MingZhangError.missingSeed("收付手段：\(id.uuidString)")
    }
    return try paymentMethod(from: row)
}

private func requirePaymentType(_ db: Database, name: String) throws -> PaymentType {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, element, is_active FROM payment_types WHERE name = ?",
        arguments: [name]
    ) else {
        throw MingZhangError.missingSeed("收付类型：\(name)")
    }
    return try paymentType(from: row)
}

private func requirePaymentType(_ db: Database, id: UUID) throws -> PaymentType {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, element, is_active FROM payment_types WHERE id = ?",
        arguments: [id.uuidString]
    ) else {
        throw MingZhangError.missingSeed("收付类型：\(id.uuidString)")
    }
    return try paymentType(from: row)
}

private func requirePaymentDetail(_ db: Database, name: String, paymentTypeId: UUID) throws -> PaymentDetail {
    guard let row = try Row.fetchOne(
        db,
        sql: """
            SELECT id, name, payment_type_id, is_active
            FROM payment_details
            WHERE name = ? AND payment_type_id = ?
            """,
        arguments: [name, paymentTypeId.uuidString]
    ) else {
        throw MingZhangError.missingSeed("类型明细：\(name)")
    }
    return try paymentDetail(from: row)
}

private func requirePaymentDetail(_ db: Database, id: UUID) throws -> PaymentDetail {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, payment_type_id, is_active FROM payment_details WHERE id = ?",
        arguments: [id.uuidString]
    ) else {
        throw MingZhangError.missingSeed("类型明细：\(id.uuidString)")
    }
    return try paymentDetail(from: row)
}

private func requireJournalRecord(_ db: Database, id: UUID) throws -> JournalRecord {
    guard let row = try Row.fetchOne(
        db,
        sql: "\(selectJournalRecordSQL) WHERE journal_records.id = ?",
        arguments: [id.uuidString]
    ) else {
        throw MingZhangError.recordNotFound(id)
    }
    return try journalRecord(from: row)
}

private func paymentMethod(from row: Row) throws -> PaymentMethod {
    PaymentMethod(
        id: try requireUUID(row["id"]),
        name: row["name"],
        methodType: PaymentMethodType(rawValue: row["method_type"]) ?? .pendingRealAccount,
        isActive: row["is_active"]
    )
}

private func paymentType(from row: Row) throws -> PaymentType {
    PaymentType(
        id: try requireUUID(row["id"]),
        name: row["name"],
        element: AccountingElement(rawValue: row["element"]) ?? .expense,
        isActive: row["is_active"]
    )
}

private func paymentDetail(from row: Row) throws -> PaymentDetail {
    PaymentDetail(
        id: try requireUUID(row["id"]),
        name: row["name"],
        paymentTypeId: try requireUUID(row["payment_type_id"]),
        isActive: row["is_active"]
    )
}

private func journalRecord(from row: Row) throws -> JournalRecord {
    let recordSource = RecordSource(rawValue: row["record_source"]) ?? .manual
    let engineFamilyValue: String? = row["engine_family"]

    return JournalRecord(
        id: try requireUUID(row["id"]),
        accountMonth: row["account_month"],
        occurredAt: try decodeDate(row["occurred_at"]),
        paymentMethodId: try requireUUID(row["payment_method_id"]),
        paymentMethodName: row["payment_method_name"],
        amount: decodeDecimal(row["amount"]),
        paymentTypeId: try requireUUID(row["payment_type_id"]),
        paymentTypeName: row["payment_type_name"],
        paymentDetailId: try requireUUID(row["payment_detail_id"]),
        paymentDetailName: row["payment_detail_name"],
        note: row["note"],
        recordSource: recordSource,
        recordKind: RecordKind(rawValue: row["record_kind"]) ?? .normal,
        carryForwardRole: CarryForwardRole(rawValue: row["carry_forward_role"]) ?? .none,
        engineFamily: engineFamilyValue.flatMap(EngineFamily.init(rawValue:)),
        engineKey: row["engine_key"],
        objectKey: row["object_key"],
        sourceRecordIds: decodeUUIDList(row["source_record_ids"]),
        createdAt: try decodeDate(row["created_at"]),
        updatedAt: try decodeDate(row["updated_at"])
    )
}

private func requireUUID(_ value: String) throws -> UUID {
    guard let uuid = UUID(uuidString: value) else {
        throw MingZhangError.missingSeed("无效 UUID：\(value)")
    }
    return uuid
}

private func encodeDate(_ date: Date) -> String {
    makeISO8601Formatter().string(from: date)
}

private func decodeDate(_ value: String) throws -> Date {
    guard let date = makeISO8601Formatter().date(from: value) else {
        throw MingZhangError.invalidDate(value)
    }
    return date
}

private func encodeDecimal(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

private func decodeDecimal(_ value: String) -> Decimal {
    Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(0)
}

private func encodeUUIDList(_ values: [UUID]) -> String {
    values.map(\.uuidString).joined(separator: ",")
}

private func decodeUUIDList(_ value: String) -> [UUID] {
    value
        .split(separator: ",")
        .compactMap { UUID(uuidString: String($0)) }
}

private func monthEndPlaceholder(_ accountMonth: String) -> Date {
    let value = "\(accountMonth)-28T23:59:59Z"
    return makeISO8601Formatter().date(from: value) ?? Date(timeIntervalSince1970: 0)
}

private func makeISO8601Formatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}
