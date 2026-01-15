<script lang="ts">
	interface Props {
		label: string;
		percent: number;
		resetIn?: string;
	}

	let { label, percent, resetIn = '' }: Props = $props();
	
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
</script>

<div class="space-y-2">
	<div class="flex items-center justify-between">
		<div class="flex items-center gap-2">
			<span class="text-sm text-text-secondary font-medium">{label}</span>
			{#if resetIn}
				<span class="text-xs text-accent-primary font-mono px-1.5 py-0.5 bg-accent-primary/10 rounded">↻ {resetIn}</span>
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
