#!/bin/bash
# ============================================================
# DIY Part 2 - Executed AFTER feeds install, BEFORE make
# For VIKINGYFY/ImmortalWrt main branch (ZN-M2 already supported)
# MINIMAL DAE EDITION: dae + luci-app-dae + tailscale only
# ============================================================

set -e

echo "============================================"
echo " DIY Part 2: Customizing VIKINGYFY/ImmortalWrt"
echo "             (minimal dae edition)"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Remove WiFi from DEFAULT_PACKAGES (user doesn't need WiFi)
# IMPORTANT: DEFAULT_PACKAGES is a multi-line block. The first line is only
# "DEFAULT_PACKAGES += \" and the actual package names live on the tab-indented
# continuation lines. Sed must target those continuation lines, otherwise
# nothing gets removed at all.
echo "[1/3] Removing WiFi from DEFAULT_PACKAGES..."
TARGET_MAKEFILE="target/linux/qualcommax/Makefile"
IPQ60XX_MK="target/linux/qualcommax/ipq60xx/target.mk"

if [ -f "$TARGET_MAKEFILE" ]; then
    # Longest names first, so "kmod-ath11k" never partially matches
    # "kmod-ath11k-ahb" and leaves a dangling "-ahb" token behind.
    for pkg in kmod-ath11k-ahb kmod-ath11k-pci kmod-ath11k wpad-openssl; do
        sed -i "/^\t/s/ *${pkg}\b//g" "$TARGET_MAKEFILE"
    done
    # Collapse the double spaces left behind by the removals
    sed -i '/^\t/s/  \+/ /g' "$TARGET_MAKEFILE"
    echo "  -> WiFi packages removed from $TARGET_MAKEFILE"
else
    echo "  -> WARNING: $TARGET_MAKEFILE not found!"
fi

if [ -f "$IPQ60XX_MK" ]; then
    sed -i "/^DEFAULT_PACKAGES/s/ *ath11k-firmware-ipq6018-ddwrt\b//g" "$IPQ60XX_MK"
    echo "  -> WiFi firmware removed from $IPQ60XX_MK"
else
    echo "  -> WARNING: $IPQ60XX_MK not found!"
fi

echo "  -> Default packages after cleanup:"
sed -n '/^DEFAULT_PACKAGES/,/^\$(eval/p' "$TARGET_MAKEFILE" 2>/dev/null | head -8
grep "^DEFAULT_PACKAGES" "$IPQ60XX_MK" 2>/dev/null || true

# 2. Add dae + luci-app-dae as packages
# Cloned from ysuolmai/luci-app-dae (maintained fork used in production
# DAE firmware builds). The repo ships the dae core (tracking
# daeuniverse/dae main) and the luci-app-dae LuCI interface with zh_Hans.
# Must land in package/ BEFORE `make defconfig` so CONFIG_PACKAGE_dae=y
# and CONFIG_PACKAGE_luci-app-dae=y resolve.
echo "[2/3] Adding dae + luci-app-dae packages..."
if [ ! -d "package/dae" ] || [ ! -d "package/luci-app-dae" ]; then
    git clone --depth 1 https://github.com/ysuolmai/luci-app-dae.git /tmp/luci-app-dae
    if [ -d "/tmp/luci-app-dae/dae" ] && [ -d "/tmp/luci-app-dae/luci-app-dae" ]; then
        rm -rf package/dae package/luci-app-dae
        cp -r /tmp/luci-app-dae/dae package/dae
        cp -r /tmp/luci-app-dae/luci-app-dae package/luci-app-dae
        echo "  -> dae + luci-app-dae packages added"
    else
        echo "  -> ERROR: dae / luci-app-dae directories not found in cloned repo!"
        exit 1
    fi
    rm -rf /tmp/luci-app-dae
else
    echo "  -> dae packages already exist"
fi

# 3. Verify everything is in place
echo "[3/3] Final verification..."
echo ""

echo "  -> ZN-M2 device definition (should be built-in):"
IPQ60XX_IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"
grep -A8 "define Device/zn_m2" "$IPQ60XX_IMAGE_MK" 2>/dev/null || echo "  -> WARNING: zn_m2 not found in ipq60xx.mk!"
echo ""

echo "  -> ZN-M2 DTS (per-port netdevs -> port status display):"
DTS_FILE="target/linux/qualcommax/dts/ipq6000-m2.dts"
DTSI_FILE="target/linux/qualcommax/dts/ipq6000-cmiot.dtsi"
if [ -f "$DTS_FILE" ]; then
    echo "    [OK] $DTS_FILE exists"
    grep -E "label|status" "$DTSI_FILE" 2>/dev/null | head -8
else
    echo "    [WARN] $DTS_FILE NOT found!"
fi
echo ""

echo "  -> NSS stack (backup: these are also in DEFAULT_PACKAGES):"
for pkg in qca-nss-drv qca-nss-ecm qca-nss-dp qca-ssdk qca-nss-crypto nss-firmware; do
    if [ -d "package/qca-nss/$pkg" ]; then
        echo "    [OK] package/qca-nss/$pkg"
    else
        echo "    [WARN] package/qca-nss/$pkg NOT found!"
    fi
done
echo ""

echo "  -> Kernel version:"
grep "KERNEL_PATCHVER" "$TARGET_MAKEFILE" 2>/dev/null || true
echo ""

echo "  -> Key packages:"
for pkg in dae luci-app-dae tailscale; do
    found=$(find package/ feeds/ -path "*/$pkg/Makefile" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "    [OK] $pkg ($found)"
    else
        echo "    [WARN] $pkg NOT found!"
    fi
done

echo ""
echo "============================================"
echo " Build Summary"
echo "============================================"
echo " Source:  VIKINGYFY/ImmortalWrt main (NSS Full Support)"
echo " Kernel:  6.18 + eBPF/BTF (required by dae)"
echo " Target:  qualcommax/ipq60xx/zn_m2"
echo " WiFi:    DISABLED"
echo " NSS:     nss-drv + ecm + nss-dp + ssdk + firmware (from DEFAULT_PACKAGES)"
echo " Ports:   lan1 / lan2 / lan3 / wan (independent netdevs, labels in DTS)"
echo " Features: dae (transparent proxy) + luci-app-dae (zh_Hans UI)"
echo "           + tailscale (mesh networking)"
echo " Overlay: none (OpenWrt defaults: LAN 192.168.1.1, DHCP WAN)"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
