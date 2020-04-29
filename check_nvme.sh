#!/bin/bash
#
# Simple Nagios check for nvme using nvme-cli
# Original Author: Sam McLeod https://smcleod.net
# https://github.com/sammcj/nagios/blob/master/check_nvme.sh
# Maintainer : Pierre D. - https://dutiko.com/
#
# v2.4 : call nvme smart-log only once, verify lifetime writes - performance drops severely when percentage_used goes above 100%
# v2.3 : check if script is runned as root/sudo, exit with unknown error if not
# v2.2 : add check to detec if nvme disk is detected, exit with unknown error if not
# v2.1 : add checks to detect if nvme-cli is present, exit with unknown error if not
# v1 : Original
#
# Requirements:
# nvme-cli - git clone https://github.com/linux-nvme/nvme-cli
#
# Usage:
# ./check_nvme.sh

# Am I root ?
if [ $(id -u) -ne 0 ] ; then echo "UNKNOWN: please run as root or with sudo" ; exit 3 ; fi

DISKS=$(lsblk -e 11,253 -dn -o NAME | grep nvme)
CRIT=false
WARN=false
MESSAGE=""

command -v nvme >/dev/null 2>&1 || { echo >&2 "UNKNOWN: nvme-cli not found ; please install it" ; exit 3; }
if [ -z "$DISKS" ] ; then echo "UNKNOWN: no nvme disks found"; exit 3; fi

for DISK in $DISKS ; do
  # capture disk SMART log
  LOG=$(nvme smart-log /dev/$DISK)

  # Check for critical_warning
  $(echo "$LOG" | awk 'FNR == 2 && $3 != 0 {exit 1}')
  if [ $? == 1 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has critical warning "
  fi

  # Check media_errors
  $(echo "$LOG" /dev/$DISK | awk 'FNR == 15 && $3 != 0 {exit 1}')
  if [ $? == 1 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has media errors "
  fi

  # Check num_err_log_entries
  $(echo "$LOG" | awk 'FNR == 16 && $3 != 0 {exit 1}')
  if [ $? == 1 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has errors logged "
  fi

  # Check percentage_used
  $(echo "$LOG" | awk 'FNR == 6 {exit $3}')
  PERC=$?
  if [ $PERC -ge 90 ]; then
    CRIT=true
    MESSAGE="$MESSAGE $DISK has $PERC percentage used "
  elif [ $PERC -ge 80 ]; then
    WARN=true
    MESSAGE="$MESSAGE $DISK has $PERC percentage used "
  fi
done

if [ $CRIT = "true" ]; then
  echo "CRITICAL: $MESSAGE"
  exit 2
elif [ $WARN = "true" ]; then
  echo "WARNING: $MESSAGE"
  exit 1
else
  echo "OK $(echo $DISKS | tr -d '\n')"
  exit 0
fi
