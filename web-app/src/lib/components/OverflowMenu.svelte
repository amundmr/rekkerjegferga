<script lang="ts">
	import { Info, LocateFixed, MoreVertical, Navigation, Star } from 'lucide-svelte';

	let {
		oninfo,
		oncustomorigin,
		onfavourites,
		onnavigate
	}: {
		oninfo: () => void;
		oncustomorigin: () => void;
		onfavourites: () => void;
		onnavigate: () => void;
	} = $props();

	let open = $state(false);

	function toggle() {
		open = !open;
	}

	function pick(action: () => void) {
		open = false;
		action();
	}
</script>

<div class="wrap">
	<button class="icon-button" onclick={toggle} aria-label="Meny">
		<MoreVertical size={22} />
	</button>
	{#if open}
		<div class="backdrop" onclick={() => (open = false)} role="presentation"></div>
		<div class="menu" role="menu">
			<button class="item" role="menuitem" onclick={() => pick(onnavigate)}>
				<Navigation size={18} />
				<span>Naviger dit</span>
			</button>
			<button class="item" role="menuitem" onclick={() => pick(oninfo)}>
				<Info size={18} />
				<span>Info</span>
			</button>
			<button class="item" role="menuitem" onclick={() => pick(onfavourites)}>
				<Star size={18} />
				<span>Favoritter</span>
			</button>
			<button class="item" role="menuitem" onclick={() => pick(oncustomorigin)}>
				<LocateFixed size={18} />
				<span>Egendefinert startpunkt</span>
			</button>
		</div>
	{/if}
</div>

<style>
	.wrap {
		position: relative;
	}

	.icon-button {
		background: none;
		border: none;
		color: rgba(255, 255, 255, 0.54);
		padding: 8px;
		cursor: pointer;
		display: flex;
	}

	.backdrop {
		position: fixed;
		inset: 0;
		z-index: 10;
	}

	.menu {
		position: absolute;
		bottom: calc(100% + 6px);
		right: 0;
		background: #1f2937;
		border-radius: 12px;
		padding: 6px;
		min-width: 220px;
		z-index: 11;
		box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
	}

	.item {
		display: flex;
		align-items: center;
		gap: 10px;
		width: 100%;
		background: none;
		border: none;
		color: white;
		font-family: inherit;
		font-size: 14px;
		padding: 10px 12px;
		border-radius: 8px;
		cursor: pointer;
		text-align: left;
	}

	.item:hover {
		background: rgba(255, 255, 255, 0.06);
	}
</style>
