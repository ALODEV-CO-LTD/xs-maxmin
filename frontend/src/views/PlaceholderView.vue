<!--
  Shared placeholder for pages not yet built out. Other agents building the
  User area / Admin area should DELETE the corresponding entry in
  src/router/index.js's `component: PlaceholderView` and point it at their
  real view component instead - this file itself should not need edits.
-->
<script setup>
import { useRoute } from 'vue-router'

const route = useRoute()
</script>

<template>
  <div class="page">
    <h1 class="page-title">{{ route.meta.title }}</h1>
    <p class="page-subtitle">Trang này chưa được xây dựng.</p>
    <div class="card">
      <p style="margin: 0; color: var(--muted)">
        Route: <code>{{ route.path }}</code>
      </p>
    </div>
  </div>
</template>
