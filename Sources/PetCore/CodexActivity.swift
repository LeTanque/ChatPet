import Foundation

public enum CodexActivityState: Sendable { case unknown, working, waiting, completed, failed }

/// Decode only routing metadata. Prompts, arguments, answers, and tool outputs are ignored.
public struct CodexActivityRecord: Decodable, Sendable {
    public let timestamp: String
    public let type: String
    public let payload: Payload
    public struct Payload: Decodable, Sendable {
        public let type: String?
        public let turn_id: String?
        public let call_id: String?
        public let name: String?
    }
    public var date: Date? {
        (try? Date(timestamp, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .colon)))
            ?? (try? Date(timestamp, strategy: .iso8601))
    }
}

public struct CodexSessionActivity: Sendable {
    public private(set) var state: CodexActivityState = .unknown
    public private(set) var updatedAt: Date = .distantPast
    private var turnID: String?
    private var pendingInputCalls: Set<String> = []
    public init() {}
    public mutating func consume(_ record: CodexActivityRecord, now: Date) {
        guard let time = record.date, time <= now.addingTimeInterval(10), time >= updatedAt else { return }
        let payload = record.payload
        if record.type == "event_msg" {
            switch payload.type {
            case "task_started":
                turnID = payload.turn_id; pendingInputCalls = []; state = .working
            case "task_complete", "turn_aborted", "task_failed":
                if let current = turnID, let ending = payload.turn_id, ending != current { return }
                pendingInputCalls = []
                state = payload.type == "task_complete" ? .completed : .failed
            case "agent_reasoning", "agent_message":
                // A tail can start in the middle of an already-running turn.
                if state == .unknown { state = .working }
                guard state == .working || state == .waiting else { return }
            default: return
            }
        } else if record.type == "response_item" {
            guard state != .completed && state != .failed else { return }
            switch payload.type {
            case "function_call", "custom_tool_call":
                if state == .unknown { state = .working }
                // Async questions don't block the task. Never infer approvals from shell arguments.
                if payload.name?.split(separator: ".").last == "request_user_input", let id = payload.call_id {
                    pendingInputCalls.insert(id); state = .waiting
                }
            case "function_call_output", "custom_tool_call_output":
                if let id = payload.call_id { pendingInputCalls.remove(id) }
                state = pendingInputCalls.isEmpty ? .working : .waiting
            case "reasoning":
                if state == .unknown { state = .working }
            default: return
            }
        } else { return }
        updatedAt = time
    }
}

/// Bounded incremental NDJSON decoding; oversize content is skipped until its newline.
public struct ActivityLineBuffer: Sendable {
    private var pending = Data()
    private var discarding: Bool
    private let maximumLineBytes: Int
    public init(skippingPartialLine: Bool = false, maximumLineBytes: Int = 128 * 1024) {
        discarding = skippingPartialLine; self.maximumLineBytes = maximumLineBytes
    }
    public mutating func append(_ data: Data) -> [CodexActivityRecord] {
        var records: [CodexActivityRecord] = []
        let decoder = JSONDecoder()
        let slices = data.split(separator: 10, omittingEmptySubsequences: false)
        for slice in slices.enumerated() {
            // The final slice has no terminating newline. Retain it for the next read.
            let terminated = slice.offset < slices.count - 1
            if !discarding {
                if pending.count + slice.element.count > maximumLineBytes { pending.removeAll(keepingCapacity: true); discarding = true }
                else { pending.append(contentsOf: slice.element) }
            }
            if terminated {
                if !discarding, let record = try? decoder.decode(CodexActivityRecord.self, from: pending) { records.append(record) }
                pending.removeAll(keepingCapacity: true); discarding = false
            }
        }
        return records
    }
}

public struct CodexActivitySummary: Equatable, Sendable {
    public var event: PetEvent?
    public var workingCount: Int
    public var waitingCount: Int
    public var monitoredCount: Int
    public var unreadableCount: Int = 0
    public init(event: PetEvent?, workingCount: Int, waitingCount: Int, monitoredCount: Int, unreadableCount: Int = 0) {
        self.event = event; self.workingCount = workingCount; self.waitingCount = waitingCount
        self.monitoredCount = monitoredCount; self.unreadableCount = unreadableCount
    }
    public static func summarize(_ sessions: [CodexSessionActivity], now: Date, monitoringSince: Date,
                                 staleAfter: TimeInterval, reactionDuration: TimeInterval) -> Self {
        let fresh = sessions.filter { now.timeIntervalSince($0.updatedAt) <= staleAfter }
        let working = fresh.filter { $0.state == .working }.count
        let waiting = fresh.filter { $0.state == .waiting }.count
        let recent = fresh.filter { $0.updatedAt >= monitoringSince && now.timeIntervalSince($0.updatedAt) < reactionDuration }
        let event: PetEvent? = waiting > 0 ? .taskWaiting :
            recent.contains { $0.state == .failed } ? .taskFailed :
            recent.contains { $0.state == .completed } ? .taskCompleted : working > 0 ? .taskWorking : nil
        return Self(event: event, workingCount: working, waitingCount: waiting, monitoredCount: sessions.count)
    }
}
