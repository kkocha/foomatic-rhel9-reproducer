#!/usr/bin/env bash
set -euo pipefail

readonly download_url='https://op-drv-ds1.support.ricoh.com/seresBB/servlet/VSORPageDownloadServlet'
readonly object_path='w/bb/pub_j/dr_ut_d/4101013/4101013911/V1122/5243054/Ricoh-Basic-PS-PPDv1.12.2.tar.gz'
readonly install_root='/opt/ricoh'
readonly archive="${install_root}/Ricoh-Basic-PS-PPDv1.12.2.tar.gz"
readonly ppd_root="${install_root}/ppd"
readonly result_root="${install_root}/results"

mkdir -p "$ppd_root" "$result_root"

curl --fail --location --silent --show-error \
    --request POST \
    --data-urlencode "PATH=${object_path}" \
    --data-urlencode 'FWID_U001=WRU001' \
    --data-urlencode 'NWID_U001=' \
    --data-urlencode 'TEST_001=' \
    --data-urlencode 'buttonName=Accept' \
    "$download_url" \
    --output "$archive"

gzip --test "$archive"
tar -xzf "$archive" -C "$ppd_root" --strip-components=1

while IFS= read -r -d '' ppd; do
    name=$(basename "$ppd" .ppd)
    foomatic-hash --ppd \
        "$ppd" \
        "${result_root}/${name}.review" \
        "${result_root}/${name}.hashes"
done < <(find "$ppd_root" -maxdepth 1 -type f -iname '*.ppd' -print0)

test -s "${result_root}/Ricoh-Basic_PS_B_W.hashes"
test -s "${result_root}/Ricoh-Basic_PS_Color.hashes"
