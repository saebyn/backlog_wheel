#!/usr/bin/env python3
import os

import aws_cdk as cdk

from backlog_wheel_stack import BacklogWheelStack


app = cdk.App()
account = app.node.try_get_context("account") or os.getenv("CDK_DEFAULT_ACCOUNT")
region = app.node.try_get_context("region") or os.getenv("CDK_DEFAULT_REGION")

BacklogWheelStack(
    app,
    "BacklogWheelPrototypeStack",
    env=cdk.Environment(
        account=account,
        region=region,
    ),
)

app.synth()
