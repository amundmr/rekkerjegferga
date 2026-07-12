export interface Env {
	GOOGLE_MAPS_API_KEY: string;
	PLACE_CACHE: KVNamespace;
}

const PLACE_MATCH_MAX_METERS = 200;

function haversineMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
	const R = 6371000;
	const toRad = (d: number) => (d * Math.PI) / 180;
	const dLat = toRad(lat2 - lat1);
	const dLng = toRad(lng2 - lng1);
	const a =
		Math.sin(dLat / 2) ** 2 +
		Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
	return 2 * R * Math.asin(Math.sqrt(a));
}

type ResolvedPlace = { latitude: number; longitude: number; source: 'places' | 'entur' };

async function resolveStopCoordinate(
	env: Env,
	stopId: string,
	stopName: string,
	enturLat: number,
	enturLng: number
): Promise<ResolvedPlace> {
	const cacheKey = `place:${stopId}`;
	const cached = await env.PLACE_CACHE.get(cacheKey, 'json') as ResolvedPlace | null;
	if (cached) return cached;

	const resolved = await lookupPlaceCoordinate(env, stopName, enturLat, enturLng);
	await env.PLACE_CACHE.put(cacheKey, JSON.stringify(resolved));
	return resolved;
}

async function lookupPlaceCoordinate(
	env: Env,
	stopName: string,
	enturLat: number,
	enturLng: number
): Promise<ResolvedPlace> {
	const fallback: ResolvedPlace = { latitude: enturLat, longitude: enturLng, source: 'entur' };
	try {
		const res = await fetch('https://places.googleapis.com/v1/places:searchText', {
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'X-Goog-Api-Key': env.GOOGLE_MAPS_API_KEY,
				'X-Goog-FieldMask': 'places.location',
			},
			body: JSON.stringify({
				textQuery: stopName,
				locationBias: {
					circle: { center: { latitude: enturLat, longitude: enturLng }, radius: 2000 },
				},
			}),
		});
		const data = await res.json() as { places?: { location?: { latitude: number; longitude: number } }[] };
		const place = data.places?.[0]?.location;
		if (!place) return fallback;

		const distance = haversineMeters(enturLat, enturLng, place.latitude, place.longitude);
		if (distance > PLACE_MATCH_MAX_METERS) return fallback;

		return { latitude: place.latitude, longitude: place.longitude, source: 'places' };
	} catch {
		return fallback;
	}
}

const CORS_HEADERS = {
	'Access-Control-Allow-Origin': '*',
	'Access-Control-Allow-Methods': 'POST, OPTIONS',
	'Access-Control-Allow-Headers': 'Content-Type',
};

function corsResponse(body: string, status = 200): Response {
	return new Response(body, {
		status,
		headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
	});
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		if (request.method === 'OPTIONS') {
			return new Response(null, { status: 204, headers: CORS_HEADERS });
		}
		const url = new URL(request.url);
		if (url.pathname === '/drive-time' && request.method === 'POST') {
			return handleDriveTime(request, env);
		}
		return corsResponse(JSON.stringify({ error: 'Not found' }), 404);
	},
} satisfies ExportedHandler<Env>;

function decodePolyline(encoded: string): [number, number][] {
	const points: [number, number][] = [];
	let index = 0, lat = 0, lng = 0;
	while (index < encoded.length) {
		let shift = 0, value = 0, b: number;
		do { b = encoded.charCodeAt(index++) - 63; value |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
		lat += (value & 1) ? ~(value >> 1) : (value >> 1);
		shift = 0; value = 0;
		do { b = encoded.charCodeAt(index++) - 63; value |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
		lng += (value & 1) ? ~(value >> 1) : (value >> 1);
		points.push([lat / 1e5, lng / 1e5]);
	}
	return points;
}

async function handleDriveTime(request: Request, env: Env): Promise<Response> {
	const { origin, destination, destinationStopId, destinationName } = await request.json<{
		origin: string;
		destination: string;
		destinationStopId?: string;
		destinationName?: string;
	}>();
	if (!origin || !destination) {
		return corsResponse(JSON.stringify({ error: 'origin and destination are required' }), 400);
	}

	const [originLat, originLng] = origin.split(',').map(Number);
	const [enturDestLat, enturDestLng] = destination.split(',').map(Number);

	const { latitude: destLat, longitude: destLng } = destinationStopId && destinationName
		? await resolveStopCoordinate(env, destinationStopId, destinationName, enturDestLat, enturDestLng)
		: { latitude: enturDestLat, longitude: enturDestLng };

	const routesRes = await fetch(
		'https://routes.googleapis.com/directions/v2:computeRoutes',
		{
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'X-Goog-Api-Key': env.GOOGLE_MAPS_API_KEY,
				'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
			},
			body: JSON.stringify({
				origin: { location: { latLng: { latitude: originLat, longitude: originLng } } },
				destination: { location: { latLng: { latitude: destLat, longitude: destLng } } },
				travelMode: 'DRIVE',
				routingPreference: 'TRAFFIC_AWARE',
			}),
		}
	);

	const data = await routesRes.json() as {
		routes?: { duration: string; distanceMeters?: number; polyline?: { encodedPolyline: string } }[];
	};
	const route = data.routes?.[0];
	if (!route?.duration) {
		return corsResponse(JSON.stringify({ error: 'No route found', raw: data }), 502);
	}

	const seconds = parseInt(route.duration.replace('s', ''), 10);
	const points = route.polyline?.encodedPolyline
		? decodePolyline(route.polyline.encodedPolyline)
		: null;

	return corsResponse(JSON.stringify({ seconds, distanceMeters: route.distanceMeters ?? null, points }));
}
