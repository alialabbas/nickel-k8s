let { Pod, .. } = import "podspec.ncl" in
{
  metadata = {
    name = "valid-name",
    # labels = {
    #   "kubernetse.io/test" = "test",
    # },
    # annotations = {
    #   testnotvali_d = "willfail",
    # },
  },
  spec = {
    containers = [
      {
        name = "custom-name",
        image = "custom-name",
        ports = [{ containerPort = 90 }],
        env = [
          {
            name = "test",
            value = "test",
            # valueFrom = { fieldRef = { fieldPath = '"metadata.name", } },
          },
        ],
        envFrom = [
          {
            configMapRef = { name = "configmap-valid", "optional" = true, },
          }
        ]
      }
    ],
  },
} | Pod
