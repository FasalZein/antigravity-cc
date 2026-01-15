<script lang="ts">
	import { getTimeRemaining, timeState } from '$lib/utils/time.svelte';

	interface Props {
		label: string;
		percent: number;
		resetIn?: string;
		resetTime?: string;
	}

	let { label, percent, resetIn = '', resetTime = '' }: Props = $props();
	
	const color = $derived(
		percent >= 50 ? 'bg-status-healthy' :
		percent >= 20 ? 'bg-status-caution' :
		'bg-status-critical'
	);
	
	const textColor = $derived(
		percent >= 50 ? 'text-status-healthy' :
		percent >= 20 ? 'text-status-caution' :
		'text-status-critical'
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
	const isIdle = $derived(percent >= 100 && !liveTime);
</script>

<div class="space-y-2">
	<div class="flex items-center justify-between">
		<div class="flex items-center gap-2">
			<span class="text-sm text-text-secondary font-medium">{label}</span>
			{#if isIdle}
				<span class="text-xs text-text-muted px-1.5 py-0.5 bg-surface-3 rounded">Idle</span>
			{:else if liveTime}
				<span class="text-xs text-accent-primary font-mono px-1.5 py-0.5 bg-accent-primary/10 rounded">↻ {liveTime}</span>
			{/if}
		</div>
		<span class="font-mono font-normal text-sm {textColor}">
			{Math.round(percent)}%
		</span>
	</div>
	<div class="h-2 bg-surface-3 rounded-full overflow-hidden">
		<div 
			class="progress-fill h-full rounded-full {color}"
			style="width: {percent}%"
		></div>
	</div>
</div>
