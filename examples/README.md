# OpenTelemetry Example

This is an example for how to setup manifest and add your own Contracts as well to the manifest. The release automatically checks against the known kind, those can also be arbitrary CRDs as well like Prometheus' ServiceMonitor or PrometheusRule.

The biggest advantage from managing an application like OpenTelemetry with Nickel is the ability to transform the ConfigMap Schema into a schema that knows that the config to be injected in the data section is an OpenTelemetry Config. See `./config.ncl`.

This allows the end user or even if you were the one deploying and managing OpenTelemetry to have a type system that knows how to validate the correctness of the loaded config. This config can be fed as part of the nickel program input, or it could be a yaml/json file you maintain in the repo. Or even it can be a various call paths inside nickel program. What matters in the end is that the Contract once established correctly, give you the ability to iterate and confidently say the changes are correctt.

NOTE: The current config implement only implement the global validation logic for OpenTelemetry, this doesn't implement a full config validation based on the components since those are dependent based on the OpenTel configuration. But theoratically those could also be implemented based on your distribution to allow you to full iterate on the config.
