<script lang="ts">
	import { onMount } from 'svelte';
	import GoogleMap from '$lib/components/GoogleMap.svelte';
	import * as ferryService from '$lib/services/ferry';
	import * as driveTimeService from '$lib/services/driveTime';
	import type { Departure, FerryStop, LatLng } from '$lib/types';

	let position = $state<LatLng | null>(null);
	let locationError = $state<string | null>(null);

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

	let arrival = $derived(driveTimeSeconds !== null ? now + driveTimeSeconds * 1000 : null);

	let nextDep = $derived.by((): Departure | null => {
		if (arrival === null) return null;
		for (const d of departures) {
			if (d.time.getTime() >= arrival) return d;
		}
		return null;
	});

	let prevDep = $derived.by((): Departure | null => {
		if (arrival === null) return null;
		let last: Departure | null = null;
		for (const d of departures) {
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

	async function loadStopsFor(lat: number, lng: number) {
		loadingStops = true;
		const result = await ferryService.nearbyStops(lat, lng);
		stops = [...result].sort((a, b) => a.distanceMeters - b.distanceMeters);
		selectedIndex = 0;
		loadingStops = false;
		if (stops.length > 0) {
			refreshDriveTime();
			refreshDepartures();
		}
	}

	async function refreshDriveTime() {
		const origin = position;
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
		departures = await ferryService.departures(stop.id);
	}

	function selectStop(index: number) {
		if (index === selectedIndex) return;
		selectedIndex = index;
		driveTimeSeconds = null;
		distanceMeters = null;
		route = [];
		departures = [];
		refreshDriveTime();
		refreshDepartures();
	}

	onMount(() => {
		if (!navigator.geolocation) {
			locationError = 'Denne nettleseren støtter ikke posisjonering.';
			return;
		}
		const watchId = navigator.geolocation.watchPosition(
			(pos) => {
				position = { lat: pos.coords.latitude, lng: pos.coords.longitude };
				if (stops.length === 0 && !loadingStops) loadStopsFor(position.lat, position.lng);
			},
			() => {
				locationError = 'Fikk ikke tilgang til posisjon — GPS eller nettverksposisjon kreves.';
			},
			{ enableHighAccuracy: true }
		);
		const departureTimer = setInterval(refreshDepartures, 60_000);
		return () => {
			navigator.geolocation.clearWatch(watchId);
			clearInterval(departureTimer);
		};
	});
</script>

<div class="app">
	{#if position}
		<GoogleMap
			center={position}
			zoom={10}
			{route}
			markers={[
				{ id: '_me', position, alpha: 1 },
				...stops.map((s, i) => ({
					id: s.id,
					position: { lat: s.latitude, lng: s.longitude },
					alpha: i === selectedIndex ? 1 : 0.5,
					onClick: () => selectStop(i)
				}))
			]}
		/>
	{/if}

	<div class="stats-bar">
		{#if locationError}
			<p class="error">{locationError}</p>
		{:else if !position || loadingStops}
			<p class="loading">{!position ? 'Henter posisjon…' : 'Søker etter ferger…'}</p>
		{:else if selectedStop}
			<div class="stop-name">{selectedStop.name}</div>
			<div class="drive-time">{formatDriveTime(driveTimeSeconds)}</div>
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

<style>
	:global(body) {
		margin: 0;
		font-family: system-ui, sans-serif;
	}

	.app {
		position: fixed;
		inset: 0;
	}

	.stats-bar {
		position: absolute;
		top: 12px;
		left: 12px;
		right: 12px;
		background: rgba(17, 24, 39, 0.9);
		border-radius: 16px;
		padding: 14px 16px;
		color: white;
	}

	.loading,
	.error {
		margin: 0;
		color: rgba(255, 255, 255, 0.6);
		font-size: 14px;
	}

	.stop-name {
		font-weight: 600;
		font-size: 15px;
	}

	.drive-time {
		color: rgba(255, 255, 255, 0.6);
		font-size: 12px;
		margin-top: 2px;
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
