let m = import "gen.ncl" in
m.v1.Pod.from_merge_form
{
  spec = {
    containers = {
      test = {
        env = { deploment = { value = "test", }, },
        image = "test",
      },
    },
  },
}
