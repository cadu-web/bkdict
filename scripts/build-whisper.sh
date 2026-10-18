#!/bin/bash
# Compila o whisper-server do whisper.cpp (estático, universal Intel + Apple Silicon, com Metal embutido) e empacota
# em dist/whisper-server-macos.tgz, o arquivo que o app baixa no primeiro uso (ver Dependency.whisper).
# O whisper.cpp não publica binário para macOS, por isso a gente compila. Requer: brew install cmake.
#
# Ao mudar WHISPER_VERSION, publique o pacote numa release nova (como pré-lançamento, para não virar a "latest" que a
# atualização automática consulta) e atualize a URL e o SHA-256 em Sources/Bkdict/Dependency.swift:
#   gh release create whisper-$WHISPER_VERSION dist/whisper-server-macos.tgz -R cadu-web/bkdict --prerelease
set -euo pipefail
cd "$(dirname "$0")/.."

WHISPER_VERSION=v1.9.5
SRC=.build/whisper.cpp-$WHISPER_VERSION
OUT=dist/whisper-server-macos.tgz

command -v cmake >/dev/null || { echo "cmake não encontrado: brew install cmake" >&2; exit 1; }
[[ -d "$SRC" ]] || git clone -q --depth 1 --branch "$WHISPER_VERSION" https://github.com/ggml-org/whisper.cpp.git "$SRC"

# Uma compilação por arquitetura, juntadas com lipo: num build universal único o cmake não reconhece a CPU e cai para
# código genérico. Os Macs Intel que rodam o macOS 14 têm todos AVX2, FMA e F16C.
build() {
    local arch=$1; shift
    cmake -S "$SRC" -B "$SRC/build-$arch" -Wno-author -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_SDL2=OFF \
        -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF \
        -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 "$@" >/dev/null
    # Só os erros: os avisos de compilação do whisper.cpp são deles e não mudam nada aqui.
    cmake --build "$SRC/build-$arch" --target whisper-server -j "$(sysctl -n hw.ncpu)" 2>&1 | grep -E "error" || true
    [[ -x "$SRC/build-$arch/bin/whisper-server" ]] || { echo "falhou a compilação para $arch" >&2; exit 1; }
}
build arm64
build x86_64 -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON

STAGE="$(mktemp -d)"
lipo -create "$SRC/build-arm64/bin/whisper-server" "$SRC/build-x86_64/bin/whisper-server" -output "$STAGE/whisper-server"
cp "$SRC/LICENSE" "$STAGE/LICENSE-whisper.cpp"
codesign --force --sign - "$STAGE/whisper-server"
mkdir -p dist
tar -czf "$OUT" -C "$STAGE" whisper-server LICENSE-whisper.cpp
echo "Packaged $OUT ($(du -h "$OUT" | cut -f1), $(lipo -archs "$STAGE/whisper-server"))"
echo "SHA-256 $(shasum -a 256 "$OUT" | cut -d" " -f1)"
rm -rf "$STAGE"
