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
