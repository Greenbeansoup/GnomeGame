# Gnome Platformer

## Local setup

This project commits Aseprite Wizard under `addons/` so teammates can clone the repo with the importer plugin available. Beehave is intentionally not committed; the export workflow pulls a known Beehave version from GitHub during CI builds.

### Aseprite imports

Some sprites are imported from `.aseprite` source files through Aseprite Wizard. Godot must be able to run the Aseprite executable when those assets are imported or reimported.

On Windows, Aseprite Wizard defaults to:

```text
C:\Steam\steamapps\common\Aseprite\aseprite.exe
```

If Aseprite is installed somewhere else, set the path in Godot:

```text
Editor > Editor Settings > Aseprite > General > Command Path
```

The project also enables Aseprite Wizard bake files. When an artist with Aseprite reimports `.aseprite` assets, the generated `.*.ase_bake.res` files beside those sources should be committed so teammates without Aseprite can still use the already-generated imports.

### Beehave

Beehave is vendored during GitHub Actions exports from `bitbrain/beehave` tag `v2.9.3`. For local development, install Beehave into `addons/beehave` yourself if you need to edit or run behavior-tree scenes locally. The folder is ignored so local installs do not get committed accidentally.