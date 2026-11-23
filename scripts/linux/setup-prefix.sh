#!/usr/bin/env bash
# Make a Wine prefix XCL can run in: Proton's own libvkd3d, DXVK's DXGI / D3D11 and a
# vkd3d-proton for D3D12. See docs/linux.md ("Prefix").
#
# usage: setup-prefix.sh <proton-dir> <prefix> <vkd3d-proton-dir>
#   <proton-dir>         Proton Experimental's folder (it holds files/bin/wine), e.g.
#                        "$HOME/.steam/steam/steamapps/common/Proton - Experimental"
#   <prefix>             the prefix to create or update
#   <vkd3d-proton-dir>   a folder with d3d12.dll and d3d12core.dll: the output of
#                        build-vkd3d-proton.sh (<work-dir>/vkd3d-proton-xcl)
#   Only <prefix> is written to.
set -euo pipefail

if [ $# -ne 3 ]; then
    echo "usage: $0 <proton-dir> <prefix> <vkd3d-proton-dir>" >&2
    exit 2
fi
proton=$1
vkd3d=$3
files=$proton/files
[ -x "$files/bin/wine" ] || files=$proton   # a bare "files" folder works too
[ -x "$files/bin/wine" ] || { echo "no files/bin/wine in $proton" >&2; exit 1; }
for f in d3d12.dll d3d12core.dll; do
    [ -f "$vkd3d/$f" ] || { echo "no $f in $vkd3d" >&2; exit 1; }
done
prefix=$(realpath -m -- "$2")
proton_root=$(realpath -e -- "$proton")
case "$prefix/" in
    "$proton_root/"*) echo "prefix must be outside the Proton distribution: $prefix" >&2; exit 1 ;;
esac
mkdir -p "$prefix"

# Wine creates these directories normally; do not follow a redirected prefix into Proton.
check_sys32() {
    local dir=$prefix part
    for part in drive_c windows system32; do
        dir=$dir/$part
        [ ! -L "$dir" ] || { echo "refusing symlink directory: $dir" >&2; exit 1; }
    done
}
check_sys32

export WINEPREFIX=$prefix WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="   # no Mono / Gecko download prompts
"$files/bin/wine" wineboot --init
"$files/bin/wineserver" --wait

sys32=$prefix/drive_c/windows/system32
check_sys32
[ -d "$sys32" ] || { echo "wineboot did not create $sys32" >&2; exit 1; }

# without these, xcl.exe does not start: d3dcompiler_47 -> wined3d -> libvkd3d-shader-1.dll
for source in "$files"/lib/vkd3d/x86_64-windows/libvkd3d-*.dll; do
    cp --remove-destination --no-target-directory "$source" "$sys32/${source##*/}"
done
# with Wine's own dxgi, presenting crashes in wined3d (upstream issue #175)
for f in dxgi.dll d3d11.dll d3d10core.dll; do
    cp --remove-destination --no-target-directory "$files/lib/wine/dxvk/x86_64-windows/$f" "$sys32/$f"
done
for f in d3d12.dll d3d12core.dll; do
    cp --remove-destination --no-target-directory "$vkd3d/$f" "$sys32/$f"
done

"$files/bin/wineserver" --kill 2>/dev/null || true
echo "prefix ready: $prefix"
