# P1-10u — S01 signed Requirement.id 型検証の限定修正（PREPARED / NOT RUN）

**2026-10-12 JST — Fixed synthetic Issuer research only / Docker NOT RUN / GitHub Actions NOT RUN / HOLD.**

## 目的・変更範囲

前段 [P1-10t](VERIFIER_P110T_S01_PREPARED_NOT_RUN.md) は、署名VALIDかつ公式Open Schema INVALIDな `checkout.line_items.items[0].id = 123` を旧Ruby研究Verifierが受理する危険挙動を、ユーザーのMac Dockerで最新observer `1 run / 6 assertions`（ACCEPT / SECURITY RED_HOLD）として記録済み。**P1-10tの観測は修正済みという意味ではない。**

本PRは固定Issuer / 一行CheckoutのみのRuby研究Verifier `research/p1_3/checkout_binding_research.rb` に限り、Issuer署名済み `checkout.line_items.items[0].id` が **Ruby String** でなければ `AP2RootSDJWTResearch::Rejected`（reason: `invalid signed requirement id type`）として明示的にFail Closedにする。**キー集合が正しい場合の値型だけ**を追加チェックし、他のSchema項目は未対応のまま。公式Schemaへの一般適合性は主張しない。

## 独立した署名付き回帰2件（現時点 NOT RUN）

1. **S01 SIGNED NEGATIVE** — P1-10tの真正Issuer署名・DisclosureをRubyで再検証し、署名済みRequirement `id: 123` を確認後、`AP2CheckoutBindingResearch.verify!` が**正確に** `invalid signed requirement id type` でREJECTすること。期限切れ、署名/Agent/nonce/merchantが別理由で失敗した場合はテストFAIL（緑と混同しない）。
2. **KNOWN-GOOD SIGNED POSITIVE** — 同じ固定公式AP2 v0.2.0 SDKから**別途新規に生成した**正常署名2hop Checkoutで、Issuer署名済みRequirement `id: "req-1"` を確認し、従来どおりVerified factsを返すこと。**Hostの最終business ALLOWではない**。

それぞれ一時鍵、署名済みfixture、公開JWKは**ローカル一時ファイルのみ**。秘密鍵/fixture/JWTをcommit・Issueに貼らない。既存 `research/p1_10t/generate_s01.py`、`research/p1_3/generate_merchant_checkout.py` を再利用し、新規Python生成器は作らない。

## Mac Dockerでの検証手順（未実行）

下記をユーザーの既存Docker `/work/verifier` 内で実施する。**最新PR HEADを `git rev-parse HEAD` で確認し、Python生成が両方成功した場合だけRubyを実行する。** 古いfixtureを再利用しない。

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

期待する**判定条件**：2件とも失敗/skip/errorなしで、S01は**指定した型チェック理由**によるREJECT、正常Checkoutは**evidence-only ACCEPT**。件数/Assertionsの実測は受領後に記録する。実行エラー・Ruby FAIL・異なるREJECT・旧fixtureなどは **NOT VERIFIED / HOLD** と報告する。

## 境界

- **Ruby研究Verifierの一箇所のみ**修正。P1-10tの歴史的危険受理観測は維持。S02（Merchant name String）・S03〜S08・一般Schema・一般Issuer・未知/未開示Constraint・replayはこの修正対象外。
- Host canonical **9/34実測・25 NOT RUN**、Authority→Host C01〜C12 UNKNOWN、HC06 **HOLD**。
- GitHub Actionsは本PRで**NOT RUN**。先行P1-10t workflow追加がplatform safety checkで拒否された経緯を迂回しない。**CIを実行したという主張をしない**。
- Gem/API/本番統合 **HOLD**、RubyGems公開・実決済・Receipt **NO-GO**。
- Docker結果・Codexレビュー・PR差分を確認するまで**マージしない**。
