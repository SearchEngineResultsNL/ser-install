#!/usr/bin/env bash
#
# =====================================================================
#  Search Engine Results — je Mac klaarzetten met je persoonstoken
# =====================================================================
#
#  Eén regel, nadat je in Studio een persoonstoken hebt aangemaakt
#  (Beheer › Agents en tokens › Persoonstoken (alle klanten)):
#
#      curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/persoon.sh | bash
#
#  Het script vraagt zelf om het token (onzichtbaar typen/plakken). Het
#  token staat dus NOOIT in die regel, niet in je shell-geschiedenis, niet in
#  een bestand en niet in de argumenten van een proces: het gaat alleen naar
#  de macOS-sleutelhanger (dienst ser-persoonstoken).
#
#  Wat er gebeurt (opnieuw draaien = repareren; wat klaar is wordt overgeslagen):
#    1. Basis: Command Line Tools/git, uv met een vaste Python 3.12, Node 20+.
#       Je eigen Python (systeem, conda, pyenv) blijft ongemoeid.
#    2. Claude: Claude Code (terminal) + inloggen, en de Claude-app.
#    3. Je persoonstoken: vragen, controleren bij het platform, opslaan.
#    4. GitHub, de ser-MCP, de SEO-, CRO- en Ads-agent en de skills
#       (via install.sh, pakket 'agents').
#    5. De ser-MCP koppelen aan Claude Code én aan de Claude-app.
#    6. Eindcontrole met ✓/✗ per stap.
#
#  Opties (na 'bash -s --'):
#      --droog            alleen kijken, niets installeren of wijzigen
#      --nieuw-token      altijd opnieuw om het token vragen (vervangen)
#      --zonder-agents    geen agents, skills en GitHub (alleen token + MCP)
#      --agents=seo,cro   alleen deze agents (seo, cro, ads)
#      --zonder-app       de Claude-app overslaan
#
#  Voorbeeld:  curl -fsSL …/persoon.sh | bash -s -- --droog
#
#  Er staat geen code en geen sleutel in. Zonder GitHub-toegang tot de
#  privé-repo's en zonder geldig token wordt er niets gekoppeld.
#
# =====================================================================
#
# Alles staat in functies en draait pas op de laatste regel. Bij
# 'curl … | bash' leest bash het script van stdin; zo is het hele script
# ingelezen vóór er iets draait, en kan de invoer daarna naar de terminal
# (/dev/tty) voor de vragen en het verborgen token.

set -uo pipefail
umask 077

BASIS_URL="${SER_INSTALL_BASIS:-https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main}"
ANALYTICS_URL="${SER_ANALYTICS_API_URL:-https://api-analytics.searchengineresults.nl}"
PYTHON_VERSIE="3.12"
NODE_MIN=20
PERSOON_DIENST="ser-persoonstoken"
OUDE_DIENSTEN="ser-tools-agent ser-ads-agent ser-cro-agent ser-seo-agent"
SER_MCP_DIR="${SER_MCP_DIR:-$HOME/.ser-mcp}"
MCP_START="$SER_MCP_DIR/mcp-server/start-met-sleutelhanger.sh"
DESKTOP_CONFIG="${SER_DESKTOP_CONFIG:-$HOME/Library/Application Support/Claude/claude_desktop_config.json}"
LOG="${TMPDIR:-/tmp}/ser-persoon.log"
TOKEN_PATROON='^sera_[0-9a-f]{16}\.[A-Za-z0-9_-]{16,}$'

DROOG=0; NIEUW=0; ZONDER_AGENTS=0; ZONDER_APP=0; AGENTS="seo,cro,ads"
GEBRUIKER="${USER:-$(id -un)}"

# Uitslag per stap voor de samenvatting: "✓|tekst" of "✗|tekst" of "!|tekst".
UITSLAG=()
MARTEN=()      # wat een beheerder nog moet doen
JIJ=()         # wat de collega zelf nog moet doen

# ── Opmaak ──────────────────────────────────────────────────────────
opmaak() {
  if [ -t 1 ]; then
    BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; BLUE=$'\033[34m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  else
    BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; DIM=""; RESET=""
  fi
}
ok()    { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
fail()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$*"; }
info()  { printf '    %s%s%s\n' "$DIM" "$*" "$RESET"; }
step()  { printf '\n%s%s%s\n' "$BOLD" "$*" "$RESET"; }
droog() { printf '    %s[droog]%s %s\n' "$DIM" "$RESET" "$*"; }
uitslag() { UITSLAG+=("$1|$2"); }

# Ja/nee-vraag; standaard het tweede argument (j of n). In een droge run
# wordt niets gevraagd: het antwoord is dan altijd nee.
vraag_jn() {
  local vraag="$1" standaard="${2:-j}" antwoord=""
  [ "$DROOG" -eq 1 ] && return 1
  if [ "$standaard" = "j" ]; then printf '  %s [J/n] ' "$vraag"; else printf '  %s [j/N] ' "$vraag"; fi
  read -r antwoord || antwoord=""
  antwoord="$(printf '%s' "$antwoord" | tr '[:upper:]' '[:lower:]')"
  [ -n "$antwoord" ] || antwoord="$standaard"
  case "$antwoord" in j|ja|y|yes) return 0 ;; *) return 1 ;; esac
}

lees_opties() {
  local a
  for a in "$@"; do
    case "$a" in
      --droog|--dry-run) DROOG=1 ;;
      --nieuw-token) NIEUW=1 ;;
      --zonder-agents) ZONDER_AGENTS=1 ;;
      --zonder-app) ZONDER_APP=1 ;;
      --agents=*) AGENTS="${a#--agents=}" ;;
      -h|--help) sed -n '2,40p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) printf 'Onbekende optie: %s\n' "$a" >&2; exit 1 ;;
    esac
  done
  local x
  for x in $(printf '%s' "$AGENTS" | tr ',' ' '); do
    case "$x" in seo|cro|ads) ;; *) printf 'Onbekende agent: %s (kies uit seo, cro, ads)\n' "$x" >&2; exit 1 ;; esac
  done
}

pad_uitbreiden() {
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
  local b
  for b in /opt/homebrew/bin /usr/local/bin; do
    [ -d "$b" ] && case ":$PATH:" in *":$b:"*) ;; *) PATH="$PATH:$b" ;; esac
  done
  hash -r
}

# Zodat ~/.local/bin ook in een volgende terminal gevonden wordt.
pad_vastleggen() {
  local regel='export PATH="$HOME/.local/bin:$PATH"' rc
  [ "$DROOG" -eq 1 ] && return 0
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -f "$rc" ] || { [ "$rc" = "$HOME/.zshrc" ] && touch "$rc" 2>/dev/null; } || continue
    [ -w "$rc" ] || continue
    grep -qF '.local/bin' "$rc" 2>/dev/null && continue
    printf '\n# Toegevoegd door de SER-installatie\n%s\n' "$regel" >> "$rc" 2>/dev/null || true
  done
  return 0
}

brew_bin() {
  # SER_BREW_BIN: alleen voor de tests (een pad dat niet bestaat = geen Homebrew).
  if [ -n "${SER_BREW_BIN:-}" ]; then [ -x "$SER_BREW_BIN" ] && { echo "$SER_BREW_BIN"; return 0; }; return 1; fi
  command -v brew 2>/dev/null && return 0
  [ -x /opt/homebrew/bin/brew ] && { echo /opt/homebrew/bin/brew; return 0; }
  [ -x /usr/local/bin/brew ] && { echo /usr/local/bin/brew; return 0; }
  return 1
}

# Homebrew alleen als het echt nodig is, en alleen na bevestiging.
zorg_voor_brew() {   # zorg_voor_brew <waarvoor>
  local waarvoor="$1" b
  if b="$(brew_bin)"; then BREW="$b"; return 0; fi
  [ "$DROOG" -eq 1 ] && { droog "zou vragen of Homebrew geïnstalleerd mag worden (voor $waarvoor)"; return 1; }
  warn "Homebrew ontbreekt (nodig voor $waarvoor)."
  vraag_jn "Homebrew installeren? Je macOS-wachtwoord kan gevraagd worden." j || return 1
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || return 1
  pad_uitbreiden
  b="$(brew_bin)" || return 1
  BREW="$b"
  eval "$("$BREW" shellenv)" 2>/dev/null || true
  ok "Homebrew geïnstalleerd"
}

# ── Stap 1: basis ───────────────────────────────────────────────────
git_werkt() { command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; }

stap_basis() {
  step "Stap 1 van 6 — Basis: git, uv, Python $PYTHON_VERSIE, Node"

  if git_werkt; then
    ok "git aanwezig"
  elif [ "$DROOG" -eq 1 ]; then
    droog "Command Line Tools ontbreken — zou het installatievenster van macOS openen"
    uitslag "✗" "Command Line Tools ontbreken"
  else
    warn "Command Line Tools ontbreken — macOS opent nu het installatievenster"
    xcode-select --install >/dev/null 2>&1 || true
    info "Klik op 'Installeer' en wacht tot het klaar is (5 tot 10 minuten)."
    info "Draai daarna dezelfde regel opnieuw; wat klaar is wordt overgeslagen."
    uitslag "✗" "Command Line Tools ontbreken (eerst installeren, dan opnieuw)"
    return 1
  fi

  # uv: regelt Python en alle libraries, zonder je systeem-Python te raken.
  if command -v uv >/dev/null 2>&1; then
    ok "uv aanwezig ($(uv --version 2>/dev/null | awk '{print $2}'))"
  elif [ "$DROOG" -eq 1 ]; then
    droog "zou uv installeren (https://astral.sh/uv)"
  else
    info "uv installeren..."
    curl -LsSf https://astral.sh/uv/install.sh 2>>"$LOG" | sh >>"$LOG" 2>&1 || true
    pad_uitbreiden
    if command -v uv >/dev/null 2>&1; then
      ok "uv geïnstalleerd"; pad_vastleggen
    else
      fail "uv kon niet geïnstalleerd worden (logboek: $LOG)"
      uitslag "✗" "uv ontbreekt"
      return 1
    fi
  fi

  if [ "$DROOG" -eq 1 ] && ! command -v uv >/dev/null 2>&1; then
    droog "zou Python $PYTHON_VERSIE ophalen via uv"
  elif uv python find "$PYTHON_VERSIE" >/dev/null 2>&1; then
    ok "Python $PYTHON_VERSIE (via uv) aanwezig"
  elif [ "$DROOG" -eq 1 ]; then
    droog "zou Python $PYTHON_VERSIE ophalen via uv (uv python install $PYTHON_VERSIE)"
  elif uv python install "$PYTHON_VERSIE" >>"$LOG" 2>&1; then
    ok "Python $PYTHON_VERSIE geïnstalleerd (via uv, los van je systeem-Python)"
  else
    fail "Python $PYTHON_VERSIE kon niet opgehaald worden (logboek: $LOG)"
    uitslag "✗" "Python $PYTHON_VERSIE ontbreekt"
    return 1
  fi
  python_melden
  uitslag "✓" "uv + Python $PYTHON_VERSIE"

  stap_node
  return 0
}

# Een andere actieve Python (conda base, pyenv, een oude python3) is de
# klassieker: de MCP of een agent start dan met de verkeerde versie. We
# slopen niets; we melden het, en alles van SER draait via uv op 3.12
# (UV_PYTHON=3.12 in de MCP-koppeling).
python_melden() {
  local p v
  if [ -n "${CONDA_PREFIX:-}" ] || [ -n "${CONDA_DEFAULT_ENV:-}" ]; then
    warn "Conda is actief (${CONDA_DEFAULT_ENV:-$CONDA_PREFIX}). Dat laten we zo."
    info "De ser-MCP en de agents gebruiken die Python niet: ze draaien via uv op $PYTHON_VERSIE."
  fi
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    warn "Er is een virtualenv actief ($VIRTUAL_ENV); die wordt niet gebruikt."
  fi
  p="$(command -v python3 2>/dev/null || true)"
  [ -n "$p" ] || return 0
  v="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || true)"
  case "$p" in
    *conda*|*miniforge*|*mambaforge*|*.pyenv*)
      info "Actieve python3: $p (${v:-?}) — blijft ongemoeid." ;;
  esac
  case "$v" in
    2.*|3.[0-9]) warn "Je actieve python3 is $v (te oud voor de MCP). Geen probleem: SER gebruikt uv-Python $PYTHON_VERSIE." ;;
  esac
  return 0
}

stap_node() {
  local major=""
  if command -v node >/dev/null 2>&1; then
    major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
    case "$major" in ''|*[!0-9]*) major=0 ;; esac
  fi
  if [ -n "$major" ] && [ "$major" -ge "$NODE_MIN" ]; then
    ok "Node $(node --version) aanwezig"
    uitslag "✓" "Node $NODE_MIN+"
    return 0
  fi
  if [ "$DROOG" -eq 1 ]; then
    droog "Node $NODE_MIN+ ontbreekt — zou Node installeren via Homebrew (na bevestiging)"
    uitslag "!" "Node $NODE_MIN+ ontbreekt"
    return 0
  fi
  if [ -n "$major" ]; then warn "Node $(node --version) is te oud (de agents vragen $NODE_MIN of hoger)."; else warn "Node ontbreekt (nodig voor de agents)."; fi
  if zorg_voor_brew "Node" && vraag_jn "Node installeren of bijwerken via Homebrew?" j; then
    if "$BREW" install node >>"$LOG" 2>&1 || "$BREW" upgrade node >>"$LOG" 2>&1; then
      hash -r
      ok "Node $(node --version 2>/dev/null) geïnstalleerd"
      uitslag "✓" "Node $NODE_MIN+"
      return 0
    fi
  fi
  fail "Node $NODE_MIN+ niet geïnstalleerd"
  info "Zelf installeren: https://nodejs.org (LTS) en daarna deze regel opnieuw."
  uitslag "✗" "Node $NODE_MIN+ ontbreekt"
  JIJ+=("Node $NODE_MIN+ installeren (https://nodejs.org) en de regel opnieuw draaien")
  return 0
}

# ── Stap 2: Claude ──────────────────────────────────────────────────
claude_ingelogd() {
  claude auth status --json 2>/dev/null | tr -d ' \n' | grep -q '"loggedIn":true'
}

app_pad() {
  local p
  for p in "${SER_CLAUDE_APP:-/Applications/Claude.app}" "$HOME/Applications/Claude.app"; do
    [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

stap_claude() {
  step "Stap 2 van 6 — Claude Code en de Claude-app"

  if command -v claude >/dev/null 2>&1; then
    ok "Claude Code aanwezig ($(claude --version 2>/dev/null | awk '{print $1}'))"
  elif [ "$DROOG" -eq 1 ]; then
    droog "zou Claude Code installeren met de officiële installer (https://claude.ai/install.sh)"
  else
    info "Claude Code installeren (officiële installer)..."
    curl -fsSL https://claude.ai/install.sh 2>>"$LOG" | bash >>"$LOG" 2>&1 || true
    pad_uitbreiden
    if command -v claude >/dev/null 2>&1; then
      ok "Claude Code geïnstalleerd"; pad_vastleggen
    else
      fail "Claude Code kon niet geïnstalleerd worden (logboek: $LOG)"
      info "Handmatig: https://code.claude.com/docs/en/setup — daarna deze regel opnieuw."
      uitslag "✗" "Claude Code ontbreekt"
      JIJ+=("Claude Code installeren (https://code.claude.com/docs/en/setup) en de regel opnieuw draaien")
    fi
  fi

  if command -v claude >/dev/null 2>&1; then
    if claude_ingelogd; then
      ok "Ingelogd in Claude Code"
      uitslag "✓" "Claude Code + ingelogd"
    elif [ "$DROOG" -eq 1 ]; then
      droog "niet ingelogd — zou 'claude auth login' voorstellen"
      uitslag "!" "Claude Code: nog niet ingelogd"
    else
      warn "Je bent nog niet ingelogd in Claude Code."
      info "Je browser opent; log in met je SER-account (Team)."
      if vraag_jn "Nu inloggen?" j && claude auth login && claude_ingelogd; then
        ok "Ingelogd in Claude Code"
        uitslag "✓" "Claude Code + ingelogd"
      else
        warn "Niet ingelogd. Doe het later met:  claude auth login"
        uitslag "!" "Claude Code: nog niet ingelogd (claude auth login)"
        JIJ+=("Inloggen in Claude Code: claude auth login")
      fi
    fi
  fi

  [ "$ZONDER_APP" -eq 1 ] && { info "Claude-app overgeslagen (--zonder-app)"; return 0; }
  local app
  if app="$(app_pad)"; then
    ok "Claude-app aanwezig ($app)"
    uitslag "✓" "Claude-app"
    return 0
  fi
  if [ "$DROOG" -eq 1 ]; then
    droog "Claude-app ontbreekt — zou vragen of hij geïnstalleerd mag worden"
    uitslag "!" "Claude-app ontbreekt"
    return 0
  fi
  warn "De Claude-app staat nog niet op deze Mac."
  if vraag_jn "Claude-app installeren?" j; then
    if b="$(brew_bin)" && "$b" install --cask claude >>"$LOG" 2>&1 && app_pad >/dev/null; then
      ok "Claude-app geïnstalleerd"
      uitslag "✓" "Claude-app"
      return 0
    fi
    info "Ik open de officiële downloadpagina. Sleep de app naar Programma's."
    open "https://claude.ai/download" >/dev/null 2>&1 || info "https://claude.ai/download"
  fi
  uitslag "!" "Claude-app nog niet geïnstalleerd (https://claude.ai/download)"
  JIJ+=("De Claude-app installeren via https://claude.ai/download (de koppeling staat al klaar)")
  return 0
}

# ── Stap 3: het persoonstoken ───────────────────────────────────────
token_opschonen() {
  local t="$1"
  t="${t//[[:space:]]/}"
  t="${t#export}"
  t="${t#SER_AGENT_TOKEN=}"
  t="${t#\"}"; t="${t%\"}"; t="${t#\'}"; t="${t%\'}"
  printf '%s' "$t"
}

in_sleutelhanger() { security find-generic-password -s "$1" -a "$GEBRUIKER" >/dev/null 2>&1; }

# Zet het token via de invoer van 'security -i'. printf is ingebouwd en
# 'security' krijgt alleen "-i" als argument: het token staat dus nooit in
# een argumentenlijst (ps), in een bestand of in de geschiedenis.
token_opslaan() {
  local token="$1"
  case "$GEBRUIKER" in *[!A-Za-z0-9._-]*) fail "Gebruikersnaam '$GEBRUIKER' kan ik niet veilig doorgeven."; return 1 ;; esac
  printf 'add-generic-password -U -s %s -a %s -w %s\n' "$PERSOON_DIENST" "$GEBRUIKER" "$token" \
    | security -i >/dev/null 2>&1
  in_sleutelhanger "$PERSOON_DIENST"
}

# Lichte controle bij het platform: GET /api/agent/analytics/capabilities.
# De Authorization-kop gaat via stdin naar curl (-K -), niet als argument.
# Zet TOKEN_STATUS (HTTP-code of 000) en TOKEN_PERSOON (1/0).
TOKEN_STATUS=""; TOKEN_PERSOON=0; TOKEN_WIE=""
token_controleren() {
  local token="$1" uit code
  uit="$(mktemp)"
  code="$(printf 'header = "Authorization: Bearer %s"\n' "$token" \
          | curl -sS --max-time 20 -o "$uit" -w '%{http_code}' -K - \
              "$ANALYTICS_URL/api/agent/analytics/capabilities" 2>>"$LOG")" || true
  case "$code" in ''|*[!0-9]*) code="000" ;; esac
  TOKEN_STATUS="$code"; TOKEN_PERSOON=0; TOKEN_WIE=""
  if [ "$code" = "200" ]; then
    tr -d ' \n' < "$uit" | grep -q '"persoon":true' && TOKEN_PERSOON=1
    TOKEN_WIE="$(tr -d '\n' < "$uit" | sed -n 's/.*"medewerker" *: *"\([^"]*\)".*/\1/p' | head -1)"
  fi
  rm -f "$uit"
}

token_uitleg() {
  case "$TOKEN_STATUS" in
    401) fail "Het platform weigert dit token (401)."
         info "Ongeldig, verlopen of ingetrokken — of je account heeft (nog) geen toegang tot Analytics."
         info "Maak een nieuw persoonstoken in Studio › Beheer › Agents en tokens." ;;
    403) fail "Het token is bekend, maar heeft hier geen rechten (403)."
         info "Is het wel een persoonstoken (preset 'Persoonstoken (alle klanten)')?" ;;
    000) warn "Het platform was niet bereikbaar; het token is niet gecontroleerd."
         info "Geen internet, of een VPN/firewall die $ANALYTICS_URL blokkeert." ;;
    *)   warn "Onverwacht antwoord van het platform (HTTP $TOKEN_STATUS)." ;;
  esac
}

stap_token() {
  step "Stap 3 van 6 — Je persoonstoken"
  if ! command -v security >/dev/null 2>&1; then
    fail "De macOS-sleutelhanger ('security') ontbreekt; dit script werkt alleen op een Mac."
    uitslag "✗" "Token: geen sleutelhanger"
    return 1
  fi

  local bestaand="" d oud=""
  if [ "$NIEUW" -eq 0 ] && in_sleutelhanger "$PERSOON_DIENST"; then
    bestaand="$(security find-generic-password -s "$PERSOON_DIENST" -a "$GEBRUIKER" -w 2>/dev/null || true)"
    if [ -n "$bestaand" ]; then
      token_controleren "$bestaand"
      bestaand=""
      if [ "$TOKEN_STATUS" = "200" ]; then
        ok "Persoonstoken staat al in de sleutelhanger en werkt${TOKEN_WIE:+ ($TOKEN_WIE)}"
        [ "$TOKEN_PERSOON" -eq 1 ] || warn "Het werkt, maar het is geen persoonstoken (één klant of een beperkte set). Vervangen: --nieuw-token"
        info "Vervangen kan met: … | bash -s -- --nieuw-token"
        uitslag "✓" "Persoonstoken in de sleutelhanger"
        return 0
      fi
      if [ "$TOKEN_STATUS" = "000" ]; then
        token_uitleg
        uitslag "!" "Persoonstoken aanwezig, niet gecontroleerd (platform onbereikbaar)"
        return 0
      fi
      warn "Het token in de sleutelhanger werkt niet meer."
      token_uitleg
    fi
  fi
  for d in $OUDE_DIENSTEN; do in_sleutelhanger "$d" && { oud="$d"; break; }; done

  if [ "$DROOG" -eq 1 ]; then
    if [ -n "$oud" ]; then droog "oud token gevonden (dienst $oud); zou om je nieuwe persoonstoken vragen"; else droog "zou om je persoonstoken vragen (onzichtbaar), het controleren en in de sleutelhanger zetten"; fi
    uitslag "!" "Persoonstoken nog niet in de sleutelhanger"
    return 0
  fi

  [ -n "$oud" ] && info "Er staat nog een ouder token in de sleutelhanger ($oud); dat blijft staan als terugval."
  info "Kopieer je persoonstoken uit Studio en plak het hieronder."
  info "Wat je plakt blijft onzichtbaar en komt alleen in de macOS-sleutelhanger."
  local poging=1 invoer="" token=""
  while [ "$poging" -le 3 ]; do
    printf '  Persoonstoken (sera_…): '
    if ! IFS= read -rs invoer; then
      printf '\n'; fail "Geen invoer mogelijk (geen terminal)."
      uitslag "✗" "Persoonstoken niet opgeslagen"
      return 1
    fi
    printf '\n'
    token="$(token_opschonen "$invoer")"; invoer=""
    if [ -z "$token" ]; then
      warn "Overgeslagen."
      break
    fi
    if ! printf '%s' "$token" | grep -Eq "$TOKEN_PATROON"; then
      warn "Dat lijkt geen persoonstoken (${#token} tekens). Verwacht: sera_ + 16 tekens + een punt + het geheim."
      token=""; poging=$((poging + 1)); continue
    fi
    token_controleren "$token"
    if [ "$TOKEN_STATUS" = "200" ] || [ "$TOKEN_STATUS" = "000" ]; then
      [ "$TOKEN_STATUS" = "000" ] && token_uitleg
      break
    fi
    token_uitleg
    token=""; poging=$((poging + 1))
  done

  if [ -z "$token" ]; then
    if [ -n "$oud" ]; then
      warn "Geen nieuw token; de koppeling gebruikt voorlopig het oude token ($oud)."
      uitslag "!" "Persoonstoken niet opgeslagen (oud token als terugval)"
    else
      fail "Geen geldig persoonstoken opgeslagen."
      uitslag "✗" "Persoonstoken niet opgeslagen"
    fi
    JIJ+=("Een persoonstoken maken in Studio › Beheer › Agents en tokens en de regel opnieuw draaien")
    return 0
  fi

  if token_opslaan "$token"; then
    token=""
    ok "Opgeslagen in de sleutelhanger (dienst $PERSOON_DIENST)${TOKEN_WIE:+ — persoonstoken van $TOKEN_WIE}"
    if [ "$TOKEN_STATUS" = "200" ] && [ "$TOKEN_PERSOON" -eq 0 ]; then
      warn "Dit token werkt, maar is geen persoonstoken (één klant of een beperkte set)."
      info "Voor alle klanten: maak 'Persoonstoken (alle klanten)' of laat het omzetten."
    fi
    if [ "$TOKEN_STATUS" = "200" ]; then uitslag "✓" "Persoonstoken gecontroleerd en opgeslagen"; else uitslag "!" "Persoonstoken opgeslagen, niet gecontroleerd"; fi
    return 0
  fi
  token=""
  fail "Opslaan in de sleutelhanger is niet gelukt. Staat hij vergrendeld? Ontgrendel hem en probeer opnieuw."
  uitslag "✗" "Persoonstoken niet opgeslagen"
  return 0
}

# ── Stap 4: GitHub, agents, skills en de ser-MCP (via install.sh) ───
install_sh_pad() {
  local hier="" doel
  if [ -n "${SER_INSTALL_SH:-}" ]; then printf '%s' "$SER_INSTALL_SH"; return 0; fi
  case "${BASH_SOURCE[0]:-}" in
    */persoon.sh) hier="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" ;;
  esac
  if [ -n "$hier" ] && [ -f "$hier/install.sh" ]; then printf '%s' "$hier/install.sh"; return 0; fi
  doel="$(mktemp -t ser-install)" || return 1
  if curl -fsSL "$BASIS_URL/install.sh" -o "$doel" 2>>"$LOG" && [ -s "$doel" ]; then
    printf '%s' "$doel"; return 0
  fi
  rm -f "$doel"
  return 1
}

agent_onderdelen() {
  local x lijst="ser-mcp"
  for x in $(printf '%s' "$AGENTS" | tr ',' ' '); do
    case "$x" in
      seo) lijst="$lijst seo-agent skills-seo" ;;
      cro) lijst="$lijst cro-agent" ;;
      ads) lijst="$lijst ai-agent skills-ads" ;;
    esac
  done
  printf '%s' "$lijst"
}

agent_map() {
  case "$1" in
    seo-agent) printf '%s' "${SEO_AGENT_DIR:-$HOME/SEO Agent}" ;;
    cro-agent) printf '%s' "${CRO_AGENT_DIR:-$HOME/CRO Agent}" ;;
    ai-agent)  printf '%s' "${AI_AGENT_DIR:-$HOME/AI Agent}" ;;
  esac
}

repo_van() {
  case "$1" in
    skills-*) printf 'ser-skills' ;;
    ser-mcp) printf 'ser-automation-platform' ;;
    *) printf '%s' "$1" ;;
  esac
}

stap_agents() {
  step "Stap 4 van 6 — GitHub, de ser-MCP, de agents en de skills"
  local onderdelen
  onderdelen="$(agent_onderdelen)"
  if [ "$ZONDER_AGENTS" -eq 1 ]; then
    onderdelen="ser-mcp"
    info "Alleen de ser-MCP (--zonder-agents)."
  fi

  if [ "$DROOG" -eq 1 ]; then
    droog "zou draaien: install.sh $onderdelen  (GitHub-login, ophalen, eigen installatie per agent)"
    toegang_melden "$onderdelen"
    uitslag "!" "Agents/skills/ser-MCP niet geïnstalleerd (droog)"
    return 0
  fi

  local inst
  if ! inst="$(install_sh_pad)"; then
    fail "Kon install.sh niet ophalen ($BASIS_URL/install.sh)."
    uitslag "✗" "Agents/skills/ser-MCP: install.sh niet opgehaald"
    return 0
  fi
  info "Dit duurt even: elke agent draait zijn eigen installatie (de Ads-agent 15-30 minuten)."
  # shellcheck disable=SC2086
  SER_INSTALL_REEXEC=1 SER_GEEN_BREW_INSTALL=1 bash "$inst" $onderdelen || true
  case "$inst" in "${TMPDIR:-/tmp}"*|/tmp/*|/var/folders/*) [ -z "${SER_INSTALL_SH:-}" ] && rm -f "$inst" ;; esac

  toegang_melden "$onderdelen"

  local o map
  for o in $onderdelen; do
    case "$o" in
      ser-mcp)
        if [ -f "$MCP_START" ]; then uitslag "✓" "ser-MCP in $SER_MCP_DIR"; else uitslag "✗" "ser-MCP niet opgehaald"; fi ;;
      *-agent)
        map="$(agent_map "$o")"
        if [ -d "$map/.git" ]; then uitslag "✓" "$o in $map"; else uitslag "✗" "$o niet geïnstalleerd"; fi ;;
      skills-*)
        if [ -d "$HOME/.claude/skills/${o#skills-}" ]; then uitslag "✓" "$o"; else uitslag "!" "$o niet gevonden in ~/.claude/skills"; fi ;;
    esac
  done
  return 0
}

# Leesrecht per repo; ontbreekt het, dan zeggen we precies wat Marten moet doen.
toegang_melden() {
  local onderdelen="$1" o repo login ontbreekt="" gezien=" "
  command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1 || {
    [ "$DROOG" -eq 1 ] && droog "niet ingelogd bij GitHub; toegang niet gecontroleerd"
    return 0
  }
  login="$(gh api user --jq .login 2>/dev/null || echo '<github-naam>')"
  for o in $onderdelen; do
    repo="$(repo_van "$o")"
    case "$gezien" in *" $repo "*) continue ;; esac
    gezien="$gezien$repo "
    if gh repo view "SearchEngineResultsNL/$repo" >/dev/null 2>&1; then
      [ "$DROOG" -eq 1 ] && ok "toegang tot $repo"
    else
      ontbreekt="$ontbreekt $repo"
    fi
  done
  [ -n "$ontbreekt" ] || return 0
  fail "Je GitHub-account ($login) kan deze privé-repo's niet lezen:$ontbreekt"
  info "Vraag Marten je toe te voegen; daarna deze regel opnieuw draaien."
  info "Ander (privé)account actief? Wissel met: gh auth switch"
  MARTEN+=("GitHub-toegang voor $login: bash collega-toevoegen.sh $login agents  (ontbrak:$ontbreekt)")
}

# ── Stap 5: de ser-MCP koppelen ─────────────────────────────────────
# Geen token in de configs: alleen het pad naar het startscript, dat het
# token zelf uit de sleutelhanger leest. UV_PYTHON zet de vaste Python vast,
# zodat conda/pyenv er niet tussen komt.
mcp_json() {   # mcp_json <met-PATH 0|1>
  local pad=""
  if [ "$1" = "1" ]; then
    # De Claude-app start zonder je shell-PATH; uv staat in ~/.local/bin.
    pad=",\"PATH\":\"$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\""
  fi
  printf '{"type":"stdio","command":"%s","args":[],"env":{"UV_PYTHON":"%s"%s}}' "$MCP_START" "$PYTHON_VERSIE" "$pad"
}

stap_mcp() {
  step "Stap 5 van 6 — De ser-MCP koppelen aan Claude"
  if [ ! -f "$MCP_START" ] && [ "$DROOG" -eq 0 ]; then
    fail "De ser-MCP staat niet klaar ($MCP_START ontbreekt); koppelen overgeslagen."
    uitslag "✗" "MCP niet gekoppeld (ser-MCP ontbreekt)"
    return 0
  fi
  case "$MCP_START" in *'"'*|*'\'*) fail "Het pad $MCP_START bevat tekens die ik niet veilig in JSON zet."; uitslag "✗" "MCP niet gekoppeld"; return 0 ;; esac

  # Claude Code (user-scope: geldt in elke map)
  if ! command -v claude >/dev/null 2>&1; then
    warn "Claude Code ontbreekt; koppeling in Claude Code overgeslagen."
    uitslag "✗" "MCP in Claude Code (Claude Code ontbreekt)"
  elif [ "$DROOG" -eq 1 ]; then
    droog "zou koppelen: claude mcp add-json -s user ser '$(mcp_json 0)'"
  else
    claude mcp remove ser -s user >/dev/null 2>&1 || true
    if claude mcp add-json -s user ser "$(mcp_json 0)" >>"$LOG" 2>&1; then
      ok "Gekoppeld in Claude Code (naam: ser, voor al je mappen)"
      uitslag "✓" "MCP 'ser' in Claude Code"
    else
      fail "Koppelen in Claude Code mislukt (logboek: $LOG)"
      uitslag "✗" "MCP 'ser' in Claude Code"
    fi
  fi

  desktop_config_bijwerken
  return 0
}

# claude_desktop_config.json veilig samenvoegen: back-up, alleen mcpServers.ser
# vervangen, de rest ongemoeid. Ongeldige JSON → niets aanraken.
desktop_config_bijwerken() {
  local map
  map="$(dirname "$DESKTOP_CONFIG")"
  if [ "$ZONDER_APP" -eq 1 ]; then return 0; fi
  if [ ! -d "$map" ] && ! app_pad >/dev/null; then
    info "Claude-app niet gevonden; de app-koppeling volgt als je deze regel na het installeren opnieuw draait."
    uitslag "!" "MCP in de Claude-app (app ontbreekt)"
    return 0
  fi
  if [ "$DROOG" -eq 1 ]; then
    droog "zou ser toevoegen aan $DESKTOP_CONFIG (met back-up, zonder token)"
    return 0
  fi
  mkdir -p "$map"
  local py
  py="$(cat <<'PY'
import json, os, sys, time, shutil, tempfile
pad, server = sys.argv[1], json.loads(sys.argv[2])
server.pop("type", None)
data = {}
if os.path.exists(pad) and os.path.getsize(pad) > 0:
    try:
        with open(pad, encoding="utf-8") as f:
            data = json.load(f)
    except Exception:
        print("ongeldig"); sys.exit(3)
    if not isinstance(data, dict):
        print("ongeldig"); sys.exit(3)
    if data.get("mcpServers", {}).get("ser") == server:
        print("al"); sys.exit(0)
    shutil.copy2(pad, pad + ".bak-ser-" + time.strftime("%Y%m%d-%H%M%S"))
servers = data.get("mcpServers")
if not isinstance(servers, dict):
    servers = {}
servers["ser"] = server
data["mcpServers"] = servers
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(pad), prefix=".claude_desktop_config.")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.chmod(tmp, 0o600)
os.replace(tmp, pad)
print("bijgewerkt")
PY
)"
  local uit
  uit="$(uv run --no-project --quiet --python "$PYTHON_VERSIE" python -I -c "$py" "$DESKTOP_CONFIG" "$(mcp_json 1)" 2>>"$LOG")"
  case "$uit" in
    al)         ok "Claude-app: koppeling stond er al"; uitslag "✓" "MCP 'ser' in de Claude-app" ;;
    bijgewerkt) ok "Claude-app: koppeling toegevoegd (back-up naast het bestand). Herstart de app."; uitslag "✓" "MCP 'ser' in de Claude-app (herstart de app)" ;;
    ongeldig)   fail "De Claude-app-config is geen geldige JSON; niets aangeraakt: $DESKTOP_CONFIG"
                uitslag "✗" "MCP in de Claude-app (config ongeldig)" ;;
    *)          fail "Claude-app-config bijwerken mislukt (logboek: $LOG)"; uitslag "✗" "MCP in de Claude-app" ;;
  esac
}

# ── Stap 6: eindcontrole ────────────────────────────────────────────
# Een echte MCP-aanroep: startscript → sleutelhanger → server → ser_klanten.
# We tonen alleen het aantal klanten, geen namen.
MCP_TEST_PY="$(cat <<'PY'
import json, os, select, subprocess, sys, time
start = sys.argv[1]
env = dict(os.environ, UV_PYTHON=os.environ.get("UV_PYTHON", "3.12"))
try:
    p = subprocess.Popen([start], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env)
except OSError as e:
    print("start niet: %s" % e.__class__.__name__); sys.exit(2)
buf = b""
def stuur(o):
    p.stdin.write((json.dumps(o) + "\n").encode()); p.stdin.flush()
def wacht(i, sec):
    global buf
    eind = time.time() + sec
    while time.time() < eind:
        while b"\n" in buf:
            regel, buf = buf.split(b"\n", 1)
            try:
                o = json.loads(regel)
            except ValueError:
                continue
            if o.get("id") == i:
                return o
        r, _, _ = select.select([p.stdout], [], [], 1)
        if r:
            stuk = os.read(p.stdout.fileno(), 65536)
            if not stuk:
                return None
            buf += stuk
    return None
try:
    stuur({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "ser-persoon-controle", "version": "1"}}})
    if not wacht(1, 180):
        print("reageerde niet"); sys.exit(2)
    stuur({"jsonrpc": "2.0", "method": "notifications/initialized"})
    stuur({"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "ser_klanten", "arguments": {}}})
    r = wacht(2, 90)
    if not r:
        print("ser_klanten reageerde niet"); sys.exit(2)
    if "error" in r:
        print("fout: %s" % str(r["error"].get("message", ""))[:160]); sys.exit(2)
    res = r.get("result", {})
    tekst = "".join(c.get("text", "") for c in res.get("content", []) if isinstance(c, dict))
    if res.get("isError"):
        print("fout: %s" % tekst[:160]); sys.exit(2)
    try:
        d = json.loads(tekst)
        n = len(d.get("klanten", [])) if isinstance(d, dict) else len(d)
    except ValueError:
        n = -1
    print("ok %d" % n)
finally:
    try:
        p.stdin.close(); p.terminate(); p.wait(5)
    except Exception:
        p.kill()
PY
)"

stap_controle() {
  step "Stap 6 van 6 — Eindcontrole"
  if [ "$DROOG" -eq 1 ]; then
    droog "zou controleren: claude mcp get ser (verbonden), een testaanroep ser_klanten, de agentmappen"
    return 0
  fi

  if command -v claude >/dev/null 2>&1; then
    local status
    status="$(claude mcp get ser 2>/dev/null | grep -i 'status' | head -1)"
    case "$status" in
      *ailed*|*✗*) fail "Claude Code: ser is gekoppeld maar verbindt niet"; uitslag "✗" "claude mcp: ser verbonden" ;;
      *onnected*)  ok "Claude Code: ser is verbonden"; uitslag "✓" "claude mcp: ser verbonden" ;;
      *)           warn "Claude Code: status van ser onbekend"; uitslag "!" "claude mcp: status ser onbekend" ;;
    esac
  fi

  if [ -f "$MCP_START" ] && command -v uv >/dev/null 2>&1; then
    local r
    r="$(UV_PYTHON="$PYTHON_VERSIE" uv run --no-project --quiet --python "$PYTHON_VERSIE" python -I -c "$MCP_TEST_PY" "$MCP_START" 2>>"$LOG")"
    case "$r" in
      "ok -1") ok "Testaanroep ser_klanten werkt"; uitslag "✓" "Testaanroep ser_klanten" ;;
      ok\ *)   ok "Testaanroep ser_klanten werkt (${r#ok } klanten zichtbaar)"; uitslag "✓" "Testaanroep ser_klanten (${r#ok } klanten)" ;;
      *)       fail "Testaanroep ser_klanten mislukt: ${r:-geen antwoord}"
               case "$r" in
                 *401*|*403*) info "Het token wordt geweigerd. Opnieuw: … | bash -s -- --nieuw-token" ;;
                 *"reageerde niet"*) info "Bij de eerste keer haalt uv de libraries op; draai de regel nog een keer." ;;
               esac
               uitslag "✗" "Testaanroep ser_klanten" ;;
    esac
  fi
  return 0
}

samenvatting() {
  printf '\n%s─────────────────────────────────────────────%s\n' "$DIM" "$RESET"
  step "Samenvatting"
  local r teken tekst fouten=0
  for r in ${UITSLAG[@]+"${UITSLAG[@]}"}; do
    teken="${r%%|*}"; tekst="${r#*|}"
    case "$teken" in
      "✓") ok "$tekst" ;;
      "✗") fail "$tekst"; fouten=$((fouten + 1)) ;;
      *)   warn "$tekst" ;;
    esac
  done
  if [ "${#JIJ[@]}" -gt 0 ]; then
    step "Nog te doen door jou"
    for r in "${JIJ[@]}"; do info "• $r"; done
  fi
  if [ "${#MARTEN[@]}" -gt 0 ]; then
    step "Nog te doen door Marten (of een beheerder)"
    for r in "${MARTEN[@]}"; do info "• $r"; done
  fi
  printf '\n'
  if [ "$DROOG" -eq 1 ]; then
    info "Droge run: er is niets gewijzigd."
  elif [ "$fouten" -eq 0 ]; then
    ok "Klaar. Start Claude Code in een agentmap (bv. cd ~/\"SEO Agent\" && claude) of herstart de Claude-app."
  else
    info "Los het bovenstaande op en draai dezelfde regel opnieuw: wat klaar is wordt overgeslagen."
  fi
  info "Logboek: $LOG"
  printf '\n'
  [ "$fouten" -eq 0 ] || return 1
  return 0
}

main() {
  opmaak
  lees_opties "$@"
  printf '\n%s' "$BLUE"
  printf '  ┌─────────────────────────────────────────┐\n'
  printf '  │   Search Engine Results                 │\n'
  printf '  │   je Mac klaarzetten (persoonstoken)    │\n'
  printf '  └─────────────────────────────────────────┘\n'
  printf '%s\n' "$RESET"

  if [ "$(uname -s)" != "Darwin" ] && [ -z "${SER_PERSOON_TEST:-}" ]; then
    fail "Dit script werkt (nog) alleen op macOS: het token gaat in de macOS-sleutelhanger."
    exit 1
  fi
  : > "$LOG"
  [ "$DROOG" -eq 1 ] && info "Droge run: er wordt niets geïnstalleerd of gewijzigd."
  pad_uitbreiden
  BREW=""

  stap_basis || { samenvatting; exit 1; }
  stap_claude
  stap_token
  stap_agents
  stap_mcp
  stap_controle
  samenvatting
}

# Invoer van de terminal, ook bij 'curl … | bash'. SER_PERSOON_INVOER is
# alleen voor de tests (een bestand met antwoorden).
if [ -n "${SER_PERSOON_INVOER:-}" ]; then
  main "$@" < "$SER_PERSOON_INVOER"
elif (: < /dev/tty) 2>/dev/null; then
  main "$@" < /dev/tty
else
  printf 'Fout: geen terminal beschikbaar. Draai deze regel in Terminal op je Mac.\n' >&2
  exit 1
fi
