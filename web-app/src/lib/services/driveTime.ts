import type { DriveTimeResult } from '$lib/types';

const BASE_URL = 'https://gateway.amund-56d.workers.dev';

export async function getDriveTime(params: {
	originLat: number;
	originLng: number;
	destLat: number;
	destLng: number;
	destinationStopId?: string;
	destinationName?: string;
}): Promise<DriveTimeResult> {
	const empty: DriveTimeResult = { durationSeconds: null, distanceMeters: null, route: [] };
	try {
		const res = await fetch(`${BASE_URL}/drive-time`, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify({
				origin: `${params.originLat},${params.originLng}`,
				destination: `${params.destLat},${params.destLng}`,
				...(params.destinationStopId ? { destinationStopId: params.destinationStopId } : {}),
				...(params.destinationName ? { destinationName: params.destinationName } : {})
			})
		});
		const data = await res.json();
		const points: [number, number][] | undefined = data.points;
		return {
			durationSeconds: typeof data.seconds === 'number' ? data.seconds : null,
			distanceMeters: typeof data.distanceMeters === 'number' ? data.distanceMeters : null,
			route: points ? points.map(([lat, lng]) => ({ lat, lng })) : []
		};
	} catch (err) {
		console.error('[driveTime] error', err);
		return empty;
	}
}
