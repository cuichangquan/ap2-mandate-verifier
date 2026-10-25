# Docker再利用：小さく確認してから本試験へ

この手順は今回の失敗から得た再利用条件です。将来の実行・取得・exec設定変更・
rerun・費用・本番への包括承認ではありません。次回も対象と回数・上限・異常終了方針を
一括してOwner承認し、新領域・固有ID・開始時刻・絶対期限を記録します。
Macに直接導入せずDockerを優先し、既存共有資源には触りません。

1. **準備**：固定image digest、arm64/OS、保存Gem/input/product/sourceのSHAを再確認。
   足りなければ取得やsource buildへ勝手に切替えずSTOP。検証済み部品をコピーし、
   実行用新領域の`run_supervised.py`/`stream_results.py`、読み取り専用`supervision/`
   のRuby3補助、`source/research/host_commit_reconcile_subset/`、`product/`、
   `archives/`、`PUBLIC_INPUTS.json`と正確な文書欠落goldenを用意します。
   専用attempt label・新しい承認記録は保存し、旧コードの期待値/pinを通すために緩めません。
2. **実行領域の診断**：設定要求だけでなく、実mountinfo、uid/gid、所有権/権限、
   compiler位置、CPU/RAM/swapとroot read-onlyを保存。専用Gem tmpfsでnative生成物を
   実行/ロードする必要を先に確認します。noexecなら導入前HOLD。今回のexec許可は
   Gem tmpfsだけでnosuid/nodevを維持したもの。他領域やOSの保護を広く変更しません。
3. **小転送を先に確認**：別途承認された回数で、同じ共有`transfer()`とRuby exporterを
   使う既知小ファイルのtmpfs転送を通します。内容/サイズ/SHA/host読戻し、必須一覧、
   意図的不在の記録、exporter exit/終端を確認。本試験を回収テストの代わりにしません。
   D2の23B成功は小転送の証拠で、全障害・大容量試験ではありません。
4. **provider/導入**：公式の版番号だけで判断せず、実ロードnative/libcrypto/libpqの
   経路・hash、所有package完全版と整合性を確認。373文書欠落は正確な診断goldenとの
   byte一致だけを認め、実ライブラリ/設定差分・別の欠落・未知エラーを除外しません。
   pg binaryのhash/ABIを固定しsource fallback禁止。JSON buildは許可された1回/180秒だけ。
5. **本試験**：独立期待表、固定入力、信頼前提と非対象を固定し、許可された1batchだけ。
   worker PID/PGID・終了code・DB session消失を記録し、失敗/timeout/不明でSTOP。
   失敗後の修正再試行には新しい承認が必要です。ダミーと本試験の枠を混同しません。
6. **証拠を先に保存**：段階別のstdout/stderr/exit、mount/provider情報、install所有groupと
   回収、mkmf.log/gem_make.out、BATCH/REPORT/SUPERVISION、worker trace、第三接続全行hashを
   必須一覧と照合。不在は未開始/optional/未証明を区別。空の結果フォルダーは成功ではありません。
   tmpfsには`docker cp`を使わず、固定対象のコンテナ内ストリームを使用します。
   remote一覧・サイズ・SHAをpayloadより先に保存し、hostで同じbytesを読戻して確認します。
   partial/非0/終端なし/必須欠落は保全失敗です。
7. **清掃**：証拠完全性を確認してから、今回の所有ID/labelのcontainer/tmpfs/networkだけを
   終了・削除し残存確認。base image/cache/旧証拠を保持し、汎用pruneは使いません。
   tmpfsはstopでも消えるため、単に停止してあとでログを取る案は不可です。
   今回のOwner承認は、回収不能時に取得済み証拠と欠落理由を保存したうえで期限内に
   今回資源を終了・削除する方針。これはEVIDENCE_INCOMPLETEであり通常成功ではありません。
   次回もこの方針を勝手に継承せず、無期限残置か無断ログ破棄かの二択を実行後に作らないよう
   開始前に終了方針を承認します。

**時間・容量**：全工程20分のうち回収/清掃用180秒を予約し、通常処理を早めに止めます。
容量制限tmpfsはRAMに算入、swap0を確認。host出力64MiB・ファイル数/個別/総転送上限と
ログ回転を維持。8GiBは追加使用量の観測停止予算であり、Docker VM全体/物理増分の
厳密な強制・全期間peak保証・削除後の縮小を約束しません。観測不能/超過はSTOP。

**残る限界**：固定合成入力/時計・信頼するRuby/DB/controllerの限定研究です。
実Issuer・認証/実時計/失効、TCP/DB protocol ACK喪失、crash耐久性、一般並行性能、
外部決済の冪等性、本番GOは別の判断・証明が必要です。

公式資料：[tmpfsの寿命/メモリ](https://docs.docker.com/engine/storage/tmpfs/)、
[docker cpのtmpfs制限](https://docs.docker.com/reference/cli/docker/container/cp/#corner-cases)。
