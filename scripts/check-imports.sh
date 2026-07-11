#!/bin/bash
#
# check-imports.sh — fast guard against Xcode 16's MemberImportVisibility errors.
#
# Using a member (property/method) from a module now requires importing that
# module directly, even if another import used to re-export it. The two that
# bite this project are Combine (@Published, ObservableObject, objectWillChange,
# .sink, Timer.publish…) and StoreKit (Product.displayPrice, Transaction…).
# This catches them in seconds instead of a 3-minute compile.
#
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

check() {
  local module="$1" pattern="$2"
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! grep -q "^import $module" "$f"; then
      echo "::error file=$f::uses $module members but is missing 'import $module'"
      fail=1
    fi
  done < <(grep -rlE "$pattern" AirPad --include="*.swift" 2>/dev/null)
}

check "Combine" "@Published|: ObservableObject|ObservableObject \{|AnyCancellable|PassthroughSubject|CurrentValueSubject|objectWillChange|\.eraseToAnyPublisher\(|Timer\.publish\("
check "StoreKit" "\b(Product|Transaction|AppStore|displayPrice|currentEntitlements)\b|\.purchase\(\)|requestReview"

if [ "$fail" -eq 0 ]; then
  echo "Import check passed."
fi
exit $fail
