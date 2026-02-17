build:
    xcodebuild -scheme damus -sdk iphoneos -destination 'platform=iOS Simulator,name=iPhone 16e' -quiet | xcbeautify --quieter

test test_name="":
    #!/usr/bin/env bash
    if [ -n "{{test_name}}" ]; then
        xcodebuild test -scheme damus -destination 'platform=iOS Simulator,name=iPhone 16e' -only-testing:{{test_name}} | xcbeautify --quieter
    else
        xcodebuild test -scheme damus -destination 'platform=iOS Simulator,name=iPhone 16e' | xcbeautify --quieter
    fi
