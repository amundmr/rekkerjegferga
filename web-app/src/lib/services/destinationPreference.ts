const KEY = 'rekker_destination_prefs';

export function load(): Record<string, string> {
	const raw = localStorage.getItem(KEY);
	if (!raw) return {};
	try {
		return JSON.parse(raw);
	} catch {
		return {};
	}
}

export function save(preferences: Record<string, string>) {
	localStorage.setItem(KEY, JSON.stringify(preferences));
}
