<script lang="ts">
	import { MapPin } from 'lucide-svelte';

	let {
		placed,
		onexit
	}: {
		placed: boolean;
		onexit: () => void;
	} = $props();
</script>

<div class="banner">
	<MapPin size={18} color="#f97316" />
	<span class="message">
		{placed ? 'Egendefinert startpunkt' : 'Dra kartet for å velge startpunkt'}
	</span>
	<button class="exit" onclick={onexit}>Bruk enhetens posisjon</button>
</div>

<style>
	.banner {
		display: flex;
		align-items: center;
		gap: 10px;
		background: rgba(17, 24, 39, 0.9);
		border: 1px solid #f97316;
		border-radius: 14px;
		padding: 11px 14px;
		color: white;
	}

	.message {
		flex: 1;
		font-size: 13px;
		font-weight: 500;
	}

	.exit {
		background: none;
		border: none;
		color: #60a5fa;
		font-size: 12px;
		font-weight: 600;
		text-decoration: underline;
		padding: 4px 0;
		cursor: pointer;
		font-family: inherit;
	}
</style>
