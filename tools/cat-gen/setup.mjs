// `npm run setup`: builds everything `npm run splat` needs, starting from Node and uv only. Safe to rerun.
// Apple Silicon runs Idol on MLX through mlx-vlm; elsewhere the vendored idol-sdk runs on PyTorch, with CUDA when
// uv finds an NVIDIA driver. Weights go to generate/weights, about 5 GB, none of them gated.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

// Idol landed in mlx-vlm after its latest release (0.7.11), so pin the commit that added it.
const MLX_VLM = 'mlx-vlm @ git+https://github.com/Blaizzy/mlx-vlm@92e07596b921af43683a0bd1bc9b6b602bc7cdce';

// Idol's own weights, plus open copies of its two image encoders: DINOv3 from the MLX repackaging of Idol (DINOv3
// License) and the FLUX.2 VAE from FLUX.2 [klein] (Apache-2.0), instead of the gated originals in its config.
const FETCH_WEIGHTS = `
import json, sys
from pathlib import Path
from huggingface_hub import snapshot_download

root = Path(sys.argv[1])
snapshot_download('speridlabs/idol', local_dir=root / 'idol', allow_patterns=['config.json', '*.safetensors'])
snapshot_download('ddalcu/Idol-MLX-Serve-8bit', local_dir=root, allow_patterns=['dinov3/*'])
snapshot_download('black-forest-labs/FLUX.2-klein-4B', local_dir=root / 'flux2', allow_patterns=['vae/*'])

config_path = root / 'idol' / 'config.json'
config = json.loads(config_path.read_text())
config['image_encoders'] = {'dinov3': (root / 'dinov3').as_posix(), 'flux2_vae': (root / 'flux2').as_posix()}
config_path.write_text(json.dumps(config, indent=2))
`;

const here = import.meta.dirname;
const venv = join(here, '.venv');
const mlx = process.platform === 'darwin' && process.arch === 'arm64';

function run(command, args) {
  console.log(`> ${command} ${args.join(' ')}`);
  const { status, error } = spawnSync(command, args, { stdio: 'inherit' });
  if (error || status !== 0) {
    console.error(error?.code === 'ENOENT' ? `${command} not found` : `${command} failed`);
    process.exit(status || 1);
  }
}

if (spawnSync('uv', ['--version']).error) {
  console.error('Setup needs uv: https://docs.astral.sh/uv/getting-started/installation/');
  process.exit(1);
}
if (!existsSync(venv)) run('uv', ['venv', venv, '--python', '3.12']);
const python = join(venv, process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');

if (mlx) run('uv', ['pip', 'install', '--python', python, MLX_VLM, 'plyfile', 'pillow']);
else run('uv', ['pip', 'install', '--python', python, '--torch-backend=auto', '-e', join(here, 'idol-sdk')]);

run(python, ['-c', FETCH_WEIGHTS, join(here, 'weights')]);
console.log(`\nReady (${mlx ? 'MLX' : 'PyTorch'}). Try: npm run splat -- nooki`);
