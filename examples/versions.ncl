let { Arrays, .. } = import "../types.ncl" in
{
  # This is merged using Nickel merge strategy,
  # objects are merged based on a priortiy, if the value doesn't exist it is added
  # Arrays can't be merged as of now and it is best to avoid merging them until there is a better way to handle them
  # An option for now is to use Inputs from the Release itself to define different behaviors for objects defined in Arrays
  # e.g. image tag for example defined in an Array of Containers
  opentelemetry-collector.Inputs.version = "0.0.13",
}
