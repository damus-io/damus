#!/bin/zsh

xcodebuild -exportLocalizations -project damus.xcodeproj -localizationPath "translations" -exportLanguage en-US
