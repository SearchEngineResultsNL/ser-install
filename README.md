# SER-install

Eén commando om onze tools, de Google Ads-agent en de Claude Code-skills op
je Mac te zetten. Je hoeft niets voor te bereiden: het script regelt zelf
Python, `uv`, de GitHub CLI en het inloggen.

## Nieuwe collega: alles in één regel (persoonstoken)

Maak eerst je persoonstoken in Studio: **Beheer › Agents en tokens ›
Persoonstoken (alle klanten)**. Draai daarna in Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/persoon.sh | bash
```

Plak je token als erom gevraagd wordt. Het blijft onzichtbaar en gaat alleen
naar de macOS-sleutelhanger (dienst `ser-persoonstoken`): nooit in die regel,
je shell-geschiedenis, een bestand of een Claude-config.

Het script zet in één keer goed (opnieuw draaien = repareren):

| Stap | Wat |
|---|---|
| 1. Basis | Command Line Tools/git, `uv` met een vaste **Python 3.12**, Node 20+. Je eigen Python (systeem, conda, pyenv) blijft ongemoeid; een actieve conda/oude python3 wordt alleen gemeld. Homebrew alleen als het echt nodig is, na een vraag. |
| 2. Claude | Claude Code (officiële installer) + inloggen (`claude auth login`), en de Claude-app (na een vraag: `brew install --cask claude` of de downloadpagina). |
| 3. Token | Verborgen vragen, controleren bij Studio (`/api/agent/analytics/capabilities`; duidelijke melding bij 401/403), opslaan. Staat er al een werkend token, dan wordt niets gevraagd. |
| 4. Agents | Via `install.sh agents`: GitHub-login, de ser-MCP (`~/.ser-mcp`, alleen `mcp-server/`), de SEO-, CRO- en Ads-agent (`~/SEO Agent`, `~/CRO Agent`, `~/AI Agent`, elk met zijn eigen installatie) en de `/seo`- en `/ads`-skills. |
| 5. MCP | `ser` op user-scope in Claude Code en in `claude_desktop_config.json` (samengevoegd, met back-up). Alleen het pad naar `start-met-sleutelhanger.sh` en `UV_PYTHON=3.12`, nooit het token. |
| 6. Controle | `claude mcp get ser` verbonden, een echte testaanroep `ser_klanten` (alleen het aantal klanten), agentmappen; samenvatting met ✓/✗ en wat jij of Marten nog moet doen. |

Opties (`… | bash -s -- <optie>`):

| Optie | |
|---|---|
| `--droog` | alleen kijken; installeert en wijzigt niets |
| `--nieuw-token` | token vervangen (verlopen of ingetrokken) |
| `--agents=seo,cro` | alleen deze agents (`seo`, `cro`, `ads`) |
| `--zonder-agents` | alleen token + ser-MCP |
| `--zonder-app` | de Claude-app overslaan |

Lukt een stap niet (geen GitHub-toegang, nog niet ingelogd), dan zegt de
samenvatting precies wat er moet gebeuren; daarna dezelfde regel opnieuw.
Werkt nu alleen op macOS. Logboek: `$TMPDIR/ser-persoon.log`.

## Een pakket installeren

```bash
# Alles voor SEO — 14 tools, de SEO-agent en de /seo-audits in Claude Code
curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/install.sh | bash -s -- seo

# Alles voor advertenties — de Google Ads-agent plus de /ads-audits
curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/install.sh | bash -s -- ads

# Alles
curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/install.sh | bash -s -- alles
```

## Zelf kiezen

Zonder argument krijg je een lijst waarin je met de pijltjes en de spatiebalk
aanvinkt wat je wilt:

```bash
curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/install.sh | bash
```

## Eén onderdeel

```bash
curl -fsSL https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/install.sh | bash -s -- ser-alt-teksten
```

## Eerst kijken wat er gebeurt

Controleert je toegang tot alle repo's, maar installeert niets:

```bash
curl -fsSLO https://raw.githubusercontent.com/SearchEngineResultsNL/ser-install/main/install.sh
SER_DRYRUN=1 bash install.sh alles
```

---

## Pakketten

| Pakket | Inhoud |
|---|---|
| `seo` | 14 SEO-tools + de `/seo`-skills en hun subagents |
| `ads` | De Google Ads-agent + de `/ads`-skills en hun subagents |
| `cro` | De CRO-agent |
| `agents` | De ser-MCP, de SEO-, CRO- en Ads-agent en de skills (wat `persoon.sh` gebruikt) |
| `data` | Alleen de data-exports: Search Console, GA4, backlinkdata |
| `kantoor` | Losse kantoortools |
| `alles` | Alles hierboven |

## Wat er in de catalogus staat

### A/B-testen

| Commando | Wat het doet |
|---|---|
| [`ser-ab-testplatform`](https://github.com/SearchEngineResultsNL/ser-ab-testplatform) | Complete SEO A/B-test: data uit Search Console of BigQuery, URL's in statistisch gelijke groepen, effect meten met Bayesiaanse causal impact-analyse. **Begin hier** — de drie tools hieronder zitten er al in. |
| [`ser-ab-test-groepen`](https://github.com/SearchEngineResultsNL/ser-ab-test-groepen) | Alleen de groepenstap: URL's splitsen in twee vergelijkbare groepen, met outlierdetectie en toetsing. |
| [`ser-ab-test-voorbereiden`](https://github.com/SearchEngineResultsNL/ser-ab-test-voorbereiden) | Alleen de voorbereidingsstap: ruwe CSV omzetten naar een bestand dat de analyse inleest. |
| [`ser-search-console-export`](https://github.com/SearchEngineResultsNL/ser-search-console-export) | Alleen de datastap: Search Console-data in bulk exporteren, voorbij de limiet van 25.000 rijen. |

### Content maken

| Commando | Wat het doet |
|---|---|
| [`ser-titels-en-metas`](https://github.com/SearchEngineResultsNL/ser-titels-en-metas) | Paginatitels en meta descriptions schrijven op basis van een Screaming Frog-crawl plus keyworddata. |
| [`ser-titels-en-metas-batch`](https://github.com/SearchEngineResultsNL/ser-titels-en-metas-batch) | Zelfde titels en meta's, maar via de Batch-API — ongeveer half zo duur bij duizenden URL's. |
| [`ser-alt-teksten`](https://github.com/SearchEngineResultsNL/ser-alt-teksten) | ALT-teksten genereren door de afbeelding echt te laten bekijken door Claude Vision. |
| [`ser-faq-generator`](https://github.com/SearchEngineResultsNL/ser-faq-generator) | People Also Ask-vragen omzetten naar FAQ-content, inclusief clustering en interne links. |
| [`ser-teksten-batch`](https://github.com/SearchEngineResultsNL/ser-teksten-batch) | Grote hoeveelheden teksten via de Batch-API van OpenAI of Anthropic: ongeveer half zo duur, klaar binnen 24 uur. |

### AI-zoekresultaten

| Commando | Wat het doet |
|---|---|
| [`ser-ai-overviews`](https://github.com/SearchEngineResultsNL/ser-ai-overviews) | Per zoekvraag uitlezen wat Google's AI Overview antwoordt en je content daarop herschrijven. |
| [`ser-ai-overviews-turbo`](https://github.com/SearchEngineResultsNL/ser-ai-overviews-turbo) | Zelfde analyse, asynchroon en parallel — voor duizenden vragen. |

### Onderzoek en data

| Commando | Wat het doet |
|---|---|
| [`ser-vragen-clustering`](https://github.com/SearchEngineResultsNL/ser-vragen-clustering) | Duizenden zoekvragen clusteren op betekenis met embeddings, UMAP en DBSCAN; GPT benoemt de clusters. Zwaar: ongeveer 2 GB aan libraries. |
| [`ser-linkdata-harvester`](https://github.com/SearchEngineResultsNL/ser-linkdata-harvester) | Backlink- en autoriteitsdata uit Ahrefs, Semrush, Majestic en SerpAPI in één run. |
| [`ser-ga4-export`](https://github.com/SearchEngineResultsNL/ser-ga4-export) | GA4-data exporteren met vrije keuze uit dimensies en metrics, met quotabewaking. |
| [`ser-geo-embeddings`](https://github.com/SearchEngineResultsNL/ser-geo-embeddings) | Nederlandse locatie-URL's geocoderen en geografische embeddings maken voor lokale SEO. |

### Kantoor

| Commando | Wat het doet |
|---|---|
| [`ser-handtekeningen`](https://github.com/SearchEngineResultsNL/ser-handtekeningen) | Gmail-handtekeningen centraal beheren en uitrollen via Google Workspace. |

### Claude Code

Geen terminalcommando's, maar uitbreidingen van Claude Code zelf.

| Onderdeel | Wat het doet |
|---|---|
| [`ai-agent`](https://github.com/SearchEngineResultsNL/ai-agent) | Google Ads-agent met klantcontext, rapportages en audits. Komt in `~/AI Agent` en draait daar zijn eigen installatie (15-30 minuten). Lees daarna `HANDLEIDING.md`. |
| [`seo-agent`](https://github.com/SearchEngineResultsNL/seo-agent) | SEO-agent: SEO-audits met rapport in SER-huisstijl. Komt in `~/SEO Agent` en draait daar `install.sh` (koppeling SER-platform). Samenwerken: `docs/samenwerken.md`. |
| [`cro-agent`](https://github.com/SearchEngineResultsNL/cro-agent) | CRO-agent: platform-audits van sites en landingspagina's. Komt in `~/CRO Agent`. |
| `ser-mcp` | De ser-MCP (brug naar Studio en Tools): alleen de map `mcp-server/` uit [`ser-automation-platform`](https://github.com/SearchEngineResultsNL/ser-automation-platform), als alleen-lezen kopie in `~/.ser-mcp`. Koppelen met je token: `persoon.sh`. |
| `skills-seo` | De `/seo`-commando's plus hun zes subagents. Uit [`ser-skills`](https://github.com/SearchEngineResultsNL/ser-skills). |
| `skills-ads` | De `/ads`-commando's plus hun zes subagents. Uit dezelfde repo. |

---

## Een tool starten

```bash
ser-alt-teksten
```

De app opent in je browser. Stoppen: `Ctrl + C` in de terminal. Start het
commando in de map waar je je bestanden wilt hebben — downloads uit de app
komen daar terecht.

Geen enkele tool bevat sleutels. Die vul je in de app zelf in, per sessie.

## Bijwerken

```bash
uv tool upgrade --all                        # alle tools
bash install.sh skills-seo                   # de skills opnieuw ophalen
```

---

## Hoe het werkt

Drie soorten onderdelen, elk met zijn eigen manier van installeren:

| Type | Wat er gebeurt |
|---|---|
| `uv` | `uv tool install` maakt van de Streamlit-app een commando in `~/.local/bin`. Elke tool krijgt zijn eigen libraries; ze kunnen elkaar niet breken. |
| `clone` | De repo wordt gekloond en zijn eigen `install.sh` draait. |
| `mcp` | Ondiepe sparse-clone van `mcp-server/` naar `~/.ser-mcp` (pushen uit), libraries via `uv` op Python 3.12. Zelfde indeling als `scripts/ser-mcp-bijwerken.sh` in de agents. |
| `skills` | [`ser-skills`](https://github.com/SearchEngineResultsNL/ser-skills) wordt gekloond en de skills en subagents gaan naar `~/.claude/`. |

Python komt via `uv` en staat vast op **3.12** — `torch` en `umap-learn`
hebben nog geen 3.13-wielen. Je systeem-Python blijft ongemoeid.

Deze repo is publiek en bevat bewust **geen code en geen sleutels**. Zonder
toegang tot de privé-repo's installeer je niets. Staat er nog een uitnodiging
open, dan accepteert de installer die zelf — niemand hoeft door zijn mail te
spitten.

---

## Voor beheerders

### Iemand toegang geven

```bash
bash collega-toevoegen.sh <github-gebruikersnaam>              # alles, alleen lezen
bash collega-toevoegen.sh <github-gebruikersnaam> ads          # alleen de Ads-repo's
bash collega-toevoegen.sh <github-gebruikersnaam> seo push     # SEO, mag wijzigen
```

De repolijst komt uit de catalogus in `install.sh`, dus die hoef je niet op
twee plekken bij te houden.

Voor `persoon.sh` heeft een collega het pakket `agents` nodig:

```bash
bash collega-toevoegen.sh <github-gebruikersnaam> agents
```

Dat geeft leesrecht op `seo-agent`, `cro-agent`, `ai-agent`, `ser-skills` en
`ser-automation-platform` (voor de ser-MCP; alleen de map `mcp-server/` wordt
opgehaald, maar het recht geldt voor de hele repo). Ook `alles` bevat ze.

### Een tool toevoegen

Eén regel in de `CATALOGUS` in `install.sh`:

```bash
"ser-nieuwe-tool|uv|seo|Wat de tool doet, in één regel"
```

De velden zijn `naam|type|pakketten|omschrijving`. Meerdere pakketten mag:
`seo,data`. Daarmee staat de tool in het menu, in het pakket, en in
`collega-toevoegen.sh`.

### Waar wat staat

| Wat | Waar |
|---|---|
| Deze installer | `SearchEngineResultsNL/ser-install` (publiek) |
| De skills | `SearchEngineResultsNL/ser-skills` (privé) |
| De Ads-agent | `SearchEngineResultsNL/ai-agent` (privé) |
| De SEO-agent | `SearchEngineResultsNL/seo-agent` (privé) |
| Elke tool | `SearchEngineResultsNL/ser-<naam>` (privé) |
| Logboek van een installatie | `$TMPDIR/ser-install.log` |
| Logboek van `persoon.sh` | `$TMPDIR/ser-persoon.log` |
| De ser-MCP (kopie) | `~/.ser-mcp/mcp-server/` |
| Het persoonstoken | macOS-sleutelhanger, dienst `ser-persoonstoken` |
| Werkmap voor gekloonde repo's | `~/.ser-install/` |

Pas een tool aan **in zijn repo**, niet in een los bestand op je Mac.

---

## Als iets niet werkt

**"Het commando wordt niet gevonden"** — open een nieuwe terminal, of draai
`export PATH="$HOME/.local/bin:$PATH"`.

**Testen** — `bash tests/persoon.test.sh` (nep-commando's, raakt je Mac niet).

**"Geen toegang tot …"** — je GitHub-account is nog geen collaborator, of je
bent ingelogd met je privé-account. Wisselen: `gh auth switch`.

**Installatie mislukt** — de laatste regels van het logboek komen in beeld;
het geheel staat in `$TMPDIR/ser-install.log`.

**Skills werken niet na installatie** — start Claude Code opnieuw op.

**Screenshots in een audit mislukken** — de browser voor playwright ontbreekt:

```bash
~/.claude/skills/seo/.venv/bin/playwright install chromium
```
