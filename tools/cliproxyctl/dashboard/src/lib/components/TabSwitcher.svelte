<script lang="ts">
	interface Props {
		tabs: { id: string; label: string; count?: number }[];
		activeTab: string;
		onTabChange: (id: string) => void;
	}

	let { tabs, activeTab, onTabChange }: Props = $props();
</script>

<div class="flex gap-1 p-1 bg-bg-tertiary rounded-lg">
	{#each tabs as tab}
		<button
			class="flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-all
				{activeTab === tab.id 
					? 'bg-bg-card text-text-primary shadow-sm' 
					: 'text-text-muted hover:text-text-secondary hover:bg-bg-hover'}"
			onclick={() => onTabChange(tab.id)}
		>
			{tab.label}
			{#if tab.count !== undefined}
				<span class="px-2 py-0.5 text-xs rounded-full bg-bg-primary/50">{tab.count}</span>
			{/if}
		</button>
	{/each}
</div>
