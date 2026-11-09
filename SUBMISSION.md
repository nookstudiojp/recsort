# RecSort 提出案内

2026年11月9日。当日は本人による説明と、公開Web版のサンプル実演で発表します。

## 共有するものと、その目的

| 共有物 | 内容・確認していただきたい点 |
| --- | --- |
| [当日改訂版スライドPDF](docs/RecSort-slides.pdf) | 本編6枚＋補足4枚。想定利用者の悩みと機能のつながり、技術構成、実装と今後の調査が伝わるか |
| [公開Web版](https://recsort-studio.alikemerit.chatgpt.site/) | 「サンプルでお試し」から、容量順の一覧、候補理由、「残す」の保護、確認画面を操作できるか |
| [Webソース](dist/)と[ローカル起動手順](docs/LOCAL_SETUP.md) | 画面・判定・保存・確認の実装と、手元で起動する方法 |
| [iPhone試作のソースと起動手順](native/RecSort-iOS/README.md) | 写真連携と圧縮・コピー保存の実装、Simulatorでの確認範囲 |

[PDFを直接ダウンロード](https://github.com/nookstudiojp/recsort/raw/refs/heads/main/docs/RecSort-slides.pdf)して、PDFアプリで表示することもできます。

## 資料を読む順番

1. スライド1〜3：課題、利用者と悩みの仮説、機能との対応。
2. スライド4：公開サイトへ切り替え、サンプル実演。
3. スライド5〜6：技術・開発工程、制限と次の顧客確認。
4. 質問に応じてスライド7〜10、[FAQ](docs/FAQ.md)、[検証記録](docs/VERIFICATION.md)を参照。

## 実装と調査の範囲

公開サイトはWeb v0.5.0です。GitHubにはWeb v0.6.0開発版とiPhone試作も含み、公開サイトへの反映やiPhone版の一般配布はまだ行っていません。

体系的な顧客ヒアリングは未実施です。[顧客像と悩み](docs/CUSTOMER-HYPOTHESES.md)は仮説として記載し、いただいた質問・感想と分けています。実機・大量実動画・削除完了と復元などの未検証項目も、資料内で明記しています。

紹介動画は記録・参考用として保持し、当日の説明は本人が行います。

[READMEの入口へ戻る](README.md)
