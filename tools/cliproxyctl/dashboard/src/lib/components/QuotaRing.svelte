<script lang="ts">
	interface Props {
		percent: number;
		size?: number;
		strokeWidth?: number;
		color?: string;
		label?: string;
		resetIn?: string;
	}

	let { percent, size = 120, strokeWidth = 8, color = '#6366f1', label = '', resetIn = '' }: Props = $props();

	const radius = $derived((size - strokeWidth) / 2);
	const circumference = $derived(2 * Math.PI * radius);
	const offset = $derived(circumference - (percent / 100) * circumference);
	const center = $derived(size / 2);
	
	const displayColor = $derived(
		percent > 50 ? '#22c55e' : 
		percent > 20 ? '#f59e0b' : 
		'#ef4444'
	);
</script>

<div class="flex flex-col items-center gap-2">
	<div class="relative" style="width: {size}px; height: {size}px;">
		<svg class="transform -rotate-90" width={size} height={size}>
			<!-- Background circle -->
			<circle
				cx={center}
				cy={center}
				r={radius}
				fill="none"
				stroke="var(--color-bg-tertiary)"
				stroke-width={strokeWidth}
			/>
			<!-- Progress circle -->
			<circle
				cx={center}
				cy={center}
				r={radius}
				fill="none"
				stroke={displayColor}
				stroke-width={strokeWidth}
				stroke-linecap="round"
				stroke-dasharray={circumference}
				stroke-dashoffset={offset}
				class="transition-all duration-500"
			/>
		</svg>
		<div class="absolute inset-0 flex flex-col items-center justify-center">
			<span class="text-2xl font-bold text-text-primary">{Math.round(percent)}%</span>
			{#if resetIn}
				<span class="text-xs text-accent-primary font-mono">↻ {resetIn}</span>
			{/if}
		</div>
	</div>
	{#if label}
		<span class="text-sm text-text-secondary font-medium">{label}</span>
	{/if}
</div>
