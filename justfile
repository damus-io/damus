build:
    xcodebuild -scheme damus -sdk iphoneos -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16e' -quiet | xcbeautify --quieter

test:
    xcodebuild test -scheme damus -destination 'platform=iOS Simulator,OS=26.0,name=iPhone 16e' | xcbeautify
