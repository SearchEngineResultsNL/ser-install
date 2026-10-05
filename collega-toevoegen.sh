#!/usr/bin/env bash
#
# Beheerderscript: nodig een collega in één keer uit voor alle privé-repo's
# die bij een pakket horen.
#
#   bash collega-toevoegen.sh <github-gebruikersnaam> [pakket] [rol]
#
#   pakket  seo · ads · data · kantoor · alles · ontwikkelaar   (standaard: alles)
#   rol     pull (alleen lezen, standaard) · push (mag wijzigen) · admin
#           (bij pakket 'ontwikkelaar' standaard push: die moet kunnen pushen)
#
# Voorbeelden:
#   bash collega-toevoegen.sh jantje                  # alles, alleen lezen
#   bash collega-toevoegen.sh jantje ads              # alleen de Ads-repo's
#   bash collega-toevoegen.sh jantje seo push         # SEO, mag wijzigen
#   bash collega-toevoegen.sh jantje ontwikkelaar     # de vier platform-repo's, push
#
# Pakket 'ontwikkelaar' is anders dan de rest: dat zijn geen tool-repo's uit
# de catalogus van install.sh, maar de vier repo's achter de twee platforms
# (zie ontwikkelaar.sh). Na de uitnodigingen hieronder blijft er voor Marten
# nog een handmatige checklist over — zie onderaan dit script.
#
# Draaien als het account dat eigenaar is van de repo's.
#
set -euo pipefail

ACCOUNT="SearchEngineResultsNL"
GEBRUIKER="${1:-}"
PAKKET="${2:-alles}"
ROL="${3:-}"

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$HIER/install.sh"
ONTWIKKELAAR_REPOS="ser-analytics-platform ser-automation-platform ser-deploy ser-werkruimte"

if [ -z "$GEBRUIKER" ]; then
  printf 'Gebruik: bash collega-toevoegen.sh <github-gebruikersnaam> [pakket] [rol]\n' >&2
  printf '  pakket: seo · ads · data · kantoor · alles · ontwikkelaar\n' >&2
  printf '  rol:    pull · push · admin\n' >&2
  exit 1
fi

if [ -z "$ROL" ]; then
  # Een ontwikkelaar moet op zijn eigen feature-branches kunnen pushen;
  # voor de tool-pakketten blijft 'pull' (alleen lezen) de veilige standaard.
  if [ "$PAKKET" = "ontwikkelaar" ]; then ROL="push"; else ROL="pull"; fi
fi

case "$ROL" in
  pull|push|admin) ;;
  *) printf "Onbekende rol '%s'. Kies pull, push of admin.\n" "$ROL" >&2; exit 1 ;;
esac

REPOS=()
if [ "$PAKKET" = "ontwikkelaar" ]; then
  # Geen catalogus-opzoeking: dit zijn de platform-repo's, geen tool-repo's.
  for naam in $ONTWIKKELAAR_REPOS; do REPOS+=("$naam"); done
else
  # ── Repo's uit de catalogus in install.sh halen ───────────────────
  # Die catalogus is de enige plek waar de indeling staat. Hem hier
  # overtypen loopt gegarandeerd uit de pas, dus we lezen hem uit.
  [ -f "$INSTALLER" ] || {
    printf 'Fout: install.sh niet gevonden naast dit script (%s).\n' "$HIER" >&2
    exit 1
  }

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
fi

if [ "${#REPOS[@]}" -eq 0 ]; then
  printf "Geen repo's gevonden voor pakket '%s'.\n" "$PAKKET" >&2
  printf 'Bestaande pakketten: seo · ads · data · kantoor · alles · ontwikkelaar\n' >&2
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

if [ "$PAKKET" = "ontwikkelaar" ]; then
  printf 'Nog met de hand te doen voor %s (checklist):\n\n' "$GEBRUIKER"
  printf '  [ ] Keeper: deel de gedeelde map "SER Platform" met %s\n' "$GEBRUIKER"
  printf '  [ ] Vraag %s om zijn/haar publieke SSH-sleutel (ontwikkelaar.sh toont die)\n' "$GEBRUIKER"
  printf '      en zet hem op de VPS in ~/.ssh/authorized_keys, MET zijn/haar naam\n'
  printf '      erbij in een commentaarregel (zodat je later weet wiens sleutel het is)\n'
  printf '  [ ] Maak een agent-token aan (Beheer → Agent-tokens) als %s de\n' "$GEBRUIKER"
  printf '      MCP-koppeling gaat gebruiken; token alleen mondeling/via Keeper delen,\n'
  printf '      nooit per mail of chat\n'
  printf '  [ ] Vercel: nodig %s uit in team ser-martens-projects als die ook gaat\n' "$GEBRUIKER"
  printf '      deployen (overleg eerst of dat nodig is — uitrollen doet in principe Marten)\n\n'
fi
