## ADDED Requirements

### Requirement: Package-managed wrapper delegation
The transparent proxy control implementation SHALL support being invoked by a package-managed wrapper as the low-level engine for nftables and policy-routing setup, cleanup, and dry-run diagnostics.

#### Scenario: Wrapper delegates setup to control script
- **WHEN** `sing-gateway set` resolves a valid effective gateway configuration
- **THEN** it invokes the packaged `tproxy_ctrl.sh set` command with explicit stack, table, route, mark, TProxy port, FakeIP, DNS hijack, and local-proxy bypass options as applicable

#### Scenario: Wrapper delegates cleanup to control script
- **WHEN** `sing-gateway unset` runs during service stop, failure cleanup, disable, or package removal
- **THEN** it invokes the packaged `tproxy_ctrl.sh unset` command with the same managed table, route table, mark, and stack context used for setup where available
- **AND** cleanup tolerates absent managed resources

#### Scenario: Wrapper delegates diagnostics to dry-run
- **WHEN** `sing-gateway print-nft` runs
- **THEN** it invokes the packaged `tproxy_ctrl.sh set --dry-run` path to generate nftables output without mutating host network state
