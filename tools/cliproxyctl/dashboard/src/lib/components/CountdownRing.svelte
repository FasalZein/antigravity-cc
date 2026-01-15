<script lang="ts">
	import { formatCountdown } from '$lib/stores/dashboard.svelte';

	interface Props {
		seconds: number;
		maxSeconds?: number;
	}

	let { seconds, maxSeconds = 300 }: Props = $props();
	
	// Calculate ring offset (113.1 is circumference of r=18 circle)
	const circumference = 113.1;
	const offset = $derived(circumference * (1 - seconds / maxSeconds));
</script>

<div class="relative glow-ring rounded-full p-0.5">
	<div class="relative w-10 h-10 bg-surface-2 rounded-full flex items-center justify-center">
		<svg class="countdown-ring absolute inset-0 w-10 h-10" viewBox="0 0 40 40">
			<circle cx="20" cy="20" r="18" fill="none" stroke="#27272a" stroke-width="2"/>
			<circle 
				cx="20" cy="20" r="18" 
				fill="none" 
				stroke="#6366f1" 
				stroke-width="2"
				stroke-dasharray={circumference} 
				stroke-dashoffset={offset} 
				stroke-linecap="round" 
				class="ring-progress"
			/>
		</svg>
		<span class="text-xs font-mono text-text-secondary relative z-10">{formatCountdown(seconds)}</span>
	</div>
</div>
