# CoE5SE Installer

`install.ps1` (Windows) and `install.sh` (Mac) ask what to install: the Script Extender and all mods, the Script Extender only, or the mods only. They take [CoE5SE](https://github.com/musical-pianist/coe5se) from its latest release and the [Jazzy mods](https://github.com/musical-pianist/coe5se-mods-suite) from the mods' repository, and put each in your mods folder, replacing older copies. With CoE5SE, they copy one file into the game folder: `glu32.dll` next to `CoE5.exe`, or `coe5se.dylib` next to `coe5_mac`. They change nothing else, and stop if the game is running.

The commands that run them are in CoE5SE's [Install](https://github.com/musical-pianist/coe5se#install).
