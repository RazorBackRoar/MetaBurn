import Testing
@testable import MetaBurn

@Suite("TaskRunner concurrency")
struct TaskRunnerConcurrencyTests {
    @Test("clean concurrency is at least 2 and never above 4")
    @MainActor
    func boundedCleanConcurrency() {
        #expect(TaskRunner.boundedCleanConcurrency(processorCount: 1) == 2)
        #expect(TaskRunner.boundedCleanConcurrency(processorCount: 2) == 2)
        #expect(TaskRunner.boundedCleanConcurrency(processorCount: 4) == 2)
        #expect(TaskRunner.boundedCleanConcurrency(processorCount: 8) == 4)
        #expect(TaskRunner.boundedCleanConcurrency(processorCount: 16) == 4)
    }
}
