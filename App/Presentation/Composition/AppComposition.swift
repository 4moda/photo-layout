import SwiftUI

/// DIコンポジションルート。Infrastructureの具象実装をUseCaseへ、UseCaseをViewModelへ
/// 結線するのはこのファイルだけ（Clean Architectureの"main"に相当）。
enum AppComposition {
    @MainActor
    static func makeRootView() -> some View {
        RootView()
    }
}
