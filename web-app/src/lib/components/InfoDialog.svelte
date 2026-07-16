<script lang="ts">
	import { fade, scale } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';

	let { onclose }: { onclose: () => void } = $props();
</script>

<div
	class="backdrop"
	onclick={onclose}
	onkeydown={(e) => e.key === 'Escape' && onclose()}
	role="button"
	tabindex="0"
	transition:fade={{ duration: 150 }}
>
	<div
		class="dialog"
		onclick={(e) => e.stopPropagation()}
		onkeydown={(e) => e.stopPropagation()}
		role="dialog"
		aria-modal="true"
		tabindex="-1"
		transition:scale={{ start: 0.95, duration: 150, easing: cubicOut }}
	>
		<h2>Rekker jeg ferga?</h2>
		<p>
			Rekker jeg ferga? er en åpen kildekode-app som beregner sanntids kjøretid til nærmeste
			fergekai og viser marginen til neste avgang.
		</p>
		<p>
			Avgangstider hentes fra Entur. Kjøretid beregnes via Google Maps Routes API. Hostet på
			Cloudflare Pages.
		</p>
		<p>Laget av Amund Raniseth.</p>
		<p class="version">Versjon 1.1.0</p>
		<a href="https://github.com/amundmr/rekkerjegferga" target="_blank" rel="noreferrer">
			Kildekode: github.com/amundmr/rekkerjegferga
		</a>
		<button class="close" onclick={onclose}>Lukk</button>
	</div>
</div>

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 20;
		padding: 20px;
	}

	.dialog {
		background: #111827;
		border-radius: 16px;
		padding: 20px;
		max-width: 360px;
		color: white;
	}

	h2 {
		margin: 0 0 12px;
		font-size: 18px;
		font-weight: 600;
	}

	p {
		margin: 0 0 12px;
		font-size: 13px;
		line-height: 1.5;
		color: rgba(255, 255, 255, 0.7);
	}

	.version {
		color: rgba(255, 255, 255, 0.4);
	}

	a {
		display: block;
		font-size: 13px;
		color: #60a5fa;
		margin-bottom: 14px;
	}

	.close {
		background: none;
		border: none;
		color: #60a5fa;
		font-size: 14px;
		font-weight: 600;
		padding: 0;
		cursor: pointer;
	}
</style>
