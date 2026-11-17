# frozen_string_literal: true

module AP2MandateVerifier
  class Diagnostic
    PAYMENT_FLOW = {
      payment_verification: {
        undetermined: ["Payment verification did not complete with a precise reason. Check inputs and runtime; no execution permission is established.", "Payment検証の詳細な理由は不明です。入力と実行環境を確認してください。実行許可ではありません。"].freeze,
        invalid_arguments: ["Check the documented keyword arguments.", "文書記載のキーワード引数を確認してください。"].freeze,
        checkout_not_verified: ["Checkout verification did not succeed. Inspect its separate result using the existing application flow, not by retrying payment.", "Checkout検証が成功していません。決済を再試行せず、既存のアプリ処理の検証結果を確認してください。"].freeze,
        checkout_binding_mismatch: ["Compare the payment with the independently verified Checkout reference, merchant, amount and currency.", "Paymentと独立に検証したCheckoutの参照、販売者、金額、通貨を照合してください。"].freeze,
        payment_time_mismatch: ["Compare the independent verification time with the signed validity window.", "独立した検証時刻と署名済み有効期間を照合してください。"].freeze,
        payment_conditions_mismatch: ["Compare the signed payment conditions with the selected payment. Do not rewrite signed data.", "署名済み支払い条件と選択したPaymentを照合してください。署名データを書き換えないでください。"].freeze,
        payment_binding_mismatch: ["Compare the signed Payment with independent expected payment and proof bindings.", "署名済みPaymentと独立した期待値・証明の結び付けを照合してください。"].freeze,
        signed_input_rejected: ["A signed-input check rejected the input. Check its supported format and independently selected public keys; this does not identify a cryptographic failure.", "署名入力の検査が入力を拒否しました。対応形式と独立に選択した公開鍵を確認してください。暗号署名失敗とは断定できません。"].freeze,
        verification_unavailable: ["Verification could not complete because a supported dependency/check was unavailable.", "対応依存関係または検証処理を利用できず、検証を完了できませんでした。"].freeze,
      }.freeze,
      payment_receipt_verification: {
        verification_unavailable: ["Receipt verification could not complete because a dependency/check was unavailable.", "依存関係または検証処理を利用できずReceipt検証を完了できませんでした。"].freeze,
        undetermined: ["Receipt verification failed without a precise diagnosis. It proves neither payment success nor a safe retry.", "Receipt検証失敗の詳細は不明です。支払い成功や安全な再試行の証拠ではありません。"].freeze,
        invalid_arguments: ["Check the documented Receipt keyword arguments.", "文書記載のReceiptキーワード引数を確認してください。"].freeze,
        receipt_time_mismatch: ["Compare the independent clock, allowed Receipt window and signed issue time.", "独立した時計、許容するReceipt期間、署名済み発行時刻を照合してください。"].freeze,
        receipt_reference_mismatch: ["Compare the Receipt issuer, payment identifier and exact Payment reference with independent saved expectations.", "Receiptの発行者・支払い識別子・原Payment参照と、独立した保存済み期待値を照合してください。"].freeze,
        signed_input_rejected: ["A signed-input check rejected Receipt or Payment input. Check original bytes, supported formats and independently trusted keys; the outcome is not yet verified.", "Receiptまたは原Paymentの入力検査が拒否しました。原文、対応形式、独立に信頼した公開鍵を確認してください。報告された結果は未検証です。"].freeze,
        reported_error: ["An authentic matching Receipt reports Error. This is not verification failure, success, retry permission or permission to release quota.", "真正で参照が一致するReceiptがErrorを報告しています。検証失敗・成功・再試行許可・利用枠解放許可ではありません。"].freeze,
      }.freeze,
      payment_acceptance: {
        undetermined: ["No precise acceptance diagnosis is available. Check saved state and the application contract; do not infer permission to execute.", "受理処理の詳細診断はありません。保存状態とアプリ契約を確認し、実行許可と解釈しないでください。"].freeze,
        conflict: ["The store reported a conflict. Check protected approval and saved state; the specific conflicting condition is not known.", "保存先が競合を報告しました。保護された承認と保存状態を確認してください。具体的な競合条件は不明です。"].freeze,
        unavailable: ["Storage was unavailable or its result uncertain. Reconcile saved state; do not retry payment or release quota automatically.", "保存先を利用できないか結果が不確実です。保存状態を照合し、自動再決済・利用枠解放をしないでください。"].freeze,
        pending: ["An existing attempt is pending. Inspect saved state and reconcile; this is not permission for another execution.", "既存の処理が保留中です。保存状態の確認・照合を行ってください。再実行許可ではありません。"].freeze,
        unknown: ["The execution outcome is unknown. Reconcile with the processor; never infer failure or release quota.", "実行結果は不明です。決済事業者と照合してください。失敗や利用枠解放を推測しないでください。"].freeze,
        receipt_error: ["A verified Receipt reports Error. It does not permit another execution or quota release.", "検証済みReceiptがErrorを報告しています。再実行・利用枠解放の許可ではありません。"].freeze,
        payment_not_verified: ["Payment verification did not succeed; no reservation was requested.", "Payment検証が成功せず、予約は要求していません。"].freeze,
        receipt_not_verified: ["Receipt verification did not succeed; no finalization was requested.", "Receipt検証が成功せず、確定保存は要求していません。"].freeze,
      }.freeze,
      payment_execution: {
        undetermined: ["No execution handle was returned. The cause and commit state are undetermined; this proves neither non-execution nor a safe retry.", "実行ハンドルは返りませんでした。原因・保存確定状態は不明です。未実行や安全な再試行の証拠ではありません。"].freeze,
        unavailable: ["Storage was unavailable or uncertain. No execution handle was returned; reconcile, do not automatically retry.", "保存先を利用できないか結果が不確実です。実行ハンドルはありません。照合し、自動再試行しないでください。"].freeze,
        conflict: ["The store reported a conflict; no execution handle was returned. Do not infer a safe retry.", "保存先が競合を報告し、実行ハンドルは返りませんでした。安全な再試行を推測しないでください。"].freeze,
        payment_not_verified: ["Fresh Payment verification did not succeed. No start was requested; this says nothing about prior attempts.", "最新Payment検証が成功せず、開始保存は要求していません。過去の処理結果を示すものではありません。"].freeze,
        saved_binding_mismatch: ["Fresh instruction or signed bytes differ from saved state. No start was requested; preserve the saved record.", "最新の指示または署名原文が保存状態と異なります。開始保存は要求していません。保存記録を維持してください。"].freeze,
      }.freeze,
    }.freeze
    # Restore only known catalog identifiers. Unknown values never become text.
    def self.payment_flow(stage, reason)
      return nil unless Symbol === stage && Symbol === reason
      hints = PAYMENT_FLOW.fetch(stage, {}).fetch(reason, nil)
      hints && new(stage, nil, reason, hints)
    end
  end

  module PaymentDiagnostics
    def self.build(stage, reason)
      Diagnostic.payment_flow(stage, reason)
    rescue StandardError, LoadError
      nil # Diagnostics never change a verification or storage decision.
    end
    # Private diagnostic metadata does not alter the public exception constructor.
    def self.invalid(klass, reason)
      error = klass.new
      error.instance_variable_set(:@diagnostic_reason, reason)
      error
    end
    def self.reason(error)
      if error.instance_of?(Payment::Invalid) || error.instance_of?(PaymentReceipt::Invalid) || error.instance_of?(SelectivePayment::Invalid)
        error.diagnostic_reason
      elsif error.is_a?(LoadError) || error.is_a?(RootSignature::Unavailable) || error.is_a?(InputValidator::Unavailable)
        :verification_unavailable
      elsif error.is_a?(RootSignature::Rejected)
        :signed_input_rejected
      else
        :undetermined
      end
    rescue StandardError, LoadError
      :undetermined
    end
  end
end
