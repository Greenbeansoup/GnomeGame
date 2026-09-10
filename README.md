# Gnome Platformer

## Local setup

This project commits its Godot addons under `addons/` so teammates can clone the repo and open it without manually installing Beehave or Aseprite Wizard.

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

Beehave is committed in `addons/beehave`, and the GitHub Actions export workflow uses that committed copy. The old build-time Beehave download step is kept commented out in the workflow as a reference only.