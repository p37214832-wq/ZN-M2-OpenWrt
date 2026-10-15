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

# 1. WiFi: KEEP (user wants WiFi AP on ZN-M2)
# Upstream DEFAULT_PACKAGES already ships the full WiFi stack for
# qualcommax/ipq60xx: wpad-openssl + kmod-ath11k/ahb/pci and
# ath11k-firmware-ipq6018-ddwrt. Nothing to strip - just verify.
echo "[1/3] Verifying WiFi packages in DEFAULT_PACKAGES..."
TARGET_MAKEFILE="target/linux/qualcommax/Makefile"
IPQ60XX_MK="target/linux/qualcommax/ipq60xx/target.mk"

echo "  -> WiFi packages kept in $TARGET_MAKEFILE:"
grep -o "wpad-openssl\|kmod-ath11k-ahb\|kmod-ath11k-pci\|kmod-ath11k" "$TARGET_MAKEFILE" 2>/dev/null | sort -u || echo "  -> WARNING: WiFi packages not found!"
echo "  -> WiFi firmware kept in $IPQ60XX_MK:"
grep -o "ath11k-firmware-ipq6018-ddwrt" "$IPQ60XX_MK" 2>/dev/null || echo "  -> WARNING: WiFi firmware not found!"

# 2. Add dae + luci-app-dae as packages (FORCE ysuolmai edition)
# Cloned from ysuolmai/luci-app-dae (maintained fork with the subscription
# form UI: Form / All Nodes / Text tabs). Any existing copies from feeds
# or a previous run are REMOVED first, so the ysuolmai fork is definitely
# what gets built. (The old logic skipped the clone when the dirs already
# existed, which is how the old UI got baked into the previous firmware.)
# Must land in package/ BEFORE `make defconfig` so CONFIG_PACKAGE_dae=y
# and CONFIG_PACKAGE_luci-app-dae=y resolve.
echo "[2/4] Force-installing dae + luci-app-dae (ysuolmai edition)..."
rm -rf package/dae package/luci-app-dae
find feeds package/feeds -maxdepth 4 \( -name "dae" -o -name "luci-app-dae" \) 2>/dev/null | while read -r d; do
    echo "  -> removing existing copy: $d"
    rm -rf "$d"
done
git clone --depth 1 https://github.com/ysuolmai/luci-app-dae.git /tmp/dae-src
if [ -d "/tmp/dae-src/dae" ] && [ -d "/tmp/dae-src/luci-app-dae" ]; then
    cp -r /tmp/dae-src/dae package/dae
    cp -r /tmp/dae-src/luci-app-dae package/luci-app-dae
    echo "  -> dae + luci-app-dae (ysuolmai) installed to package/"
else
    echo "  -> ERROR: dae / luci-app-dae directories not found in cloned repo!"
    exit 1
fi
rm -rf /tmp/dae-src

# 3. Add luci-app-tailscale (asvow edition)
# Standard Lua LuCI app (luci.mk), compatible with this tree's LuCI.
# The stock feeds do not provide luci-app-tailscale, which is why
# CONFIG_PACKAGE_luci-app-tailscale=y was silently dropped by defconfig
# in the previous build.
echo "[3/4] Adding luci-app-tailscale (asvow)..."
rm -rf package/luci-app-tailscale
find feeds package/feeds -maxdepth 4 -name "luci-app-tailscale" 2>/dev/null | while read -r d; do
    echo "  -> removing existing copy: $d"
    rm -rf "$d"
done
git clone --depth 1 https://github.com/asvow/luci-app-tailscale.git package/luci-app-tailscale
# Fix file conflicts: the tailscale main package already ships
# /etc/config/tailscale and /etc/init.d/tailscale. The copies bundled in
# this luci-app would abort the build with "trying to overwrite" errors,
# so drop them and keep only the LuCI web UI files.
rm -f package/luci-app-tailscale/root/etc/config/tailscale
rm -f package/luci-app-tailscale/root/etc/init.d/tailscale
echo "  -> luci-app-tailscale (asvow) installed to package/"

# 4. Verify everything is in place
echo "[4/4] Final verification..."
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
for pkg in dae luci-app-dae tailscale luci-app-tailscale ttyd luci-app-ttyd; do
    found=$(find package/ feeds/ -path "*/$pkg/Makefile" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "    [OK] $pkg ($found)"
    else
        echo "    [WARN] $pkg NOT found!"
    fi
done

# --- v3: files overlay (CN mirrors, LAN 192.168.2.1, open WiFi) ---
# These go into files/ and do NOT affect `make defconfig`.
echo ""
echo "[7/7] Setting up files overlay (CN mirrors, LAN IP, open WiFi)..."
mkdir -p files/etc/opkg files/etc/uci-defaults

# Chinese opkg mirrors (Tsinghua)
cat > files/etc/opkg/distfeeds.conf << 'FEEDSEOF'
src/gz openwrt_core https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/targets/qualcommax/ipq60xx/packages
src/gz openwrt_base https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/base
src/gz openwrt_luci https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/luci
src/gz openwrt_packages https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/packages
src/gz openwrt_routing https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/routing
src/gz openwrt_telephony https://mirrors.tuna.tsinghua.edu.cn/immortalwrt/releases/24.10-SNAPSHOT/packages/aarch64_cortex-a53/telephony
FEEDSEOF
echo "  -> files/etc/opkg/distfeeds.conf (Tsinghua mirrors)"

# First-boot: LAN 192.168.2.1, WiFi open (no password)
cat > files/etc/uci-defaults/99-zn-m2-v3 << 'UCIEOF'
#!/bin/sh
# ZN-M2 v3 first-boot: LAN 192.168.2.1, open WiFi
uci set network.lan.ipaddr='192.168.2.1'
uci commit network
# Open WiFi (remove password)
uci set wireless.@wifi-iface[0].encryption='none'
uci delete wireless.@wifi-iface[0].key 2>/dev/null
uci set wireless.@wifi-iface[1].encryption='none' 2>/dev/null
uci delete wireless.@wifi-iface[1].key 2>/dev/null
uci commit wireless
exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-zn-m2-v3
echo "  -> files/etc/uci-defaults/99-zn-m2-v3 (LAN 192.168.2.1, open WiFi)"

echo ""
echo "============================================"
echo " Build Summary"
echo "============================================"
echo " Source:  VIKINGYFY/ImmortalWrt main (NSS Full Support)"
echo " Kernel:  6.18 + eBPF/BTF (required by dae)"
echo " Target:  qualcommax/ipq60xx/zn_m2"
echo " WiFi:    ENABLED (ath11k-ahb + wpad-openssl)"
echo " NSS:     nss-drv + ecm + nss-dp + ssdk + firmware (from DEFAULT_PACKAGES)"
echo " Ports:   lan1 / lan2 / lan3 / wan (independent netdevs, labels in DTS)"
echo " Features: dae (transparent proxy) + luci-app-dae (ysuolmai, subscription UI)"
echo "           + tailscale + luci-app-tailscale (asvow, web UI)"
echo "           + ttyd + luci-app-ttyd (web terminal)"
echo " Overlay: CN opkg mirrors, LAN 192.168.2.1, open WiFi (via files/)"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
