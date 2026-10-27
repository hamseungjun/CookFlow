#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mode="${1:-iphone}"
if [[ "$mode" != "iphone" && "$mode" != "ipad" ]]; then
  print -u2 'Usage: ./scripts/run-ios.sh iphone|ipad [runtime, e.g. 17.5]'
  exit 1
fi
mkdir -p .build
xcrun simctl list devices available -j > .build/simulator-devices.json
runtime="${2:-17.5}"
simulator_id=$(python3 - "$mode" "$runtime" <<'PY'
import json, sys
with open('.build/simulator-devices.json') as f: devices=json.load(f)['devices']
family='iPhone' if sys.argv[1]=='iphone' else 'iPad'
runtimes=sorted((k for k in devices if '.iOS-' in k), key=lambda k: tuple(int(n) for n in k.split('.iOS-')[-1].split('-')), reverse=True)
preferred='.iOS-'+sys.argv[2].replace('.', '-')
runtimes.sort(key=lambda k: not k.endswith(preferred))
for runtime in runtimes:
    matches=[d for d in devices[runtime] if d['isAvailable'] and d['name'].startswith(family)]
    if matches:
        print(matches[0]['udid']); break
else:
    sys.exit('No matching iOS Simulator is installed. Install an iOS runtime in Xcode Settings.')
PY
)
xcodebuild -project CookFlow.xcodeproj -scheme CookFlow -configuration Debug -destination "id=$simulator_id" -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO build
xcrun simctl boot "$simulator_id" 2>/dev/null || true
xcrun simctl bootstatus "$simulator_id" -b
xcrun simctl install "$simulator_id" .build/ios/Build/Products/Debug-iphonesimulator/CookFlow.app
xcrun simctl launch "$simulator_id" com.cookflow.ios
print "CookFlow launched on simulator $simulator_id"
