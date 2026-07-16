<script lang="ts">
	import { fade, fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import type { Departure } from '$lib/types';

	let {
		stopName,
		departures,
		driveTimeSeconds,
		onclose
	}: {
		stopName: string;
		departures: Departure[];
		driveTimeSeconds: number | null;
		onclose: () => void;
	} = $props();

	function isPast(d: Departure): boolean {
		return d.time.getTime() < Date.now();
	}

	function timeStr(d: Departure): string {
		return d.time.toLocaleTimeString('no-NO', { hour: '2-digit', minute: '2-digit' });
	}

	function marginSeconds(d: Departure): number | null {
		if (driveTimeSeconds === null) return null;
		return Math.round((d.time.getTime() - Date.now()) / 1000) - driveTimeSeconds;
	}

	function marginLabel(d: Departure): string {
		const margin = marginSeconds(d);
		if (margin === null) return '';
		if (Math.abs(margin) < 60) return 'Nå!';
		const h = Math.floor(Math.abs(margin) / 3600);
		const m = Math.round((Math.abs(margin) % 3600) / 60);
		const formatted = h > 0 ? `${h}t ${m}m` : `${m}m`;
		return margin < 0 ? `−${formatted}` : `+${formatted}`;
	}

	function marginColor(d: Departure): string {
		if (driveTimeSeconds === null) return 'transparent';
		if (isPast(d)) return 'rgba(255,255,255,0.24)';
		const margin = marginSeconds(d)!;
		if (margin < 120) return '#ef4444';
		if (margin < 300) return '#f59e0b';
		return '#4ade80';
	}

	let nextIndex = $derived(departures.findIndex((d) => !isPast(d)));
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
		<div class="header">
			<h2>{stopName}</h2>
			<button class="close" onclick={onclose} aria-label="Lukk">✕</button>
		</div>
		<div class="list">
			{#each departures as d, i (d.time.getTime() + (d.destination ?? ''))}
				<div class="row" class:next={i === nextIndex} class:past={isPast(d)}>
					<span class="time">{timeStr(d)}</span>
					<span class="arrow">→</span>
					<span class="destination">{d.destination ?? '—'}</span>
					{#if driveTimeSeconds !== null}
						<span class="margin" style:color={marginColor(d)}>{marginLabel(d)}</span>
					{/if}
				</div>
			{:else}
				<p class="empty">Ingen avganger funnet.</p>
			{/each}
		</div>
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
		touch-action: pan-y;
	}

	.header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin: 0 12px 12px 20px;
	}

	h2 {
		margin: 0;
		font-size: 16px;
		font-weight: 600;
	}

	.close {
		background: none;
		border: none;
		color: rgba(255, 255, 255, 0.5);
		font-size: 18px;
		line-height: 1;
		padding: 8px;
		cursor: pointer;
	}

	.list {
		overflow-y: auto;
		overscroll-behavior: contain;
		padding: 0 12px;
	}

	.row {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 10px 14px;
		margin: 2px 0;
		border-radius: 8px;
	}

	.row.next {
		background: rgba(29, 78, 216, 0.25);
	}

	.time {
		font-variant-numeric: tabular-nums;
		font-size: 17px;
	}

	.row.next .time {
		font-weight: 700;
	}

	.row.past .time,
	.row.past .destination {
		color: rgba(255, 255, 255, 0.3);
	}

	.arrow {
		color: rgba(255, 255, 255, 0.38);
		font-size: 14px;
	}

	.destination {
		flex: 1;
		font-size: 15px;
		color: rgba(255, 255, 255, 0.7);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.margin {
		font-size: 13px;
		font-weight: 600;
	}

	.empty {
		text-align: center;
		color: rgba(255, 255, 255, 0.38);
		padding: 20px;
	}
</style>
