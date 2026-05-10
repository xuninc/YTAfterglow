#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(pwd)}"
TWEAK="$ROOT/YTAfterglow.x"

require() {
  local pattern="$1"
  local message="$2"
  if ! rg -q "$pattern" "$TWEAK"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

require 'ytagStartupAnimationEnabled' 'startup animation hooks must use a shared preference helper'
require 'mainAppCoreClientIosEnableStartupAnimation' 'iOS startup animation base flag must be hooked'
require 'mainAppCoreClientIosEnableShortsFirstStartupAnimation' 'Shorts-first startup animation gate must be hooked'
require 'mainAppCoreClientEnableStartupAnimationForAllStartupTypes' 'all startup types gate must be hooked'
require 'mainAppCoreClientEnableStartupAnimationForWarmStartups' 'warm startup gate must be hooked'
require 'mainAppCoreClientEnableStartupAnimationForShortsStartups' 'Shorts startup gate must be hooked'
require 'mainAppCoreClientEnableStartupAnimationForStartupTypes' 'startup type mask gate must be hooked'
require '%hook YTStartupAnimationViewController' 'startup animation eligibility class must be hooked'
require 'evaluateStartupAnimationEligibility:.*didLaunchIntoShorts:' 'startup animation eligibility must be forced when enabled'
require 'mainAppCoreClientIosInvalidateStartupAnimation' 'startup animation invalidation gate must be blocked when enabled'

echo "startup animation static check passed"
