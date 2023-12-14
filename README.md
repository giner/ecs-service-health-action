# ecs-service-health-action
GitHub Action which ensures that ECS Service is healthy. This action checks load balancer health state if attached to the service and container health otherwise.

## Inputs

| Option       | Required | Default | Description          | Notes |
|--------------|----------|---------|----------------------|-------|
| cluster_name | true     |         | ECS Cluster Name     |       |
| service_name | true     |         | ECS Service Name     |       |
| timeout      | false    | 120     | Health Check Timeout |       |

## Usage example

```yaml
on:
  push:
    branches:
      - develop

permissions: {}

jobs:
  checks:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      # - name: Configure AWS Credentials
      #   uses: aws-actions/configure-aws-credentials@v4
      #   with:
      #     ...
      # - name: Deploy ECS Service
      #   ...
      - name: Check ECS Service Health
        uses: giner/ecs-service-health-action@main  # v1.0.0
        with:
          cluster_name: mycluster
          service_name: myservice
          timeout: 300
```

## Example output

Example 1

    INFO: Gathering data for mycluster/myservice
    INFO: loadbalancer_is_attached=true
    INFO: Waiting 300 seconds for the app to become healthy
    .......................
    INFO: mycluster/myservice is healthy!

Example 2

    INFO: Gathering data for mycluster/myservice
    INFO: loadbalancer_is_attached=true
    INFO: Waiting 300 seconds for the app to become healthy
    ..........................................................................
    ERROR: mycluster/myservice is not healthy! The state is unused.
    Error: Process completed with exit code 1.
