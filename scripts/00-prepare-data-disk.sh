#!/usr/bin/env bash
set -euo pipefail

echo "==> Preparing Harbor data disk"

fail() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

ensure_safe_disk_target() {
  local dev="$1"
  local dev_type root_src root_parent

  [[ -b "$dev" ]] || fail "DATA_DISK_DEVICE=${dev} is not a block device."

  dev_type="$(lsblk -dn -o TYPE "$dev" 2>/dev/null || true)"
  [[ "$dev_type" == "disk" ]] || fail "DATA_DISK_DEVICE=${dev} must reference a whole disk device, not a partition."

  root_src="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
  if [[ -n "$root_src" && -b "$root_src" ]]; then
    root_parent="/dev/$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)"
    if [[ "$dev" == "$root_src" || "$dev" == "$root_parent" ]]; then
      fail "Refusing to format ${dev}: it appears to be the OS/root disk path (${root_src})."
    fi
  fi

  if lsblk -nrpo NAME,MOUNTPOINT "$dev" | awk 'NF > 1 && $2 != "" {found=1} END {exit found ? 0 : 1}'; then
    fail "Refusing to format ${dev}: one or more partitions are currently mounted."
  fi
}

[[ "${PREPARE_DATA_DISK}" == "true" ]] || { echo "INFO: PREPARE_DATA_DISK=false; skipping."; exit 0; }

mkdir -p "${HARBOR_DATA_VOLUME}"

if findmnt -rn "${HARBOR_DATA_VOLUME}" >/dev/null 2>&1; then
  echo "INFO: ${HARBOR_DATA_VOLUME} is already mounted."
else
  if [[ -n "${DATA_DISK_DEVICE}" ]]; then
    [[ -b "${DATA_DISK_DEVICE}" ]] || fail "DATA_DISK_DEVICE=${DATA_DISK_DEVICE} is not a block device."

    if [[ "${FORMAT_DATA_DISK}" == "true" ]]; then
      ensure_safe_disk_target "${DATA_DISK_DEVICE}"
      echo "WARNING: This will DESTROY data on ${DATA_DISK_DEVICE} and create one ${DATA_DISK_FS} partition mounted at ${HARBOR_DATA_VOLUME}."
      lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,MODEL "${DATA_DISK_DEVICE}" || true
      read -r -p "Type FORMAT-${DATA_DISK_DEVICE} to continue: " confirm
      [[ "$confirm" == "FORMAT-${DATA_DISK_DEVICE}" ]] || fail "Data disk format was not confirmed."

      command -v parted >/dev/null || fail "parted is required to format the data disk. Install it from the OS image/packages first."
      command -v mkfs."${DATA_DISK_FS}" >/dev/null || fail "mkfs.${DATA_DISK_FS} is required."

      wipefs -a "${DATA_DISK_DEVICE}"
      parted -s "${DATA_DISK_DEVICE}" mklabel gpt
      parted -s "${DATA_DISK_DEVICE}" mkpart primary "${DATA_DISK_FS}" 0% 100%
      partprobe "${DATA_DISK_DEVICE}" || true
      sleep 2

      part="${DATA_DISK_DEVICE}1"
      if [[ ! -b "$part" && "${DATA_DISK_DEVICE}" =~ nvme|mmcblk ]]; then
        part="${DATA_DISK_DEVICE}p1"
      fi
      [[ -b "$part" ]] || fail "Could not find new partition for ${DATA_DISK_DEVICE}."
      mkfs."${DATA_DISK_FS}" -F -L "${DATA_DISK_LABEL}" "$part"
    fi

    # Mount by label if possible, otherwise by the first filesystem partition on DATA_DISK_DEVICE.
    source_spec="LABEL=${DATA_DISK_LABEL}"
    if ! blkid -L "${DATA_DISK_LABEL}" >/dev/null 2>&1; then
      part="${DATA_DISK_DEVICE}1"
      if [[ ! -b "$part" && "${DATA_DISK_DEVICE}" =~ nvme|mmcblk ]]; then
        part="${DATA_DISK_DEVICE}p1"
      fi
      [[ -b "$part" ]] || fail "No partition found on ${DATA_DISK_DEVICE}. Set FORMAT_DATA_DISK=true if this is a blank disk."
      source_spec="UUID=$(blkid -s UUID -o value "$part")"
    fi

    grep -q "[[:space:]]${HARBOR_DATA_VOLUME}[[:space:]]" /etc/fstab || \
      echo "${source_spec} ${HARBOR_DATA_VOLUME} ${DATA_DISK_FS} defaults,nofail 0 2" >> /etc/fstab

    [[ "${MOUNT_DATA_DISK}" == "true" ]] && mount "${HARBOR_DATA_VOLUME}"
  else
    echo "INFO: No DATA_DISK_DEVICE set. Current block devices:" >&2
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL,MODEL >&2 || true
    fail "${HARBOR_DATA_VOLUME} is not mounted. Set DATA_DISK_DEVICE=/dev/<disk> and optionally FORMAT_DATA_DISK=true in config/harbor.env."
  fi
fi

if ! findmnt -rn "${HARBOR_DATA_VOLUME}" >/dev/null 2>&1; then
  fail "${HARBOR_DATA_VOLUME} is still not mounted."
fi

data_size_gb="$(df -BG "${HARBOR_DATA_VOLUME}" | awk 'NR==2 {gsub(/G/,"",$2); print $2}')"
data_free_gb="$(df -BG "${HARBOR_DATA_VOLUME}" | awk 'NR==2 {gsub(/G/,"",$4); print $4}')"
if (( data_size_gb < 450 )); then
  warn "${HARBOR_DATA_VOLUME} size is ${data_size_gb} GB; expected roughly 500 GB for this deployment."
fi
if (( data_free_gb < 400 )); then
  warn "${HARBOR_DATA_VOLUME} free space is ${data_free_gb} GB; registry growth headroom may be weak."
fi

install -d -m 0755 "${HARBOR_DATA_VOLUME}"
echo "INFO: data volume ready: ${HARBOR_DATA_VOLUME} ($(df -h "${HARBOR_DATA_VOLUME}" | awk 'NR==2 {print $2 " total, " $4 " free"}'))."
