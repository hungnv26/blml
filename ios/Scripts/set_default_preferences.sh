#!/bin/bash

# This script assigns DefaultValue for host name and TLS in Settings.bundle/Root.plist preferences
# reading them from build configuration Info.plist.

# Location of Settings.bundle/Root.plist to update
prefs_file="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Settings.bundle/Root.plist"
# Location of Info.plist to read values from
info_plist="$TARGET_BUILD_DIR/$INFOPLIST_PATH"

# Find array entry with the necessary key
# Iterate at most 10 array entries until either the key is found or all entries iterated.
# @param: key to find
find_array_entry() {
  for i in {0..10}
  do
    local key=$(/usr/libexec/PlistBuddy -c "Print PreferenceSpecifiers:${i}:Key" "$prefs_file" 2>/dev/null)
    if [ -z "$key" ]; then
      continue
    fi
    if [[ $key == "$1" ]]; then
      echo $i
      return 0
    fi
  done
  return 1
}

# Find the entries. BLML's Settings.bundle dropped the host name and TLS
# entries (the server is fixed), so a missing entry is skipped, not an error.
hn_index=$(find_array_entry "host_name_preference") || hn_index=""
tls_index=$(find_array_entry "use_tls_preference") || tls_index=""
bv_index=$(find_array_entry "bundle_version") || bv_index=""

# Read values from Info.plist
host_name=$(/usr/libexec/PlistBuddy -c "Print :HOST_NAME" "$info_plist" 2>/dev/null)
use_tls=$(/usr/libexec/PlistBuddy -c "Print :USE_TLS" "$info_plist" 2>/dev/null)
bundle_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist" 2>/dev/null)
if [ -z "$host_name" ] || [ -z "$use_tls" ] || [ -z "$bundle_version" ]; then
  echo "Missing host name '$host_name' or TLS value '$use_tls' or bundle version value '$bundle_version'"
  exit 1
fi

# Assign values as appropriate
echo "Modifying preference entries in '$prefs_file'"
assign() {
  if [ -n "$1" ]; then
    /usr/libexec/PlistBuddy -c "Set PreferenceSpecifiers:$1:DefaultValue $2" "$prefs_file"
    echo "Assigned '$2' to PreferenceSpecifiers:$1:DefaultValue"
  fi
}
assign "$hn_index" "$host_name"
assign "$tls_index" "$use_tls"
assign "$bv_index" "$bundle_version"
