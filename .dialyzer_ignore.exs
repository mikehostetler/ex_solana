[
  # Suppress no_return warning for all_tenants/0 callback in Repo
  {"lib/jido_hub/repo.ex", :no_return},
  # Suppress unreachable pattern match in legacy admin chart helper
  {"lib/jido_hub_web/live/admin/dashboard/admin_chart_data_helper.ex", :pattern_match_cov},
  # Suppress Ash.get!/3 contract mismatch when using Query struct as first arg
  {"lib/jido_hub_web/live/admin/organization_live/index.ex", :call}
]
