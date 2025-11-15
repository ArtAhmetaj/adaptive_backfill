defmodule DefaultSysHealthCheckers do

  @ram_limit_percentage 80
  @cpu_limit_percentage 80



  def sys_checks() do
    [&check_ram_usage/0, &check_cpu_usage/0]
  end


  def check_ram_usage() do
  total = :erlang.memory(:total)
  system = :erlang.memory(:system)

  used = total - system

  usage_pct = used * 100 / total

  usage_pct > @ram_limit_percentage
  end


  def check_cpu_usage() do

    usage = :cpu_sup.util()

    usage > @cpu_limit_percentage

  end

end

# iex> :erlang.memory()
# %{
#   total: 48730712,
#   processes: 18816208,
#   processes_used: 18813160,
#   system: 29914504,
#   atom: 836425,
#   atom_used: 801707,
#   binary: 3359040,
#   code: 13920781,
#   ets: 1323824
# }
