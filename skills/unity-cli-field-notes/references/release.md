# Releases

Tl (IAFahim/tl) publishes to NuGet automatically: pushing a `v*` tag runs `publish-nuget.yml` (release gate, artifact verification, then OIDC trusted-publishing push in dependency order with `--skip-duplicate`); never push packages by hand, and re-run an existing tag with `gh workflow run publish-nuget.yml -f tag=<tag>`.
