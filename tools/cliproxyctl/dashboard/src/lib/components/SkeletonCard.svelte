<script lang="ts">
	interface Props {
		type?: 'summary' | 'ring' | 'account';
	}
	
	let { type = 'account' }: Props = $props();
</script>

{#if type === 'summary'}
	<div class="glass-card rounded-xl p-5">
		<div class="skeleton h-3 w-16 mb-3"></div>
		<div class="skeleton h-8 w-12"></div>
	</div>
{:else if type === 'ring'}
	<div class="glass-card rounded-xl p-5">
		<div class="flex items-center justify-between">
			<div>
				<div class="skeleton h-3 w-20 mb-3"></div>
				<div class="skeleton h-7 w-16"></div>
			</div>
			<div class="skeleton w-14 h-14 rounded-full"></div>
		</div>
	</div>
{:else}
	<div class="glass-card rounded-xl overflow-hidden">
		<div class="px-5 py-4 border-b border-white/5">
			<div class="skeleton h-4 w-48 mb-2"></div>
			<div class="skeleton h-3 w-32"></div>
		</div>
		<div class="p-5 space-y-4">
			<div class="space-y-2">
				<div class="flex justify-between">
					<div class="skeleton h-3 w-16"></div>
					<div class="skeleton h-3 w-10"></div>
				</div>
				<div class="skeleton h-2 w-full rounded-full"></div>
			</div>
			<div class="space-y-2">
				<div class="flex justify-between">
					<div class="skeleton h-3 w-20"></div>
					<div class="skeleton h-3 w-10"></div>
				</div>
				<div class="skeleton h-2 w-full rounded-full"></div>
			</div>
			<div class="space-y-2">
				<div class="flex justify-between">
					<div class="skeleton h-3 w-24"></div>
					<div class="skeleton h-3 w-10"></div>
				</div>
				<div class="skeleton h-2 w-full rounded-full"></div>
			</div>
		</div>
	</div>
{/if}

<style>
	.skeleton {
		background: linear-gradient(
			90deg,
			rgba(255, 255, 255, 0.03) 0%,
			rgba(255, 255, 255, 0.08) 50%,
			rgba(255, 255, 255, 0.03) 100%
		);
		background-size: 200% 100%;
		animation: shimmer 1.5s infinite;
		border-radius: 0.25rem;
	}
	
	@keyframes shimmer {
		0% { background-position: 200% 0; }
		100% { background-position: -200% 0; }
	}
</style>
