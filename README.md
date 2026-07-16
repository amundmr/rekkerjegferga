# Rekker jeg ferga?

Sanntids ferge-kalkulator for Norge. Viser kjøretid til nærmeste fergekai og margin til neste avgang.

## Stack

- **Frontend:** SvelteKit + TypeScript, statisk bygget (`@sveltejs/adapter-static`), hostet på Cloudflare Pages (`/web-app`)
- **Backend:** Cloudflare Worker (`/gateway`) — proxyer Google Routes API, løser fergekai-koordinater via Places API (KV-cachet)
- **Fergedata:** Entur Journey Planner GraphQL API
- **Kart:** Google Maps JavaScript API

## Lokal utvikling

Frontend (fra `/web-app`):
```bash
npm run dev
```

Worker lokalt (fra `/gateway`):
```bash
npx wrangler dev
```

Husk å bytte `BASE_URL` i `web-app/src/lib/services/driveTime.ts` til `http://localhost:8787` for lokal Worker-testing.

## Miljøer

| Branch | URL | Bruk |
|--------|-----|------|
| `main` | rekkerjegferga.pages.dev | Produksjon — ekte brukere |
| `dev`  | dev.rekkerjegferga.pages.dev | Utvikling — test her først |

**Arbeidsflyt:**
1. Jobb på `dev`-branchen
2. Bygg og deploy til dev: se kommandoer under
3. Test på `dev.rekkerjegferga.pages.dev`
4. Når klar for produksjon: `git checkout main && git merge dev && git push`
5. Bygg og deploy til prod: se kommandoer under

## Deploy

Dev (→ dev.rekkerjegferga.pages.dev), fra `/web-app`:
```bash
npm run build
npx wrangler pages deploy build --project-name rekkerjegferga --branch dev
```

Prod (→ rekkerjegferga.pages.dev), fra `/web-app`:
```bash
npm run build
npx wrangler pages deploy build --project-name rekkerjegferga --branch main
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

- **Maps JS API-nøkkel** (frontend) — ligger i `web-app/src/app.html`, begrenset til `*.rekkerjegferga.pages.dev/*` i Google Cloud Console
- **Routes API-nøkkel** (backend) — lagret som Wrangler secret `GOOGLE_MAPS_API_KEY`, kun Routes API aktivert, ingen referrer-begrensning

## Kjente/pågående problemer

- **Entur `nearest()` mangler enkelte fergekaier i nærhets-søket.** Eksempel: fra Skei (61.5392092, 6.4406246) returnerer Enturs `nearest`-spørring aldri "Hella ferjekai" (`NSR:StopPlace:58324`, ~38 km unna), verken med `filterByModes: [water]` eller helt ufiltrert — testet med en uttømmende, ikke-avkuttet radius på 45 km (431 treff, siste i 44 972 m) uten at Hella dukker opp. Stedet finnes og har korrekt data (bl.a. `localCarFerry`-kai) når det hentes direkte via `stopPlace(id: ...)`, så det er stedet selv som mangler i Enturs nærhetsindeks — ikke noe som kan løses med spørringsparametre på vår side. Appen viser i stedet "Dragsvik ferjekai" (~88 km unna), som ruten uansett må passere gjennom Hella-Dragsvik-fergen for å nå, og gir dermed helt feil kjøretid/margin. Bør meldes til Entur. Se `web-app/src/lib/services/ferry.ts` `nearbyStops()`.

## Historikk

Appen var opprinnelig skrevet i Flutter Web. Den koden finnes bevart på branchen `flutter-legacy`.
