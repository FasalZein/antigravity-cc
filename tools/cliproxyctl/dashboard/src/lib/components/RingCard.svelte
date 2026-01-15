<script lang="ts">
	import { getTimeRemaining, timeState } from '$lib/utils/time.svelte';

	interface Props {
		label: string;
		percent: number;
		resetIn?: string;
		resetTime?: string;
	}

	let { label, percent, resetIn = '', resetTime = '' }: Props = $props();
	
	const circumference = 150.8; // 2 * PI * 24
	const offset = $derived(circumference * (1 - percent / 100));
	
	const color = $derived(
		percent >= 50 ? '#10b981' :
		percent >= 20 ? '#f59e0b' :
		'#ef4444'
	);
	
	// Live countdown - recalculates every tick
	const liveTime = $derived.by(() => {
		// Use timeState.now to subscribe to updates and pass current time
		if (resetTime) {
			return getTimeRemaining(resetTime, timeState.now);
		}
		return resetIn || '';
	});
	
	// Show "Idle" if quota is 100% and no reset time needed
	const isFull = $derived(percent >= 100 && !liveTime);
</script>

<div class="glass-card rounded-xl p-5">
	<div class="flex items-center justify-between">
		<div>
			<span class="text-xs text-text-muted uppercase tracking-wider font-medium">{label}</span>
			{#if isFull}
				<p class="text-2xl font-medium mt-2 text-text-muted">Idle</p>
			{:else}
				<p class="text-2xl font-medium mt-2 text-text-primary">{liveTime || '—'}</p>
			{/if}
		</div>
		<div class="relative w-14 h-14">
			<svg class="w-14 h-14 -rotate-90" viewBox="0 0 56 56">
				<circle cx="28" cy="28" r="24" fill="none" stroke="#27272a" stroke-width="4"/>
				<circle 
					cx="28" cy="28" r="24" 
					fill="none" 
					stroke={color} 
					stroke-width="4"
					stroke-dasharray={circumference} 
					stroke-dashoffset={offset} 
					stroke-linecap="round" 
					class="ring-progress"
				/>
			</svg>
			<span class="absolute inset-0 flex items-center justify-center text-xs font-mono font-normal text-text-secondary">
				{Math.round(percent)}%
			</span>
		</div>
	</div>
</div>
