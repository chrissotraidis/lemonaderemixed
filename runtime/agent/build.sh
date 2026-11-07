#!/bin/bash
# Build the in-game agent (fmod.dll, 32-bit Windows). mac/bundle.sh passes
# LLVM=<llvm-mingw>/bin; by default this uses Homebrew LLVM.
set -euo pipefail
cd "$(dirname "$0")"
LLVM=${LLVM:-/opt/homebrew/opt/llvm/bin}
LLD_LINK=${LLD_LINK:-$LLVM/lld-link}
OUT=build
mkdir -p $OUT
python3 gen.py exports.txt $OUT

implib() {  # implib NAME FUNCTION@BYTES...
  local name=$1; shift
  { echo "LIBRARY $name.dll"; echo EXPORTS; printf '%s\n' "$@"; } > $OUT/$name.def
  $LLVM/llvm-dlltool -m i386 -k -d $OUT/$name.def -l $OUT/$name.lib
}
implib kernel32 LoadLibraryA@4 GetProcAddress@8 CreateThread@24 Sleep@4 CreateFileA@28 ReadFile@20 \
  WriteFile@20 CloseHandle@4 GetModuleFileNameA@12 CreateFileMappingA@24 MapViewOfFile@20
implib user32 FindWindowA@8 GetDC@4 ReleaseDC@8
implib gdi32 CreateCompatibleDC@4 CreateDIBSection@24 SelectObject@8 BitBlt@36 GdiFlush@0

FLAGS="--target=i686-pc-windows-msvc -O2 -ffreestanding -fno-builtin -fno-stack-protector -fno-exceptions -I. -I$OUT"
for src in audio frametap; do $LLVM/clang $FLAGS -c $src.c -o $OUT/$src.o; done
$LLVM/clang $FLAGS -c $OUT/thunks.c -o $OUT/thunks.o
"$LLD_LINK" /dll /nodefaultlib /entry:DllMain /def:$OUT/fmod.def /out:$OUT/fmod.dll /safeseh:no /base:0x0f800000 \
    $OUT/audio.o $OUT/frametap.o $OUT/thunks.o $OUT/kernel32.lib $OUT/user32.lib $OUT/gdi32.lib
echo "$OUT/fmod.dll"
