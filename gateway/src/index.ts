export interface Env {
	GOOGLE_MAPS_API_KEY: string;
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
	const { origin, destination } = await request.json<{ origin: string; destination: string }>();
	if (!origin || !destination) {
		return corsResponse(JSON.stringify({ error: 'origin and destination are required' }), 400);
	}

	const [originLat, originLng] = origin.split(',').map(Number);
	const [destLat, destLng] = destination.split(',').map(Number);

	const routesRes = await fetch(
		'https://routes.googleapis.com/directions/v2:computeRoutes',
		{
			method: 'POST',
			headers: {
				'Content-Type': 'application/json',
				'X-Goog-Api-Key': env.GOOGLE_MAPS_API_KEY,
				'X-Goog-FieldMask': 'routes.duration,routes.polyline.encodedPolyline',
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
		routes?: { duration: string; polyline?: { encodedPolyline: string } }[];
	};
	const route = data.routes?.[0];
	if (!route?.duration) {
		return corsResponse(JSON.stringify({ error: 'No route found', raw: data }), 502);
	}

	const seconds = parseInt(route.duration.replace('s', ''), 10);
	const points = route.polyline?.encodedPolyline
		? decodePolyline(route.polyline.encodedPolyline)
		: null;

	return corsResponse(JSON.stringify({ seconds, points }));
}
