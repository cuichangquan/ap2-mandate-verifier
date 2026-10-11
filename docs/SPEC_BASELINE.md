# AP2 v0.2 Specification Baseline — Phase 0 / P0-1

**確認日:** 2026-10-11 (JST)  
**状態:** P0-1 の参照基準確定（調査のみ）。Verifier要件確定・Gem実装・テスト実行・適合性認定は **未実施**。  
**対象:** AP2 v0.2 / Checkout Mandate / Merchant（受信側Verifier）の調査。Payment Mandateは関連参照に留める。

> **重要:** 以下の「AP2仕様リリース v0.2.0」「仕様文書内の v0.2」「Python配布メタデータの `version = "0.1"`」「Mandateの `vct` 末尾 `.1`」は**異なるバージョン体系**。相互に置き換えない。

## 1. 再現可能な基準点

| 項目 | 固定値 / 確認事項 | 根拠 |
| --- | --- | --- |
| 公式リポジトリ | `google-agentic-commerce/AP2` | [AP2 repository](https://github.com/google-agentic-commerce/AP2) |
| **採用する公式リリース** | **`v0.2.0`**（2026-04-28 公開。「Human Not Present flows」が主眼） | [GitHub Release](https://github.com/google-agentic-commerce/AP2/releases/tag/v0.2.0) |
| **公式Tagの解決先Commit** | **`b4587ac1d055888a73b4b21750973cffba961793`**（軽量tag → commit。リリースCommitのGitHub署名 verified） | [tag ref](https://api.github.com/repos/google-agentic-commerce/AP2/git/ref/tags/v0.2.0) / [fixed commit](https://github.com/google-agentic-commerce/AP2/commit/b4587ac1d055888a73b4b21750973cffba961793) |
| 仕様書本文の表記 | `Agentic Payment Protocol (v0.2)` | [固定Specification](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md) |
| Python SDK **ソースの基準Commit** | **同じ `b4587ac1d055888a73b4b21750973cffba961793`**。SDK独自のリリース番号・独立Commitではなく、モノレポのtagで同時固定 | [固定SDK](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk) |
| Python package metadata | root `pyproject.toml`: `name = "ap2"`, **`version = "0.1"`**, `requires-python = ">=3.11"`。**PyPI公開バージョンやv0.2対応を示す別の配布タグだとは判断しない** | [固定pyproject.toml](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/pyproject.toml) |
| 確認時点の上流main | `e1ea56db72a6385bce3e5c1112b3a56ce60acb43`。tagより4 commits先だが、差分は `CHANGELOG.md`, `CONTRIBUTING.md`, `README.md`, `uv.lock` のみ。**対象3仕様書・SDK Pythonコード・pyproject.tomlはtagと同一** | [比較](https://github.com/google-agentic-commerce/AP2/compare/v0.2.0...e1ea56db72a6385bce3e5c1112b3a56ce60acb43) |
| 本リポジトリ作業前main | `1d7408a9c43b2638b416853f8f4dea6e3d8f6396`。作業開始時Open Issue: 0 / Open PR: 0 | [本リポジトリmain](https://github.com/cuichangquan/ap2-mandate-verifier/tree/main) |

**採用ルール:** 仕様解釈と将来の相互運用試験は、まず `v0.2.0` の固定Commitを基準とする。公開Web版（`ap2-protocol.org`）と `main` は変更可能な参照先であり、差分が生じたら別記する。SDKの実挙動をそのまま規範的なMUSTとみなさない。

## 2. 固定した一次仕様（同一Commit）

| 資料 | 仕様で確認できる調査起点 | 固定リンク |
| --- | --- | --- |
| **Specification** | v0.2、役割とMerchantの検証責務、Checkout Mandate、Mandate Versioning、Human Present / Human Not Present | [docs/ap2/specification.md](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md) |
| **Agent Authorization** | Mandate Delegation、User Credential / Trusted Agent Provider、SD-JWT VC、**Verification and Processing Rules**、Action Authorization | [docs/ap2/agent_authorization.md](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md) |
| **Checkout Mandate** | **`mandate.checkout.1` / `mandate.checkout.open.1`**、Checkout JWT・`checkout_hash`、制約、Receipt、open/closed例 | [docs/ap2/checkout_mandate.md](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md) |

主な該当箇所（**P0-2の網羅的な要件抽出ではない**）:

- [Specification — Mandate Versioning](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#mandate-versioning): `vct` は数値suffixを含めて完全一致が必要。
- [Specification — Verification / Merchant](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/specification.md#merchant): MerchantはCheckout Mandate、checkout JWTとのhash一致、必要なopen Mandate制約を検証する。
- [Agent Authorization — Verification and Processing Rules](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/agent_authorization.md#verification-and-processing-rules): SD-JWT委任チェーン、open→closedの値・制約の評価。unknown constraintsは失敗扱い。
- [Checkout Mandate — Type / Mandate Schema](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/docs/ap2/checkout_mandate.md#type): `vct`、`checkout_jwt`、`checkout_hash`とその表現。なお**Type節とSchema表の説明文に版suffixの不整合**があり、Type節およびSpecificationの明示ルールを混同しない（[#322](https://github.com/google-agentic-commerce/AP2/issues/322)）。

公開Web表示（**可変URL・参考用**）: [Specification](https://ap2-protocol.org/ap2/specification/) / [Agent Authorization](https://ap2-protocol.org/ap2/agent_authorization/) / [Checkout Mandate](https://ap2-protocol.org/ap2/checkout_mandate/)。

## 3. 公式Python SDKの固定点

- **リポジトリTag/Commit:** AP2 `v0.2.0` / `b4587ac1d055888a73b4b21750973cffba961793`。package自体の `version = "0.1"` はそのまま併記し、**「Python SDK v0.2.0」等と断定しない**。
- **package source:** [`code/sdk/python/ap2`](https://github.com/google-agentic-commerce/AP2/tree/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2)、[SDK README](https://github.com/google-agentic-commerce/AP2/blob/b4587ac1d055888a73b4b21750973cffba961793/code/sdk/python/ap2/sdk/README.md)。
- **確認した主要入口（ソース・README記述）:** `ap2.sdk.mandate.MandateClient`（create/present/verify）、`ap2.sdk.sdjwt.chain.verify_chain`、`ap2.sdk.checkout_mandate_chain.CheckoutMandateChain`、`ap2.sdk.sdjwt.kb_sd_jwt`、`ap2.sdk.constraints`、`ap2.sdk.receipt_wrapper`。
- **後続の照合点:** issuer鍵の選択、terminal hopのaud/nonce、開示を伴うチェーン、Checkout JWT hash、制約評価を**仕様とテストの両方**で確認する。READMEのAPI説明は検証済み相互運用結果ではない。
- **実行状況:** Python SDKのインストール、テスト、サンプル通信、Ruby相互運用は**未実施**。依存関係は固定`pyproject.toml`参照。PyPI配布物のハッシュ・公開状況は**未確認**。

## 4. v0.1との境界

- [AP2 `v0.1.0`](https://github.com/google-agentic-commerce/AP2/releases/tag/v0.1.0) → `bb57b6bfdb9a1caafffe7d024ca04d99cefa40be`（2025-09-16公開）。
- [AP2 `v0.2.0`](https://github.com/google-agentic-commerce/AP2/releases/tag/v0.2.0) → `b4587ac1d055888a73b4b21750973cffba961793`（2026-04-28公開）。公式リリース説明は **Human Not Present flows** に焦点を置く。v0.2で上記3文書とSDKの現行構成が導入されたことは[tag比較](https://github.com/google-agentic-commerce/AP2/compare/v0.1.0...v0.2.0)で確認した。
- 今後の仕様・fixture・APIの判断にv0.1のデータ構造や主張を混在させない。**AP2仕様v0.2 ≠ Checkout vct suffix `.2`**。Checkoutはv0.2仕様内でも `mandate.checkout.1` / `mandate.checkout.open.1`。

## 5. 未確定事項・リスク（2026-10-11時点）

| 状態 | 論点 | リスク・後続アクション |
| --- | --- | --- |
| **Open upstream Issue** | [#319 — terminal KB-SD-JWTのaud/nonce](https://github.com/google-agentic-commerce/AP2/issues/319) | デフォルト呼び出しのclaim欠落許容という報告。発行時の前提と検証時の強制範囲が違う可能性。**報告を既に実証済みの脆弱性とみなさない**。P0-2/P0-3で一次条文・テスト確認。 |
| **Open upstream Issue** | [#358 — Closed Checkoutのcheckout_hash結合](https://github.com/google-agentic-commerce/AP2/issues/358) | `CheckoutMandateChain.verify` の任意引数を省略すると入力JWTのhashを独立計算しないという報告。Merchantの検証義務とSDKのデフォルト実装を同一視しない。 |
| **Open upstream Issue** | [#339 — 非開示Constraint / budget単位](https://github.com/google-agentic-commerce/AP2/issues/339) | 選択的開示で必要制約が見えず、空の違反リストが承認に誤変換される可能性。どの制約が存在すべきかのHost側情報・失敗条件は未確定。 |
| **Open upstream Issue** | [#322 — `vct` suffixの記述不一致](https://github.com/google-agentic-commerce/AP2/issues/322) | 説明文と仕様の完全一致ルールの食い違い。**prefix一致やsuffixなし受理を正当化しない**。 |
| **Open upstream Issue / 初期スコープ外** | [#346 — Payment Mandateの再利用](https://github.com/google-agentic-commerce/AP2/issues/346) | Payment側の二重実行防止は独立の状態管理上の論点。Checkout Verifierだけでreplay防止済みと主張しない。 |
| **要調査** | Issuer / Trusted Surface / Agent鍵・委任の信頼起点 | 仕様の署名妥当性とHostが採用する発行者/ユーザー/取引の信用は別。どの識別子と鍵を誰が設定するかP0-2で仕分け。 |
| **要調査** | 署名鍵選択、失効、nonce・aud・期限、replay、Open/Closed、merchant JWTの信頼・制約・Receipt | **MUST/SHOULD/未規定/Host責務**とデータフローをP0-2で節・行番号付きで整理。安全な実装保証は未成立。 |
| **未確認** | PyPI実配布版、独立SDK release、実行可能な正負fixture、仕様とSDKの相互運用 | 「GitHub v0.2.0 tagに同梱されるPython source」だけを固定。配布の整合性と挙動はP0-3以降で調べる。 |
| **継続監視** | 公式仕様 / SDK / 上流Issueの後続変更 | frozen baselineと新しいCommitを比較。mainの状態、IssueのOpen/Closedは**確認日現在のスナップショット**。 |

これらは**調査すべきリスク**であり、Ruby Gemに既知の脆弱性がある、AP2全体が危険、またはPython SDKの各報告が独立に再現確認済み、という意味ではない。

## 6. P0-1 完了範囲と次のGate

- [x] 公式仕様の版・tag・完全Commit SHAを特定。
- [x] Specification / Agent Authorization / Checkout Mandateを同一Commitの固定URLに統一。
- [x] Python SDKの所在・Commit・`pyproject.toml`のpackage versionを区別して記録。
- [x] v0.1との境界、上流の未解決論点、追加確認が必要な範囲を明示。
- [ ] Verifierの全MUST/SHOULD・Host責務の確定（**P0-2**）。
- [ ] Python SDKとRubyの実行・相互運用、Gem設計・実装（今回対象外）。

**次の重要タスクは1つだけ:** **P0-2 — `docs/VERIFIER_REQUIREMENTS.md` にCheckout Mandate VerifierのMUST/SHOULD、Fail Closed、Host責務を仕様節ごとに整理する。** それ以前に実装しない。
