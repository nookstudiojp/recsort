# 提出用パッケージとREADMEの確認結果

> この文書は学校提出版v0.3.3の記録です。現行版の追加機能は[更新内容と検証範囲](RELEASE-v0.4.0.md)を参照してください。

2026年11月6日、このMac上で確認しました。

## GitHubから取得したコードの確認

- GitHubのmainブランチをZIPで取得し、そのコードから実行しました。
- `node test-core.mjs`：13アサーションが成功。
- `node test-decisions.mjs`：11アサーションが成功。合計24です。
- 当初のcore側ログに「12」と表示する誤記がありましたが、実際のassert呼び出しは13件でした。ログと資料の件数を訂正しました。判定処理やテスト条件は変更していません。
- Python 3.12.14でstart.pyを提出フォルダ以外の場所から起動し、http://127.0.0.1:8765 がHTTP 200でRecSortを返すことを確認。ESモジュールのContent-TypeもJavaScriptでした。確認後サーバーを終了しました。

## URL・配信ファイル

以下を実際のHTTPS GETで確認しました。ブラウザ上でも公開デモの画面表示を確認しました。

| URLまたはファイル | 結果 |
| --- | --- |
| https://recsort-studio.alikemerit.chatgpt.site/ | HTTP 200、アプリのHTML |
| https://www.python.org/downloads/ | HTTP 200、Python公式ダウンロードページ |
| https://github.com/nookstudiojp/recsort/blob/main/docs/RecSort-slides.pdf | HTTP 200。取得したソースZIP内のPDFも確認 |
| https://codeload.github.com/nookstudiojp/recsort/zip/refs/heads/main | HTTP 200、解凍可能なZIP |
| start.py、docs/DESIGN.md、docs/VERIFICATION.md | リポジトリ内の存在を確認 |
| dist/RecSort-desktop-v0.1.zip | 存在と解凍可能な形式を確認。専用READMEとソース、依存定義を収録 |

公開デモのapp.js、core.mjs、decisions.mjs、style.css、light.css、アイコン、デスクトップZIPをHTTP 200で取得し、GitHub版と一致することを確認しました。公開HTMLには配信サービス側のCloudflareスクリプトが追加されているため、そのままのバイト比較では一致しません。

上記はロジック・配信・URLの確認です。Windows実機・iPhone実機・全形式の動画再生・大量実動画の動作を保証するものではありません。ブラウザ操作の手動確認手順はREADMEに記載しています。
