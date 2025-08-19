defmodule ErrorTracker.Web.Live.Dashboard do
  @moduledoc false

  use ErrorTracker.Web, :live_view

  import Ecto.Query

  alias ErrorTracker.Error
  alias ErrorTracker.Repo
  alias ErrorTracker.Web.Search

  @per_page 10

  require Logger

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    # Initialize all assigns with safe defaults using proper form construction
    # Add extra safety checks to ensure nothing is nil
    default_search =
      try do
        Search.from_params(%{}) || %{}
      rescue
        _ -> %{}
      end

    default_search_form =
      try do
        Search.to_form(%{})
      rescue
        _ -> nil
      end

    socket_with_assigns =
      assign(socket,
        path: %URI{},
        search: default_search || %{},
        page: 1,
        search_form: default_search_form,
        errors: [],
        occurrences: %{},
        total_pages: 1,
        # Add debug flag to check initialization
        _debug_initialized: true
      )

    {:ok, socket_with_assigns}
  end

  @impl Phoenix.LiveView
  def handle_params(params, uri, socket) do
    path = struct(URI, uri |> URI.parse() |> Map.take([:path, :query]))
    search = Search.from_params(params || %{})
    search_form = Search.to_form(params || %{})

    # Ensure all assigns have safe defaults
    socket_with_defaults =
      socket
      |> assign(
        path: path || %URI{},
        search: search || %{},
        page: 1,
        search_form: search_form || Search.to_form(%{}),
        errors: [],
        occurrences: %{},
        total_pages: 1
      )

    {:noreply, paginate_errors(socket_with_defaults)}
  end

  @impl Phoenix.LiveView
  def handle_event("search", params, socket) do
    search = Search.from_params(params["search"] || %{})

    path_w_filters = %URI{socket.assigns.path | query: URI.encode_query(search)}

    {:noreply, push_patch(socket, to: URI.to_string(path_w_filters))}
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
    current_page = socket.assigns.page || 1
    total_pages = socket.assigns.total_pages || 1

    # Only advance if we're not already on the last page
    new_page = if current_page < total_pages, do: current_page + 1, else: current_page

    {:noreply, socket |> assign(page: new_page) |> paginate_errors()}
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
    # Don't change page for empty values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("prev-page", %{"value" => nil}, socket) do
    # Don't change page for nil values
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  def handle_event("prev-page", _params, socket) do
    current_page = socket.assigns.page || 1

    # Only go back if we're not already on the first page
    new_page = if current_page > 1, do: current_page - 1, else: 1

    {:noreply, socket |> assign(page: new_page) |> paginate_errors()}
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
    {:noreply, socket |> assign(page: 1) |> paginate_errors()}
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
    total_pages = socket.assigns.total_pages || 1

    {:noreply, socket |> assign(page: total_pages) |> paginate_errors()}
  end

  @impl Phoenix.LiveView
  def handle_event("resolve", %{"error_id" => id}, socket) do
    error = Repo.get(Error, id)
    {:ok, _resolved} = ErrorTracker.resolve(error)

    {:noreply, paginate_errors(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("unresolve", %{"error_id" => id}, socket) do
    error = Repo.get(Error, id)
    {:ok, _unresolved} = ErrorTracker.unresolve(error)

    {:noreply, paginate_errors(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("mute", %{"error_id" => id}, socket) do
    error = Repo.get(Error, id)
    {:ok, _muted} = ErrorTracker.mute(error)

    {:noreply, paginate_errors(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("unmute", %{"error_id" => id}, socket) do
    error = Repo.get(Error, id)
    {:ok, _unmuted} = ErrorTracker.unmute(error)

    {:noreply, paginate_errors(socket)}
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

  defp paginate_errors(socket) do
    try do
      %{page: page, search: search} = socket.assigns
      # Ensure page is at least 1 before calculating offset
      safe_page = max(1, page || 1)
      offset = (safe_page - 1) * @per_page
      query = filter(Error, search)

      total_errors = Repo.aggregate(query, :count)

      errors =
        Repo.all(
          from(query,
            order_by: [desc: :last_occurrence_at],
            offset: ^offset,
            limit: @per_page
          )
        )

      error_ids = Enum.map(errors, & &1.id)

      occurrences =
        if errors != [] do
          errors
          |> Ecto.assoc(:occurrences)
          |> where([o], o.error_id in ^error_ids)
          |> group_by([o], o.error_id)
          |> select([o], {o.error_id, count(o.id)})
          |> Repo.all()
        else
          []
        end

      total_pages = max(1, (total_errors / @per_page) |> Float.ceil() |> trunc)
      current_page = socket.assigns[:page] || 1

      # Ensure page is within valid bounds
      valid_page = max(1, min(current_page, total_pages))

      assign(socket,
        errors: errors || [],
        occurrences: Map.new(occurrences || []),
        total_pages: total_pages,
        page: valid_page,
        search: socket.assigns[:search] || %{},
        search_form: socket.assigns[:search_form] || Search.to_form(%{})
      )
    rescue
      e ->
        Logger.error("[ErrorTracker Dashboard] Error paginating: #{inspect(e)}")

        assign(socket,
          errors: [],
          occurrences: %{},
          total_pages: 1,
          page: socket.assigns[:page] || 1,
          search: socket.assigns[:search] || %{},
          search_form: socket.assigns[:search_form] || Search.to_form(%{})
        )
    end
  end

  defp filter(query, search) do
    Enum.reduce(search, query, &do_filter/2)
  end

  defp do_filter({:status, status}, query) do
    where(query, [error], error.status == ^status)
  end

  defp do_filter({field, value}, query) do
    # Postgres provides the ILIKE operator which produces a case-insensitive match between two
    # strings. SQLite3 only supports LIKE, which is case-insensitive for ASCII characters.
    Repo.with_adapter(fn
      :postgres -> where(query, [error], ilike(field(error, ^field), ^"%#{value}%"))
      :mysql -> where(query, [error], like(field(error, ^field), ^"%#{value}%"))
      :sqlite -> where(query, [error], like(field(error, ^field), ^"%#{value}%"))
    end)
  end
end
