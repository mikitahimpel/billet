# Notices

The MIT licence in [LICENSE](LICENSE) covers this project's own code. These parts are not covered by
it:

- `apps/ios` (its code, scenes, cat, rooms, shop items, icon and tools) and `tools/cat-gen` (including
  the reference pictures in `tools/cat-gen/refs`) are used with their author's permission, which
  includes publication in this repository. All rights stay with their author. The cat's files and
  the shop thumbnails are kept byte for byte (`apps/ios/nooki-cat.sha256`, checked in CI).
- `tools/cat-gen/idol-sdk` is the inference code of [Idol](https://huggingface.co/speridlabs/idol)
  by Speridlabs, under the Apache License 2.0; its `LICENSE` is kept beside it. No model weights
  are in the repository; the setup script downloads them.
