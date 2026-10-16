#!/bin/bash
# ============================================================
# DIY Part 2 - Executed AFTER feeds install, BEFORE make
# For VIKINGYFY/ImmortalWrt main branch (ZN-M2 already supported)
# MINIMAL DAE EDITION: dae (pinned v2.1.1) + daed + ttyd + tailscale
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

# 2. Add dae core as package (FORCE ysuolmai edition, dae subdir only).
# Web UI is daed + luci-app-daed from feeds (no cloning needed).
# Must land in package/ BEFORE `make defconfig` so CONFIG_PACKAGE_dae=y resolves.
echo "[2/3] Force-installing dae core (ysuolmai edition)..."
rm -rf package/dae package/luci-app-dae
find feeds package/feeds -maxdepth 4 \( -name "dae" -o -name "luci-app-dae" \) 2>/dev/null | while read -r d; do
    echo "  -> removing existing copy: $d"
    rm -rf "$d"
done
git clone --depth 1 https://github.com/ysuolmai/luci-app-dae.git /tmp/dae-src
if [ -d "/tmp/dae-src/dae" ]; then
    cp -r /tmp/dae-src/dae package/dae
    echo "  -> dae core (ysuolmai) installed to package/"
else
    echo "  -> ERROR: dae directory not found in cloned repo!"
    exit 1
fi
rm -rf /tmp/dae-src

# 2b. Pin dae core to upstream v2.1.1 (kdae rework) instead of floating main.
# The Makefile clones daeuniverse/dae@$GIT_BRANCH; a tag name works with `git clone -b`.
# Tolerant: if the Makefile layout ever changes, warn and keep floating main.
if grep -q '^GIT_BRANCH:=main$' package/dae/Makefile 2>/dev/null; then
    sed -i 's/^GIT_BRANCH:=main$/GIT_BRANCH:=v2.1.1/' package/dae/Makefile
    echo "  -> dae pinned to upstream v2.1.1 (kdae)"
else
    echo "  -> WARNING: GIT_BRANCH line not found in package/dae/Makefile, dae NOT pinned!"
fi

# 2c. Slim the dae package: install ONLY the main `dae` binary.
# GoPackage/Package/Install/Bin would also ship build-time helper tools
# (semantic-refactor-quic-helper, dae-ebpf-audit, gen_ebpf_sync, ~13.7MB).
# Tolerant: warn and continue if the install line is not found.
python3 - <<'PYEOF'
import sys
p = 'package/dae/Makefile'
s = open(p).read()
old = "\t$(call GoPackage/Package/Install/Bin,$(1))\n"
add = ("\t# keep only the main dae binary; drop build-time helper tools (~13.7MB)\n"
       "\tfor f in $(1)/usr/bin/*; do \\\n"
       "\t\t[ \"$$f\" = \"$(1)/usr/bin/dae\" ] || rm -f \"$$f\"; \\\n"
       "\tdone\n")
if old not in s:
    print("  -> WARNING: GoPackage install line not found, dae NOT slimmed!")
else:
    open(p, 'w').write(s.replace(old, old + add, 1))
    print("  -> dae install slimmed to main binary only")
PYEOF

# 2d. tailscale vs luci-app-tailscale file conflict: both ship
# etc/config/tailscale and etc/init.d/tailscale, which fails image assembly.
# Strip the duplicates from the luci app (tolerant if paths differ or gone).
if [ -d "feeds/luci/applications/luci-app-tailscale" ]; then
    find feeds/luci/applications/luci-app-tailscale -path "*etc/config/tailscale" -delete 2>/dev/null || true
    find feeds/luci/applications/luci-app-tailscale -path "*etc/init.d/tailscale" -delete 2>/dev/null || true
    echo "  -> stripped tailscale file conflicts from luci-app-tailscale"
fi


# 4. Verify everything is in place
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
for pkg in dae daed luci-app-daed ttyd luci-app-ttyd tailscale luci-app-tailscale; do
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

# First-boot: WiFi open (no password), LAN stays at default 192.168.1.1
# NOTE 2026-10-16: 192.168.2.1 preset removed for testing - IPv4 LAN was dead
# on builds with the 192.168.2.1 override (DHCP/ping/SSH all failed).
cat > files/etc/uci-defaults/99-zn-m2-v3 << 'UCIEOF'
#!/bin/sh
# ZN-M2 first-boot: open WiFi (LAN stays at default 192.168.1.1)
# Open WiFi (remove password)
uci set wireless.@wifi-iface[0].encryption='none'
uci delete wireless.@wifi-iface[0].key 2>/dev/null
uci set wireless.@wifi-iface[1].encryption='none' 2>/dev/null
uci delete wireless.@wifi-iface[1].key 2>/dev/null
uci commit wireless
exit 0
UCIEOF
chmod +x files/etc/uci-defaults/99-zn-m2-v3
echo "  -> files/etc/uci-defaults/99-zn-m2-v3 (LAN default 192.168.1.1, open WiFi)"

echo ""
echo "============================================"
echo " Build Summary"
echo "============================================"
echo " Source:  VIKINGYFY/ImmortalWrt main (NSS Full Support)"
echo " Kernel:  6.18 + eBPF/BTF (required by dae)"
echo " Target:  qualcommax/ipq60xx/zn_m2"
echo " WiFi:    ENABLED (ath11k-ahb + wpad-openssl)"
echo " NSS:     nss-drv + nss-dp + ssdk + firmware (ECM DISABLED for testing)"
echo " Ports:   lan1 / lan2 / lan3 / wan (independent netdevs, labels in DTS)"
echo " Features: dae v2.1.1 (pinned, kdae) + daed (official web UI) + ttyd + tailscale"
echo "           + luci-app-ttyd (web terminal) + luci-app-tailscale"
echo " Overlay: CN opkg mirrors, LAN 192.168.2.1, open WiFi (via files/)"
echo "============================================"

echo ""
echo "DIY Part 2 completed successfully."
