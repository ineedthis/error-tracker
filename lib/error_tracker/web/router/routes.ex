defmodule ErrorTracker.Web.Router.Routes do
  @moduledoc false

  alias ErrorTracker.Error
  alias ErrorTracker.Occurrence
  alias Phoenix.LiveView.Socket

  @doc """
  Returns the dashboard path
  """
  def dashboard_path(socket = %Socket{}, params \\ %{}) do
    socket
    |> dashboard_uri(params)
    |> URI.to_string()
  end

  @doc """
  Returns the path to see the details of an error
  """
  def error_path(socket = %Socket{}, %Error{id: id}, params \\ %{}) do
    socket
    |> dashboard_uri(params)
    |> URI.append_path("/#{id}")
    |> URI.to_string()
  end

  @doc """
  Returns the path to see the details of an occurrence
  """
  def occurrence_path(socket = %Socket{}, %Occurrence{id: id, error_id: error_id}, params \\ %{})
      when not is_nil(id) and not is_nil(error_id) do
    socket
    |> dashboard_uri(params)
    |> URI.append_path("/#{error_id}/#{id}")
    |> URI.to_string()
  rescue
    e in ArgumentError ->
      require Logger
      Logger.error("[ErrorTracker] Error generating occurrence path: #{inspect(e)}")
      dashboard_path(socket, params)
  end

  def occurrence_path(socket = %Socket{}, occurrence, params) do
    require Logger

    Logger.warning(
      "[ErrorTracker] Invalid occurrence for path generation: #{inspect(occurrence)}"
    )

    dashboard_path(socket, params)
  end

  defp dashboard_uri(socket = %Socket{}, params) do
    %URI{
      path: socket.private[:dashboard_path],
      query: if(Enum.any?(params), do: URI.encode_query(params))
    }
  end
end
