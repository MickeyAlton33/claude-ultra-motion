# Web 3D rules — budgets, compression, R3F handoff

Target: the user's Next.js/R3F sites (drei `useGLTF`). Everything below is enforced by
`mesh_check.py --track web --budget <tier>` (numbers kept in sync with `BUDGETS` in that script) and produced by
`web_optimize.sh`.

## Budgets (per asset, after `web_optimize.sh`)
| Tier | Use | Triangles | Max texture | GLB size | Draw calls (primitives) |
|---|---|---|---|---|---|
| **hero** | the one model a page is about (above the fold, rotatable) | ≤ 150k | 2048² | ≤ 4 MB | ≤ 30 |
| **secondary** | supporting models, product grid items | ≤ 50k | 1024² | ≤ 1.5 MB | ≤ 15 |
| **prop** | background / decoration / instanced bits | ≤ 15k | 1024² (512² preferred) | ≤ 0.5 MB | ≤ 5 |
| **ar** | iOS Quick Look / Android Scene Viewer | ≤ 100k | 2048² | ≤ 4 MB | ≤ 20 |
Page total: aim ≤ 300k triangles and ≤ 8 MB of 3D on first load; lazy-load anything below the fold.
Mobile: halve hero textures (1024) if the page has more than one hero-tier model.

## Textures
- Power-of-two sizes (1024, 2048) — mipmaps and KTX2 need them; `mesh_check` warns on NPOT.
- **WebP** (default, no extra tools): small downloads, decoded to RGBA in VRAM (2048² ≈ 21 MB VRAM with mips).
- **KTX2/Basis** (when `ktx` ≥ 4.4 is installed): stays compressed on the GPU (2048² ETC1S ≈ 2–3 MB VRAM). Use for
  hero models on mobile-heavy pages. glTF-Transform picks UASTC for normal maps, ETC1S for colour automatically.
- Channel packing: occlusion (R) + roughness (G) + metalness (B) in one ORM map (glTF standard).
- Base colour must not contain baked shadows/highlights (Meshy textures sometimes do — check under neutral light).
- `--prune-solid-textures` (on by default) turns 1-colour textures into material factors.

## Geometry compression
- **Meshopt** (default): smallest files, also compresses animation & morph targets, fast WASM decode.
  drei `useGLTF` wires the meshopt decoder automatically.
- **Draco** (`--compress draco`): use only if a target loader can't do meshopt; geometry-only, slower decode.
- Quantization (`KHR_mesh_quantization`) is applied by both; `quantize: Skipping TEXCOORD_0; out of [0,1] range`
  is harmless (tiling UVs keep float precision).
- `--simplify` only when over budget: `web_optimize.sh` computes the keep-ratio from the budget (×0.92 margin),
  error 0.001 of extent. Look at the result — simplification kills silhouettes on thin parts first.

## Scene structure
- Real-world meters, +Y up, model facing +Z (glTF front) — Blender's glTF exporter converts from Z-up/−Y-front.
- Origin at the model's base centre; no transforms on the root (apply in Blender before export).
- Default `optimize` flattens & joins meshes (fewer draw calls). Use `--keep-structure` when site code targets named
  nodes (e.g. animating a lid), and `--rigged` for skinned meshes (no flatten/join/simplify — they break skins).
- Lights and cameras: don't ship them in the GLB; the site owns lighting (drei `<Environment>` / `<Stage>`).

## R3F handoff
`web_optimize.sh --jsx` writes `<name>Model.tsx` via pmndrs **gltfjsx 6.5.3** (typed, `--types --shadows`).
Minimal manual version:
```tsx
'use client'
import { Suspense } from 'react'
import { Canvas } from '@react-three/fiber'
import { useGLTF, Environment, ContactShadows, OrbitControls } from '@react-three/drei'

function Model(props: JSX.IntrinsicElements['group']) {
  const { scene } = useGLTF('/models/lamp.web.glb')   // meshopt + draco decoders on by default
  return <primitive object={scene} {...props} />
}
useGLTF.preload('/models/lamp.web.glb')

export default function Hero3D() {
  return (
    <Canvas dpr={[1, 2]} camera={{ position: [0.6, 0.35, 0.9], fov: 30 }} gl={{ antialias: true }}>
      <Suspense fallback={null}>
        <Model />
        <Environment preset="studio" environmentIntensity={0.8} />
        <ContactShadows position={[0, 0, 0]} opacity={0.45} scale={2} blur={2.4} far={1} />
      </Suspense>
      <OrbitControls enablePan={false} minDistance={0.5} maxDistance={2} makeDefault />
    </Canvas>
  )
}
```
- KTX2 textures need the transcoder: `useGLTF(url, true, true, (loader) => loader.setKTX2Loader(ktx2))` with a
  `KTX2Loader().setTranscoderPath('https://cdn.jsdelivr.net/gh/pmndrs/drei-assets/basis/').detectSupport(gl)`.
- Put GLBs in `public/models/`; set `Cache-Control: public, max-age=31536000, immutable` and version the filename.
- Next.js: render the Canvas in a client component, `dynamic(() => import('./Hero3D'), { ssr: false })` + a static
  poster image (a `render.sh --transparent` still) as the LCP element.
- Animations: `const { animations } = useGLTF(url); const { actions } = useAnimations(animations, ref)`; clip names =
  those listed by `mesh_check --track rigged`.

## AR
- iOS Quick Look needs **USDZ** (Blender `wm.usd_export` → .usdz) — `<a rel="ar" href="x.usdz"><img …></a>`.
- Android Scene Viewer / `<model-viewer>` takes the GLB directly (`ar ar-modes="webxr scene-viewer quick-look"`, `ios-src` = USDZ).
- AR models must be at real scale (meters) — the user places them in their room.

## Verification
1. `mesh_check.py out.web.glb --track web --budget hero` → PASS.
2. `gltf-transform inspect out.web.glb` → no unexpected extensions in `extensionsRequired`.
3. Load in the site (or https://gltf-viewer.donmccurdy.com) and check: textures sharp at the intended size, no
   z-fighting, normals not inverted, animation clips play, first-load size in DevTools Network tab.
