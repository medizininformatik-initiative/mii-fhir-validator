<style>

/* 1. Hide the "Servers" header by ID */
#servers, 
h2#servers {
    display: none !important;
}

/* 2. Hide the server selection box that immediately follows the header */
h2#servers + div,
.OAServers,
.v-openapi-servers {
    display: none !important;
}

/* 3. Hide the "Try It Out" buttons and their containers */
.OAPathContentEnd button {
    display: none !important;
}

/* 4. Hide the samples header */
.OAPathContentEnd h2[id$="-samples"] {
    display: none !important;
}

/* 5. Hide the code snippet blocks (curl, etc.) */
.OAPathContentEnd .vp-code-group {
    display: none !important;
}

/* 6. Hide the playground section */
.OAPathContentEnd .flex.flex-col.gap-2 {
    display: none !important;
}

/* 7. Make the responses column full width */
.OAPath .sm\:grid-cols-2 {
    grid-template-columns: 1fr !important;
}
</style>

<ClientOnly>
  <OASpec spec-url="openapi.yaml" />
</ClientOnly>