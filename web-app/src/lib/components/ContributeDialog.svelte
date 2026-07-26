<script lang="ts">
	import { fade, scale } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import { Code2, Heart } from 'lucide-svelte';

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
		<h2>Bidra</h2>
		<p>
			Rekker jeg ferga? er et åpen kildekode-prosjekt som drives på fritiden. Det er to måter å
			bidra på:
		</p>

		<div class="option">
			<Code2 size={18} color="#60a5fa" />
			<div>
				<h3>Kode og forslag</h3>
				<p>
					Fant du en feil, eller har du en idé til en ny funksjon? Meld gjerne inn en issue eller
					en pull request på GitHub.
				</p>
				<a href="https://github.com/amundmr/rekkerjegferga" target="_blank" rel="noreferrer">
					github.com/amundmr/rekkerjegferga
				</a>
			</div>
		</div>

		<div class="option">
			<Heart size={18} color="#f97316" />
			<div>
				<h3>Driftskostnader</h3>
				<p>
					Appen koster litt å drifte (kart og ruteberegning). Om du vil bidra til det, kan du
					gjøre det her:
				</p>
				<a href="https://buymeacoffee.com/amundmr" target="_blank" rel="noreferrer">
					buymeacoffee.com/amundmr
				</a>
			</div>
		</div>

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

	h3 {
		margin: 0 0 4px;
		font-size: 14px;
		font-weight: 600;
	}

	p {
		margin: 0 0 12px;
		font-size: 13px;
		line-height: 1.5;
		color: rgba(255, 255, 255, 0.7);
	}

	.option {
		display: flex;
		gap: 12px;
		margin-bottom: 16px;
	}

	.option p {
		margin-bottom: 6px;
	}

	.option a {
		font-size: 13px;
		color: #60a5fa;
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
