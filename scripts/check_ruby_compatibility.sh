#!/bin/sh
# Existing suites run separately and sequentially. Output directory must be outside source.
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${1:?output directory required}
mkdir -p "$out_dir"
cd "$source_dir"
ruby scripts/check_runtime.rb > "$out_dir/runtime.json"
for suite in ruby_requirement input_boundary root_signature root_disclosures purchase_binding scoped_constraints integration_matrix trust_context verify_checkout input_builder diagnostic checkout_receipt; do
  ruby -r "$source_dir/test/runtime_dependencies.rb" "test/${suite}_test.rb" > "$out_dir/${suite}.log" 2>&1
  cat "$out_dir/${suite}.log"
done
# verify_checkout already executes Host and Evidence suites; never double-count them.
