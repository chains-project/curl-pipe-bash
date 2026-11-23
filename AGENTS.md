## Goal

Provide infrastructure to do "curl ... | bash" safely.

Core idea:
- read the internet file (without execution)
- extract a sandboxing policy
- ask the human to validate the policy
- run the "curl ... | bash" in the sandbox with guarantees

