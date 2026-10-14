# How To

## Use AWS Creds from .env file
```bash
set -a
source .env
set +a
aws sts get-caller-identity
```
- `set -a` exports every variable that `source` assigns, so the `aws` process inherits them