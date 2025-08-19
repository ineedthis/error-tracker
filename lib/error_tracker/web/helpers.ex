defmodule ErrorTracker.Web.Helpers do
  @moduledoc false

  require Logger

  @doc false
  @spec sanitize_module(binary() | atom() | nil) :: binary()
  def sanitize_module(nil), do: "(nil)"
  def sanitize_module(<<"Elixir.", str::binary>>), do: str
  def sanitize_module(str) when is_binary(str), do: str
  def sanitize_module(atom) when is_atom(atom), do: atom |> Atom.to_string() |> sanitize_module
  def sanitize_module(other) do
    Logger.warning("[ErrorTracker] Unexpected module format: #{inspect(other)}")
    "(unknown)"
  end

  @doc false
  @spec format_datetime(DateTime.t() | nil | term()) :: binary()
  def format_datetime(nil), do: "(no date)"
  def format_datetime(dt = %DateTime{}), do: Calendar.strftime(dt, "%c %Z")
  def format_datetime(other) do
    Logger.warning("[ErrorTracker] Unexpected datetime format: #{inspect(other)}")
    "(invalid date)"
  end
end
