let { CronJob, .. } = import "deployment.ncl" in
{
  apiVersion = "batch/v1",
  kind = "CronJob",
  metadata = { name = "exporter", },
  spec = {
    concurrencyPolicy = "Forbid",
    jobTemplate = {
      spec = {
        template = {
          spec = {
            containers = [
              {
                image = "exporter",
                imagePullPolicy = "Always",
                name = "exporter",
                resources = {
                  limits = { cpu = 1, memory = "8G", },
                  requests = { cpu = 1, memory = "6G", },
                },
                volumeMounts = [
                  {
                    mountPath = "/work",
                    name = "ssd",
                  }
                ],
              }
            ],
            restartPolicy = "OnFailure",
            volumes = [
              {
                hostPath = { path = "/mnt/disks/ssd0", },
                name = "ssd",
              }
            ],
          },
        },
      },
    },
    schedule = "0 */1 * * *",
  },
} | CronJob
