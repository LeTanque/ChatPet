import Foundation
import Testing
@testable import PetCore

private func eventLine(_ type: String, at date: Date, envelope: String = "event_msg", turn: String? = "turn-1",
                       call: String? = nil, name: String? = nil) throws -> Data {
    var payload: [String: Any] = ["type": type]
    payload["turn_id"] = turn; payload["call_id"] = call; payload["name"] = name
    let dateString = ISO8601DateFormatter().string(from: date)
    var data = try JSONSerialization.data(withJSONObject: ["timestamp": dateString, "type": envelope, "payload": payload])
    data.append(10); return data
}
private func record(_ type: String, at date: Date, envelope: String = "event_msg", turn: String? = "turn-1",
                    call: String? = nil, name: String? = nil) throws -> CodexActivityRecord {
    try JSONDecoder().decode(CodexActivityRecord.self, from: eventLine(type, at: date, envelope: envelope, turn: turn, call: call, name: name))
}

@Test func taskLifecycleAndBlockingInputAreTracked() throws {
    let now = Date()
    var session = CodexSessionActivity()
    session.consume(try record("task_started", at: now), now: now)
    #expect(session.state == .working)
    session.consume(try record("function_call", at: now.addingTimeInterval(1), envelope: "response_item", call: "question", name: "request_user_input"), now: now.addingTimeInterval(1))
    #expect(session.state == .waiting)
    session.consume(try record("function_call_output", at: now.addingTimeInterval(2), envelope: "response_item", call: "other"), now: now.addingTimeInterval(2))
    #expect(session.state == .waiting)
    session.consume(try record("function_call_output", at: now.addingTimeInterval(3), envelope: "response_item", call: "question"), now: now.addingTimeInterval(3))
    #expect(session.state == .working)
    session.consume(try record("task_complete", at: now.addingTimeInterval(4)), now: now.addingTimeInterval(4))
    #expect(session.state == .completed)
    session.consume(try record("reasoning", at: now.addingTimeInterval(5), envelope: "response_item"), now: now.addingTimeInterval(5))
    #expect(session.state == .completed)
}

@Test func asyncQuestionAndToolErrorAreNotInventedFailuresOrBlockingStates() throws {
    let now = Date()
    var session = CodexSessionActivity()
    session.consume(try record("function_call", at: now, envelope: "response_item", call: "async", name: "request_user_input_async"), now: now)
    #expect(session.state == .working)
    session.consume(try record("function_call_output", at: now, envelope: "response_item", call: "async"), now: now)
    #expect(session.state == .working)
}

@Test func wrongTurnCompletionAndOutOfOrderEventsAreIgnored() throws {
    let now = Date()
    var session = CodexSessionActivity()
    session.consume(try record("task_started", at: now, turn: "new"), now: now)
    session.consume(try record("task_complete", at: now.addingTimeInterval(1), turn: "old"), now: now.addingTimeInterval(1))
    #expect(session.state == .working)
    session.consume(try record("turn_aborted", at: now.addingTimeInterval(-60), turn: "new"), now: now)
    #expect(session.state == .working)
    session.consume(try record("turn_aborted", at: now.addingTimeInterval(2), turn: "new"), now: now.addingTimeInterval(2))
    #expect(session.state == .failed)
}

@Test func historicalCompletionIsNotReplayedAndStaleWorkExpires() throws {
    let now = Date()
    var done = CodexSessionActivity(); var working = CodexSessionActivity()
    done.consume(try record("task_complete", at: now.addingTimeInterval(-1)), now: now)
    working.consume(try record("task_started", at: now.addingTimeInterval(-4000)), now: now)
    let summary = CodexActivitySummary.summarize([done, working], now: now, monitoringSince: now, staleAfter: 3600, reactionDuration: 4)
    #expect(summary.event == nil)
    #expect(summary.workingCount == 0)
}

@Test func multipleTasksChooseWaitingThenFailureThenCompletionThenWork() throws {
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    var work = CodexSessionActivity(); var waiting = CodexSessionActivity(); var failure = CodexSessionActivity(); var done = CodexSessionActivity()
    work.consume(try record("task_started", at: now), now: now)
    waiting.consume(try record("function_call", at: now, envelope: "response_item", call: "q", name: "functions.request_user_input"), now: now)
    failure.consume(try record("turn_aborted", at: now), now: now)
    done.consume(try record("task_complete", at: now), now: now)
    func summary(_ sessions: [CodexSessionActivity], at time: Date = now) -> CodexActivitySummary {
        .summarize(sessions, now: time, monitoringSince: now, staleAfter: 3600, reactionDuration: 4)
    }
    #expect(summary([work, waiting, failure, done]).event == .taskWaiting)
    #expect(summary([work, failure, done]).event == .taskFailed)
    #expect(summary([work, done]).event == .taskCompleted)
    #expect(summary([work, done], at: now.addingTimeInterval(5)).event == .taskWorking)
}

@Test func lineBufferHandlesSplitRecordsMalformedAndOversizedContent() throws {
    let line = try eventLine("task_started", at: Date())
    var buffer = ActivityLineBuffer(maximumLineBytes: 1024)
    #expect(buffer.append(line.prefix(20)).isEmpty)
    #expect(buffer.append(line.dropFirst(20)).count == 1)
    #expect(buffer.append(Data("not json\n".utf8)).isEmpty)
    #expect(buffer.append(Data(repeating: 65, count: 2000)).isEmpty)
    var next = Data("trailing giant message\n".utf8); next.append(line)
    #expect(buffer.append(next).count == 1)
    var tail = ActivityLineBuffer(skippingPartialLine: true)
    #expect(tail.append(next).count == 1)
}

@Test func eventRecordIgnoresConversationContentAndAcceptsFractionalTimestamp() throws {
    let data = Data(#"{"timestamp":"2026-09-14T20:15:30.123Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t","last_agent_message":"private text","arguments":{"nested":"not retained"}}}"#.utf8)
    let record = try JSONDecoder().decode(CodexActivityRecord.self, from: data)
    #expect(record.payload.type == "task_started")
    #expect(record.date != nil)
}

@Test func taskPriorityDoesNotReplayExpiredNetworkFailure() {
    var router = EventRouter()
    router.receive(.upstream, at: 0)
    router.receive(.stopped, at: 1, duration: 2, priority: 100)
    #expect(router.currentEvent(at: 2, preferredEvent: .taskWorking) == .taskWorking)
    #expect(router.currentEvent(at: 5, preferredEvent: .taskWaiting) == .taskWaiting)
    #expect(router.currentEvent(at: 6) == .upstream)
    router.reset()
    #expect(router.currentEvent(at: 7, preferredEvent: .taskWorking) == .taskWorking)
}

@Test func existingSettingsGainDisabledTriggerWithoutLosingPreferences() throws {
    var configuration = PetConfiguration()
    configuration.selectedPet = "builtin.ember"; configuration.paused = true
    configuration.mappings["downstream"] = .failed; configuration.network.interface = "en5"
    var old = try #require(JSONSerialization.jsonObject(with: ConfigurationCodec.encode(configuration)) as? [String: Any])
    old.removeValue(forKey: "codex")
    let migrated = try ConfigurationCodec.decode(JSONSerialization.data(withJSONObject: old))
    #expect(migrated == configuration)
    #expect(!migrated.codex.enabled)
    #expect(migrated.animation(for: .taskWorking) == .laptop)
    #expect(migrated.animation(for: .taskWaiting) == .waiting)
    #expect(migrated.animation(for: .taskCompleted) == .celebration)
}

@Test func readerTailsAppendsAndRecoversFromReplacement() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    let file = root.appendingPathComponent("rollout-test.jsonl")
    try eventLine("task_started", at: now).write(to: file)
    let reader = CodexSessionReader(root: root, monitoringSince: now)
    #expect(try await reader.poll(now: now).event == .taskWorking)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    let complete = try eventLine("task_complete", at: now.addingTimeInterval(1))
    try handle.write(contentsOf: complete.prefix(20))
    #expect(try await reader.poll(now: now.addingTimeInterval(1)).event == .taskWorking)
    try handle.write(contentsOf: complete.dropFirst(20)); try handle.close()
    #expect(try await reader.poll(now: now.addingTimeInterval(1)).event == .taskCompleted)
    #expect(try await reader.poll(now: now.addingTimeInterval(6)).event == nil)
    try eventLine("turn_aborted", at: now.addingTimeInterval(7)).write(to: file, options: .atomic)
    #expect(try await reader.poll(now: now.addingTimeInterval(7)).event == .taskFailed)
    try FileManager.default.removeItem(at: file)
    #expect(try await reader.poll(now: now.addingTimeInterval(12)).monitoredCount == 0)
}

@Test func readerReportsMissingDirectoryAndRecoversWhenItAppears() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let reader = CodexSessionReader(root: root)
    await #expect(throws: CodexSessionReader.ReaderError.self) { try await reader.poll() }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    #expect(try await reader.poll().monitoredCount == 0)
}
