<script lang="ts">
	import { Star } from 'lucide-svelte';
	import { formatDistance, type FerryStop } from '$lib/types';

	let {
		stops,
		selectedIndex,
		favourites,
		onselect
	}: {
		stops: FerryStop[];
		selectedIndex: number;
		favourites: Record<string, string>;
		onselect: (index: number) => void;
	} = $props();
</script>

<div class="switcher">
	{#each stops as stop, i (stop.id)}
		<button class="chip" class:selected={i === selectedIndex} onclick={() => onselect(i)}>
			<span class="name-row">
				{#if favourites[stop.id]}
					<Star size={11} fill="currentColor" />
				{/if}
				<span class="name">{stop.name}</span>
			</span>
			<span class="distance">{formatDistance(stop.distanceMeters)}</span>
		</button>
	{/each}
</div>

<style>
	.switcher {
		display: flex;
		gap: 8px;
		overflow-x: auto;
		flex: 1;
		min-width: 0;
	}

	.chip {
		flex: 0 0 auto;
		width: 140px;
		padding: 10px 8px;
		background: #1f2937;
		border: none;
		border-radius: 10px;
		color: rgba(255, 255, 255, 0.6);
		font-family: inherit;
		text-align: center;
		cursor: pointer;
	}

	.chip.selected {
		background: #1d4ed8;
		color: white;
	}

	.name-row {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 3px;
		color: inherit;
		opacity: 0.7;
	}

	.name {
		display: block;
		font-size: 12px;
		font-weight: 600;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		opacity: 1;
		color: inherit;
	}

	.distance {
		display: block;
		font-size: 11px;
		margin-top: 2px;
		color: inherit;
		opacity: 0.7;
	}
</style>
