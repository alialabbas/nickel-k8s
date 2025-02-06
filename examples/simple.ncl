let myBundle =
  {
    Manifests = {
      nginx-pod = {
        apiVersion = "v1",
        kind = "Pod",
        metadata = {
          name = "nginx",
          labels = { app = "nginx" }
        },
        spec = {
          containers = [
            {
              name = "nginx",
              image = "nginx:1.14.2",
              ports = [
                {
                  containerPort = 80,
                }
              ]
            },
          ]
        }
      }
    }
  } | (import "../kube.ncl").Release {}
in
myBundle & { k8s_version = "v1.31.0", }
