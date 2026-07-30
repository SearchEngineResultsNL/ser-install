# SER-install

Eén commando om onze tools, de Google Ads-agent en de Claude Code-skills op
je Mac te zetten. Je hoeft niets voor te bereiden: het script regelt zelf
Python, `uv`, de GitHub CLI en het inloggen.

## Een pakket installeren

```bash
# Alles voor SEO — 14 tools plus de /seo-audits in Claude Code
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
| Elke tool | `SearchEngineResultsNL/ser-<naam>` (privé) |
| Logboek van een installatie | `$TMPDIR/ser-install.log` |
| Werkmap voor gekloonde repo's | `~/.ser-install/` |

Pas een tool aan **in zijn repo**, niet in een los bestand op je Mac.

---

## Als iets niet werkt

**"Het commando wordt niet gevonden"** — open een nieuwe terminal, of draai
`export PATH="$HOME/.local/bin:$PATH"`.

**"Geen toegang tot …"** — je GitHub-account is nog geen collaborator, of je
bent ingelogd met je privé-account. Wisselen: `gh auth switch`.

**Installatie mislukt** — de laatste regels van het logboek komen in beeld;
het geheel staat in `$TMPDIR/ser-install.log`.

**Skills werken niet na installatie** — start Claude Code opnieuw op.

**Screenshots in een audit mislukken** — de browser voor playwright ontbreekt:

```bash
~/.claude/skills/seo/.venv/bin/playwright install chromium
```
