#!/bin/zsh

if [ -z "$*" ]; then
  echo "Usage: ./devtools/import-translation.sh <locale_code_in_snake_case>"
  return
fi

find "translations" -name "${1}.xliff" | grep -v "en-US.xliff" | xargs -I % xcodebuild -importLocalizations -project damus.xcodeproj -localizationPath %
