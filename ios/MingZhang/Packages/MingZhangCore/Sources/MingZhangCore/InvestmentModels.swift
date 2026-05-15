import Foundation

public enum InvestmentTransactionType: String, Codable, Equatable, Sendable, CaseIterable {
    case buy
    case sell
    case nav
}

public struct InvestmentTransaction: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var accountMonth: String
    public var occurredAt: Date
    public var fundName: String
    public var transactionType: InvestmentTransactionType
    public var tradeAmount: Decimal?
    public var tradeShare: Decimal?
    public var nav: Decimal?
    public var note: String?
    public var bookAmount: Decimal?
    public var realizedGain: Decimal
    public var realizedLoss: Decimal
    public var holdingShare: Decimal
    public var averageCost: Decimal?
    public var bookValue: Decimal
    public var presentValue: Decimal?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        accountMonth: String,
        occurredAt: Date,
        fundName: String,
        transactionType: InvestmentTransactionType,
        tradeAmount: Decimal?,
        tradeShare: Decimal?,
        nav: Decimal?,
        note: String?,
        bookAmount: Decimal?,
        realizedGain: Decimal,
        realizedLoss: Decimal,
        holdingShare: Decimal,
        averageCost: Decimal?,
        bookValue: Decimal,
        presentValue: Decimal?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.fundName = fundName
        self.transactionType = transactionType
        self.tradeAmount = tradeAmount
        self.tradeShare = tradeShare
        self.nav = nav
        self.note = note
        self.bookAmount = bookAmount
        self.realizedGain = realizedGain
        self.realizedLoss = realizedLoss
        self.holdingShare = holdingShare
        self.averageCost = averageCost
        self.bookValue = bookValue
        self.presentValue = presentValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CreateInvestmentTransactionInput: Equatable, Sendable {
    public var accountMonth: String
    public var occurredAt: Date
    public var fundName: String
    public var transactionType: InvestmentTransactionType
    public var tradeAmount: Decimal?
    public var tradeShare: Decimal?
    public var nav: Decimal?
    public var note: String?

    public init(
        accountMonth: String,
        occurredAt: Date,
        fundName: String,
        transactionType: InvestmentTransactionType,
        tradeAmount: Decimal? = nil,
        tradeShare: Decimal? = nil,
        nav: Decimal? = nil,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.fundName = fundName
        self.transactionType = transactionType
        self.tradeAmount = tradeAmount
        self.tradeShare = tradeShare
        self.nav = nav
        self.note = note
    }
}

public struct InvestmentTransactionChanges: Equatable, Sendable {
    public var accountMonth: String?
    public var occurredAt: Date?
    public var fundName: String?
    public var transactionType: InvestmentTransactionType?
    public var tradeAmount: Decimal?
    public var tradeShare: Decimal?
    public var nav: Decimal?
    public var note: String?

    public init(
        accountMonth: String? = nil,
        occurredAt: Date? = nil,
        fundName: String? = nil,
        transactionType: InvestmentTransactionType? = nil,
        tradeAmount: Decimal? = nil,
        tradeShare: Decimal? = nil,
        nav: Decimal? = nil,
        note: String? = nil
    ) {
        self.accountMonth = accountMonth
        self.occurredAt = occurredAt
        self.fundName = fundName
        self.transactionType = transactionType
        self.tradeAmount = tradeAmount
        self.tradeShare = tradeShare
        self.nav = nav
        self.note = note
    }
}

public struct InvestmentHolding: Equatable, Identifiable, Sendable {
    public var id: String { fundName }
    public var fundName: String
    public var accountMonth: String
    public var holdingShare: Decimal
    public var averageCost: Decimal?
    public var bookValue: Decimal
    public var latestNav: Decimal?
    public var presentValue: Decimal?
    public var unrealizedGain: Decimal?
    public var sourceTransactionIds: [UUID]

    public init(
        fundName: String,
        accountMonth: String,
        holdingShare: Decimal,
        averageCost: Decimal?,
        bookValue: Decimal,
        latestNav: Decimal?,
        presentValue: Decimal?,
        unrealizedGain: Decimal?,
        sourceTransactionIds: [UUID]
    ) {
        self.fundName = fundName
        self.accountMonth = accountMonth
        self.holdingShare = holdingShare
        self.averageCost = averageCost
        self.bookValue = bookValue
        self.latestNav = latestNav
        self.presentValue = presentValue
        self.unrealizedGain = unrealizedGain
        self.sourceTransactionIds = sourceTransactionIds
    }
}

public struct InvestmentMonthlySummary: Equatable, Sendable {
    public var accountMonth: String
    public var fundName: String?
    public var buyBookAmount: Decimal
    public var sellBookAmount: Decimal
    public var realizedGain: Decimal
    public var realizedLoss: Decimal
    public var endingBookValue: Decimal
    public var endingShare: Decimal
    public var feedJournalRecordIds: [UUID]
    public var sourceTransactionIds: [UUID]

    public init(
        accountMonth: String,
        fundName: String?,
        buyBookAmount: Decimal,
        sellBookAmount: Decimal,
        realizedGain: Decimal,
        realizedLoss: Decimal,
        endingBookValue: Decimal,
        endingShare: Decimal,
        feedJournalRecordIds: [UUID],
        sourceTransactionIds: [UUID]
    ) {
        self.accountMonth = accountMonth
        self.fundName = fundName
        self.buyBookAmount = buyBookAmount
        self.sellBookAmount = sellBookAmount
        self.realizedGain = realizedGain
        self.realizedLoss = realizedLoss
        self.endingBookValue = endingBookValue
        self.endingShare = endingShare
        self.feedJournalRecordIds = feedJournalRecordIds
        self.sourceTransactionIds = sourceTransactionIds
    }
}

public struct InvestmentFeedTrace: Equatable, Sendable {
    public var journalRecord: JournalRecord
    public var transactions: [InvestmentTransaction]

    public init(journalRecord: JournalRecord, transactions: [InvestmentTransaction]) {
        self.journalRecord = journalRecord
        self.transactions = transactions
    }
}
