# AP2公式情報・標準化ウォッチリスト

確認基準日：**2026-10-11**。リンク先は更新されるため、Gem実装の際は**対象バージョン、公式Commit SHA、確認日時**を必ず記録する。

## 1. 最優先 — AP2一次資料

| 重要度 | 資料 | 確認するポイント |
| --- | --- | --- |
| ★★★ | [AP2 v0.2 Specification](https://ap2-protocol.org/ap2/specification/) | 仕様版、Roles、Mandates、Verifierの必須契約 |
| ★★★ | [Agent Authorization](https://ap2-protocol.org/ap2/agent_authorization/) | 委任チェーン、検証とAction Authorization、Issuer/Agent binding、制約 |
| ★★★ | [Checkout Mandate](https://ap2-protocol.org/ap2/checkout_mandate/) | Open/Closed Checkout、Merchant署名、checkout_hash、制約 |
| ★★★ | [Official AP2 GitHub](https://github.com/google-agentic-commerce/AP2) | 公式実装、タグ、PR、Issue、変更履歴、ライセンス |
| ★★★ | [Official Python SDK folder](https://github.com/google-agentic-commerce/AP2/tree/main/code/sdk/python/ap2) | 検証API、対象フォーマット、公式の正負テスト |
| ★★ | [Payment Mandate](https://ap2-protocol.org/ap2/payment_mandate/) | 将来用。初期のCheckout検証に混ぜない |
| ★★ | [GitHub issues](https://github.com/google-agentic-commerce/AP2/issues) | verifierに影響する未決定点・不具合 |
| ★★ | [GitHub pull requests](https://github.com/google-agentic-commerce/AP2/pulls) | 将来の互換性破壊・仕様変更を確認 |

## 2. 関連する正式規格・標準化

| 資料 | 関連性 |
| --- | --- |
| [IETF RFC 9901 — Selective Disclosure for JWTs (SD-JWT)](https://www.rfc-editor.org/rfc/rfc9901.html) | 選択的開示の暗号学的土台（正式RFC） |
| [SD-JWT VC draft](https://datatracker.ietf.org/doc/draft-ietf-oauth-sd-jwt-vc/) | VC表現。最終的な標準状態を必ず確認 |
| [FIDO Alliance — Agentic AI](https://fidoalliance.org/fido-alliance-agentic-ai/) | Agentが人の代理として行う操作の標準化 |
| [FIDO — trusted AI agents announcement](https://fidoalliance.org/fido-alliance-to-develop-standards-for-trusted-ai-agent-interactions/) | 2026年の標準化方向。完成した規格と混同しない |
| [IETF OAuth Token Exchange RFC 8693](https://www.rfc-editor.org/rfc/rfc8693.html) | 既存の委任主体・Actor表現の参考 |
| [IETF OAuth RAR RFC 9396](https://www.rfc-editor.org/rfc/rfc9396.html) | 対象操作と細かな認可条件の表現 |

## 3. 特に確認する上流論点（Issue番号は状態を再調査）

- [AP2 #319 — aud/nonce in KB-SD-JWT](https://github.com/google-agentic-commerce/AP2/issues/319)
- [AP2 #358 — Closed Checkout binding](https://github.com/google-agentic-commerce/AP2/issues/358)
- [AP2 #339 — undisclosed constraints](https://github.com/google-agentic-commerce/AP2/issues/339)
- [AP2 #322 — vct version suffix](https://github.com/google-agentic-commerce/AP2/issues/322)
- [AP2 #346 — Payment Mandate reuse](https://github.com/google-agentic-commerce/AP2/issues/346)（初期スコープ外）

これらは上流課題の確認先。**修正済みかどうか・現行仕様に該当するかの再確認が必要**であり、本プロジェクトに既知の脆弱性があるという意味ではない。

## 4. 追跡手順（推奨：月1回、実装前、リリース前）

1. AP2の最新Release/Tag、Agent Authorization、Checkout Mandate、公式SDKの差分を確認。
2. 変更をBreaking / Compatible / Informationalに分類し、どのテストに影響するか記録。
3. FIDO/IETFの提案段階と正式標準を区別する。
4. RubyGems・GitHubで競合・再利用可能なRuby Gemを再調査。
5. GitHub Issueに必要な事実のみ記録し、Core実装の自動変更はしない。

## 5. 注意点

- **AP2 v0.1をv0.2と混同しない。**
- GoogleのPython SDKが示す動作が正式仕様のMUSTと違う場合、勝手に仕様を変更しない。
- 信頼できるIssuer、鍵管理、unknown constraintの扱いはセキュリティ境界。規格の変更をGitHubのmainリンクだけで追いかけず、Commit SHAで固定してテストする。
