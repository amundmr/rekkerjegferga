const KEY = 'rekker_favourites';

export function load(): Record<string, string> {
	const raw = localStorage.getItem(KEY);
	if (!raw) return {};
	try {
		return JSON.parse(raw);
	} catch {
		return {};
	}
}

export function save(favourites: Record<string, string>) {
	localStorage.setItem(KEY, JSON.stringify(favourites));
}
