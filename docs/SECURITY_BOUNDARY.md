# Security Boundary — 研究時点のチェックリスト

> Draft / 2026-10-11。ここに書かれた条件は設計候補であり、実装済み・安全性保証を意味しない。

## 信頼境界

```text
Untrusted Agent/Mandate input
  -> format/size limits
  -> cryptographic signature + disclosure validation
  -> trusted issuer/key selection (host policy)
  -> presenter/Agent key binding and audience/nonce/time
  -> mandate chain / constraints / checkout transaction binding
  -> VERIFIED EVIDENCE (NOT an authorization decision)
  -> host account/business authorization, anti-replay and payment controls
  -> execute OR fail closed
```

## 守るべき性質

- Agentの自己宣言、未信頼Issuer/鍵、外部のPrincipal IDをそのまま承認しない。
- 署名成功だけを業務のALLOWやUser本人の同意の証明として扱わない。
- 検証する範囲がMandateの形式・委任チェーン・Agent鍵・aud/nonce/期限・制約・取引内容に及ぶか調査する。
- 不明な制約、未開示の必要情報、形式不正、期限外、対応しない仕様版はFail Closed。
- 柔軟な委任でも途中Hopで権限拡大を許さない。
- 取引対象、Merchant、金額、通貨、Checkoutの署名・hashの一貫性を確認する。
- Replay/二重課金、失効、残予算のような状態管理がLibraryかHostかを明確化。
- Mandate原文・鍵・機微な識別情報をログへ出さない。
- 仕様で定義されない仮の検証条件を「公式準拠」と誤表示しない。

## 実装GO前に決めること

1. どのIssuerがどの鍵を使って何を証明できるか、誰が信頼を決めるか。
2. 失効・Proof of Possession・Audience/Nonce・リプレイ防止の境界。
3. 正しくVerifiedと判定された証拠をHostへ返す最小API。
4. 正例・負例・境界値と、公式Python SDKとの相互運用手順。

これらの詳細を決めるまでは暗号化・署名検証コードを急いで書かない。
