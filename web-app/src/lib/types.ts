export interface FerryStop {
	id: string;
	name: string;
	latitude: number;
	longitude: number;
	distanceMeters: number;
}

export interface Departure {
	time: Date;
	destination: string | null;
}

export function isPast(departure: Departure): boolean {
	return departure.time.getTime() < Date.now();
}

export function formatDistance(meters: number): string {
	if (meters < 1000) return `${Math.round(meters)} m`;
	return `${(meters / 1000).toFixed(1)} km`;
}

export interface LatLng {
	lat: number;
	lng: number;
}

export interface DriveTimeResult {
	durationSeconds: number | null;
	distanceMeters: number | null;
	route: LatLng[];
}

export function haversineMeters(a: LatLng, b: LatLng): number {
	const R = 6371000;
	const toRad = (d: number) => (d * Math.PI) / 180;
	const dLat = toRad(b.lat - a.lat);
	const dLng = toRad(b.lng - a.lng);
	const sinLat = Math.sin(dLat / 2);
	const sinLng = Math.sin(dLng / 2);
	const h = sinLat * sinLat + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinLng * sinLng;
	return 2 * R * Math.asin(Math.sqrt(h));
}
