# Project — 目的・責務・決定事項

更新日：2026-10-11

## 1. 背景

各個人が分身AI（Personal AI）を持ち、多数のサービスを代理利用する将来、Userがすべてのサービスで事前に個別のAgent権限設定を行う方式だけでは限界がある可能性がある。

Agentの「このUserから購入権限を与えられた」という**自己申告**ではなく、Userが信頼できる方法で発行した**外部委任証明**を、サービス側が検証する方式を研究する。

**検証可能性と受け入れるべき信頼は別問題。** 署名が正しくても、サービスは発行元の信頼性、対象User、Agentの鍵、委任の範囲、取引内容、自サービスの規則を確認する必要がある。

## 2. 目指すもの

- Ruby汎用の、AP2 v0.2 Mandateを検証する最小ライブラリの実現可能性調査。
- 最初の対象はMerchant側の**Checkout Mandate Verifier**。
- 仕様のMUSTを明確にし、公式Python SDKとの相互運用で正例・負例を検証する。
- Railsへの依存は持たせない。ActingForとは別プロジェクトとして進める。
- 認証・決済・業務実行・外部Agentの自己宣言の無条件受理はしない。

## 3. 信頼境界

```text
User ── trusted approval ──► Personal AI
                                    |
                            untrusted Mandate
                                    v
                              Ruby Host Service
                                    |
                              AP2 Verifier候補
                  issuer/key / signature / agent binding
                  audience / expiry / constraints / checkout binding
                                    |
                              Verified Evidence
                              (not an ALLOW)
                                    |
                          Host authorization/policy
                                    |
                              Execute or STOP
```

Verifier側で何を保証できるかと、Host側が行う発行者信頼ポリシー・User解決・事業ルール・二重決済防止・失効管理などを分離する。

## 4. 非スコープ

AP2全部入りSDK、ウォレット、鍵発行、OAuth Server、MCP/A2A Server、Agent自体、決済実行、ActingFor Core/Shopping Demoの拡張。

## 5. 独立した関連OSS

| Project | Responsibility |
| --- | --- |
| `ap2-mandate-verifier` | 外部AP2 Mandateの検証（本プロジェクト） |
| [ActingFor](https://github.com/cuichangquan/acting_for) | Rails内部のDelegationに基づく代理認可・Audit |
| [a2a-rails](https://github.com/cuichangquan/a2a-rails) | RailsとA2A Agent間の通信 |

## 6. 研究開始時の決定

- D001: リポジトリ `ap2-mandate-verifier` は独立OSS。Gem名 / Namespace / RubyGems公開日は未決定。
- D002: AP2 **v0.2** / **Checkout Mandate** を初期スコープとして研究。
- D003: 暗号学的検証は最終業務認可ではない。Hostのポリシー適用が必須。
- D004: fail-closedを原則とする。未知の署名アルゴリズム・Constraint・不十分な証明は許可に丸めない。
- D005: 公式仕様・SDK照合・相互運用・セキュリティ負例を検証してから実装と公開のGO/NO-GOを判定。
- D006: ActingForとa2a-railsのCore/API/Schemaはこの研究段階では変更しない。

## 7. 現在の進捗・次の作業（2026-10-11）

P0-1〜P0-5b、P1-0〜P1-7までの研究を進めた。固定AP2 v0.2公式Python SDK由来の限定Ruby研究PoCは、Issuer Root→Agent 2hop→Merchant署名Checkoutの検証、P1-5の6 REDの発見、P1-6の研究修正で**同じ18観測に対して17 GREEN/0 RED/Host Replay境界1**と43件回帰成功を記録済み（[P1-6証拠](SECURITY_HARDENING_RESEARCH.md)）。

**P1-7（今回・文書設計のみ）:** [HOST_SECURITY_CONTRACT](HOST_SECURITY_CONTRACT.md)と[HOST_SECURITY_TEST_PLAN](HOST_SECURITY_TEST_PLAN.md)で、Host登録Issuer/Merchant/Agentの鍵・Buyer資格、Checkout正本、VerifiedEvidenceと購入ALLOWの境界、nonce消費と注文操作の原子的な整合性、失効・Clock・Receipt/障害対応を明確化した。Host trust/Replay/Receiptの**将来テスト34件は全件未実行**。新Rubyコード/CI/DB/実決済は一切追加していない。

**最新判断:** [RESEARCH_DECISION](RESEARCH_DECISION.md) §17 — 非本番の研究/設計のみCONDITIONAL GO、**汎用Ruby Gem/API実装HOLD、公開・実決済・Production NO-GO**。次の1件（別途承認後のみ）は**P1-8：ローカルDBによるHost nonce/Checkout競合を検証するためのテスト実施設計・採用判断**。本StepでGem実装・Host DB実装・クラウドへは進まない。
