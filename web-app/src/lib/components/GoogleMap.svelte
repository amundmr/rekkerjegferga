<script lang="ts">
	import type { LatLng } from '$lib/types';

	interface MarkerSpec {
		id: string;
		position: LatLng;
		alpha?: number;
		iconUrl?: string;
		onClick?: () => void;
	}

	let {
		center,
		zoom,
		markers = [],
		route = null,
		onready,
		oncameraidle
	}: {
		center: LatLng;
		zoom: number;
		markers?: MarkerSpec[];
		route?: LatLng[] | null;
		onready?: (map: google.maps.Map) => void;
		oncameraidle?: () => void;
	} = $props();

	let mapDiv: HTMLDivElement;
	let map: google.maps.Map | undefined;
	let gMarkers = new Map<string, google.maps.Marker>();
	let polyline: google.maps.Polyline | undefined;

	$effect(() => {
		if (!map && mapDiv) {
			map = new google.maps.Map(mapDiv, {
				center,
				zoom,
				disableDefaultUI: true,
				gestureHandling: 'greedy'
			});
			map.addListener('idle', () => oncameraidle?.());
			onready?.(map);
		}
	});

	// Keep markers in sync with the `markers` prop without recreating the map.
	$effect(() => {
		if (!map) return;
		const seen = new Set<string>();
		for (const spec of markers) {
			seen.add(spec.id);
			let marker = gMarkers.get(spec.id);
			if (!marker) {
				marker = new google.maps.Marker({ map });
				marker.addListener('click', () => spec.onClick?.());
				gMarkers.set(spec.id, marker);
			}
			marker.setPosition(spec.position);
			marker.setOpacity(spec.alpha ?? 1);
			if (spec.iconUrl) marker.setIcon(spec.iconUrl);
		}
		for (const [id, marker] of gMarkers) {
			if (!seen.has(id)) {
				marker.setMap(null);
				gMarkers.delete(id);
			}
		}
	});

	$effect(() => {
		if (!map) return;
		if (!route || route.length === 0) {
			polyline?.setMap(null);
			polyline = undefined;
			return;
		}
		if (!polyline) {
			polyline = new google.maps.Polyline({
				map,
				strokeColor: '#1D4ED8',
				strokeWeight: 5
			});
		}
		polyline.setPath(route);
	});

	export function panTo(position: LatLng, newZoom?: number) {
		if (!map) return;
		map.panTo(position);
		if (newZoom !== undefined) map.setZoom(newZoom);
	}

	export function getMap(): google.maps.Map | undefined {
		return map;
	}

	export function getCenter(): LatLng | undefined {
		const c = map?.getCenter();
		return c ? { lat: c.lat(), lng: c.lng() } : undefined;
	}
</script>

<div bind:this={mapDiv} class="map"></div>

<style>
	.map {
		position: absolute;
		inset: 0;
	}
</style>
