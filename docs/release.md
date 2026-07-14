# リリース（TestFlight / 本番）計画

> 現状は**骨組みのみ**。`.github/workflows/release.yml` は手動実行（`workflow_dispatch`）専用で、
> 実ステップは `if: false` で無効化してある。ここに実装・設定の手順を残す。中身の実装は後日。

## 全体像

```
PR / push(main)         push(main)                 手動 or タグ
    core-tests   ─┐
   ios-ci        ─┴─ 成功 ──▶ Appetize Deploy      Release (TestFlight)
   (テスト・スクショ)         (ブラウザ確認)          (署名ビルド→配布)
```

- **CI（core-tests / ios-ci）**: テストとスクリーンショット。未署名 .ipa（Sideload用）は main のみ。
- **Appetize**: ios-ci 成功後にのみ起動（`workflow_run`）。テストが赤いビルドは上げない。
- **Release**: 署名済みビルドを TestFlight（のちに App Store）へ。**手動トリガ**（誤配信防止）。

## Mac なし開発との関係

CI で署名するには App Store Connect API キーが要る（無料 Apple ID の手動サイドロードとは別物）。
TestFlight 配布には **有料の Apple Developer Program** 登録が前提。ここは登録後に着手する。

## 必要な Secrets（未設定）

| Secret | 用途 |
|---|---|
| `ASC_KEY_ID` | App Store Connect API キーの Key ID |
| `ASC_ISSUER_ID` | 同 Issuer ID |
| `ASC_API_KEY_P8` | 同 秘密鍵（`.p8` の中身。base64 ではなくそのまま） |

署名資産（証明書・provisioning profile）は次のいずれか（後日決定）:
- **fastlane match**（証明書を別リポジトリ/ストレージで共有）
- 手動で証明書 `.p12` と profile を Secrets に入れてインポート

## 実装 TODO（`release.yml` の `if: false` を順に有効化）

1. **署名資産の導入**: match もしくは手動 import。`security import` で一時キーチェーンへ。
2. **Archive**: `xcodebuild archive -scheme PhotoLayout -configuration Release -destination 'generic/platform=iOS' -archivePath build/PhotoLayout.xcarchive`（署名設定を注入）。
3. **Export**: `ExportOptions.plist`（`method: app-store-connect`）を用意し `-exportArchive`。
4. **Upload**: App Store Connect API キーで TestFlight へ（`xcrun altool --upload-app` または fastlane `pilot`）。
5. **バージョニング**: `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` の採番方針（タグ連動 or run number）を決める。
6. **トリガ**: 手動に加え、`v*` タグ push で走らせるか検討。

## メモ

- ビルドツールチェーンは CI と揃える（Xcode 26.6 / `DEVELOPER_DIR` 固定）。
- 署名まわりの秘密情報はログに出さない（`::add-mask::` / 環境変数経由）。
- Info.plist は XcodeGen 生成物（`project.yml` の `info:` 由来）。バンドルIDは `com.fourmoda.photolayout`。
