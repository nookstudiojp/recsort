# RecSort iOS 試作版

SwiftUI / PhotoKit / AVFoundation / AVKitで作成したiPhone・iPad向けの試作です。Web版とは別アプリです。App Store・TestFlight配布や実機署名は行っていません。

## 起動

MacとXcode、iOS Simulatorランタイムが必要です。iOS 17以降を対象にしています。今回のビルド環境はXcode 27.2、確認用のシミュレーターはiOS 27.0です。

1. `RecSort.xcodeproj`をXcodeで開く。
2. Schemeを`RecSort`、実行先をiPhoneシミュレーターにする。
3. Runを押す。シミュレーターではAppleアカウントや実機署名は不要です。
4. 右上のライブラリ設定から「サンプル12件」「サンプル1,700件」で操作を試せます。架空データのみです。
5. 写真連携は、シミュレーターの写真へ自分で用意した不要なテスト動画を追加してから、写真へのアクセスを許可します。

コマンドでビルドする場合：

```sh
xcodebuild -project RecSort.xcodeproj -scheme RecSort -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/recsort-ios-build CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build
```

Intel Macでは`ARCHS=arm64`を外すか、実行先に合う設定をXcodeで選びます。UI操作はXcodeのDevice Hub（旧バージョンではSimulator）から行います。

## 実装

- 許可された写真ライブラリの動画を一覧化。許可が維持されていれば、起動のたびに対象動画を一件ずつ選び直す必要はありません。
- フルアクセス／限定アクセス／拒否を扱い、限定アクセスの選択変更を用意。
- 容量順・撮影日順・検索。お気に入りと「残す」は削除対象外。
- 「7日後に見直す」と見直し日の表示。通知や期限後の自動削除はありません。
- 写真の変更通知で一覧を更新。判断はPHAssetの識別子に対応付けてUserDefaultsへ保存。
- 手動の容量確認は同時4件まで。iCloudから自動ダウンロードせず、取得できないものは容量未確認と表示。未確認を0バイト扱いしません。
- 内容確認、同意、アプリの最終確認、必要なiOSの確認を経て写真の削除を依頼。変更やお気に入りを再確認してから実行。
- Nook Studioのクリーム色・濃い文字・ライム色に合わせたカード型UI。写真サムネイルは表示する行で取得し、スクロールアウト時にリクエストを中止します。
- 「その他」から元動画を残した圧縮・コピー書き出し。最大720pまたは540pの圧縮を選び、結果の容量と動画を確認できます。小さくならない動画もあります。
- 確認後にコピーを写真へ追加保存。共有画面からファイルや利用者が選んだ保存先に渡せます。クラウドへの自動転送・転送完了確認は行いません。コピー保存だけでは空き容量は増えません。

容量は公開APIで取得できた元動画URLのファイルサイズです。写真ライブラリ全体の使用量や端末の空き容量を保証しません。取得結果は現在の一覧内で保持し、次回起動時には必要に応じて容量確認をやり直します。iCloudのみの動画や一部の編集済み動画などでは取得できない場合があります。

## 安全と制限

iCloud写真での削除は同期先にも反映されます。iOS側の削除後の保持と空き容量反映はOS・アカウントの状態に依存します。大切な動画で試さないでください。容量を空けるために「最近削除した項目」を自動で空にする機能はありません。

今回はユーザーの希望によりシミュレーターまでを対象とし、実機での動作や1,700件の本物の動画、iCloud同期、配布署名は検証していません。写真連携の実測確認と、1,700件の架空データ表示を区別してください。シミュレーターではテスト動画の再取得・保護・アプリ内確認・iOS側の削除確認まで操作しました。最終ボタンの操作に画面ツールが対応できず、削除完了・復元の確認は残っています。

2026-11-08の新UIはシミュレーターで表示と保護・検索・確認画面を確認し、圧縮と写真へのコピー追加保存を検証しています。新UIと圧縮は開発版で、公開Web版の更新やApp Store公開は含みません。

これまでの結果は[対応状況](../../docs/TEACHER-FEEDBACK.md)に記載しています。

## モデルのテスト

```sh
sh scripts/test-model.sh
```

候補・保護・並べ替え・保存データと、1,700件の架空データを検証します。写真ライブラリや実動画は変更しません。

## ファイル

- `RecSortApp.swift`：画面と確認の導線
- `NookUI.swift`：共通の色・カード・ボタン・写真サムネイル
- `Assets.xcassets`：RecSortの既存アイコンとアプリアイコン
- `VideoExporter.swift`：AVFoundationの書き出し・中止・生成コピーの管理
- `LibraryStore.swift`：PhotoKitの権限・一覧・容量取得・削除依頼
- `VideoRecord.swift`：候補ルールと保護、ソート

Apple公式資料：
- https://developer.apple.com/documentation/photos/phphotolibrary
- https://developer.apple.com/documentation/photos/phassetchangerequest
- https://developer.apple.com/documentation/photos/phimagemanager/requestavasset(forvideo:options:resulthandler:)
