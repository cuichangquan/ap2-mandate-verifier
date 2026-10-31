# frozen_string_literal: true

module AP2MandateVerifier
  # Supplemental guidance, never a verification decision or an input echo.
  # Only the closed catalog below can construct diagnostics. No input retained.
  class Diagnostic
    GROUPS = {
      input_validation: [%i[invalid_input_type input_too_large invalid_encoding invalid_json duplicate_key input_too_deep],
        "Check original String bytes, JSON syntax, duplicate keys and documented input limits.",
        "原文のString型、JSON構文、重複キー、文書記載の入力上限を確認してください。"],
      signature_verification: [%i[invalid_root_jws unsupported_root_header unsupported_root_algorithm unsupported_root_type invalid_root_payload invalid_root_signature],
        "Check original signed Root/Agent/Merchant bytes, the fixed header profile and independently selected public keys. A signature failure alone does not identify which input is wrong.",
        "署名原文、固定ヘッダー仕様、独立に選択した公開鍵を確認してください。署名失敗だけでは誤った入力を特定できません。"],
      root_disclosures: [%i[invalid_root_presentation unsupported_disclosure_profile invalid_disclosure missing_disclosure duplicate_disclosure duplicate_commitment extra_disclosure disclosure_limit_exceeded],
        "Check the complete original Root presentation and disclosures against the supported profile; do not repair received signed data.",
        "原Root提示全体と開示を対応profileと照合してください。受信した署名データを補修しないでください。"],
      purchase_binding: [%i[unsupported_purchase_profile agent_key_mismatch root_binding_mismatch audience_mismatch nonce_mismatch invalid_purchase_time delegation_claim_mismatch checkout_binding_mismatch checkout_identity_mismatch],
        "Compare original Root, Agent and Merchant wires with independent Host audience, nonce, identity and clock inputs. The code identifies a failed check, not its underlying cause.",
        "Root・Agent・Merchant原文と、Hostが独立に取得したaudience、nonce、主体、時刻を照合してください。コードは失敗した検査を示し、根本原因を断定しません。"],
      constraints: [%i[invalid_scoped_schema unsupported_scoped_profile unsupported_constraint constraint_mismatch amount_mismatch currency_mismatch constraint_limit_exceeded],
        "Compare signed constraints, checkout items, currency and minor-unit totals with independent current order data and the fixed profile.",
        "署名済み制約、購入項目、通貨、最小単位の合計額を、独立した現在の注文情報および固定profileと照合してください。"],
      trust_context: [%i[invalid_trust_context trust_context_mismatch unsupported_trust_profile inactive_trust_snapshot trust_snapshot_time_mismatch invalid_trust_key trust_key_not_found ambiguous_trust_key inactive_trust_key trust_key_time_mismatch],
        "Check authenticated current trust snapshot, explicit role/key selection, active state and validity at the independent verification time. Never select trust from received claims.",
        "認証された現在のtrust snapshot、明示的な役割・鍵選択、active状態、独立した検証時刻での有効期間を確認してください。受信claimから信頼先を選ばないでください。"],
      host_binding: [%i[invalid_host_context host_binding_mismatch challenge_state_mismatch challenge_reference_mismatch challenge_time_mismatch invalid_host_validity],
        "Compare the authenticated saved challenge with independent current order, trust references, expected issuer and time. Preserve the saved record; do not rebuild it from current values.",
        "認証された保存済みchallengeと、独立した現在の注文、trust参照、期待issuer、時刻を照合してください。保存記録を現在値で作り直さないでください。"]
    }.freeze
    GROUPS.each_value { |entry| entry[0].freeze; entry.freeze }
    SPECIAL = {
      invalid_purchase_time: ["Check the independent clock and the signed Open/Closed validity and terminal proof time window. This does not establish whether the clock or signed times are wrong.",
        "独立した時計、署名済みOpen・Closedの有効期間、terminal proofの時刻窓を確認してください。時計と署名時刻のどちらが誤っているかは断定できません。"]
    }.freeze
    BUILDER_HINTS = {
      missing_required_field: ["Supply the documented required field from independent Host data.", "文書記載の必須項目を、独立したHost情報から渡してください。"],
      invalid_type: ["Check the documented exact Ruby/JSON type; coercion and subclasses are not supported.", "文書記載のRuby・JSONの厳密な型を確認してください。暗黙変換やサブクラスは対応外です。"],
      unknown_field: ["Remove unsupported fields using the documented schema. Unknown field names are intentionally omitted.", "文書記載の構造と照合し、未対応項目を除いてください。未知の項目名は意図的に表示しません。"],
      unsupported_saved_format: ["Check the saved format/profile version against this gem. Restore original authenticated bytes; do not rewrite the version.", "保存形式・profileの版がGemの対応版か確認してください。認証された原文を復元し、版を書き換えないでください。"],
      invalid_value: ["Check documented bounds and supported values for this field.", "この項目の文書記載の範囲と対応値を確認してください。"],
      invalid_builder_input: ["Check the InputBuilder contract and bounded, plain Ruby input shapes. The exact cause could not be safely identified.", "InputBuilder契約と上限内の通常Ruby入力構造を確認してください。正確な原因は安全に特定できませんでした。"]
    }.freeze
    SPECIAL.each_value(&:freeze)
    BUILDER_HINTS.each_value(&:freeze)
    FIELDS = (%w[order trust verified_at saved_challenge snapshot snapshot.records issuer agent merchant arguments root_presentation terminal_jws host_checkout_jws trust_json selection_json expected_challenge_issuer_id clock_source_id challenge_id nonce issuer_id not_before not_after] +
      %w[tenant_id buyer_account_id order_id merchant_id audience order_version currency expected_total].map { |f| "order.#{f}" } +
      %w[id policy_version active not_before not_after records].map { |f| "snapshot.#{f}" } +
      %w[format_version profile_ref profile_version challenge].map { |f| "saved_challenge.#{f}" } +
      %w[issuer agent merchant].flat_map { |r| %w[identity purpose key_ref].map { |f| "#{r}.#{f}" } }).each(&:freeze).freeze

    attr_reader :stage, :field, :reason
    def initialize(stage, field, reason, hints)
      @stage, @field, @reason = stage, field, reason
      @hints = hints.map { |s| s.dup.freeze }.freeze
      freeze
    end
    private_class_method :new, :allocate
    def hint(locale: :en) = @hints[locale == :ja ? 1 : 0]
    def to_h(locale: :en) = {stage: stage, field: field, reason: reason, hint: hint(locale: locale)}.freeze
    def [](key) = to_h[key]
    def dup = self
    def clone(freeze: true) = self
    def self.for_result(status, code)
      return nil if status == :verified_research
      known = Result::CODES.fetch(status, []).include?(code)
      if status == :unavailable && known
        return new(:verification_unavailable, nil, code,
          ["Verification could not be completed. Check supported dependency versions and service/runtime health; this is not proof of invalid business data.",
           "検証を完了できませんでした。対応依存バージョンと実行環境の状態を確認してください。業務データ不正の証拠ではありません。"])
      end
      GROUPS.each do |stage, (codes, en, ja)|
        return new(stage, nil, code, SPECIAL.fetch(code, [en, ja])) if known && codes.include?(code)
      end
      new(:verification, nil, :undetermined,
        ["No precise diagnostic is available. Check status/code and the documented API scope; do not infer checkout permission.",
         "詳細診断はありません。status・codeとAPIの保証範囲を確認してください。購入許可とは解釈しないでください。"])
    end
    def self.builder(field, reason)
      # Look up canonical strings; never retain a caller string or arbitrary key.
      safe_field = FIELDS.find { |known| known == field }
      safe_reason = BUILDER_HINTS.key?(reason) ? reason : :invalid_builder_input
      new(:input_assembly, safe_field, safe_reason, BUILDER_HINTS.fetch(safe_reason))
    end
  end
end
