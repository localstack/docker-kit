## LocalStack

This sandbox runs LocalStack for AWS, a local emulator of AWS services. Use
it to build, deploy, and test AWS applications. The sandbox has no access to
a real AWS account. Do not try to use one.

### Before you use LocalStack

LocalStack starts when the sandbox boots. The start can take one or two
minutes.

1. Run `lstk status`.
2. If LocalStack is not running, run `lstk start`.
3. If the start fails, read `/tmp/localstack-kit/start.log`.

### Endpoint and credentials

The endpoint is `http://localhost:4566`. These variables are set, so the AWS
CLI and the AWS SDKs send requests to LocalStack:

- `AWS_ENDPOINT_URL=http://localhost:4566`
- `AWS_ACCESS_KEY_ID=test` and `AWS_SECRET_ACCESS_KEY=test`
- `AWS_DEFAULT_REGION=us-east-1`

Use `http://localhost:4566` in application code and tests. Do not use a real
AWS endpoint.

### Tools

- For Terraform, use `tflocal` or `lstk terraform`. It sets the provider
  endpoints for LocalStack.
- For AWS CDK, use `cdklocal` or `lstk cdk`. Run `cdklocal bootstrap` one
  time before the first deploy.
- For AWS SAM, use `samlocal` or `lstk sam`.
- For the AWS CLI, use `aws` or `awslocal`.
- `lstk logs` shows the LocalStack logs. Add `-f` to follow them.
- `lstk reset` removes all resources from LocalStack.
- The `localstack` MCP server has tools to deploy stacks, read logs, analyze
  IAM policies, inject faults, and save or load state.

### State

LocalStack does not keep resources when the sandbox stops. To keep them, save
a snapshot in the workspace, then load it later:

    lstk snapshot save ./localstack.snapshot
    lstk snapshot load ./localstack.snapshot

### Auth token

`LOCALSTACK_AUTH_TOKEN` activates LocalStack. Do not print it, log it, or
write it to a file. Do not put it in code, commits, or test fixtures.
