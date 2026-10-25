# Sops

Secrets management with [sops-nix](https://github.com/Mic92/sops-nix).

## Setup

Generate the age key:

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Add the public key to `.sops.yaml` at the repo root:

```bash
cat ~/.config/sops/age/keys.txt | grep "public key" | awk '{print $NF}'
```
