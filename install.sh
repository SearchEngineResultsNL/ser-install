#!/usr/bin/env bash
#
# =====================================================================
#  Search Engine Results — alles installeren in één commando
# =====================================================================
#
#  Dit bestand hoort in de PUBLIEKE repo:
#      github.com/SearchEngineResultsNL/ser-install
#
#  Een compleet pakket:
#      curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/install.sh | bash -s -- seo
#      curl -fsSL … | bash -s -- ads
#      curl -fsSL … | bash -s -- alles
#
#  Zelf kiezen uit een menu:
#      curl -fsSL … | bash
#
#  Eén onderdeel rechtstreeks:
#      curl -fsSL … | bash -s -- ser-alt-teksten
#
#  Het script regelt alles wat nodig is: Command Line Tools, Homebrew,
#  Python, uv, GitHub CLI, inloggen, en per onderdeel de libraries.
#
#  Alleen kijken wat er zou gebeuren, zonder iets te installeren:
#      SER_DRYRUN=1 bash install.sh seo
#
#  Er staat bewust geen code en geen sleutel in. Dat deze repo publiek
#  is, is dus geen risico: zonder toegang tot de privé-repo's installeer
#  je niets.
#
# =====================================================================
set -euo pipefail

DRYRUN="${SER_DRYRUN:-0}"

GITHUB_ACCOUNT="SearchEngineResultsNL"
SCRIPT_URL="https://raw.githubusercontent.com/$GITHUB_ACCOUNT/ser-install/main/install.sh"
PYTHON_VERSIE="3.12"          # torch en umap-learn hebben nog geen 3.13-wielen
WERKMAP="$HOME/.ser-install"  # cache voor repo's die geen uv-tool zijn
LOG="${TMPDIR:-/tmp}/ser-install.log"

# ── curl | bash: het script zichzelf naar een bestand halen ─────────
#
# Bij 'curl … | bash' leest bash dit script van stdin, regel voor regel.
# Dat botst met het keuzemenu verderop, dat óók stdin nodig heeft.
# De werkende aanpak: het script opnieuw ophalen als bestand en dáárop
# overschakelen. Bash leest de opdrachten dan uit het bestand en stdin
# blijft vrij voor de terminal.
if [ -z "${SER_INSTALL_REEXEC:-}" ] && [ ! -t 0 ]; then
  # /dev/tty kán bestaan zonder bruikbaar te zijn (cron, CI, een agent
  # zonder terminal). Daarom niet kijken óf hij bestaat, maar of hij
  # opengaat — anders faalt de omleiding pas ná de exec, en dan is er
  # geen foutmelding meer die iets verduidelijkt.
  if ! (: < /dev/tty) 2>/dev/null; then
    printf 'Fout: geen terminal beschikbaar voor de installatie.\n' >&2
    printf 'Download het script en draai het rechtstreeks:\n' >&2
    printf '  curl -fsSLO %s\n' "$SCRIPT_URL" >&2
    printf '  bash install.sh\n' >&2
    exit 1
  fi

  SELF="$(mktemp -t ser-install)" || SELF="/tmp/ser-install-$$.sh"
  if curl -fsSL "$SCRIPT_URL" -o "$SELF" && [ -s "$SELF" ]; then
    export SER_INSTALL_REEXEC=1
    export SER_INSTALL_SELF="$SELF"
    exec bash "$SELF" "$@" < /dev/tty
  else
    printf 'Fout: kon het installatiescript niet ophalen.\n' >&2
    exit 1
  fi
fi

# ── Opmaak ──────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; DIM=""; RESET=""
fi

ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
fail() { printf '  %s✗%s %s\n' "$RED" "$RESET" "$*" >&2; }
info() { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
step() { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }

# Bij een fout de laatste regels van het logboek tonen; zonder dat is
# "installatie mislukt" niet te herleiden.
toon_log() {
  [ -s "$LOG" ] || return 0
  info "Laatste regels uit het logboek ($LOG):"
  tail -n 12 "$LOG" | while IFS= read -r r; do printf '      %s%s%s\n' "$DIM" "$r" "$RESET"; done
}

trap 'rm -f "${SER_INSTALL_SELF:-}"' EXIT INT TERM
: > "$LOG"

# ── Catalogus ───────────────────────────────────────────────────────
#
# Per regel: naam|type|pakketten|omschrijving
#
#   type = uv      Streamlit-tool, wordt een commando via 'uv tool install'
#   type = clone   repo naar een map halen en zijn eigen install.sh draaien
#   type = skills  skills en subagents naar ~/.claude zetten
#
# pakketten is een lijst met komma's; een onderdeel mag in meerdere
# pakketten zitten (ser-search-console-export hoort bij seo én data).
#
# Een regel die met KOP| begint is alleen een tussenkop in het menu.
CATALOGUS=(
  "KOP|SEO-tools"
  "ser-ab-testplatform|uv|seo|SEO A/B-test van A tot Z: data, groepen, causal impact-analyse"
  "ser-ab-test-voorbereiden|uv|seo|Ruwe CSV klaarzetten voor A/B-analyse"
  "ser-ab-test-groepen|uv|seo|URL's splitsen in twee statistisch gelijke groepen"
  "ser-ai-overviews|uv|seo|AI Overviews per zoekvraag uitlezen en content erop herschrijven"
  "ser-ai-overviews-turbo|uv|seo|Zelfde als hierboven, maar voor duizenden vragen tegelijk"
  "ser-alt-teksten|uv|seo|ALT-teksten genereren met Claude Vision, in bulk vanuit een CSV"
  "ser-titels-en-metas|uv|seo|Paginatitels en meta descriptions uit een Screaming Frog-crawl"
  "ser-titels-en-metas-batch|uv|seo|Titels en meta's via de Batch-API, voor duizenden URL's"
  "ser-teksten-batch|uv|seo|Teksten in bulk via de Batch-API (ongeveer half zo duur)"
  "ser-faq-generator|uv|seo|People Also Ask-vragen omzetten naar FAQ-content met interne links"
  "ser-vragen-clustering|uv|seo|Duizenden zoekvragen clusteren op betekenis (zwaar, ~2 GB)"
  "ser-geo-embeddings|uv|seo|Nederlandse locatie-URL's geocoderen en geo-embeddings maken"

  "KOP|Data-export"
  "ser-search-console-export|uv|seo,data|Search Console-data in bulk exporteren, voorbij de 25.000-rijenlimiet"
  "ser-linkdata-harvester|uv|seo,data|Backlinkdata uit Ahrefs, Semrush, Majestic en SerpAPI in één run"
  "ser-ga4-export|uv|data|GA4-data exporteren met quotabewaking"

  "KOP|Kantoor"
  "ser-handtekeningen|uv|kantoor|Gmail-handtekeningen centraal uitrollen over alle medewerkers"

  "KOP|Claude Code: agent en skills"
  "ai-agent|clone|ads|Google Ads-agent met klantcontext, rapportages en audits"
  "seo-agent|clone|seo|SEO-agent: SEO-audits met rapport in SER-huisstijl (samen bouwen)"
  "skills-seo|skills|seo|De /seo-commando's in Claude Code plus hun zes subagents"
  "skills-ads|skills|ads|De /ads-commando's in Claude Code plus hun zes subagents"
)

# ── Pakketten ───────────────────────────────────────────────────────
# naam|omschrijving. De inhoud komt uit de kolom 'pakketten' hierboven,
# zodat een onderdeel toevoegen aan een pakket één woord kost.
PAKKETTEN=(
  "seo|Alles voor SEO: 14 tools, de SEO-agent en de /seo-audits in Claude Code"
  "ads|Alles voor advertenties: de Google Ads-agent plus de /ads-audits"
  "data|Alleen de data-exports: Search Console, GA4, backlinkdata"
  "kantoor|Losse kantoortools"
  "alles|Alles hierboven bij elkaar"
)

# --- Opzoeken in de catalogus ----------------------------------------
cat_veld() {   # cat_veld <naam> <veldnummer>
  local naam="$1" nr="$2" regel
  [ "$naam" = "KOP" ] && return 1
  for regel in "${CATALOGUS[@]}"; do
    [ "${regel%%|*}" = "$naam" ] || continue
    printf '%s' "$regel" | cut -d'|' -f"$nr"
    return 0
  done
  return 1
}

cat_type() { cat_veld "$1" 2; }
cat_oms()  { cat_veld "$1" 4; }

bestaat_onderdeel() { cat_veld "$1" 1 >/dev/null 2>&1; }

bestaat_pakket() {
  local zoek="$1" p
  for p in "${PAKKETTEN[@]}"; do [ "${p%%|*}" = "$zoek" ] && return 0; done
  return 1
}

# Alle onderdelen van een pakket, in catalogusvolgorde.
pakket_inhoud() {
  local pakket="$1" regel naam pakketten
  for regel in "${CATALOGUS[@]}"; do
    naam="$(printf '%s' "$regel" | cut -d'|' -f1)"
    [ "$naam" = "KOP" ] && continue
    pakketten="$(printf '%s' "$regel" | cut -d'|' -f3)"
    if [ "$pakket" = "alles" ]; then
      printf '%s\n' "$naam"
    else
      case ",$pakketten," in *",$pakket,"*) printf '%s\n' "$naam" ;; esac
    fi
  done
}

printf '\n%s' "$BLUE"
cat <<'ASCII'
  ┌─────────────────────────────────────────┐
  │   Search Engine Results                 │
  │   tools, agent en skills installeren    │
  └─────────────────────────────────────────┘
ASCII
printf '%s\n' "$RESET"

# ── 0. Platform ─────────────────────────────────────────────────────
BESTURING="$(uname -s)"
if [ "$BESTURING" != "Darwin" ] && [ "$BESTURING" != "Linux" ]; then
  fail "Dit script werkt op macOS en Linux (gevonden: $BESTURING)."
  exit 1
fi

LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN" "$WERKMAP"
export PATH="$LOCAL_BIN:$HOME/.cargo/bin:$PATH"

# Zodat de commando's ook in een volgende terminal gevonden worden
pad_vastleggen() {
  local regel='export PATH="$HOME/.local/bin:$PATH"'
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    [ -w "$rc" ] || continue          # niet elk profielbestand is beschrijfbaar
    grep -qF '.local/bin' "$rc" 2>/dev/null && continue
    # Mislukt schrijven mag de installatie niet afbreken.
    if printf '\n# Toegevoegd door de SER-installatie\n%s\n' "$regel" >> "$rc" 2>/dev/null; then
      info "PATH vastgelegd in $(basename "$rc")"
    fi
  done
  return 0
}

# ── 1. Basissoftware ────────────────────────────────────────────────
step "Stap 1 van 4 — Basissoftware"

if [ "$DRYRUN" = "1" ]; then
  info "Proefrun: er wordt niets geïnstalleerd, alleen gecontroleerd."
fi

# --- Command Line Tools (levert git en de compilers) ---------------
#
# Op macOS bestaat /usr/bin/git altijd, ook zonder Command Line Tools. Dat
# is een doorgeefluik dat pas bij uitvoeren klaagt ("No developer tools
# were found"). 'command -v git' ziet dat verschil niet en zegt dus ten
# onrechte dat git er is. Gevolg: stap 1 gaat groen door, Homebrew faalt,
# 'gh auth setup-git' faalt, en elke tool struikelt op 'git init' — vijftien
# keer dezelfde fout zonder dat de oorzaak in beeld komt. Daarom git echt
# draaien in plaats van hem alleen opzoeken.
git_werkt() {
  command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1
}

if git_werkt; then
  ok "git aanwezig"
elif [ "$BESTURING" = "Darwin" ]; then
  warn "Command Line Tools ontbreken — macOS opent nu het installatievenster"
  xcode-select --install 2>/dev/null || true
  printf '\n'
  info "Klik in dat venster op 'Installeer' en wacht tot het klaar is."
  info "Dat duurt 5 tot 10 minuten. Draai daarna dit script opnieuw:"
  info "  bash install.sh seo"
  exit 1
else
  fail "git ontbreekt of werkt niet. Installeer het via je pakketbeheerder."
  toon_log
  exit 1
fi

# --- Homebrew (handig, niet verplicht) ------------------------------
brew_bin() {
  command -v brew 2>/dev/null && return 0
  [ -x /opt/homebrew/bin/brew ] && { echo /opt/homebrew/bin/brew; return 0; }
  [ -x /usr/local/bin/brew ]    && { echo /usr/local/bin/brew;    return 0; }
  [ -x /home/linuxbrew/.linuxbrew/bin/brew ] && { echo /home/linuxbrew/.linuxbrew/bin/brew; return 0; }
  return 1
}

BREW_OK=0
if BREW="$(brew_bin)" 2>/dev/null && "$BREW" --version >/dev/null 2>&1; then
  # Aanwezig is niet hetzelfde als bruikbaar: Homebrew kan onder een ander
  # gebruikersaccount geïnstalleerd zijn, en dan is de Cellar niet beschrijfbaar.
  if [ -w "$("$BREW" --cellar 2>/dev/null || echo /nonexistent)" ]; then
    BREW_OK=1
    eval "$("$BREW" shellenv)" 2>/dev/null || true
    ok "Homebrew aanwezig"
  else
    warn "Homebrew is aanwezig maar niet bruikbaar op dit account"
    info "Wordt overgeslagen; de rest wordt los opgehaald."
  fi
else
  info "Homebrew installeren (je macOS-wachtwoord kan gevraagd worden)..."
  if NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >>"$LOG" 2>&1; then
    if BREW="$(brew_bin)" 2>/dev/null; then
      BREW_OK=1
      eval "$("$BREW" shellenv)" 2>/dev/null || true
      ok "Homebrew geïnstalleerd"
    fi
  else
    warn "Homebrew-installatie mislukt — we gaan verder zonder"
    info "Dat is geen probleem: alles hieronder kan ook zonder."
  fi
fi

# --- uv: regelt Python én alle libraries ----------------------------
if command -v uv >/dev/null 2>&1; then
  ok "uv aanwezig ($(uv --version 2>/dev/null | awk '{print $2}'))"
else
  info "uv installeren..."
  if curl -LsSf https://astral.sh/uv/install.sh 2>>"$LOG" | sh >>"$LOG" 2>&1; then
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
    hash -r
  fi
  if ! command -v uv >/dev/null 2>&1 && [ "$BREW_OK" -eq 1 ]; then
    info "Tweede poging via Homebrew..."
    "$BREW" install uv >>"$LOG" 2>&1 && hash -r
  fi
  if command -v uv >/dev/null 2>&1; then
    ok "uv geïnstalleerd"
    pad_vastleggen
  else
    fail "uv kon niet geïnstalleerd worden."
    toon_log
    info "Installeer handmatig via https://docs.astral.sh/uv/ en draai opnieuw."
    exit 1
  fi
fi

# --- Python ----------------------------------------------------------
# uv haalt een eigen Python op. Je systeem-Python blijft ongemoeid, en de
# tools zijn niet afhankelijk van wat er toevallig op de Mac staat.
if uv python find "$PYTHON_VERSIE" >/dev/null 2>&1; then
  ok "Python $PYTHON_VERSIE aanwezig"
else
  info "Python $PYTHON_VERSIE ophalen (ongeveer 30 MB)..."
  if uv python install "$PYTHON_VERSIE" >>"$LOG" 2>&1; then
    ok "Python $PYTHON_VERSIE geïnstalleerd"
  else
    warn "Python $PYTHON_VERSIE kon niet vooraf opgehaald worden"
    info "uv probeert het straks per tool alsnog."
  fi
fi

# --- GitHub CLI ------------------------------------------------------
installeer_gh_los() {
  local arch tag ver tmp bestand rc
  arch="$(uname -m)"
  [ "$arch" = "x86_64" ] && arch="amd64"
  [ "$arch" = "aarch64" ] && arch="arm64"

  tag="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest 2>>"$LOG" \
         | grep -oE '"tag_name": *"[^"]+"' | head -1 | cut -d'"' -f4)"
  [ -n "$tag" ] || return 1
  ver="${tag#v}"

  tmp="$(mktemp -d)"
  rc=1
  if [ "$BESTURING" = "Darwin" ]; then
    bestand="gh_${ver}_macOS_${arch}"
    if curl -fsSL -o "$tmp/gh.zip" \
         "https://github.com/cli/cli/releases/download/${tag}/${bestand}.zip" 2>>"$LOG" \
       && unzip -q -o "$tmp/gh.zip" -d "$tmp" \
       && cp "$tmp/${bestand}/bin/gh" "$LOCAL_BIN/gh"; then rc=0; fi
  else
    bestand="gh_${ver}_linux_${arch}"
    if curl -fsSL -o "$tmp/gh.tgz" \
         "https://github.com/cli/cli/releases/download/${tag}/${bestand}.tar.gz" 2>>"$LOG" \
       && tar -xzf "$tmp/gh.tgz" -C "$tmp" \
       && cp "$tmp/${bestand}/bin/gh" "$LOCAL_BIN/gh"; then rc=0; fi
  fi
  rm -rf "$tmp"
  [ "$rc" -eq 0 ] || return 1
  chmod +x "$LOCAL_BIN/gh"
  hash -r
  return 0
}

if command -v gh >/dev/null 2>&1; then
  ok "GitHub CLI aanwezig"
elif [ "$BREW_OK" -eq 1 ] && "$BREW" install gh >>"$LOG" 2>&1; then
  hash -r
  ok "GitHub CLI geïnstalleerd"
elif installeer_gh_los; then
  pad_vastleggen
  ok "GitHub CLI geïnstalleerd in ~/.local/bin"
else
  fail "GitHub CLI kon niet geïnstalleerd worden."
  toon_log
  info "Installeer handmatig via https://cli.github.com/ en draai opnieuw."
  exit 1
fi

# ── 2. Inloggen bij GitHub ──────────────────────────────────────────
step "Stap 2 van 4 — Inloggen bij GitHub"

if gh auth status >/dev/null 2>&1; then
  GH_USER="$(gh api user --jq .login 2>/dev/null || echo '?')"
  ok "Ingelogd als $GH_USER"
else
  info "Je browser opent zo. Log in met je werkaccount."
  info "Kies bij de vragen: GitHub.com → HTTPS → Login with a web browser."
  printf '  Druk op Enter om te beginnen. '
  read -r _
  gh auth login || { fail "Inloggen mislukt."; exit 1; }
  ok "Ingelogd"
fi

# git moet de GitHub-login kunnen gebruiken, anders kan uv de privé-repo's
# niet ophalen en blijft hij om een wachtwoord vragen.
if gh auth setup-git >/dev/null 2>&1; then
  ok "git gekoppeld aan je GitHub-login"
else
  warn "Kon git niet automatisch koppelen — het ophalen kan om inloggen vragen."
fi

# ── 3. Kiezen ───────────────────────────────────────────────────────
SELECTIE=()

# Dubbelen eruit, volgorde van de catalogus aanhouden. Zonder dit
# installeert 'bash install.sh seo data' de gedeelde tools twee keer.
ontdubbel_selectie() {
  local regel naam nieuw=()
  for regel in "${CATALOGUS[@]}"; do
    naam="${regel%%|*}"
    [ "$naam" = "KOP" ] && continue
    case " ${SELECTIE[*]-} " in *" $naam "*) nieuw+=("$naam") ;; esac
  done
  SELECTIE=(${nieuw[@]+"${nieuw[@]}"})
}

# Breedte van het scherm, zodat regels niet omslaan. Een omgeslagen regel
# verpest het opnieuw tekenen van de lijst: de cursor springt dan te weinig
# regels omhoog en je krijgt dubbele lijsten in beeld.
schermbreedte() {
  local b
  b="$(tput cols 2>/dev/null || echo 80)"
  case "$b" in ''|*[!0-9]*) b=80 ;; esac
  [ "$b" -ge 50 ] || b=50
  echo "$b"
}

knip() {  # knip($tekst, $max)
  local t="$1" max="$2"
  if [ "${#t}" -gt "$max" ]; then
    printf '%s…' "${t:0:$((max - 1))}"
  else
    printf '%s' "$t"
  fi
}

# ---- Regels voor het menu ------------------------------------------
# Twee soorten regels: 'K' voor een kop (niet aan te vinken) en
# 'P'/'O' voor een pakket of los onderdeel. Zo staan de pakketten
# bovenaan zonder dat de cursor erover struikelt.
MENU_SOORT=(); MENU_NAAM=(); MENU_OMS=(); MENU_VLAG=()

menu_opbouwen() {
  local p regel naam oms

  MENU_SOORT+=("K"); MENU_NAAM+=("Pakketten"); MENU_OMS+=(""); MENU_VLAG+=(0)
  for p in "${PAKKETTEN[@]}"; do
    MENU_SOORT+=("P"); MENU_NAAM+=("${p%%|*}"); MENU_OMS+=("${p#*|}"); MENU_VLAG+=(0)
  done

  MENU_SOORT+=("K"); MENU_NAAM+=(""); MENU_OMS+=(""); MENU_VLAG+=(0)
  for regel in "${CATALOGUS[@]}"; do
    naam="$(printf '%s' "$regel" | cut -d'|' -f1)"
    if [ "$naam" = "KOP" ]; then
      MENU_SOORT+=("K"); MENU_NAAM+=("${regel#KOP|}"); MENU_OMS+=(""); MENU_VLAG+=(0)
      continue
    fi
    oms="$(printf '%s' "$regel" | cut -d'|' -f4)"
    MENU_SOORT+=("O"); MENU_NAAM+=("$naam"); MENU_OMS+=("$oms"); MENU_VLAG+=(0)
  done
}

# ---- Aanvinklijst met pijltjes en spatiebalk -----------------------
# Werkt alleen op een echte terminal. Kan dat niet, dan valt het script
# terug op nummers typen (kies_getypt hieronder).
#
# De lijst is langer dan een gemiddeld terminalvenster. Hij wordt daarom
# door een venster bekeken dat meeschuift met de cursor. Zonder dat
# scrollt het beeld weg en tekent de lijst over zichzelf heen: je ziet
# dan dubbele lijsten en de bovenste regels zijn niet meer te bereiken.
kies_aanvinken() {
  local n i cursor=0 toets rest breedte naambreedte desc_max eerste=1
  local hoogte zichtbaar venster=0 getekend=0 laatste
  n="${#MENU_NAAM[@]}"
  breedte="$(schermbreedte)"
  naambreedte=26
  desc_max=$((breedte - naambreedte - 14))

  # Hoeveel regels passen er? Zeven houden we vrij voor de uitleg
  # erboven, de statusregel eronder en de prompt van de shell.
  hoogte="$(tput lines 2>/dev/null || echo 24)"
  case "$hoogte" in ''|*[!0-9]*) hoogte=24 ;; esac
  zichtbaar=$((hoogte - 7))
  [ "$zichtbaar" -ge 5 ] || zichtbaar=5
  [ "$zichtbaar" -le "$n" ] || zichtbaar="$n"

  # Op de eerste aanvinkbare regel beginnen (regel 0 is een kop).
  while [ "${MENU_SOORT[$cursor]}" = "K" ]; do cursor=$((cursor + 1)); done

  printf '\n'
  info "Pijltjes = bewegen · spatiebalk = aan- of uitvinken"
  info "a = alles · n = niets · Enter = installeren · q = stoppen"
  info "Een pakket aanvinken mag samen met losse onderdelen."
  printf '\n'

  printf '\033[?25l'                      # cursor verbergen
  trap 'printf "\033[?25h"' RETURN 2>/dev/null || true

  volgende() {  # volgende($start, $richting) — koppen overslaan
    local pos="$1" ri="$2"
    while :; do
      pos=$(( (pos + ri + n) % n ))
      [ "${MENU_SOORT[$pos]}" = "K" ] || break
    done
    printf '%s' "$pos"
  }

  while :; do
    # Venster laten meeschuiven met de cursor, met één regel marge: dan
    # blijft de tussenkop boven de cursor in beeld en zie je waar je zit.
    [ "$cursor" -ge $((venster + 1)) ] || venster=$((cursor - 1))
    if [ "$cursor" -ge $((venster + zichtbaar - 1)) ]; then
      venster=$((cursor - zichtbaar + 2))
    fi
    [ "$venster" -le $((n - zichtbaar)) ] || venster=$((n - zichtbaar))
    [ "$venster" -ge 0 ] || venster=0

    # Welke onderdelen zitten al in een aangevinkt pakket? Die krijgen
    # een punt in plaats van een leeg vakje, zodat je ziet dat ze
    # meekomen en je niet per ongeluk dubbel kiest.
    local inbegrepen=" " aantal=0 onderdeel
    for ((i = 0; i < n; i++)); do
      if [ "${MENU_SOORT[$i]}" = "P" ] && [ "${MENU_VLAG[$i]}" -eq 1 ]; then
        while IFS= read -r onderdeel; do
          case "$inbegrepen" in *" $onderdeel "*) ;; *) inbegrepen="$inbegrepen$onderdeel " ;; esac
        done < <(pakket_inhoud "${MENU_NAAM[$i]}")
      fi
    done
    for ((i = 0; i < n; i++)); do
      if [ "${MENU_SOORT[$i]}" = "O" ] && [ "${MENU_VLAG[$i]}" -eq 1 ]; then
        case "$inbegrepen" in *" ${MENU_NAAM[$i]} "*) ;; *) inbegrepen="$inbegrepen${MENU_NAAM[$i]} " ;; esac
      fi
    done
    for onderdeel in $inbegrepen; do aantal=$((aantal + 1)); done

    [ "$eerste" -eq 1 ] || printf '\033[%dA' "$getekend"
    eerste=0
    getekend=0

    laatste=$((venster + zichtbaar - 1))
    for ((i = venster; i <= laatste; i++)); do
      getekend=$((getekend + 1))
      if [ "${MENU_SOORT[$i]}" = "K" ]; then
        if [ -n "${MENU_NAAM[$i]}" ]; then
          printf '\r\033[K  %s%s%s\n' "$BOLD" "${MENU_NAAM[$i]}" "$RESET"
        else
          printf '\r\033[K\n'
        fi
        continue
      fi
      local vink pijl kleur
      if [ "${MENU_VLAG[$i]}" -eq 1 ]; then
        vink="x"
      elif [ "${MENU_SOORT[$i]}" = "O" ] && case "$inbegrepen" in *" ${MENU_NAAM[$i]} "*) true ;; *) false ;; esac; then
        vink="·"
      else
        vink=" "
      fi
      if [ "$i" -eq "$cursor" ]; then pijl="›"; kleur="$BOLD"; else pijl=" "; kleur=""; fi
      printf '\r\033[K  %s%s%s %s[%s]%s %s%-*s%s %s%s%s\n' \
        "$BLUE" "$pijl" "$RESET" \
        "$kleur" "$vink" "$RESET" \
        "$kleur" "$naambreedte" "${MENU_NAAM[$i]}" "$RESET" \
        "$DIM" "$(knip "${MENU_OMS[$i]}" "$desc_max")" "$RESET"
    done

    # Statusregel: waar je bent, en dat er meer is dan je ziet.
    local pijl_op="  " pijl_neer="  "
    [ "$venster" -gt 0 ] && pijl_op="↑ "
    [ "$laatste" -lt $((n - 1)) ] && pijl_neer="↓ "
    printf '\r\033[K  %s%s%sregel %d van %d · %d gekozen%s\n' \
      "$DIM" "$pijl_op" "$pijl_neer" "$((cursor + 1))" "$n" "$aantal" "$RESET"
    getekend=$((getekend + 1))

    IFS= read -rsn1 toets || break
    case "$toets" in
      $'\033')
        # Een pijltoets stuurt drie tekens: ESC [ A of ESC [ B. De twee
        # resterende lezen we zonder tijdslimiet: de bash van macOS (3.2)
        # weigert een gebroken getal bij -t, en een hele seconde wachten
        # maakt de lijst traag.
        rest=""
        read -rsn2 rest 2>/dev/null || true
        case "$rest" in
          "[A"|"OA") cursor="$(volgende "$cursor" -1)" ;;
          "[B"|"OB") cursor="$(volgende "$cursor" 1)" ;;
        esac
        ;;
      ' ')
        [ "${MENU_VLAG[$cursor]}" -eq 1 ] && MENU_VLAG[$cursor]=0 || MENU_VLAG[$cursor]=1
        ;;
      j|J) cursor="$(volgende "$cursor" 1)" ;;   # vim-toetsen, kost niets
      k|K) cursor="$(volgende "$cursor" -1)" ;;
      a|A) for ((i = 0; i < n; i++)); do
             [ "${MENU_SOORT[$i]}" = "O" ] && MENU_VLAG[$i]=1
           done ;;
      n|N) for ((i = 0; i < n; i++)); do MENU_VLAG[$i]=0; done ;;
      q|Q) printf '\033[?25h'; printf '\n'; info "Gestopt."; exit 0 ;;
      '')  break ;;                            # Enter
    esac
  done

  printf '\033[?25h'
  for ((i = 0; i < n; i++)); do
    # Let op: 'test && append' als laatste opdracht laat de functie met
    # exitcode 1 eindigen zodra het laatste vakje leeg is. Met set -e stopt
    # het script dan zonder melding. Vandaar een volwaardige if.
    if [ "${MENU_VLAG[$i]}" -eq 1 ]; then
      if [ "${MENU_SOORT[$i]}" = "P" ]; then
        while IFS= read -r onderdeel; do SELECTIE+=("$onderdeel"); done \
          < <(pakket_inhoud "${MENU_NAAM[$i]}")
      else
        SELECTIE+=("${MENU_NAAM[$i]}")
      fi
    fi
  done
  return 0
}

# ---- Terugval: nummers typen ---------------------------------------
kies_getypt() {
  local i=1 KEUZE nr van tot
  local -a NUMMERS=()          # nummer → naam (pakket of onderdeel)

  printf '\n  %sPakketten%s\n' "$BOLD" "$RESET"
  for p in "${PAKKETTEN[@]}"; do
    printf '  %s%2d%s  %s%-26s%s %s%s%s\n' \
      "$BOLD" "$i" "$RESET" "$BOLD" "${p%%|*}" "$RESET" "$DIM" "${p#*|}" "$RESET"
    NUMMERS+=("${p%%|*}"); i=$((i + 1))
  done

  local naam
  for regel in "${CATALOGUS[@]}"; do
    naam="$(printf '%s' "$regel" | cut -d'|' -f1)"
    if [ "$naam" = "KOP" ]; then
      printf '\n  %s%s%s\n' "$BOLD" "${regel#KOP|}" "$RESET"
      continue
    fi
    printf '  %s%2d%s  %s%-26s%s %s%s%s\n' \
      "$BOLD" "$i" "$RESET" "$BOLD" "$naam" "$RESET" \
      "$DIM" "$(printf '%s' "$regel" | cut -d'|' -f4)" "$RESET"
    NUMMERS+=("$naam"); i=$((i + 1))
  done

  local totaal="${#NUMMERS[@]}"
  printf '\n'
  info "Typ de nummers die je wilt, gescheiden door spaties: 1 8 12"
  info "Een reeks mag ook: 6-10 · Enter zonder invoer stopt."
  printf '\n  Jouw keuze: '
  read -r KEUZE

  [ -n "${KEUZE// /}" ] || { printf '\n'; info "Niets gekozen — gestopt."; exit 0; }

  kies_nummer() {
    local nr="$1" naam
    [ "$nr" -ge 1 ] && [ "$nr" -le "$totaal" ] || { warn "$nr bestaat niet — overgeslagen"; return 0; }
    naam="${NUMMERS[$((nr - 1))]}"
    if bestaat_pakket "$naam"; then
      while IFS= read -r onderdeel; do SELECTIE+=("$onderdeel"); done < <(pakket_inhoud "$naam")
    else
      SELECTIE+=("$naam")
    fi
  }

  for nr in $KEUZE; do
    case "$nr" in
      *-*)                                     # reeks, bijvoorbeeld 6-10
        van="${nr%%-*}"; tot="${nr##*-}"
        case "$van$tot" in ''|*[!0-9]*) warn "'$nr' snap ik niet — overgeslagen"; continue ;; esac
        [ "$van" -le "$tot" ] || { i="$van"; van="$tot"; tot="$i"; }
        while [ "$van" -le "$tot" ]; do kies_nummer "$van"; van=$((van + 1)); done
        ;;
      ''|*[!0-9]*) warn "'$nr' is geen nummer — overgeslagen" ;;
      *) kies_nummer "$nr" ;;
    esac
  done
  return 0
}

if [ "$#" -gt 0 ]; then
  step "Stap 3 van 4 — Gekozen"
  for arg in "$@"; do
    if bestaat_pakket "$arg"; then
      ok "pakket $arg"
      while IFS= read -r onderdeel; do SELECTIE+=("$onderdeel"); done < <(pakket_inhoud "$arg")
    elif bestaat_onderdeel "$arg"; then
      SELECTIE+=("$arg")
      ok "$arg"
    else
      fail "Onbekend: $arg"
      info "Pakketten: seo · ads · data · kantoor · alles"
      info "Of een onderdeelnaam uit de catalogus, bijvoorbeeld ser-alt-teksten."
    fi
  done
  [ "${#SELECTIE[@]}" -gt 0 ] || { fail "Niets geldigs opgegeven."; exit 1; }
else
  step "Stap 3 van 4 — Kies wat je wilt"

  menu_opbouwen

  # Aanvinken kan alleen op een echte terminal die kleuren en cursorsprongen
  # aankan. Anders: nummers typen.
  if [ -t 0 ] && [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    kies_aanvinken
  else
    kies_getypt
  fi

  if [ "${#SELECTIE[@]}" -eq 0 ]; then
    printf '\n'
    info "Niets aangevinkt — gestopt."
    exit 0
  fi
fi

ontdubbel_selectie
printf '\n'
ok "Gekozen: ${#SELECTIE[@]} onderdeel/onderdelen"

# ── 4. Installeren ──────────────────────────────────────────────────
step "Stap 4 van 4 — Installeren"

info "Per tool worden Python en alle benodigde libraries opgehaald."
info "Reken op één tot vijf minuten per tool. ser-vragen-clustering duurt"
info "langer (~2 GB) en ai-agent draait zijn eigen installatie van 15-30 min."
printf '\n'

# ── Claude Code ─────────────────────────────────────────────────────
#
# De skills landen in ~/.claude en de Ads-agent draait erin. Zonder Claude
# Code zet de installer die bestanden gewoon neer, meldt "klaar", en bestaat
# /seo daarna nog steeds niet. Die stille mislukking kost iemand een dag
# zoeken. Dus: controleren, en alleen ophalen als er iets geselecteerd is
# dat hem nodig heeft.
CLAUDE_NIEUW=0

claude_code_nodig() {
  case " ${SELECTIE[*]-} " in
    *" skills-"*|*" ai-agent "*|*" seo-agent "*) return 0 ;;
  esac
  return 1
}

zorg_voor_claude_code() {
  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code aanwezig ($(claude --version 2>/dev/null | awk '{print $1}'))"
    return 0
  fi

  if [ "$DRYRUN" = "1" ]; then
    info "Claude Code ontbreekt — zou nu opgehaald worden"
    return 0
  fi

  info "Claude Code installeren..."
  if curl -fsSL https://claude.ai/install.sh 2>>"$LOG" | bash >>"$LOG" 2>&1; then
    export PATH="$HOME/.local/bin:$PATH"
    hash -r
  fi

  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code geïnstalleerd"
    pad_vastleggen
    CLAUDE_NIEUW=1
    return 0
  fi

  warn "Claude Code kon niet geïnstalleerd worden"
  info "Installeer hem zelf: https://code.claude.com/docs/en/setup"
  info "De skills worden wel neergezet en werken zodra hij er is."
  return 1
}

if claude_code_nodig; then
  zorg_voor_claude_code || true
  printf '\n'
fi

GELUKT=(); MISLUKT=(); COMMANDOS=()

# Toegang controleren en een openstaande uitnodiging meteen accepteren.
# Verreweg de vaakste oorzaak van "geen toegang" is een uitnodiging die
# nog in iemands mailbox staat.
heeft_toegang() {
  local repo="$1" uitnodiging
  gh repo view "$GITHUB_ACCOUNT/$repo" >/dev/null 2>&1 && return 0

  uitnodiging="$(gh api user/repository_invitations \
    --jq ".[] | select(.repository.full_name == \"$GITHUB_ACCOUNT/$repo\") | .id" 2>/dev/null || true)"
  if [ -n "$uitnodiging" ] && gh api -X PATCH "user/repository_invitations/$uitnodiging" >/dev/null 2>&1; then
    ok "openstaande uitnodiging geaccepteerd"
    return 0
  fi

  fail "Geen toegang tot $GITHUB_ACCOUNT/$repo"
  info "Je GitHub-account is nog geen collaborator op deze repo,"
  info "of je bent ingelogd met een ander account dan je werkaccount."
  info "Vraag de beheerder je toe te voegen. Ander account? Wissel met: gh auth switch"
  return 1
}

# Repo ophalen of bijwerken in de werkmap.
haal_repo() {
  local repo="$1" doel="$2"
  if [ -d "$doel/.git" ]; then
    git -C "$doel" fetch --quiet origin >>"$LOG" 2>&1 || true
    git -C "$doel" reset --hard --quiet "origin/$(git -C "$doel" rev-parse --abbrev-ref origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo main)" >>"$LOG" 2>&1 \
      || git -C "$doel" pull --rebase --autostash --quiet >>"$LOG" 2>&1 || true
  else
    rm -rf "$doel"
    gh repo clone "$GITHUB_ACCOUNT/$repo" "$doel" -- --quiet >>"$LOG" 2>&1 || return 1
  fi
  return 0
}

# --- type uv: Streamlit-tool als commando ---------------------------
installeer_uv() {
  local naam="$1"
  heeft_toegang "$naam" || return 1

  info "libraries ophalen en installeren..."
  if uv tool install --force --python "$PYTHON_VERSIE" \
       "git+https://github.com/$GITHUB_ACCOUNT/$naam.git" >>"$LOG" 2>&1; then
    COMMANDOS+=("$naam")
    return 0
  fi
  # Tweede poging zonder vaste Python-versie, voor het geval de tool
  # een andere versie vraagt.
  if uv tool install --force \
       "git+https://github.com/$GITHUB_ACCOUNT/$naam.git" >>"$LOG" 2>&1; then
    COMMANDOS+=("$naam")
    return 0
  fi
  return 1
}

# --- type clone: repo met eigen installatie ------------------------
installeer_clone() {
  local naam="$1" doel
  heeft_toegang "$naam" || return 1

  case "$naam" in
    ai-agent) doel="${AI_AGENT_DIR:-$HOME/AI Agent}" ;;
    seo-agent) doel="${SEO_AGENT_DIR:-$HOME/SEO Agent}" ;;
    *)        doel="$WERKMAP/$naam" ;;
  esac

  if [ -d "$doel" ] && [ ! -d "$doel/.git" ] && [ -n "$(ls -A "$doel" 2>/dev/null)" ]; then
    # Er staat al iets, maar geen git-repo. Niet overschrijven.
    fail "De map bestaat al en bevat bestanden: $doel"
    info "Hernoem of verplaats die map eerst, of kies een andere locatie:"
    info "  AI_AGENT_DIR=\"\$HOME/AI Agent 2\" bash install.sh ads"
    info "  SEO_AGENT_DIR=\"\$HOME/SEO Agent 2\" bash install.sh seo"
    return 1
  fi

  info "repo ophalen naar $doel..."
  haal_repo "$naam" "$doel" || return 1

  if [ -f "$doel/install.sh" ]; then
    chmod +x "$doel/install.sh" "$doel"/scripts/*.sh "$doel/sync.sh" 2>/dev/null || true
    info "eigen installatie van $naam draaien (dit duurt lang)..."
    ( cd "$doel" && ./install.sh ) || return 1
  fi
  return 0
}

# --- type skills: skills en subagents naar ~/.claude ---------------
installeer_skills() {
  local naam="$1" groep doel="$WERKMAP/ser-skills"
  groep="${naam#skills-}"                    # skills-seo → seo

  heeft_toegang "ser-skills" || return 1

  info "skills-repo ophalen..."
  haal_repo "ser-skills" "$doel" || return 1

  [ -f "$doel/install-skills.sh" ] || { fail "install-skills.sh niet gevonden"; return 1; }
  bash "$doel/install-skills.sh" "$groep" || return 1
  return 0
}

for naam in "${SELECTIE[@]}"; do
  soort="$(cat_type "$naam" || echo '')"
  printf '  %s%s%s %s(%s)%s\n' "$BOLD" "$naam" "$RESET" "$DIM" "$soort" "$RESET"

  gelukt=1
  if [ "$DRYRUN" = "1" ]; then
    # Bij een proefrun controleren we alleen de toegang. Dat is precies
    # de stap die in de praktijk struikelt, en hij verandert niets.
    case "$soort" in
      skills) heeft_toegang "ser-skills" || gelukt=0 ;;
      *)      heeft_toegang "$naam"      || gelukt=0 ;;
    esac
    [ "$gelukt" -eq 1 ] && info "toegang in orde — zou nu geïnstalleerd worden ($soort)"
  else
    case "$soort" in
      uv)     installeer_uv "$naam"     || gelukt=0 ;;
      clone)  installeer_clone "$naam"  || gelukt=0 ;;
      skills) installeer_skills "$naam" || gelukt=0 ;;
      *)      fail "onbekend type '$soort'"; gelukt=0 ;;
    esac
  fi

  if [ "$gelukt" -eq 1 ]; then
    ok "klaar"
    GELUKT+=("$naam")
  else
    fail "installatie mislukt"
    toon_log
    MISLUKT+=("$naam")
  fi
  printf '\n'
done

# ── Afronden ────────────────────────────────────────────────────────
printf '%s─────────────────────────────────────────────%s\n' "$DIM" "$RESET"

if [ "${#GELUKT[@]}" -gt 0 ]; then
  pad_vastleggen

  if [ "${#COMMANDOS[@]}" -gt 0 ]; then
    step "Klaar. Je kunt nu starten met:"
    for naam in "${COMMANDOS[@]}"; do printf '    %s%s%s\n' "$BOLD" "$naam" "$RESET"; done
    printf '\n'
    info "De app opent in je browser. Stoppen doe je met Ctrl + C."
    info "Start het commando in de map waar je je bestanden wilt hebben:"
    info "  downloads uit de app komen daar terecht."

    # Controleren of het commando echt gevonden wordt
    if ! command -v "${COMMANDOS[0]}" >/dev/null 2>&1; then
      printf '\n'
      warn "Het commando wordt in deze terminal nog niet gevonden."
      info "Open een nieuwe terminal, of draai eerst:"
      info '  export PATH="$HOME/.local/bin:$PATH"'
    fi
  else
    step "Klaar."
  fi

  case " ${GELUKT[*]} " in
    *" skills-seo "*|*" skills-ads "*)
      printf '\n'
      if [ "$CLAUDE_NIEUW" = "1" ]; then
        info "Claude Code is nieuw op deze Mac. Start hem één keer en log in:"
        info "  claude"
        info "Dat vraagt een Claude-account met Pro, Max, Team of Console."
        printf '\n'
      fi
      info "Start Claude Code opnieuw op; daarna werken de nieuwe commando's:"
      case " ${GELUKT[*]} " in *" skills-seo "*) info "  /seo audit <url>" ;; esac
      case " ${GELUKT[*]} " in *" skills-ads "*) info "  /ads audit" ;; esac
      ;;
  esac

  case " ${GELUKT[*]} " in
    *" ai-agent "*)
      printf '\n'
      info "De Google Ads-agent staat in: ${AI_AGENT_DIR:-$HOME/AI Agent}"
      info "Lees daar HANDLEIDING.md voor de eerste stappen."
      ;;
  esac
  case " ${GELUKT[*]} " in
    *" seo-agent "*)
      printf '\n'
      info "De SEO-agent staat in: ${SEO_AGENT_DIR:-$HOME/SEO Agent}"
      info "Lees daar README.md en docs/samenwerken.md."
      ;;
  esac
fi

if [ "${#MISLUKT[@]}" -gt 0 ]; then
  printf '\n'
  warn "Niet gelukt: ${MISLUKT[*]}"
  info "Het volledige logboek staat in $LOG"
fi

printf '\n'
