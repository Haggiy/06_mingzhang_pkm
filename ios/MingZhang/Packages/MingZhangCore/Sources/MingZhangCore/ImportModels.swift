import Foundation

public enum ImportSource: String, Codable, Equatable, Sendable {
    case alipay
    case wechat

    public var displayName: String {
        switch self {
        case .alipay:
            "支付宝"
        case .wechat:
            "微信"
        }
    }
}

public enum ImportBatchStatus: String, Codable, Equatable, Sendable {
    case draft
    case confirmed
    case failed
}

public enum ImportCandidateStatus: String, Codable, Equatable, Sendable {
    case pending
    case ignored
    case confirmed
}

public enum ImportIssueCode: String, Codable, Equatable, Sendable {
    case invalidAmount
    case invalidDate
    case unknownFields
    case duplicate
    case unsupportedDirection
}

public struct ImportBatch: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var source: ImportSource
    public var fileName: String?
    public var importedAt: Date
    public var status: ImportBatchStatus
    public var confirmedRecordCount: Int

    public init(
        id: UUID,
        source: ImportSource,
        fileName: String?,
        importedAt: Date,
        status: ImportBatchStatus,
        confirmedRecordCount: Int
    ) {
        self.id = id
        self.source = source
        self.fileName = fileName
        self.importedAt = importedAt
        self.status = status
        self.confirmedRecordCount = confirmedRecordCount
    }
}

public struct ImportCandidateRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var batchId: UUID
    public var status: ImportCandidateStatus
    public var accountMonth: String
    public var occurredAt: Date
    public var paymentMethodId: UUID?
    public var paymentMethodName: String?
    public var amount: Decimal
    public var paymentTypeId: UUID?
    public var paymentTypeName: String?
    public var paymentDetailId: UUID?
    public var paymentDetailName: String?
    public var note: String?
    public var rawLineNumber: Int
    public var rawPayload: String
    public var rawTransactionId: String?
    public var rawFingerprint: String
    public var createdJournalRecordId: UUID?

    public init(
        id: UUID,
        batchId: UUID,
        status: ImportCandidateStatus,
        accountMonth: String,
        occurredAt: Date,
        paymentMethodId: UUID?,
        paymentMethodName: String?,
        amount: Decimal,
        paymentTypeId: UUID?,
        paymentTypeName: String?,
        paymentDetailId: UUID?,
        paymentDetailName: String?,
        note: String?,
        rawLineNumber: Int,
        rawPayload: String,
        rawTransactionId: String?,
        rawFingerprint: String,
        createdJournalRecordId: UUID?
    ) {
        self.id = id
        self.batchId = batchId
        self.status = status
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.paymentMethodId = paymentMethodId
        self.paymentMethodName = paymentMethodName
        self.amount = amount
        self.paymentTypeId = paymentTypeId
        self.paymentTypeName = paymentTypeName
        self.paymentDetailId = paymentDetailId
        self.paymentDetailName = paymentDetailName
        self.note = note
        self.rawLineNumber = rawLineNumber
        self.rawPayload = rawPayload
        self.rawTransactionId = rawTransactionId
        self.rawFingerprint = rawFingerprint
        self.createdJournalRecordId = createdJournalRecordId
    }
}

public struct ImportCandidateChanges: Equatable, Sendable {
    public var accountMonth: String?
    public var amount: Decimal?
    public var paymentMethodName: String?
    public var paymentTypeName: String?
    public var paymentDetailName: String?
    public var note: String?

    public init(
        accountMonth: String? = nil,
        amount: Decimal? = nil,
        paymentMethodName: String? = nil,
        paymentTypeName: String? = nil,
        paymentDetailName: String? = nil,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.amount = amount
        self.paymentMethodName = paymentMethodName
        self.paymentTypeName = paymentTypeName
        self.paymentDetailName = paymentDetailName
        self.note = note
    }
}

public struct ImportIssue: Equatable, Sendable {
    public var lineNumber: Int?
    public var code: ImportIssueCode
    public var message: String

    public init(lineNumber: Int?, code: ImportIssueCode, message: String) {
        self.lineNumber = lineNumber
        self.code = code
        self.message = message
    }
}

public struct CreateImportBatchResult: Equatable, Sendable {
    public var batch: ImportBatch
    public var candidates: [ImportCandidateRecord]
    public var issues: [ImportIssue]

    public init(batch: ImportBatch, candidates: [ImportCandidateRecord], issues: [ImportIssue]) {
        self.batch = batch
        self.candidates = candidates
        self.issues = issues
    }
}

public struct ImportTrace: Equatable, Sendable {
    public var batch: ImportBatch
    public var candidate: ImportCandidateRecord

    public init(batch: ImportBatch, candidate: ImportCandidateRecord) {
        self.batch = batch
        self.candidate = candidate
    }
}
