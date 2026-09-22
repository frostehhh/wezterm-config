#Requires -Version 5.1
<#
.SYNOPSIS
  theme_picker.ps1 - fzf-backed color theme picker for wezterm-config (Windows).

  Windows counterpart of theme_picker.sh; same three subcommands, same
  contract with modules/colorscheme.lua:

    theme_picker.ps1 list   <masterListPath> <favoritesPath>
    theme_picker.ps1 toggle <favoritesPath> <themeName>
    theme_picker.ps1 run    <masterListPath> <favoritesPath> <query> <prevTheme>

  `run` drives fzf.exe, seeded with the given query text and cursor position
  (derived from prevTheme), with Shift+F (bind key "F") bound to `toggle`
  + a live `reload` — plain `f` stays free for filtering.
  Reports the result back to wezterm via OSC 1337 SetUserVar escapes:
    wezterm_theme_result = "CANCEL" | <base64 theme name>
    wezterm_theme_query  = <base64 typed query text>

  fzf on Windows runs bind/reload commands through cmd.exe by default, so
  `--with-shell` pins it to this same PowerShell so the bind strings below
  (written as PowerShell, calling this script recursively via $PSCommandPath)
  are interpreted consistently.
#>
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("list", "toggle", "run")]
  [string]$Action,

  [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
  [string[]]$Rest
)

$ErrorActionPreference = "Stop"

function Get-ThemeRows {
  # Master list lines are "<name>`t<ansi swatch>", written by
  # modules/colorscheme.lua (only Lua can read WezTerm's builtin color
  # scheme data).
  param([string]$Master, [string]$Favorites)
  if (-not (Test-Path -LiteralPath $Favorites)) { New-Item -ItemType File -Path $Favorites -Force | Out-Null }
  $favSet = @{}
  Get-Content -LiteralPath $Favorites | Where-Object { $_ -ne "" } | ForEach-Object { $favSet[$_] = $true }

  $rows = Get-Content -LiteralPath $Master | Where-Object { $_ -ne "" } | ForEach-Object {
    $parts = $_ -split "`t", 2
    $name = $parts[0]
    $swatch = if ($parts.Count -gt 1) { $parts[1] } else { "" }
    $isFav = $favSet.ContainsKey($name)
    [PSCustomObject]@{
      Marker = $(if ($isFav) { [char]0x2605 } else { " " })
      Name   = $name
      Swatch = $swatch
      Sort   = $(if ($isFav) { 1 } else { 0 })
    }
  }
  $rows | Sort-Object -Property @{Expression = "Sort"; Descending = $true }, @{Expression = "Name"; Descending = $false }
}

function Invoke-List {
  param([string]$Master, [string]$Favorites)
  Get-ThemeRows -Master $Master -Favorites $Favorites | ForEach-Object {
    "{0}`t{1}`t{2}`t{3}" -f $_.Marker, $_.Name, $_.Swatch, $_.Sort
  }
}

function Invoke-Toggle {
  param([string]$Favorites, [string]$Name)
  if (-not (Test-Path -LiteralPath $Favorites)) { New-Item -ItemType File -Path $Favorites -Force | Out-Null }
  $lines = @(Get-Content -LiteralPath $Favorites | Where-Object { $_ -ne "" })
  if ($lines -contains $Name) {
    $lines = @($lines | Where-Object { $_ -ne $Name })
  } else {
    $lines += $Name
  }
  Set-Content -LiteralPath $Favorites -Value $lines
}

function Send-UserVar {
  param([string]$Name, [string]$Value)
  $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
  $esc = [char]27
  $bel = [char]7
  [Console]::Out.Write("$esc]1337;SetUserVar=$Name=$b64$bel")
  [Console]::Out.Flush()
}

function Invoke-Run {
  param([string]$Master, [string]$Favorites, [string]$Query, [string]$Prev)

  $rows = @(Invoke-List -Master $Master -Favorites $Favorites)
  $pos = 1
  if ($Prev) {
    for ($i = 0; $i -lt $rows.Count; $i++) {
      if (($rows[$i] -split "`t")[1] -eq $Prev) { $pos = $i + 1; break }
    }
  }

  $self = $PSCommandPath
  $shellCmd = "powershell -NoProfile -ExecutionPolicy Bypass -Command"
  $toggleBind = "F:execute-silent(& '$self' toggle '$Favorites' {2})+reload(& '$self' list '$Master' '$Favorites')"

  $fzfOutput = $rows -join "`n" | & fzf `
    --ansi `
    --delimiter="`t" --with-nth=1,2,3 --nth=2 `
    --print-query `
    --prompt="Theme> " `
    --header="[Enter] preview  [Shift+F] favorite  [Esc] cancel" `
    --query="$Query" `
    --with-shell="$shellCmd" `
    --bind "load:pos($pos)" `
    --bind $toggleBind

  if ($LASTEXITCODE -ne 0 -or -not $fzfOutput -or $fzfOutput.Count -lt 2) {
    Send-UserVar -Name "wezterm_theme_result" -Value "CANCEL"
    return
  }

  $typedQuery = $fzfOutput[0]
  $selected = ($fzfOutput[1] -split "`t")[1]

  if ([string]::IsNullOrEmpty($selected)) {
    Send-UserVar -Name "wezterm_theme_result" -Value "CANCEL"
  } else {
    Send-UserVar -Name "wezterm_theme_result" -Value $selected
    Send-UserVar -Name "wezterm_theme_query" -Value $typedQuery
  }
}

switch ($Action) {
  "list" { Invoke-List -Master $Rest[0] -Favorites $Rest[1] }
  "toggle" { Invoke-Toggle -Favorites $Rest[0] -Name $Rest[1] }
  "run" { Invoke-Run -Master $Rest[0] -Favorites $Rest[1] -Query $Rest[2] -Prev $Rest[3] }
}
