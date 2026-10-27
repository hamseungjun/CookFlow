#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
swiftc -D CORE_STANDALONE CookFlow/Core/*.swift Tests/CookFlowCoreTests/CookFlowCoreTests.swift scripts/TestRunner.swift -o .build/core-test-runner
.build/core-test-runner
swiftc -frontend -parse CookFlow/CookFlowApp.swift CookFlow/Views/*.swift CookFlow/Services/*.swift
plutil -lint CookFlow/Info.plist CookFlow/PrivacyInfo.xcprivacy CookFlow.xcodeproj/project.pbxproj
