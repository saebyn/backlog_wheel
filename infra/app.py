#!/usr/bin/env python3
import aws_cdk as cdk

from backlog_wheel_stack import BacklogWheelStack


app = cdk.App()

BacklogWheelStack(app, "BacklogWheelPrototypeStack")

app.synth()
