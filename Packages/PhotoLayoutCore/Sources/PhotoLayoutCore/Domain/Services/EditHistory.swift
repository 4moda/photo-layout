/// ProjectEntityスナップショットによるundo/redo履歴。
/// エンティティは値型（struct）なのでスナップショット保存は安全かつ軽量。
/// 「操作の確定前」の状態をpushする使い方（ジェスチャ中の中間状態は積まない）。
public struct EditHistory: Sendable {
    private var undoStack: [ProjectEntity] = []
    private var redoStack: [ProjectEntity] = []
    private let limit: Int

    public init(limit: Int = 50) {
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// 操作の確定直前の状態を積む。新しい操作が入ったのでredo履歴は破棄する
    public mutating func push(_ snapshot: ProjectEntity) {
        undoStack.append(snapshot)
        if undoStack.count > limit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    /// 直前の状態へ戻す。現在状態はredoスタックへ移す
    public mutating func undo(current: ProjectEntity) -> ProjectEntity? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    /// 戻した操作をやり直す。現在状態はundoスタックへ移す
    public mutating func redo(current: ProjectEntity) -> ProjectEntity? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }
}
