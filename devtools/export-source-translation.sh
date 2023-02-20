#!/bin/zsh

# Generates all en-US source localized strings EXCEPT for SwiftUI Text wrapped strings.
xcodebuild -exportLocalizations -project damus.xcodeproj -localizationPath "damus" -exportLanguage en-US

# Generates all SwiftUI Text() wrapped localized strings.
genstrings -o "damus/en-US.xcloc/Source Contents/damus/en-US.lproj/" -SwiftUI **/*.swift
