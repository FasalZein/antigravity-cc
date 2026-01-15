<script lang="ts">
	import '../app.css';

	let { children } = $props();
</script>

<svelte:head>
	<title>AI-Pill War Room</title>
	<meta name="description" content="Quota Command Center" />
</svelte:head>

{@render children()}
