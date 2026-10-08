#!/bin/sh
# Linux equivalent of git2revision.bat — writes revision.inc for FMDOptions.pas {$i revision.inc}
# Usage: git2revision.sh <output-file>
revfile="$1"
revnumber=''
revsha=''
if git --version >/dev/null 2>&1; then
  revnumber=$(git rev-list --count --first-parent HEAD 2>/dev/null || echo '')
  revsha=$(git log --pretty=%H -1 2>/dev/null || echo '')
fi
{
  echo "const"
  echo "  REVISION_NUMBER = '$revnumber';"
  echo "  REVISION_SHA = '$revsha';"
} > "$revfile"
