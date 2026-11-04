# Test Resources

This directory contains FHIR resources used for integration testing in GitHub Actions.

`*.json` in this directory must validate without fatal or error issues (`make test`).
Subdirectories hold resources with an expected issue and are checked by their own script:

- `display/observation-wrong-display.json`: LOINC `67162-8` with a wrong display.
  `scripts/test/check-display-mode.sh error` expects one `Invalid display` error (default);
  `check-display-mode.sh warning` expects it as a warning and no errors
  (`DISPLAY_ISSUES_ARE_WARNINGS=true`, #27).
