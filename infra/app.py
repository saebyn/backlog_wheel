#!/usr/bin/env python3
import os

import aws_cdk as cdk

from backlog_wheel_stack import BacklogWheelStack


app = cdk.App()

BacklogWheelStack(
    app,
    "BacklogWheelPrototypeStack",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION"),
    ),
)

app.synth()
