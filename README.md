# CoE5SE Installer

One command installs [CoE5SE](https://github.com/musical-pianist/coe5se) and every [Jazzy mod](https://github.com/musical-pianist/coe5se-mods-suite), and copies CoE5SE's file into the game folder. Close the game first. Run it again any time to update.

**Windows:** open the Start menu, type PowerShell, open Windows PowerShell, then paste this and press Enter:

```
irm https://raw.githubusercontent.com/musical-pianist/coe5se-installer/main/install.ps1 | iex
```

**Mac:** open Terminal (in Applications, Utilities), then paste this and press Return:

```
curl -fsSL https://raw.githubusercontent.com/musical-pianist/coe5se-installer/main/install.sh | bash
```

On Mac, the first install leaves one step: in Steam, click the gear on Conquest of Elysium 5's page, then Properties, General, and set Launch Options to `/usr/bin/env DYLD_INSERT_LIBRARIES=coe5se.dylib %command%`. The script prints this step only while Launch Options still need it.

Then start the game. The first time, CoE5SE turns itself on and tells you so. Turn on the Jazzy mods you want on the Mods screen.

You can read both scripts before running them: [install.ps1](install.ps1), [install.sh](install.sh).

The scripts take CoE5SE from [its latest release](https://github.com/musical-pianist/coe5se/releases/latest) and the Jazzy mods from [the mods' repository](https://github.com/musical-pianist/coe5se-mods-suite). To install by hand instead, follow [Install by Hand](https://github.com/musical-pianist/coe5se#install-by-hand).
