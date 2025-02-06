# GOAL: Top-Down approach for manifests management based on application configurations
# The idea is to make operators only care initially about how to configure the application they are interested in
# If the application has some dependencies on other systems. This should be resolved automatically unless it was overwritten

# TODO: The goal is to show a top down approach where app config would be used to generate configuration data and would both be kept in sync
# This could be utilized to handle merging and adding things if necessary
# Ugly though, this should be hidden away and only the system should have access to it
# There is useful use cases for this like handling incremenetal pods in a user's module
# basically, the end goal is to drive certain parts from the configs as much as possible
# The goal of the modules is to expose different way to manage an application and abstract and constrain their configuration
# This demo should show how it is hard to make a mistake with nickel when done right since you are developing your concepts internally as well
# Also how minimizing your configuration scope will allow you to test various configuration easily without worrying about any potential template errors
# We want everything to be data driven from Loki's config as much as possible, except the zone awareness most likely need to be constrained with distributed mode
# TODO: Loki's & Co outputs are parsable, should be possible to do it from there
# TODO: could also generate some binaries to do this for end users using Nix if necessary
let schema = {
  version | doc "version of loki to run" | String | default = "3.3.2",
  canary | doc "Canary is a continuous testing tool to ensure loki can ingest logs correctly" | { enabled | Bool | default = false } | default = {},
  configuration
    | doc "Run mode for loki, scalable is a read-write distribution and distributed is the microservices mode"
    | std.enum.TagOrString
    | [| 'single-binary, 'distributed, 'scalable |]
    | default
    = 'scalable,
  # TODO: is there going to be more really to the cache behavior
  # one thing to figure out is how to get the connection urls for various components and pass them around with paramterizing a lot of values
  cache | { enabled | Bool } | optional,
  # TODO: where to get this schema. The one in schema store is shit and doesn't map to the correct version
  # TODO: in an ideal world, this is where the nix integration would be neat and amazing
  # Could easily just yonk some nix expression that would evaluate schema for each specified version or even just let it be a contract that would get the binary for the specified loki version, compiled at best effort without a sha
  # The best we can do now is to parse the output from go or the doc and convert that if possible
  # An interesting side effect of this is ENV Vars expansion. Secrets are usually strings so it shouldn't matter but would be interesting to see when someone wants to use it with Ints and Such
  config | { .. } | default = import "./loki.yaml",
}
in
{
  Inputs = schema,
  ReleaseInputs = {},
  Manifests =
    Inputs.configuration
    |> match {
      'distributed =>
        # TODO: Some interesting things from the loki config
        # Each user could have its own cache instance with its own cache client
        # Meaning, many results
        ((import "./loki/distributor.ncl") Inputs.version)
        & ((import "./loki/common.ncl") Inputs.version ReleaseInputs.namespace Inputs.config)
        & (
          if Inputs.config.ruler.enable_api then
            ((import "./loki/ruler.ncl") Inputs.version)
          else
            {}
        )
        & ((import "./loki/compactor.ncl") Inputs.version)
        & ((import "./loki/ingester.ncl") Inputs.version)
        & ((import "./loki/query-frontend.ncl") Inputs.version)
        & ((import "./loki/querier.ncl") Inputs.version)
        & ((import "./loki/query-scheudler.ncl") Inputs.version)
        & (
          if Inputs.canary.enabled then
            ((import "./loki/canary.ncl") Inputs.version)
          else
            {}
        )
        # TODO: FEATURE ME
        # The interesting part here is
        # - enabling from configuration results & cache
        # - Figuring out a cache sharding strategy to allow either a client per instance or not
        # - This assumes the cache would be created in cluster and won't be using a cloud instance
        # What if a user doesn't want to use the in-cluster cache and they want to provide their own cache configuration... This needs to be possible
        & (
          if Inputs.config.query_range.cache_results then
            ((import "./loki/result-cache.ncl") Inputs.version)
          else
            {}
        )
        & ((import "./loki/chunks-cache.ncl") Inputs.version),
      'scalable =>
        let scalable_mode =
          ((import "./loki/read.ncl") Inputs.version)
          & ((import "./loki/write.ncl") Inputs.version)
          & ((import "./loki/backend.ncl") Inputs.version)
          & (
            if Inputs.config.query_range.cache_results then
              ((import "./loki/result-cache.ncl") Inputs.version)
            else
              {}
          )
          & ((import "./loki/common.ncl") Inputs.version ReleaseInputs.namespace)
        in
        scalable_mode
    },
  k8s_schema = import "../k8s/v1.31.0/swagger.json",
} | (import "../kube.ncl").Release schema
