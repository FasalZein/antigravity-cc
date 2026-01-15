<script lang="ts">
	interface Props {
		icon?: string;
		title: string;
		message: string;
		hint?: string;
	}

	let { icon = '', title, message, hint = '' }: Props = $props();
</script>

<div class="text-center py-20">
	<div class="inline-flex items-center justify-center w-20 h-20 bg-surface-2 rounded-2xl mb-6">
		{#if icon}
			<img src={icon} alt="" class="w-10 h-10">
		{:else}
			<svg class="w-10 h-10 text-text-muted" fill="none" stroke="currentColor" viewBox="0 0 24 24">
				<path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M21 21l-5.197-5.197m0 0A7.5 7.5 0 105.196 5.196a7.5 7.5 0 0010.607 10.607z" />
			</svg>
		{/if}
	</div>
	<h2 class="text-xl font-semibold text-white mb-2">{title}</h2>
	<p class="text-text-muted mb-4">{@html message}</p>
	{#if hint}
		<p class="text-sm text-text-muted">{hint}</p>
	{/if}
</div>
