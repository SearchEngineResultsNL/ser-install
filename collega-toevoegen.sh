#!/usr/bin/env bash
#
# Beheerderscript: nodig een collega in één keer uit voor alle privé-repo's
# die bij een pakket horen.
#
#   bash collega-toevoegen.sh <github-gebruikersnaam> [pakket] [rol]
#
#   pakket  seo · ads · data · kantoor · alles   (standaard: alles)
#   rol     pull (alleen lezen, standaard) · push (mag wijzigen) · admin
#
# Voorbeelden:
#   bash collega-toevoegen.sh jantje                  # alles, alleen lezen
#   bash collega-toevoegen.sh jantje ads              # alleen de Ads-repo's
#   bash collega-toevoegen.sh jantje seo push         # SEO, mag wijzigen
#
# Draaien als het account dat eigenaar is van de repo's.
#
set -euo pipefail

ACCOUNT="SearchEngineResultsNL"
GEBRUIKER="${1:-}"
PAKKET="${2:-alles}"
ROL="${3:-pull}"

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$HIER/install.sh"

if [ -z "$GEBRUIKER" ]; then
  printf 'Gebruik: bash collega-toevoegen.sh <github-gebruikersnaam> [pakket] [rol]\n' >&2
  printf '  pakket: seo · ads · data · kantoor · alles\n' >&2
  printf '  rol:    pull · push · admin\n' >&2
  exit 1
fi

case "$ROL" in
  pull|push|admin) ;;
  *) printf "Onbekende rol '%s'. Kies pull, push of admin.\n" "$ROL" >&2; exit 1 ;;
esac

# ── Repo's uit de catalogus in install.sh halen ─────────────────────
# Die catalogus is de enige plek waar de indeling staat. Hem hier
# overtypen loopt gegarandeerd uit de pas, dus we lezen hem uit.
[ -f "$INSTALLER" ] || {
  printf 'Fout: install.sh niet gevonden naast dit script (%s).\n' "$HIER" >&2
  exit 1
}

REPOS=()
while IFS='|' read -r naam _type pakketten; do
  [ -n "$naam" ] || continue
  if [ "$PAKKET" != "alles" ]; then
    case ",$pakketten," in *",$PAKKET,"*) ;; *) continue ;; esac
  fi
  # skills-seo en skills-ads komen beide uit één repo: ser-skills.
  case "$naam" in skills-*) naam="ser-skills" ;; esac
  # Dubbelen eruit
  case " ${REPOS[*]-} " in *" $naam "*) continue ;; esac
  REPOS+=("$naam")
done < <(sed -n '/^CATALOGUS=(/,/^)/p' "$INSTALLER" \
         | grep -oE '"[a-z0-9-]+\|(uv|clone|skills)\|[a-z,]+' \
         | tr -d '"')

if [ "${#REPOS[@]}" -eq 0 ]; then
  printf "Geen repo's gevonden voor pakket '%s'.\n" "$PAKKET" >&2
  printf 'Bestaande pakketten: seo · ads · data · kantoor · alles\n' >&2
  exit 1
fi

printf '\n%s krijgt %s-rechten op %d repo'"'"'s (pakket: %s):\n\n' \
  "$GEBRUIKER" "$ROL" "${#REPOS[@]}" "$PAKKET"

GELUKT=0; MISLUKT=0
for repo in "${REPOS[@]}"; do
  if gh api -X PUT "repos/$ACCOUNT/$repo/collaborators/$GEBRUIKER" \
       -f permission="$ROL" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$repo"
    GELUKT=$((GELUKT + 1))
  else
    printf '  ✗ %s — mislukt\n' "$repo" >&2
    MISLUKT=$((MISLUKT + 1))
  fi
done

printf '\n%d gelukt' "$GELUKT"
[ "$MISLUKT" -gt 0 ] && printf ', %d mislukt' "$MISLUKT"
printf '.\n'
printf '%s krijgt per repo een uitnodiging per e-mail. Die hoeft niet\n' "$GEBRUIKER"
printf 'aangeklikt te worden: de installer accepteert ze zelf.\n\n'
