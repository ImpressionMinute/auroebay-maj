# Mise à jour d'AurOEBay sur Windows (https://auroebay.netlify.app/mise-a-jour).
# Remplace les fichiers du dossier AurOEBay que Chrome utilise, AU MÊME ENDROIT.
# Tes données (produits, fournisseurs, ventes, licence) sont rangées dans
# Chrome, pas dans ce dossier : elles ne sont jamais touchées.
# Tout est dans une fonction : rien ne s'exécute si le téléchargement est coupé.

function Update-AurOEBay {
  $ErrorActionPreference = 'Stop'
  $site = if ($env:AUROEBAY_SITE) { $env:AUROEBAY_SITE } else { 'https://raw.githubusercontent.com/ImpressionMinute/auroebay-maj/main' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  function Ok($t) { Write-Host ''; Write-Host $t -ForegroundColor Green }
  function Err($t) { Write-Host ''; Write-Host $t -ForegroundColor Red }

  Write-Host ''
  Write-Host "Mise à jour d'AurOEBay…" -ForegroundColor Yellow
  Write-Host ''

  # Version d'un dossier AurOEBay ($null si ce n'en est pas un).
  function FolderVersion($dir) {
    $m = Join-Path $dir 'manifest.json'
    if (-not (Test-Path -LiteralPath $m)) { return $null }
    $text = [IO.File]::ReadAllText($m)
    if ($text -notmatch '"name"\s*:\s*"AurOEBay"') { return $null }
    if ($text -match '"version"\s*:\s*"([0-9.]+)"') { return $Matches[1] }
    return $null
  }
  function Older($a, $b) { return ([version]$a) -lt ([version]$b) }

  # 1. Les dossiers AurOEBay que Chrome utilise (noté dans ses réglages).
  $found = New-Object System.Collections.Generic.List[string]
  $chrome = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
  if (Test-Path -LiteralPath $chrome) {
    Get-ChildItem -LiteralPath $chrome -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      foreach ($name in 'Secure Preferences', 'Preferences') {
        $f = Join-Path $_.FullName $name
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $raw = [IO.File]::ReadAllText($f)
        foreach ($m in [regex]::Matches($raw, '"path":"((?:[^"\\]|\\.)*)"')) {
          try { $p = ('"' + $m.Groups[1].Value + '"') | ConvertFrom-Json } catch { continue }
          if ($p -and (FolderVersion $p) -and -not $found.Contains($p)) { $found.Add($p) }
        }
      }
    }
  }
  # Sinon : recherche dans les dossiers habituels.
  if ($found.Count -eq 0) {
    $places = @([Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), (Join-Path $env:USERPROFILE 'Downloads'), $env:USERPROFILE)
    foreach ($place in $places) {
      if (-not $place -or -not (Test-Path -LiteralPath $place)) { continue }
      Get-ChildItem -LiteralPath $place -Filter manifest.json -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | ForEach-Object {
        $d = $_.DirectoryName
        if ((FolderVersion $d) -and -not $found.Contains($d)) { $found.Add($d) }
      }
    }
  }
  # Jamais le dossier de développement d'AurOEBay.
  $targets = @($found | Where-Object { -not ((Test-Path -LiteralPath (Join-Path (Split-Path $_) 'package.json')) -and (Test-Path -LiteralPath (Join-Path (Split-Path $_) 'src'))) })
  if ($targets.Count -eq 0) {
    Err 'Je ne trouve pas ton dossier AurOEBay.'
    Write-Host "Suis la méthode manuelle : https://auroebay.netlify.app/mise-a-jour"
    return
  }

  # 2. La nouvelle version, vérifiée.
  Write-Host '• Lecture de la dernière version…'
  $web = New-Object Net.WebClient
  $web.Encoding = [Text.Encoding]::UTF8
  try { $info = $web.DownloadString("$site/version.json?t=$([DateTime]::UtcNow.Ticks)") | ConvertFrom-Json }
  catch { Err 'Pas de connexion au site AurOEBay. Vérifie Internet et réessaie.'; return }
  $latest = [string]$info.version
  if ($latest -notmatch '^\d+\.\d+\.\d+$') { Err 'Réponse du site illisible. Réessaie dans quelques minutes.'; return }
  $need = @($targets | Where-Object { Older (FolderVersion $_) $latest })
  if ($need.Count -eq 0) { Ok "AurOEBay est déjà à jour (version $latest). Rien à faire."; return }

  $tmp = Join-Path $env:TEMP ('auroebay-maj-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  try {
    Write-Host "• Téléchargement d'AurOEBay $latest…"
    $zip = Join-Path $tmp 'a.zip'
    try { $web.DownloadFile("$site/AurOEBay-testeurs.zip?v=$latest", $zip) }
    catch { Err 'Téléchargement impossible. Vérifie Internet et réessaie.'; return }
    if ($info.sha256 -and ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower() -ne ([string]$info.sha256).ToLower())) {
      Err 'Le fichier téléchargé est abîmé. Réessaie dans quelques minutes.'; return
    }
    $x = Join-Path $tmp 'x'
    try { Expand-Archive -LiteralPath $zip -DestinationPath $x -Force }
    catch { Err 'Le fichier téléchargé est illisible. Réessaie.'; return }
    $new = Join-Path $x 'AurOEBay'
    if ((FolderVersion $new) -ne $latest) { Err "Le fichier téléchargé n'est pas le bon. Réessaie dans quelques minutes."; return }

    # 3. Remplacement au même endroit ; manifest.json en dernier (AurOEBay se
    #    recharge quand il le voit). En cas de souci : retour à l'ancienne version.
    $allOk = $true
    foreach ($t in $need) {
      $before = FolderVersion $t
      Write-Host "• Mise à jour du dossier : $t"
      $backup = Join-Path $tmp 'backup'
      if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
      Copy-Item -LiteralPath $t -Destination $backup -Recurse -Force
      try {
        Get-ChildItem -LiteralPath $new -Recurse -File | Where-Object { $_.FullName -ne (Join-Path $new 'manifest.json') } | ForEach-Object {
          $rel = $_.FullName.Substring($new.Length).TrimStart('\')
          $dest = Join-Path $t $rel
          $dir = Split-Path $dest
          if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
          Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
        }
        Copy-Item -LiteralPath (Join-Path $new 'manifest.json') -Destination (Join-Path $t 'manifest.json') -Force
        if ((FolderVersion $t) -ne $latest) { throw 'version' }
        Write-Host "  $before -> $latest OK"
      } catch {
        Copy-Item -Path (Join-Path $backup '*') -Destination $t -Recurse -Force -ErrorAction SilentlyContinue
        Err "Copie impossible : l'ancienne version est remise, rien n'est perdu."
        $allOk = $false
      }
    }
    if (-not $allOk) { return }
    Ok "C'est fait ! AurOEBay $latest est installé."
    Write-Host ''
    Write-Host "-> DERNIÈRE ÉTAPE, OBLIGATOIRE : ferme complètement Chrome (la croix de toutes ses fenêtres), attends 5 secondes, puis rouvre-le." -ForegroundColor Yellow
    Write-Host "   Sans ça, les boutons AurOEBay ne marchent pas sur les pages eBay et AliExpress."
    Write-Host "   Tes données sont gardées. AurOEBay t'affichera ses nouveautés."
  } finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  }
}
try { Update-AurOEBay } catch { Write-Host ''; Write-Host ('Erreur : ' + $_.Exception.Message) -ForegroundColor Red }
Write-Host ''
Read-Host 'Appuie sur Entrée pour fermer cette fenêtre' | Out-Null
