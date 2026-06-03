import Foundation
import Combine
import MingZhangCore

@MainActor
final class LedgerStore: ObservableObject {
    private let useInMemory: Bool

    init(useInMemory: Bool = false) {
        self.useInMemory = useInMemory
    }
    @Published private(set) var accountMonth = "2026-04"
    @Published private(set) var availableAccountMonths: [String] = ["2026-04"]
    @Published private(set) var journalFilter = JournalRecordFilter(accountMonths: ["2026-04"])
    @Published private(set) var records: [JournalRecord] = []
    @Published private(set) var methods: [PaymentMethod] = []
    @Published private(set) var types: [PaymentType] = []
    @Published private(set) var details: [PaymentDetail] = []
    @Published private(set) var homeSummary = HomeSummary(incomeTotal: 0, expenseTotal: 0, balance: 0, recentRecordIds: [])
    @Published private(set) var balanceSummary = BalanceSummary(cashBalance: 0, liabilityItems: [])
    @Published private(set) var statisticsSummary = StatisticsSummary(expenseByType: [], sourceRecordIds: [])
    @Published private(set) var investmentHoldings: [InvestmentHolding] = []
    @Published private(set) var investmentTransactions: [InvestmentTransaction] = []
    @Published private(set) var investmentMonthlySummary = InvestmentMonthlySummary(
        accountMonth: "2026-04",
        fundName: nil,
        buyBookAmount: 0,
        sellBookAmount: 0,
        realizedGain: 0,
        realizedLoss: 0,
        endingBookValue: 0,
        endingShare: 0,
        feedJournalRecordIds: [],
        sourceTransactionIds: []
    )
    @Published private(set) var activeImportSource: ImportSource?
    @Published private(set) var activeImportBatch: ImportBatch?
    @Published private(set) var importCandidates: [ImportCandidateRecord] = []
    @Published private(set) var importIssues: [ImportIssue] = []
    @Published var selectedImportCandidateIds: Set<UUID> = []
    @Published var lastError: String?
    @Published private(set) var isDataManagementBusy = false
    @Published private(set) var auditExportURL: URL?
    @Published private(set) var backupPackageURL: URL?
    @Published private(set) var backupValidation: BackupValidationResult?
    @Published private(set) var restoreResult: BackupRestoreResult?
    @Published private(set) var restoreFailureMessage: String?
    @Published private(set) var pendingBackupFileName: String?

    private var pendingBackupData: Data?

    var userVisibleMethods: [PaymentMethod] {
        methods.filter { $0.methodType != .pendingRealAccount }
    }

    var activePaymentMethods: [PaymentMethod] {
        userVisibleMethods.filter(\.isActive)
    }

    var activePaymentTypes: [PaymentType] {
        types.filter(\.isActive)
    }

    var activePaymentDetails: [PaymentDetail] {
        let activeTypeIds = Set(activePaymentTypes.map(\.id))
        return details.filter { $0.isActive && activeTypeIds.contains($0.paymentTypeId) }
    }

    var isUITesting: Bool {
        useInMemory
    }

    private var useCases: LedgerUseCases?

    func bootstrap() async {
        do {
            let database: LedgerDatabase
            if useInMemory {
                database = try LedgerDatabase.inMemory()
            } else {
                let databaseURL = try Self.databaseURL()
                database = try LedgerDatabase.fileBacked(at: databaseURL)
            }
            let useCases = LedgerUseCases(database: database)
            try useCases.initializeLedgerSeed()
            self.useCases = useCases
            try refresh()
            try processUITestSetup()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 处理 UITest 环境变量注入的设置数据
    private func processUITestSetup() throws {
        guard useInMemory else { return }
        guard let useCases else { return }
        let env = ProcessInfo.processInfo.environment

        // 处理多步设置导入（MZ_SETUP_0_CSV, MZ_SETUP_1_CSV, ...）
        var stepIndex = 0
        while let csv = env["MZ_SETUP_\(stepIndex)_CSV"] {
            let sourceStr = env["MZ_SETUP_\(stepIndex)_SOURCE"] ?? "alipay"
            let typeName = env["MZ_SETUP_\(stepIndex)_TYPE"]
            let detailName = env["MZ_SETUP_\(stepIndex)_DETAIL"]
            let source: ImportSource = sourceStr == "wechat" ? .wechat : .alipay

            let batch = try useCases.createImportBatch(source: source, fileName: "setup-\(stepIndex).csv", contents: csv)
            if let candidate = batch.candidates.first, let typeName, let detailName {
                let objectKey = env["MZ_SETUP_\(stepIndex)_OBJECT_KEY"]
                _ = try useCases.updateImportCandidate(id: candidate.id, changes: ImportCandidateChanges(
                    paymentMethodName: candidate.paymentMethodName,
                    paymentTypeName: typeName,
                    paymentDetailName: detailName,
                    objectKey: objectKey
                ))
                _ = try useCases.confirmImportCandidates(ids: [candidate.id])
            }
            stepIndex += 1
        }
        if stepIndex > 0 {
            try refresh()
        }

        // 处理待验证的测试导入（通过 store 方法确保所有状态正确更新）
        if let testCSV = env["MZ_TEST_CSV"] {
            let sourceStr = env["MZ_TEST_SOURCE"] ?? "alipay"
            let source: ImportSource = sourceStr == "wechat" ? .wechat : .alipay
            _ = createImportBatch(source: source, fileName: "test.csv", contents: testCSV)
        }

        if let setup = env["MZ_INVESTMENT_SETUP"] {
            for line in setup.split(separator: "\n") {
                let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 8 else { continue }
                let input = try InvestmentFormInput(
                    accountMonth: parts[0],
                    occurredDateText: parts[1],
                    fundName: parts[2],
                    transactionType: InvestmentTransactionType(rawValue: parts[3]) ?? .buy,
                    tradeAmountText: parts[4],
                    tradeShareText: parts[5],
                    navText: parts[6],
                    note: parts[7]
                ).toCreateInput()
                _ = try useCases.createInvestmentTransaction(input: input)
            }
            try refresh()
        }

        if let restoreScenario = env["MZ_RESTORE_TEST_SCENARIO"] {
            _ = prepareUITestRestoreBackup(valid: restoreScenario != "invalid")
        }
    }

    func refresh() throws {
        guard let useCases else { return }
        methods = try useCases.queryPaymentMethods()
        types = try useCases.queryPaymentTypes()
        details = try useCases.queryPaymentDetails()
        let queriedMonths = try useCases.queryAccountMonths()
        availableAccountMonths = queriedMonths.isEmpty ? [accountMonth] : queriedMonths
        if !availableAccountMonths.contains(accountMonth), let first = availableAccountMonths.first {
            accountMonth = first
        }
        journalFilter.accountMonths = [accountMonth]
        records = try useCases.queryJournalRecords(filter: journalFilter)
        homeSummary = try useCases.queryHomeSummary(accountMonth: accountMonth)
        balanceSummary = try useCases.queryBalanceSummary(accountMonth: accountMonth)
        statisticsSummary = try useCases.queryStatisticsSummary(accountMonth: accountMonth)
        investmentHoldings = try useCases.queryInvestmentHoldings(accountMonth: accountMonth)
        investmentMonthlySummary = try useCases.queryInvestmentMonthlySummary(accountMonth: accountMonth, fundName: nil)
        lastError = nil
    }

    func selectAccountMonth(_ month: String) -> Bool {
        do {
            accountMonth = month
            journalFilter.accountMonths = [month]
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func applyJournalFilter(_ filter: JournalRecordFilter) -> Bool {
        do {
            var scopedFilter = filter
            scopedFilter.accountMonths = [accountMonth]
            journalFilter = scopedFilter
            guard let useCases else { return false }
            records = try useCases.queryJournalRecords(filter: scopedFilter)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func clearJournalFilter() -> Bool {
        applyJournalFilter(JournalRecordFilter(accountMonths: [accountMonth]))
    }

    func queryRecords(filter: JournalRecordFilter) throws -> [JournalRecord] {
        guard let useCases else { return [] }
        return try useCases.queryJournalRecords(filter: filter)
    }

    func querySourceRecords(recordIds: [UUID]) throws -> [JournalRecord] {
        guard let useCases else { return [] }
        return try useCases.queryJournalRecords(recordIds: recordIds)
    }

    func createPaymentMethod(input: CreatePaymentMethodInput) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.createPaymentMethod(input: input)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updatePaymentMethod(id: UUID, input: UpdatePaymentMethodInput) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.updatePaymentMethod(id: id, input: input)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func disablePaymentMethod(id: UUID) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.disablePaymentMethod(id: id)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createPaymentType(input: CreatePaymentTypeInput) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.createPaymentType(input: input)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updatePaymentType(id: UUID, input: UpdatePaymentTypeInput) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.updatePaymentType(id: id, input: input)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func disablePaymentType(id: UUID) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.disablePaymentType(id: id)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createPaymentDetail(input: CreatePaymentDetailInput) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.createPaymentDetail(input: input)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updatePaymentDetail(id: UUID, input: UpdatePaymentDetailInput) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.updatePaymentDetail(id: id, input: input)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func disablePaymentDetail(id: UUID) -> Bool {
        do {
            guard let useCases else { return false }
            _ = try useCases.disablePaymentDetail(id: id)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func prepareImport(source: ImportSource) {
        activeImportSource = source
        activeImportBatch = nil
        importCandidates = []
        importIssues = []
        selectedImportCandidateIds = []
        lastError = nil
    }

    func createImportBatch(source: ImportSource, fileName: String?, contents: String) -> Bool {
        do {
            guard let useCases else { return false }
            let result = try useCases.createImportBatch(source: source, fileName: fileName, contents: contents)
            applyImportResult(result, source: source)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createImportBatch(source: ImportSource, fileName: String?, data: Data) -> Bool {
        do {
            guard let useCases else { return false }
            let result = try useCases.createImportBatch(source: source, fileName: fileName, data: data)
            applyImportResult(result, source: source)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updateImportCandidate(id: UUID, changes: ImportCandidateChanges) -> Bool {
        do {
            guard let useCases else { return false }
            let updated = try useCases.updateImportCandidate(id: id, changes: changes)
            replaceImportCandidates(with: [updated])
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func batchUpdateImportCandidates(ids: Set<UUID>, changes: ImportCandidateChanges) -> Bool {
        do {
            guard let useCases else { return false }
            let updated = try useCases.batchUpdateImportCandidates(ids: Array(ids), changes: changes)
            replaceImportCandidates(with: updated)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func confirmSelectedImportCandidates() -> Bool {
        do {
            guard let useCases else { return false }
            let records = try useCases.confirmImportCandidates(ids: Array(selectedImportCandidateIds))
            if let month = records.first?.accountMonth {
                accountMonth = month
            }
            if let batch = activeImportBatch {
                importCandidates = try useCases.queryImportCandidates(batchId: batch.id)
                activeImportBatch = try useCases.queryImportBatches().first { $0.id == batch.id }
            }
            selectedImportCandidateIds = []
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func ignoreSelectedImportCandidates() -> Bool {
        do {
            guard let useCases else { return false }
            let ignored = try useCases.ignoreImportCandidates(ids: Array(selectedImportCandidateIds))
            replaceImportCandidates(with: ignored)
            selectedImportCandidateIds = []
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func loadImportTrace(recordId: UUID) -> ImportTrace? {
        do {
            guard let useCases else { return nil }
            let trace = try useCases.getImportTrace(recordId: recordId)
            lastError = nil
            return trace
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func loadInvestmentTransactions(fundName: String?) -> [InvestmentTransaction] {
        do {
            guard let useCases else { return [] }
            let transactions = try useCases.queryInvestmentTransactions(fundName: fundName)
            investmentTransactions = transactions
            lastError = nil
            return transactions
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func loadInvestmentMonthlySummary(fundName: String?) -> InvestmentMonthlySummary? {
        do {
            guard let useCases else { return nil }
            let summary = try useCases.queryInvestmentMonthlySummary(accountMonth: accountMonth, fundName: fundName)
            if fundName == nil {
                investmentMonthlySummary = summary
            }
            lastError = nil
            return summary
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func loadInvestmentFeedRecords(fundName: String?) -> [JournalRecord] {
        do {
            guard let useCases else { return [] }
            let records = try useCases.queryInvestmentFeedRecords(accountMonth: accountMonth, fundName: fundName)
            lastError = nil
            return records
        } catch {
            lastError = error.localizedDescription
            return []
        }
    }

    func loadInvestmentTrace(recordId: UUID) -> InvestmentFeedTrace? {
        do {
            guard let useCases else { return nil }
            let trace = try useCases.getInvestmentFeedTrace(recordId: recordId)
            lastError = nil
            return trace
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func createInvestmentTransaction(input: InvestmentFormInput) -> Bool {
        do {
            guard let useCases else { return false }
            let created = try useCases.createInvestmentTransaction(input: try input.toCreateInput())
            accountMonth = created.accountMonth
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func updateInvestmentTransaction(id: UUID, input: InvestmentFormInput) -> Bool {
        do {
            guard let useCases else { return false }
            let updated = try useCases.updateInvestmentTransaction(id: id, changes: try input.toChanges())
            accountMonth = updated.accountMonth
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func deleteInvestmentTransaction(id: UUID) -> Bool {
        do {
            guard let useCases else { return false }
            try useCases.deleteInvestmentTransaction(id: id)
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createRecord(input: JournalFormInput) -> Bool {
        do {
            guard let useCases else { return false }
            let created = try useCases.createManualRecord(input: try input.toCreateInput())
            accountMonth = created.accountMonth
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createLiabilityCost(input: JournalFormInput) -> Bool {
        do {
            guard let useCases else { return false }
            let created = try useCases.createLiabilityCost(input: CreateLiabilityCostInput(
                accountMonth: input.accountMonth,
                occurredAt: input.occurredAt,
                liabilityObjectKey: input.liabilityObjectKey,
                amount: try input.parsedAmount(),
                kind: input.liabilityCostKind,
                note: input.note.isEmpty ? nil : input.note
            ))
            accountMonth = created.accountMonth
            try refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createDeferredRelease(input: DeferredReleaseFormInput) -> Bool {
        do {
            guard let useCases else { return false }
            let result = try useCases.createDeferredRelease(input: try input.toCreateInput())
            accountMonth = result.assetReleaseRecord.accountMonth
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
            let updated = try useCases.updateJournalRecord(
                id: id,
                changes: try input.toChanges()
            )
            accountMonth = updated.accountMonth
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

    func exportAuditData() -> Bool {
        do {
            isDataManagementBusy = true
            defer { isDataManagementBusy = false }
            guard let useCases else { return false }
            let result = try useCases.exportAuditData()
            auditExportURL = try writeTemporaryFile(data: result.data, fileName: result.fileName)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func createBackupPackage() -> Bool {
        do {
            isDataManagementBusy = true
            defer { isDataManagementBusy = false }
            guard let useCases else { return false }
            let result = try useCases.createBackupPackage()
            backupPackageURL = try writeTemporaryFile(data: result.data, fileName: result.fileName)
            pendingBackupData = result.data
            pendingBackupFileName = result.fileName
            backupValidation = try useCases.validateBackupPackage(data: result.data)
            restoreResult = nil
            restoreFailureMessage = nil
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func validateBackupFile(at url: URL) -> Bool {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let data = try Data(contentsOf: url)
            return validateBackupData(data, fileName: url.lastPathComponent)
        } catch {
            backupValidation = BackupValidationResult(
                isValid: false,
                manifest: nil,
                preview: nil,
                errors: ["备份文件读取失败：\(error.localizedDescription)"]
            )
            pendingBackupData = nil
            pendingBackupFileName = url.lastPathComponent
            restoreResult = nil
            restoreFailureMessage = nil
            lastError = nil
            return false
        }
    }

    func validateBackupData(_ data: Data, fileName: String) -> Bool {
        do {
            guard let useCases else { return false }
            let validation = try useCases.validateBackupPackage(data: data)
            backupValidation = validation
            pendingBackupData = validation.isValid ? data : nil
            pendingBackupFileName = fileName
            restoreResult = nil
            restoreFailureMessage = nil
            lastError = nil
            return validation.isValid
        } catch {
            backupValidation = BackupValidationResult(
                isValid: false,
                manifest: nil,
                preview: nil,
                errors: [error.localizedDescription]
            )
            pendingBackupData = nil
            pendingBackupFileName = fileName
            restoreResult = nil
            restoreFailureMessage = nil
            lastError = nil
            return false
        }
    }

    func restoreValidatedBackup() -> Bool {
        do {
            isDataManagementBusy = true
            defer { isDataManagementBusy = false }
            guard let useCases, let pendingBackupData else {
                throw MingZhangError.validation("请先选择并校验备份文件")
            }
            let result = try useCases.restoreBackupPackage(data: pendingBackupData, confirmed: true)
            restoreResult = result
            restoreFailureMessage = nil
            self.pendingBackupData = nil
            try refresh()
            return true
        } catch {
            restoreResult = nil
            restoreFailureMessage = "恢复失败，当前数据未被修改。\(error.localizedDescription)"
            lastError = error.localizedDescription
            return false
        }
    }

    func clearBackupFlow() {
        backupValidation = nil
        restoreResult = nil
        restoreFailureMessage = nil
        pendingBackupData = nil
        pendingBackupFileName = nil
    }

    func prepareUITestRestoreBackup(valid: Bool) -> Bool {
        guard useInMemory else { return false }
        do {
            guard let useCases else { return false }
            let data: Data
            let fileName: String
            if valid {
                let package = try useCases.createBackupPackage()
                data = package.data
                fileName = package.fileName
            } else {
                data = Data("{\"format\":\"mingzhang.backup\",\"broken\":true}".utf8)
                fileName = "broken.mzbackup"
            }
            return validateBackupData(data, fileName: fileName)
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

    private func writeTemporaryFile(data: Data, fileName: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MingZhangExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func replaceImportCandidates(with updated: [ImportCandidateRecord]) {
        var candidatesById = Dictionary(uniqueKeysWithValues: importCandidates.map { ($0.id, $0) })
        for candidate in updated {
            candidatesById[candidate.id] = candidate
            if candidate.status != .pending {
                selectedImportCandidateIds.remove(candidate.id)
            }
        }
        importCandidates = candidatesById.values.sorted { ($0.occurredAt, $0.rawLineNumber) < ($1.occurredAt, $1.rawLineNumber) }
    }

    private func applyImportResult(_ result: CreateImportBatchResult, source: ImportSource) {
        activeImportSource = source
        activeImportBatch = result.batch
        importCandidates = result.candidates
        importIssues = result.issues
        selectedImportCandidateIds = []
        lastError = nil
    }
}

struct DeferredReleaseFormInput: Equatable {
    var accountMonth: String
    var occurredAt: Date
    var deferredObjectKey: String
    var amountText: String
    var expensePaymentTypeName: String
    var expensePaymentDetailName: String
    var note: String
    var remainingAmount: Decimal

    func parsedAmount() throws -> Decimal {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MingZhangError.validation("金额不能为空")
        }
        guard let amount = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MingZhangError.validation("金额必须是有效数字")
        }
        return amount
    }

    func toCreateInput() throws -> CreateDeferredReleaseInput {
        try validateRequiredFields()
        let amount = try parsedAmount()
        guard amount > 0 else {
            throw MingZhangError.validation("递延释放金额必须大于 0")
        }
        guard amount <= remainingAmount else {
            throw MingZhangError.validation("递延释放金额不能超过递延余额")
        }
        return CreateDeferredReleaseInput(
            accountMonth: accountMonth,
            occurredAt: occurredAt,
            deferredObjectKey: deferredObjectKey,
            amount: amount,
            expensePaymentTypeName: expensePaymentTypeName,
            expensePaymentDetailName: expensePaymentDetailName,
            note: note.isEmpty ? nil : note
        )
    }

    private func validateRequiredFields() throws {
        if accountMonth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("账月不能为空")
        }
        if deferredObjectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("递延对象不能为空")
        }
        if expensePaymentTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("收付类型不能为空")
        }
        if expensePaymentDetailName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("类型明细不能为空")
        }
    }

    static func deferredRelease(item: DeferredBalanceItem, accountMonth: String, now: Date = Date()) -> DeferredReleaseFormInput {
        DeferredReleaseFormInput(
            accountMonth: accountMonth,
            occurredAt: now,
            deferredObjectKey: item.objectKey,
            amountText: "",
            expensePaymentTypeName: "投资自身开支",
            expensePaymentDetailName: "健身训练费",
            note: "",
            remainingAmount: item.amount
        )
    }
}

struct JournalFormInput: Equatable {
    var accountMonth: String
    var occurredAt: Date
    var paymentMethodName: String
    var amountText: String
    var paymentTypeName: String
    var paymentDetailName: String
    var liabilityObjectKey: String
    var note: String

    func parsedAmount() throws -> Decimal {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MingZhangError.validation("金额不能为空")
        }
        guard let amount = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MingZhangError.validation("金额必须是有效数字")
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
            objectKey: liabilityObjectKey.isEmpty ? nil : liabilityObjectKey,
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
            objectKey: liabilityObjectKey.isEmpty ? nil : liabilityObjectKey,
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
            liabilityObjectKey: "",
            note: "午餐"
        )
    }

    static func liabilityRepayment(item: BalanceItem, accountMonth: String, now: Date = Date()) -> JournalFormInput {
        let objectKey = item.objectKey ?? "liability:\(item.name)"
        let amount = item.amount > 0 ? item.amount : Decimal(0)
        return JournalFormInput(
            accountMonth: accountMonth,
            occurredAt: now,
            paymentMethodName: "电子钱包余额",
            amountText: NSDecimalNumber(decimal: amount).stringValue,
            paymentTypeName: "负债类减记",
            paymentDetailName: "账单还款",
            liabilityObjectKey: objectKey,
            note: "\(item.name)还款"
        )
    }

    static func liabilityCost(
        item: BalanceItem,
        accountMonth: String,
        kind: LiabilityCostKind = .interest,
        now: Date = Date()
    ) -> JournalFormInput {
        let objectKey = item.objectKey ?? "liability:\(item.name)"
        return JournalFormInput(
            accountMonth: accountMonth,
            occurredAt: now,
            paymentMethodName: item.name,
            amountText: "",
            paymentTypeName: "财务费用开支",
            paymentDetailName: kind.paymentDetailName,
            liabilityObjectKey: objectKey,
            note: "\(item.name)\(kind.noteSuffix)"
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
            liabilityObjectKey: record.objectKey ?? "",
            note: record.note ?? ""
        )
    }

    var liabilityCostKind: LiabilityCostKind {
        paymentDetailName == LiabilityCostKind.fee.paymentDetailName ? .fee : .interest
    }

    mutating func applyLiabilityCostKind(_ kind: LiabilityCostKind) {
        paymentTypeName = "财务费用开支"
        paymentDetailName = kind.paymentDetailName
    }
}

extension LiabilityCostKind {
    var displayName: String {
        switch self {
        case .interest:
            "利息"
        case .fee:
            "费用"
        }
    }

    var paymentDetailName: String {
        switch self {
        case .interest:
            "金融利息支出"
        case .fee:
            "金融手续费与罚款"
        }
    }

    var noteSuffix: String {
        switch self {
        case .interest:
            "利息"
        case .fee:
            "费用"
        }
    }
}

struct InvestmentFormInput: Equatable {
    var accountMonth = "2026-04"
    var occurredDateText = "2026-04-10"
    var fundName = "沪深300指数A"
    var transactionType: InvestmentTransactionType = .buy
    var tradeAmountText = ""
    var tradeShareText = ""
    var navText = ""
    var note = ""

    func toCreateInput() throws -> CreateInvestmentTransactionInput {
        try validateRequiredFields()
        return CreateInvestmentTransactionInput(
            accountMonth: accountMonth,
            occurredAt: try parseDate(),
            fundName: fundName,
            transactionType: transactionType,
            tradeAmount: try parseOptionalDecimal(tradeAmountText, fieldName: "交易金额"),
            tradeShare: try parseOptionalDecimal(tradeShareText, fieldName: "交易份额"),
            nav: try parseOptionalDecimal(navText, fieldName: "单位净值"),
            note: note.isEmpty ? nil : note
        )
    }

    func toChanges() throws -> InvestmentTransactionChanges {
        try validateRequiredFields()
        let tradeAmount = try parseOptionalDecimal(tradeAmountText, fieldName: "交易金额")
        let tradeShare = try parseOptionalDecimal(tradeShareText, fieldName: "交易份额")
        let nav = try parseOptionalDecimal(navText, fieldName: "单位净值")
        let normalizedNote: String? = note.isEmpty ? nil : note
        return InvestmentTransactionChanges(
            accountMonth: accountMonth,
            occurredAt: try parseDate(),
            fundName: fundName,
            transactionType: transactionType,
            tradeAmount: tradeAmount,
            tradeShare: tradeShare,
            nav: nav,
            note: normalizedNote
        )
    }

    private func validateRequiredFields() throws {
        if accountMonth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("账月不能为空")
        }
        if fundName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MingZhangError.validation("标的名称不能为空")
        }
    }

    private func parseDate() throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: occurredDateText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw MingZhangError.invalidDate(occurredDateText)
        }
        return date
    }

    private func parseOptionalDecimal(_ value: String, fieldName: String) throws -> Decimal? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let amount = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MingZhangError.validation("\(fieldName)必须是有效数字")
        }
        return amount
    }

    static func from(transaction: InvestmentTransaction) -> InvestmentFormInput {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return InvestmentFormInput(
            accountMonth: transaction.accountMonth,
            occurredDateText: formatter.string(from: transaction.occurredAt),
            fundName: transaction.fundName,
            transactionType: transaction.transactionType,
            tradeAmountText: transaction.tradeAmount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
            tradeShareText: transaction.tradeShare.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
            navText: transaction.nav.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
            note: transaction.note ?? ""
        )
    }
}
