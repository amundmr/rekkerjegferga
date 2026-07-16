<script lang="ts">
	import { onMount } from 'svelte';
	import { Car, ChevronDown, MapPin, Star } from 'lucide-svelte';
	import GoogleMap from '$lib/components/GoogleMap.svelte';
	import DepartureSheet from '$lib/components/DepartureSheet.svelte';
	import PortSwitcher from '$lib/components/PortSwitcher.svelte';
	import OverflowMenu from '$lib/components/OverflowMenu.svelte';
	import InfoDialog from '$lib/components/InfoDialog.svelte';
	import CustomOriginBanner from '$lib/components/CustomOriginBanner.svelte';
	import FavouritesSheet from '$lib/components/FavouritesSheet.svelte';
	import DestinationSwitcher from '$lib/components/DestinationSwitcher.svelte';
	import * as ferryService from '$lib/services/ferry';
	import * as driveTimeService from '$lib/services/driveTime';
	import * as favouritesService from '$lib/services/favourites';
	import * as destinationPreferenceService from '$lib/services/destinationPreference';
	import type { Departure, FerryStop, LatLng } from '$lib/types';

	const MY_LOCATION_ICON =
		'data:image/svg+xml;charset=UTF-8,' +
		encodeURIComponent(
			'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">' +
				'<circle cx="12" cy="12" r="12" fill="white"/>' +
				'<circle cx="12" cy="12" r="7" fill="#4285F4"/>' +
				'</svg>'
		);

	const CUSTOM_ORIGIN_ICON =
		'data:image/svg+xml;charset=UTF-8,' +
		encodeURIComponent(
			'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">' +
				'<circle cx="12" cy="12" r="12" fill="white"/>' +
				'<circle cx="12" cy="12" r="7" fill="#ef4444"/>' +
				'</svg>'
		);

	let sheetOpen = $state(false);
	let infoOpen = $state(false);
	let favouritesOpen = $state(false);

	let favourites = $state<Record<string, string>>({});
	let destinationPrefs: Record<string, string> = {};
	let selectedDestination = $state<string | null>(null);

	let position = $state<LatLng | null>(null);
	let locationError = $state<string | null>(null);
	let usingApproximateLocation = $state(false);
	let locationWarningDismissed = $state(false);

	// Two-step picker: while `customOriginMode && !originPlaced`, the
	// crosshair follows the map (`pendingOrigin`) but nothing is committed —
	// no network calls, no marker — so the user can freely pan/zoom to find
	// a spot. Pressing "Plasser nål" commits `pendingOrigin` into
	// `customOrigin`, which is what actually drives calculations from then on.
	let customOriginMode = $state(false);
	let originPlaced = $state(false);
	let pendingOrigin = $state<LatLng | null>(null);
	let customOrigin = $state<LatLng | null>(null);
	let suppressNextIdle = false;
	let mapComponent: GoogleMap | undefined = $state();

	let stops = $state<FerryStop[]>([]);
	let selectedIndex = $state(0);
	let loadingStops = $state(false);

	let departures = $state<Departure[]>([]);
	let driveTimeSeconds = $state<number | null>(null);
	let distanceMeters = $state<number | null>(null);
	let route = $state<LatLng[]>([]);

	let selectedStop = $derived(stops[selectedIndex] as FerryStop | undefined);

	// Ticks once a second so the countdown/margin labels stay live.
	let now = $state(Date.now());
	onMount(() => {
		const ticker = setInterval(() => (now = Date.now()), 1000);
		return () => clearInterval(ticker);
	});

	onMount(() => {
		favourites = favouritesService.load();
		destinationPrefs = destinationPreferenceService.load();
	});

	let arrival = $derived(driveTimeSeconds !== null ? now + driveTimeSeconds * 1000 : null);

	let distinctDestinations = $derived.by((): string[] => {
		const seen = new Set<string>();
		for (const d of departures) if (d.destination) seen.add(d.destination);
		return [...seen];
	});

	let visibleDepartures = $derived(
		selectedDestination === null
			? departures
			: departures.filter((d) => d.destination === selectedDestination)
	);

	let nextDep = $derived.by((): Departure | null => {
		if (arrival === null) return null;
		for (const d of visibleDepartures) {
			if (d.time.getTime() >= arrival) return d;
		}
		return null;
	});

	let prevDep = $derived.by((): Departure | null => {
		if (arrival === null) return null;
		let last: Departure | null = null;
		for (const d of visibleDepartures) {
			if (d.time.getTime() < arrival) last = d;
		}
		return last;
	});

	function marginFor(dep: Departure | null): number | null {
		if (driveTimeSeconds === null || dep === null) return null;
		return Math.round((dep.time.getTime() - now) / 1000) - driveTimeSeconds;
	}

	function formatMargin(seconds: number | null): string {
		if (seconds === null) return '—';
		const sign = seconds < 0 ? '−' : '+';
		const abs = Math.abs(seconds);
		if (abs < 60) return `${sign}${abs}s`;
		return `${sign}${Math.round(abs / 60)} min`;
	}

	function formatClock(date: Date | undefined | null): string {
		if (!date) return '—:—';
		return date.toLocaleTimeString('no-NO', { hour: '2-digit', minute: '2-digit' });
	}

	function formatDriveTime(seconds: number | null): string {
		if (seconds === null) return '';
		const h = Math.floor(seconds / 3600);
		const m = Math.round((seconds % 3600) / 60);
		if (h === 0) return `${m}m`;
		if (m === 0) return `${h}h`;
		return `${h}h ${m}m`;
	}

	function sortStops(list: FerryStop[]): FerryStop[] {
		return [...list].sort((a, b) => {
			const aFav = a.id in favourites;
			const bFav = b.id in favourites;
			if (aFav !== bFav) return aFav ? -1 : 1;
			return a.distanceMeters - b.distanceMeters;
		});
	}

	async function loadStopsFor(lat: number, lng: number) {
		loadingStops = true;
		const result = await ferryService.nearbyStops(lat, lng);
		stops = sortStops(result);
		selectedIndex = 0;
		loadingStops = false;
		if (stops.length > 0) {
			refreshDriveTime();
			refreshDepartures();
		}
	}

	function toggleFavourite(stopId: string) {
		const stop = stops.find((s) => s.id === stopId);
		if (!stop) return;
		const updated = { ...favourites };
		if (stopId in updated) {
			delete updated[stopId];
		} else {
			updated[stopId] = stop.name;
		}
		favourites = updated;
		favouritesService.save(favourites);
		const selectedId = selectedStop?.id;
		stops = sortStops(stops);
		if (selectedId) selectedIndex = stops.findIndex((s) => s.id === selectedId);
	}

	function removeFavourite(stopId: string) {
		const updated = { ...favourites };
		delete updated[stopId];
		favourites = updated;
		favouritesService.save(favourites);
		const selectedId = selectedStop?.id;
		stops = sortStops(stops);
		if (selectedId) selectedIndex = stops.findIndex((s) => s.id === selectedId);
	}

	async function refreshDriveTime() {
		const origin = customOrigin ?? position;
		const stop = selectedStop;
		if (!origin || !stop) return;
		const result = await driveTimeService.getDriveTime({
			originLat: origin.lat,
			originLng: origin.lng,
			destLat: stop.latitude,
			destLng: stop.longitude,
			destinationStopId: stop.id,
			destinationName: stop.name
		});
		driveTimeSeconds = result.durationSeconds;
		distanceMeters = result.distanceMeters;
		route = result.route.map((p) => ({ lat: p.lat, lng: p.lng }));
	}

	async function refreshDepartures() {
		const stop = selectedStop;
		if (!stop) return;
		const result = await ferryService.departures(stop.id);
		departures = result;
		const destinations = [...new Set(result.map((d) => d.destination).filter((d) => d !== null))];
		if (destinations.length <= 1) {
			selectedDestination = null;
		} else if (selectedDestination === null || !destinations.includes(selectedDestination)) {
			const preferred = destinationPrefs[stop.id];
			selectedDestination = preferred && destinations.includes(preferred) ? preferred : result[0]?.destination ?? null;
		}
	}

	function selectDestination(destination: string) {
		const stop = selectedStop;
		if (!stop) return;
		selectedDestination = destination;
		destinationPrefs = { ...destinationPrefs, [stop.id]: destination };
		destinationPreferenceService.save(destinationPrefs);
	}

	function openNavigation() {
		const stop = selectedStop;
		if (!stop) return;
		// Prefer the last point of the computed route — it reflects the
		// Places-resolved arrival coordinate from the gateway, which is often
		// more accurate than Entur's raw quay coordinate.
		const dest = route.length > 0 ? route[route.length - 1] : { lat: stop.latitude, lng: stop.longitude };
		const url =
			'https://www.google.com/maps/dir/?api=1' +
			`&destination=${dest.lat},${dest.lng}` +
			'&travelmode=driving&dir_action=navigate';
		window.open(url, '_blank');
	}

	function selectStop(index: number) {
		if (index === selectedIndex) return;
		selectedIndex = index;
		driveTimeSeconds = null;
		distanceMeters = null;
		route = [];
		departures = [];
		selectedDestination = null;
		refreshDriveTime();
		refreshDepartures();
	}

	// Every programmatic camera move goes through this so `onCameraIdle` can
	// tell "we moved the camera" apart from "the user dragged the map" — only
	// the latter should update the custom origin.
	function animateCamera(pos: LatLng, zoom?: number) {
		suppressNextIdle = true;
		mapComponent?.panTo(pos, zoom);
	}

	// Uber-style pin picker: a crosshair sits fixed at the screen center and
	// the map moves underneath it; there is deliberately no click-to-drop-pin
	// handler (that approach was tried in the Flutter app and abandoned —
	// taps on UI stacked above the map could reach the map's own click
	// handler in parallel with the UI, misplacing the pin). Two-step: nothing
	// is committed until "Plasser nål" is pressed, so the user can freely
	// zoom/pan to find the exact spot before it affects anything.
	function enterCustomOriginMode() {
		if (!position) return;
		customOriginMode = true;
		originPlaced = false;
		pendingOrigin = position;
		animateCamera(position, 9);
	}

	function placeCustomOrigin() {
		if (!pendingOrigin) return;
		customOrigin = pendingOrigin;
		originPlaced = true;
		loadStopsFor(customOrigin.lat, customOrigin.lng);
	}

	function exitCustomOriginMode() {
		customOriginMode = false;
		originPlaced = false;
		customOrigin = null;
		pendingOrigin = null;
		if (position) {
			animateCamera(position, 13);
			loadStopsFor(position.lat, position.lng);
		}
	}

	function onCameraIdle() {
		if (suppressNextIdle) {
			suppressNextIdle = false;
			return;
		}
		// Once placed, the pin is a normal map marker at a fixed coordinate —
		// further panning/zooming is just regular map browsing and must not
		// move it again.
		if (!customOriginMode || originPlaced) return;
		const center = mapComponent?.getCenter();
		if (center) pendingOrigin = center;
	}

	function handlePosition(pos: GeolocationPosition) {
		position = { lat: pos.coords.latitude, lng: pos.coords.longitude };
		locationError = null;
		if (stops.length === 0 && !loadingStops) loadStopsFor(position.lat, position.lng);
	}

	onMount(() => {
		if (!navigator.geolocation) {
			locationError = 'Denne nettleseren støtter ikke posisjonering.';
			return;
		}

		let watchId: number;
		let fallenBack = false;
		let fallbackTimer: ReturnType<typeof setTimeout>;

		// High accuracy (GPS) first. Desktop browsers commonly fail this
		// (e.g. macOS CoreLocation's Wi-Fi based lookup can simply fail with
		// kCLErrorLocationUnknown) even with permission correctly granted, so
		// fall back to a coarser, more reliable lookup rather than giving up.
		function fallbackToApproximate() {
			if (fallenBack) return;
			fallenBack = true;
			navigator.geolocation.clearWatch(watchId);
			usingApproximateLocation = true;
			watchId = navigator.geolocation.watchPosition(handlePosition, onFallbackError, {
				enableHighAccuracy: false
			});
			fallbackTimer = setTimeout(() => {
				if (!position) {
					locationError = 'Posisjon utilgjengelig — GPS eller nettverksposisjon kreves.';
				}
			}, 8000);
		}

		function onInitialError(err: GeolocationPositionError) {
			console.error('[geolocation]', err.code, err.message);
			fallbackToApproximate();
		}

		function onFallbackError(err: GeolocationPositionError) {
			console.error('[geolocation:fallback]', err.code, err.message);
			locationError = 'Posisjon utilgjengelig — GPS eller nettverksposisjon kreves.';
		}

		watchId = navigator.geolocation.watchPosition(handlePosition, onInitialError, {
			enableHighAccuracy: true
		});
		const initialTimeout = setTimeout(() => {
			if (!position) fallbackToApproximate();
		}, 10_000);

		const departureTimer = setInterval(refreshDepartures, 60_000);
		return () => {
			navigator.geolocation.clearWatch(watchId);
			clearInterval(departureTimer);
			clearTimeout(initialTimeout);
			clearTimeout(fallbackTimer);
		};
	});
</script>

<div class="app">
	{#if position}
		<GoogleMap
			bind:this={mapComponent}
			center={position}
			zoom={10}
			{route}
			oncameraidle={onCameraIdle}
			markers={[
				{ id: '_me', position, alpha: 1, iconUrl: MY_LOCATION_ICON },
				...(originPlaced && customOrigin
					? [{ id: '_custom_origin', position: customOrigin, alpha: 1, iconUrl: CUSTOM_ORIGIN_ICON }]
					: []),
				...stops.map((s, i) => ({
					id: s.id,
					position: { lat: s.latitude, lng: s.longitude },
					alpha: i === selectedIndex ? 1 : 0.5,
					onClick: () => selectStop(i)
				}))
			]}
		/>
	{/if}

	{#if customOriginMode && !originPlaced}
		<div class="crosshair">
			<MapPin size={36} color="#f97316" fill="#f97316" fill-opacity={0.15} />
		</div>
	{/if}

	<div class="top-stack">
		{#if customOriginMode}
			<CustomOriginBanner placed={originPlaced} onexit={exitCustomOriginMode} />
		{/if}

		<div
			class="stats-bar"
			role="button"
			tabindex="0"
			onclick={() => {
				if (selectedStop) sheetOpen = true;
			}}
			onkeydown={(e) => {
				if ((e.key === 'Enter' || e.key === ' ') && selectedStop) sheetOpen = true;
			}}
		>
			{#if selectedStop}
				<ChevronDown class="chevron-corner" size={18} aria-hidden="true" />
			{/if}
		{#if !position || loadingStops}
			<p class="loading">{!position ? 'Henter posisjon…' : 'Søker etter ferger…'}</p>
		{:else if selectedStop}
			<div class="stop-name-row">
				<button
					class="favourite-toggle"
					onclick={(e) => {
						e.stopPropagation();
						toggleFavourite(selectedStop!.id);
					}}
					aria-label="Favoritt"
				>
					<Star
						size={18}
						color={favourites[selectedStop.id] ? '#fbbf24' : 'rgba(255,255,255,0.38)'}
						fill={favourites[selectedStop.id] ? '#fbbf24' : 'none'}
					/>
				</button>
				<span class="stop-name">{selectedStop.name}</span>
				<span class="drive-time">
					<Car class="car-icon" size={14} aria-hidden="true" />
					{formatDriveTime(driveTimeSeconds)}
				</span>
			</div>
			<div class="margins">
				<div class="margin">
					<div class="value">{formatMargin(marginFor(prevDep))}</div>
					<div class="label">{prevDep ? formatClock(prevDep.time) : 'Forrige ferge'}</div>
				</div>
				<div class="margin">
					<div class="value next">{formatMargin(marginFor(nextDep))}</div>
					<div class="label">{nextDep ? `Rekker ${formatClock(nextDep.time)}` : 'Neste ferge'}</div>
				</div>
			</div>
		{:else}
			<p class="loading">Fant ingen fergekaier i nærheten.</p>
		{/if}
		</div>
	</div>

	{#if locationError}
		<div class="location-banner error">
			<span>{locationError}</span>
		</div>
	{:else if usingApproximateLocation && !locationWarningDismissed}
		<div class="location-banner warning">
			<span>Omtrentlig posisjon (WiFi/nettverk). Aktiver GPS for best nøyaktighet.</span>
			<button onclick={() => (locationWarningDismissed = true)} aria-label="Lukk">✕</button>
		</div>
	{/if}

	{#if position}
		<div class="bottom-stack">
			{#if customOriginMode && !originPlaced}
				<button class="place-pin" onclick={placeCustomOrigin}>Plasser nål</button>
			{/if}
			{#if distinctDestinations.length > 1}
				<DestinationSwitcher
					destinations={distinctDestinations}
					selected={selectedDestination}
					onselect={selectDestination}
				/>
			{/if}
			<div class="bottom-bar">
				<PortSwitcher {stops} {selectedIndex} {favourites} onselect={selectStop} />
				<OverflowMenu
					oninfo={() => (infoOpen = true)}
					oncustomorigin={enterCustomOriginMode}
					onfavourites={() => (favouritesOpen = true)}
					onnavigate={openNavigation}
				/>
			</div>
		</div>
	{/if}

	{#if sheetOpen && selectedStop}
		<DepartureSheet
			stopName={selectedStop.name}
			departures={visibleDepartures}
			{driveTimeSeconds}
			onclose={() => (sheetOpen = false)}
		/>
	{/if}

	{#if infoOpen}
		<InfoDialog onclose={() => (infoOpen = false)} />
	{/if}

	{#if favouritesOpen}
		<FavouritesSheet
			{favourites}
			onremove={removeFavourite}
			onclose={() => (favouritesOpen = false)}
		/>
	{/if}
</div>

<style>
	:global(html, body) {
		margin: 0;
		font-family: system-ui, sans-serif;
		overscroll-behavior-y: contain;
	}

	.app {
		position: fixed;
		inset: 0;
	}

	.bottom-stack {
		position: absolute;
		bottom: 0;
		left: 0;
		right: 0;
		display: flex;
		flex-direction: column;
		align-items: stretch;
		gap: 10px;
		margin: 0 12px 12px;
	}

	.place-pin {
		background: #1d4ed8;
		border: none;
		border-radius: 14px;
		color: white;
		font-family: inherit;
		font-size: 15px;
		font-weight: 700;
		padding: 14px;
		cursor: pointer;
		box-shadow: 0 4px 16px rgba(29, 78, 216, 0.5);
	}

	.bottom-bar {
		display: flex;
		align-items: center;
		gap: 8px;
		background: rgba(17, 24, 39, 0.9);
		border-radius: 16px;
		padding: 10px 12px;
	}

	.crosshair {
		position: absolute;
		top: 50%;
		left: 50%;
		transform: translate(-50%, calc(-50% - 18px));
		pointer-events: none;
		filter: drop-shadow(0 2px 4px rgba(0, 0, 0, 0.4));
	}

	.top-stack {
		position: absolute;
		top: 12px;
		left: 12px;
		right: 12px;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.stats-bar {
		position: relative;
		background: rgba(17, 24, 39, 0.9);
		border: none;
		border-radius: 16px;
		padding: 14px 16px;
		color: white;
		font-family: inherit;
		text-align: left;
		cursor: pointer;
	}

	:global(.chevron-corner) {
		position: absolute;
		top: 10px;
		right: 12px;
		color: rgba(255, 255, 255, 0.38);
	}

	.loading {
		margin: 0;
		color: rgba(255, 255, 255, 0.6);
		font-size: 14px;
	}

	.location-banner {
		position: absolute;
		top: 12px;
		left: 12px;
		right: 12px;
		display: flex;
		align-items: center;
		gap: 10px;
		border-radius: 14px;
		padding: 11px 14px;
		color: white;
		font-size: 13px;
		font-weight: 500;
		z-index: 5;
	}

	.location-banner span {
		flex: 1;
	}

	.location-banner button {
		background: none;
		border: none;
		color: white;
		font-size: 16px;
		cursor: pointer;
	}

	.location-banner.error {
		background: rgba(220, 38, 38, 0.94);
	}

	.location-banner.warning {
		background: rgba(217, 119, 6, 0.94);
	}

	.stop-name-row {
		display: flex;
		align-items: center;
		gap: 8px;
		padding-right: 20px;
	}

	.favourite-toggle {
		background: none;
		border: none;
		padding: 0;
		display: flex;
		cursor: pointer;
		flex-shrink: 0;
	}

	.stop-name {
		flex: 1;
		font-weight: 600;
		font-size: 15px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.drive-time {
		display: inline-flex;
		align-items: center;
		gap: 3px;
		color: rgba(255, 255, 255, 0.6);
		font-size: 12px;
	}


	.margins {
		display: flex;
		margin-top: 10px;
	}

	.margin {
		flex: 1;
		text-align: center;
	}

	.value {
		font-size: 28px;
		font-weight: 700;
		color: rgba(255, 255, 255, 0.4);
	}

	.value.next {
		color: #4ade80;
	}

	.label {
		font-size: 11px;
		color: rgba(255, 255, 255, 0.4);
		margin-top: 2px;
	}
</style>
