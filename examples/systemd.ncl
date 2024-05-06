let unit = m%"
[Unit]
Description=OpenTelemtry Collector
Documentation=https://github.com/open-telemetry/opentelemetry-collector

[Service]
Type=notify
ExecStart=otelcol --config config.yaml
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always

KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
"%
in
{
  systemd  = unit,
}
