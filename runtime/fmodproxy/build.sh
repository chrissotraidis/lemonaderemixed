#!/bin/bash
# Build the FMOD proxy (fmod.dll, 32-bit Windows) with Homebrew LLVM.
set -euo pipefail
cd "$(dirname "$0")"
LLVM=${LLVM:-/opt/homebrew/opt/llvm/bin}
OUT=build
mkdir -p $OUT
python3 gen.py exports.txt $OUT
cat > $OUT/kernel32.def <<'DEF'
LIBRARY kernel32.dll
EXPORTS
LoadLibraryA@4
GetProcAddress@8
CreateThread@24
Sleep@4
CreateFileA@28
ReadFile@20
WriteFile@20
CloseHandle@4
GetModuleFileNameA@12
DEF
$LLVM/llvm-dlltool -m i386 -k -d $OUT/kernel32.def -l $OUT/kernel32.lib
FLAGS="--target=i686-pc-windows-msvc -O2 -ffreestanding -fno-builtin -fno-stack-protector -fno-exceptions -I. -I$OUT"
$LLVM/clang $FLAGS -c fmodproxy.c -o $OUT/fmodproxy.o
$LLVM/clang $FLAGS -c $OUT/thunks.c -o $OUT/thunks.o
${LLD_LINK:-lld-link} /dll /nodefaultlib /entry:DllMain /def:$OUT/fmod.def /out:$OUT/fmod.dll /safeseh:no /base:0x0f800000 \
    $OUT/fmodproxy.o $OUT/thunks.o $OUT/kernel32.lib
echo "$OUT/fmod.dll"
