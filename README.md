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

### SEO-tools

| Onderdeel | Wat het doet |
|---|---|
| `ser-ab-testplatform` | SEO A/B-test van A tot Z: data, groepen, causal impact-analyse |
| `ser-ab-test-voorbereiden` | Ruwe CSV klaarzetten voor A/B-analyse |
| `ser-ab-test-groepen` | URL's splitsen in twee statistisch gelijke groepen |
| `ser-ai-overviews` | AI Overviews per zoekvraag uitlezen en content erop herschrijven |
| `ser-ai-overviews-turbo` | Zelfde, maar voor duizenden vragen tegelijk |
| `ser-alt-teksten` | ALT-teksten genereren met Claude Vision, in bulk vanuit een CSV |
| `ser-titels-en-metas` | Paginatitels en meta descriptions uit een Screaming Frog-crawl |
| `ser-titels-en-metas-batch` | Titels en meta's via de Batch-API, voor duizenden URL's |
| `ser-teksten-batch` | Teksten in bulk via de Batch-API (ongeveer half zo duur) |
| `ser-faq-generator` | People Also Ask-vragen omzetten naar FAQ-content met interne links |
| `ser-vragen-clustering` | Duizenden zoekvragen clusteren op betekenis (zwaar, ~2 GB) |
| `ser-geo-embeddings` | Nederlandse locatie-URL's geocoderen en geo-embeddings maken |

### Data-export

| Onderdeel | Wat het doet |
|---|---|
| `ser-search-console-export` | Search Console-data in bulk, voorbij de 25.000-rijenlimiet |
| `ser-linkdata-harvester` | Backlinkdata uit Ahrefs, Semrush, Majestic en SerpAPI in één run |
| `ser-ga4-export` | GA4-data exporteren met quotabewaking |

### Kantoor

| Onderdeel | Wat het doet |
|---|---|
| `ser-handtekeningen` | Gmail-handtekeningen centraal uitrollen over alle medewerkers |

### Claude Code

| Onderdeel | Wat het doet |
|---|---|
| `ai-agent` | Google Ads-agent met klantcontext, rapportages en audits. Komt in `~/AI Agent` en draait daar zijn eigen installatie (15-30 minuten). |
| `skills-seo` | De `/seo`-commando's in Claude Code plus hun zes subagents |
| `skills-ads` | De `/ads`-commando's in Claude Code plus hun zes subagents |

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
