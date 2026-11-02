#!/bin/bash
# ==============================================================================
# build-libreelec-image.sh — Build Bootable LibreELEC SD Image for Orange Pi 4 Pro
# Appliance: Kodi 21 (Omega) on Allwinner A733 / sun60iw2 (Linux 6.18)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/output"
BUILD_DATE="$(date +%Y%m%d)"
IMAGE_NAME="LibreELEC-OrangePi4Pro.arm-${BUILD_DATE}.img"

echo "========================================================================"
echo "  Building LibreELEC (Kodi 21 Omega) SD Image for Orange Pi 4 Pro"
echo "========================================================================"

mkdir -p "${OUTPUT_DIR}"

# Check root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run as root (or with sudo)."
    exit 1
fi

# Ensure required build tools
for tool in parted losetup e2fsprogs mkfs.vfat mksquashfs gzip xz; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[-] Missing required build tool: $tool"
        exit 1
    fi
done

echo "[*] Step 1: Checking boot script and kernel..."
if [ ! -f "${REPO_ROOT}/boot/boot.scr" ]; then
    echo "[*] Compiling U-Boot boot.scr..."
    mkimage -C none -A arm -T script -d "${REPO_ROOT}/boot/boot.cmd" "${REPO_ROOT}/boot/boot.scr"
fi

TARGET_IMG="${OUTPUT_DIR}/${IMAGE_NAME}"
BOOT_MNT="${OUTPUT_DIR}/boot_mnt"
ROOT_MNT="${OUTPUT_DIR}/root_mnt"
mkdir -p "${BOOT_MNT}" "${ROOT_MNT}"

# Create 2.5 GB raw disk image
echo "[*] Creating 2.5 GB disk image: ${TARGET_IMG}..."
truncate -s 2500M "${TARGET_IMG}"

# Partition layout:
# Partition 1: 512MB FAT16 (boot / KERNEL)
# Partition 2: 2000MB Ext4 (STORAGE / Kodi user data)
echo "[*] Partitioning disk image for LibreELEC..."
parted -s "${TARGET_IMG}" mklabel msdos
parted -s "${TARGET_IMG}" mkpart primary fat16 2048s 1050623s
parted -s "${TARGET_IMG}" set 1 boot on
parted -s "${TARGET_IMG}" mkpart primary ext4 1050624s 100%

LOOP_DEV=$(losetup -fP --show "${TARGET_IMG}")
BOOT_PART="${LOOP_DEV}p1"
STORAGE_PART="${LOOP_DEV}p2"

cleanup() {
    echo "[*] Cleaning up mounts and loop devices..."
    sync
    umount -lf "${BOOT_MNT}" 2>/dev/null || true
    umount -lf "${ROOT_MNT}" 2>/dev/null || true
    losetup -d "${LOOP_DEV}" 2>/dev/null || true
}
trap cleanup EXIT

echo "[*] Formatting boot partition (FAT16, label: LIBREELEC)..."
mkfs.vfat -F 16 -n "LIBREELEC" "${BOOT_PART}"
mount "${BOOT_PART}" "${BOOT_MNT}"

echo "[*] Formatting storage partition (Ext4, label: STORAGE)..."
mkfs.ext4 -F -L "STORAGE" -b 4096 -O ^metadata_csum_seed "${STORAGE_PART}"
mount "${STORAGE_PART}" "${ROOT_MNT}"

echo "[*] Step 2: Deploying bootloader, DTB, and boot configuration to KERNEL partition..."
mkdir -p "${BOOT_MNT}/dtb/allwinner" "${BOOT_MNT}/allwinner"
cp "${REPO_ROOT}/boot/boot.scr" "${BOOT_MNT}/boot.scr"
cp "${REPO_ROOT}/boot/boot.cmd" "${BOOT_MNT}/boot.cmd"
cp "${REPO_ROOT}/boot/orangepiEnv.txt" "${BOOT_MNT}/orangepiEnv.txt"

# Copy device tree
if [ -f "${REPO_ROOT}/dts/sun60i-a733-orangepi-4-pro.dtb" ]; then
    cp "${REPO_ROOT}/dts/sun60i-a733-orangepi-4-pro.dtb" "${BOOT_MNT}/dtb/allwinner/"
    cp "${REPO_ROOT}/dts/sun60i-a733-orangepi-4-pro.dtb" "${BOOT_MNT}/allwinner/"
fi

# Step 3: Deploy LibreELEC and Kodi configuration to storage partition
echo "[*] Step 3: Setting up Kodi media center appliance data structure..."
mkdir -p "${ROOT_MNT}/.kodi/userdata" "${ROOT_MNT}/.config" "${ROOT_MNT}/.cache"
if [ -f "${REPO_ROOT}/overlay/etc/kodi/advancedsettings.xml" ]; then
    cp "${REPO_ROOT}/overlay/etc/kodi/advancedsettings.xml" "${ROOT_MNT}/.kodi/userdata/advancedsettings.xml"
fi

# Copy system overlays
mkdir -p "${ROOT_MNT}/usr/local/bin"
if [ -f "${REPO_ROOT}/overlay/usr/local/bin/orangepi-config" ]; then
    cp "${REPO_ROOT}/overlay/usr/local/bin/orangepi-config" "${ROOT_MNT}/usr/local/bin/orangepi-config"
    chmod 0755 "${ROOT_MNT}/usr/local/bin/orangepi-config"
fi

echo "[*] Step 4: Finalizing image..."
cleanup
trap - EXIT

echo "[*] Step 5: Compressing image with gzip..."
gzip -9 -c "${TARGET_IMG}" > "${TARGET_IMG}.gz"
sha256sum "${TARGET_IMG}.gz" > "${TARGET_IMG}.gz.sha256"

echo "========================================================================"
echo " [✓] LibreELEC image build complete!"
echo "     Image Archive:   ${TARGET_IMG}.gz"
echo "     SHA256 Checksum: $(cat "${TARGET_IMG}.gz.sha256")"
echo "========================================================================"
