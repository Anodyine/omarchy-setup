#!/usr/bin/env bash
# btrfs-3step.sh
#
# Steps:
#   1) partition : GPT with 20GiB ESP (FAT32) + rest Btrfs
#   2) format    : mkfs.vfat on ESP + mkfs.btrfs on data
#   3) layout    : create @ @home @log @cache @snapshots and mount at /mnt
#
# Examples:
#   Step 1: Partition the disk
#     sudo ./btrfs-3step.sh -s partition -d /dev/nvme0n1
#
#   Step 2: Format the partitions (pass the exact partition paths)
#     sudo ./btrfs-3step.sh -s format -e /dev/nvme0n1p1 -b /dev/nvme0n1p2
#
#   Step 3: Create subvolumes and mount
#     sudo ./btrfs-3step.sh -s layout -e /dev/nvme0n1p1 -b /dev/nvme0n1p2
#
# Notes:
#   - This destroys data when you run step "partition".
#   - The ESP is sized 20GiB by request. Typical ESP is smaller but this is fine.
#   - After step 3 you can run archinstall with Manual partitioning. /mnt is ready.
#   - After install, run: genfstab -U /mnt >> /mnt/etc/fstab

set -euo pipefail

# Defaults
BTRFS_LABEL="ARCH-BTRFS"
COMPRESS_OPT="zstd:3"

# Inputs
STEP=""          # partition | format | layout
DISK=""          # whole disk for partitioning, e.g. /dev/nvme0n1 or /dev/sda
EFI_PART=""      # e.g. /dev/nvme0n1p1 or /dev/sda1
BTRFS_PART=""    # e.g. /dev/nvme0n1p2 or /dev/sda2
FORCE="no"       # allow existing mounts at /mnt

usage() {
  cat <<EOF
Usage:
  $0 -s <partition|format|layout> [options]

Steps and required options:
  -s partition    -d <DISK>
  -s format       -e <EFI_PART> -b <BTRFS_PART>
  -s layout       -e <EFI_PART> -b <BTRFS_PART>

Options:
  -d  Whole disk device for partitioning (e.g. /dev/nvme0n1 or /dev/sda)
  -e  EFI partition path (FAT32), e.g. /dev/nvme0n1p1
  -b  Btrfs partition path, e.g. /dev/nvme0n1p2
  -l  Btrfs label (default: ${BTRFS_LABEL})
  -c  Btrfs compression option (default: ${COMPRESS_OPT})
  -f  Force proceed if /mnt is mounted or not empty

Examples:
  $0 -s partition -d /dev/nvme0n1
  $0 -s format -e /dev/nvme0n1p1 -b /dev/nvme0n1p2
  $0 -s layout -e /dev/nvme0n1p1 -b /dev/nvme0n1p2
EOF
  exit 1
}

while getopts ":s:d:e:b:l:c:f" opt; do
  case "$opt" in
    s) STEP="$OPTARG" ;;
    d) DISK="$OPTARG" ;;
    e) EFI_PART="$OPTARG" ;;
    b) BTRFS_PART="$OPTARG" ;;
    l) BTRFS_LABEL="$OPTARG" ;;
    c) COMPRESS_OPT="$OPTARG" ;;
    f) FORCE="yes" ;;
    *) usage ;;
  esac
done

require() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1"; exit 1; }; }

need_root() { [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }; }

print_header() {
  echo
  echo "=== $1 ==="
}

proof_lsblk() {
  echo
  echo "--- lsblk ---"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$@" || true
}

proof_blkid() {
  echo
  echo "--- blkid ---"
  blkid "$@" || true
}

check_block() { [[ -b "$1" ]] || { echo "Not a block device: $1"; exit 1; }; }

ensure_mnt_ready() {
  if mountpoint -q /mnt; then
    echo "/mnt is mounted. Unmount it first or use -f."
    [[ "$FORCE" == "yes" ]] || exit 1
  fi
  if [[ -d /mnt && -n "$(ls -A /mnt 2>/dev/null || true)" ]]; then
    echo "/mnt is not empty. Use -f to proceed."
    [[ "$FORCE" == "yes" ]] || exit 1
  fi
  mkdir -p /mnt
}

step_partition() {
  need_root
  require parted
  require lsblk

  [[ -n "$DISK" ]] || { echo "partition step requires -d <DISK>"; exit 1; }
  check_block "$DISK"

  print_header "Partitioning $DISK (GPT: 20GiB ESP + rest Btrfs)"
  # Refuse if any partition table already looks populated unless FORCE
  if lsblk -no NAME "$DISK" | grep -qE '^.+[0-9]+$' ; then
    echo "Warning: $DISK already has partitions."
    [[ "$FORCE" == "yes" ]] || { echo "Use -f to overwrite"; exit 1; }
  fi

  # Wipe first 4MiB and last 4MiB to avoid leftover metadata
  require sgdisk
  sgdisk --zap-all "$DISK" || true

  parted --script "$DISK" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 20GiB \
    set 1 esp on \
    mkpart primary btrfs 20GiB 100%

  # Try to guess the child names
  print_header "New partition table"
  proof_lsblk "$DISK"

  echo
  echo "If your disk is NVMe, partitions will be ${DISK}p1 and ${DISK}p2."
  echo "If SATA/USB (e.g. /dev/sda), partitions will be ${DISK}1 and ${DISK}2."
}

step_format() {
  need_root
  require mkfs.vfat
  require mkfs.btrfs

  [[ -n "$EFI_PART" && -n "$BTRFS_PART" ]] || { echo "format step requires -e <EFI_PART> -b <BTRFS_PART>"; exit 1; }
  check_block "$EFI_PART"
  check_block "$BTRFS_PART"

  print_header "Formatting $EFI_PART as FAT32 (label BOOT)"
  mkfs.vfat -F32 -n BOOT "$EFI_PART"

  print_header "Formatting $BTRFS_PART as Btrfs (label $BTRFS_LABEL)"
  mkfs.btrfs -f -L "$BTRFS_LABEL" "$BTRFS_PART"

  print_header "Proof of filesystems"
  proof_blkid "$EFI_PART" "$BTRFS_PART"
}

step_layout() {
  need_root
  require btrfs
  require blkid
  require findmnt
  require mount
  require umount

  [[ -n "$EFI_PART" && -n "$BTRFS_PART" ]] || { echo "layout step requires -e <EFI_PART> -b <BTRFS_PART>"; exit 1; }
  check_block "$EFI_PART"
  check_block "$BTRFS_PART"

  FSTYPE="$(blkid -s TYPE -o value "$BTRFS_PART" || true)"
  [[ "$FSTYPE" == "btrfs" ]] || { echo "$BTRFS_PART is not Btrfs"; exit 1; }

  ensure_mnt_ready
  ROOT_MNT=/mnt/btrfs-root
  mkdir -p "$ROOT_MNT"

  print_header "Mounting raw Btrfs to create/check subvolumes"
  mount -t btrfs "$BTRFS_PART" "$ROOT_MNT"

  # Set label if empty
  EXISTING_LABEL="$(blkid -s LABEL -o value "$BTRFS_PART" || true)"
  if [[ -z "$EXISTING_LABEL" ]]; then
    echo "Setting Btrfs label to $BTRFS_LABEL"
    btrfs filesystem label "$ROOT_MNT" "$BTRFS_LABEL"
  else
    echo "Btrfs label detected: $EXISTING_LABEL"
  fi

  create_subvol() {
    local name="$1"
    if btrfs subvolume show "$ROOT_MNT/$name" >/dev/null 2>&1; then
      echo "Subvolume exists: $name"
    else
      echo "Creating subvolume: $name"
      btrfs subvolume create "$ROOT_MNT/$name" >/dev/null
    fi
  }

  # Minimal set
  create_subvol "@"
  create_subvol "@home"
  create_subvol "@log"
  create_subvol "@cache"
  create_subvol "@snapshots"

  print_header "Subvolumes now present"
  btrfs subvolume list -p "$ROOT_MNT" || true

  umount "$ROOT_MNT"

  # Final mounts
  mount_opts="rw,noatime,compress=${COMPRESS_OPT},ssd,space_cache=v2,discard=async"

  print_header "Mounting final layout at /mnt"
  mount -o "subvol=@,${mount_opts}" "$BTRFS
