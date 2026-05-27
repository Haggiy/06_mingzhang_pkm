import Foundation

public struct BackupRecordCounts: Codable, Equatable, Sendable {
    public var paymentMethods: Int
    public var paymentTypes: Int
    public var paymentDetails: Int
    public var importBatches: Int
    public var investmentTransactions: Int
    public var journalRecords: Int
    public var importCandidates: Int

    public init(
        paymentMethods: Int,
        paymentTypes: Int,
        paymentDetails: Int,
        importBatches: Int,
        investmentTransactions: Int,
        journalRecords: Int,
        importCandidates: Int
    ) {
        self.paymentMethods = paymentMethods
        self.paymentTypes = paymentTypes
        self.paymentDetails = paymentDetails
        self.importBatches = importBatches
        self.investmentTransactions = investmentTransactions
        self.journalRecords = journalRecords
        self.importCandidates = importCandidates
    }
}

public struct BackupManifest: Codable, Equatable, Sendable {
    public var backupSchemaVersion: Int
    public var appDataSchemaVersion: String
    public var exportedAt: Date
    public var appVersion: String?
    public var recordCounts: BackupRecordCounts
    public var payloadChecksum: String

    public init(
        backupSchemaVersion: Int,
        appDataSchemaVersion: String,
        exportedAt: Date,
        appVersion: String?,
        recordCounts: BackupRecordCounts,
        payloadChecksum: String
    ) {
        self.backupSchemaVersion = backupSchemaVersion
        self.appDataSchemaVersion = appDataSchemaVersion
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.recordCounts = recordCounts
        self.payloadChecksum = payloadChecksum
    }
}

public struct BackupRestorePreview: Equatable, Sendable {
    public var recordCounts: BackupRecordCounts
    public var exportedAt: Date
    public var accountMonths: [String]

    public init(recordCounts: BackupRecordCounts, exportedAt: Date, accountMonths: [String]) {
        self.recordCounts = recordCounts
        self.exportedAt = exportedAt
        self.accountMonths = accountMonths
    }
}

public struct BackupValidationResult: Equatable, Sendable {
    public var isValid: Bool
    public var manifest: BackupManifest?
    public var preview: BackupRestorePreview?
    public var errors: [String]

    public init(
        isValid: Bool,
        manifest: BackupManifest?,
        preview: BackupRestorePreview?,
        errors: [String]
    ) {
        self.isValid = isValid
        self.manifest = manifest
        self.preview = preview
        self.errors = errors
    }
}

public struct BackupPackageResult: Equatable, Sendable {
    public var data: Data
    public var fileName: String
    public var manifest: BackupManifest

    public init(data: Data, fileName: String, manifest: BackupManifest) {
        self.data = data
        self.fileName = fileName
        self.manifest = manifest
    }
}

public struct BackupRestoreResult: Equatable, Sendable {
    public var recordCounts: BackupRecordCounts
    public var restoredAccountMonths: [String]

    public init(recordCounts: BackupRecordCounts, restoredAccountMonths: [String]) {
        self.recordCounts = recordCounts
        self.restoredAccountMonths = restoredAccountMonths
    }
}

public struct AuditExportResult: Equatable, Sendable {
    public var data: Data
    public var fileName: String
    public var exportedAt: Date

    public init(data: Data, fileName: String, exportedAt: Date) {
        self.data = data
        self.fileName = fileName
        self.exportedAt = exportedAt
    }
}
