#!/usr/bin/env bash
#
# Tests voor persoon.sh en de catalogus van install.sh/collega-toevoegen.sh.
# Alles met nep-commando's via PATH (security, claude, curl, uv, node, gh) in
# een tijdelijke HOME: er wordt niets op deze Mac geïnstalleerd en de echte
# sleutelhanger en Claude-config worden nooit aangeraakt.
#
#   bash tests/persoon.test.sh
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GOED="sera_0123456789abcdef.GoedGeheimGoedGeheim_1234"
NIETPERSOON="sera_fedcba9876543210.AnderGeheimAnderGeheim_99"
FOUT="sera_aaaaaaaaaaaaaaaa.FoutGeheimFoutGeheim_0000"
GESLAAGD=0; GEFAALD=0
SHELLCHECK="$(command -v shellcheck 2>/dev/null || true)"

geslaagd() { GESLAAGD=$((GESLAAGD + 1)); printf '  ✓ %s\n' "$1"; }
gefaald()  { GEFAALD=$((GEFAALD + 1)); printf '  ✗ %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -40 | sed 's/^/      /'; }
check()    { if eval "$2"; then geslaagd "$1"; else gefaald "$1" "${3:-}"; fi; }

# ── Nep-omgeving ────────────────────────────────────────────────────
maak_omgeving() {
  T="$(mktemp -d)"
  export HOME="$T/home" FAKE="$T/fake"
  mkdir -p "$HOME" "$FAKE/bin" "$HOME/Applications/Claude.app"
  : > "$FAKE/argv.log"; : > "$FAKE/hanger"

  cat > "$FAKE/bin/security" <<'SH'
#!/usr/bin/env bash
printf 'security %s\n' "$*" >> "$FAKE/argv.log"
case "$1" in
  find-generic-password)
    shift; d=""; a=""; w=0
    while [ $# -gt 0 ]; do case "$1" in -s) d="$2"; shift ;; -a) a="$2"; shift ;; -w) w=1 ;; esac; shift; done
    regel="$(grep -F "$d|$a|" "$FAKE/hanger" | tail -1)"
    [ -n "$regel" ] || exit 44
    [ "$w" -eq 1 ] && printf '%s\n' "${regel#"$d|$a|"}"
    exit 0 ;;
  -i)
    while read -r cmd rest; do
      [ "$cmd" = "add-generic-password" ] || continue
      set -- $rest; d=""; a=""; pw=""
      while [ $# -gt 0 ]; do case "$1" in -s) d="$2"; shift ;; -a) a="$2"; shift ;; -w) pw="$2"; shift ;; esac; shift; done
      grep -vF "$d|$a|" "$FAKE/hanger" > "$FAKE/hanger.n" || true
      printf '%s|%s|%s\n' "$d" "$a" "$pw" >> "$FAKE/hanger.n"; mv "$FAKE/hanger.n" "$FAKE/hanger"
    done
    exit 0 ;;
esac
exit 1
SH

  cat > "$FAKE/bin/claude" <<'SH'
#!/usr/bin/env bash
printf 'claude %s\n' "$*" >> "$FAKE/argv.log"
case "$1 ${2:-}" in
  "--version ") echo "2.1.0 (Claude Code)" ;;
  "auth status") if [ "${FAKE_CLAUDE_LOGIN:-1}" = "1" ]; then echo '{"loggedIn": true}'; else echo '{"loggedIn": false}'; fi ;;
  "auth login") exit 1 ;;
  "mcp remove") rm -f "$FAKE/claude-mcp.json" ;;
  "mcp add-json") printf '%s' "$6" > "$FAKE/claude-mcp.json" ;;
  "mcp get") [ -f "$FAKE/claude-mcp.json" ] && printf 'ser:\n  Scope: User config\n  Status: ✔ Connected\n' || echo 'No MCP server named "ser".' ;;
esac
exit 0
SH

  cat > "$FAKE/bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$FAKE/argv.log"
uit=""; schrijf=""; conf=0
while [ $# -gt 0 ]; do case "$1" in -o) uit="$2"; shift ;; -w) schrijf="$2"; shift ;; -K) conf=1; shift ;; esac; shift; done
token=""
[ "$conf" -eq 1 ] && token="$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p')"
case "$token" in
  "$FAKE_GOED")        code=200; body='{"agent_id":"0123456789abcdef","client_id":"__ser__","persoon":true,"medewerker":"robin@searchengineresults.nl"}' ;;
  "$FAKE_NIETPERSOON") code=200; body='{"agent_id":"fedcba9876543210","client_id":"__ser__"}' ;;
  *)                   code=401; body='{"detail":"Ongeldig token"}' ;;
esac
[ "${FAKE_OFFLINE:-0}" = "1" ] && { echo "curl: (6) Could not resolve host" >&2; printf '000'; exit 6; }
[ -n "$uit" ] && printf '%s' "$body" > "$uit"
[ -n "$schrijf" ] && printf '%s' "$code"
exit 0
SH

  cat > "$FAKE/bin/uv" <<'SH'
#!/usr/bin/env bash
printf 'uv %s\n' "$*" >> "$FAKE/argv.log"
case "$1" in
  --version) echo "uv 0.9.0" ;;
  python) exit 0 ;;
  run) while [ $# -gt 0 ] && [ "$1" != "python" ]; do shift; done; shift; exec python3 "$@" ;;
esac
SH

  cat > "$FAKE/bin/node" <<'SH'
#!/usr/bin/env bash
echo "v${FAKE_NODE:-22.1.0}"
SH

  cat > "$FAKE/bin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$FAKE/argv.log"
case "$1 ${2:-}" in
  "auth status") exit 0 ;;
  "api user") echo "robin-ser" ;;
  "repo view") case " ${FAKE_GEEN_TOEGANG:-} " in *" ${3#SearchEngineResultsNL/} "*) exit 1 ;; esac; exit 0 ;;
  "api -X") exit 0 ;;
esac
exit 0
SH

  # Nep-install.sh: legt vast wat gevraagd is en zet de mappen neer.
  cat > "$FAKE/install.sh" <<'SH'
#!/usr/bin/env bash
printf 'install.sh %s\n' "$*" >> "$FAKE/argv.log"
for o in "$@"; do
  case "$o" in
    ser-mcp) mkdir -p "$HOME/.ser-mcp/.git" "$HOME/.ser-mcp/mcp-server"
             cp "$FAKE/mcp-server.sh" "$HOME/.ser-mcp/mcp-server/start-met-sleutelhanger.sh"
             chmod +x "$HOME/.ser-mcp/mcp-server/start-met-sleutelhanger.sh" ;;
    seo-agent) mkdir -p "$HOME/SEO Agent/.git" ;;
    cro-agent) case " ${FAKE_GEEN_TOEGANG:-} " in *" cro-agent "*) ;; *) mkdir -p "$HOME/CRO Agent/.git" ;; esac ;;
    ai-agent)  mkdir -p "$HOME/AI Agent/.git" ;;
    skills-*)  mkdir -p "$HOME/.claude/skills/${o#skills-}" ;;
  esac
done
SH

  # Nep-MCP-server, zoals start-met-sleutelhanger.sh: token uit de sleutelhanger, dan JSON-RPC.
  cat > "$FAKE/mcp-server.sh" <<'SH'
#!/usr/bin/env bash
TOKEN="$(security find-generic-password -s ser-persoonstoken -a "$USER" -w 2>/dev/null)" || { echo "Geen agent-token" >&2; exit 1; }
[ "$UV_PYTHON" = "3.12" ] || { echo "UV_PYTHON ontbreekt" >&2; exit 1; }
export SER_AGENT_TOKEN="$TOKEN"
exec python3 -c '
import json, os, sys
for regel in sys.stdin:
    m = json.loads(regel)
    if m.get("method") == "initialize":
        print(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": {"protocolVersion": "2025-06-18", "capabilities": {}, "serverInfo": {"name": "nep", "version": "1"}}}), flush=True)
    elif m.get("method") == "tools/call":
        ok = os.environ.get("SER_AGENT_TOKEN") == os.environ.get("FAKE_GOED")
        tekst = json.dumps({"klanten": [{"id": "a"}, {"id": "b"}]}) if ok else "HTTP 401 Ongeldig token"
        print(json.dumps({"jsonrpc": "2.0", "id": m["id"], "result": {"content": [{"type": "text", "text": tekst}], "isError": not ok}}), flush=True)
'
SH
  chmod +x "$FAKE"/bin/* "$FAKE/install.sh" "$FAKE/mcp-server.sh"

  DESK="$HOME/Library/Application Support/Claude"
  mkdir -p "$DESK"
  printf '{\n  "globalShortcut": "Alt+Space",\n  "mcpServers": {\n    "ander": {"command": "/bin/echo"}\n  }\n}\n' > "$DESK/claude_desktop_config.json"

  export PATH="$FAKE/bin:/usr/bin:/bin:/usr/sbin:/sbin:$(dirname "$(command -v python3)")"
  export FAKE_GOED="$GOED" FAKE_NIETPERSOON="$NIETPERSOON"
  export SER_PERSOON_TEST=1 SER_BREW_BIN=/bestaat-niet SER_INSTALL_SH="$FAKE/install.sh" SER_CLAUDE_APP=/bestaat-niet TMPDIR="$T"
  export USER=robin
  unset CONDA_PREFIX CONDA_DEFAULT_ENV VIRTUAL_ENV
}

draai() {  # draai <invoer> [opties...] → $UIT, $RC
  printf '%b' "$1" > "$T/invoer"; shift
  UIT="$(SER_PERSOON_INVOER="$T/invoer" bash "$REPO/persoon.sh" "$@" 2>&1)"; RC=$?
}

opruimen() { rm -rf "$T"; }

printf '\npersoon.sh\n'

# 1. Verse Mac: alles in één keer goed
maak_omgeving
export CONDA_DEFAULT_ENV=base
draai "$GOED\n"
unset CONDA_DEFAULT_ENV
check "verse installatie eindigt met exit 0" '[ "$RC" -eq 0 ]' "$UIT"
check "token staat onder ser-persoonstoken in de (nep-)sleutelhanger" 'grep -qxF "ser-persoonstoken|robin|$GOED" "$FAKE/hanger"'
check "token komt in geen enkele argumentenlijst" '! grep -q "sera_" "$FAKE/argv.log"' "$(grep sera_ "$FAKE/argv.log")"
check "token komt niet in de uitvoer" '! printf "%s" "$UIT" | grep -q "GoedGeheim"'
check "token staat in geen enkel bestand in HOME" '! grep -rqs "GoedGeheim" "$HOME"'
check "token staat niet in het logboek" '! grep -qs "GoedGeheim" "$T/ser-persoon.log"'
check "security alleen met -i (nooit -w <token>)" 'grep -q "^security -i$" "$FAKE/argv.log"'
check "controle via capabilities met de kop op stdin (-K -)" 'grep -q "^curl .*-K - https://api-analytics.searchengineresults.nl/api/agent/analytics/capabilities" "$FAKE/argv.log"'
check "medewerker uit capabilities gemeld" 'printf "%s" "$UIT" | grep -q "persoonstoken van robin@searchengineresults.nl"'
check "conda gemeld, niet aangepast" 'printf "%s" "$UIT" | grep -q "Conda is actief (base)"'
check "install.sh krijgt het pakket agents in onderdelen" 'grep -q "^install.sh ser-mcp seo-agent skills-seo cro-agent ai-agent skills-ads$" "$FAKE/argv.log"' "$(grep install.sh "$FAKE/argv.log")"
check "Claude Code: ser op user-scope met startscript en UV_PYTHON, zonder token" \
  'grep -q "^claude mcp add-json -s user ser " "$FAKE/argv.log" && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d[\"command\"].endswith(\"/.ser-mcp/mcp-server/start-met-sleutelhanger.sh\"); assert d[\"env\"]==dict(UV_PYTHON=\"3.12\")" "$FAKE/claude-mcp.json"'
check "Claude-app-config: ser erbij, rest behouden, met PATH, zonder token" \
  'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); s=d[\"mcpServers\"]; assert d[\"globalShortcut\"]==\"Alt+Space\"; assert s[\"ander\"]==dict(command=\"/bin/echo\"); assert s[\"ser\"][\"env\"][\"UV_PYTHON\"]==\"3.12\"; assert \".local/bin\" in s[\"ser\"][\"env\"][\"PATH\"]; assert \"type\" not in s[\"ser\"]" "$DESK/claude_desktop_config.json"'
check "back-up van de app-config gemaakt" 'ls "$DESK"/claude_desktop_config.json.bak-ser-* >/dev/null 2>&1'
check "app-config alleen voor de eigenaar leesbaar" '[ "$(stat -f %Lp "$DESK/claude_desktop_config.json" 2>/dev/null || stat -c %a "$DESK/claude_desktop_config.json")" = "600" ]'
check "eindcontrole: ser verbonden" 'printf "%s" "$UIT" | grep -q "ser is verbonden"'
check "eindcontrole: echte MCP-aanroep ser_klanten (2 klanten, geen namen)" 'printf "%s" "$UIT" | grep -q "ser_klanten werkt (2 klanten zichtbaar)"' "$UIT"
check "samenvatting zonder ✗" '! printf "%s" "$UIT" | sed -n "/Samenvatting/,\$p" | grep -q "✗"'

# 2. Opnieuw draaien = niets kapot, niets dubbel, geen tokenvraag
BAKS="$(ls "$DESK" | grep -c bak-ser)"
: > "$FAKE/argv.log"
draai ""
check "tweede run: exit 0 zonder invoer (token al aanwezig en geldig)" '[ "$RC" -eq 0 ]' "$UIT"
check "tweede run: vraagt niet opnieuw om het token" '! printf "%s" "$UIT" | grep -q "Persoonstoken (sera_"'
check "tweede run: geen nieuwe schrijfactie in de sleutelhanger" '! grep -q "^security -i" "$FAKE/argv.log"'
check "tweede run: app-config ongewijzigd, geen extra back-up" 'printf "%s" "$UIT" | grep -q "koppeling stond er al" && [ "$(ls "$DESK" | grep -c bak-ser)" = "$BAKS" ]'
check "tweede run: één regel in de sleutelhanger" '[ "$(grep -c "^ser-persoonstoken|" "$FAKE/hanger")" = "1" ]'
check "tweede run: ook bij een bestaande sleutel geen token in argv" '! grep -q "sera_" "$FAKE/argv.log"'

# 3. --nieuw-token vervangt
draai "$NIETPERSOON\n" --nieuw-token
check "--nieuw-token vervangt het token" 'grep -qxF "ser-persoonstoken|robin|$NIETPERSOON" "$FAKE/hanger" && [ "$(grep -c "^ser-persoonstoken|" "$FAKE/hanger")" = "1" ]'
check "waarschuwing als het geen persoonstoken is" 'printf "%s" "$UIT" | grep -q "geen persoonstoken"'
opruimen

# 4. Ongeldig token: duidelijke melding bij 401, niets opgeslagen
maak_omgeving
draai "$FOUT\n$FOUT\n$FOUT\n" --zonder-agents
check "401 geeft een duidelijke melding" 'printf "%s" "$UIT" | grep -q "weigert dit token (401)"'
check "ongeldig token wordt niet opgeslagen" '! grep -q "^ser-persoonstoken|" "$FAKE/hanger"'
check "ongeldig token: exit ≠ 0" '[ "$RC" -ne 0 ]'
check "geen token in argv bij een fout token" '! grep -q "sera_" "$FAKE/argv.log"'
opruimen

# 5. Rommel om het token heen wordt weggehaald; vorm wordt gecontroleerd
maak_omgeving
draai "geen-token\n  export SER_AGENT_TOKEN=\"$GOED\"  \n" --zonder-agents
check "verkeerde vorm: nieuwe poging" 'printf "%s" "$UIT" | grep -q "lijkt geen persoonstoken"'
check "aanhalingstekens/export eraf en daarna opgeslagen" 'grep -qxF "ser-persoonstoken|robin|$GOED" "$FAKE/hanger"'
opruimen

# 6. Droge run: niets gewijzigd
maak_omgeving
VOOR="$(cksum < "$DESK/claude_desktop_config.json")"
draai "" --droog
check "droog: exit 0" '[ "$RC" -eq 0 ]' "$UIT"
check "droog: sleutelhanger leeg" '[ ! -s "$FAKE/hanger" ]'
check "droog: geen claude mcp add" '! grep -q "mcp add" "$FAKE/argv.log" && [ ! -f "$FAKE/claude-mcp.json" ]'
check "droog: install.sh niet gedraaid" '! grep -q "^install.sh" "$FAKE/argv.log"'
check "droog: app-config ongewijzigd en geen back-up" '[ "$(cksum < "$DESK/claude_desktop_config.json")" = "$VOOR" ] && ! ls "$DESK" | grep -q bak-ser'
check "droog: toegang wel gecontroleerd" 'grep -q "^gh repo view SearchEngineResultsNL/ser-automation-platform" "$FAKE/argv.log"'
check "droog: meldt dat er niets gewijzigd is" 'printf "%s" "$UIT" | grep -q "er is niets gewijzigd"'
opruimen

# 7. Ongeldige JSON in de app-config: niet aanraken
maak_omgeving
printf '{ kapot' > "$DESK/claude_desktop_config.json"
draai "$GOED\n" --zonder-agents
check "ongeldige app-config blijft onaangeraakt" '[ "$(cat "$DESK/claude_desktop_config.json")" = "{ kapot" ]'
check "ongeldige app-config gemeld met ✗" 'printf "%s" "$UIT" | grep -q "geen geldige JSON"'
opruimen

# 8. Geen GitHub-toegang: precies zeggen wat Marten moet doen
maak_omgeving
export FAKE_GEEN_TOEGANG="cro-agent"
draai "$GOED\n"
unset FAKE_GEEN_TOEGANG
check "ontbrekende toegang: melding met repo" 'printf "%s" "$UIT" | grep -q "kan deze privé-repo.s niet lezen: cro-agent"'
check "ontbrekende toegang: opdracht voor Marten" 'printf "%s" "$UIT" | grep -q "bash collega-toevoegen.sh robin-ser agents"'
check "ontbrekende toegang: ✗ voor cro-agent, rest gekoppeld" 'printf "%s" "$UIT" | grep -q "cro-agent niet geïnstalleerd" && [ -f "$FAKE/claude-mcp.json" ]'
opruimen

# 9. --agents en --zonder-agents
maak_omgeving
draai "$GOED\n" --agents=seo
check "--agents=seo: alleen ser-mcp, seo-agent en skills-seo" 'grep -q "^install.sh ser-mcp seo-agent skills-seo$" "$FAKE/argv.log"'
: > "$FAKE/argv.log"
draai "" --zonder-agents
check "--zonder-agents: alleen de ser-MCP" 'grep -q "^install.sh ser-mcp$" "$FAKE/argv.log"'
draai "" --agents=onzin
check "onbekende agent geweigerd" '[ "$RC" -ne 0 ] && printf "%s" "$UIT" | grep -q "Onbekende agent"'
opruimen

# 10. Niet ingelogd in Claude Code en Node te oud: melden, doorgaan
maak_omgeving
export FAKE_CLAUDE_LOGIN=0 FAKE_NODE=18.2.0
draai "n\nn\n$GOED\n" --zonder-agents --zonder-app
unset FAKE_CLAUDE_LOGIN FAKE_NODE
check "niet ingelogd: één duidelijke stap (claude auth login)" 'printf "%s" "$UIT" | grep -q "claude auth login"'
check "Node 18 te oud gemeld; Homebrew alleen na bevestiging" 'printf "%s" "$UIT" | grep -q "te oud" && printf "%s" "$UIT" | grep -q "Homebrew installeren?"'
check "token toch opgeslagen (doorgaan na een melding)" 'grep -qxF "ser-persoonstoken|robin|$GOED" "$FAKE/hanger"'
opruimen

# 11. Platform onbereikbaar: wel opslaan, als niet-gecontroleerd melden
maak_omgeving
export FAKE_OFFLINE=1
draai "$GOED\n" --zonder-agents
unset FAKE_OFFLINE
check "offline: token opgeslagen met waarschuwing" 'grep -qxF "ser-persoonstoken|robin|$GOED" "$FAKE/hanger" && printf "%s" "$UIT" | grep -q "niet gecontroleerd"'
opruimen

# 12. Zoals 'curl … | bash': script via stdin, antwoorden via de terminal
maak_omgeving
printf '%s\n' "$GOED" > "$T/invoer"
UIT="$(SER_PERSOON_INVOER="$T/invoer" bash < "$REPO/persoon.sh" 2>&1)"; RC=$?
check "via stdin (curl | bash) werkt het hele script" '[ "$RC" -eq 0 ] && grep -qxF "ser-persoonstoken|robin|$GOED" "$FAKE/hanger"' "$UIT"
opruimen

# 13. Zonder terminal en zonder invoerbestand: nette fout, niets gedaan
if ! (: < /dev/tty) 2>/dev/null; then
  maak_omgeving
  UIT="$(bash "$REPO/persoon.sh" < /dev/null 2>&1)"; RC=$?
  check "zonder terminal: duidelijke fout, niets opgeslagen" '[ "$RC" -ne 0 ] && printf "%s" "$UIT" | grep -q "geen terminal" && [ ! -s "$FAKE/hanger" ]' "$UIT"
  opruimen
else
  printf '  - test zonder terminal overgeslagen (deze sessie heeft een terminal)\n'
fi

printf '\ninstall.sh en collega-toevoegen.sh\n'

check "install.sh: syntax" 'bash -n "$REPO/install.sh"'
check "collega-toevoegen.sh: syntax" 'bash -n "$REPO/collega-toevoegen.sh"'
check "catalogus: ser-mcp (type mcp), cro-agent en het pakket agents" \
  'grep -q "\"ser-mcp|mcp|agents|" "$REPO/install.sh" && grep -q "\"cro-agent|clone|cro,agents|" "$REPO/install.sh" && grep -q "\"agents|" "$REPO/install.sh"'

maak_omgeving
UIT="$(cd "$REPO" && bash collega-toevoegen.sh robin-ser agents 2>&1)"
for r in ser-automation-platform seo-agent cro-agent ai-agent ser-skills; do
  check "collega-toevoegen agents → $r" 'grep -q "^gh api -X PUT repos/SearchEngineResultsNL/$r/collaborators/robin-ser" "$FAKE/argv.log"' "$UIT"
done
check "collega-toevoegen agents: geen gewone tools" '! grep -q "ser-alt-teksten" "$FAKE/argv.log"'
: > "$FAKE/argv.log"
UIT="$(cd "$REPO" && bash collega-toevoegen.sh robin-ser seo 2>&1)"
check "collega-toevoegen seo: géén platform-repo" '! grep -q "ser-automation-platform" "$FAKE/argv.log"' "$UIT"
opruimen

if [ -n "$SHELLCHECK" ]; then
  check "shellcheck persoon.sh" '"$SHELLCHECK" -S warning "$REPO/persoon.sh"' "$("$SHELLCHECK" -S warning "$REPO/persoon.sh" 2>&1)"
  check "shellcheck install.sh en collega-toevoegen.sh (warning)" '"$SHELLCHECK" -S warning "$REPO/install.sh" "$REPO/collega-toevoegen.sh"' "$("$SHELLCHECK" -S warning "$REPO/install.sh" "$REPO/collega-toevoegen.sh" 2>&1 | head -30)"
else
  printf '  - shellcheck niet aanwezig, overgeslagen\n'
fi

printf '\n%d geslaagd, %d mislukt\n' "$GESLAAGD" "$GEFAALD"
[ "$GEFAALD" -eq 0 ]
