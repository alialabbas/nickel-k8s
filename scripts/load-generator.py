#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python3Packages.requests

import requests
import time
import json

from uuid import uuid4


def genTraceId() -> str:
    return str(uuid4()).replace("-", "")


def genSpanId() -> str:
    return str(uuid4()).replace("-", "")[:16]


def logResponse(response: requests.Response, Header: str) -> None:
    print(f"-----------{Header}-----------")
    pretty_json = json.loads(response.text)
    print(json.dumps(pretty_json, indent=2))
    print("\n")

counter = 0

def push():
    global counter
    traceId = genTraceId()
    spanId = genSpanId()
    event = {
        "resourceLogs": [
            {
                "resource": {
                    "attributes": [
                        {"key": "service.name", "value": {"stringValue": "Example.Service"}}
                    ]
                },
                "scopeLogs": [
                    {
                        "scope": {
                            "name": "my.library",
                            "version": "1.0.0",
                            "attributes": [
                                {
                                    "key": "my.scope.attribute",
                                    "value": {"stringValue": "some scope attribute"},
                                }
                            ],
                        },
                        "logRecords": [
                            {
                                "timeUnixNano": str(time.time_ns()),
                                # "observedTimeUnixNano": "1544712660300000000",
                                "severityNumber": 9,
                                "severityText": "Info",
                                "traceId": traceId,
                                "spanId": spanId,
                                "body": {"stringValue": "Live from the CLI: " + str(counter)},
                                "attributes": [
                                    {
                                        "key": "string.attribute",
                                        "value": {"stringValue": "some string"},
                                    },
                                    {
                                        "key": "boolean.attribute",
                                        "value": {"boolValue": True},
                                    },
                                ],
                            }
                        ],
                    }
                ],
            }
        ]
    }

    response = requests.post("http://localhost:4318/v1/logs", json=event)
    logResponse(response, "Logs")

    traces = {
        "resourceSpans": [
            {
                "resource": {
                    "attributes": [
                        {"key": "service.name", "value": {"stringValue": "Example.Service"}}
                    ]
                },
                "scopeSpans": [
                    {
                        "scope": {"name": "cli-generator"},
                        "spans": [
                            {
                                "traceId": traceId,
                                "spanId": spanId,
                                "parentSpanId": "",
                                "name": "cli-trace",
                                "kind": "SPAN_KIND_INTERNAL",
                                "startTimeUnixNano": str(time.time_ns() - 20),
                                "endTimeUnixNano": str(time.time_ns()),
                                "attributes": [
                                    {
                                        "key": "string-value-type",
                                        "value": {"stringValue": "test-trace"},
                                    }
                                ],
                                "status": {},
                            },
                        ],
                    },
                ],
            }
        ]
    }

    response = requests.post("http://localhost:4318/v1/traces", json=traces)
    logResponse(response, "Trace with one span")

    metrics = {
        "resourceMetrics": [
            {
                "resource": {
                    "attributes": [
                        {
                            "key": "resource-attr",
                            "value": {"stringValue": "resource-attr-val-1"},
                        }
                    ]
                },
                "scopeMetrics": [
                    {
                        "scope": {"name": "cli-test"},
                        "metrics": [
                            {
                                "name": "counter-int",
                                "unit": "1",
                                "description": "CLI Counter",
                                "sum": {
                                    "dataPoints": [
                                        {
                                            "attributes": [
                                                {
                                                    "key": "service.name",
                                                    "value": {
                                                        "stringValue": "Example.Service",
                                                    },
                                                }
                                            ],
                                            "exemplars": [
                                                {
                                                    "traceId": traceId,
                                                    "spanId": spanId,
                                                    "time_unix_nano": str(time.time_ns()),
                                                    "as_int": str(counter+23),
                                                },
                                            ],
                                            "startTimeUnixNano": str(time.time_ns()),
                                            "timeUnixNano": str(time.time_ns()),
                                            "asInt": str(counter),
                                        }
                                    ],
                                    "aggregationTemporality": "AGGREGATION_TEMPORALITY_CUMULATIVE",
                                    "isMonotonic": True,
                                },
                            }
                        ],
                    }
                ],
            }
        ]
    }

    response = requests.post("http://localhost:4318/v1/metrics", json=metrics)
    logResponse(response, "Metrics")
    counter = counter + 1

while True:
    push()
    time.sleep(1)
