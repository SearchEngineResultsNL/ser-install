#!/usr/bin/env bash
#
# =====================================================================
#  SER — werkplek voor een ontwikkelaar inrichten
# =====================================================================
#
#  Hoort bij ser-install (PUBLIEK). Zet een Mac klaar om mee te bouwen aan
#  tools.searchengineresults.nl en analytics.searchengineresults.nl:
#  basissoftware, de vier repo's, een eigen SSH-sleutel, de testomgeving
#  (één keer gedraaid, mét een tijdelijke Postgres) en Claude Code.
#
#  Starten — via het pakket in install.sh (aanbevolen):
#      curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/install.sh \
#        | bash -s -- ontwikkelaar
#
#  Of rechtstreeks:
#      curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/ontwikkelaar.sh | bash
#
#  Alleen kijken wat er zou gebeuren, zonder iets te doen:
#      curl -fsSLO https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/ontwikkelaar.sh
#      bash ontwikkelaar.sh --droog
#      # of: DRY_RUN=1 bash ontwikkelaar.sh
#
#  Opties:
#      --droog       niets installeren/klonen/aanmaken, alleen tonen (ook: DRY_RUN=1)
#      --map <map>   waar de vier repo's komen (standaard: je thuismap)
#      -h, --help    deze uitleg
#
#  Dit script zet NOOIT iets automatisch op de VPS en stuurt nooit een
#  geheim ergens heen. De publieke SSH-sleutel die het toont is geen
#  geheim; die stuur je zelf naar Marten. Veilig om opnieuw te draaien:
#  wat er al staat, wordt overgeslagen, nooit overschreven.
#
#  Geschreven voor de bash van macOS (3.2): geen associatieve arrays, geen
#  ${var,,}, geen mapfile, geen 'read -t' met een gebroken getal.
#
# =====================================================================
set -euo pipefail

GITHUB_ACCOUNT="SearchEngineResultsNL"
REPOS="ser-analytics-platform ser-automation-platform ser-deploy ser-werkruimte"
PYTHON_VERSIE="3.12"
NODE_FORMULE="node@24"            # huidige LTS-lijn; elke even versie vanaf 20 is prima
SLEUTELHANGER_DIENST="ser-tools-agent"   # zelfde naam als mcp-server/start-met-sleutelhanger.sh
SCRIPT_URL="https://raw.githubusercontent.com/$GITHUB_ACCOUNT/ser-install/main/ontwikkelaar.sh"
LOG="${TMPDIR:-/tmp}"; LOG="${LOG%/}/ser-ontwikkelaar.log"

DROOG="${DRY_RUN:-0}"
MAP="${SER_ONTWIKKELAAR_MAP:-}"

hulp() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]:-$0}"; }

# ── Argumenten ────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
  case "$1" in
    --droog|--dry-run) DROOG=1 ;;
    --map)   shift; MAP="${1:-}" ;;
    --map=*) MAP="${1#--map=}" ;;
    -h|--help) hulp; exit 0 ;;
    *) printf 'Onbekende optie: %s (zie --help)\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

# ── Via een pijp gestart? Dan eerst jezelf als bestand ophalen ────────
#
# Bij '… | bash' leest bash dit script van stdin. Elke vraag die daarna
# stdin leest, eet dan een stuk van het script op. De werkende aanpak:
# het script opnieuw ophalen als bestand en dáárop overschakelen, met de
# terminal als stdin.
BRON="${BASH_SOURCE[0]:-}"
if [ -z "${SER_ONTWIKKELAAR_REEXEC:-}" ] && { [ -z "$BRON" ] || [ ! -f "$BRON" ]; }; then
  if ! (: < /dev/tty) 2>/dev/null; then
    printf 'Fout: geen terminal beschikbaar voor de installatie.\n' >&2
    printf 'Download het script en draai het rechtstreeks:\n' >&2
    printf '  curl -fsSLO %s\n' "$SCRIPT_URL" >&2
    printf '  bash ontwikkelaar.sh\n' >&2
    exit 1
  fi
  ZELF="$(mktemp -t ser-ontwikkelaar)" || ZELF="/tmp/ser-ontwikkelaar-$$.sh"
  if curl -fsSL "$SCRIPT_URL" -o "$ZELF" && [ -s "$ZELF" ]; then
    export SER_ONTWIKKELAAR_REEXEC=1 DRY_RUN="$DROOG" SER_ONTWIKKELAAR_MAP="$MAP"
    exec bash "$ZELF" < /dev/tty
  fi
  printf 'Fout: kon het script niet ophalen.\n' >&2
  exit 1
fi
trap 'rm -f "${ZELF:-}"' EXIT INT TERM

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
droog_melding() { printf '    %s[droog]%s %s\n' "$BLUE" "$RESET" "$*"; }

: > "$LOG"
toon_log() {
  [ -s "$LOG" ] || return 0
  info "Laatste regels uit het logboek ($LOG):"
  tail -n 12 "$LOG" | while IFS= read -r r; do printf '      %s%s%s\n' "$DIM" "$r" "$RESET"; done
}

GEDAAN=(); OVERGESLAGEN=(); NOG_DOEN=()
gedaan()       { GEDAAN+=("$*"); }
overgeslagen() { OVERGESLAGEN+=("$*"); }
nog_doen()     { NOG_DOEN+=("$*"); }

# ── Terminal voor vragen ────────────────────────────────────────────
# Vragen lezen altijd van /dev/tty, nooit van stdin. Geen terminal (agent,
# CI)? Dan kan alleen de droogloop: die neemt overal 'ja' aan.
TTY_OK=0
if (: < /dev/tty) 2>/dev/null; then TTY_OK=1; fi
if [ "$TTY_OK" -eq 0 ] && [ "$DROOG" != "1" ]; then
  fail "Geen terminal beschikbaar: dit script stelt vragen."
  info "Draai het in Terminal of iTerm, of kijk eerst met --droog."
  exit 1
fi

vraag() {  # vraag "tekst" [j|n] → 0 bij ja, 1 bij nee
  local tekst="$1" standaard="${2:-j}" antwoord keuzes
  if [ "$standaard" = "j" ]; then keuzes="J/n"; else keuzes="j/N"; fi
  if [ "$DROOG" = "1" ]; then
    droog_melding "vraag: $tekst [$keuzes] → aangenomen: ja"
    return 0
  fi
  printf '  %s?%s %s [%s] ' "$BLUE" "$RESET" "$tekst" "$keuzes"
  IFS= read -r antwoord < /dev/tty || antwoord=""
  [ -n "$antwoord" ] || antwoord="$standaard"
  case "$antwoord" in j|J|ja|Ja|JA|y|Y|yes) return 0 ;; esac
  return 1
}

vraag_tekst() {  # vraag_tekst "tekst" "standaard" → antwoord op stdout
  local tekst="$1" standaard="$2" antwoord
  if [ "$DROOG" = "1" ]; then
    droog_melding "vraag: $tekst [$standaard] → aangenomen: $standaard" >&2
    printf '%s' "$standaard"; return 0
  fi
  printf '  %s?%s %s [%s] ' "$BLUE" "$RESET" "$tekst" "$standaard" >&2
  IFS= read -r antwoord < /dev/tty || antwoord=""
  printf '%s' "${antwoord:-$standaard}"
}

doe() {  # doe <omschrijving> -- <commando…>  — droog: alleen tonen
  local oms="$1"; shift; [ "${1:-}" = "--" ] && shift
  if [ "$DROOG" = "1" ]; then
    droog_melding "zou draaien: $*"
    return 0
  fi
  info "$oms..."
  printf '\n$ %s\n' "$*" >> "$LOG"
  "$@" >> "$LOG" 2>&1
}

doe_interactief() {  # zelfde, maar met de terminal erbij (logins, wachtwoorden)
  local oms="$1"; shift; [ "${1:-}" = "--" ] && shift
  if [ "$DROOG" = "1" ]; then
    droog_melding "zou (interactief) draaien: $*"
    return 0
  fi
  info "$oms"
  "$@" < /dev/tty
}

aanvullen_met_bak() {  # aanvullen_met_bak <bestand> <tekst> — met .bak ervoor
  local bestand="$1" tekst="$2" bak
  if [ "$DROOG" = "1" ]; then
    droog_melding "zou aanvullen: $bestand (eerst kopie naar $bestand.bak-…)"
    return 0
  fi
  if [ -f "$bestand" ]; then
    bak="$bestand.bak-$(date +%Y%m%d-%H%M%S)"
    cp -p "$bestand" "$bak"
    info "kopie gemaakt: $bak"
  fi
  printf '\n%s\n' "$tekst" >> "$bestand"
}

lijst() {  # lijst <kop> <item…>
  local kop="$1"; shift
  [ "$#" -gt 0 ] || return 0
  printf '\n  %s%s%s\n' "$BOLD" "$kop" "$RESET"
  local x; for x in "$@"; do printf '    • %s\n' "$x"; done
}

printf '\n%s' "$BLUE"
cat <<'ASCII'
  ┌─────────────────────────────────────────┐
  │   Search Engine Results                 │
  │   werkplek voor een ontwikkelaar        │
  └─────────────────────────────────────────┘
ASCII
printf '%s\n' "$RESET"

if [ "$DROOG" = "1" ]; then
  warn "Droogloop: er wordt niets geïnstalleerd, gekloond of aangemaakt."
fi

if [ "$(uname -s)" != "Darwin" ]; then
  fail "Dit script is voor macOS (gevonden: $(uname -s))."
  exit 1
fi

# =======================================================================
# Stap 1 van 6 — Basissoftware
# =======================================================================
step "Stap 1 van 6 — Basissoftware"

# Op macOS bestaat /usr/bin/git altijd, ook zonder Command Line Tools — dat
# is een doorgeefluik dat pas bij uitvoeren klaagt. Daarom git echt draaien.
if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
  ok "git aanwezig ($(git --version | awk '{print $3}'))"
else
  warn "Command Line Tools ontbreken (die leveren git en de compilers)"
  if vraag "Nu het installatievenster van macOS openen?" j; then
    doe "Command Line Tools aanvragen" -- xcode-select --install || true
  fi
  info "Wacht tot dat venster klaar is (5-10 minuten) en draai dit script opnieuw."
  [ "$DROOG" = "1" ] || exit 1
fi

brew_bin() {
  command -v brew 2>/dev/null && return 0
  [ -x /opt/homebrew/bin/brew ] && { echo /opt/homebrew/bin/brew; return 0; }
  [ -x /usr/local/bin/brew ]    && { echo /usr/local/bin/brew;    return 0; }
  return 1
}

BREW=""
if BREW="$(brew_bin)"; then
  eval "$("$BREW" shellenv)" 2>/dev/null || true
  ok "Homebrew aanwezig"
elif vraag "Homebrew installeren? Je macOS-wachtwoord kan gevraagd worden." j; then
  # shellcheck disable=SC2016
  if doe_interactief "Homebrew installeren..." -- /bin/bash -c \
       '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'; then
    if [ "$DROOG" = "1" ]; then BREW="brew"
    elif BREW="$(brew_bin)"; then
      eval "$("$BREW" shellenv)" 2>/dev/null || true
      ok "Homebrew geïnstalleerd"; gedaan "Homebrew"
      if ! grep -qF 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
        aanvullen_met_bak "$HOME/.zprofile" "# Toegevoegd door ser-install (ontwikkelaar)
eval \"\$($BREW shellenv)\""
      fi
    fi
  else
    fail "Homebrew-installatie mislukt"; toon_log; nog_doen "Homebrew installeren"
  fi
else
  overgeslagen "Homebrew"
fi

brew_pakket() {  # brew_pakket <commando> <formule> <omschrijving> [j|n]
  local cmd="$1" formule="$2" oms="$3" standaard="${4:-j}"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$oms aanwezig"
    return 0
  fi
  if [ -z "$BREW" ]; then
    warn "$oms ontbreekt, en zonder Homebrew kan dit script hem niet installeren"
    nog_doen "$oms installeren ($formule)"
    return 0
  fi
  if vraag "$oms installeren (brew install $formule)?" "$standaard"; then
    if doe "$oms installeren" -- "$BREW" install "$formule"; then
      hash -r
      [ "$DROOG" = "1" ] || { ok "$oms geïnstalleerd"; gedaan "$oms"; }
    else
      fail "$oms installeren mislukt"; toon_log; nog_doen "$oms installeren"
    fi
  else
    overgeslagen "$oms"
  fi
}

brew_pakket gh gh "GitHub CLI (gh)"
brew_pakket gitleaks gitleaks "gitleaks (controle op geheimen)"

# rsync: macOS levert altijd een (oude) versie mee; alleen aanvullen als hij
# echt ontbreekt (zelden, bv. een sterk afgeslankte installatie).
if command -v rsync >/dev/null 2>&1; then
  ok "rsync aanwezig"
else
  brew_pakket rsync rsync "rsync"
fi

# uv: regelt Python én alle libraries van de repo's.
if command -v uv >/dev/null 2>&1; then
  ok "uv aanwezig ($(uv --version 2>/dev/null | awk '{print $2}'))"
elif vraag "uv installeren (regelt Python en alle Python-libraries)?" j; then
  if doe "uv installeren" -- /bin/bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh"; then
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"; hash -r
    if ! command -v uv >/dev/null 2>&1 && [ -n "$BREW" ]; then
      doe "uv installeren via Homebrew (tweede poging)" -- "$BREW" install uv && hash -r
    fi
    [ "$DROOG" = "1" ] || { command -v uv >/dev/null 2>&1 && { ok "uv geïnstalleerd"; gedaan "uv"; }; }
  else
    fail "uv installeren mislukt"; toon_log; nog_doen "uv installeren (https://docs.astral.sh/uv/)"
  fi
else
  overgeslagen "uv"
fi

# Python 3.12: vastgepind, zoals de repo's vragen (torch/umap-learn hebben
# nog geen wielen voor nieuwere versies; dezelfde reden als in install.sh).
if command -v uv >/dev/null 2>&1; then
  if uv python find "$PYTHON_VERSIE" >/dev/null 2>&1; then
    ok "Python $PYTHON_VERSIE aanwezig"
  elif [ "$DROOG" = "1" ]; then
    droog_melding "zou Python $PYTHON_VERSIE ophalen via uv"
  else
    if doe "Python $PYTHON_VERSIE ophalen" -- uv python install "$PYTHON_VERSIE"; then
      ok "Python $PYTHON_VERSIE geïnstalleerd"; gedaan "Python $PYTHON_VERSIE"
    else
      warn "Python $PYTHON_VERSIE kon niet vooraf opgehaald worden"; info "uv probeert het straks per stap alsnog."
    fi
  fi
fi

# node: elke even versie vanaf 20 is prima. node@24 is 'keg-only' en komt dus
# niet vanzelf in PATH; dat regelen we in ~/.zprofile.
NODE_MAJOR=0
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
  case "$NODE_MAJOR" in ''|*[!0-9]*) NODE_MAJOR=0 ;; esac
fi
if [ "$NODE_MAJOR" -ge 20 ]; then
  ok "node aanwezig ($(node --version))"
elif [ -n "$BREW" ] && vraag "node (LTS, $NODE_FORMULE) installeren?" j; then
  if doe "node installeren" -- "$BREW" install "$NODE_FORMULE"; then
    if [ "$DROOG" != "1" ]; then
      NODE_BIN="$("$BREW" --prefix "$NODE_FORMULE" 2>/dev/null)/bin"
      export PATH="$NODE_BIN:$PATH"; hash -r
      if ! grep -qF "$NODE_FORMULE" "$HOME/.zprofile" 2>/dev/null; then
        aanvullen_met_bak "$HOME/.zprofile" "# Toegevoegd door ser-install (ontwikkelaar): node LTS
export PATH=\"$NODE_BIN:\$PATH\""
      fi
      ok "node geïnstalleerd ($(node --version 2>/dev/null || echo '?'))"; gedaan "node ($NODE_FORMULE)"
    fi
  else
    fail "node installeren mislukt"; toon_log; nog_doen "node installeren"
  fi
else
  warn "node (20+) ontbreekt"
  nog_doen "node 20 of hoger installeren"
fi

# Claude Code CLI
if command -v claude >/dev/null 2>&1; then
  ok "Claude Code aanwezig ($(claude --version 2>/dev/null | awk '{print $1}'))"
elif vraag "Claude Code installeren?" j; then
  if doe "Claude Code installeren" -- /bin/bash -c "curl -fsSL https://claude.ai/install.sh | bash"; then
    export PATH="$HOME/.local/bin:$PATH"; hash -r
    [ "$DROOG" = "1" ] || { ok "Claude Code geïnstalleerd"; gedaan "Claude Code"; }
  else
    fail "Claude Code installeren mislukt"; toon_log
    nog_doen "Claude Code installeren: https://code.claude.com/docs/en/setup"
  fi
else
  overgeslagen "Claude Code"
fi

# Playwright-browsers, voor de frontend-QA (screenshots/e2e). Via uv, geen
# losse virtuele omgeving nodig; de browser-cache is systeembreed.
if command -v uv >/dev/null 2>&1; then
  if vraag "Playwright-browser (Chromium) ophalen voor frontend-QA?" j; then
    if doe "Chromium voor Playwright ophalen" -- uv run --quiet --with playwright --python "$PYTHON_VERSIE" \
         python3 -m playwright install chromium; then
      [ "$DROOG" = "1" ] || { ok "Playwright-Chromium geïnstalleerd"; gedaan "Playwright-Chromium"; }
    else
      warn "Playwright-browser ophalen mislukt — niet kritiek, later met de hand:"
      info "  uv run --with playwright python3 -m playwright install chromium"
      nog_doen "Playwright-Chromium installeren"
    fi
  else
    overgeslagen "Playwright-browser"
  fi
else
  info "uv ontbreekt nog — Playwright-browser wordt overgeslagen"
fi

# =======================================================================
# Stap 2 van 6 — GitHub: inloggen, toegang, repo's klonen
# =======================================================================
step "Stap 2 van 6 — GitHub: inloggen, toegang, repo's klonen"

GH_OK=0; GH_ECHT=0
if ! command -v gh >/dev/null 2>&1 && [ "$DROOG" != "1" ]; then
  fail "Zonder GitHub CLI kan er niets gekloond worden."
  nog_doen "GitHub CLI installeren en dit script opnieuw draaien"
elif gh auth status >/dev/null 2>&1; then
  GH_OK=1; GH_ECHT=1
  ok "Ingelogd bij GitHub als $(gh api user --jq .login 2>/dev/null || echo '?')"
elif vraag "Nu inloggen bij GitHub (gh auth login — kies GitHub.com → HTTPS → browser, je eigen account)?" j; then
  if doe_interactief "Inloggen bij GitHub..." -- gh auth login; then
    GH_OK=1; [ "$DROOG" = "1" ] || gedaan "Ingelogd bij GitHub"
  else
    fail "Inloggen mislukt"
  fi
else
  overgeslagen "GitHub-login"
fi

if [ "$GH_OK" -eq 1 ]; then
  if [ "$DROOG" = "1" ]; then
    droog_melding "zou draaien: gh auth setup-git"
  elif gh auth setup-git >/dev/null 2>&1; then
    ok "git gekoppeld aan je GitHub-login"
  fi
fi

# SearchEngineResultsNL is op GitHub een gewoon ACCOUNT, geen organisatie:
# toegang gaat per repo als collaborator, niet via een org-uitnodiging.
# "Repository not found" betekent bijna altijd: nog geen collaborator, of
# het verkeerde account actief (gh auth switch).
heeft_toegang() {
  local repo="$1" uitnodiging
  gh repo view "$GITHUB_ACCOUNT/$repo" >/dev/null 2>&1 && return 0
  uitnodiging="$(gh api user/repository_invitations \
    --jq ".[] | select(.repository.full_name == \"$GITHUB_ACCOUNT/$repo\") | .id" 2>/dev/null || true)"
  if [ -n "$uitnodiging" ]; then
    if [ "$DROOG" = "1" ]; then droog_melding "zou openstaande uitnodiging voor $repo accepteren"; return 0; fi
    if gh api -X PATCH "user/repository_invitations/$uitnodiging" >/dev/null 2>&1; then
      ok "openstaande uitnodiging voor $repo geaccepteerd"; return 0
    fi
  fi
  return 1
}

if [ -z "$MAP" ]; then
  MAP="$(vraag_tekst "In welke map komen de vier repo's (naast elkaar)?" "$HOME")"
fi
# shellcheck disable=SC2088
case "$MAP" in "~"|"~/"*) MAP="$HOME${MAP#\~}" ;; esac
info "Map voor de repo's: $MAP"

EERSTE_TOEGANGSFOUT=1
GEKLOOND=""
for repo in $REPOS; do
  doel="$MAP/$repo"
  printf '  %s%s%s\n' "$BOLD" "$repo" "$RESET"
  if [ "$GH_OK" -ne 1 ]; then
    warn "overgeslagen: niet ingelogd bij GitHub"; overgeslagen "$repo klonen"; continue
  fi
  if [ "$GH_ECHT" -ne 1 ]; then
    droog_melding "zou toegang tot $GITHUB_ACCOUNT/$repo controleren (en een openstaande uitnodiging accepteren)"
  elif ! heeft_toegang "$repo"; then
    fail "Geen toegang tot $GITHUB_ACCOUNT/$repo"
    if [ "$EERSTE_TOEGANGSFOUT" -eq 1 ]; then
      info "Vraag Marten je als collaborator toe te voegen op de SER-repo's"
      info "(SearchEngineResultsNL is een GitHub-account, geen organisatie —"
      info "er is dus geen org-uitnodiging, wel per repo een collaborator-uitnodiging)."
      info "Account: https://github.com/$GITHUB_ACCOUNT"
      EERSTE_TOEGANGSFOUT=0
    fi
    nog_doen "Toegang vragen tot $GITHUB_ACCOUNT/$repo"
    continue
  fi

  if [ -d "$doel/.git" ]; then
    if [ "$DROOG" = "1" ]; then
      droog_melding "staat er al; zou draaien: git fetch, en git pull --ff-only als je schoon op main staat"
    else
      git -C "$doel" fetch --quiet origin >> "$LOG" 2>&1 || true
      tak="$(git -C "$doel" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
      if [ -z "$(git -C "$doel" status --porcelain 2>/dev/null)" ] && [ "$tak" = "main" ]; then
        if git -C "$doel" pull --ff-only --quiet >> "$LOG" 2>&1; then
          ok "bijgewerkt (main)"
        else
          warn "main loopt uiteen met origin; niets aangeraakt"
        fi
      else
        warn "staat er al op '$tak' met eigen wijzigingen; alleen opgehaald (git fetch)"
      fi
    fi
    GEKLOOND="$GEKLOOND $repo"
  elif [ -e "$doel" ] && [ -n "$(ls -A "$doel" 2>/dev/null)" ]; then
    fail "$doel bestaat al en is geen git-repo — niets aangeraakt"
    info "Hernoem die map, of kies een andere met --map."
    nog_doen "$repo klonen (map $doel was bezet)"
  elif vraag "$repo klonen naar $doel?" j; then
    if doe "klonen" -- gh repo clone "$GITHUB_ACCOUNT/$repo" "$doel" -- --quiet; then
      [ "$DROOG" = "1" ] || { ok "gekloond"; gedaan "$repo gekloond"; }
      GEKLOOND="$GEKLOOND $repo"
    else
      fail "klonen mislukt"; toon_log; nog_doen "$repo klonen"
    fi
  else
    overgeslagen "$repo klonen"
  fi
done

# Startritueel (besluit 27-10, ser-deploy/START.md): het commando
# 'ser-bijwerken' haalt vóór het ontwikkelen alle SER-repo's op (alleen
# fast-forward). Het script zelf staat in ser-deploy; hier alleen een snelkoppeling.
case " $GEKLOOND " in
  *" ser-deploy "*)
    BIJWERKEN_BIN="$HOME/.local/bin/ser-bijwerken"
    if [ -e "$BIJWERKEN_BIN" ] && ! grep -q "ser-bijwerken-shim" "$BIJWERKEN_BIN" 2>/dev/null; then
      warn "$BIJWERKEN_BIN bestaat al (niet van ons) — niets aangeraakt"
      info "Startritueel dan zo: bash $MAP/ser-deploy/scripts/bijwerken.sh"
    elif [ "$DROOG" = "1" ]; then
      droog_melding "zou $BIJWERKEN_BIN aanmaken (startritueel: bash $MAP/ser-deploy/scripts/bijwerken.sh)"
    else
      mkdir -p "$HOME/.local/bin"
      printf '%s\n' '#!/bin/bash' \
        '# ser-bijwerken-shim — aangemaakt door ser-install/ontwikkelaar.sh (startritueel, ser-deploy/START.md)' \
        "exec bash \"$MAP/ser-deploy/scripts/bijwerken.sh\" --map \"$MAP\" \"\$@\"" > "$BIJWERKEN_BIN"
      chmod 755 "$BIJWERKEN_BIN"
      ok "commando ser-bijwerken (startritueel) aangemaakt"; gedaan "ser-bijwerken (startritueel)"
    fi
    ;;
esac

# =======================================================================
# Stap 3 van 6 — Eigen SSH-sleutel (voor latere VPS-toegang)
# =======================================================================
step "Stap 3 van 6 — Eigen SSH-sleutel"

info "Deze sleutel dient later om in te loggen op de SER-server. Hij wordt"
info "nu alleen aangemaakt en getoond — er gaat niets automatisch naar de VPS."

SLEUTEL="$HOME/.ssh/id_ed25519"
if [ -f "$SLEUTEL.pub" ]; then
  ok "SSH-sleutel aanwezig ($SLEUTEL)"
elif [ -f "$SLEUTEL" ]; then
  warn "$SLEUTEL bestaat, maar de .pub ernaast ontbreekt"
  info "Herstellen met: ssh-keygen -y -f $SLEUTEL > $SLEUTEL.pub"
  nog_doen "publieke sleutel ($SLEUTEL.pub) herstellen"
elif vraag "Nieuwe SSH-sleutel maken (ed25519)? Kies een wachtzin; macOS onthoudt hem." j; then
  if [ "$DROOG" != "1" ]; then mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"; fi
  if doe_interactief "sleutel maken..." -- ssh-keygen -t ed25519 -f "$SLEUTEL" \
       -C "$(whoami)@$(hostname -s 2>/dev/null || echo mac) (SER)"; then
    [ "$DROOG" = "1" ] || { ok "sleutel gemaakt"; gedaan "SSH-sleutel ed25519"; }
  else
    fail "ssh-keygen mislukt"
  fi
else
  overgeslagen "SSH-sleutel"
fi

if [ -f "$SLEUTEL.pub" ]; then
  printf '\n    %sJe PUBLIEKE sleutel (veilig om te delen):%s\n\n' "$BOLD" "$RESET"
  printf '    %s\n\n' "$(cat "$SLEUTEL.pub")"
  if [ "$DROOG" != "1" ] && command -v pbcopy >/dev/null 2>&1; then
    pbcopy < "$SLEUTEL.pub" && info "Staat ook op je klembord."
  fi
  info "Stuur deze regel (met je naam erbij) naar Marten voor toegang tot de VPS."
  info "Stuur NOOIT het bestand zonder .pub — dat is je privésleutel."
  nog_doen "Publieke SSH-sleutel ($SLEUTEL.pub) + je naam naar Marten sturen"
elif [ "$DROOG" = "1" ]; then
  droog_melding "zou de publieke sleutel hier tonen en vragen die naar Marten te sturen"
fi

# =======================================================================
# Stap 4 van 6 — Testomgeving: afhankelijkheden + tests (met Postgres)
# =======================================================================
step "Stap 4 van 6 — Testomgeving"

# Per repo: afhankelijkheden installeren en één keer de volledige suite
# draaien, met een wegwerp-Postgres erbij (pgserver). Zonder TEST_DATABASE_URL
# naar een database die op '_test' eindigt, worden de *_pg.py/*_postgres.py-
# tests stil OVERGESLAGEN — dat is precies waarom we die database hier zelf
# opzetten, en waarom we straks de uitvoer controleren op zulke skips.
draai_backend_tests() {  # draai_backend_tests <repo> <doel> <dbnaam> <socketmap>
  local repo="$1" doel="$2" dbnaam="$3" socketmap="$4" testlog
  if [ -f "$doel/scripts/test-alles.sh" ]; then
    # Toekomstige, snellere all-in-one testrunner (branch 'snellere-tests').
    if doe "volledige testsuite van $repo (test-alles.sh)" -- \
         /bin/bash -c "cd \"$doel\" && bash scripts/test-alles.sh"; then
      [ "$DROOG" = "1" ] || { ok "tests $repo groen (test-alles.sh)"; gedaan "tests $repo groen"; }
    else
      warn "tests van $repo niet groen — zie $LOG"; nog_doen "tests $repo nakijken (zie $LOG)"
    fi
    return 0
  fi
  [ -f "$doel/scripts/tests.sh" ] || { info "geen scripts/tests.sh in $repo — overgeslagen"; return 0; }

  if [ "$DROOG" = "1" ]; then
    droog_melding "zou een wegwerp-Postgres starten (socketmap $socketmap, database $dbnaam)"
    droog_melding "en draaien: ./scripts/tests.sh -rs  met TEST_DATABASE_URL gezet"
    return 0
  fi

  testlog="$(mktemp -t "ser-ontwikkelaar-tests-$repo")"
  info "tests van $repo draaien, met een tijdelijke Postgres (kan enkele minuten duren)..."
  printf '\n$ (pgserver) ./scripts/tests.sh -rs  [%s]\n' "$repo" >> "$LOG"
  if uv run --quiet --with pgserver python3 - "$doel" "$dbnaam" "$socketmap" > "$testlog" 2>&1 <<'PY'
import os, subprocess, sys, pgserver
doel, dbnaam, socketmap = sys.argv[1], sys.argv[2], sys.argv[3]
srv = pgserver.get_server(socketmap, cleanup_mode="stop")   # socketmap eindigt op _test
try:
    srv.psql(f"CREATE DATABASE {dbnaam};")
except Exception:
    pass                                                     # bestaat al
env = dict(os.environ, TEST_DATABASE_URL=srv.get_uri(dbnaam))
r = subprocess.run(["./scripts/tests.sh", "-rs"], cwd=doel, env=env)
raise SystemExit(r.returncode)
PY
  then
    cat "$testlog" >> "$LOG"
    samenvatting="$(grep -E '^[0-9]+ (passed|failed)' "$testlog" | tail -1)"
    ok "tests $repo groen${samenvatting:+ — $samenvatting}"
    gedaan "tests $repo groen${samenvatting:+ ($samenvatting)}"
  else
    cat "$testlog" >> "$LOG"
    samenvatting="$(grep -E '^[0-9]+ (passed|failed)' "$testlog" | tail -1)"
    fail "tests van $repo niet groen${samenvatting:+ — $samenvatting}"
    nog_doen "tests $repo nakijken (zie $LOG)"
  fi

  # Postgres-skips die er ondanks TEST_DATABASE_URL toch nog zijn, zijn een
  # teken dat er iets mis is met de aanname (naam/pad socketmap, connectie) —
  # dat is precies de stille valkuil uit de repo-documentatie.
  pg_skips="$(grep -E 'SKIPPED.*(_pg\.py|_postgres\.py)' "$testlog" || true)"
  if [ -n "$pg_skips" ]; then
    warn "Postgres-tests van $repo zijn toch overgeslagen, ondanks een tijdelijke database:"
    printf '%s\n' "$pg_skips" | head -10 | while IFS= read -r regel; do info "  $regel"; done
    nog_doen "Postgres-skips van $repo handmatig controleren (zie $testlog)"
  fi
  rm -f "$testlog"
}

for repo in $GEKLOOND; do
  doel="$MAP/$repo"
  printf '  %s%s%s\n' "$BOLD" "$repo" "$RESET"

  # Frontend-afhankelijkheden (als die er zijn) vóór de backendtests.
  for sub in . frontend; do
    d="$doel"; label="$repo"
    [ "$sub" = "." ] || { d="$doel/$sub"; label="$repo/$sub"; }
    [ -f "$d/package.json" ] || continue
    if vraag "$label: npm-pakketten installeren en bouwen?" j; then
      if doe "npm install + build in $label" -- /bin/bash -c "cd \"$d\" && npm install --no-audit --no-fund && npm run build"; then
        [ "$DROOG" = "1" ] || { ok "$label gebouwd"; gedaan "$label: npm install + build"; }
        if doe "frontend-tests in $label" -- /bin/bash -c "cd \"$d\" && npm test 2>/dev/null || node --test *.test.mjs 2>/dev/null || true"; then
          [ "$DROOG" = "1" ] || ok "$label: frontend-tests gedraaid"
        fi
      else
        fail "$label: npm install/build mislukt"; toon_log; nog_doen "$label: npm install/build nakijken"
      fi
    else
      overgeslagen "$label: npm install/build"
    fi
  done

  if ! vraag "$repo: backend-afhankelijkheden + tests draaien (met tijdelijke Postgres)?" j; then
    overgeslagen "$repo: backend-tests"
    continue
  fi

  TMP_ZONDER_SLASH="${TMPDIR:-/tmp}"; TMP_ZONDER_SLASH="${TMP_ZONDER_SLASH%/}"
  case "$repo" in
    ser-analytics-platform)  draai_backend_tests "$repo" "$doel" "analytics_test" "$TMP_ZONDER_SLASH/sot_an_test" ;;
    ser-automation-platform) draai_backend_tests "$repo" "$doel" "tools_test"     "$TMP_ZONDER_SLASH/sot_au_test" ;;
    *) info "geen backend-testsuite voor $repo — overgeslagen" ;;
  esac
done

# =======================================================================
# Stap 5 van 6 — Claude Code
# =======================================================================
step "Stap 5 van 6 — Claude Code"

if command -v claude >/dev/null 2>&1; then
  info "Inloggen (eenmalig, vraagt een Claude-account met Pro/Max/Team/Console):"
  info "  claude"
  info "Elke repo heeft een AGENTS.md (en soms CLAUDE.md) met de regels voor AI-agents."
  info "Lees die vóór je Claude Code iets laat wijzigen — de harde regels staan er in."
else
  info "Claude Code is niet geïnstalleerd — zie stap 1."
fi

MCP_SCRIPT="$MAP/ser-automation-platform/mcp-server/start-met-sleutelhanger.sh"
if command -v claude >/dev/null 2>&1 && { [ -f "$MCP_SCRIPT" ] || [ "$DROOG" = "1" ]; }; then
  if claude mcp get ser >/dev/null 2>&1 || claude mcp get ser-tools >/dev/null 2>&1; then
    ok "Claude Code kent de ser-MCP-server al"
  elif vraag "ser-MCP-server aan Claude Code koppelen (tools + analytics voor agents)?" n; then
    if doe "MCP-server koppelen" -- claude mcp add --scope user ser -- "$MCP_SCRIPT"; then
      [ "$DROOG" = "1" ] || { ok "gekoppeld (voor al je projecten)"; gedaan "MCP-server 'ser'"; }
    else
      fail "koppelen mislukt"; toon_log
    fi
  else
    overgeslagen "MCP-koppeling"
  fi

  # Het agent-token gaat ALLEEN via de sleutelhanger-prompt naar binnen —
  # nooit als argument (zichtbaar in de procestabel/geschiedenis) en nooit
  # in een bestand. 'security … -w' zonder waarde vraagt er zelf om.
  if security find-generic-password -s "$SLEUTELHANGER_DIENST" -a "$USER" >/dev/null 2>&1; then
    ok "agent-token staat al in de sleutelhanger"
  else
    info "De MCP-server heeft een agent-token nodig (begint met sera_)."
    info "Dat token maakt Marten voor je aan: Beheer → Agent-tokens."
    if vraag "Heb je het token nu bij de hand en wil je het in de sleutelhanger zetten?" n; then
      if doe_interactief "Plak het token bij de vraag (je ziet niets verschijnen; dat hoort zo):" -- \
           security add-generic-password -U -s "$SLEUTELHANGER_DIENST" -a "$USER" -w; then
        [ "$DROOG" = "1" ] || { ok "token opgeslagen"; gedaan "agent-token in sleutelhanger"; }
      else
        fail "opslaan mislukt"
      fi
    else
      info "Later: security add-generic-password -U -s $SLEUTELHANGER_DIENST -a \"\$USER\" -w"
      nog_doen "Agent-token (sera_…) vragen aan Marten en in de sleutelhanger zetten"
    fi
  fi
else
  info "mcp-server/start-met-sleutelhanger.sh niet gevonden — MCP-koppeling overgeslagen"
  info "(normaal zodra ser-automation-platform gekloond is)"
fi

# =======================================================================
# Stap 6 van 6 — Eindcontrole
# =======================================================================
step "Stap 6 van 6 — Eindcontrole"

if [ "$DROOG" = "1" ]; then
  info "Droogloop klaar: er is niets veranderd."
fi

lijst "Gedaan (✓)"       ${GEDAAN[@]+"${GEDAAN[@]}"}
lijst "Overgeslagen"     ${OVERGESLAGEN[@]+"${OVERGESLAGEN[@]}"}
lijst "Nog te doen (✗)"  ${NOG_DOEN[@]+"${NOG_DOEN[@]}"}

printf '\n  %sWat nu%s\n' "$BOLD" "$RESET"
printf '    • Begin elke keer met het startritueel: %sser-bijwerken%s (alle repo'"'"'s ophalen, alleen fast-forward).\n' "$BOLD" "$RESET"
printf '    • Lees eerst %s%s/ser-deploy/START.md%s, daarna per repo %sAGENTS.md%s en %sdocs/ONTWIKKELEN.md%s.\n' "$BOLD" "$MAP" "$RESET" "$BOLD" "$RESET" "$BOLD" "$RESET"
printf '    • Werk op een eigen branch vanaf de %sverse integratiebranch%s (START.md §2) — nooit direct op main.\n' "$BOLD" "$RESET"
printf '    • Uitrollen naar productie doet Marten, of jij na expliciete afspraak met hem.\n'
printf '    • Geheimen staan in Keeper. Vraag Marten toegang tot de gedeelde map "SER Platform".\n'
printf '    • Zodra je toegang hebt: %s%s/ser-deploy/installer/install-platform.sh%s regelt de\n' "$DIM" "$MAP" "$RESET"
printf '      rest (Vercel-koppeling, VPS-alias, Google Drive-snelkoppeling).\n'

printf '\n'
info "Logboek: $LOG"
info "Nieuwe terminal openen, zodat PATH-wijzigingen actief worden."
printf '\n'
