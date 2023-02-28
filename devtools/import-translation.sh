#!/bin/zsh

# Soon to be deprecated. Translation process of using localized .xliff files will be replaced with Transifex directly updating localized .strings and .stringsdict files.

if [ -z "$*" ]; then
  echo "Usage: ./devtools/import-translation.sh <locale_code_in_snake_case>"
  return
fi

find "translations" -name "${1}.xliff" | grep -v "en-US.xliff" | xargs -I % xcodebuild -importLocalizations -project damus.xcodeproj -localizationPath %
