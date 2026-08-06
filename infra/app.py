#!/usr/bin/env python3
import os

import aws_cdk as cdk

from backlog_wheel_stack import BacklogWheelEc2Stack


app = cdk.App()
account = app.node.try_get_context("account") or os.getenv("CDK_DEFAULT_ACCOUNT")
region = app.node.try_get_context("region") or os.getenv("CDK_DEFAULT_REGION")

env = cdk.Environment(
    account=account,
    region=region,
)

BacklogWheelEc2Stack(
    app,
    "BacklogWheelEc2Stack",
    env=env,
)

app.synth()
