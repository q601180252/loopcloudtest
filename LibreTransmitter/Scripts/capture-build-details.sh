#!/bin/sh -e

#  capture-build-details.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.

echo "Libretransmitter Gathering build details in ${SRCROOT}"
cd "${SRCROOT}"

plist="${BUILT_PRODUCTS_DIR}/${INFOPLIST_PATH}"

prefix="com-loopkit-libre"

if [ -e .git ]; then
  # Check if this is a valid git repository before executing git commands
  if git rev-parse --git-dir > /dev/null 2>&1; then
    rev=$(git rev-parse HEAD 2>/dev/null)
    if [ -n "$rev" ]; then
      dirty=$([[ -z $(git status -s 2>/dev/null) ]] || echo '-dirty')
      plutil -replace $prefix-git-revision -string "${rev}${dirty}" "${plist}"
    fi
    
    branch=$(git branch 2>/dev/null | grep \* | cut -d ' ' -f2-)
    if [ -n "$branch" ]; then
      plutil -replace $prefix-git-branch -string "${branch}" "${plist}"
    fi

    remoteurl=$(git config --get remote.origin.url 2>/dev/null)
    if [ -n "$remoteurl" ]; then
      plutil -replace $prefix-git-remote -string "${remoteurl}" "${plist}"
    fi
  else
    echo "WARN: Current directory is not a valid git repository, skipping git info" >&2
  fi
fi;
plutil -replace $prefix-srcroot -string "${SRCROOT}" "${plist}"
plutil -replace $prefix-build-date -string "$(date)" "${plist}"
plutil -replace $prefix-xcode-version -string "${XCODE_PRODUCT_BUILD_VERSION}" "${plist}"

echo "Listing all custom plist properties:"
plutil -p "${plist}"|grep $prefix



