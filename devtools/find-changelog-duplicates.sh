#!/bin/bash

# Usage function to display help
function usage() {
  echo "Usage: $0 <file1> <file2>"
  echo "Where:"
  echo "  <file1> is the file to find duplicates within"
  echo "  <file2> is the file to check these duplicates against"
  echo
  echo "This script finds duplicate lines in <file1> and prints out any"
  echo "of these duplicates that exist in <file2>."
  exit 1
}

# Check for help flag
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
fi

# Check the number of arguments provided
if [ "$#" -ne 2 ]; then
  echo "Error: Two arguments are required."
  usage
fi

# Assign arguments to variables
file1=$1
file2=$2

# Check if files exist
if [ ! -f "$file1" ]; then
  echo "Error: File '$file1' does not exist."
  exit 1
fi

if [ ! -f "$file2" ]; then
  echo "Error: File '$file2' does not exist."
  exit 1
fi

# Find duplicates and check against the second file
sort "$file1" | uniq -d | grep -Fxf - "$file2"
