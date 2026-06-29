# Rekker jeg ferga?

Sanntids ferge-kalkulator for Norge. Viser kjøretid til nærmeste fergekai og margin til neste avgang.

## Stack

- **Frontend:** Flutter Web (Cloudflare Pages)
- **Backend:** Cloudflare Worker (`/gateway`) — proxyer Google Routes API
- **Fergedata:** Entur Journey Planner GraphQL API
- **Kart:** Google Maps JavaScript API

## Lokal utvikling

```bash
flutter run -d web-server --web-port 8080 --web-hostname localhost
```

Worker lokalt (fra `/gateway`):
```bash
npx wrangler dev
```

Husk å bytte `_baseUrl` i `lib/services/drive_time_service.dart` til `http://localhost:8787` for lokal Worker-testing.

## Miljøer

| Branch | URL | Bruk |
|--------|-----|------|
| `main` | rekkerjegferga.pages.dev | Produksjon — ekte brukere |
| `dev`  | dev.rekkerjegferga.pages.dev | Utvikling — test her først |

Cloudflare Pages deployer begge branches automatisk ved push.

**Arbeidsflyt:**
1. Jobb på `dev`-branchen
2. Test på `dev.rekkerjegferga.pages.dev`
3. Når klar for produksjon: `git checkout main && git merge dev && git push`

## Deploy

Flutter-bygg og deploy til Cloudflare Pages:
```bash
flutter build web --release --base-href /
npx wrangler pages deploy build/web --project-name rekkerjegferga
```

Worker-deploy (fra `/gateway`):
```bash
npx wrangler deploy
```

Secrets (settes én gang via Wrangler, lagres aldri i kode):
```bash
npx wrangler secret put GOOGLE_MAPS_API_KEY
```

## API-nøkler

- **Maps JS API-nøkkel** (frontend) — ligger i `web/index.html`, begrenset til `*.rekkerjegferga.pages.dev/*` i Google Cloud Console
- **Routes API-nøkkel** (backend) — lagret som Wrangler secret `GOOGLE_MAPS_API_KEY`, kun Routes API aktivert, ingen referrer-begrensning
