{
  manifests = {
    secret = {
      apiVersion = "v1",
      data = {
        admin-userss = "YWRtaW4=",
      },
      kind = "Secret",
      metadata.name = "new-secret", # Change this to a secret name that doesn't exist and you should see a faiure
      type = "Opaque",
    },
    secrets = {
      apiVersion = "v1",
      data = {
        admin-userss = "YWRtaW4=",
      },
      kind = "Secret",
      metadata.name = "new-secsdret", # Change this to a secret name that doesn't exist and you should see a faiure
      type = "Opaque",
    },
    secrsdets = {
      apiVersion = "v1",
      data = {
        admin-userss = "YWRtaW4=",
      },
      kind = "Secret",
      metadata.name = "newsdsad-secsdret", # Change this to a secret name that doesn't exist and you should see a faiure
      type = "Opaque",
    },
  },
} | (import "../kube.ncl").Release
