import Foundation
import CryptoKit
import class CoreXLSX.XLSXFile
import struct CoreXLSX.Cell
import struct CoreXLSX.SharedStrings
import GRDB

public enum MingZhangError: Error, Equatable, LocalizedError {
    case missingSeed(String)
    case recordNotFound(UUID)
    case investmentTransactionNotFound(UUID)
    case recordNotEditable(UUID)
    case invalidDate(String)
    case validation(String)

    public var errorDescription: String? {
        switch self {
        case .missingSeed(let value):
            "缺少默认配置：\(value)"
        case .recordNotFound(let id):
            "找不到流水记录：\(id.uuidString)"
        case .investmentTransactionNotFound(let id):
            "找不到投资交易：\(id.uuidString)"
        case .recordNotEditable:
            "这条记录由系统生成或回填，不能直接编辑或删除"
        case .invalidDate(let value):
            "日期格式无效：\(value)"
        case .validation(let message):
            message
        }
    }
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
    public var semanticTags: [String]
    public var configVersion: Int
}

public struct PaymentType: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var element: AccountingElement
    public var isActive: Bool
    public var semanticTags: [String]
    public var configDescription: String?
    public var configVersion: Int
}

public struct PaymentDetail: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var paymentTypeId: UUID
    public var isActive: Bool
    public var semanticTags: [String]
    public var configDescription: String?
    public var configVersion: Int
}

public struct CreatePaymentMethodInput: Equatable, Sendable {
    public var name: String
    public var methodType: PaymentMethodType
    public var semanticTags: [String]

    public init(name: String, methodType: PaymentMethodType, semanticTags: [String] = []) {
        self.name = name
        self.methodType = methodType
        self.semanticTags = semanticTags
    }
}

public struct UpdatePaymentMethodInput: Equatable, Sendable {
    public var name: String?
    public var methodType: PaymentMethodType?
    public var semanticTags: [String]?

    public init(name: String? = nil, methodType: PaymentMethodType? = nil, semanticTags: [String]? = nil) {
        self.name = name
        self.methodType = methodType
        self.semanticTags = semanticTags
    }
}

public struct CreatePaymentTypeInput: Equatable, Sendable {
    public var name: String
    public var element: AccountingElement
    public var semanticTags: [String]
    public var configDescription: String?

    public init(
        name: String,
        element: AccountingElement,
        semanticTags: [String] = [],
        configDescription: String? = nil
    ) {
        self.name = name
        self.element = element
        self.semanticTags = semanticTags
        self.configDescription = configDescription
    }
}

public struct UpdatePaymentTypeInput: Equatable, Sendable {
    public var name: String?
    public var element: AccountingElement?
    public var semanticTags: [String]?
    public var configDescription: String?

    public init(
        name: String? = nil,
        element: AccountingElement? = nil,
        semanticTags: [String]? = nil,
        configDescription: String? = nil
    ) {
        self.name = name
        self.element = element
        self.semanticTags = semanticTags
        self.configDescription = configDescription
    }
}

public struct CreatePaymentDetailInput: Equatable, Sendable {
    public var name: String
    public var paymentTypeId: UUID
    public var semanticTags: [String]
    public var configDescription: String?

    public init(
        name: String,
        paymentTypeId: UUID,
        semanticTags: [String] = [],
        configDescription: String? = nil
    ) {
        self.name = name
        self.paymentTypeId = paymentTypeId
        self.semanticTags = semanticTags
        self.configDescription = configDescription
    }
}

public struct UpdatePaymentDetailInput: Equatable, Sendable {
    public var name: String?
    public var paymentTypeId: UUID?
    public var semanticTags: [String]?
    public var configDescription: String?

    public init(
        name: String? = nil,
        paymentTypeId: UUID? = nil,
        semanticTags: [String]? = nil,
        configDescription: String? = nil
    ) {
        self.name = name
        self.paymentTypeId = paymentTypeId
        self.semanticTags = semanticTags
        self.configDescription = configDescription
    }
}

public enum SemanticTagCatalog {
    public static let paymentMethodTags = ["资产型", "负债型", "账务处理型"]
    public static let paymentTypeTags = ["资产", "负债", "收入", "支出"]
    public static let paymentDetailTags = ["递延资产", "已实现投资收益", "已实现投资亏损", "金融费用", "账单还款"]
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
    public var sourceInvestmentTransactionIds: [UUID]
    public var sourceImportBatchId: UUID?
    public var sourceImportCandidateId: UUID?
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
    public var objectKey: String?
    public var note: String?

    public init(
        accountMonth: String,
        occurredAt: Date,
        paymentMethodName: String,
        amount: Decimal,
        paymentTypeName: String,
        paymentDetailName: String,
        objectKey: String? = nil,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.paymentMethodName = paymentMethodName
        self.amount = amount
        self.paymentTypeName = paymentTypeName
        self.paymentDetailName = paymentDetailName
        self.objectKey = objectKey
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
    public var objectKey: String?
    public var note: String?

    public init(
        accountMonth: String? = nil,
        occurredAt: Date? = nil,
        paymentMethodName: String? = nil,
        amount: Decimal? = nil,
        paymentTypeName: String? = nil,
        paymentDetailName: String? = nil,
        objectKey: String? = nil,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.paymentMethodName = paymentMethodName
        self.amount = amount
        self.paymentTypeName = paymentTypeName
        self.paymentDetailName = paymentDetailName
        self.objectKey = objectKey
        self.note = note
    }
}

public struct JournalRecordFilter: Equatable, Sendable {
    public var accountMonths: [String]
    public var includeEngineRecords: Bool
    public var paymentMethodNames: [String]
    public var paymentTypeNames: [String]
    public var paymentDetailNames: [String]
    public var amountMin: Decimal?
    public var amountMax: Decimal?
    public var noteKeyword: String?
    public var searchKeyword: String?

    public init(
        accountMonths: [String],
        includeEngineRecords: Bool = false,
        paymentMethodNames: [String] = [],
        paymentTypeNames: [String] = [],
        paymentDetailNames: [String] = [],
        amountMin: Decimal? = nil,
        amountMax: Decimal? = nil,
        noteKeyword: String? = nil,
        searchKeyword: String? = nil
    ) {
        self.accountMonths = accountMonths
        self.includeEngineRecords = includeEngineRecords
        self.paymentMethodNames = paymentMethodNames
        self.paymentTypeNames = paymentTypeNames
        self.paymentDetailNames = paymentDetailNames
        self.amountMin = amountMin
        self.amountMax = amountMax
        self.noteKeyword = noteKeyword
        self.searchKeyword = searchKeyword
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
    public var objectKey: String?
    public var amount: Decimal
    public var formedAmount: Decimal
    public var repaidAmount: Decimal
    public var costAmount: Decimal
    public var sourceRecordIds: [UUID]

    public init(
        name: String,
        objectKey: String? = nil,
        amount: Decimal,
        formedAmount: Decimal = 0,
        repaidAmount: Decimal = 0,
        costAmount: Decimal = 0,
        sourceRecordIds: [UUID]
    ) {
        self.name = name
        self.objectKey = objectKey
        self.amount = amount
        self.formedAmount = formedAmount
        self.repaidAmount = repaidAmount
        self.costAmount = costAmount
        self.sourceRecordIds = sourceRecordIds
    }
}

public typealias LiabilityBalanceItem = BalanceItem

public struct BalanceSummary: Equatable, Sendable {
    public var cashBalance: Decimal
    public var cashSourceRecordIds: [UUID]
    public var liabilityItems: [BalanceItem]
    public var investmentItems: [BalanceItem]

    public init(
        cashBalance: Decimal,
        cashSourceRecordIds: [UUID] = [],
        liabilityItems: [BalanceItem],
        investmentItems: [BalanceItem] = []
    ) {
        self.cashBalance = cashBalance
        self.cashSourceRecordIds = cashSourceRecordIds
        self.liabilityItems = liabilityItems
        self.investmentItems = investmentItems
    }
}

public struct CreateLiabilityRepaymentInput: Equatable, Sendable {
    public var accountMonth: String
    public var occurredAt: Date
    public var liabilityObjectKey: String
    public var amount: Decimal
    public var paymentMethodName: String
    public var note: String?

    public init(
        accountMonth: String,
        occurredAt: Date,
        liabilityObjectKey: String,
        amount: Decimal,
        paymentMethodName: String,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.liabilityObjectKey = liabilityObjectKey
        self.amount = amount
        self.paymentMethodName = paymentMethodName
        self.note = note
    }
}

public struct LiabilityDetailSummary: Equatable, Sendable {
    public var name: String
    public var objectKey: String
    public var formedAmount: Decimal
    public var repaidAmount: Decimal
    public var costAmount: Decimal
    public var remainingAmount: Decimal
    public var formationSourceRecordIds: [UUID]
    public var repaymentSourceRecordIds: [UUID]
    public var costSourceRecordIds: [UUID]
    public var sourceRecordIds: [UUID]

    public init(
        name: String,
        objectKey: String,
        formedAmount: Decimal,
        repaidAmount: Decimal,
        costAmount: Decimal,
        remainingAmount: Decimal,
        formationSourceRecordIds: [UUID],
        repaymentSourceRecordIds: [UUID],
        costSourceRecordIds: [UUID],
        sourceRecordIds: [UUID]
    ) {
        self.name = name
        self.objectKey = objectKey
        self.formedAmount = formedAmount
        self.repaidAmount = repaidAmount
        self.costAmount = costAmount
        self.remainingAmount = remainingAmount
        self.formationSourceRecordIds = formationSourceRecordIds
        self.repaymentSourceRecordIds = repaymentSourceRecordIds
        self.costSourceRecordIds = costSourceRecordIds
        self.sourceRecordIds = sourceRecordIds
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
        migrator.registerMigration("v2_p1_import") { db in
            try db.alter(table: "journal_records") { table in
                table.add(column: "source_import_batch_id", .text)
                table.add(column: "source_import_candidate_id", .text)
            }

            try db.create(table: "import_batches", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("source", .text).notNull().indexed()
                table.column("file_name", .text)
                table.column("imported_at", .text).notNull()
                table.column("status", .text).notNull().indexed()
                table.column("confirmed_record_count", .integer).notNull()
            }

            try db.create(table: "import_candidates", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("batch_id", .text).notNull().indexed().references("import_batches", onDelete: .cascade)
                table.column("status", .text).notNull().indexed()
                table.column("account_month", .text).notNull().indexed()
                table.column("occurred_at", .text).notNull()
                table.column("payment_method_id", .text).references("payment_methods", onDelete: .setNull)
                table.column("payment_method_name", .text)
                table.column("amount", .text).notNull()
                table.column("payment_type_id", .text).references("payment_types", onDelete: .setNull)
                table.column("payment_type_name", .text)
                table.column("payment_detail_id", .text).references("payment_details", onDelete: .setNull)
                table.column("payment_detail_name", .text)
                table.column("note", .text)
                table.column("raw_line_number", .integer).notNull()
                table.column("raw_payload", .text).notNull()
                table.column("raw_transaction_id", .text)
                table.column("raw_fingerprint", .text).notNull()
                table.column("created_journal_record_id", .text).references("journal_records", onDelete: .setNull)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }

            try db.create(index: "idx_import_candidates_transaction", on: "import_candidates", columns: ["raw_transaction_id"])
            try db.create(index: "idx_import_candidates_fingerprint", on: "import_candidates", columns: ["raw_fingerprint"])
        }
        migrator.registerMigration("v3_p1_investment") { db in
            try db.alter(table: "journal_records") { table in
                table.add(column: "source_investment_transaction_ids", .text)
                    .notNull()
                    .defaults(to: "")
            }

            try db.create(table: "investment_transactions", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("account_month", .text).notNull().indexed()
                table.column("occurred_at", .text).notNull().indexed()
                table.column("fund_name", .text).notNull().indexed()
                table.column("transaction_type", .text).notNull()
                table.column("trade_amount", .text)
                table.column("trade_share", .text)
                table.column("nav", .text)
                table.column("note", .text)
                table.column("book_amount", .text)
                table.column("realized_gain", .text).notNull()
                table.column("realized_loss", .text).notNull()
                table.column("holding_share", .text).notNull()
                table.column("average_cost", .text)
                table.column("book_value", .text).notNull()
                table.column("present_value", .text)
                table.column("created_at", .text).notNull()
                table.column("updated_at", .text).notNull()
            }
        }
        migrator.registerMigration("v4_p1_settings_semantics") { db in
            try db.alter(table: "payment_methods") { table in
                table.add(column: "semantic_tags", .text).notNull().defaults(to: "[]")
                table.add(column: "config_version", .integer).notNull().defaults(to: 1)
                table.add(column: "seed_key", .text)
            }

            try db.alter(table: "payment_types") { table in
                table.add(column: "semantic_tags", .text).notNull().defaults(to: "[]")
                table.add(column: "config_description", .text)
                table.add(column: "config_version", .integer).notNull().defaults(to: 1)
                table.add(column: "seed_key", .text)
            }

            try db.alter(table: "payment_details") { table in
                table.add(column: "semantic_tags", .text).notNull().defaults(to: "[]")
                table.add(column: "config_description", .text)
                table.add(column: "config_version", .integer).notNull().defaults(to: 1)
                table.add(column: "seed_key", .text)
            }

            try db.create(index: "idx_payment_methods_seed_key", on: "payment_methods", columns: ["seed_key"], unique: true)
            try db.create(index: "idx_payment_types_seed_key", on: "payment_types", columns: ["seed_key"], unique: true)
            try db.create(index: "idx_payment_details_seed_key", on: "payment_details", columns: ["seed_key"], unique: true)
        }
        migrator.registerMigration("v5_p1_liability_repayment") { db in
            try db.alter(table: "import_candidates") { table in
                table.add(column: "object_key", .text)
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
            for seed in paymentMethodSeeds {
                try insertPaymentMethodIfNeeded(
                    db,
                    seedKey: seed.seedKey,
                    name: seed.name,
                    methodType: seed.methodType,
                    semanticTags: seed.semanticTags,
                    now: now
                )
            }

            var typeIdsBySeedKey: [String: UUID] = [:]
            for seed in paymentTypeSeeds {
                let type = try insertPaymentTypeIfNeeded(
                    db,
                    seedKey: seed.seedKey,
                    name: seed.name,
                    element: seed.element,
                    semanticTags: seed.semanticTags,
                    configDescription: seed.configDescription,
                    now: now
                )
                typeIdsBySeedKey[seed.seedKey] = type.id
            }

            for seed in paymentDetailSeeds {
                guard let typeId = typeIdsBySeedKey[seed.paymentTypeSeedKey] else {
                    throw MingZhangError.missingSeed("收付类型：\(seed.paymentTypeSeedKey)")
                }
                try insertPaymentDetailIfNeeded(
                    db,
                    seedKey: seed.seedKey,
                    name: seed.name,
                    paymentTypeId: typeId,
                    semanticTags: seed.semanticTags,
                    configDescription: seed.configDescription,
                    now: now
                )
            }
        }
    }

    public func queryPaymentMethods(includeInactive: Bool = true, includeInternal: Bool = true) throws -> [PaymentMethod] {
        try database.writer.read { db in
            var sql = """
                SELECT id, name, method_type, is_active, semantic_tags, config_version
                FROM payment_methods
                WHERE 1 = 1
                """
            var arguments = StatementArguments()
            if !includeInactive {
                sql += " AND is_active = ?"
                arguments += [true]
            }
            if !includeInternal {
                sql += " AND method_type != ?"
                arguments += [PaymentMethodType.pendingRealAccount.rawValue]
            }
            sql += " ORDER BY name"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(paymentMethod(from:))
        }
    }

    public func queryPaymentTypes(includeInactive: Bool = true) throws -> [PaymentType] {
        try database.writer.read { db in
            var sql = """
                SELECT id, name, element, is_active, semantic_tags, config_description, config_version
                FROM payment_types
                """
            var arguments = StatementArguments()
            if !includeInactive {
                sql += " WHERE is_active = ?"
                arguments += [true]
            }
            sql += " ORDER BY name"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(paymentType(from:))
        }
    }

    public func queryPaymentDetails(includeInactive: Bool = true) throws -> [PaymentDetail] {
        try database.writer.read { db in
            var sql = """
                SELECT id, name, payment_type_id, is_active, semantic_tags, config_description, config_version
                FROM payment_details
                """
            var arguments = StatementArguments()
            if !includeInactive {
                sql += " WHERE is_active = ?"
                arguments += [true]
            }
            sql += " ORDER BY name"
            return try Row.fetchAll(db, sql: sql, arguments: arguments).map(paymentDetail(from:))
        }
    }

    @discardableResult
    public func createPaymentMethod(input: CreatePaymentMethodInput) throws -> PaymentMethod {
        try database.writer.write { db in
            let name = try normalizedConfigName(input.name, fieldName: "收付手段")
            guard input.methodType != .pendingRealAccount else {
                throw MingZhangError.validation("待补真实账户是导入内部占位，不能手动新增")
            }
            try ensureUniquePaymentMethodName(db, name: name)
            let now = Date()
            let id = UUID()
            try db.execute(sql: """
                INSERT INTO payment_methods (id, name, method_type, is_active, semantic_tags, config_version, seed_key, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                id.uuidString,
                name,
                input.methodType.rawValue,
                true,
                encodeStringList(normalizedTags(input.semanticTags)),
                1,
                nil,
                encodeDate(now),
                encodeDate(now)
            ])
            return try requirePaymentMethod(db, id: id)
        }
    }

    @discardableResult
    public func updatePaymentMethod(id: UUID, input: UpdatePaymentMethodInput) throws -> PaymentMethod {
        let context = try database.writer.write { db in
            var method = try requirePaymentMethod(db, id: id)
            guard method.methodType != .pendingRealAccount else {
                throw MingZhangError.validation("待补真实账户是导入内部占位，不能在设置中编辑")
            }
            let referenced = try hasJournalRecordReference(db, column: "payment_method_id", id: id)
            let newName = try input.name.map { try normalizedConfigName($0, fieldName: "收付手段") } ?? method.name
            if newName != method.name {
                try ensureUniquePaymentMethodName(db, name: newName, excluding: id)
                method.name = newName
            }
            if let methodType = input.methodType, methodType != method.methodType {
                guard methodType != .pendingRealAccount else {
                    throw MingZhangError.validation("待补真实账户是导入内部占位，不能在设置中编辑")
                }
                guard !referenced else {
                    throw MingZhangError.validation("已被历史流水引用的收付手段不能修改属性")
                }
                method.methodType = methodType
            }
            if let semanticTags = input.semanticTags {
                method.semanticTags = normalizedTags(semanticTags)
            }
            try persistPaymentMethodUpdate(db, method: method)
            let affectedMonths = try referencedAccountMonths(db, column: "payment_method_id", id: id)
            return (method: try requirePaymentMethod(db, id: id), affectedMonths: affectedMonths)
        }
        for month in context.affectedMonths {
            _ = try recalculateAccountMonth(month)
        }
        return context.method
    }

    @discardableResult
    public func disablePaymentMethod(id: UUID) throws -> PaymentMethod {
        try database.writer.write { db in
            var method = try requirePaymentMethod(db, id: id)
            guard method.methodType != .pendingRealAccount else {
                throw MingZhangError.validation("待补真实账户是导入内部占位，不能在设置中停用")
            }
            method.isActive = false
            try persistPaymentMethodUpdate(db, method: method)
            return try requirePaymentMethod(db, id: id)
        }
    }

    @discardableResult
    public func createPaymentType(input: CreatePaymentTypeInput) throws -> PaymentType {
        try database.writer.write { db in
            let name = try normalizedConfigName(input.name, fieldName: "收付类型")
            try ensureUniquePaymentTypeName(db, name: name)
            let now = Date()
            let id = UUID()
            try db.execute(sql: """
                INSERT INTO payment_types (id, name, element, is_active, semantic_tags, config_description, config_version, seed_key, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                id.uuidString,
                name,
                input.element.rawValue,
                true,
                encodeStringList(normalizedTags(input.semanticTags)),
                normalizedOptionalText(input.configDescription),
                1,
                nil,
                encodeDate(now),
                encodeDate(now)
            ])
            return try requirePaymentType(db, id: id)
        }
    }

    @discardableResult
    public func updatePaymentType(id: UUID, input: UpdatePaymentTypeInput) throws -> PaymentType {
        try database.writer.write { db in
            var type = try requirePaymentType(db, id: id)
            let referenced = try hasJournalRecordReference(db, column: "payment_type_id", id: id)
            let newName = try input.name.map { try normalizedConfigName($0, fieldName: "收付类型") } ?? type.name
            if newName != type.name {
                try ensureUniquePaymentTypeName(db, name: newName, excluding: id)
                type.name = newName
            }
            if let element = input.element, element != type.element {
                guard !referenced else {
                    throw MingZhangError.validation("已被历史流水引用的收付类型不能修改会计要素")
                }
                type.element = element
            }
            if let semanticTags = input.semanticTags {
                type.semanticTags = normalizedTags(semanticTags)
            }
            if let configDescription = input.configDescription {
                type.configDescription = normalizedOptionalText(configDescription)
            }
            try persistPaymentTypeUpdate(db, type: type)
            return try requirePaymentType(db, id: id)
        }
    }

    @discardableResult
    public func disablePaymentType(id: UUID) throws -> PaymentType {
        try database.writer.write { db in
            var type = try requirePaymentType(db, id: id)
            type.isActive = false
            try persistPaymentTypeUpdate(db, type: type)
            try db.execute(sql: """
                UPDATE payment_details
                SET is_active = ?, updated_at = ?
                WHERE payment_type_id = ?
                """, arguments: [false, encodeDate(Date()), id.uuidString])
            return try requirePaymentType(db, id: id)
        }
    }

    @discardableResult
    public func createPaymentDetail(input: CreatePaymentDetailInput) throws -> PaymentDetail {
        try database.writer.write { db in
            let type = try requirePaymentType(db, id: input.paymentTypeId)
            try requireActive(type, label: "收付类型")
            let name = try normalizedConfigName(input.name, fieldName: "类型明细")
            try ensureUniquePaymentDetailName(db, name: name, paymentTypeId: type.id)
            let now = Date()
            let id = UUID()
            try db.execute(sql: """
                INSERT INTO payment_details (id, name, payment_type_id, is_active, semantic_tags, config_description, config_version, seed_key, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                id.uuidString,
                name,
                type.id.uuidString,
                true,
                encodeStringList(normalizedTags(input.semanticTags)),
                normalizedOptionalText(input.configDescription),
                1,
                nil,
                encodeDate(now),
                encodeDate(now)
            ])
            return try requirePaymentDetail(db, id: id)
        }
    }

    @discardableResult
    public func updatePaymentDetail(id: UUID, input: UpdatePaymentDetailInput) throws -> PaymentDetail {
        try database.writer.write { db in
            var detail = try requirePaymentDetail(db, id: id)
            let referenced = try hasJournalRecordReference(db, column: "payment_detail_id", id: id)
            let newTypeId = input.paymentTypeId ?? detail.paymentTypeId
            if newTypeId != detail.paymentTypeId {
                guard !referenced else {
                    throw MingZhangError.validation("已被历史流水引用的类型明细不能移动归属")
                }
                let type = try requirePaymentType(db, id: newTypeId)
                try requireActive(type, label: "收付类型")
                detail.paymentTypeId = type.id
            }
            let newName = try input.name.map { try normalizedConfigName($0, fieldName: "类型明细") } ?? detail.name
            if newName != detail.name {
                try ensureUniquePaymentDetailName(db, name: newName, paymentTypeId: detail.paymentTypeId, excluding: id)
                detail.name = newName
            }
            if let semanticTags = input.semanticTags {
                detail.semanticTags = normalizedTags(semanticTags)
            }
            if let configDescription = input.configDescription {
                detail.configDescription = normalizedOptionalText(configDescription)
            }
            try persistPaymentDetailUpdate(db, detail: detail)
            return try requirePaymentDetail(db, id: id)
        }
    }

    @discardableResult
    public func disablePaymentDetail(id: UUID) throws -> PaymentDetail {
        try database.writer.write { db in
            var detail = try requirePaymentDetail(db, id: id)
            detail.isActive = false
            try persistPaymentDetailUpdate(db, detail: detail)
            return try requirePaymentDetail(db, id: id)
        }
    }

    public func queryInvestmentTransactions(fundName: String? = nil) throws -> [InvestmentTransaction] {
        try database.writer.read { db in
            try fetchInvestmentTransactions(db, fundName: fundName)
        }
    }

    public func queryInvestmentHoldings(accountMonth: String) throws -> [InvestmentHolding] {
        try database.writer.read { db in
            try fetchInvestmentHoldings(db, accountMonth: accountMonth)
        }
    }

    public func queryInvestmentMonthlySummary(accountMonth: String, fundName: String? = nil) throws -> InvestmentMonthlySummary {
        try database.writer.read { db in
            try validateAccountMonth(accountMonth)
            let transactions = try fetchInvestmentTransactions(db, fundName: fundName)
                .filter { $0.accountMonth == accountMonth }
            let holdings = try fetchInvestmentHoldings(db, accountMonth: accountMonth)
                .filter { holding in
                    fundName.map { holding.fundName == $0 } ?? true
                }
            let feedRecords = try fetchInvestmentFeedRecords(db, accountMonth: accountMonth, fundName: fundName)

            return InvestmentMonthlySummary(
                accountMonth: accountMonth,
                fundName: fundName,
                buyBookAmount: transactions
                    .filter { $0.transactionType == .buy }
                    .reduce(Decimal(0)) { $0 + ($1.bookAmount ?? 0) },
                sellBookAmount: transactions
                    .filter { $0.transactionType == .sell }
                    .reduce(Decimal(0)) { $0 + ($1.bookAmount ?? 0) },
                realizedGain: transactions.reduce(Decimal(0)) { $0 + $1.realizedGain },
                realizedLoss: transactions.reduce(Decimal(0)) { $0 + $1.realizedLoss },
                endingBookValue: holdings.reduce(Decimal(0)) { $0 + $1.bookValue },
                endingShare: holdings.reduce(Decimal(0)) { $0 + $1.holdingShare },
                feedJournalRecordIds: feedRecords.map(\.id).sorted { $0.uuidString < $1.uuidString },
                sourceTransactionIds: transactions.map(\.id).sorted { $0.uuidString < $1.uuidString }
            )
        }
    }

    public func queryInvestmentFeedRecords(accountMonth: String, fundName: String? = nil) throws -> [JournalRecord] {
        try database.writer.read { db in
            try fetchInvestmentFeedRecords(db, accountMonth: accountMonth, fundName: fundName)
        }
    }

    public func getInvestmentFeedTrace(recordId: UUID) throws -> InvestmentFeedTrace? {
        try database.writer.read { db in
            let record = try requireJournalRecord(db, id: recordId)
            guard
                record.recordSource == .investmentFeed,
                !record.sourceInvestmentTransactionIds.isEmpty
            else {
                return nil
            }
            return InvestmentFeedTrace(
                journalRecord: record,
                transactions: try fetchInvestmentTransactions(db, ids: record.sourceInvestmentTransactionIds)
            )
        }
    }

    @discardableResult
    public func createInvestmentTransaction(input: CreateInvestmentTransactionInput) throws -> InvestmentTransaction {
        let result = try database.writer.write { db in
            try validateInvestmentInput(db, input: input)
            let now = Date()
            let transaction = InvestmentTransaction(
                id: UUID(),
                accountMonth: input.accountMonth,
                occurredAt: input.occurredAt,
                fundName: input.fundName.trimmingCharacters(in: .whitespacesAndNewlines),
                transactionType: input.transactionType,
                tradeAmount: input.tradeAmount,
                tradeShare: input.tradeShare,
                nav: input.nav,
                note: input.note,
                bookAmount: nil,
                realizedGain: 0,
                realizedLoss: 0,
                holdingShare: 0,
                averageCost: nil,
                bookValue: 0,
                presentValue: nil,
                createdAt: now,
                updatedAt: now
            )
            try insertInvestmentTransaction(db, transaction: transaction)
            let affectedMonths = try recalculateInvestmentLedger(db, fundName: transaction.fundName)
            try reflowInvestmentFeedRecords(db, fundName: transaction.fundName, accountMonths: affectedMonths)
            return (transaction: try requireInvestmentTransaction(db, id: transaction.id), affectedMonths: affectedMonths)
        }

        for month in result.affectedMonths.sorted() {
            _ = try recalculateAccountMonth(month)
        }
        return result.transaction
    }

    @discardableResult
    public func updateInvestmentTransaction(id: UUID, changes: InvestmentTransactionChanges) throws -> InvestmentTransaction {
        let result = try database.writer.write { db in
            let original = try requireInvestmentTransaction(db, id: id)
            let oldFundMonths = Set(try fetchInvestmentTransactions(db, fundName: original.fundName).map(\.accountMonth))
            var transaction = original

            if let accountMonth = changes.accountMonth {
                transaction.accountMonth = accountMonth
            }
            if let occurredAt = changes.occurredAt {
                transaction.occurredAt = occurredAt
            }
            if let fundName = changes.fundName {
                transaction.fundName = fundName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let transactionType = changes.transactionType {
                transaction.transactionType = transactionType
            }
            if let tradeAmount = changes.tradeAmount {
                transaction.tradeAmount = tradeAmount
            }
            if let tradeShare = changes.tradeShare {
                transaction.tradeShare = tradeShare
            }
            if let nav = changes.nav {
                transaction.nav = nav
            }
            if let note = changes.note {
                transaction.note = note
            }

            try validateInvestmentInput(db, input: CreateInvestmentTransactionInput(
                accountMonth: transaction.accountMonth,
                occurredAt: transaction.occurredAt,
                fundName: transaction.fundName,
                transactionType: transaction.transactionType,
                tradeAmount: transaction.tradeAmount,
                tradeShare: transaction.tradeShare,
                nav: transaction.nav,
                note: transaction.note
            ))
            transaction.updatedAt = Date()
            try persistInvestmentTransactionUpdate(db, transaction: transaction)

            var affectedMonths = oldFundMonths
            if original.fundName != transaction.fundName {
                let oldRemainingMonths = try recalculateInvestmentLedger(db, fundName: original.fundName)
                try reflowInvestmentFeedRecords(
                    db,
                    fundName: original.fundName,
                    accountMonths: oldFundMonths.union(oldRemainingMonths)
                )
                affectedMonths.formUnion(oldRemainingMonths)
            }

            let newFundMonths = try recalculateInvestmentLedger(db, fundName: transaction.fundName)
            let newReflowMonths = original.fundName == transaction.fundName
                ? oldFundMonths.union(newFundMonths)
                : newFundMonths
            try reflowInvestmentFeedRecords(db, fundName: transaction.fundName, accountMonths: newReflowMonths)
            affectedMonths.formUnion(newReflowMonths)

            return (transaction: try requireInvestmentTransaction(db, id: id), affectedMonths: affectedMonths)
        }

        for month in result.affectedMonths.sorted() {
            _ = try recalculateAccountMonth(month)
        }
        return result.transaction
    }

    public func deleteInvestmentTransaction(id: UUID) throws {
        let affectedMonths = try database.writer.write { db in
            let transaction = try requireInvestmentTransaction(db, id: id)
            let oldFundMonths = Set(try fetchInvestmentTransactions(db, fundName: transaction.fundName).map(\.accountMonth))
            try db.execute(sql: "DELETE FROM investment_transactions WHERE id = ?", arguments: [id.uuidString])
            let remainingMonths = try recalculateInvestmentLedger(db, fundName: transaction.fundName)
            let reflowMonths = oldFundMonths.union(remainingMonths)
            try reflowInvestmentFeedRecords(db, fundName: transaction.fundName, accountMonths: reflowMonths)
            return reflowMonths
        }

        for month in affectedMonths.sorted() {
            _ = try recalculateAccountMonth(month)
        }
    }

    public func queryImportBatches() throws -> [ImportBatch] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, source, file_name, imported_at, status, confirmed_record_count
                FROM import_batches
                ORDER BY imported_at DESC
                """).map(importBatch(from:))
        }
    }

    public func queryImportCandidates(batchId: UUID) throws -> [ImportCandidateRecord] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, batch_id, status, account_month, occurred_at, payment_method_id,
                       payment_method_name, amount, payment_type_id, payment_type_name,
                       payment_detail_id, payment_detail_name, object_key, note, raw_line_number,
                       raw_payload, raw_transaction_id, raw_fingerprint, created_journal_record_id
                FROM import_candidates
                WHERE batch_id = ?
                ORDER BY occurred_at ASC, raw_line_number ASC
                """, arguments: [batchId.uuidString]).map(importCandidate(from:))
        }
    }

    @discardableResult
    public func createImportBatch(
        source: ImportSource,
        fileName: String?,
        contents: String
    ) throws -> CreateImportBatchResult {
        try createImportBatch(source: source, fileName: fileName, parseResult: try parseImportRows(source: source, contents: contents))
    }

    @discardableResult
    public func createImportBatch(
        source: ImportSource,
        fileName: String?,
        data: Data
    ) throws -> CreateImportBatchResult {
        let parseResult: ImportParseResult
        if fileName?.lowercased().hasSuffix(".xlsx") == true || data.starts(with: [0x50, 0x4B, 0x03, 0x04]) {
            parseResult = try parseXLSXImportRows(source: source, data: data)
        } else {
            parseResult = try parseImportRows(source: source, contents: try decodeImportText(data))
        }
        return try createImportBatch(source: source, fileName: fileName, parseResult: parseResult)
    }

    private func createImportBatch(
        source: ImportSource,
        fileName: String?,
        parseResult: ImportParseResult
    ) throws -> CreateImportBatchResult {
        return try database.writer.write { db in
            let now = Date()
            let batch = ImportBatch(
                id: UUID(),
                source: source,
                fileName: fileName,
                importedAt: now,
                status: .draft,
                confirmedRecordCount: 0
            )
            try insertImportBatch(db, batch: batch)

            let memoryIndex = try loadImportMemoryIndex(db, source: source)
            var issues = parseResult.issues
            var candidates: [ImportCandidateRecord] = []
            var seenKeys: Set<String> = []
            for row in parseResult.rows {
                let duplicateKey = row.rawTransactionId.map { "tx:\($0)" } ?? "fp:\(row.rawFingerprint)"
                guard !seenKeys.contains(duplicateKey) else {
                    issues.append(ImportIssue(lineNumber: row.lineNumber, code: .duplicate, message: "重复账单行"))
                    continue
                }
                seenKeys.insert(duplicateKey)

                guard try !importCandidateExists(db, source: source, transactionId: row.rawTransactionId, fingerprint: row.rawFingerprint) else {
                    issues.append(ImportIssue(lineNumber: row.lineNumber, code: .duplicate, message: "重复导入：\(row.rawTransactionId ?? row.rawFingerprint)"))
                    continue
                }

                let method = try resolveImportPaymentMethod(db, source: source, rawName: row.paymentMethodName)
                let memory = row.memoryKey.flatMap { memoryIndex[$0] }
                let candidate = ImportCandidateRecord(
                    id: UUID(),
                    batchId: batch.id,
                    status: .pending,
                    accountMonth: row.accountMonth,
                    occurredAt: row.occurredAt,
                    paymentMethodId: method.id,
                    paymentMethodName: method.name,
                    amount: row.amount,
                    paymentTypeId: memory?.paymentTypeId,
                    paymentTypeName: memory?.paymentTypeName,
                    paymentDetailId: memory?.paymentDetailId,
                    paymentDetailName: memory?.paymentDetailName,
                    note: row.note,
                    rawLineNumber: row.lineNumber,
                    rawPayload: row.rawPayload,
                    rawTransactionId: row.rawTransactionId,
                    rawFingerprint: row.rawFingerprint,
                    createdJournalRecordId: nil
                )
                try insertImportCandidate(db, candidate: candidate, now: now)
                candidates.append(candidate)
            }

            return CreateImportBatchResult(batch: batch, candidates: candidates, issues: issues)
        }
    }

    @discardableResult
    public func updateImportCandidate(id: UUID, changes: ImportCandidateChanges) throws -> ImportCandidateRecord {
        let updated = try database.writer.write { db in
            var candidate = try requireImportCandidate(db, id: id)
            try applyImportCandidateChanges(db, candidate: &candidate, changes: changes)
            try persistImportCandidateUpdate(db, candidate: candidate, updatedAt: Date())
            return candidate
        }
        return updated
    }

    @discardableResult
    public func batchUpdateImportCandidates(ids: [UUID], changes: ImportCandidateChanges) throws -> [ImportCandidateRecord] {
        guard !ids.isEmpty else { return [] }
        return try database.writer.write { db in
            let now = Date()
            var updated: [ImportCandidateRecord] = []
            for id in ids {
                var candidate = try requireImportCandidate(db, id: id)
                try applyImportCandidateChanges(db, candidate: &candidate, changes: changes)
                try persistImportCandidateUpdate(db, candidate: candidate, updatedAt: now)
                updated.append(candidate)
            }
            return updated.sorted { ($0.occurredAt, $0.rawLineNumber) < ($1.occurredAt, $1.rawLineNumber) }
        }
    }

    @discardableResult
    public func ignoreImportCandidates(ids: [UUID]) throws -> [ImportCandidateRecord] {
        guard !ids.isEmpty else { return [] }
        return try database.writer.write { db in
            let now = Date()
            var ignored: [ImportCandidateRecord] = []
            for id in ids {
                var candidate = try requireImportCandidate(db, id: id)
                guard candidate.status == .pending else {
                    throw MingZhangError.validation("只能整理待确认候选记录")
                }
                candidate.status = .ignored
                try persistImportCandidateUpdate(db, candidate: candidate, updatedAt: now)
                ignored.append(candidate)
            }
            return ignored.sorted { ($0.occurredAt, $0.rawLineNumber) < ($1.occurredAt, $1.rawLineNumber) }
        }
    }

    @discardableResult
    public func confirmImportCandidates(ids: [UUID]) throws -> [JournalRecord] {
        guard !ids.isEmpty else { return [] }
        let result = try database.writer.write { db in
            let now = Date()
            var records: [JournalRecord] = []
            var affectedMonths: Set<String> = []

            for id in ids {
                var candidate = try requireImportCandidate(db, id: id)
                guard candidate.status == .pending else {
                    throw MingZhangError.validation("只能确认待确认候选记录")
                }
                guard let typeId = candidate.paymentTypeId, let detailId = candidate.paymentDetailId else {
                    throw MingZhangError.validation("确认入账前必须补齐收付类型和类型明细")
                }
                let method: PaymentMethod
                if let paymentMethodId = candidate.paymentMethodId {
                    method = try requirePaymentMethod(db, id: paymentMethodId)
                } else {
                    method = try requirePaymentMethodBySeedKey(db, seedKey: "pending_real_account")
                }
                let type = try requirePaymentType(db, id: typeId)
                let detail = try requirePaymentDetail(db, id: detailId)
                if method.methodType != .pendingRealAccount {
                    try requireActive(method)
                }
                try requireActive(type)
                try requireActive(detail)
                let recordAmount = candidate.amount
                try validateRecordFields(
                    db,
                    accountMonth: candidate.accountMonth,
                    amount: recordAmount,
                    paymentMethod: method,
                    paymentType: type,
                    paymentDetail: detail,
                    objectKey: candidate.objectKey
                )

                let record = JournalRecord(
                    id: UUID(),
                    accountMonth: candidate.accountMonth,
                    occurredAt: candidate.occurredAt,
                    paymentMethodId: method.id,
                    paymentMethodName: method.name,
                    amount: recordAmount,
                    paymentTypeId: type.id,
                    paymentTypeName: type.name,
                    paymentDetailId: detail.id,
                    paymentDetailName: detail.name,
                    note: candidate.note,
                    recordSource: .import,
                    recordKind: .normal,
                    carryForwardRole: .none,
                    engineFamily: nil,
                    engineKey: nil,
                    objectKey: normalizedOptionalText(candidate.objectKey),
                    sourceRecordIds: [],
                    sourceInvestmentTransactionIds: [],
                    sourceImportBatchId: candidate.batchId,
                    sourceImportCandidateId: candidate.id,
                    createdAt: now,
                    updatedAt: now
                )
                try insertJournalRecord(db, record: record)

                candidate.status = .confirmed
                candidate.createdJournalRecordId = record.id
                try persistImportCandidateUpdate(db, candidate: candidate, updatedAt: now)
                try incrementBatchConfirmedCount(db, batchId: candidate.batchId)
                try markBatchConfirmedIfComplete(db, batchId: candidate.batchId)

                records.append(record)
                affectedMonths.insert(record.accountMonth)
            }

            return (records: records.sorted { ($0.occurredAt, $0.createdAt) < ($1.occurredAt, $1.createdAt) }, months: affectedMonths)
        }

        if let firstMonth = result.months.sorted().first {
            _ = try recalculateAccountMonths(startingAt: firstMonth)
        }
        return result.records
    }

    public func getImportTrace(recordId: UUID) throws -> ImportTrace? {
        try database.writer.read { db in
            let record = try requireJournalRecord(db, id: recordId)
            guard
                record.recordSource == .import,
                let batchId = record.sourceImportBatchId,
                let candidateId = record.sourceImportCandidateId
            else {
                return nil
            }
            let batch = try requireImportBatch(db, id: batchId)
            let candidate = try requireImportCandidate(db, id: candidateId)
            return ImportTrace(batch: batch, candidate: candidate)
        }
    }

    public func queryAccountMonths() throws -> [String] {
        try database.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT account_month
                FROM journal_records
                WHERE record_source != ?
                ORDER BY account_month DESC
                """, arguments: [RecordSource.engine.rawValue])
        }
    }

    @discardableResult
    public func createManualRecord(input: CreateManualRecordInput) throws -> JournalRecord {
        let record = try database.writer.write { db in
            let method = try requirePaymentMethod(db, name: input.paymentMethodName)
            let type = try requirePaymentType(db, name: input.paymentTypeName)
            let detail = try requirePaymentDetail(db, name: input.paymentDetailName, paymentTypeId: type.id)
            guard method.methodType != .pendingRealAccount else {
                throw MingZhangError.validation("待补真实账户是导入内部占位，不能用于手工记账")
            }
            try requireActive(method)
            try requireActive(type)
            try requireActive(detail)
            try validateRecordFields(
                db,
                accountMonth: input.accountMonth,
                amount: input.amount,
                paymentMethod: method,
                paymentType: type,
                paymentDetail: detail,
                objectKey: input.objectKey
            )
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
                    objectKey: normalizedOptionalText(input.objectKey),
                sourceRecordIds: [],
                sourceInvestmentTransactionIds: [],
                sourceImportBatchId: nil,
                sourceImportCandidateId: nil,
                createdAt: now,
                updatedAt: now
            )
            try insertJournalRecord(db, record: record)
            return record
        }

        _ = try recalculateAccountMonths(startingAt: record.accountMonth)
        return record
    }

    @discardableResult
    public func createLiabilityRepayment(input: CreateLiabilityRepaymentInput) throws -> JournalRecord {
        try createManualRecord(input: CreateManualRecordInput(
            accountMonth: input.accountMonth,
            occurredAt: input.occurredAt,
            paymentMethodName: input.paymentMethodName,
            amount: input.amount,
            paymentTypeName: "负债类减记",
            paymentDetailName: "账单还款",
            objectKey: input.liabilityObjectKey,
            note: input.note
        ))
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
                let isChangingMethod = method.id != record.paymentMethodId
                guard method.methodType != .pendingRealAccount || !isChangingMethod else {
                    throw MingZhangError.validation("待补真实账户是导入内部占位，不能用于手工记账")
                }
                if isChangingMethod {
                    try requireActive(method)
                }
                record.paymentMethodId = method.id
                record.paymentMethodName = method.name
            }
            if let amount = changes.amount {
                record.amount = amount
            }
            if let paymentTypeName = changes.paymentTypeName {
                let type = try requirePaymentType(db, name: paymentTypeName)
                if type.id != record.paymentTypeId {
                    try requireActive(type)
                }
                record.paymentTypeId = type.id
                record.paymentTypeName = type.name
            }
            if let paymentDetailName = changes.paymentDetailName {
                let detail = try requirePaymentDetail(db, name: paymentDetailName, paymentTypeId: record.paymentTypeId)
                if detail.id != record.paymentDetailId {
                    try requireActive(detail)
                }
                record.paymentDetailId = detail.id
                record.paymentDetailName = detail.name
            }
            if let objectKey = changes.objectKey {
                record.objectKey = normalizedOptionalText(objectKey)
            }
            if let note = changes.note {
                record.note = note
            }
            let finalMethod = try requirePaymentMethod(db, id: record.paymentMethodId)
            let finalType = try requirePaymentType(db, id: record.paymentTypeId)
            let finalDetail = try requirePaymentDetail(db, id: record.paymentDetailId)
            try validateRecordFields(
                db,
                accountMonth: record.accountMonth,
                amount: record.amount,
                paymentMethod: finalMethod,
                paymentType: finalType,
                paymentDetail: finalDetail,
                objectKey: record.objectKey
            )
            record.updatedAt = Date()
            try persistJournalRecordUpdate(db, record: record)
            return (record: record, originalMonth: originalMonth)
        }

        let startMonth = min(updateContext.originalMonth, updateContext.record.accountMonth)
        _ = try recalculateAccountMonths(startingAt: startMonth)
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

        _ = try recalculateAccountMonths(startingAt: month)
    }

    public func queryJournalRecords(filter: JournalRecordFilter) throws -> [JournalRecord] {
        guard !filter.accountMonths.isEmpty else { return [] }

        return try database.writer.read { db in
            var sql = selectJournalRecordSQL + " WHERE journal_records.account_month IN \(sqlPlaceholders(filter.accountMonths.count))"
            var arguments = StatementArguments(filter.accountMonths)

            if !filter.includeEngineRecords {
                sql += " AND journal_records.record_source != ?"
                arguments += [RecordSource.engine.rawValue]
            }
            if !filter.paymentMethodNames.isEmpty {
                sql += " AND payment_methods.name IN \(sqlPlaceholders(filter.paymentMethodNames.count))"
                arguments += StatementArguments(filter.paymentMethodNames)
            }
            if !filter.paymentTypeNames.isEmpty {
                sql += " AND payment_types.name IN \(sqlPlaceholders(filter.paymentTypeNames.count))"
                arguments += StatementArguments(filter.paymentTypeNames)
            }
            if !filter.paymentDetailNames.isEmpty {
                sql += " AND payment_details.name IN \(sqlPlaceholders(filter.paymentDetailNames.count))"
                arguments += StatementArguments(filter.paymentDetailNames)
            }
            if let amountMin = filter.amountMin {
                sql += " AND CAST(journal_records.amount AS REAL) >= CAST(? AS REAL)"
                arguments += [encodeDecimal(amountMin)]
            }
            if let amountMax = filter.amountMax {
                sql += " AND CAST(journal_records.amount AS REAL) <= CAST(? AS REAL)"
                arguments += [encodeDecimal(amountMax)]
            }
            if let noteKeyword = filter.noteKeyword?.trimmingCharacters(in: .whitespacesAndNewlines), !noteKeyword.isEmpty {
                sql += " AND journal_records.note LIKE ?"
                arguments += ["%\(noteKeyword)%"]
            }
            if let keyword = filter.searchKeyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty {
                let pattern = "%\(keyword)%"
                sql += """
                 AND (
                    journal_records.amount LIKE ?
                    OR payment_methods.name LIKE ?
                    OR payment_types.name LIKE ?
                    OR payment_details.name LIKE ?
                    OR journal_records.note LIKE ?
                 )
                """
                arguments += [pattern, pattern, pattern, pattern, pattern]
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
        try database.writer.read { db in
            let engineRecords = try fetchEngineRecords(db, accountMonth: accountMonth)

            let cashBalance = engineRecords
                .filter { $0.engineFamily == .cash }
                .reduce(Decimal(0)) { $0 + $1.amount }
            let cashSourceRecordIds = engineRecords
                .filter { $0.engineFamily == .cash }
                .flatMap(\.sourceRecordIds)
                .sorted { $0.uuidString < $1.uuidString }

            let liabilities = try engineRecords
                .filter { $0.engineFamily == .liability }
                .map { record -> BalanceItem in
                    let objectKey = record.objectKey ?? liabilityObjectKey(for: record.paymentMethodName)
                    let detail = try liabilityDetailSummary(db, objectKey: objectKey, accountMonth: accountMonth)
                    return BalanceItem(
                        name: detail.name,
                        objectKey: detail.objectKey,
                        amount: detail.remainingAmount,
                        formedAmount: detail.formedAmount,
                        repaidAmount: detail.repaidAmount,
                        costAmount: detail.costAmount,
                        sourceRecordIds: detail.sourceRecordIds
                    )
                }
                .sorted { $0.name < $1.name }

            let investments = engineRecords
                .filter { $0.engineFamily == .investment }
                .map { record in
                    BalanceItem(
                        name: record.objectKey?.replacingOccurrences(of: "investment:", with: "") ?? "总投资资产",
                        amount: record.amount,
                        sourceRecordIds: record.sourceRecordIds
                    )
                }
                .sorted { $0.name < $1.name }

            return BalanceSummary(
                cashBalance: cashBalance,
                cashSourceRecordIds: cashSourceRecordIds,
                liabilityItems: liabilities,
                investmentItems: investments
            )
        }
    }

    public func queryLiabilityDetail(accountMonth: String, objectKey: String) throws -> LiabilityDetailSummary {
        try database.writer.read { db in
            try liabilityDetailSummary(db, objectKey: objectKey, accountMonth: accountMonth)
        }
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

    public func exportAuditData() throws -> AuditExportResult {
        let exportedAt = Date()
        let records = try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: selectJournalRecordSQL + """
                 ORDER BY journal_records.account_month ASC,
                          journal_records.occurred_at ASC,
                          journal_records.created_at ASC,
                          journal_records.id ASC
                """
            ).map(journalRecord(from:))
        }

        var lines: [String] = [
            [
                "id",
                "账月",
                "时间",
                "收付手段",
                "金额",
                "收付类型",
                "类型明细",
                "备注",
                "记录来源",
                "record_kind",
                "carry_forward_role",
                "engine_family",
                "engine_key",
                "object_key",
                "source_record_ids",
                "source_import_batch_id",
                "source_import_candidate_id",
                "source_investment_transaction_ids",
                "created_at",
                "updated_at"
            ].map(csvEscape).joined(separator: ",")
        ]

        for record in records {
            lines.append([
                record.id.uuidString,
                record.accountMonth,
                encodeDate(record.occurredAt),
                record.paymentMethodName,
                encodeDecimal(record.amount),
                record.paymentTypeName,
                record.paymentDetailName,
                record.note ?? "",
                record.recordSource.rawValue,
                record.recordKind.rawValue,
                record.carryForwardRole.rawValue,
                record.engineFamily?.rawValue ?? "",
                record.engineKey ?? "",
                record.objectKey ?? "",
                encodeUUIDList(record.sourceRecordIds),
                record.sourceImportBatchId?.uuidString ?? "",
                record.sourceImportCandidateId?.uuidString ?? "",
                encodeUUIDList(record.sourceInvestmentTransactionIds),
                encodeDate(record.createdAt),
                encodeDate(record.updatedAt)
            ].map(csvEscape).joined(separator: ","))
        }

        let csv = lines.joined(separator: "\n") + "\n"
        return AuditExportResult(
            data: Data(csv.utf8),
            fileName: "mingzhang-audit-\(fileTimestamp(exportedAt)).csv",
            exportedAt: exportedAt
        )
    }

    public func createBackupPackage() throws -> BackupPackageResult {
        let exportedAt = dateRoundedToWholeSeconds(Date())
        let payload = try database.writer.read { db in
            try fetchBackupPayload(db)
        }
        let payloadChecksum = try checksum(for: payload)
        let manifest = BackupManifest(
            backupSchemaVersion: currentBackupSchemaVersion,
            appDataSchemaVersion: currentAppDataSchemaVersion,
            exportedAt: exportedAt,
            appVersion: nil,
            recordCounts: payload.recordCounts,
            payloadChecksum: payloadChecksum
        )
        let package = MingZhangBackupPackage(format: backupPackageFormat, manifest: manifest, payload: payload)
        let data = try backupJSONEncoder().encode(package)
        return BackupPackageResult(
            data: data,
            fileName: "mingzhang-backup-\(fileTimestamp(exportedAt)).mzbackup",
            manifest: manifest
        )
    }

    public func validateBackupPackage(data: Data) throws -> BackupValidationResult {
        try inspectBackupPackage(data).result
    }

    public func restoreBackupPackage(data: Data, confirmed: Bool) throws -> BackupRestoreResult {
        guard confirmed else {
            throw MingZhangError.validation("恢复前必须明确确认")
        }
        let inspected = try inspectBackupPackage(data)
        guard inspected.result.isValid, let package = inspected.package, let preview = inspected.result.preview else {
            throw MingZhangError.validation(inspected.result.errors.joined(separator: "；"))
        }

        try database.writer.write { db in
            try replaceBackupPayload(package.payload, in: db)
        }

        return BackupRestoreResult(
            recordCounts: package.manifest.recordCounts,
            restoredAccountMonths: preview.accountMonths
        )
    }

    public func recalculateAfterMutation(_ mutation: Mutation) throws -> EngineRecalculationResult {
        let record = try database.writer.read { db in
            try requireJournalRecord(db, id: mutation.recordId)
        }

        guard record.recordSource.triggersEngine else {
            return .empty
        }

        return try recalculateAccountMonths(startingAt: record.accountMonth)
    }

    @discardableResult
    private func recalculateAccountMonth(_ accountMonth: String) throws -> EngineRecalculationResult {
        try database.writer.write { db in
            let rows = try fetchSourceRecordsWithSemantics(db, accountMonth: accountMonth)
            let now = Date()
            let accountingMethod = try requirePaymentMethodBySeedKey(db, seedKey: "accounting")
            let defaultType = try requirePaymentTypeBySeedKey(db, seedKey: "essential_expense")
            let defaultDetail = try requirePaymentDetailBySeedKey(db, seedKey: "essential_food")
            var createdIds: [UUID] = []
            var updatedIds: [UUID] = []
            var deletedIds: [UUID] = []

            let expectedDrafts = try makeEngineDrafts(db, accountMonth: accountMonth, rows: rows)
            let existingRecords = try fetchEngineRecords(db, accountMonth: accountMonth)
            let existingRecordsByKey = Dictionary(
                uniqueKeysWithValues: existingRecords.compactMap { record in
                    record.engineKey.map { ($0, record) }
                }
            )
            let expectedKeys = Set(expectedDrafts.map(\.engineKey))

            for draft in expectedDrafts {
                if let existing = existingRecordsByKey[draft.engineKey] {
                    guard engineRecordNeedsUpdate(
                        existing,
                        draft: draft,
                        accountingMethod: accountingMethod,
                        paymentType: defaultType,
                        paymentDetail: defaultDetail
                    ) else {
                        continue
                    }
                    let updatedRecord = makeEngineRecord(
                        draft: draft,
                        id: existing.id,
                        accountingMethod: accountingMethod,
                        paymentType: defaultType,
                        paymentDetail: defaultDetail,
                        createdAt: existing.createdAt,
                        updatedAt: now
                    )
                    try persistJournalRecordUpdate(db, record: updatedRecord)
                    updatedIds.append(existing.id)
                } else {
                    let id = UUID()
                    let record = makeEngineRecord(
                        draft: draft,
                        id: id,
                        accountingMethod: accountingMethod,
                        paymentType: defaultType,
                        paymentDetail: defaultDetail,
                        createdAt: now,
                        updatedAt: now
                    )
                    try insertJournalRecord(db, record: record)
                    createdIds.append(id)
                }
            }

            for existing in existingRecords {
                guard let engineKey = existing.engineKey, expectedKeys.contains(engineKey) else {
                    try db.execute(
                        sql: "DELETE FROM journal_records WHERE id = ?",
                        arguments: [existing.id.uuidString]
                    )
                    deletedIds.append(existing.id)
                    continue
                }
            }

            return EngineRecalculationResult(
                recalculatedMonths: [accountMonth],
                createdEngineRecordIds: createdIds,
                updatedEngineRecordIds: updatedIds,
                deletedEngineRecordIds: deletedIds,
                warnings: []
            )
        }
    }

    @discardableResult
    private func recalculateAccountMonths(startingAt accountMonth: String) throws -> EngineRecalculationResult {
        try validateAccountMonth(accountMonth)
        let months = try database.writer.read { db in
            var values = try String.fetchAll(db, sql: """
                SELECT DISTINCT account_month
                FROM journal_records
                WHERE account_month >= ?
                ORDER BY account_month ASC
                """, arguments: [accountMonth])
            if !values.contains(accountMonth) {
                values.insert(accountMonth, at: 0)
            }
            return values
        }

        var result = EngineRecalculationResult.empty
        for month in months {
            let monthResult = try recalculateAccountMonth(month)
            result.recalculatedMonths.append(contentsOf: monthResult.recalculatedMonths)
            result.createdEngineRecordIds.append(contentsOf: monthResult.createdEngineRecordIds)
            result.updatedEngineRecordIds.append(contentsOf: monthResult.updatedEngineRecordIds)
            result.deletedEngineRecordIds.append(contentsOf: monthResult.deletedEngineRecordIds)
            result.warnings.append(contentsOf: monthResult.warnings)
        }
        return result
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

private struct LiabilityMovementAccumulator {
    var name: String
    var objectKey: String
    var formedAmount: Decimal = 0
    var repaidAmount: Decimal = 0
    var costAmount: Decimal = 0
    var formationSourceRecordIds: [UUID] = []
    var repaymentSourceRecordIds: [UUID] = []
    var costSourceRecordIds: [UUID] = []
    var hasCurrentMonthMovement = false

    var remainingAmount: Decimal {
        formedAmount + costAmount - repaidAmount
    }

    var sourceRecordIds: [UUID] {
        uniqueUUIDs(formationSourceRecordIds + repaymentSourceRecordIds + costSourceRecordIds)
    }
}

private struct EngineRecordDraft {
    var accountMonth: String
    var occurredAt: Date
    var amount: Decimal
    var note: String
    var engineFamily: EngineFamily
    var engineKey: String
    var objectKey: String
    var sourceRecordIds: [UUID]
    var sourceInvestmentTransactionIds: [UUID]
}

private enum InvestmentFeedKind {
    case bookAmount
    case realizedGain
    case realizedLoss
}

private struct ImportMemoryKey: Hashable {
    var source: ImportSource
    var counterparty: String
    var product: String
}

private struct ImportMemoryClassification: Hashable {
    var paymentTypeId: UUID
    var paymentTypeName: String
    var paymentDetailId: UUID
    var paymentDetailName: String
}

private struct ParsedImportRow {
    var lineNumber: Int
    var rawPayload: String
    var accountMonth: String
    var occurredAt: Date
    var paymentMethodName: String?
    var amount: Decimal
    var note: String?
    var rawTransactionId: String?
    var rawFingerprint: String
    var memoryKey: ImportMemoryKey?
}

private struct ImportParseResult {
    var rows: [ParsedImportRow]
    var issues: [ImportIssue]
}

private struct PaymentMethodSeed {
    var seedKey: String
    var name: String
    var methodType: PaymentMethodType
    var semanticTags: [String]
}

private struct PaymentTypeSeed {
    var seedKey: String
    var name: String
    var element: AccountingElement
    var semanticTags: [String]
    var configDescription: String?
}

private struct PaymentDetailSeed {
    var seedKey: String
    var paymentTypeSeedKey: String
    var name: String
    var semanticTags: [String]
    var configDescription: String?
}

private let backupPackageFormat = "mingzhang.backup"
private let currentBackupSchemaVersion = 1
private let currentAppDataSchemaVersion = "v4_p1_settings_semantics"

private struct MingZhangBackupPackage: Codable, Equatable {
    var format: String
    var manifest: BackupManifest
    var payload: BackupPayload
}

private struct BackupPayload: Codable, Equatable {
    var paymentMethods: [BackupPaymentMethodRow]
    var paymentTypes: [BackupPaymentTypeRow]
    var paymentDetails: [BackupPaymentDetailRow]
    var importBatches: [BackupImportBatchRow]
    var investmentTransactions: [BackupInvestmentTransactionRow]
    var journalRecords: [BackupJournalRecordRow]
    var importCandidates: [BackupImportCandidateRow]

    var recordCounts: BackupRecordCounts {
        BackupRecordCounts(
            paymentMethods: paymentMethods.count,
            paymentTypes: paymentTypes.count,
            paymentDetails: paymentDetails.count,
            importBatches: importBatches.count,
            investmentTransactions: investmentTransactions.count,
            journalRecords: journalRecords.count,
            importCandidates: importCandidates.count
        )
    }

    var accountMonths: [String] {
        Array(Set(journalRecords.map(\.accountMonth)))
            .sorted(by: >)
    }
}

private struct BackupPaymentMethodRow: Codable, Equatable {
    var id: String
    var name: String
    var methodType: String
    var isActive: Bool
    var semanticTags: String
    var configVersion: Int
    var seedKey: String?
    var createdAt: String
    var updatedAt: String
}

private struct BackupPaymentTypeRow: Codable, Equatable {
    var id: String
    var name: String
    var element: String
    var isActive: Bool
    var semanticTags: String
    var configDescription: String?
    var configVersion: Int
    var seedKey: String?
    var createdAt: String
    var updatedAt: String
}

private struct BackupPaymentDetailRow: Codable, Equatable {
    var id: String
    var name: String
    var paymentTypeId: String
    var isActive: Bool
    var semanticTags: String
    var configDescription: String?
    var configVersion: Int
    var seedKey: String?
    var createdAt: String
    var updatedAt: String
}

private struct BackupImportBatchRow: Codable, Equatable {
    var id: String
    var source: String
    var fileName: String?
    var importedAt: String
    var status: String
    var confirmedRecordCount: Int
}

private struct BackupInvestmentTransactionRow: Codable, Equatable {
    var id: String
    var accountMonth: String
    var occurredAt: String
    var fundName: String
    var transactionType: String
    var tradeAmount: String?
    var tradeShare: String?
    var nav: String?
    var note: String?
    var bookAmount: String?
    var realizedGain: String
    var realizedLoss: String
    var holdingShare: String
    var averageCost: String?
    var bookValue: String
    var presentValue: String?
    var createdAt: String
    var updatedAt: String
}

private struct BackupJournalRecordRow: Codable, Equatable {
    var id: String
    var accountMonth: String
    var occurredAt: String
    var paymentMethodId: String
    var amount: String
    var paymentTypeId: String
    var paymentDetailId: String
    var note: String?
    var recordSource: String
    var recordKind: String
    var carryForwardRole: String
    var engineFamily: String?
    var engineKey: String?
    var objectKey: String?
    var sourceRecordIds: String
    var sourceInvestmentTransactionIds: String
    var sourceImportBatchId: String?
    var sourceImportCandidateId: String?
    var createdAt: String
    var updatedAt: String
}

private struct BackupImportCandidateRow: Codable, Equatable {
    var id: String
    var batchId: String
    var status: String
    var accountMonth: String
    var occurredAt: String
    var paymentMethodId: String?
    var paymentMethodName: String?
    var amount: String
    var paymentTypeId: String?
    var paymentTypeName: String?
    var paymentDetailId: String?
    var paymentDetailName: String?
    var objectKey: String?
    var note: String?
    var rawLineNumber: Int
    var rawPayload: String
    var rawTransactionId: String?
    var rawFingerprint: String
    var createdJournalRecordId: String?
    var createdAt: String
    var updatedAt: String
}

private let paymentMethodSeeds: [PaymentMethodSeed] = [
    PaymentMethodSeed(seedKey: "cash", name: "现金", methodType: .asset, semanticTags: ["资产型"]),
    PaymentMethodSeed(seedKey: "wallet", name: "电子钱包余额", methodType: .asset, semanticTags: ["资产型"]),
    PaymentMethodSeed(seedKey: "huabei", name: "花呗", methodType: .liability, semanticTags: ["负债型"]),
    PaymentMethodSeed(seedKey: "cgb_card", name: "广发卡", methodType: .liability, semanticTags: ["负债型"]),
    PaymentMethodSeed(seedKey: "cmb_card", name: "招商卡", methodType: .liability, semanticTags: ["负债型"]),
    PaymentMethodSeed(seedKey: "pingan_card", name: "平安卡", methodType: .liability, semanticTags: ["负债型"]),
    PaymentMethodSeed(seedKey: "beijing_card", name: "北京卡", methodType: .liability, semanticTags: ["负债型"]),
    PaymentMethodSeed(seedKey: "ant_card", name: "蚂蚁卡", methodType: .liability, semanticTags: ["负债型"]),
    PaymentMethodSeed(seedKey: "jd_baitiao", name: "京东白条", methodType: .liability, semanticTags: ["负债型"]),
    PaymentMethodSeed(seedKey: "accounting", name: "账务处理", methodType: .accounting, semanticTags: ["账务处理型"]),
    PaymentMethodSeed(seedKey: "pending_real_account", name: "待补真实账户", methodType: .pendingRealAccount, semanticTags: ["待补真实账户"])
]

private let paymentTypeSeeds: [PaymentTypeSeed] = [
    PaymentTypeSeed(seedKey: "essential_expense", name: "生活必要开支", element: .expense, semanticTags: ["支出"], configDescription: nil),
    PaymentTypeSeed(seedKey: "leisure_expense", name: "文娱游购开支", element: .expense, semanticTags: ["支出"], configDescription: nil),
    PaymentTypeSeed(seedKey: "finance_expense", name: "财务费用开支", element: .expense, semanticTags: ["支出"], configDescription: nil),
    PaymentTypeSeed(seedKey: "self_investment_expense", name: "投资自身开支", element: .expense, semanticTags: ["支出"], configDescription: nil),
    PaymentTypeSeed(seedKey: "other_necessary_expense", name: "其他必要开支", element: .expense, semanticTags: ["支出"], configDescription: nil),
    PaymentTypeSeed(seedKey: "work_income", name: "工作收入", element: .income, semanticTags: ["收入"], configDescription: nil),
    PaymentTypeSeed(seedKey: "investment_income", name: "理财收入", element: .income, semanticTags: ["收入"], configDescription: nil),
    PaymentTypeSeed(seedKey: "other_income", name: "其他收入", element: .income, semanticTags: ["收入"], configDescription: nil),
    PaymentTypeSeed(seedKey: "asset_outflow", name: "资产类支出", element: .asset, semanticTags: ["资产"], configDescription: nil),
    PaymentTypeSeed(seedKey: "liability_increase", name: "负债类增记", element: .liability, semanticTags: ["负债"], configDescription: nil),
    PaymentTypeSeed(seedKey: "liability_decrease", name: "负债类减记", element: .liability, semanticTags: ["负债"], configDescription: nil)
]

private let paymentDetailSeeds: [PaymentDetailSeed] = [
    PaymentDetailSeed(seedKey: "essential_food", paymentTypeSeedKey: "essential_expense", name: "伙食费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "essential_transport", paymentTypeSeedKey: "essential_expense", name: "交通通信费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "essential_rent", paymentTypeSeedKey: "essential_expense", name: "房租费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "essential_home", paymentTypeSeedKey: "essential_expense", name: "其他必要家用", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "essential_clothing", paymentTypeSeedKey: "essential_expense", name: "必要着装费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "essential_pet", paymentTypeSeedKey: "essential_expense", name: "宠物养育费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "leisure_food_travel", paymentTypeSeedKey: "leisure_expense", name: "饮食游乐费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "leisure_shopping", paymentTypeSeedKey: "leisure_expense", name: "日常购物费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "leisure_large_purchase", paymentTypeSeedKey: "leisure_expense", name: "大件购置费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "finance_interest", paymentTypeSeedKey: "finance_expense", name: "金融利息支出", semanticTags: ["金融费用"], configDescription: nil),
    PaymentDetailSeed(seedKey: "finance_fee_penalty", paymentTypeSeedKey: "finance_expense", name: "金融手续费与罚款", semanticTags: ["金融费用"], configDescription: nil),
    PaymentDetailSeed(seedKey: "finance_investment_loss", paymentTypeSeedKey: "finance_expense", name: "投资亏损", semanticTags: ["已实现投资亏损"], configDescription: nil),
    PaymentDetailSeed(seedKey: "finance_cashout", paymentTypeSeedKey: "finance_expense", name: "账单套现", semanticTags: ["金融费用"], configDescription: nil),
    PaymentDetailSeed(seedKey: "self_education", paymentTypeSeedKey: "self_investment_expense", name: "教育费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "self_book", paymentTypeSeedKey: "self_investment_expense", name: "图书费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "self_office_printing", paymentTypeSeedKey: "self_investment_expense", name: "办公文印费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "self_fitness", paymentTypeSeedKey: "self_investment_expense", name: "健身训练费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "other_parent_support", paymentTypeSeedKey: "other_necessary_expense", name: "父母亲人赡养费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "other_relationship", paymentTypeSeedKey: "other_necessary_expense", name: "人情费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "other_insurance", paymentTypeSeedKey: "other_necessary_expense", name: "保险费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "other_medical", paymentTypeSeedKey: "other_necessary_expense", name: "医疗费", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "work_salary", paymentTypeSeedKey: "work_income", name: "到手工资", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "work_social_security", paymentTypeSeedKey: "work_income", name: "社保", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "work_housing_fund", paymentTypeSeedKey: "work_income", name: "公积金", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "work_non_cash_benefit", paymentTypeSeedKey: "work_income", name: "非货币性福利", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "work_part_time", paymentTypeSeedKey: "work_income", name: "兼职收入", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "work_bonus", paymentTypeSeedKey: "work_income", name: "奖金", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "investment_money_market_income", paymentTypeSeedKey: "investment_income", name: "货币理财收入", semanticTags: ["已实现投资收益"], configDescription: nil),
    PaymentDetailSeed(seedKey: "investment_equity_income", paymentTypeSeedKey: "investment_income", name: "权益理财收入", semanticTags: ["已实现投资收益"], configDescription: nil),
    PaymentDetailSeed(seedKey: "investment_bond_income", paymentTypeSeedKey: "investment_income", name: "债券理财收入", semanticTags: ["已实现投资收益"], configDescription: nil),
    PaymentDetailSeed(seedKey: "investment_generic_income", paymentTypeSeedKey: "investment_income", name: "投资收益", semanticTags: ["已实现投资收益"], configDescription: nil),
    PaymentDetailSeed(seedKey: "other_income_generic", paymentTypeSeedKey: "other_income", name: "其他收入", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "other_income_parent", paymentTypeSeedKey: "other_income", name: "父母资助", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "other_income_social_security_return", paymentTypeSeedKey: "other_income", name: "社保返还", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_bill_accrual", paymentTypeSeedKey: "liability_increase", name: "账单补记", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_bank_loan", paymentTypeSeedKey: "liability_increase", name: "银行借款", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_cash_installment", paymentTypeSeedKey: "liability_increase", name: "现金分期", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_bill_installment", paymentTypeSeedKey: "liability_increase", name: "账单分期", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_purchase_installment", paymentTypeSeedKey: "liability_increase", name: "消费分期", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_family_loan", paymentTypeSeedKey: "liability_increase", name: "亲朋借款", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_bill_repayment", paymentTypeSeedKey: "liability_decrease", name: "账单还款", semanticTags: ["账单还款"], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_bank_loan_repayment", paymentTypeSeedKey: "liability_decrease", name: "银行借款还款", semanticTags: ["账单还款"], configDescription: nil),
    PaymentDetailSeed(seedKey: "liability_family_loan_repayment", paymentTypeSeedKey: "liability_decrease", name: "亲朋借款还款", semanticTags: ["账单还款"], configDescription: nil),
    PaymentDetailSeed(seedKey: "asset_cash_saving", paymentTypeSeedKey: "asset_outflow", name: "现金储蓄", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "asset_dedicated_saving", paymentTypeSeedKey: "asset_outflow", name: "专项储蓄", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "asset_financial_investment", paymentTypeSeedKey: "asset_outflow", name: "金融资产投资", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "asset_personal_account", paymentTypeSeedKey: "asset_outflow", name: "个人账户", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "asset_receivable", paymentTypeSeedKey: "asset_outflow", name: "应收账款", semanticTags: [], configDescription: nil),
    PaymentDetailSeed(seedKey: "asset_deferred_expense", paymentTypeSeedKey: "asset_outflow", name: "长期待摊费用", semanticTags: ["递延资产"], configDescription: nil),
    PaymentDetailSeed(seedKey: "asset_other", paymentTypeSeedKey: "asset_outflow", name: "其他资产类支出", semanticTags: [], configDescription: nil)
]

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
        journal_records.source_investment_transaction_ids,
        journal_records.source_import_batch_id,
        journal_records.source_import_candidate_id,
        journal_records.created_at,
        journal_records.updated_at
    FROM journal_records
    JOIN payment_methods ON payment_methods.id = journal_records.payment_method_id
    JOIN payment_types ON payment_types.id = journal_records.payment_type_id
    JOIN payment_details ON payment_details.id = journal_records.payment_detail_id
    """

private func fetchBackupPayload(_ db: Database) throws -> BackupPayload {
    BackupPayload(
        paymentMethods: try Row.fetchAll(db, sql: """
            SELECT id, name, method_type, is_active, semantic_tags, config_version, seed_key, created_at, updated_at
            FROM payment_methods
            ORDER BY name ASC, id ASC
            """).map(backupPaymentMethod(from:)),
        paymentTypes: try Row.fetchAll(db, sql: """
            SELECT id, name, element, is_active, semantic_tags, config_description, config_version, seed_key, created_at, updated_at
            FROM payment_types
            ORDER BY name ASC, id ASC
            """).map(backupPaymentType(from:)),
        paymentDetails: try Row.fetchAll(db, sql: """
            SELECT id, name, payment_type_id, is_active, semantic_tags, config_description, config_version, seed_key, created_at, updated_at
            FROM payment_details
            ORDER BY payment_type_id ASC, name ASC, id ASC
            """).map(backupPaymentDetail(from:)),
        importBatches: try Row.fetchAll(db, sql: """
            SELECT id, source, file_name, imported_at, status, confirmed_record_count
            FROM import_batches
            ORDER BY imported_at ASC, id ASC
            """).map(backupImportBatch(from:)),
        investmentTransactions: try Row.fetchAll(db, sql: """
            SELECT id, account_month, occurred_at, fund_name, transaction_type,
                   trade_amount, trade_share, nav, note, book_amount, realized_gain,
                   realized_loss, holding_share, average_cost, book_value, present_value,
                   created_at, updated_at
            FROM investment_transactions
            ORDER BY fund_name ASC, occurred_at ASC, created_at ASC, id ASC
            """).map(backupInvestmentTransaction(from:)),
        journalRecords: try Row.fetchAll(db, sql: """
            SELECT id, account_month, occurred_at, payment_method_id, amount, payment_type_id,
                   payment_detail_id, note, record_source, record_kind, carry_forward_role,
                   engine_family, engine_key, object_key, source_record_ids,
                   source_investment_transaction_ids, source_import_batch_id,
                   source_import_candidate_id, created_at, updated_at
            FROM journal_records
            ORDER BY account_month ASC, occurred_at ASC, created_at ASC, id ASC
            """).map(backupJournalRecord(from:)),
        importCandidates: try Row.fetchAll(db, sql: """
            SELECT id, batch_id, status, account_month, occurred_at, payment_method_id,
                   payment_method_name, amount, payment_type_id, payment_type_name,
                   payment_detail_id, payment_detail_name, object_key, note, raw_line_number,
                   raw_payload, raw_transaction_id, raw_fingerprint, created_journal_record_id,
                   created_at, updated_at
            FROM import_candidates
            ORDER BY batch_id ASC, occurred_at ASC, raw_line_number ASC, id ASC
            """).map(backupImportCandidate(from:))
    )
}

private func replaceBackupPayload(_ payload: BackupPayload, in db: Database) throws {
    try db.execute(sql: "DELETE FROM import_candidates")
    try db.execute(sql: "DELETE FROM journal_records")
    try db.execute(sql: "DELETE FROM investment_transactions")
    try db.execute(sql: "DELETE FROM import_batches")
    try db.execute(sql: "DELETE FROM payment_details")
    try db.execute(sql: "DELETE FROM payment_types")
    try db.execute(sql: "DELETE FROM payment_methods")

    for row in payload.paymentMethods {
        try db.execute(sql: """
            INSERT INTO payment_methods (id, name, method_type, is_active, semantic_tags, config_version, seed_key, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                row.id,
                row.name,
                row.methodType,
                row.isActive,
                row.semanticTags,
                row.configVersion,
                row.seedKey,
                row.createdAt,
                row.updatedAt
            ])
    }

    for row in payload.paymentTypes {
        try db.execute(sql: """
            INSERT INTO payment_types (id, name, element, is_active, semantic_tags, config_description, config_version, seed_key, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                row.id,
                row.name,
                row.element,
                row.isActive,
                row.semanticTags,
                row.configDescription,
                row.configVersion,
                row.seedKey,
                row.createdAt,
                row.updatedAt
            ])
    }

    for row in payload.paymentDetails {
        try db.execute(sql: """
            INSERT INTO payment_details (id, name, payment_type_id, is_active, semantic_tags, config_description, config_version, seed_key, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                row.id,
                row.name,
                row.paymentTypeId,
                row.isActive,
                row.semanticTags,
                row.configDescription,
                row.configVersion,
                row.seedKey,
                row.createdAt,
                row.updatedAt
            ])
    }

    for row in payload.importBatches {
        try db.execute(sql: """
            INSERT INTO import_batches (id, source, file_name, imported_at, status, confirmed_record_count)
            VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [
                row.id,
                row.source,
                row.fileName,
                row.importedAt,
                row.status,
                row.confirmedRecordCount
            ])
    }

    for row in payload.investmentTransactions {
        try db.execute(sql: """
            INSERT INTO investment_transactions (
                id, account_month, occurred_at, fund_name, transaction_type,
                trade_amount, trade_share, nav, note, book_amount, realized_gain,
                realized_loss, holding_share, average_cost, book_value, present_value,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                row.id,
                row.accountMonth,
                row.occurredAt,
                row.fundName,
                row.transactionType,
                row.tradeAmount,
                row.tradeShare,
                row.nav,
                row.note,
                row.bookAmount,
                row.realizedGain,
                row.realizedLoss,
                row.holdingShare,
                row.averageCost,
                row.bookValue,
                row.presentValue,
                row.createdAt,
                row.updatedAt
            ])
    }

    for row in payload.journalRecords {
        try db.execute(sql: """
            INSERT INTO journal_records (
                id, account_month, occurred_at, payment_method_id, amount, payment_type_id,
                payment_detail_id, note, record_source, record_kind, carry_forward_role,
                engine_family, engine_key, object_key, source_record_ids,
                source_investment_transaction_ids, source_import_batch_id,
                source_import_candidate_id, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                row.id,
                row.accountMonth,
                row.occurredAt,
                row.paymentMethodId,
                row.amount,
                row.paymentTypeId,
                row.paymentDetailId,
                row.note,
                row.recordSource,
                row.recordKind,
                row.carryForwardRole,
                row.engineFamily,
                row.engineKey,
                row.objectKey,
                row.sourceRecordIds,
                row.sourceInvestmentTransactionIds,
                row.sourceImportBatchId,
                row.sourceImportCandidateId,
                row.createdAt,
                row.updatedAt
            ])
    }

    for row in payload.importCandidates {
        try db.execute(sql: """
            INSERT INTO import_candidates (
                id, batch_id, status, account_month, occurred_at, payment_method_id,
                payment_method_name, amount, payment_type_id, payment_type_name,
                payment_detail_id, payment_detail_name, object_key, note, raw_line_number,
                raw_payload, raw_transaction_id, raw_fingerprint, created_journal_record_id,
                created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                row.id,
                row.batchId,
                row.status,
                row.accountMonth,
                row.occurredAt,
                row.paymentMethodId,
                row.paymentMethodName,
                row.amount,
                row.paymentTypeId,
                row.paymentTypeName,
                row.paymentDetailId,
                row.paymentDetailName,
                row.objectKey,
                row.note,
                row.rawLineNumber,
                row.rawPayload,
                row.rawTransactionId,
                row.rawFingerprint,
                row.createdJournalRecordId,
                row.createdAt,
                row.updatedAt
            ])
    }
}

private func sqlPlaceholders(_ count: Int) -> String {
    "(\(Array(repeating: "?", count: count).joined(separator: ",")))"
}

private func rowExists(_ db: Database, table: String, column: String, value: String) throws -> Bool {
    let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM \(table) WHERE \(column) = ?",
        arguments: [value]
    ) ?? 0
    return count > 0
}

private func fillSeedMetadataIfNeeded(
    _ db: Database,
    table: String,
    seedKey: String,
    semanticTags: [String]
) throws {
    try db.execute(sql: """
        UPDATE \(table)
        SET semantic_tags = CASE WHEN semantic_tags = '[]' THEN ? ELSE semantic_tags END,
            config_version = CASE WHEN config_version IS NULL THEN 1 ELSE config_version END
        WHERE seed_key = ?
        """, arguments: [encodeStringList(semanticTags), seedKey])
}

private func insertPaymentMethodIfNeeded(
    _ db: Database,
    seedKey: String,
    name: String,
    methodType: PaymentMethodType,
    semanticTags: [String],
    now: Date
) throws {
    if try rowExists(db, table: "payment_methods", column: "seed_key", value: seedKey) {
        try fillSeedMetadataIfNeeded(db, table: "payment_methods", seedKey: seedKey, semanticTags: semanticTags)
        return
    }
    if try rowExists(db, table: "payment_methods", column: "name", value: name) {
        try db.execute(sql: """
            UPDATE payment_methods
            SET seed_key = ?,
                semantic_tags = CASE WHEN semantic_tags = '[]' THEN ? ELSE semantic_tags END,
                config_version = CASE WHEN config_version IS NULL THEN 1 ELSE config_version END
            WHERE name = ? AND seed_key IS NULL
            """, arguments: [seedKey, encodeStringList(semanticTags), name])
        return
    }

    try db.execute(sql: """
        INSERT INTO payment_methods (id, name, method_type, is_active, semantic_tags, config_version, seed_key, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
        UUID().uuidString,
        name,
        methodType.rawValue,
        true,
        encodeStringList(semanticTags),
        1,
        seedKey,
        encodeDate(now),
        encodeDate(now)
    ])
}

@discardableResult
private func insertPaymentTypeIfNeeded(
    _ db: Database,
    seedKey: String,
    name: String,
    element: AccountingElement,
    semanticTags: [String],
    configDescription: String?,
    now: Date
) throws -> PaymentType {
    if let existing = try paymentTypeBySeedKey(db, seedKey: seedKey) {
        try fillSeedMetadataIfNeeded(db, table: "payment_types", seedKey: seedKey, semanticTags: semanticTags)
        return existing
    }
    if try rowExists(db, table: "payment_types", column: "name", value: name) {
        try db.execute(sql: """
            UPDATE payment_types
            SET seed_key = ?,
                semantic_tags = CASE WHEN semantic_tags = '[]' THEN ? ELSE semantic_tags END,
                config_description = COALESCE(config_description, ?),
                config_version = CASE WHEN config_version IS NULL THEN 1 ELSE config_version END
            WHERE name = ? AND seed_key IS NULL
            """, arguments: [seedKey, encodeStringList(semanticTags), configDescription, name])
        return try requirePaymentType(db, name: name)
    }

    try db.execute(sql: """
        INSERT INTO payment_types (id, name, element, is_active, semantic_tags, config_description, config_version, seed_key, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
        UUID().uuidString,
        name,
        element.rawValue,
        true,
        encodeStringList(semanticTags),
        configDescription,
        1,
        seedKey,
        encodeDate(now),
        encodeDate(now)
    ])
    return try requirePaymentTypeBySeedKey(db, seedKey: seedKey)
}

private func insertPaymentDetailIfNeeded(
    _ db: Database,
    seedKey: String,
    name: String,
    paymentTypeId: UUID,
    semanticTags: [String],
    configDescription: String?,
    now: Date
) throws {
    if try rowExists(db, table: "payment_details", column: "seed_key", value: seedKey) {
        try fillSeedMetadataIfNeeded(db, table: "payment_details", seedKey: seedKey, semanticTags: semanticTags)
        return
    }
    let existing = try Row.fetchOne(
        db,
        sql: "SELECT id FROM payment_details WHERE name = ? AND payment_type_id = ? AND seed_key IS NULL",
        arguments: [name, paymentTypeId.uuidString]
    )
    if existing != nil {
        try db.execute(sql: """
            UPDATE payment_details
            SET seed_key = ?,
                semantic_tags = CASE WHEN semantic_tags = '[]' THEN ? ELSE semantic_tags END,
                config_description = COALESCE(config_description, ?),
                config_version = CASE WHEN config_version IS NULL THEN 1 ELSE config_version END
            WHERE name = ? AND payment_type_id = ? AND seed_key IS NULL
            """, arguments: [seedKey, encodeStringList(semanticTags), configDescription, name, paymentTypeId.uuidString])
        return
    }

    try db.execute(sql: """
        INSERT INTO payment_details (id, name, payment_type_id, is_active, semantic_tags, config_description, config_version, seed_key, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: [
        UUID().uuidString,
        name,
        paymentTypeId.uuidString,
        true,
        encodeStringList(semanticTags),
        configDescription,
        1,
        seedKey,
        encodeDate(now),
        encodeDate(now)
    ])
}

private func insertImportBatch(_ db: Database, batch: ImportBatch) throws {
    try db.execute(sql: """
        INSERT INTO import_batches (id, source, file_name, imported_at, status, confirmed_record_count)
        VALUES (?, ?, ?, ?, ?, ?)
        """, arguments: [
            batch.id.uuidString,
            batch.source.rawValue,
            batch.fileName,
            encodeDate(batch.importedAt),
            batch.status.rawValue,
            batch.confirmedRecordCount
        ])
}

private func insertImportCandidate(_ db: Database, candidate: ImportCandidateRecord, now: Date) throws {
    try db.execute(sql: """
        INSERT INTO import_candidates (
            id, batch_id, status, account_month, occurred_at, payment_method_id,
            payment_method_name, amount, payment_type_id, payment_type_name,
            payment_detail_id, payment_detail_name, object_key, note, raw_line_number,
            raw_payload, raw_transaction_id, raw_fingerprint, created_journal_record_id,
            created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: importCandidateArguments(candidate, createdAt: now, updatedAt: now))
}

private func loadImportMemoryIndex(_ db: Database, source: ImportSource) throws -> [ImportMemoryKey: ImportMemoryClassification] {
    let rows = try Row.fetchAll(db, sql: """
        SELECT
            import_candidates.raw_payload,
            journal_records.payment_type_id,
            payment_types.name AS payment_type_name,
            journal_records.payment_detail_id,
            payment_details.name AS payment_detail_name
        FROM import_candidates
        JOIN import_batches ON import_batches.id = import_candidates.batch_id
        JOIN journal_records ON journal_records.source_import_candidate_id = import_candidates.id
        JOIN payment_types ON payment_types.id = journal_records.payment_type_id
        JOIN payment_details ON payment_details.id = journal_records.payment_detail_id
        WHERE import_batches.source = ?
          AND import_candidates.status = ?
          AND journal_records.record_source = ?
        """, arguments: [
            source.rawValue,
            ImportCandidateStatus.confirmed.rawValue,
            RecordSource.import.rawValue
        ])

    var classificationsByKey: [ImportMemoryKey: Set<ImportMemoryClassification>] = [:]
    for row in rows {
        let rawPayload: String = row["raw_payload"]
        guard let key = importMemoryKey(source: source, rawPayload: rawPayload) else { continue }
        let classification = ImportMemoryClassification(
            paymentTypeId: try requireUUID(row["payment_type_id"]),
            paymentTypeName: row["payment_type_name"],
            paymentDetailId: try requireUUID(row["payment_detail_id"]),
            paymentDetailName: row["payment_detail_name"]
        )
        classificationsByKey[key, default: []].insert(classification)
    }

    return classificationsByKey.compactMapValues { classifications in
        classifications.count == 1 ? classifications.first : nil
    }
}

private func persistImportCandidateUpdate(_ db: Database, candidate: ImportCandidateRecord, updatedAt: Date) throws {
    let currentCreatedAt = try String.fetchOne(
        db,
        sql: "SELECT created_at FROM import_candidates WHERE id = ?",
        arguments: [candidate.id.uuidString]
    ) ?? encodeDate(updatedAt)
    var arguments = importCandidateArguments(candidate, createdAt: try decodeDate(currentCreatedAt), updatedAt: updatedAt)
    arguments += [candidate.id.uuidString]
    try db.execute(sql: """
        UPDATE import_candidates SET
            id = ?, batch_id = ?, status = ?, account_month = ?, occurred_at = ?,
            payment_method_id = ?, payment_method_name = ?, amount = ?, payment_type_id = ?,
            payment_type_name = ?, payment_detail_id = ?, payment_detail_name = ?, object_key = ?,
            note = ?, raw_line_number = ?, raw_payload = ?, raw_transaction_id = ?,
            raw_fingerprint = ?, created_journal_record_id = ?, created_at = ?, updated_at = ?
        WHERE id = ?
        """, arguments: arguments)
}

private func importCandidateArguments(
    _ candidate: ImportCandidateRecord,
    createdAt: Date,
    updatedAt: Date
) -> StatementArguments {
    [
        candidate.id.uuidString,
        candidate.batchId.uuidString,
        candidate.status.rawValue,
        candidate.accountMonth,
        encodeDate(candidate.occurredAt),
        candidate.paymentMethodId?.uuidString,
        candidate.paymentMethodName,
        encodeDecimal(candidate.amount),
        candidate.paymentTypeId?.uuidString,
        candidate.paymentTypeName,
        candidate.paymentDetailId?.uuidString,
        candidate.paymentDetailName,
        candidate.objectKey,
        candidate.note,
        candidate.rawLineNumber,
        candidate.rawPayload,
        candidate.rawTransactionId,
        candidate.rawFingerprint,
        candidate.createdJournalRecordId?.uuidString,
        encodeDate(createdAt),
        encodeDate(updatedAt)
    ]
}

private func insertInvestmentTransaction(_ db: Database, transaction: InvestmentTransaction) throws {
    try db.execute(sql: """
        INSERT INTO investment_transactions (
            id, account_month, occurred_at, fund_name, transaction_type,
            trade_amount, trade_share, nav, note, book_amount, realized_gain,
            realized_loss, holding_share, average_cost, book_value, present_value,
            created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, arguments: investmentTransactionArguments(transaction))
}

private func persistInvestmentTransactionUpdate(_ db: Database, transaction: InvestmentTransaction) throws {
    var arguments = investmentTransactionArguments(transaction)
    arguments += [transaction.id.uuidString]
    try db.execute(sql: """
        UPDATE investment_transactions SET
            id = ?, account_month = ?, occurred_at = ?, fund_name = ?, transaction_type = ?,
            trade_amount = ?, trade_share = ?, nav = ?, note = ?, book_amount = ?,
            realized_gain = ?, realized_loss = ?, holding_share = ?, average_cost = ?,
            book_value = ?, present_value = ?, created_at = ?, updated_at = ?
        WHERE id = ?
        """, arguments: arguments)
}

private func investmentTransactionArguments(_ transaction: InvestmentTransaction) -> StatementArguments {
    [
        transaction.id.uuidString,
        transaction.accountMonth,
        encodeDate(transaction.occurredAt),
        transaction.fundName,
        transaction.transactionType.rawValue,
        transaction.tradeAmount.map(encodeDecimal),
        transaction.tradeShare.map(encodeDecimal),
        transaction.nav.map(encodeDecimal),
        transaction.note,
        transaction.bookAmount.map(encodeDecimal),
        encodeDecimal(transaction.realizedGain),
        encodeDecimal(transaction.realizedLoss),
        encodeDecimal(transaction.holdingShare),
        transaction.averageCost.map(encodeDecimal),
        encodeDecimal(transaction.bookValue),
        transaction.presentValue.map(encodeDecimal),
        encodeDate(transaction.createdAt),
        encodeDate(transaction.updatedAt)
    ]
}

private func insertJournalRecord(_ db: Database, record: JournalRecord) throws {
    try db.execute(sql: """
        INSERT INTO journal_records (
            id, account_month, occurred_at, payment_method_id, amount, payment_type_id,
            payment_detail_id, note, record_source, record_kind, carry_forward_role,
            engine_family, engine_key, object_key, source_record_ids,
            source_investment_transaction_ids, source_import_batch_id,
            source_import_candidate_id, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
            object_key = ?, source_record_ids = ?, source_investment_transaction_ids = ?,
            source_import_batch_id = ?, source_import_candidate_id = ?, created_at = ?,
            updated_at = ?
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
        encodeUUIDList(record.sourceInvestmentTransactionIds),
        record.sourceImportBatchId?.uuidString,
        record.sourceImportCandidateId?.uuidString,
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

private func fetchSourceRecordsWithSemanticsThrough(_ db: Database, accountMonth: String) throws -> [SemanticRecordRow] {
    let rows = try Row.fetchAll(db, sql: """
        \(selectJournalRecordSQL)
        WHERE journal_records.account_month <= ?
          AND journal_records.record_source != ?
        ORDER BY journal_records.account_month ASC, journal_records.occurred_at ASC, journal_records.created_at ASC
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

private func fetchInvestmentTransactions(_ db: Database, fundName: String? = nil) throws -> [InvestmentTransaction] {
    var sql = """
        SELECT id, account_month, occurred_at, fund_name, transaction_type,
               trade_amount, trade_share, nav, note, book_amount, realized_gain,
               realized_loss, holding_share, average_cost, book_value, present_value,
               created_at, updated_at
        FROM investment_transactions
        """
    var arguments = StatementArguments()
    if let fundName {
        sql += " WHERE fund_name = ?"
        arguments += [fundName]
    }
    sql += " ORDER BY occurred_at ASC, created_at ASC, id ASC"
    return try Row.fetchAll(db, sql: sql, arguments: arguments).map(investmentTransaction(from:))
}

private func fetchInvestmentTransactions(_ db: Database, ids: [UUID]) throws -> [InvestmentTransaction] {
    guard !ids.isEmpty else { return [] }
    let rows = try Row.fetchAll(db, sql: """
        SELECT id, account_month, occurred_at, fund_name, transaction_type,
               trade_amount, trade_share, nav, note, book_amount, realized_gain,
               realized_loss, holding_share, average_cost, book_value, present_value,
               created_at, updated_at
        FROM investment_transactions
        WHERE id IN \(sqlPlaceholders(ids.count))
        """, arguments: StatementArguments(ids.map(\.uuidString)))
        .map(investmentTransaction(from:))
    let transactionsById = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
    return ids.compactMap { transactionsById[$0] }
}

private func fetchInvestmentFeedRecords(
    _ db: Database,
    accountMonth: String,
    fundName: String? = nil
) throws -> [JournalRecord] {
    try validateAccountMonth(accountMonth)
    var sql = """
        \(selectJournalRecordSQL)
        WHERE journal_records.account_month = ?
          AND journal_records.record_source = ?
        """
    var arguments: StatementArguments = [
        accountMonth,
        RecordSource.investmentFeed.rawValue
    ]
    if let fundName {
        sql += " AND journal_records.object_key = ?"
        arguments += ["investment:\(fundName)"]
    }
    sql += " ORDER BY journal_records.occurred_at ASC, journal_records.created_at ASC"
    return try Row.fetchAll(db, sql: sql, arguments: arguments).map(journalRecord(from:))
}

private func recalculateInvestmentLedger(_ db: Database, fundName: String) throws -> Set<String> {
    let transactions = try fetchInvestmentTransactions(db, fundName: fundName)
    let affectedMonths = Set(transactions.map(\.accountMonth))
    var holdingShare = Decimal(0)
    var bookValue = Decimal(0)
    var latestNav: Decimal?

    for var transaction in transactions {
        transaction.realizedGain = 0
        transaction.realizedLoss = 0
        transaction.bookAmount = nil

        switch transaction.transactionType {
        case .buy:
            let amount = transaction.tradeAmount ?? 0
            let share = transaction.tradeShare ?? 0
            transaction.bookAmount = roundCurrency(amount)
            holdingShare += share
            bookValue += amount
        case .sell:
            let amount = transaction.tradeAmount ?? 0
            let share = transaction.tradeShare ?? 0
            guard holdingShare + share >= 0 else {
                throw MingZhangError.validation("卖出份额不能超过当前持仓")
            }
            let averageCost = holdingShare == 0 ? Decimal(0) : bookValue / holdingShare
            let bookAmount = roundCurrency(share * averageCost)
            let realized = absoluteDecimal(amount) - absoluteDecimal(bookAmount)
            transaction.bookAmount = bookAmount
            if realized >= 0 {
                transaction.realizedGain = roundCurrency(realized)
            } else {
                transaction.realizedLoss = roundCurrency(absoluteDecimal(realized))
            }
            holdingShare += share
            bookValue += bookAmount
        case .nav:
            if let nav = transaction.nav {
                latestNav = nav
            }
        }

        if let nav = transaction.nav {
            latestNav = nav
        }
        transaction.holdingShare = roundShare(holdingShare)
        transaction.bookValue = roundCurrency(bookValue)
        transaction.averageCost = holdingShare == 0 ? nil : roundUnitCost(bookValue / holdingShare)
        transaction.presentValue = latestNav.map { roundCurrency(holdingShare * $0) }
        transaction.updatedAt = Date()
        try persistInvestmentTransactionUpdate(db, transaction: transaction)
    }

    return affectedMonths
}

private func fetchInvestmentHoldings(_ db: Database, accountMonth: String) throws -> [InvestmentHolding] {
    try validateAccountMonth(accountMonth)
    let transactions = try fetchInvestmentTransactions(db)
        .filter { $0.accountMonth <= accountMonth }
    let grouped = Dictionary(grouping: transactions) { $0.fundName }

    return grouped.keys.sorted().compactMap { fundName in
        guard let fundTransactions = grouped[fundName], let latest = fundTransactions.last else { return nil }
        guard latest.holdingShare != 0 || latest.bookValue != 0 else { return nil }
        let sourceIds = fundTransactions
            .filter { $0.transactionType == .buy || $0.transactionType == .sell }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }
        let latestNav = fundTransactions.reversed().first { $0.nav != nil }?.nav
        let presentValue = latestNav.map { roundCurrency(latest.holdingShare * $0) }
        return InvestmentHolding(
            fundName: fundName,
            accountMonth: accountMonth,
            holdingShare: latest.holdingShare,
            averageCost: latest.averageCost,
            bookValue: latest.bookValue,
            latestNav: latestNav,
            presentValue: presentValue,
            unrealizedGain: presentValue.map { roundCurrency($0 - latest.bookValue) },
            sourceTransactionIds: sourceIds
        )
    }
}

private func reflowInvestmentFeedRecords(
    _ db: Database,
    fundName: String,
    accountMonths: Set<String>
) throws {
    guard !accountMonths.isEmpty else { return }
    let method = try requirePaymentMethodBySeedKey(db, seedKey: "wallet")
    let assetType = try requirePaymentTypeBySeedKey(db, seedKey: "asset_outflow")
    let assetDetail = try requirePaymentDetailBySeedKey(db, seedKey: "asset_financial_investment")
    let incomeType = try requirePaymentTypeBySeedKey(db, seedKey: "investment_income")
    let incomeDetail = try requirePaymentDetailBySeedKey(db, seedKey: "investment_generic_income")
    let lossType = try requirePaymentTypeBySeedKey(db, seedKey: "finance_expense")
    let lossDetail = try requirePaymentDetailBySeedKey(db, seedKey: "finance_investment_loss")
    let allTransactions = try fetchInvestmentTransactions(db, fundName: fundName)
    let objectKey = "investment:\(fundName)"

    for accountMonth in accountMonths {
        try db.execute(sql: """
            DELETE FROM journal_records
            WHERE record_source = ?
              AND account_month = ?
              AND object_key = ?
            """, arguments: [
                RecordSource.investmentFeed.rawValue,
                accountMonth,
                objectKey
            ])

        let monthTransactions = allTransactions.filter { $0.accountMonth == accountMonth }
        let bookTransactions = monthTransactions.filter { $0.bookAmount != nil }
        let gainTransactions = monthTransactions.filter { $0.realizedGain != 0 }
        let lossTransactions = monthTransactions.filter { $0.realizedLoss != 0 }

        let bookAmount = bookTransactions.reduce(Decimal(0)) { $0 + ($1.bookAmount ?? 0) }
        let realizedGain = gainTransactions.reduce(Decimal(0)) { $0 + $1.realizedGain }
        let realizedLoss = lossTransactions.reduce(Decimal(0)) { $0 + $1.realizedLoss }

        if bookAmount != 0 {
            try insertInvestmentFeedRecord(
                db,
                accountMonth: accountMonth,
                fundName: fundName,
                amount: roundCurrency(bookAmount),
                method: method,
                type: assetType,
                detail: assetDetail,
                kind: .bookAmount,
                sourceTransactionIds: bookTransactions.map(\.id)
            )
        }
        if realizedGain != 0 {
            try insertInvestmentFeedRecord(
                db,
                accountMonth: accountMonth,
                fundName: fundName,
                amount: roundCurrency(realizedGain),
                method: method,
                type: incomeType,
                detail: incomeDetail,
                kind: .realizedGain,
                sourceTransactionIds: gainTransactions.map(\.id)
            )
        }
        if realizedLoss != 0 {
            try insertInvestmentFeedRecord(
                db,
                accountMonth: accountMonth,
                fundName: fundName,
                amount: roundCurrency(realizedLoss),
                method: method,
                type: lossType,
                detail: lossDetail,
                kind: .realizedLoss,
                sourceTransactionIds: lossTransactions.map(\.id)
            )
        }
    }
}

private func insertInvestmentFeedRecord(
    _ db: Database,
    accountMonth: String,
    fundName: String,
    amount: Decimal,
    method: PaymentMethod,
    type: PaymentType,
    detail: PaymentDetail,
    kind: InvestmentFeedKind,
    sourceTransactionIds: [UUID]
) throws {
    let now = Date()
    let kindNote: String
    switch kind {
    case .bookAmount:
        kindNote = "投资成本回填"
    case .realizedGain:
        kindNote = "投资收益回填"
    case .realizedLoss:
        kindNote = "投资亏损回填"
    }
    let record = JournalRecord(
        id: UUID(),
        accountMonth: accountMonth,
        occurredAt: monthEndPlaceholder(accountMonth),
        paymentMethodId: method.id,
        paymentMethodName: method.name,
        amount: amount,
        paymentTypeId: type.id,
        paymentTypeName: type.name,
        paymentDetailId: detail.id,
        paymentDetailName: detail.name,
        note: "\(fundName) \(kindNote)",
        recordSource: .investmentFeed,
        recordKind: .carryForward,
        carryForwardRole: .accountingSkeleton,
        engineFamily: nil,
        engineKey: nil,
        objectKey: "investment:\(fundName)",
        sourceRecordIds: [],
        sourceInvestmentTransactionIds: sourceTransactionIds.sorted { $0.uuidString < $1.uuidString },
        sourceImportBatchId: nil,
        sourceImportCandidateId: nil,
        createdAt: now,
        updatedAt: now
    )
    try insertJournalRecord(db, record: record)
}

private func fetchEngineRecords(_ db: Database, accountMonth: String) throws -> [JournalRecord] {
    try Row.fetchAll(db, sql: """
        \(selectJournalRecordSQL)
        WHERE journal_records.account_month = ?
          AND journal_records.record_source = ?
          AND journal_records.engine_family IN (?, ?, ?)
        ORDER BY journal_records.engine_key ASC
        """, arguments: [
            accountMonth,
            RecordSource.engine.rawValue,
            EngineFamily.cash.rawValue,
            EngineFamily.liability.rawValue,
            EngineFamily.investment.rawValue
        ])
        .map(journalRecord(from:))
}

private func liabilityAccumulators(_ db: Database, through accountMonth: String) throws -> [String: LiabilityMovementAccumulator] {
    let rows = try fetchSourceRecordsWithSemanticsThrough(db, accountMonth: accountMonth)
    var accumulators: [String: LiabilityMovementAccumulator] = [:]

    for row in rows {
        let targetObjectKey: String?
        if let objectKey = normalizedOptionalText(row.record.objectKey) {
            targetObjectKey = objectKey
        } else if row.paymentMethod.methodType == .liability {
            targetObjectKey = liabilityObjectKey(for: row.paymentMethod.name)
        } else {
            targetObjectKey = nil
        }

        guard let objectKey = targetObjectKey, objectKey.hasPrefix("liability:") else {
            continue
        }

        let name = try liabilityName(from: objectKey)
        if accumulators[objectKey] == nil {
            accumulators[objectKey] = LiabilityMovementAccumulator(name: name, objectKey: objectKey)
        }

        let amount = absoluteDecimal(row.record.amount)
        let isCurrentMonth = row.record.accountMonth == accountMonth

        if row.paymentMethod.methodType == .liability && row.paymentType.element == .expense {
            if isLiabilityCost(paymentDetail: row.paymentDetail) {
                accumulators[objectKey]?.costAmount += amount
                accumulators[objectKey]?.costSourceRecordIds.append(row.record.id)
            } else {
                accumulators[objectKey]?.formedAmount += amount
                accumulators[objectKey]?.formationSourceRecordIds.append(row.record.id)
            }
            if isCurrentMonth {
                accumulators[objectKey]?.hasCurrentMonthMovement = true
            }
        } else if isLiabilityIncrease(paymentType: row.paymentType) {
            accumulators[objectKey]?.formedAmount += amount
            accumulators[objectKey]?.formationSourceRecordIds.append(row.record.id)
            if isCurrentMonth {
                accumulators[objectKey]?.hasCurrentMonthMovement = true
            }
        } else if isLiabilityRepayment(paymentType: row.paymentType, paymentDetail: row.paymentDetail) {
            accumulators[objectKey]?.repaidAmount += amount
            accumulators[objectKey]?.repaymentSourceRecordIds.append(row.record.id)
            if isCurrentMonth {
                accumulators[objectKey]?.hasCurrentMonthMovement = true
            }
        }
    }

    return accumulators
}

private func liabilityDetailSummary(
    _ db: Database,
    objectKey: String,
    accountMonth: String
) throws -> LiabilityDetailSummary {
    try validateAccountMonth(accountMonth)
    _ = try liabilityPaymentMethod(db, objectKey: objectKey)
    let accumulator = try liabilityAccumulators(db, through: accountMonth)[objectKey] ??
        LiabilityMovementAccumulator(name: try liabilityName(from: objectKey), objectKey: objectKey)

    return LiabilityDetailSummary(
        name: accumulator.name,
        objectKey: accumulator.objectKey,
        formedAmount: roundCurrency(accumulator.formedAmount),
        repaidAmount: roundCurrency(accumulator.repaidAmount),
        costAmount: roundCurrency(accumulator.costAmount),
        remainingAmount: roundCurrency(accumulator.remainingAmount),
        formationSourceRecordIds: accumulator.formationSourceRecordIds,
        repaymentSourceRecordIds: accumulator.repaymentSourceRecordIds,
        costSourceRecordIds: accumulator.costSourceRecordIds,
        sourceRecordIds: accumulator.sourceRecordIds
    )
}

private func makeEngineDrafts(_ db: Database, accountMonth: String, rows: [SemanticRecordRow]) throws -> [EngineRecordDraft] {
    var drafts: [EngineRecordDraft] = []
    let occurredAt = monthEndPlaceholder(accountMonth)

    let liabilities = try liabilityAccumulators(db, through: accountMonth)
        .values
        .filter { $0.remainingAmount != 0 || $0.hasCurrentMonthMovement }
        .sorted { $0.name < $1.name }

    for liability in liabilities {
        drafts.append(EngineRecordDraft(
            accountMonth: accountMonth,
            occurredAt: occurredAt,
            amount: roundCurrency(liability.remainingAmount),
            note: "\(liability.name) 负债期末余额",
            engineFamily: .liability,
            engineKey: "\(accountMonth):liability:ending_balance:\(liability.objectKey)",
            objectKey: liability.objectKey,
            sourceRecordIds: liability.sourceRecordIds,
            sourceInvestmentTransactionIds: []
        ))
    }

    let cashRows = rows.filter {
        $0.paymentMethod.methodType == .asset &&
            (
                $0.paymentType.element == .expense ||
                    $0.paymentType.element == .asset ||
                    isLiabilityRepayment(paymentType: $0.paymentType, paymentDetail: $0.paymentDetail)
            )
    }
    let cashAmount = cashRows.reduce(Decimal(0)) { $0 - $1.record.amount }
    if cashAmount != Decimal(0) {
        let objectKey = "cash_pool:电子钱包余额"
        drafts.append(EngineRecordDraft(
            accountMonth: accountMonth,
            occurredAt: occurredAt,
            amount: cashAmount,
            note: "现金池期末余额",
            engineFamily: .cash,
            engineKey: "\(accountMonth):cash:ending_balance:\(objectKey)",
            objectKey: objectKey,
            sourceRecordIds: cashRows.map(\.record.id).sorted { $0.uuidString < $1.uuidString },
            sourceInvestmentTransactionIds: cashRows
                .flatMap(\.record.sourceInvestmentTransactionIds)
                .sorted { $0.uuidString < $1.uuidString }
        ))
    }

    let holdingRows = try fetchInvestmentHoldings(db, accountMonth: accountMonth)
    let investmentAmount = holdingRows.reduce(Decimal(0)) { $0 + $1.bookValue }
    if investmentAmount != 0 {
        let objectKey = "investment:总投资资产"
        drafts.append(EngineRecordDraft(
            accountMonth: accountMonth,
            occurredAt: occurredAt,
            amount: roundCurrency(investmentAmount),
            note: "总投资资产期末余额",
            engineFamily: .investment,
            engineKey: "\(accountMonth):investment:ending_balance:\(objectKey)",
            objectKey: objectKey,
            sourceRecordIds: [],
            sourceInvestmentTransactionIds: holdingRows
                .flatMap(\.sourceTransactionIds)
                .sorted { $0.uuidString < $1.uuidString }
        ))
    }

    return drafts.sorted { $0.engineKey < $1.engineKey }
}

private func makeEngineRecord(
    draft: EngineRecordDraft,
    id: UUID,
    accountingMethod: PaymentMethod,
    paymentType: PaymentType,
    paymentDetail: PaymentDetail,
    createdAt: Date,
    updatedAt: Date
) -> JournalRecord {
    JournalRecord(
        id: id,
        accountMonth: draft.accountMonth,
        occurredAt: draft.occurredAt,
        paymentMethodId: accountingMethod.id,
        paymentMethodName: accountingMethod.name,
        amount: draft.amount,
        paymentTypeId: paymentType.id,
        paymentTypeName: paymentType.name,
        paymentDetailId: paymentDetail.id,
        paymentDetailName: paymentDetail.name,
        note: draft.note,
        recordSource: .engine,
        recordKind: .carryForward,
        carryForwardRole: .accountingSkeleton,
        engineFamily: draft.engineFamily,
        engineKey: draft.engineKey,
        objectKey: draft.objectKey,
        sourceRecordIds: draft.sourceRecordIds,
        sourceInvestmentTransactionIds: draft.sourceInvestmentTransactionIds,
        sourceImportBatchId: nil,
        sourceImportCandidateId: nil,
        createdAt: createdAt,
        updatedAt: updatedAt
    )
}

private func engineRecordNeedsUpdate(
    _ record: JournalRecord,
    draft: EngineRecordDraft,
    accountingMethod: PaymentMethod,
    paymentType: PaymentType,
    paymentDetail: PaymentDetail
) -> Bool {
    record.accountMonth != draft.accountMonth ||
        record.occurredAt != draft.occurredAt ||
        record.paymentMethodId != accountingMethod.id ||
        record.paymentMethodName != accountingMethod.name ||
        record.amount != draft.amount ||
        record.paymentTypeId != paymentType.id ||
        record.paymentTypeName != paymentType.name ||
        record.paymentDetailId != paymentDetail.id ||
        record.paymentDetailName != paymentDetail.name ||
        record.note != draft.note ||
        record.recordSource != .engine ||
        record.recordKind != .carryForward ||
        record.carryForwardRole != .accountingSkeleton ||
        record.engineFamily != draft.engineFamily ||
        record.engineKey != draft.engineKey ||
        record.objectKey != draft.objectKey ||
        record.sourceRecordIds != draft.sourceRecordIds ||
        record.sourceInvestmentTransactionIds != draft.sourceInvestmentTransactionIds
}

private func normalizedConfigName(_ value: String, fieldName: String) throws -> String {
    let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else {
        throw MingZhangError.validation("\(fieldName)不能为空")
    }
    return name
}

private func normalizedOptionalText(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func uniqueUUIDs(_ values: [UUID]) -> [UUID] {
    var seen: Set<UUID> = []
    var result: [UUID] = []
    for value in values where !seen.contains(value) {
        seen.insert(value)
        result.append(value)
    }
    return result
}

private func liabilityObjectKey(for methodName: String) -> String {
    "liability:\(methodName)"
}

private func liabilityName(from objectKey: String) throws -> String {
    let prefix = "liability:"
    guard objectKey.hasPrefix(prefix), objectKey.count > prefix.count else {
        throw MingZhangError.validation("负债对象必须使用 liability:<名称> 格式")
    }
    return String(objectKey.dropFirst(prefix.count))
}

private func liabilityPaymentMethod(_ db: Database, objectKey: String) throws -> PaymentMethod {
    let method = try requirePaymentMethod(db, name: try liabilityName(from: objectKey))
    guard method.methodType == .liability else {
        throw MingZhangError.validation("负债对象必须指向负债类收付手段")
    }
    return method
}

private func isLiabilityRepayment(paymentType: PaymentType, paymentDetail: PaymentDetail) -> Bool {
    paymentType.name == "负债类减记" || paymentDetail.semanticTags.contains("账单还款")
}

private func isLiabilityIncrease(paymentType: PaymentType) -> Bool {
    paymentType.name == "负债类增记"
}

private func isLiabilityCost(paymentDetail: PaymentDetail) -> Bool {
    paymentDetail.semanticTags.contains("金融费用")
}

private func normalizedTags(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
        seen.insert(trimmed)
        result.append(trimmed)
    }
    return result
}

private func ensureUniquePaymentMethodName(_ db: Database, name: String, excluding id: UUID? = nil) throws {
    var sql = "SELECT id FROM payment_methods WHERE name = ?"
    var arguments: StatementArguments = [name]
    if let id {
        sql += " AND id != ?"
        arguments += [id.uuidString]
    }
    if try Row.fetchOne(db, sql: sql, arguments: arguments) != nil {
        throw MingZhangError.validation("收付手段名称已存在：\(name)")
    }
}

private func ensureUniquePaymentTypeName(_ db: Database, name: String, excluding id: UUID? = nil) throws {
    var sql = "SELECT id FROM payment_types WHERE name = ?"
    var arguments: StatementArguments = [name]
    if let id {
        sql += " AND id != ?"
        arguments += [id.uuidString]
    }
    if try Row.fetchOne(db, sql: sql, arguments: arguments) != nil {
        throw MingZhangError.validation("收付类型名称已存在：\(name)")
    }
}

private func ensureUniquePaymentDetailName(
    _ db: Database,
    name: String,
    paymentTypeId: UUID,
    excluding id: UUID? = nil
) throws {
    var sql = "SELECT id FROM payment_details WHERE name = ? AND payment_type_id = ?"
    var arguments: StatementArguments = [name, paymentTypeId.uuidString]
    if let id {
        sql += " AND id != ?"
        arguments += [id.uuidString]
    }
    if try Row.fetchOne(db, sql: sql, arguments: arguments) != nil {
        throw MingZhangError.validation("类型明细名称已存在：\(name)")
    }
}

private func hasJournalRecordReference(_ db: Database, column: String, id: UUID) throws -> Bool {
    let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM journal_records WHERE \(column) = ? AND record_source != ?",
        arguments: [id.uuidString, RecordSource.engine.rawValue]
    ) ?? 0
    return count > 0
}

private func referencedAccountMonths(_ db: Database, column: String, id: UUID) throws -> [String] {
    try String.fetchAll(
        db,
        sql: """
            SELECT DISTINCT account_month
            FROM journal_records
            WHERE \(column) = ? AND record_source != ?
            ORDER BY account_month ASC
            """,
        arguments: [id.uuidString, RecordSource.engine.rawValue]
    )
}

private func requireActive(_ method: PaymentMethod) throws {
    guard method.isActive else {
        throw MingZhangError.validation("收付手段已停用：\(method.name)")
    }
}

private func requireActive(_ type: PaymentType, label: String = "收付类型") throws {
    guard type.isActive else {
        throw MingZhangError.validation("\(label)已停用：\(type.name)")
    }
}

private func requireActive(_ detail: PaymentDetail) throws {
    guard detail.isActive else {
        throw MingZhangError.validation("类型明细已停用：\(detail.name)")
    }
}

private func persistPaymentMethodUpdate(_ db: Database, method: PaymentMethod) throws {
    try db.execute(sql: """
        UPDATE payment_methods
        SET name = ?, method_type = ?, is_active = ?, semantic_tags = ?, config_version = ?, updated_at = ?
        WHERE id = ?
        """, arguments: [
        method.name,
        method.methodType.rawValue,
        method.isActive,
        encodeStringList(method.semanticTags),
        method.configVersion,
        encodeDate(Date()),
        method.id.uuidString
    ])
}

private func persistPaymentTypeUpdate(_ db: Database, type: PaymentType) throws {
    try db.execute(sql: """
        UPDATE payment_types
        SET name = ?, element = ?, is_active = ?, semantic_tags = ?, config_description = ?, config_version = ?, updated_at = ?
        WHERE id = ?
        """, arguments: [
        type.name,
        type.element.rawValue,
        type.isActive,
        encodeStringList(type.semanticTags),
        type.configDescription,
        type.configVersion,
        encodeDate(Date()),
        type.id.uuidString
    ])
}

private func persistPaymentDetailUpdate(_ db: Database, detail: PaymentDetail) throws {
    try db.execute(sql: """
        UPDATE payment_details
        SET name = ?, payment_type_id = ?, is_active = ?, semantic_tags = ?, config_description = ?, config_version = ?, updated_at = ?
        WHERE id = ?
        """, arguments: [
        detail.name,
        detail.paymentTypeId.uuidString,
        detail.isActive,
        encodeStringList(detail.semanticTags),
        detail.configDescription,
        detail.configVersion,
        encodeDate(Date()),
        detail.id.uuidString
    ])
}

private func paymentTypeBySeedKey(_ db: Database, seedKey: String) throws -> PaymentType? {
    try Row.fetchOne(
        db,
        sql: """
            SELECT id, name, element, is_active, semantic_tags, config_description, config_version
            FROM payment_types
            WHERE seed_key = ?
            """,
        arguments: [seedKey]
    ).map(paymentType(from:))
}

private func requirePaymentTypeBySeedKey(_ db: Database, seedKey: String) throws -> PaymentType {
    guard let type = try paymentTypeBySeedKey(db, seedKey: seedKey) else {
        throw MingZhangError.missingSeed("收付类型：\(seedKey)")
    }
    return type
}

private func requirePaymentMethodBySeedKey(_ db: Database, seedKey: String) throws -> PaymentMethod {
    guard let row = try Row.fetchOne(
        db,
        sql: """
            SELECT id, name, method_type, is_active, semantic_tags, config_version
            FROM payment_methods
            WHERE seed_key = ?
            """,
        arguments: [seedKey]
    ) else {
        throw MingZhangError.missingSeed("收付手段：\(seedKey)")
    }
    return try paymentMethod(from: row)
}

private func requirePaymentDetailBySeedKey(_ db: Database, seedKey: String) throws -> PaymentDetail {
    guard let row = try Row.fetchOne(
        db,
        sql: """
            SELECT id, name, payment_type_id, is_active, semantic_tags, config_description, config_version
            FROM payment_details
            WHERE seed_key = ?
            """,
        arguments: [seedKey]
    ) else {
        throw MingZhangError.missingSeed("类型明细：\(seedKey)")
    }
    return try paymentDetail(from: row)
}

private func requirePaymentMethod(_ db: Database, name: String) throws -> PaymentMethod {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, method_type, is_active, semantic_tags, config_version FROM payment_methods WHERE name = ?",
        arguments: [name]
    ) else {
        throw MingZhangError.missingSeed("收付手段：\(name)")
    }
    return try paymentMethod(from: row)
}

private func requirePaymentMethod(_ db: Database, id: UUID) throws -> PaymentMethod {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, method_type, is_active, semantic_tags, config_version FROM payment_methods WHERE id = ?",
        arguments: [id.uuidString]
    ) else {
        throw MingZhangError.missingSeed("收付手段：\(id.uuidString)")
    }
    return try paymentMethod(from: row)
}

private func requirePaymentType(_ db: Database, name: String) throws -> PaymentType {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, element, is_active, semantic_tags, config_description, config_version FROM payment_types WHERE name = ?",
        arguments: [name]
    ) else {
        throw MingZhangError.missingSeed("收付类型：\(name)")
    }
    return try paymentType(from: row)
}

private func requirePaymentType(_ db: Database, id: UUID) throws -> PaymentType {
    guard let row = try Row.fetchOne(
        db,
        sql: "SELECT id, name, element, is_active, semantic_tags, config_description, config_version FROM payment_types WHERE id = ?",
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
            SELECT id, name, payment_type_id, is_active, semantic_tags, config_description, config_version
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
        sql: "SELECT id, name, payment_type_id, is_active, semantic_tags, config_description, config_version FROM payment_details WHERE id = ?",
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

private func requireInvestmentTransaction(_ db: Database, id: UUID) throws -> InvestmentTransaction {
    guard let row = try Row.fetchOne(
        db,
        sql: """
            SELECT id, account_month, occurred_at, fund_name, transaction_type,
                   trade_amount, trade_share, nav, note, book_amount, realized_gain,
                   realized_loss, holding_share, average_cost, book_value, present_value,
                   created_at, updated_at
            FROM investment_transactions
            WHERE id = ?
            """,
        arguments: [id.uuidString]
    ) else {
        throw MingZhangError.investmentTransactionNotFound(id)
    }
    return try investmentTransaction(from: row)
}

private func requireImportBatch(_ db: Database, id: UUID) throws -> ImportBatch {
    guard let row = try Row.fetchOne(
        db,
        sql: """
            SELECT id, source, file_name, imported_at, status, confirmed_record_count
            FROM import_batches
            WHERE id = ?
            """,
        arguments: [id.uuidString]
    ) else {
        throw MingZhangError.validation("找不到导入批次")
    }
    return try importBatch(from: row)
}

private func requireImportCandidate(_ db: Database, id: UUID) throws -> ImportCandidateRecord {
    guard let row = try Row.fetchOne(
        db,
        sql: """
            SELECT id, batch_id, status, account_month, occurred_at, payment_method_id,
                   payment_method_name, amount, payment_type_id, payment_type_name,
                   payment_detail_id, payment_detail_name, object_key, note, raw_line_number,
                   raw_payload, raw_transaction_id, raw_fingerprint, created_journal_record_id
            FROM import_candidates
            WHERE id = ?
            """,
        arguments: [id.uuidString]
    ) else {
        throw MingZhangError.validation("找不到导入候选记录")
    }
    return try importCandidate(from: row)
}

private func applyImportCandidateChanges(
    _ db: Database,
    candidate: inout ImportCandidateRecord,
    changes: ImportCandidateChanges
) throws {
    guard candidate.status == .pending else {
        throw MingZhangError.validation("只能整理待确认候选记录")
    }
    if let accountMonth = changes.accountMonth {
        try validateAccountMonth(accountMonth)
        candidate.accountMonth = accountMonth
    }
    if let amount = changes.amount {
        candidate.amount = amount
    }
    if let paymentMethodName = changes.paymentMethodName {
        let method = try requirePaymentMethod(db, name: paymentMethodName)
        guard method.methodType != .pendingRealAccount else {
            throw MingZhangError.validation("待补真实账户是导入内部占位，不能在导入整理中手动选择")
        }
        try requireActive(method)
        candidate.paymentMethodId = method.id
        candidate.paymentMethodName = method.name
    }
    if let paymentTypeName = changes.paymentTypeName {
        let type = try requirePaymentType(db, name: paymentTypeName)
        try requireActive(type)
        candidate.paymentTypeId = type.id
        candidate.paymentTypeName = type.name
        if changes.paymentDetailName == nil, let detailName = candidate.paymentDetailName {
            let detail = try requirePaymentDetail(db, name: detailName, paymentTypeId: type.id)
            try requireActive(detail)
            candidate.paymentDetailId = detail.id
            candidate.paymentDetailName = detail.name
        }
    }
    if let paymentDetailName = changes.paymentDetailName {
        guard let typeId = candidate.paymentTypeId else {
            throw MingZhangError.validation("请先选择收付类型")
        }
        let detail = try requirePaymentDetail(db, name: paymentDetailName, paymentTypeId: typeId)
        try requireActive(detail)
        candidate.paymentDetailId = detail.id
        candidate.paymentDetailName = detail.name
    }
    if let objectKey = changes.objectKey {
        candidate.objectKey = normalizedOptionalText(objectKey)
    }
    if let note = changes.note {
        candidate.note = note
    }
}

private func importCandidateExists(
    _ db: Database,
    source: ImportSource,
    transactionId: String?,
    fingerprint: String
) throws -> Bool {
    if let transactionId, !transactionId.isEmpty {
        let count = try Int.fetchOne(db, sql: """
            SELECT COUNT(*)
            FROM import_candidates
            JOIN import_batches ON import_batches.id = import_candidates.batch_id
            LEFT JOIN journal_records ON journal_records.id = import_candidates.created_journal_record_id
            WHERE import_batches.source = ? AND import_candidates.raw_transaction_id = ?
              AND (
                import_candidates.status = ?
                OR (import_candidates.status = ? AND journal_records.id IS NOT NULL)
              )
            """, arguments: [
                source.rawValue,
                transactionId,
                ImportCandidateStatus.pending.rawValue,
                ImportCandidateStatus.confirmed.rawValue
            ]) ?? 0
        return count > 0
    }

    let count = try Int.fetchOne(db, sql: """
        SELECT COUNT(*)
        FROM import_candidates
        JOIN import_batches ON import_batches.id = import_candidates.batch_id
        LEFT JOIN journal_records ON journal_records.id = import_candidates.created_journal_record_id
        WHERE import_batches.source = ?
          AND import_candidates.raw_transaction_id IS NULL
          AND import_candidates.raw_fingerprint = ?
          AND (
            import_candidates.status = ?
            OR (import_candidates.status = ? AND journal_records.id IS NOT NULL)
          )
        """, arguments: [
            source.rawValue,
            fingerprint,
            ImportCandidateStatus.pending.rawValue,
            ImportCandidateStatus.confirmed.rawValue
        ]) ?? 0
    return count > 0
}

private func resolveImportPaymentMethod(
    _ db: Database,
    source: ImportSource,
    rawName: String?
) throws -> (id: UUID?, name: String?) {
    let cleaned = cleanImportField(rawName ?? "")
    let pending = try requirePaymentMethodBySeedKey(db, seedKey: "pending_real_account")
    guard !cleaned.isEmpty, cleaned != "/" else {
        return (pending.id, pending.name)
    }
    if let exact = try Row.fetchOne(
        db,
        sql: "SELECT id, name, method_type, is_active, semantic_tags, config_version FROM payment_methods WHERE name = ? AND is_active = ? AND method_type != ?",
        arguments: [cleaned, true, PaymentMethodType.pendingRealAccount.rawValue]
    ).map(paymentMethod(from:)) {
        return (exact.id, exact.name)
    }
    if let exactInactiveOrInternal = try Row.fetchOne(
        db,
        sql: "SELECT id, name, method_type, is_active, semantic_tags, config_version FROM payment_methods WHERE name = ?",
        arguments: [cleaned]
    ).map(paymentMethod(from:)) {
        return exactInactiveOrInternal.methodType == .pendingRealAccount ? (pending.id, pending.name) : (nil, cleaned)
    }
    switch source {
    case .alipay:
        return (nil, cleaned)
    case .wechat:
        return (pending.id, pending.name)
    }
}

private func incrementBatchConfirmedCount(_ db: Database, batchId: UUID) throws {
    try db.execute(sql: """
        UPDATE import_batches
        SET confirmed_record_count = confirmed_record_count + 1
        WHERE id = ?
        """, arguments: [batchId.uuidString])
}

private func markBatchConfirmedIfComplete(_ db: Database, batchId: UUID) throws {
    let pendingCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*)
        FROM import_candidates
        WHERE batch_id = ? AND status = ?
        """, arguments: [batchId.uuidString, ImportCandidateStatus.pending.rawValue]) ?? 0
    guard pendingCount == 0 else { return }
    try db.execute(sql: """
        UPDATE import_batches
        SET status = ?
        WHERE id = ?
        """, arguments: [ImportBatchStatus.confirmed.rawValue, batchId.uuidString])
}

private func validateRecordFields(
    _ db: Database,
    accountMonth: String,
    amount: Decimal,
    paymentMethod: PaymentMethod,
    paymentType: PaymentType,
    paymentDetail: PaymentDetail,
    objectKey: String?
) throws {
    try validateAccountMonth(accountMonth)
    guard paymentDetail.paymentTypeId == paymentType.id else {
        throw MingZhangError.validation("类型明细必须归属于当前收付类型")
    }

    if let objectKey = normalizedOptionalText(objectKey) {
        _ = try liabilityPaymentMethod(db, objectKey: objectKey)
    }

    guard isLiabilityRepayment(paymentType: paymentType, paymentDetail: paymentDetail) else {
        return
    }

    guard amount > 0 else {
        throw MingZhangError.validation("还款金额必须大于 0")
    }
    guard paymentMethod.methodType == .asset else {
        throw MingZhangError.validation("还款记录必须使用现金类资产作为收付手段")
    }
    guard let objectKey = normalizedOptionalText(objectKey) else {
        throw MingZhangError.validation("还款记录必须选择负债对象")
    }
    _ = try liabilityPaymentMethod(db, objectKey: objectKey)
}

private func validateInvestmentInput(_ db: Database, input: CreateInvestmentTransactionInput) throws {
    try validateAccountMonth(input.accountMonth)
    let fundName = input.fundName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !fundName.isEmpty else {
        throw MingZhangError.validation("基金标的名称不能为空")
    }

    switch input.transactionType {
    case .buy:
        guard let amount = input.tradeAmount, amount > 0 else {
            throw MingZhangError.validation("买入交易金额必须大于 0")
        }
        guard let share = input.tradeShare, share > 0 else {
            throw MingZhangError.validation("买入交易份额必须大于 0")
        }
    case .sell:
        guard let amount = input.tradeAmount, amount < 0 else {
            throw MingZhangError.validation("卖出交易金额必须小于 0")
        }
        guard let share = input.tradeShare, share < 0 else {
            throw MingZhangError.validation("卖出交易份额必须小于 0")
        }
    case .nav:
        guard let nav = input.nav, nav > 0 else {
            throw MingZhangError.validation("净值记录必须填写大于 0 的单位净值")
        }
    }

    if let nav = input.nav, nav <= 0 {
        throw MingZhangError.validation("单位净值必须大于 0")
    }
}

private func validateAccountMonth(_ accountMonth: String) throws {
    let parts = accountMonth.split(separator: "-", omittingEmptySubsequences: false)
    guard
        accountMonth.count == 7,
        parts.count == 2,
        parts[0].count == 4,
        parts[1].count == 2,
        let year = Int(parts[0]),
        let month = Int(parts[1]),
        year > 0,
        (1...12).contains(month)
    else {
        throw MingZhangError.validation("账月必须是合法的 YYYY-MM")
    }
}

private func paymentMethod(from row: Row) throws -> PaymentMethod {
    PaymentMethod(
        id: try requireUUID(row["id"]),
        name: row["name"],
        methodType: PaymentMethodType(rawValue: row["method_type"]) ?? .pendingRealAccount,
        isActive: row["is_active"],
        semanticTags: decodeStringList(row["semantic_tags"]),
        configVersion: row["config_version"]
    )
}

private func paymentType(from row: Row) throws -> PaymentType {
    PaymentType(
        id: try requireUUID(row["id"]),
        name: row["name"],
        element: AccountingElement(rawValue: row["element"]) ?? .expense,
        isActive: row["is_active"],
        semanticTags: decodeStringList(row["semantic_tags"]),
        configDescription: row["config_description"],
        configVersion: row["config_version"]
    )
}

private func paymentDetail(from row: Row) throws -> PaymentDetail {
    PaymentDetail(
        id: try requireUUID(row["id"]),
        name: row["name"],
        paymentTypeId: try requireUUID(row["payment_type_id"]),
        isActive: row["is_active"],
        semanticTags: decodeStringList(row["semantic_tags"]),
        configDescription: row["config_description"],
        configVersion: row["config_version"]
    )
}

private func backupPaymentMethod(from row: Row) throws -> BackupPaymentMethodRow {
    BackupPaymentMethodRow(
        id: row["id"],
        name: row["name"],
        methodType: row["method_type"],
        isActive: row["is_active"],
        semanticTags: row["semantic_tags"],
        configVersion: row["config_version"],
        seedKey: row["seed_key"],
        createdAt: row["created_at"],
        updatedAt: row["updated_at"]
    )
}

private func backupPaymentType(from row: Row) throws -> BackupPaymentTypeRow {
    BackupPaymentTypeRow(
        id: row["id"],
        name: row["name"],
        element: row["element"],
        isActive: row["is_active"],
        semanticTags: row["semantic_tags"],
        configDescription: row["config_description"],
        configVersion: row["config_version"],
        seedKey: row["seed_key"],
        createdAt: row["created_at"],
        updatedAt: row["updated_at"]
    )
}

private func backupPaymentDetail(from row: Row) throws -> BackupPaymentDetailRow {
    BackupPaymentDetailRow(
        id: row["id"],
        name: row["name"],
        paymentTypeId: row["payment_type_id"],
        isActive: row["is_active"],
        semanticTags: row["semantic_tags"],
        configDescription: row["config_description"],
        configVersion: row["config_version"],
        seedKey: row["seed_key"],
        createdAt: row["created_at"],
        updatedAt: row["updated_at"]
    )
}

private func importBatch(from row: Row) throws -> ImportBatch {
    let sourceValue: String = row["source"]
    let statusValue: String = row["status"]
    return ImportBatch(
        id: try requireUUID(row["id"]),
        source: ImportSource(rawValue: sourceValue) ?? .alipay,
        fileName: row["file_name"],
        importedAt: try decodeDate(row["imported_at"]),
        status: ImportBatchStatus(rawValue: statusValue) ?? .draft,
        confirmedRecordCount: row["confirmed_record_count"]
    )
}

private func backupImportBatch(from row: Row) throws -> BackupImportBatchRow {
    BackupImportBatchRow(
        id: row["id"],
        source: row["source"],
        fileName: row["file_name"],
        importedAt: row["imported_at"],
        status: row["status"],
        confirmedRecordCount: row["confirmed_record_count"]
    )
}

private func importCandidate(from row: Row) throws -> ImportCandidateRecord {
    let statusValue: String = row["status"]
    return ImportCandidateRecord(
        id: try requireUUID(row["id"]),
        batchId: try requireUUID(row["batch_id"]),
        status: ImportCandidateStatus(rawValue: statusValue) ?? .pending,
        accountMonth: row["account_month"],
        occurredAt: try decodeDate(row["occurred_at"]),
        paymentMethodId: optionalUUID(row["payment_method_id"]),
        paymentMethodName: row["payment_method_name"],
        amount: decodeDecimal(row["amount"]),
        paymentTypeId: optionalUUID(row["payment_type_id"]),
        paymentTypeName: row["payment_type_name"],
        paymentDetailId: optionalUUID(row["payment_detail_id"]),
        paymentDetailName: row["payment_detail_name"],
        objectKey: row["object_key"],
        note: row["note"],
        rawLineNumber: row["raw_line_number"],
        rawPayload: row["raw_payload"],
        rawTransactionId: row["raw_transaction_id"],
        rawFingerprint: row["raw_fingerprint"],
        createdJournalRecordId: optionalUUID(row["created_journal_record_id"])
    )
}

private func backupImportCandidate(from row: Row) throws -> BackupImportCandidateRow {
    BackupImportCandidateRow(
        id: row["id"],
        batchId: row["batch_id"],
        status: row["status"],
        accountMonth: row["account_month"],
        occurredAt: row["occurred_at"],
        paymentMethodId: row["payment_method_id"],
        paymentMethodName: row["payment_method_name"],
        amount: row["amount"],
        paymentTypeId: row["payment_type_id"],
        paymentTypeName: row["payment_type_name"],
        paymentDetailId: row["payment_detail_id"],
        paymentDetailName: row["payment_detail_name"],
        objectKey: row["object_key"],
        note: row["note"],
        rawLineNumber: row["raw_line_number"],
        rawPayload: row["raw_payload"],
        rawTransactionId: row["raw_transaction_id"],
        rawFingerprint: row["raw_fingerprint"],
        createdJournalRecordId: row["created_journal_record_id"],
        createdAt: row["created_at"],
        updatedAt: row["updated_at"]
    )
}

private func investmentTransaction(from row: Row) throws -> InvestmentTransaction {
    let typeValue: String = row["transaction_type"]
    return InvestmentTransaction(
        id: try requireUUID(row["id"]),
        accountMonth: row["account_month"],
        occurredAt: try decodeDate(row["occurred_at"]),
        fundName: row["fund_name"],
        transactionType: InvestmentTransactionType(rawValue: typeValue) ?? .buy,
        tradeAmount: decodeOptionalDecimal(row["trade_amount"]),
        tradeShare: decodeOptionalDecimal(row["trade_share"]),
        nav: decodeOptionalDecimal(row["nav"]),
        note: row["note"],
        bookAmount: decodeOptionalDecimal(row["book_amount"]),
        realizedGain: decodeDecimal(row["realized_gain"]),
        realizedLoss: decodeDecimal(row["realized_loss"]),
        holdingShare: decodeDecimal(row["holding_share"]),
        averageCost: decodeOptionalDecimal(row["average_cost"]),
        bookValue: decodeDecimal(row["book_value"]),
        presentValue: decodeOptionalDecimal(row["present_value"]),
        createdAt: try decodeDate(row["created_at"]),
        updatedAt: try decodeDate(row["updated_at"])
    )
}

private func backupInvestmentTransaction(from row: Row) throws -> BackupInvestmentTransactionRow {
    BackupInvestmentTransactionRow(
        id: row["id"],
        accountMonth: row["account_month"],
        occurredAt: row["occurred_at"],
        fundName: row["fund_name"],
        transactionType: row["transaction_type"],
        tradeAmount: row["trade_amount"],
        tradeShare: row["trade_share"],
        nav: row["nav"],
        note: row["note"],
        bookAmount: row["book_amount"],
        realizedGain: row["realized_gain"],
        realizedLoss: row["realized_loss"],
        holdingShare: row["holding_share"],
        averageCost: row["average_cost"],
        bookValue: row["book_value"],
        presentValue: row["present_value"],
        createdAt: row["created_at"],
        updatedAt: row["updated_at"]
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
        sourceInvestmentTransactionIds: decodeUUIDList(row["source_investment_transaction_ids"]),
        sourceImportBatchId: optionalUUID(row["source_import_batch_id"]),
        sourceImportCandidateId: optionalUUID(row["source_import_candidate_id"]),
        createdAt: try decodeDate(row["created_at"]),
        updatedAt: try decodeDate(row["updated_at"])
    )
}

private func backupJournalRecord(from row: Row) throws -> BackupJournalRecordRow {
    BackupJournalRecordRow(
        id: row["id"],
        accountMonth: row["account_month"],
        occurredAt: row["occurred_at"],
        paymentMethodId: row["payment_method_id"],
        amount: row["amount"],
        paymentTypeId: row["payment_type_id"],
        paymentDetailId: row["payment_detail_id"],
        note: row["note"],
        recordSource: row["record_source"],
        recordKind: row["record_kind"],
        carryForwardRole: row["carry_forward_role"],
        engineFamily: row["engine_family"],
        engineKey: row["engine_key"],
        objectKey: row["object_key"],
        sourceRecordIds: row["source_record_ids"],
        sourceInvestmentTransactionIds: row["source_investment_transaction_ids"],
        sourceImportBatchId: row["source_import_batch_id"],
        sourceImportCandidateId: row["source_import_candidate_id"],
        createdAt: row["created_at"],
        updatedAt: row["updated_at"]
    )
}

private func requireUUID(_ value: String) throws -> UUID {
    guard let uuid = UUID(uuidString: value) else {
        throw MingZhangError.missingSeed("无效 UUID：\(value)")
    }
    return uuid
}

private func optionalUUID(_ value: String?) -> UUID? {
    value.flatMap(UUID.init(uuidString:))
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

private func decodeOptionalDecimal(_ value: String?) -> Decimal? {
    guard let value, !value.isEmpty else { return nil }
    return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
}

private func roundCurrency(_ value: Decimal) -> Decimal {
    roundDecimal(value, scale: 2)
}

private func roundShare(_ value: Decimal) -> Decimal {
    roundDecimal(value, scale: 6)
}

private func roundUnitCost(_ value: Decimal) -> Decimal {
    roundDecimal(value, scale: 6)
}

private func roundDecimal(_ value: Decimal, scale: Int) -> Decimal {
    var input = value
    var output = Decimal()
    NSDecimalRound(&output, &input, scale, .plain)
    return output
}

private func encodeUUIDList(_ values: [UUID]) -> String {
    values.map(\.uuidString).joined(separator: ",")
}

private func decodeUUIDList(_ value: String) -> [UUID] {
    value
        .split(separator: ",")
        .compactMap { UUID(uuidString: String($0)) }
}

private func encodeStringList(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values),
          let encoded = String(data: data, encoding: .utf8) else {
        return "[]"
    }
    return encoded
}

private func decodeStringList(_ value: String?) -> [String] {
    guard let value,
          let data = value.data(using: .utf8),
          let decoded = try? JSONDecoder().decode([String].self, from: data) else {
        return []
    }
    return decoded
}

private func backupJSONEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

private func backupJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func checksum(for payload: BackupPayload) throws -> String {
    let data = try backupJSONEncoder().encode(payload)
    return "sha256:\(sha256Hex(data))"
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func inspectBackupPackage(_ data: Data) throws -> (package: MingZhangBackupPackage?, result: BackupValidationResult) {
    let package: MingZhangBackupPackage
    do {
        package = try backupJSONDecoder().decode(MingZhangBackupPackage.self, from: data)
    } catch {
        let result = BackupValidationResult(
            isValid: false,
            manifest: nil,
            preview: nil,
            errors: ["备份文件无法解析：\(error.localizedDescription)"]
        )
        return (nil, result)
    }

    var errors: [String] = []
    if package.format != backupPackageFormat {
        errors.append("备份文件格式不匹配")
    }
    if package.manifest.backupSchemaVersion != currentBackupSchemaVersion {
        errors.append("不支持的 backup schema version：\(package.manifest.backupSchemaVersion)")
    }
    if package.manifest.appDataSchemaVersion != currentAppDataSchemaVersion {
        errors.append("不支持的数据 schema version：\(package.manifest.appDataSchemaVersion)")
    }
    let actualChecksum = try checksum(for: package.payload)
    if actualChecksum != package.manifest.payloadChecksum {
        errors.append("payload checksum 校验失败")
    }
    errors.append(contentsOf: validateBackupPayload(package.payload, manifest: package.manifest))

    var accountMonths = package.payload.accountMonths
    if errors.isEmpty {
        do {
            let dryRunDatabase = try LedgerDatabase.inMemory()
            try dryRunDatabase.writer.write { db in
                try replaceBackupPayload(package.payload, in: db)
            }
            let dryRunUseCases = LedgerUseCases(database: dryRunDatabase)
            accountMonths = try dryRunUseCases.queryAccountMonths()
            for month in accountMonths {
                _ = try dryRunUseCases.queryHomeSummary(accountMonth: month)
                _ = try dryRunUseCases.queryBalanceSummary(accountMonth: month)
                _ = try dryRunUseCases.queryStatisticsSummary(accountMonth: month)
                _ = try dryRunUseCases.queryInvestmentMonthlySummary(accountMonth: month, fundName: nil)
            }
        } catch {
            errors.append("备份 dry-run 校验失败：\(error.localizedDescription)")
        }
    }

    let preview = errors.isEmpty
        ? BackupRestorePreview(
            recordCounts: package.manifest.recordCounts,
            exportedAt: package.manifest.exportedAt,
            accountMonths: accountMonths
        )
        : nil

    return (
        errors.isEmpty ? package : nil,
        BackupValidationResult(
            isValid: errors.isEmpty,
            manifest: package.manifest,
            preview: preview,
            errors: errors
        )
    )
}

private func validateBackupPayload(_ payload: BackupPayload, manifest: BackupManifest) -> [String] {
    var errors: [String] = []
    if payload.recordCounts != manifest.recordCounts {
        errors.append("备份记录数量与 manifest 不一致")
    }

    let paymentMethodIds = validateUniqueUUIDs(payload.paymentMethods.map(\.id), label: "payment_methods", errors: &errors)
    let paymentTypeIds = validateUniqueUUIDs(payload.paymentTypes.map(\.id), label: "payment_types", errors: &errors)
    let paymentDetailIds = validateUniqueUUIDs(payload.paymentDetails.map(\.id), label: "payment_details", errors: &errors)
    let importBatchIds = validateUniqueUUIDs(payload.importBatches.map(\.id), label: "import_batches", errors: &errors)
    let investmentIds = validateUniqueUUIDs(payload.investmentTransactions.map(\.id), label: "investment_transactions", errors: &errors)
    let journalIds = validateUniqueUUIDs(payload.journalRecords.map(\.id), label: "journal_records", errors: &errors)
    let importCandidateIds = validateUniqueUUIDs(payload.importCandidates.map(\.id), label: "import_candidates", errors: &errors)

    for row in payload.paymentMethods {
        validateDate(row.createdAt, field: "payment_methods.created_at", errors: &errors)
        validateDate(row.updatedAt, field: "payment_methods.updated_at", errors: &errors)
        validateStringListJSON(row.semanticTags, field: "payment_methods.semantic_tags", errors: &errors)
        if PaymentMethodType(rawValue: row.methodType) == nil {
            errors.append("payment_methods.method_type 无效：\(row.methodType)")
        }
    }

    for row in payload.paymentTypes {
        validateDate(row.createdAt, field: "payment_types.created_at", errors: &errors)
        validateDate(row.updatedAt, field: "payment_types.updated_at", errors: &errors)
        validateStringListJSON(row.semanticTags, field: "payment_types.semantic_tags", errors: &errors)
        if AccountingElement(rawValue: row.element) == nil {
            errors.append("payment_types.element 无效：\(row.element)")
        }
    }

    for row in payload.paymentDetails {
        validateDate(row.createdAt, field: "payment_details.created_at", errors: &errors)
        validateDate(row.updatedAt, field: "payment_details.updated_at", errors: &errors)
        validateStringListJSON(row.semanticTags, field: "payment_details.semantic_tags", errors: &errors)
        requireReference(row.paymentTypeId, in: paymentTypeIds, field: "payment_details.payment_type_id", errors: &errors)
    }

    for row in payload.importBatches {
        validateDate(row.importedAt, field: "import_batches.imported_at", errors: &errors)
        if ImportSource(rawValue: row.source) == nil {
            errors.append("import_batches.source 无效：\(row.source)")
        }
        if ImportBatchStatus(rawValue: row.status) == nil {
            errors.append("import_batches.status 无效：\(row.status)")
        }
    }

    for row in payload.investmentTransactions {
        validateDate(row.occurredAt, field: "investment_transactions.occurred_at", errors: &errors)
        validateDate(row.createdAt, field: "investment_transactions.created_at", errors: &errors)
        validateDate(row.updatedAt, field: "investment_transactions.updated_at", errors: &errors)
        validateOptionalDecimal(row.tradeAmount, field: "investment_transactions.trade_amount", errors: &errors)
        validateOptionalDecimal(row.tradeShare, field: "investment_transactions.trade_share", errors: &errors)
        validateOptionalDecimal(row.nav, field: "investment_transactions.nav", errors: &errors)
        validateOptionalDecimal(row.bookAmount, field: "investment_transactions.book_amount", errors: &errors)
        validateDecimal(row.realizedGain, field: "investment_transactions.realized_gain", errors: &errors)
        validateDecimal(row.realizedLoss, field: "investment_transactions.realized_loss", errors: &errors)
        validateDecimal(row.holdingShare, field: "investment_transactions.holding_share", errors: &errors)
        validateOptionalDecimal(row.averageCost, field: "investment_transactions.average_cost", errors: &errors)
        validateDecimal(row.bookValue, field: "investment_transactions.book_value", errors: &errors)
        validateOptionalDecimal(row.presentValue, field: "investment_transactions.present_value", errors: &errors)
        if InvestmentTransactionType(rawValue: row.transactionType) == nil {
            errors.append("investment_transactions.transaction_type 无效：\(row.transactionType)")
        }
    }

    let engineKeys = payload.journalRecords.compactMap(\.engineKey).filter { !$0.isEmpty }
    let duplicateEngineKeys = duplicateValues(engineKeys)
    if !duplicateEngineKeys.isEmpty {
        errors.append("journal_records.engine_key 重复：\(duplicateEngineKeys.sorted().joined(separator: ","))")
    }

    for row in payload.journalRecords {
        validateDate(row.occurredAt, field: "journal_records.occurred_at", errors: &errors)
        validateDate(row.createdAt, field: "journal_records.created_at", errors: &errors)
        validateDate(row.updatedAt, field: "journal_records.updated_at", errors: &errors)
        validateDecimal(row.amount, field: "journal_records.amount", errors: &errors)
        requireReference(row.paymentMethodId, in: paymentMethodIds, field: "journal_records.payment_method_id", errors: &errors)
        requireReference(row.paymentTypeId, in: paymentTypeIds, field: "journal_records.payment_type_id", errors: &errors)
        requireReference(row.paymentDetailId, in: paymentDetailIds, field: "journal_records.payment_detail_id", errors: &errors)
        if RecordSource(rawValue: row.recordSource) == nil {
            errors.append("journal_records.record_source 无效：\(row.recordSource)")
        }
        if RecordKind(rawValue: row.recordKind) == nil {
            errors.append("journal_records.record_kind 无效：\(row.recordKind)")
        }
        if CarryForwardRole(rawValue: row.carryForwardRole) == nil {
            errors.append("journal_records.carry_forward_role 无效：\(row.carryForwardRole)")
        }
        if let engineFamily = row.engineFamily, EngineFamily(rawValue: engineFamily) == nil {
            errors.append("journal_records.engine_family 无效：\(engineFamily)")
        }
        validateUUIDList(row.sourceRecordIds, field: "journal_records.source_record_ids", requiredSet: journalIds, errors: &errors)
        validateUUIDList(row.sourceInvestmentTransactionIds, field: "journal_records.source_investment_transaction_ids", requiredSet: investmentIds, errors: &errors)
        if let batchId = row.sourceImportBatchId {
            requireReference(batchId, in: importBatchIds, field: "journal_records.source_import_batch_id", errors: &errors)
        }
        if let candidateId = row.sourceImportCandidateId {
            requireReference(candidateId, in: importCandidateIds, field: "journal_records.source_import_candidate_id", errors: &errors)
        }
    }

    for row in payload.importCandidates {
        validateDate(row.occurredAt, field: "import_candidates.occurred_at", errors: &errors)
        validateDate(row.createdAt, field: "import_candidates.created_at", errors: &errors)
        validateDate(row.updatedAt, field: "import_candidates.updated_at", errors: &errors)
        validateDecimal(row.amount, field: "import_candidates.amount", errors: &errors)
        requireReference(row.batchId, in: importBatchIds, field: "import_candidates.batch_id", errors: &errors)
        if let methodId = row.paymentMethodId {
            requireReference(methodId, in: paymentMethodIds, field: "import_candidates.payment_method_id", errors: &errors)
        }
        if let typeId = row.paymentTypeId {
            requireReference(typeId, in: paymentTypeIds, field: "import_candidates.payment_type_id", errors: &errors)
        }
        if let detailId = row.paymentDetailId {
            requireReference(detailId, in: paymentDetailIds, field: "import_candidates.payment_detail_id", errors: &errors)
        }
        if let recordId = row.createdJournalRecordId {
            requireReference(recordId, in: journalIds, field: "import_candidates.created_journal_record_id", errors: &errors)
        }
        if ImportCandidateStatus(rawValue: row.status) == nil {
            errors.append("import_candidates.status 无效：\(row.status)")
        }
    }

    return errors
}

private func validateUniqueUUIDs(_ ids: [String], label: String, errors: inout [String]) -> Set<String> {
    var seen: Set<String> = []
    for id in ids {
        guard UUID(uuidString: id) != nil else {
            errors.append("\(label) 包含无效 UUID：\(id)")
            continue
        }
        guard !seen.contains(id) else {
            errors.append("\(label) 包含重复 UUID：\(id)")
            continue
        }
        seen.insert(id)
    }
    return seen
}

private func duplicateValues(_ values: [String]) -> Set<String> {
    var seen: Set<String> = []
    var duplicates: Set<String> = []
    for value in values {
        if seen.contains(value) {
            duplicates.insert(value)
        } else {
            seen.insert(value)
        }
    }
    return duplicates
}

private func requireReference(_ value: String, in ids: Set<String>, field: String, errors: inout [String]) {
    guard UUID(uuidString: value) != nil else {
        errors.append("\(field) 包含无效 UUID：\(value)")
        return
    }
    guard ids.contains(value) else {
        errors.append("\(field) 引用了不存在的记录：\(value)")
        return
    }
}

private func validateUUIDList(_ value: String, field: String, requiredSet: Set<String>, errors: inout [String]) {
    for raw in value.split(separator: ",").map(String.init) {
        requireReference(raw, in: requiredSet, field: field, errors: &errors)
    }
}

private func validateDate(_ value: String, field: String, errors: inout [String]) {
    if makeISO8601Formatter().date(from: value) == nil {
        errors.append("\(field) 日期格式无效：\(value)")
    }
}

private func validateDecimal(_ value: String, field: String, errors: inout [String]) {
    if Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) == nil {
        errors.append("\(field) 数字格式无效：\(value)")
    }
}

private func validateOptionalDecimal(_ value: String?, field: String, errors: inout [String]) {
    guard let value, !value.isEmpty else { return }
    validateDecimal(value, field: field, errors: &errors)
}

private func validateStringListJSON(_ value: String, field: String, errors: inout [String]) {
    guard let data = value.data(using: .utf8),
          (try? JSONDecoder().decode([String].self, from: data)) != nil else {
        errors.append("\(field) 不是有效字符串数组 JSON")
        return
    }
}

private func csvEscape(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
        return value
    }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}

private func fileTimestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
}

private func dateRoundedToWholeSeconds(_ date: Date) -> Date {
    Date(timeIntervalSince1970: floor(date.timeIntervalSince1970))
}

private func parseImportRows(source: ImportSource, contents: String) throws -> ImportParseResult {
    let normalized = contents
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
    let lines = normalized.components(separatedBy: "\n")
    guard let headerIndex = lines.firstIndex(where: { isImportHeaderLine($0, source: source) }) else {
        throw MingZhangError.validation(source == .alipay ? "无法识别支付宝账单字段" : "无法识别微信账单字段")
    }

    var rows: [ParsedImportRow] = []
    var issues: [ImportIssue] = []
    for index in lines.indices where index > headerIndex {
        let line = lines[index]
        let lineNumber = index + 1
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        guard !line.hasPrefix("---") else { continue }

        switch source {
        case .alipay:
            parseAlipayLine(line, lineNumber: lineNumber, rows: &rows, issues: &issues)
        case .wechat:
            parseWechatLine(line, lineNumber: lineNumber, rows: &rows, issues: &issues)
        }
    }
    return ImportParseResult(rows: rows, issues: issues)
}

private func parseXLSXImportRows(source: ImportSource, data: Data) throws -> ImportParseResult {
    let file = try XLSXFile(data: data)
    guard
        let workbook = try file.parseWorkbooks().first,
        let worksheetPath = try file.parseWorksheetPathsAndNames(workbook: workbook).first?.path
    else {
        throw MingZhangError.validation("无法识别 XLSX 工作表")
    }

    let worksheet = try file.parseWorksheet(at: worksheetPath)
    let sharedStrings = try file.parseSharedStrings()
    let rows = worksheet.data?.rows ?? []
    let maxRow = rows.map(\.reference).max() ?? 0
    guard maxRow > 0 else {
        throw MingZhangError.validation(source == .alipay ? "无法识别支付宝账单字段" : "无法识别微信账单字段")
    }

    var lines = Array(repeating: "", count: Int(maxRow))
    for row in rows {
        lines[Int(row.reference) - 1] = xlsxRowCSVLine(row.cells, sharedStrings: sharedStrings)
    }
    return try parseImportRows(source: source, contents: lines.joined(separator: "\n"))
}

private func xlsxRowCSVLine(_ cells: [Cell], sharedStrings: SharedStrings?) -> String {
    let valuesByColumn = Dictionary(uniqueKeysWithValues: cells.map { cell in
        (xlsxColumnIndex(cell.reference.column.description), xlsxCellText(cell, sharedStrings: sharedStrings))
    })
    let maxColumn = valuesByColumn.keys.max() ?? 0
    guard maxColumn > 0 else { return "" }
    return (1...maxColumn)
        .map { csvEscapedField(valuesByColumn[$0] ?? "") }
        .joined(separator: ",")
}

private func xlsxCellText(_ cell: Cell, sharedStrings: SharedStrings?) -> String {
    if let sharedStrings, let value = cell.stringValue(sharedStrings) {
        return value
    }
    if let text = cell.inlineString?.text {
        return text
    }
    if let date = cell.dateValue {
        return importDateTimeString(from: date)
    }
    return cell.value ?? ""
}

private func xlsxColumnIndex(_ value: String) -> Int {
    value.uppercased().unicodeScalars.reduce(0) { result, scalar in
        guard (65...90).contains(scalar.value) else { return result }
        return result * 26 + Int(scalar.value - 64)
    }
}

private func csvEscapedField(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
        return value
    }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}

private func isImportHeaderLine(_ line: String, source: ImportSource) -> Bool {
    let normalized = cleanImportField(line)
    switch source {
    case .alipay:
        return normalized.contains("交易时间") &&
            normalized.contains("收/支") &&
            normalized.contains("金额") &&
            normalized.contains("交易订单号")
    case .wechat:
        return normalized.contains("交易时间") &&
            normalized.contains("收/支") &&
            normalized.contains("金额(元)") &&
            normalized.contains("交易单号")
    }
}

private func makeImportMemoryKey(source: ImportSource, counterparty: String, product: String) -> ImportMemoryKey? {
    let cleanedCounterparty = cleanImportField(counterparty)
    let cleanedProduct = cleanImportField(product)
    guard !cleanedCounterparty.isEmpty, cleanedCounterparty != "/" else { return nil }
    guard !cleanedProduct.isEmpty, cleanedProduct != "/" else { return nil }
    return ImportMemoryKey(source: source, counterparty: cleanedCounterparty, product: cleanedProduct)
}

private func importMemoryKey(source: ImportSource, rawPayload: String) -> ImportMemoryKey? {
    let fields = parseCSVLine(rawPayload)
    switch source {
    case .alipay:
        guard fields.count >= 5 else { return nil }
        return makeImportMemoryKey(
            source: source,
            counterparty: fields[2],
            product: fields[4]
        )
    case .wechat:
        guard fields.count >= 4 else { return nil }
        return makeImportMemoryKey(
            source: source,
            counterparty: fields[2],
            product: fields[3]
        )
    }
}

private func parseAlipayLine(
    _ line: String,
    lineNumber: Int,
    rows: inout [ParsedImportRow],
    issues: inout [ImportIssue]
) {
    let fields = parseCSVLine(line)
    guard fields.count >= 10 else {
        issues.append(ImportIssue(lineNumber: lineNumber, code: .unknownFields, message: "支付宝账单行字段不足"))
        return
    }

    let occurredAtText = cleanImportField(fields[0])
    let category = cleanImportField(fields[1])
    let counterparty = cleanImportField(fields[2])
    let product = cleanImportField(fields[safe: 4] ?? "")
    let amountText = cleanImportField(fields[safe: 6] ?? "")
    let paymentMethodName = cleanImportField(fields[safe: 7] ?? "")
    let transactionId = nonEmptyImportField(fields[safe: 9])

    guard let occurredAt = parseImportDate(occurredAtText) else {
        issues.append(ImportIssue(lineNumber: lineNumber, code: .invalidDate, message: "无法识别交易时间"))
        return
    }
    guard let unsignedAmount = parseImportAmount(amountText) else {
        issues.append(ImportIssue(lineNumber: lineNumber, code: .invalidAmount, message: "无法识别金额"))
        return
    }

    let amount = absoluteDecimal(unsignedAmount)
    let note = makeImportNote(prefix: category, counterparty: counterparty, product: product)
    rows.append(ParsedImportRow(
        lineNumber: lineNumber,
        rawPayload: line,
        accountMonth: accountMonthString(from: occurredAt),
        occurredAt: occurredAt,
        paymentMethodName: paymentMethodName.isEmpty ? nil : paymentMethodName,
        amount: amount,
        note: note,
        rawTransactionId: transactionId,
        rawFingerprint: makeRawFingerprint(source: .alipay, rawPayload: line),
        memoryKey: makeImportMemoryKey(source: .alipay, counterparty: counterparty, product: product)
    ))
}

private func parseWechatLine(
    _ line: String,
    lineNumber: Int,
    rows: inout [ParsedImportRow],
    issues: inout [ImportIssue]
) {
    let fields = parseCSVLine(line)
    guard fields.count >= 9 else {
        issues.append(ImportIssue(lineNumber: lineNumber, code: .unknownFields, message: "微信账单行字段不足"))
        return
    }

    let occurredAtText = cleanImportField(fields[0])
    let transactionType = cleanImportField(fields[1])
    let counterparty = cleanImportField(fields[2])
    let product = cleanImportField(fields[3])
    let amountText = cleanImportField(fields[5])
    let paymentMethodName = cleanImportField(fields[6])
    let transactionId = nonEmptyImportField(fields[safe: 8])

    guard let occurredAt = parseImportDate(occurredAtText) else {
        issues.append(ImportIssue(lineNumber: lineNumber, code: .invalidDate, message: "无法识别交易时间"))
        return
    }
    guard let unsignedAmount = parseImportAmount(amountText) else {
        issues.append(ImportIssue(lineNumber: lineNumber, code: .invalidAmount, message: "无法识别金额"))
        return
    }

    let amount = absoluteDecimal(unsignedAmount)
    let note = makeImportNote(prefix: transactionType, counterparty: counterparty, product: product)
    rows.append(ParsedImportRow(
        lineNumber: lineNumber,
        rawPayload: line,
        accountMonth: accountMonthString(from: occurredAt),
        occurredAt: occurredAt,
        paymentMethodName: paymentMethodName.isEmpty ? nil : paymentMethodName,
        amount: amount,
        note: note,
        rawTransactionId: transactionId,
        rawFingerprint: makeRawFingerprint(source: .wechat, rawPayload: line),
        memoryKey: makeImportMemoryKey(source: .wechat, counterparty: counterparty, product: product)
    ))
}

private func parseCSVLine(_ line: String) -> [String] {
    var fields: [String] = []
    var current = ""
    var isInsideQuotes = false
    var iterator = line.makeIterator()
    while let character = iterator.next() {
        if character == "\"" {
            if isInsideQuotes, let next = iterator.next() {
                if next == "\"" {
                    current.append("\"")
                } else {
                    isInsideQuotes.toggle()
                    if next == "," {
                        fields.append(current)
                        current = ""
                    } else {
                        current.append(next)
                    }
                }
            } else {
                isInsideQuotes.toggle()
            }
        } else if character == ",", !isInsideQuotes {
            fields.append(current)
            current = ""
        } else {
            current.append(character)
        }
    }
    fields.append(current)
    return fields.map(cleanImportField)
}

private func cleanImportField(_ value: String) -> String {
    value
        .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}\t\"")))
}

private func nonEmptyImportField(_ value: String?) -> String? {
    let cleaned = cleanImportField(value ?? "")
    return cleaned.isEmpty || cleaned == "/" ? nil : cleaned
}

private func parseImportDate(_ value: String) -> Date? {
    let trimmed = cleanImportField(value)
    let normalized = trimmed.count == 10 ? "\(trimmed) 00:00:00" : trimmed
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: normalized)
}

private func parseImportAmount(_ value: String) -> Decimal? {
    let cleaned = cleanImportField(value)
        .replacingOccurrences(of: "¥", with: "")
        .replacingOccurrences(of: "￥", with: "")
        .replacingOccurrences(of: ",", with: "")
        .replacingOccurrences(of: "元", with: "")
    if cleaned.isEmpty || cleaned == "/" || cleaned.lowercased() == "null" {
        return Decimal(0)
    }
    guard let amount = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
        return nil
    }
    return amount
}

private func absoluteDecimal(_ value: Decimal) -> Decimal {
    value < Decimal(0) ? -value : value
}

private func accountMonthString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM"
    return formatter.string(from: date)
}

private func importDateTimeString(from date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
}

private func makeImportNote(prefix: String, counterparty: String, product: String) -> String? {
    let parts = [counterparty, product].filter { !$0.isEmpty && $0 != "/" }
    guard !prefix.isEmpty || !parts.isEmpty else { return nil }
    let body = parts.joined(separator: " - ")
    if prefix.isEmpty {
        return body
    }
    if body.isEmpty {
        return "[\(prefix)]"
    }
    return "[\(prefix)] \(body)"
}

private func makeRawFingerprint(source: ImportSource, rawPayload: String) -> String {
    let payload = [
        source.rawValue,
        rawPayload
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\t", with: "")
    ].joined(separator: "|")
    let digest = SHA256.hash(data: Data(payload.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
}

private func decodeImportText(_ data: Data) throws -> String {
    let encodings: [String.Encoding] = [.utf8, .unicode, .utf16, .gb18030]
    for encoding in encodings {
        if let value = String(data: data, encoding: encoding) {
            return value
        }
    }
    throw MingZhangError.validation("无法读取账单文件编码")
}

private func isWechatNeutralTransaction(_ type: String) -> Bool {
    type == "零钱提现" ||
        type == "信用卡还款" ||
        type.hasPrefix("转入零钱通-") ||
        type.hasPrefix("零钱通转出-")
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String.Encoding {
    static var gb18030: String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
    }
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
