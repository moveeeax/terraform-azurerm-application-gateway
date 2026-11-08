# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.0] - 2026-11-08

### Added

- `probe` input: an optional custom health probe (path, host, protocol, port,
  interval, timeout, unhealthy threshold, status codes, body match) emitted as
  `<name>-probe` and attached to the backend HTTP settings. Defaults to `null`,
  which keeps Azure's default probe.
- `backend_host_name` and `backend_pick_host_name_from_backend_address` inputs
  for the Host header sent to the backend, which a probe that picks its host
  from the backend HTTP settings needs. Default to `null` and `false`.
- Plan-time checks for conflicting host settings on the probe and the backend
  HTTP settings.

## [1.1.0] - 2026-11-05

### Changed

- azurerm bounded to `>= 3.66.0, < 6.0`; CI refreshed and Dependabot added.

### Fixed

- `identity_ids` rejects more than one identity at plan time.

## [1.0.0] - 2026-07-26

Initial release (`v0.1.0` points at the same commit).

[Unreleased]: https://github.com/moveeeax/terraform-azurerm-application-gateway/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/moveeeax/terraform-azurerm-application-gateway/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/moveeeax/terraform-azurerm-application-gateway/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/moveeeax/terraform-azurerm-application-gateway/releases/tag/v1.0.0
