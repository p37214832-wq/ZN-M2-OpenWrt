#!/bin/bash
# ============================================================
# DIY Part 1 - Executed BEFORE feeds update
# Remove problematic feeds that break `make defconfig`
# ============================================================

set -e

echo "============================================"
echo " DIY Part 1: Pruning feeds"
echo "============================================"

# 2026-10-17 v4: feeds/video has qt5 recursive dependency that breaks
# `make defconfig` (feeds/video/frameworks/qt5/qt5base/Config.in:18).
# We don't need video packages for a minimal dae router.
if [ -f "feeds.conf.default" ]; then
    sed -i '/\/video/d' feeds.conf.default
    echo "  -> removed video feed from feeds.conf.default"
else
    echo "  -> WARNING: feeds.conf.default not found!"
fi

echo "DIY Part 1 completed."
