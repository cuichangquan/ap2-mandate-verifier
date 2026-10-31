#!/bin/sh
# Run in an isolated Linux container. Build once, then pass the same Gem to both MRI runs.
set -eu
source_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out_dir=${1:?output directory required}
artifact=${2:?absolute candidate Gem path required}
mkdir -p "$out_dir"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
cd "$source_dir"
# Dependencies were installed through ordinary RubyGems during container setup.
# --local disables acquisition; this does not replace dependency resolution.
dependency_path=$(ruby -e 'puts Gem.path.join(File::PATH_SEPARATOR)')
GEM_HOME="$work_dir/installed" GEM_PATH="$work_dir/installed:$dependency_path" \
  gem install --local --no-document "$artifact" > "$out_dir/install.log" 2>&1
ruby -r "$source_dir/test/runtime_dependencies.rb" test/package_contents_audit.rb "$artifact" "$work_dir/extracted" "$work_dir/installed/gems/ap2_mandate_verifier-0.6.0" > "$out_dir/package.json"
mkdir "$work_dir/detached"
cd "$work_dir/detached"
GEM_HOME="$work_dir/installed" GEM_PATH="$work_dir/installed:$dependency_path" \
  ruby "$source_dir/test/packaged_gem_test.rb" \
    "$source_dir/research/stage15/results/R3/INPUTS.json" \
    "$source_dir/research/stage15_linux/EXPECTED.json" \
    "$out_dir/package.json" "$source_dir" > "$out_dir/installed.json"
cat "$out_dir/install.log"

GEM_HOME="$work_dir/installed" GEM_PATH="$work_dir/installed:$dependency_path" AP2_INSTALLED=1 \
  ruby "$source_dir/test/diagnostic_test.rb" > "$out_dir/diagnostic.log"
for scenario in valid tampered expired missing_currency wrong_total_type unknown_order_field unsupported_saved_format; do
  GEM_HOME="$work_dir/installed" GEM_PATH="$work_dir/installed:$dependency_path" \
    ruby "$source_dir/examples/input_builder.rb" "$scenario" >> "$out_dir/examples.log"
done
GEM_HOME="$work_dir/installed" GEM_PATH="$work_dir/installed:$dependency_path" \
  ruby "$source_dir/test/merchant_installed_test.rb" "$source_dir/examples/input_builder/signed_wires.json" > "$out_dir/merchant-installed.json"
GEM_HOME="$work_dir/installed" GEM_PATH="$work_dir/installed:$dependency_path" \
  ruby "$source_dir/examples/multi_item_checkout.rb" > "$out_dir/multi-item-installed.log"
cat "$out_dir/multi-item-installed.log"
