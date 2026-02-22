# scripts

Operational scripts for local development and testing.

Key scripts:
- `run_local_moo.sh`: manage local LambdaMOO docker stack
- `run_proxy.sh`: launch Go proxy
- `run_client.sh`: line client for manual protocol testing
- `test_e2e.sh`: end-to-end smoke test
- `test_cli_smoke.sh`: scripted smoke test for Rust `moo-cli`
- `test_cli_scenario.sh`: scripted scenario-mode smoke test for Rust `moo-cli`
- `test_classifier_parity.sh`: validates shared classifier fixtures and Rust/Swift parity

Subfolders:
- `moo/`: bootstrap assets/scripts for local MOO initialization
- `scenarios/`: scripted `moo-cli` scenario files
- `wslineclient/`: lightweight Go websocket line client used by `run_client.sh`
