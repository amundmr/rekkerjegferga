<script lang="ts">
	import { fade, fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { Star, Trash2 } from 'lucide-svelte';

	let {
		favourites,
		onremove,
		onclose
	}: {
		favourites: Record<string, string>;
		onremove: (stopId: string) => void;
		onclose: () => void;
	} = $props();

	let entries = $derived(Object.entries(favourites));
</script>

<div
	class="backdrop"
	onclick={onclose}
	onkeydown={(e) => e.key === 'Escape' && onclose()}
	role="button"
	tabindex="0"
	transition:fade={{ duration: 180 }}
>
	<div
		class="sheet"
		onclick={(e) => e.stopPropagation()}
		onkeydown={(e) => e.stopPropagation()}
		role="dialog"
		aria-modal="true"
		tabindex="-1"
		transition:fly={{ y: 300, duration: 220, easing: cubicOut }}
	>
		<h2>Favoritter</h2>
		{#if entries.length === 0}
			<p class="empty">Ingen favoritter ennå.</p>
		{:else}
			<div class="list">
				{#each entries as [id, name] (id)}
					<div class="row">
						<Star size={16} color="#fbbf24" fill="#fbbf24" />
						<span class="name">{name}</span>
						<button class="remove" onclick={() => onremove(id)} aria-label="Fjern favoritt">
							<Trash2 size={20} />
						</button>
					</div>
				{/each}
			</div>
		{/if}
	</div>
</div>

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		display: flex;
		align-items: flex-end;
		z-index: 10;
		overscroll-behavior: contain;
	}

	.sheet {
		width: 100%;
		max-height: 70vh;
		background: #111827;
		border-radius: 20px 20px 0 0;
		padding: 18px 0 20px;
		display: flex;
		flex-direction: column;
		color: white;
		overscroll-behavior: contain;
	}

	h2 {
		margin: 0 20px 12px;
		font-size: 16px;
		font-weight: 600;
	}

	.empty {
		text-align: center;
		color: rgba(255, 255, 255, 0.38);
		padding: 20px;
	}

	.list {
		overflow-y: auto;
		padding: 0 16px;
	}

	.row {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 6px 4px;
	}

	.name {
		flex: 1;
		font-size: 15px;
	}

	.remove {
		background: none;
		border: none;
		color: rgba(255, 255, 255, 0.38);
		cursor: pointer;
		padding: 4px;
	}
</style>
