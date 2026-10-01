import Foundation

@MainActor final class Timer {
    let fire: (Timer) -> Void
    init(_ fire: @escaping (Timer) -> Void) { self.fire = fire }
    static func scheduledTimer(withTimeInterval interval: Double, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer {
        precondition(interval == 60 && repeats) // Delivery cadence must stay unchanged.
        return Timer(block)
    }
    func invalidate() {}
}
struct Column { init(_ name: String) {} }
func ==(lhs: Column, rhs: Bool) -> Bool { rhs }
@MainActor struct Account {
    static func filter(_ value: Bool) -> Account { Account() }
    func fetchCount(_ db: Int) throws -> Int { db }
}
@MainActor struct Pool {
    var enabledAccounts = 0
    func read<T>(_ body: (Int) throws -> T) rethrows -> T { try body(enabledAccounts) }
}
@MainActor final class Transport { func disconnect() async {} }
@MainActor final class Probe {
    var idleTasks: [String: Task<Void, Never>] = [:]
    var selectedIdleKey: String?
    var imapServices: [UUID: Transport] = [:]
    var commandIMAPServices: [UUID: Transport] = [:]
    var smtpServiceStore: [UUID: Int] = [:]
    var runningSyncs: [UUID: Task<Void, Never>] = [:]
    var accountSerialTail: [UUID: Task<Void, Never>] = [:]
    var accountCommandSerialTail: [UUID: Task<Void, Never>] = [:]
    var lastExistsCount: [UUID: Int] = [:]
    var pendingIdleEvents: [UUID: [Int]] = [:]
    var syncingFolders: Set<UUID> = []
    var bulkOpFolderIDs: Set<UUID> = []
    var pool = Pool()
    var receivingActivity: NSObjectProtocol?
    var periodicSyncTimer: Timer?
    var periodicSyncTask: Task<Void, Never>?
    var periodicFullRefreshPending = false
    var polls = 0
    var activePolls = 0
    var peakPolls = 0
    var fullRefreshes = 0
    func pruneExpiredMutations() {}
    func pollFolderStatuses() async {
        polls += 1; activePolls += 1; peakPolls = max(peakPolls, activePolls)
        try? await Task.sleep(for: .milliseconds(30))
        activePolls -= 1
    }
    func updateDockBadge() async {}
    func refreshAll() async { fullRefreshes += 1 }
    // PRODUCTION_METHODS
}
@main struct Check {
    @MainActor static func main() async {
        let p = Probe()
        p.updateReceivingActivity(); precondition(p.receivingActivity == nil)
        p.pool.enabledAccounts = 1
        p.updateReceivingActivity(); precondition(p.receivingActivity != nil)
        let activity = p.receivingActivity
        p.updateReceivingActivity(); precondition(p.receivingActivity === activity)
        p.pool.enabledAccounts = 0
        p.updateReceivingActivity(); precondition(p.receivingActivity == nil)
        p.startPeriodicSync()
        for _ in 0..<5 { p.periodicSyncTimer!.fire(p.periodicSyncTimer!) }
        try? await Task.sleep(for: .milliseconds(60))
        precondition(p.polls == 1 && p.peakPolls == 1 && p.fullRefreshes == 1)
        precondition(p.periodicSyncTask == nil)
        p.periodicSyncTimer!.fire(p.periodicSyncTimer!)
        try? await Task.sleep(for: .milliseconds(60))
        precondition(p.polls == 2 && p.peakPolls == 1 && p.fullRefreshes == 1)
        let a = UUID(), b = UUID()
        p.pool.enabledAccounts = 1
        p.updateReceivingActivity()
        let idleA = Task<Void, Never> { try? await Task.sleep(for: .seconds(10)) }
        let idleB = Task<Void, Never> { try? await Task.sleep(for: .seconds(10)) }
        p.idleTasks["\(a):INBOX"] = idleA
        p.idleTasks["\(b):INBOX"] = idleB
        p.selectedIdleKey = "\(b):INBOX"
        await p.removeAccount(id: a)
        precondition(idleA.isCancelled && !idleB.isCancelled)
        precondition(p.idleTasks["\(b):INBOX"] != nil && p.selectedIdleKey == "\(b):INBOX")
        precondition(p.receivingActivity != nil)
        idleB.cancel()
        p.pool.enabledAccounts = 0; p.updateReceivingActivity()
        print("PASS deleting one account preserves the other account's actual IDLE task and delivery activity")
        print("PASS production scheduler: unchanged 60s cadence, overlapping ticks coalesced, 5-minute refresh retained, next poll resumes; active-account App Nap protection retained")
    }
}
