#!/usr/bin/env python3
import os

import aws_cdk as cdk

from backlog_wheel_stack import BacklogWheelServiceStack, BacklogWheelStatefulStack


app = cdk.App()
account = app.node.try_get_context("account") or os.getenv("CDK_DEFAULT_ACCOUNT")
region = app.node.try_get_context("region") or os.getenv("CDK_DEFAULT_REGION")

env = cdk.Environment(
    account=account,
    region=region,
)

stateful_stack = BacklogWheelStatefulStack(
    app,
    "BacklogWheelStatefulStack",
    env=env,
)

service_stack = BacklogWheelServiceStack(
    app,
    "BacklogWheelServiceStack",
    env=env,
    stateful_stack=stateful_stack,
)
service_stack.add_dependency(stateful_stack)

app.synth()
