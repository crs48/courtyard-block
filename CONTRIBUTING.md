# Contribute to Courtyard Block

A useful contribution can be a reproducible experiment, a better explanation, a source-backed material pack, a usability improvement or a simulation fix. Start by describing the question and the result you expected.

## Set up the game

```sh
git clone https://github.com/crs48/courtyard-block.git
cd courtyard-block
godot --editor --path .
```

Use **Godot 4.7.2** with Compatibility rendering. Press F5 to play the annual lab. Runtime code uses typed GDScript; simulation calculations remain separate from scenes and platform effects, and canonical state stays serializable.

Before submitting simulation or mod API changes, run:

```sh
godot --headless --path . --script tests/run.gd
python3 scripts/check.py
```

The second command also imports the project and checks both playable scenes. Godot sometimes returns success despite script errors; the helper treats those diagnostics as failures.

## Change the website or docs

The website lives in `website/` and uses Astro, Tailwind CSS and Node 24. Documentation is rendered directly from the repository's Markdown files. Edit the source document, rather than a generated copy.

```sh
npm ci --prefix website
npm run dev --prefix website
```

Open `http://localhost:4321/courtyard-block/`. For the embedded game and search, export and build the full site as described in [website and publishing](docs/publishing.md). Run `npm run check --prefix website` and `npm run build --prefix website` before submitting website changes.

## Make a reviewable change

1. Create a branch for one problem or experiment.
2. Explain the behavior and its boundaries. For simulation changes, include a small fixture or experiment that distinguishes correct from incorrect behavior.
3. Record provenance, units, uncertainty and redistribution permissions for new data. Keep synthetic assumptions labeled.
4. Preserve replay compatibility, or explicitly bump the model runtime identifier when numerical behavior becomes incompatible. Do not silently reinterpret saved experiments.
5. Use conventional commits with a concise subject and bulleted details. Open a pull request with what changed and the checks you ran.

The automated workflow checks the game, builds the browser export and checks website links. Pull requests do not deploy; pushes to `main` publish GitHub Pages.

## License

Contributions to the project's original code and content are under the [MIT license](LICENSE), copyright Christopher Smothers. Include attribution and applicable licenses for third-party material. The [third-party notices](THIRD_PARTY_NOTICES.md) describe the components distributed with the site and game.
