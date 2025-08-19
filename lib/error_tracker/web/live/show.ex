defmodule ErrorTracker.Web.Live.Show do
  @moduledoc false
  use ErrorTracker.Web, :live_view

  import Ecto.Query

  alias ErrorTracker.Error
  alias ErrorTracker.Occurrence
  alias ErrorTracker.Repo
  alias ErrorTracker.Web.Search

  @occurrences_to_navigate 50

  @impl Phoenix.LiveView
  def mount(params = %{"id" => id}, _session, socket) do
    error = Repo.get!(Error, id)

    {:ok,
     assign(socket,
       error: error,
       app: Application.fetch_env!(:error_tracker, :otp_app),
       search: Search.from_params(params)
     )}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    occurrence =
      if occurrence_id = params["occurrence_id"] do
        socket.assigns.error
        |> Ecto.assoc(:occurrences)
        |> Repo.get!(occurrence_id)
      else
        socket.assigns.error
        |> Ecto.assoc(:occurrences)
        |> order_by([o], desc: o.id)
        |> limit(1)
        |> Repo.one()
      end

    socket =
      socket
      |> assign(occurrence: occurrence)
      |> load_related_occurrences()

    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("occurrence_navigation", %{"occurrence_id" => ""}, socket) do
    # Handle empty occurrence_id - just return current state
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("occurrence_navigation", %{"occurrence_id" => id}, socket) when is_binary(id) do
    case Integer.parse(id) do
      {parsed_id, ""} ->
        occurrence_path =
          occurrence_path(
            socket,
            %Occurrence{error_id: socket.assigns.error.id, id: parsed_id},
            socket.assigns.search
          )

        {:noreply, push_patch(socket, to: occurrence_path)}

      _ ->
        # Invalid ID format - just return current state
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("occurrence_navigation", %{"occurrence_id" => id}, socket) do
    occurrence_path =
      occurrence_path(
        socket,
        %Occurrence{error_id: socket.assigns.error.id, id: id},
        socket.assigns.search
      )

    {:noreply, push_patch(socket, to: occurrence_path)}
  end

  @impl Phoenix.LiveView
  def handle_event("resolve", _params, socket) do
    {:ok, updated_error} = ErrorTracker.resolve(socket.assigns.error)

    {:noreply, assign(socket, :error, updated_error)}
  end

  @impl Phoenix.LiveView
  def handle_event("unresolve", _params, socket) do
    {:ok, updated_error} = ErrorTracker.unresolve(socket.assigns.error)

    {:noreply, assign(socket, :error, updated_error)}
  end

  @impl Phoenix.LiveView
  def handle_event("mute", _params, socket) do
    {:ok, updated_error} = ErrorTracker.mute(socket.assigns.error)

    {:noreply, assign(socket, :error, updated_error)}
  end

  @impl Phoenix.LiveView
  def handle_event("unmute", _params, socket) do
    {:ok, updated_error} = ErrorTracker.unmute(socket.assigns.error)

    {:noreply, assign(socket, :error, updated_error)}
  end

  # Handle pagination events with empty or invalid values
  @impl Phoenix.LiveView
  def handle_event("next-page", %{"value" => ""}, socket) do
    # Don't change page for empty values - just return current socket
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("next-page", %{"value" => nil}, socket) do
    # Don't change page for nil values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("next-page", _params, socket) do
    # Handle next page event - this might be triggered accidentally
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("previous-page", %{"value" => ""}, socket) do
    # Don't change page for empty values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("previous-page", %{"value" => nil}, socket) do
    # Don't change page for nil values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("prev-page", %{"value" => ""}, socket) do
    # Handle previous page event with empty value - pagination boundary reached
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("prev-page", %{"value" => nil}, socket) do
    # Handle previous page event with nil value - pagination boundary reached
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("prev-page", _params, socket) do
    # Handle previous page event - this might be triggered accidentally
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("first-page", %{"value" => ""}, socket) do
    # Don't change page for empty values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("first-page", %{"value" => nil}, socket) do
    # Don't change page for nil values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("first-page", _params, socket) do
    # Handle first page event
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("last-page", %{"value" => ""}, socket) do
    # Don't change page for empty values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("last-page", %{"value" => nil}, socket) do
    # Don't change page for nil values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("last-page", _params, socket) do
    # Handle last page event
    {:noreply, socket}
  end

  # Catch-all for any unhandled events with empty values
  @impl Phoenix.LiveView
  def handle_event(_event, %{"value" => ""}, socket) do
    # Handle any event with empty value gracefully
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event(_event, %{"value" => nil}, socket) do
    # Handle any event with nil value gracefully
    {:noreply, socket}
  end

  defp load_related_occurrences(socket) do
    current_occurrence = socket.assigns.occurrence
    base_query = Ecto.assoc(socket.assigns.error, :occurrences)

    half_limit = floor(@occurrences_to_navigate / 2)

    previous_occurrences_query = where(base_query, [o], o.id < ^current_occurrence.id)
    next_occurrences_query = where(base_query, [o], o.id > ^current_occurrence.id)
    previous_count = Repo.aggregate(previous_occurrences_query, :count)
    next_count = Repo.aggregate(next_occurrences_query, :count)

    {previous_limit, next_limit} =
      cond do
        previous_count < half_limit and next_count < half_limit ->
          {previous_count, next_count}

        previous_count < half_limit ->
          {previous_count, @occurrences_to_navigate - previous_count - 1}

        next_count < half_limit ->
          {@occurrences_to_navigate - next_count - 1, next_count}

        true ->
          {half_limit, half_limit}
      end

    occurrences =
      [
        related_occurrences(next_occurrences_query, next_limit),
        current_occurrence,
        related_occurrences(previous_occurrences_query, previous_limit)
      ]
      |> List.flatten()
      |> Enum.reverse()

    total_occurrences =
      socket.assigns.error
      |> Ecto.assoc(:occurrences)
      |> Repo.aggregate(:count)

    next_occurrence =
      base_query
      |> where([o], o.id > ^current_occurrence.id)
      |> order_by([o], asc: o.id)
      |> limit(1)
      |> select([:id, :error_id, :inserted_at])
      |> Repo.one()

    prev_occurrence =
      base_query
      |> where([o], o.id < ^current_occurrence.id)
      |> order_by([o], desc: o.id)
      |> limit(1)
      |> select([:id, :error_id, :inserted_at])
      |> Repo.one()

    socket
    |> assign(:occurrences, occurrences)
    |> assign(:total_occurrences, total_occurrences)
    |> assign(:next, next_occurrence)
    |> assign(:prev, prev_occurrence)
  end

  defp related_occurrences(query, num_results) do
    query
    |> order_by([o], desc: o.id)
    |> select([:id, :error_id, :inserted_at])
    |> limit(^num_results)
    |> Repo.all()
  end
end
