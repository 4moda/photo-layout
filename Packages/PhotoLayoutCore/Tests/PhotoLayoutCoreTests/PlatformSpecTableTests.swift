import Testing
@testable import PhotoLayoutCore

@Suite("PlatformSpecTable")
struct PlatformSpecTableTests {
    @Test("X 1枚は3:4縦長")
    func xSingle() {
        let aspects = PlatformSpecTable.xPageAspects(photoCount: 1)
        #expect(aspects == [AspectRatio(width: 3, height: 4)])
    }

    @Test("X 2枚は8:9が2つ")
    func xTwo() {
        let aspects = PlatformSpecTable.xPageAspects(photoCount: 2)
        #expect(aspects == Array(repeating: AspectRatio(width: 8, height: 9), count: 2))
    }

    @Test("X 3枚は8:9（左大）+16:9×2（右上下）")
    func xThree() {
        let aspects = PlatformSpecTable.xPageAspects(photoCount: 3)
        #expect(aspects.count == 3)
        #expect(aspects[0] == AspectRatio(width: 8, height: 9))
        #expect(aspects[1] == AspectRatio(width: 16, height: 9))
        #expect(aspects[2] == AspectRatio(width: 16, height: 9))
    }

    @Test("X 4枚は16:9が4つ")
    func xFour() {
        let aspects = PlatformSpecTable.xPageAspects(photoCount: 4)
        #expect(aspects == Array(repeating: AspectRatio(width: 16, height: 9), count: 4))
    }

    @Test("X 範囲外の枚数は空")
    func xOutOfRange() {
        #expect(PlatformSpecTable.xPageAspects(photoCount: 0).isEmpty)
        #expect(PlatformSpecTable.xPageAspects(photoCount: 5).isEmpty)
    }

    @Test("Instagramアスペクト値")
    func instagramAspects() {
        #expect(PlatformSpecTable.instagramAspect(.square).ratio == 1)
        #expect(PlatformSpecTable.instagramAspect(.portrait) == AspectRatio(width: 4, height: 5))
        #expect(abs(PlatformSpecTable.instagramAspect(.landscape).ratio - 1.91) < 1e-9)
    }

    @Test("Instagramカルーセルのページ数は1..20にクランプ")
    func instagramPageCountClamp() {
        #expect(PlatformSpecTable.pageAspects(for: .instagram(aspect: .square, pageCount: 0)).count == 1)
        #expect(PlatformSpecTable.pageAspects(for: .instagram(aspect: .square, pageCount: 25)).count == 20)
        #expect(PlatformSpecTable.pageAspects(for: .instagram(aspect: .portrait, pageCount: 3)).count == 3)
    }
}
