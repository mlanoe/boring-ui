#!/usr/bin/env bash
# Builds the Todo window for `--target wgpu` and runs it (Escape quits).
#
# STOPGAPS, until the compiler does it (see README.md, "Window"):
#   - a Screen program's generated crate drops the module-level constants of the modules it imports (they are
#     emitted as locals of `main`, invisible to the functions that use them): they are put back at module level;
#   - the Screen `main` builds the kernel with `TileKernel::new(device, queue)` and never runs its `init`, so the
#     constructor arguments of main.br are ignored and every buffer stays empty (a 1-pixel window): the init
#     (upload of the encoded display list, atlas and sizes) is added after that line, the way the host code of
#     `rasterizeTiled` does it.
set -euo pipefail

BORING="${BORING:-boring}"
cd "$(dirname "${BASH_SOURCE[0]}")"

rm -rf main_wgpu
"$BORING" build --target wgpu >/dev/null
cd main_wgpu
for name in GLYPH_COLUMNS GLYPH_ROWS GLYPH_TEXELS MAX_DEPTH UNBOUNDED CHARWIDTH; do
    sed -i.bak -E "/^    let $name: [a-z0-9]+ = [0-9.]+;\$/d" src/main.rs
done
rm -f src/main.rs.bak
cat > init.rs.snippet <<'SNIPPET'
    let mut k = TileKernel::new(std::sync::Arc::clone(&device), std::sync::Arc::clone(&queue));
    {
        let encoded = todoFrame();
        k.copy_f_to_device(&encoded.f.iter().map(|&x| x as f32).collect::<Vec<f32>>());
        k.copy_u_to_device(&encoded.u.iter().map(|&x| x as u32).collect::<Vec<u32>>());
        k.copy_atlas_to_device(&atlasWords().iter().map(|&x| x as u32).collect::<Vec<u32>>());
        k.count = (encoded.count) as i32;
        k.width = 640;
        k.height = 360;
        k.chunks = ((encoded.count + 255) / 256) as i32;
        k.copy_out_to_device(&vec![0u32; 640 * 360]);
    }
SNIPPET
awk 'FNR==NR { snippet = snippet $0 "\n"; next }
     /^    let k = TileKernel::new\(std::sync::Arc::clone\(&device\), std::sync::Arc::clone\(&queue\)\);$/ { printf "%s", snippet; next }
     { print }' init.rs.snippet src/main.rs > src/main.rs.new
mv src/main.rs.new src/main.rs
rm -f init.rs.snippet
{
    echo "const UNBOUNDED: f64 = 1000000000.0;"
    echo "const CHARWIDTH: f64 = 8.0;"
    echo "const GLYPH_COLUMNS: isize = 6;"
    echo "const GLYPH_ROWS: isize = 8;"
    echo "const GLYPH_TEXELS: isize = 48;"
    echo "const MAX_DEPTH: isize = 4;"
    cat src/main.rs
} > src/main.rs.new
mv src/main.rs.new src/main.rs
RUSTFLAGS="-A warnings" cargo run --release -q
