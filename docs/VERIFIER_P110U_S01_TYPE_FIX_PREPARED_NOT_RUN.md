# P1-10u — S01 signed Requirement.id 型検証の限定修正（Docker実測済み・限定GREEN）

**2026-10-12 JST — Fixed synthetic Issuer研究のみ / Mac DockerのP1-10u専用2件: 2 runs / 12 assertions / 失敗0 / GitHub Actions専用CI NOT RUN / 本番・一般Gem HOLD。**

## 目的・変更範囲

前段 [P1-10t](VERIFIER_P110T_S01_PREPARED_NOT_RUN.md) は、署名VALIDかつ公式Open Schema INVALIDな `checkout.line_items.items[0].id = 123` を旧Ruby研究Verifierが受理する危険挙動を、ユーザーのMac Dockerで最新observer `1 run / 6 assertions`（ACCEPT / SECURITY RED_HOLD）として記録済み。**P1-10tの観測は修正済みという意味ではない。**

本PRは固定Issuer / 一行CheckoutのみのRuby研究Verifier `research/p1_3/checkout_binding_research.rb` に限り、Issuer署名済み `checkout.line_items.items[0].id` が **Ruby String** でなければ `AP2RootSDJWTResearch::Rejected`（reason: `invalid signed requirement id type`）として明示的にFail Closedにする。**キー集合が正しい場合の値型だけ**を追加チェックし、他のSchema項目は未対応のまま。公式Schemaへの一般適合性は主張しない。

## 独立した署名付き回帰2件（Docker実測済み）

1. **S01 SIGNED NEGATIVE** — P1-10tの真正Issuer署名・DisclosureをRubyで再検証し、署名済みRequirement `id: 123` を確認後、`AP2CheckoutBindingResearch.verify!` が**正確に** `invalid signed requirement id type` でREJECTすること。期限切れ、署名/Agent/nonce/merchantが別理由で失敗した場合はテストFAIL（緑と混同しない）。
2. **KNOWN-GOOD SIGNED POSITIVE** — 同じ固定公式AP2 v0.2.0 SDKから**別途新規に生成した**正常署名2hop Checkoutで、Issuer署名済みRequirement `id: "req-1"` を確認し、従来どおりVerified factsを返すこと。**Hostの最終business ALLOWではない**。

それぞれ一時鍵、署名済みfixture、公開JWKは**ローカル一時ファイルのみ**。秘密鍵/fixture/JWTをcommit・Issueに貼らない。既存 `research/p1_10t/generate_s01.py`、`research/p1_3/generate_merchant_checkout.py` を再利用し、新規Python生成器は作らない。

## Mac Dockerで実行した検証手順（ユーザー提供の実測）

下記手順をユーザーが既存Docker `/work/verifier` で実行済み。**PR HEAD `b7aba6dd41bc6ed180166e5b84d308cbeee7c6a8`を確認し、PythonのS01生成および別途正常fixture生成が両方成功した後にのみRubyテストを実行**した。古いfixtureは再利用していない。

```bash
cd /work/verifier
git fetch origin
git switch research/p1-10u-s01-signed-id-type-fail-closed
git pull --ff-only
git rev-parse HEAD

# 公式AP2: 既存 /work/AP2 を改変せず、今回専用のclean checkoutを用意
CLEAN_AP2="$(mktemp -d /tmp/ap2-p110u-src.XXXXXX)"
git --no-replace-objects -c core.fsmonitor=false \
  -c core.hooksPath=/dev/null -C /work/AP2 \
  worktree add --detach "$CLEAN_AP2" \
  b4587ac1d055888a73b4b21750973cffba961793

RUN_DIR="$(mktemp -d /tmp/ap2-p110u-run.XXXXXX)"
export AP2_P110T_UPSTREAM_ROOT="$CLEAN_AP2"

if PYTHONDONTWRITEBYTECODE=1 python -B \
     research/p1_10t/generate_s01.py "$RUN_DIR/s01.json" &&
   PYTHONPATH="$CLEAN_AP2/code/sdk/python" PYTHONDONTWRITEBYTECODE=1 python -B \
     research/p1_3/generate_merchant_checkout.py "$RUN_DIR/valid.json"
then
  AP2_P110U_S01_FIXTURE="$RUN_DIR/s01.json" \
  AP2_P110U_VALID_FIXTURE="$RUN_DIR/valid.json" \
  AP2_P110U_REPORT="$RUN_DIR/p110u-report.json" \
    ruby research/p1_10u/test_signed_s01_type_fix.rb --verbose
else
  echo "P1-10u: fixture generation failed; Ruby NOT RUN" >&2
fi
```

**実測結果：2 runs / 12 assertions / 0 failures / 0 errors / 0 skips**。S01は指定した`invalid signed requirement id type`の**厳密な理由**でREJECT、別途生成した正常署名Checkoutは**evidence-only ACCEPT**。一般的Schema適合性・本番の安全性を証明しない。

## 実測結果（2026-10-12 JST、ユーザーMac Docker）

**研究コードのHEAD：** `b7aba6dd41bc6ed180166e5b84d308cbeee7c6a8`。
**固定公式AP2：** `b4587ac1d055888a73b4b21750973cffba961793`（新規detached worktree、Python `-B`）。
**証拠の出所：** ユーザーがMac上Dockerコンテナで実行した端末ログ（ChatGPTやGitHub Actionsでこの2件を直接実行した結果ではない）。

```text
b7aba6dd41bc6ed180166e5b84d308cbeee7c6a8
Preparing worktree (detached HEAD b4587ac)
HEAD is now at b4587ac feat: Release Ap2 v0.2 (#233)
S01 SIGNATURE VALID: issuer disclosure/commitment, agent PoP and merchant JWS
S01 SCHEMA INVALID: pinned anyOf/contains errors; nested id type:string violation (integer 123)
S01: synthetic ephemeral signing keys never written/uploaded
PASS: generated Python AP2 Open/Closed with merchant-signed Checkout JWT
P1-10u S01: signed integer requirement ID REJECT at exact type gate
P1-10u known-good: signed Checkout evidence OK (no business ALLOW)
2 runs, 12 assertions, 0 failures, 0 errors, 0 skips
```

- **S01限定負例：LIMITED REGRESSION PASS**。RootのIssuer署名とDisclosureをRubyでも再検証し、正署名 `id = 123` を確かめたうえで、Ruby研究Verifierの`invalid signed requirement id type`だけを合格理由として検査。期限切れ・無効署名・別nonce等でのREJECTは合格理由にしない。
- **別署名正常例：LIMITED POSITIVE PASS**。`id = "req-1"`をRubyで署名検証し、Merchant/Checkout/金額の検証済みfactsだけを取得。最終business ALLOWやreceiptは返さない。
- **P1-10tの観測した修正前ACCEPT/SECURITY RED_HOLDは歴史的証拠として保持**。今回の結果は**固定合成IssuerのS01一件を型チェックで拒否した**ことを示す。S02〜S08・一般Schema/SD-JWT・Host/HC06へ安全宣言を拡張しない。
- **新P1-10u専用GitHub Actions CI：NOT RUN**。既存P1-10o/q/rのGitHub Actionsは最新コードHEADでそれぞれ成功（[P1-10o #38225195314](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38225195314)、[P1-10q #38225195214](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38225195214)、[P1-10r #38225195217](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38225195217)）。専用2件のCI成功とは混同しない。
- fixture・署名済みJWT・秘密鍵・実決済情報はリポジトリ・PRに含めない。

## 境界

- **Ruby研究Verifierの一箇所のみ**修正。P1-10tの歴史的危険受理観測は維持。S02（Merchant name String）・S03〜S08・一般Schema・一般Issuer・未知/未開示Constraint・replayはこの修正対象外。
- Host canonical **9/34実測・25 NOT RUN**、Authority→Host C01〜C12 UNKNOWN、HC06 **HOLD**。
- PR #42で自動起動した**既存GitHub Actions 3件**は成功：[P1-10o（#38225024091）](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38225024091)、[P1-10q（#38225023906）](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38225023906)、[P1-10r（#38225023980）](https://github.com/cuichangquan/ap2-mandate-verifier/actions/runs/38225023980)。**今回新規のP1-10u signed S01 + signed positive 2件はこれらのCIで実行されていない／NOT RUN**。先行P1-10t workflow追加がplatform safety checkで拒否された経緯を迂回しない。既存CIの成功をS01対策の成功と混同しない。
- Gem/API/本番統合 **HOLD**、RubyGems公開・実決済・Receipt **NO-GO**。
- Docker実測とCodexレビューが完了し、[PR #42](https://github.com/cuichangquan/ap2-mandate-verifier/pull/42) は **2026-10-12 にmainへSquashマージ済み**（merge SHA `09c71903d0ac5a36b88002f59402c0371b20c2ba`）。レビュー対象の最終PR HEAD `95538f5f224005c6c62e8ca422c87ae09ed04b3f` は重大指摘なし、P2解決、既存CI 3件成功を確認。**P1-10u専用CIは未実行**で、一般Gem/API/Host/Authority/本番へのGOではない。
