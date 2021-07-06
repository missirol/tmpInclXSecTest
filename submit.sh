#!/bin/bash

OUTTAG=test001

muRFscales=(
  10
  20
  30
  40
  50
  60
  70
  80
  90
 100
 110
 120
 130
 140
 150
 160
)

for muRFscale_i in  "${muRFscales[@]}"; do

  for fsName_i in yc3FS yc4FS yb4FS yb5FS; do

    [ -d "${OUTTAG}"/"${fsName_i}"_muRF_"${muRFscale_i}" ] || sbatch --array="${muRFscale_i}" ./run.sh "${fsName_i}" "${OUTTAG}"/"${fsName_i}"_muRF_"${muRFscale_i}"
  done
done
