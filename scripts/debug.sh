#!/bin/zsh
# Drive the running debug build: ./scripts/debug.sh expand|collapse|music|shelf|drag|undrag|add <path>
ACTION="$1"; P="${2:-}"
cat > /tmp/notch-debug.swift <<SWIFT
import Foundation
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.lance.notch.debug"), object: nil,
    userInfo: ["action": "$ACTION", "path": "$P"], deliverImmediately: true)
usleep(300_000)
SWIFT
swift /tmp/notch-debug.swift 2>/dev/null
