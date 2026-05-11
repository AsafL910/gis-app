# Cross-Repo Bundling Reference

This document describes a low-friction pattern for bundling multiple services that live in separate repositories.

The goal is to keep source initialization separate from packaging so you can:

- prepare a machine from one manifest
- pin exact repo refs or artifact versions
- keep using the existing `build_package.ps1`
- move into CI later without forcing a monorepo now

## Recommended Shape

Create a dedicated packaging repo, or keep a packaging folder like this one until you are ready to split it out.

That packaging layer owns:

- an initialization manifest
- initialization scripts
- packaging scripts
- deployment templates
- installer/runtime files

Each service stays in its own repo.

## Two-Step Flow

Use two explicit commands:

1. Initialize sources and tools.
2. Build the deployment package.

In this repo that means:

```powershell
cd gis-app\windows-deployment
.\initialize_sources.ps1 -Manifest .\initialize_sources.example.json
.\build_package.ps1
```

This split keeps the integration surface small:

- `initialize_sources.ps1` gets the project into a ready-to-build state
- `build_package.ps1` keeps owning the actual packaging

## Why Keep The Manifest Separate

Your existing `deployment_manifest.json` is runtime-oriented. It describes how already-packaged services should run.

The initialization manifest solves a different problem: where each input comes from and where it should land in the working tree before packaging.

Keeping them separate helps because:

- you can adopt cross-repo initialization without rewriting runtime metadata
- local setup can evolve independently from service startup metadata
- later CI can use the same initialization manifest even if the package format changes

## Reference Manifest

Use [initialize_sources.example.json](D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/initialize_sources.example.json) as a starting point.

Suggested top-level sections:

- `defaults`: shared behaviors like a default git ref or overwrite policy
- `entries`: one entry per repo, runtime tool, exported environment, or local input

Each entry has:

- `source`: how to obtain the input
- `target_path`: where to place it so the build script can consume it

## Supported Source Types

Use `source.type` to describe where an input comes from.

### `git`

For application repos or source-controlled components.

Fields:

- `url`: git remote URL
- `ref`: branch, tag, or commit SHA

Example:

```json
{
  "source": {
    "type": "git",
    "url": "https://example.com/org/map-provider.git",
    "ref": "release/0.2"
  },
  "target_path": "map-provider"
}
```

### `artifact`

For Artifactory downloads, portable runtimes, exported Pixi environments, or zipped outputs from CI.

Fields:

- `url`: downloadable artifact URL
- `unpack`: whether the downloaded file should be extracted
- `archive_subpath`: optional subfolder inside the extracted archive to copy from

Example:

```json
{
  "source": {
    "type": "artifact",
    "url": "https://artifactory.example.com/generic/envs/map-provider-pixi.zip",
    "unpack": true
  },
  "target_path": "map-provider/.pixi"
}
```

### `local`

For data or inputs that already exist on the developer machine.

Fields:

- `path`: local file or directory path

Example:

```json
{
  "source": {
    "type": "local",
    "path": "C:\\release-inputs\\glb-demo\\data"
  },
  "target_path": "data"
}
```

## Refs To Pin

For git sources, `ref` can be:

- a branch name like `main`
- a tag like `release/0.2`
- a commit SHA

A practical split is:

- local manual setup: branch names are fine
- release builds and CI: prefer tags or commit SHAs

## Initialization Script Behavior

[initialize_sources.ps1](D:/Courses/MAPS/israel/glb-demo/gis-app/windows-deployment/initialize_sources.ps1) is intentionally separate from the build script.

It will:

- clone missing git repos
- fetch and check out the requested git ref
- download artifacts
- optionally unpack archives
- copy local inputs into the expected project paths

By default it is conservative:

- it does not overwrite existing files or folders
- it stops if an existing git repo has local changes

If you explicitly want replacement behavior, run with `-OverwriteExisting`.

## Minimal Adoption Plan

1. Copy the example manifest and rename it for your real environment.
2. Fill in repo URLs, refs, artifact URLs, and local paths.
3. Point each `target_path` at the location the existing build expects.
4. Run the initializer.
5. Run the existing package build.

That gives you one clean setup step before packaging, without forcing a full bundler redesign.
