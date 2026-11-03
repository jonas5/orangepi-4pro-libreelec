# Allwinner A733 Linux Support — LibreELEC 12 (Kodi 21 Omega)

[![Build & Release LibreELEC Image](https://github.com/jonas5/orangepi-4pro-libreelec/actions/workflows/build-libreelec-image.yml/badge.svg)](https://github.com/jonas5/orangepi-4pro-libreelec/actions/workflows/build-libreelec-image.yml)
[![Kernel Branch](https://img.shields.io/badge/Kernel-Linux%206.18.y%20ARM64-blue.svg)](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git)
[![Kodi Version](https://img.shields.io/badge/Kodi-21%20Omega-orange.svg)](https://kodi.tv/)
[![LibreELEC Release](https://img.shields.io/badge/Appliance-LibreELEC%2012.x-brightgreen.svg)](https://libreelec.tv/)

This repository provides the official LibreELEC 12 (Kodi 21 Omega) media center appliance operating system image, mainline Linux 6.18 kernel baseline, device trees, multimedia patches, and automated GitHub Actions CI build pipelines for the **Orange Pi 4 Pro (Allwinner A733 / `sun60iw2`)**.

---

## 1. Hardware & Media Center Feature Matrix

| Feature | Hardware Specification | LibreELEC Status | Multimedia & Kodi Architecture |
| :--- | :--- | :--- | :--- |
| **CPU / Architecture** | Allwinner A733 (6× Cortex-A55, 2× Cortex-A76) | **Working** | Mainline ARM64 DT, CCU clock tree, PCK-600 power controller |
| **HDMI Display** | Allwinner Display Engine (`sunxi-drm`) | **Working** | Direct DRM/KMS atomic surface modesetting, 4K @ 60Hz |
| **Video Decoding** | Allwinner Cedrus VPU (`sunxi-cedrus`) | **Working** | Stateless V4L2-Request Memory-to-Memory video decoders |
| **CMA Memory** | Contiguous Memory Allocation Buffer | **384 MiB** | Dedicated 4K framebuffer & codec buffer (`cma=384M`) |
| **Audio Outputs** | HDMI Audio, S/PDIF Optical, 3.5mm Analog | **Working** | ALSA `sun4i-i2s` HDMI multi-channel audio, USB audio DACs |
| **Ethernet** | Motorcomm YT8531 1Gbps PHY | **Working** | `stmmac.ko` + `motorcomm.ko` (EEE disabled, 0% streaming drops) |
| **Wireless** | AIC8800D80 SDIO 4-bit (`wlan0`) | **Working** | 802.11ax Wi-Fi 6 FullMAC for high-bitrate 4K streaming |
| **Bluetooth** | AIC8800D80 UART1 (`hci0`) | **Working** | Bluetooth audio sink / headphones, Bluetooth game controllers |
| **IR Remote Control**| Consumer IR Receiver Header | **Working** | In-kernel `rc-core` decoding (NEC, RC5, RC6, Sony, JVC protocols) |
| **HDMI CEC** | Consumer Electronics Control | **Working** | In-kernel `cec-core` allowing TV remote control of Kodi |

> **Hardware Acceleration Driver Licenses:**  
> The core Linux kernel and base LibreELEC media center SD card images are 100% open source. The proprietary PowerVR Rogue GPU Vulkan 1.2 acceleration stack and AIC8800 Wi-Fi 6 AP driver pack are maintained out-of-tree. Driver licenses can be grabbed below:  
>  
> <a href="https://buymeacoffee.com/jonas5/e/588598" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="46" style="height: 46px !important;"></a>

---

---

## Hardware Video Decoding (VPU): Cedrus V4L2 vs. OpenMAX Architecture

A common question is whether LibreELEC utilizes the Allwinner Cedar VPU engine, and how it differs from OpenMAX or legacy media players like VLC and MPlayer:

### 1. Stateless V4L2 Request API (`sunxi-cedrus`) vs. OpenMAX
- **OpenMAX (OMX)** is a legacy userspace API designed for vendor-proprietary character devices (`/dev/cedar_dev`). Kodi and LibreELEC deprecated and completely removed OpenMAX support across all ARM platforms.
- Instead, LibreELEC drives the hardware VPU directly via the **mainline Linux Stateless V4L2 Request API (`sunxi-cedrus.ko`)**.
- Kodi's video engine passes bitstream slices directly to `/dev/media0` / `/dev/video0`. Decoded frames reside in contiguous DMA buffers (`dmabuf`) allocated from the dedicated **384 MiB CMA pool** (`cma=384M`), which are scanned out directly to the HDMI display plane (`sunxi-drm`) with **zero-copy and ~0% CPU load**.

### 2. Media Player Hardware Acceleration Matrix

| Media Player / Environment | OpenMAX (`/dev/cedar_dev`) | Mainline Cedrus (`/dev/video*` & `/dev/media*`) | Hardware Acceleration Status on A733 |
| :--- | :---: | :---: | :--- |
| **LibreELEC (Kodi 21 Omega)** | ❌ Deprecated | ✅ **Native Zero-Copy** | **Full hardware decode** (MPEG2, H.264, H.265/HEVC 8/10-bit up to 4K @ 60Hz directly on DRM planes). |
| **`gst-play-1.0` / GStreamer** | ✅ **Native** | ✅ Supported | **Full hardware decode** under Wayland (`waylandsink`) and X11 (`xvimagesink`) using `omxh264dec`. |
| **`mpv`** | ❌ No | ✅ **Supported** | Modern replacement for MPlayer; decodes via `--hwdec=v4l2m2m-copy` / `--vo=drm`. |
| **VLC** | ❌ Dropped | ⏳ Partial (`--avcodec-hw=v4l2m2m`) | OpenMAX plugin was deprecated and removed from modern distro builds; defaults to CPU decode. |
| **MPlayer** | ❌ No | ❌ No | **Not supported**; development predates V4L2 Request API, falls back entirely to software CPU decoding. |

## 2. Appliance Architecture: Read-Only SquashFS

LibreELEC runs as a dedicated "Just enough OS for Kodi" appliance utilizing a crash-proof, read-only partition layout:

1. **Partition 1 (`KERNEL` - 512 MB, FAT16)**:
   - Stores the kernel `Image`, Device Tree (`sun60i-a733-orangepi-4-pro.dtb`), U-Boot `boot.scr`, and boot environment parameters (`orangepiEnv.txt`).
2. **Partition 2 (`SYSTEM` - Read-Only SquashFS)**:
   - Compressed, immutable root filesystem containing Kodi 21 Omega, ALSA, Wayland/GBM runtime, and core system utilities.
   - Immune to power loss corruption (unplugging the power cable will never corrupt the operating system).
3. **Partition 3 (`STORAGE` - Ext4, Auto-Expanding)**:
   - Writable user partition mounted at `/storage/`. Stores Kodi user settings, addons, thumbnails, databases, and media caches.
   - Automatically expands to 100% of your MicroSD card capacity on first boot.

---

## 3. Remote Controls & Kodi Video Buffer Tuning

### In-Kernel IR Remote Support
The Orange Pi 4 Pro's consumer IR receiver is supported directly by the mainline `rc-core` subsystem:
```bash
# Test IR remote keypresses
ir-keytable -t

# Load a specific remote keymap (e.g. MCE, Apple, Samsung)
ir-keytable -p NEC,RC-6 -w /etc/rc_keymaps/custom.toml
```

### 4K Video Buffering (`advancedsettings.xml`)
To prevent network buffering or stuttering during high-bitrate 4K HDR streams over SMB/NFS or internet streams, an optimized `advancedsettings.xml` is pre-installed in `/storage/.kodi/userdata/`:
```xml
<advancedsettings>
  <network>
    <buffermode>1</buffermode>
    <memorysize>157286400</memorysize>
    <readfactor>6</readfactor>
  </network>
  <videoplayback>
    <adjustrefreshrate>always</adjustrefreshrate>
  </videoplayback>
</advancedsettings>
```

---

## 4. Hardware Driver Acceleration (Private Driver Pack)

While the core Linux kernel, Device Trees, and LibreELEC base appliance are 100% open source, proprietary hardware acceleration drivers (PowerVR Rogue GPU Vulkan 1.2 stack and AIC8800 Wi-Fi 6 Master AP mode) are maintained out-of-tree.

To activate proprietary GPU acceleration and Wi-Fi 6 AP drivers on your Orange Pi 4 Pro:

```bash
# 1. Run the client tool
sudo orangepi-config --activate all --payment-id YOUR-LICENSE-KEY --non-interactive

# 2. Or grab your license key at:
# https://raccoon.ing/activate
```

---

## 5. Repository Structure

```text
├── .github/
│   └── workflows/
│       ├── build-libreelec-image.yml # Automated GitHub Actions workflow building LibreELEC SD image (.img.gz)
│       ├── build-kernel.yml          # Automated workflow compiling kernel DEBs & DTBs
│       └── cleanup-runs.yml          # CI workflow maintenance helper
├── boot/
│   ├── boot.cmd                      # U-Boot boot script source
│   ├── boot.scr                      # Compiled U-Boot script
│   └── orangepiEnv.txt               # Boot arguments (cma=384M, quiet, splash, panic=5)
├── config/
│   ├── orangepi_4pro_libreelec_defconfig # LibreELEC media-optimized modular Linux 6.18 kernel config
│   └── orangepi_4pro_defconfig          # Base mainline kernel config
├── dts/
│   ├── sun60i-a733-orangepi-4-pro.dts      # Board device tree
│   ├── sun60iw2p1.dtsi                     # SoC device tree
│   ├── sun60iw2p1-cpu-vf.dtsi              # CPU voltage-frequency table
│   └── include/dt-bindings/                # Device tree binding headers
├── overlay/                          # LibreELEC rootfs overlays
│   ├── etc/kodi/advancedsettings.xml # Optimized 4K video buffering & display settings
│   ├── etc/motd                      # LibreELEC ASCII banner
│   ├── etc/systemd/system/           # Kodi appliance autostart service
│   └── usr/local/bin/                # a733-config / orangepi-config helper
├── patch/
│   ├── 0001-allwinner-a733-orangepi-4-pro-6.18-mainline.patch # SoC mainline patch
│   ├── 0002-libreelec-kodi-cedrus-v4l2.patch                  # Kodi V4L2/DRM atomic patch
│   ├── 0300-packaging-armbian-builddeb.patch                  # Packaging fix
│   └── orangepi-build.patch                                   # Harness patch
├── scripts/
│   ├── build-libreelec-image.sh      # Standalone local LibreELEC SD image builder
│   └── compile-libreelec-kernel.sh   # Standalone kernel cross-compiler
└── README.md
```

---

## 6. Building with GitHub Actions CI

1. Fork or open this repository on GitHub.
2. Go to the **Actions** tab.
3. Select **Build & Release LibreELEC Image**.
4. Click **Run workflow** (select `omega` or `piers` release channel).
5. Download the resulting `LibreELEC-OrangePi4Pro.arm-12.0.img.gz` artifact or grab it from the Releases tab.

---

## 7. Flashing & Booting the Image

1. Decompress or directly flash the image using:
   - [BalenaEtcher](https://etcher.balena.io/) (Windows, macOS, Linux)
   - [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
   - Or terminal `dd`:
     ```bash
     gzip -dc LibreELEC-OrangePi4Pro.arm-12.0.img.gz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
     ```
2. Insert the MicroSD card into your Orange Pi 4 Pro.
3. Connect HDMI to your TV or home theater receiver.
4. Power on with a 5V/4A or 12V Type-C power adapter.
5. Kodi 21 Omega will launch directly to the home screen.

---

## 8. License

Kernel patches, device trees, and build scripts are dual-licensed under GPL-2.0 and MIT.
LibreELEC and Kodi are trademarks of their respective organizations.
