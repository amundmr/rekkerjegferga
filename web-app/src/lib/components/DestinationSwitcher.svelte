<script lang="ts">
	import { ArrowRight } from 'lucide-svelte';

	let {
		destinations,
		selected,
		onselect
	}: {
		destinations: string[];
		selected: string | null;
		onselect: (destination: string) => void;
	} = $props();
</script>

<div class="switcher">
	{#each destinations as destination (destination)}
		<button
			class="chip"
			class:selected={destination === selected}
			onclick={() => onselect(destination)}
		>
			<ArrowRight size={13} />
			{destination}
		</button>
	{/each}
</div>

<style>
	.switcher {
		display: flex;
		gap: 8px;
		overflow-x: auto;
		background: rgba(17, 24, 39, 0.9);
		border-radius: 14px;
		padding: 8px 10px;
	}

	.chip {
		flex: 0 0 auto;
		display: flex;
		align-items: center;
		gap: 5px;
		padding: 8px 14px;
		background: #1f2937;
		border: none;
		border-radius: 10px;
		color: rgba(255, 255, 255, 0.6);
		font-family: inherit;
		font-size: 12px;
		font-weight: 600;
		white-space: nowrap;
		cursor: pointer;
	}

	.chip.selected {
		background: #1d4ed8;
		color: white;
	}
</style>
