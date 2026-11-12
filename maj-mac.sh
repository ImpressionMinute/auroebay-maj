#!/bin/bash
# Mise à jour d'AurOEBay sur Mac (https://auroebay.netlify.app/mise-a-jour).
# Remplace les fichiers du dossier AurOEBay que Chrome utilise, AU MÊME ENDROIT.
# Tes données (produits, fournisseurs, ventes, licence) sont rangées dans
# Chrome, pas dans ce dossier : elles ne sont jamais touchées.
# Tout est dans une fonction : rien ne s'exécute si le téléchargement est coupé.

auroebay_update() {
  set -u
  local SITE="${AUROEBAY_SITE:-https://raw.githubusercontent.com/ImpressionMinute/auroebay-maj/main}"
  local TMP
  TMP="$(mktemp -d /tmp/auroebay-maj.XXXXXX)" || return 1
  trap 'rm -rf "${TMP}"' RETURN

  say_ok() { printf '\n\033[1;32m%s\033[0m\n' "$1"; }
  say_err() { printf '\n\033[1;31m%s\033[0m\n' "$1"; }
  say() { printf '%s\n' "$1"; }

  printf '\n\033[1;33m🔄 Mise à jour d’AurOEBay…\033[0m\n\n'

  # Lit la version d'un dossier AurOEBay ("" si ce n'en est pas un).
  folder_version() {
    local m="$1/manifest.json"
    [ -f "${m}" ] || return 0
    grep -q '"name"[[:space:]]*:[[:space:]]*"AurOEBay"' "${m}" || return 0
    grep -o '"version"[[:space:]]*:[[:space:]]*"[0-9.]*"' "${m}" | head -1 | grep -o '[0-9][0-9.]*'
  }
  # a < b ?
  older() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$1" ]; }

  # 1. Les dossiers AurOEBay que Chrome utilise (noté dans ses réglages).
  local found=() p
  local chrome="${HOME}/Library/Application Support/Google/Chrome"
  if [ -d "${chrome}" ]; then
    while IFS= read -r p; do
      p="${p#\"path\":\"}"; p="${p%\"}"; p="${p//\\\//\/}"; p="${p//\\\\/\\}"
      [ -n "$(folder_version "${p}")" ] && found+=("${p}")
    done < <(grep -oh '"path":"[^"]*"' "${chrome}"/*/"Secure Preferences" "${chrome}"/*/Preferences 2>/dev/null | sort -u)
  fi
  # Sinon : recherche dans les dossiers habituels.
  if [ ${#found[@]} -eq 0 ]; then
    while IFS= read -r p; do
      p="$(dirname "${p}")"
      [ -n "$(folder_version "${p}")" ] && found+=("${p}")
    done < <(find "${HOME}/Documents" "${HOME}/Desktop" "${HOME}/Downloads" "${HOME}" -maxdepth 4 -name manifest.json -not -path "*/node_modules/*" -not -path "*/Library/*" 2>/dev/null | sort -u)
  fi
  # Jamais le dossier de développement d'AurOEBay.
  local targets=() t
  for t in "${found[@]+"${found[@]}"}"; do
    [ -f "$(dirname "${t}")/package.json" ] && [ -d "$(dirname "${t}")/src" ] && continue
    case " ${targets[*]+"${targets[*]}"} " in *" ${t} "*) continue ;; esac
    targets+=("${t}")
  done
  if [ ${#targets[@]} -eq 0 ]; then
    say_err "❌ Je ne trouve pas ton dossier AurOEBay."
    say "Suis la méthode manuelle : https://auroebay.netlify.app/mise-a-jour"
    return 1
  fi

  # 2. La nouvelle version, vérifiée.
  say "• Lecture de la dernière version…"
  local info latest sum
  info="$(curl -fsSL --retry 2 "${SITE}/version.json?t=$(date +%s)")" || { say_err "❌ Pas de connexion au site AurOEBay. Vérifie Internet et réessaie."; return 1; }
  latest="$(printf '%s' "${info}" | grep -o '"version"[[:space:]]*:[[:space:]]*"[0-9.]*"' | grep -o '[0-9][0-9.]*')"
  sum="$(printf '%s' "${info}" | grep -o '"sha256"[[:space:]]*:[[:space:]]*"[0-9a-f]*"' | grep -o '[0-9a-f]\{64\}')"
  [ -n "${latest}" ] || { say_err "❌ Réponse du site illisible. Réessaie dans quelques minutes."; return 1; }

  local need=0
  for t in "${targets[@]}"; do older "$(folder_version "${t}")" "${latest}" && need=1; done
  if [ ${need} -eq 0 ]; then
    say_ok "✅ AurOEBay est déjà à jour (version ${latest}). Rien à faire."
    return 0
  fi

  say "• Téléchargement d’AurOEBay ${latest}…"
  curl -fsSL --retry 2 -o "${TMP}/a.zip" "${SITE}/AurOEBay-testeurs.zip?v=${latest}" || { say_err "❌ Téléchargement impossible. Vérifie Internet et réessaie."; return 1; }
  if [ -n "${sum}" ] && [ "$(shasum -a 256 "${TMP}/a.zip" | cut -d' ' -f1)" != "${sum}" ]; then
    say_err "❌ Le fichier téléchargé est abîmé. Réessaie dans quelques minutes."
    return 1
  fi
  mkdir "${TMP}/x" && unzip -q "${TMP}/a.zip" -d "${TMP}/x" || { say_err "❌ Le fichier téléchargé est illisible. Réessaie."; return 1; }
  local NEW="${TMP}/x/AurOEBay"
  [ "$(folder_version "${NEW}")" = "${latest}" ] || { say_err "❌ Le fichier téléchargé n’est pas le bon. Réessaie dans quelques minutes."; return 1; }

  # 3. Remplacement au même endroit ; manifest.json en dernier (AurOEBay se
  #    recharge quand il le voit). En cas de souci : retour à l'ancienne version.
  local ok=1
  for t in "${targets[@]}"; do
    local before; before="$(folder_version "${t}")"
    older "${before}" "${latest}" || continue
    say "• Mise à jour du dossier : ${t}"
    if [ ! -w "${t}" ]; then say_err "❌ Je n’ai pas le droit d’écrire dans ce dossier."; ok=0; continue; fi
    rm -rf "${TMP}/backup" && cp -R "${t}" "${TMP}/backup"
    if rsync -a --exclude manifest.json "${NEW}/" "${t}/" && cp "${NEW}/manifest.json" "${t}/manifest.json" && [ "$(folder_version "${t}")" = "${latest}" ]; then
      say "  ${before} → ${latest} ✔"
    else
      rsync -a "${TMP}/backup/" "${t}/" 2>/dev/null
      say_err "❌ Copie impossible : l’ancienne version est remise, rien n’est perdu."
      ok=0
    fi
  done
  [ ${ok} -eq 1 ] || return 1

  say_ok "✅ Fichiers installés : AurOEBay ${latest}."
  say ""
  # Seen 11/2026: after Cmd+Q, Chrome may keep running the OLD engine with the
  # new files (« Message non autorisé », licence refused). The ↻ of
  # chrome://extensions is the sure way: the page is opened for the user.
  printf '\n\033[1;33m%s\033[0m\n' "👉 2 ÉTAPES OBLIGATOIRES, sinon Chrome garde l’ancienne version :"
  say "   1. Dans Chrome, sur la page chrome://extensions (je l’ouvre pour toi), clique la flèche ronde ↻ sur la carte AurOEBay."
  say "   2. Recharge tes onglets eBay et AliExpress (⌘ Cmd + R) et tes pages AurOEBay."
  say ""
  say "   Vérifie : AurOEBay → ⚙️ Paramètres doit afficher la version ${latest}."
  say "   ⚠️ Ne clique JAMAIS « Supprimer » sur AurOEBay et ne déplace pas son dossier : tes données seraient effacées."
  say "   Tes données sont gardées. AurOEBay t’affichera ses nouveautés."
  open -a "Google Chrome" "chrome://extensions/" >/dev/null 2>&1 || true
  say ""
  say "Tu peux fermer cette fenêtre."
}
auroebay_update
