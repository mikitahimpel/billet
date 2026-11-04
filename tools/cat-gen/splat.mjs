// `npm run splat -- <scene> [--only A,B]` or `npm run splat -- --image x.png --out X.ply --height 0.3`.
// Runs make_splat.py with the Python that `npm run setup` built; offline mode skips Hugging Face's access checks,
// since setup already put every weight in generate/weights.
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';

const here = import.meta.dirname;
const python = [join(here, '.venv/Scripts/python.exe'), join(here, '.venv/bin/python')].find(existsSync);
if (!python) {
  console.error('No Python environment in generate/.venv; run `npm run setup` first');
  process.exit(1);
}

const { status } = spawnSync(python, [join(here, 'make_splat.py'), ...process.argv.slice(2)], {
  stdio: 'inherit',
  env: { ...process.env, HF_HUB_OFFLINE: '1', PYTHONIOENCODING: 'utf-8' },
});
process.exit(status ?? 1);
