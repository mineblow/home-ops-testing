#!/bin/bash

FILE="$1"
MSG=$(head -n1 "$FILE")

# Allow merge commits, reverts, etc.
if [[ "$MSG" =~ ^(Merge|Revert|fixup!|squash!) ]]; then
  exit 0
fi

# Enforce type(scope): message
if ! [[ "$MSG" =~ ^(feat|fix|docs|style|refactor|test|chore|ci|build)(\([a-z0-9_-]+\))?:\ .+ ]]; then
  echo "❌ Invalid commit message format!"
  echo "💡 Use: feat(scope): message"
  echo "   Example: fix(terraform): correct vm count"
  exit 1
fi
