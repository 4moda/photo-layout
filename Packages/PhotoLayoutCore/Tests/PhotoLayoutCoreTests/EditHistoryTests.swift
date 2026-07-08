import Testing
@testable import PhotoLayoutCore

@Suite("EditHistory（undo/redo）")
struct EditHistoryTests {
    private func project(title: String) -> ProjectEntity {
        ProjectEntity(title: title)
    }

    @Test("undo→redoの往復")
    func undoRedoRoundTrip() {
        var history = EditHistory()
        let v1 = project(title: "v1")
        let v2 = project(title: "v2")

        history.push(v1)                    // v1 → v2 に変更する直前
        #expect(history.canUndo)
        #expect(!history.canRedo)

        let undone = history.undo(current: v2)
        #expect(undone?.title == "v1")
        #expect(history.canRedo)

        let redone = history.redo(current: undone!)
        #expect(redone?.title == "v2")
        #expect(history.canUndo)
        #expect(!history.canRedo)
    }

    @Test("undo後に新しい操作をpushするとredo履歴は破棄される")
    func pushClearsRedo() {
        var history = EditHistory()
        let v1 = project(title: "v1")
        let v2 = project(title: "v2")
        history.push(v1)
        _ = history.undo(current: v2)
        #expect(history.canRedo)

        history.push(v1) // 分岐する新操作
        #expect(!history.canRedo)
    }

    @Test("履歴上限を超えると古いものから捨てられる")
    func limitDropsOldest() {
        var history = EditHistory(limit: 2)
        history.push(project(title: "a"))
        history.push(project(title: "b"))
        history.push(project(title: "c"))
        #expect(history.undo(current: project(title: "d"))?.title == "c")
        #expect(history.undo(current: project(title: "c"))?.title == "b")
        #expect(history.undo(current: project(title: "b")) == nil) // "a"は落ちている
    }

    @Test("空の履歴ではundo/redoともnil")
    func emptyHistory() {
        var history = EditHistory()
        #expect(history.undo(current: project(title: "x")) == nil)
        #expect(history.redo(current: project(title: "x")) == nil)
        #expect(!history.canUndo)
        #expect(!history.canRedo)
    }
}
