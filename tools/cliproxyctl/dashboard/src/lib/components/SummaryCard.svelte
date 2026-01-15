<script lang="ts">
	interface Props {
		label: string;
		value: string | number;
		subLabel?: string;
	}

	let { label, value, subLabel = '' }: Props = $props();
</script>

<div class="glass-card rounded-xl p-5">
	<div class="flex items-center justify-between mb-3">
		<span class="text-xs text-text-muted uppercase tracking-wider font-medium">{label}</span>
		{#if subLabel}
			<span class="text-xs text-text-muted font-mono">{subLabel}</span>
		{/if}
	</div>
	<p class="text-3xl font-bold text-white font-mono">{value}</p>
</div>
