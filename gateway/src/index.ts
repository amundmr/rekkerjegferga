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
				'X-Goog-FieldMask': 'routes.duration',
			},
			body: JSON.stringify({
				origin: { location: { latLng: { latitude: originLat, longitude: originLng } } },
				destination: { location: { latLng: { latitude: destLat, longitude: destLng } } },
				travelMode: 'DRIVE',
				routingPreference: 'TRAFFIC_AWARE',
			}),
		}
	);

	const data = await routesRes.json() as { routes?: { duration: string }[] };
	const durationStr = data.routes?.[0]?.duration;

	if (!durationStr) {
		return corsResponse(JSON.stringify({ error: 'No route found', raw: data }), 502);
	}

	// Routes API returns duration as "1234s"
	const seconds = parseInt(durationStr.replace('s', ''), 10);
	return corsResponse(JSON.stringify({ seconds }));
}
