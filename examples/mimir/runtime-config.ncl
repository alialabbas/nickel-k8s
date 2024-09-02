# This is a runtime config contract set with the default. While the config allows nulls
# this specifically forsake those nullables since config + nulls doesn't make sense 99% of the time
{
  overrides | { _ | { ingestion_rate | std.number.PosNat } } | default = {},
  multi_kv_config = {
    primary | String | default = "",
    # TODO: need this nullable, also why
    mirror_enabled | Bool | default = false,
  },
  ingester_stream_chunks_when_using_blocks | Bool | default = false,
  ingester_limits = {
    max_ingestion_rate | Number | default = 20000,
    max_series | Number | default = 1500000,
    max_tenants | Number | default = 1000,
    max_inflight_push_requests | Number | default = 30000
  },
  distributor_limits | ingester_limits | default = ingester_limits,
}
