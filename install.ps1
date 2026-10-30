# Installs CoE5SE (its latest release, from github.com/musical-pianist/coe5se), the Jazzy mods
# (the main branch of github.com/musical-pianist/coe5se-mods-suite), or both, on Windows. It asks which.
# Run it in PowerShell with:
#   irm https://raw.githubusercontent.com/musical-pianist/coe5se-installer/main/install.ps1 | iex
# It puts each mod folder in %APPDATA%\coe5\mods (replacing an older copy) and, with CoE5SE,
# glu32.dll in the game folder, next to CoE5.exe. It changes nothing else.
# $env:COE5_INSTALL_CHOICE = 1, 2 or 3 answers the question without asking (tests).
# Everything runs in one script block, so an error never closes the window.
& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

  $archiveUrl = if ($env:COE5_SUITE_ZIP_URL) { $env:COE5_SUITE_ZIP_URL } else { 'https://github.com/musical-pianist/coe5se-mods-suite/archive/refs/heads/main.zip' }
  $latestUrl = 'https://api.github.com/repos/musical-pianist/coe5se/releases/latest'
  $modsDir = if ($env:COE5_MODS_DIR) { $env:COE5_MODS_DIR } else { Join-Path $env:APPDATA 'coe5\mods' }
  $appId = '1606340'
  $allMods = @('JazzyGamePresets', 'JazzyHotkeys', 'JazzyRestart', 'JazzyUITweaks', 'JazzyCheats')

  # Each Steam library holds the game if it has the game's app manifest.
  function Find-GameDir {
    $steam = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue
    if (-not $steam) { return $null }
    $libraries = @($steam.SteamPath)
    $libraryList = Join-Path $steam.SteamPath 'steamapps\libraryfolders.vdf'
    if (Test-Path $libraryList) {
      foreach ($match in [regex]::Matches((Get-Content -Raw $libraryList), '"path"\s*"([^"]*)"')) {
        $libraries += $match.Groups[1].Value -replace '\\\\', '\'
      }
    }
    foreach ($library in $libraries) {
      $manifest = Join-Path $library "steamapps\appmanifest_$appId.acf"
      if (-not (Test-Path $manifest)) { continue }
      $installDir = [regex]::Match((Get-Content -Raw $manifest), '"installdir"\s*"([^"]*)"')
      if (-not $installDir.Success) { continue }
      $gameDir = Join-Path $library "steamapps\common\$($installDir.Groups[1].Value)"
      if (Test-Path (Join-Path $gameDir 'CoE5.exe')) { return $gameDir }
    }
    return $null
  }

  # An arrow-key menu; 1, 2 or 3 picks directly. Without a console to read keys from (input redirected),
  # it asks for the number instead. Returns '1', '2' or '3'.
  function Select-Choice {
    $options = @('Script Extender and all mods', 'Script Extender only', 'Mods only')
    Write-Host 'What do you want to install?'
    Write-Host ''
    if ([Console]::IsInputRedirected) {
      for ($i = 0; $i -lt 3; $i++) { Write-Host "  $($i + 1)) $($options[$i])" }
      while ($true) {
        $answer = (Read-Host 'Type 1, 2 or 3, then press Enter').Trim()
        if ($answer -in @('1', '2', '3')) { return $answer }
        Write-Host "That's not 1, 2 or 3."
      }
    }
    $color = -not $env:NO_COLOR
    foreach ($o in $options) { Write-Host "  $o" }
    Write-Host ''
    Write-Host 'Up and Down to move, Enter to pick, Ctrl-C to quit'
    $top = [Console]::CursorTop - 5
    $width = [Math]::Max([Console]::WindowWidth - 1, 40)
    $selected = 0
    $cursor = [Console]::CursorVisible
    try {
      [Console]::CursorVisible = $false
      while ($true) {
        for ($i = 0; $i -lt 3; $i++) {
          [Console]::SetCursorPosition(0, $top + $i)
          if ($i -eq $selected) {
            if ($color) { Write-Host ("> " + $options[$i]).PadRight($width) -ForegroundColor Cyan -NoNewline } else { Write-Host ("> " + $options[$i]).PadRight($width) -NoNewline }
          } else { Write-Host ("  " + $options[$i]).PadRight($width) -NoNewline }
        }
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'UpArrow' -and $selected -gt 0) { $selected-- }
        elseif ($key.Key -eq 'DownArrow' -and $selected -lt 2) { $selected++ }
        elseif ($key.Key -eq 'Enter') { break }
        elseif ($key.KeyChar -in @('1', '2', '3')) { $selected = [int]"$($key.KeyChar)" - 1; break }
      }
      for ($i = 0; $i -lt 3; $i++) {
        [Console]::SetCursorPosition(0, $top + $i)
        if ($i -eq $selected) { Write-Host ("> " + $options[$i]).PadRight($width) -NoNewline } else { Write-Host ("  " + $options[$i]).PadRight($width) -NoNewline }
      }
      # The hint line goes; what the script prints next starts there.
      [Console]::SetCursorPosition(0, $top + 4)
      Write-Host (' ' * $width) -NoNewline
      [Console]::SetCursorPosition(0, $top + 4)
    } finally {
      [Console]::CursorVisible = $cursor
    }
    return [string]($selected + 1)
  }

  $workDir = Join-Path $env:TEMP ('coe5se_install_' + [guid]::NewGuid().ToString('N'))
  try {
    $gameDir = if ($env:COE5_GAME_DIR) { $env:COE5_GAME_DIR } else { Find-GameDir }
    if (-not $gameDir) { throw "couldn't find Conquest of Elysium 5 in Steam. Is it installed?" }
    $gameDir = [IO.Path]::GetFullPath($gameDir)
    $gameExe = Join-Path $gameDir 'CoE5.exe'
    if (-not (Test-Path $gameExe)) { throw "no CoE5.exe in $gameDir" }

    $running = Get-Process -Name CoE5 -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $gameExe }
    if ($running) { throw 'Conquest of Elysium 5 is running. Close the game, then paste the command again.' }

    $choice = $env:COE5_INSTALL_CHOICE
    if (-not $choice) { $choice = Select-Choice }
    if ($choice -notin @('1', '2', '3')) { throw 'COE5_INSTALL_CHOICE must be 1, 2 or 3.' }
    $withCore = $choice -ne '3'
    $mods = if ($choice -eq '2') { @() } else { $allMods }

    Write-Host 'Downloading...'
    New-Item -ItemType Directory -Path $workDir | Out-Null
    try {
      if ($withCore) {
        $coreUrl = if ($env:COE5SE_ZIP_URL) { $env:COE5SE_ZIP_URL } else {
          $latest = Invoke-RestMethod -Uri $latestUrl -UseBasicParsing
          ($latest.assets | Where-Object { $_.name -like 'CoE5SE-*.zip' } | Select-Object -First 1).browser_download_url
        }
        if (-not $coreUrl) { throw "couldn't find CoE5SE's latest release. Check your internet connection and try again." }
        Invoke-WebRequest -Uri $coreUrl -OutFile (Join-Path $workDir 'coe5se.zip') -UseBasicParsing
      }
      if ($mods.Count) { Invoke-WebRequest -Uri $archiveUrl -OutFile (Join-Path $workDir 'suite.zip') -UseBasicParsing }
    } catch {
      if ($_.Exception.Message -like "couldn't find*") { throw }
      throw 'the download failed. Check your internet connection and try again.'
    }
    try {
      if ($withCore) { Expand-Archive -Path (Join-Path $workDir 'coe5se.zip') -DestinationPath (Join-Path $workDir 'coe5se') }
      if ($mods.Count) { Expand-Archive -Path (Join-Path $workDir 'suite.zip') -DestinationPath (Join-Path $workDir 'suite') }
    } catch {
      throw 'the download was damaged. Try again.'
    }
    # CoE5SE's zip holds its CoE5SE folder; the suite's archive holds one folder with every Jazzy mod in it.
    $sources = [ordered]@{}
    if ($withCore) { $sources['CoE5SE'] = Join-Path $workDir 'coe5se\CoE5SE' }
    if ($mods.Count) {
      $suiteDir = (Get-ChildItem -Directory (Join-Path $workDir 'suite') | Select-Object -First 1).FullName
      foreach ($mod in $mods) { $sources[$mod] = Join-Path $suiteDir $mod }
    }
    foreach ($mod in $sources.Keys) {
      if (-not (Test-Path (Join-Path $sources[$mod] "$mod.c5m"))) { throw "the download has no $mod folder. Try again later." }
    }
    if ($withCore) {
      $stub = Join-Path $sources['CoE5SE'] 'glu32.dll'
      if (-not (Test-Path $stub)) { throw 'the download has no glu32.dll. Try again later.' }
    }

    try { New-Item -ItemType Directory -Path $modsDir -Force | Out-Null } catch { throw "couldn't create the mods folder $modsDir." }
    foreach ($mod in $sources.Keys) {
      # Copy next to the old folder first, so a failed copy leaves the old one in place.
      $target = Join-Path $modsDir $mod
      $staging = Join-Path $modsDir ".$mod.installing"
      try {
        if (Test-Path $staging) { Remove-Item -Recurse -Force $staging }
        Copy-Item -Recurse $sources[$mod] $staging
      } catch { throw "couldn't copy $mod into $modsDir. Is the disk full?" }
      # Each folder's README.md is for the repo's page; the game never reads it.
      Remove-Item (Join-Path $staging 'README.md') -Force -ErrorAction SilentlyContinue
      try {
        if (Test-Path $target) { Remove-Item -Recurse -Force $target }
        Rename-Item $staging $mod
      } catch { throw "couldn't replace the old $mod folder in $modsDir. Close any window showing it and try again." }
      Write-Host "Installed $mod in $target"
    }

    if ($withCore) {
      $stubStaging = Join-Path $gameDir '.glu32.dll.installing'
      try {
        Copy-Item $stub $stubStaging -Force
        Move-Item $stubStaging (Join-Path $gameDir 'glu32.dll') -Force
      } catch { throw "couldn't copy glu32.dll into the game folder $gameDir. Close the game and try again." }
      Write-Host "Installed glu32.dll in $gameDir"
    }

    # The ending: what was installed is done; the steps left are numbered, the last one the player's.
    Write-Host ''
    if ($env:NO_COLOR) { Write-Host 'Install finished!' } else { Write-Host 'Install finished!' -ForegroundColor Green }
    Write-Host ''
    if ($withCore) { Write-Host '1. Start the game. The first time, CoE5SE turns itself on and tells you so.' } else { Write-Host '1. Start the game.' }
    if ($mods.Count) { Write-Host '2. Turn on the mods you want on the Mods screen.' }
  } catch {
    # Every message thrown above is a plain sentence; anything else is unexpected.
    $message = $_.Exception.Message
    if ($_.FullyQualifiedErrorId -ne $message) {
      $message = 'something unexpected went wrong. Nothing more was changed. Try again, or report it on github.com/musical-pianist/coe5se-installer.'
    }
    Write-Host "Install stopped: $message" -ForegroundColor Red
  } finally {
    if (Test-Path $workDir) { Remove-Item -Recurse -Force $workDir -ErrorAction SilentlyContinue }
  }
}
