import type { Departure, FerryStop } from '$lib/types';

const ENDPOINT = 'https://api.entur.io/journey-planner/v3/graphql';
const HEADERS = {
	'Content-Type': 'application/json',
	'ET-Client-Name': 'hand-built-rekkerjegferga'
};

const CAR_FERRY_SUBMODES = new Set(['localCarFerry', 'nationalCarFerry', 'internationalCarFerry']);

interface EnturLine {
	transportSubmode?: string;
}

interface EnturQuay {
	lines?: EnturLine[];
}

interface EnturStopPlace {
	id: string;
	name: string;
	latitude: number;
	longitude: number;
	quays?: EnturQuay[];
}

function hasCarFerry(place: EnturStopPlace): boolean {
	for (const quay of place.quays ?? []) {
		for (const line of quay.lines ?? []) {
			if (line.transportSubmode && CAR_FERRY_SUBMODES.has(line.transportSubmode)) return true;
		}
	}
	return false;
}

export async function nearbyStops(lat: number, lng: number): Promise<FerryStop[]> {
	const query = `
		query($lat: Float!, $lng: Float!) {
			nearest(
				latitude: $lat
				longitude: $lng
				maximumDistance: 100000
				filterByPlaceTypes: [stopPlace]
				filterByModes: [water]
			) {
				edges {
					node {
						distance
						place {
							id
							... on StopPlace {
								name
								latitude
								longitude
								quays {
									lines {
										transportSubmode
									}
								}
							}
						}
					}
				}
			}
		}
	`;
	try {
		const res = await fetch(ENDPOINT, {
			method: 'POST',
			headers: HEADERS,
			body: JSON.stringify({ query, variables: { lat, lng } })
		});
		const body = await res.json();
		const edges: { distance: number; place: EnturStopPlace }[] = body.data.nearest.edges.map(
			(e: { node: { distance: number; place: EnturStopPlace } }) => e.node
		);
		return edges
			.filter((e) => hasCarFerry(e.place))
			.map((e) => ({
				id: e.place.id,
				name: e.place.name,
				latitude: e.place.latitude,
				longitude: e.place.longitude,
				distanceMeters: e.distance
			}));
	} catch (err) {
		console.error('[ferry] nearbyStops error', err);
		return [];
	}
}

interface EstimatedCall {
	expectedDepartureTime: string;
	destinationDisplay?: { frontText?: string };
	serviceJourney?: { transportSubmode?: string };
}

export async function departures(stopId: string): Promise<Departure[]> {
	const startTime = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
	const query = `
		query($id: String!, $startTime: DateTime!) {
			stopPlace(id: $id) {
				quays {
					estimatedCalls(startTime: $startTime, timeRange: 21600, numberOfDepartures: 20) {
						expectedDepartureTime
						destinationDisplay { frontText }
						serviceJourney { transportSubmode }
					}
				}
			}
		}
	`;
	try {
		const res = await fetch(ENDPOINT, {
			method: 'POST',
			headers: HEADERS,
			body: JSON.stringify({ query, variables: { id: stopId, startTime } })
		});
		const body = await res.json();
		const quays: { estimatedCalls: EstimatedCall[] }[] = body.data.stopPlace.quays;
		const all: Departure[] = [];
		for (const quay of quays) {
			for (const call of quay.estimatedCalls) {
				const submode = call.serviceJourney?.transportSubmode;
				if (!submode || !CAR_FERRY_SUBMODES.has(submode)) continue;
				all.push({
					time: new Date(call.expectedDepartureTime),
					destination: call.destinationDisplay?.frontText ?? null
				});
			}
		}
		all.sort((a, b) => a.time.getTime() - b.time.getTime());
		const seen = new Set<string>();
		return all.filter((d) => {
			const key = `${d.time.getHours()}:${d.time.getMinutes()}:${d.destination}`;
			if (seen.has(key)) return false;
			seen.add(key);
			return true;
		});
	} catch (err) {
		console.error('[ferry] departures error', err);
		return [];
	}
}
