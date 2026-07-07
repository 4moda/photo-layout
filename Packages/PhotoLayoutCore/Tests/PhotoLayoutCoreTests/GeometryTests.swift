import Testing
@testable import PhotoLayoutCore

@Suite("LayoutRect fit/fill")
struct LayoutRectFitFillTests {
    let container = LayoutRect(x: 0, y: 0, width: 400, height: 500) // 4:5

    @Test("fitは全体がコンテナに収まり、アスペクト比を保つ")
    func fitStaysInside() {
        let content = AspectRatio(width: 3, height: 2) // 横長写真
        let fitted = container.fitting(content)
        #expect(container.contains(fitted))
        #expect(abs(fitted.aspectRatio - content.ratio) < 1e-9)
        // 横長コンテンツを縦長コンテナにfit → 幅が一致し上下に余白
        #expect(abs(fitted.width - container.width) < 1e-9)
        #expect(fitted.height < container.height)
    }

    @Test("fillはコンテナを覆い、アスペクト比を保つ")
    func fillCoversContainer() {
        let content = AspectRatio(width: 3, height: 2)
        let filled = container.filling(content)
        #expect(filled.contains(container))
        #expect(abs(filled.aspectRatio - content.ratio) < 1e-9)
        // 横長コンテンツで縦長コンテナをfill → 高さが一致し左右がはみ出す
        #expect(abs(filled.height - container.height) < 1e-9)
        #expect(filled.width > container.width)
    }

    @Test("fit/fillとも中央寄せになる")
    func centered() {
        let content = AspectRatio(width: 1, height: 1)
        for rect in [container.fitting(content), container.filling(content)] {
            #expect(abs(rect.midX - container.midX) < 1e-9)
            #expect(abs(rect.midY - container.midY) < 1e-9)
        }
    }

    @Test("同一アスペクト比ならfit/fillはコンテナと一致する")
    func sameAspectIsIdentity() {
        let content = AspectRatio(width: 4, height: 5)
        #expect(container.fitting(content) == container)
        #expect(container.filling(content) == container)
    }
}
