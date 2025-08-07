build:
    xcodebuild -scheme damus -sdk iphoneos -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -quiet | xcbeautify --quieter

test:
    xcodebuild test -scheme damus -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -quiet | xcbeautify --quieter
