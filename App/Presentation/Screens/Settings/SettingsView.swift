import SwiftUI

/// iOSの「設定」アプリのようなグループ化リスト形式。サインイン等のアカウント関連UIは
/// 持たない（#64で将来追加検討・本Issueの対象外）。通信も行わない。
struct SettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Text("プライバシーポリシー")
                }
                .accessibilityIdentifier("settings.privacyPolicy")

                NavigationLink {
                    TermsOfServiceView()
                } label: {
                    Text("利用規約")
                }
                .accessibilityIdentifier("settings.terms")
            }

            Section {
                HStack {
                    Text("バージョン")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("settings.version")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}
