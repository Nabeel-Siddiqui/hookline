defmodule HooklineWeb.EndpointLive.Show do
  @moduledoc """
  One endpoint's dashboard: its receiving URL, its destinations, and the
  events captured on it, live — `Relay.subscribe_to_endpoint/1` means a
  webhook that arrives while this page is open shows up with no reload.
  """

  use HooklineWeb, :live_view

  alias Hookline.Relay

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Relay.get_endpoint(socket.assigns.current_user, id) do
      {:ok, endpoint} ->
        if connected?(socket), do: Relay.subscribe_to_endpoint(endpoint)

        filters = %{}
        events = Relay.list_events(endpoint, filters)

        {:ok,
         socket
         |> assign(:endpoint, endpoint)
         |> assign(:page_title, endpoint.name)
         |> assign(:destinations, Relay.list_destinations(endpoint))
         |> assign(:destination_form, to_form(Relay.create_destination_changeset()))
         |> assign(:signature_form, to_form(Relay.change_endpoint_signature(endpoint)))
         |> assign(:filters, filters)
         |> assign(:filter_form, to_form(filters, as: :filters))
         |> assign(:events_empty?, events == [])
         |> stream(:events, events)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "That endpoint doesn't exist.")
         |> push_navigate(to: ~p"/endpoints")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.header>
      {@endpoint.name}
      <:subtitle>Receiving URL: <code>/in/{@endpoint.token}</code></:subtitle>
      <:actions>
        <.back navigate={~p"/endpoints"}>Back to endpoints</.back>
      </:actions>
    </.header>

    <.header class="mt-10">Destinations</.header>
    <.table id="destinations" rows={@destinations}>
      <:col :let={destination} label="URL">{destination.url}</:col>
      <:col :let={destination} label="Active">{destination.active}</:col>
    </.table>
    <p :if={@destinations == []} class="mt-4 text-sm text-zinc-500">
      No destinations yet — events will be captured but never forwarded until one exists.
    </p>

    <.simple_form
      for={@destination_form}
      id="destination-form"
      phx-submit="add_destination"
      class="mt-4"
    >
      <.input
        field={@destination_form[:url]}
        type="text"
        label="New destination URL"
        placeholder="https://example.com/webhooks"
      />
      <:actions>
        <.button phx-disable-with="Adding...">Add destination</.button>
      </:actions>
    </.simple_form>

    <.header class="mt-10">
      Signature verification
      <:subtitle>
        Optional. Set the header your sender puts its signature in, give the sender
        the secret below, and anything that arrives without a matching signature is
        rejected before it's ever stored.
      </:subtitle>
    </.header>

    <p class="text-sm">
      Signing secret: <code :if={@endpoint.signing_secret}>{@endpoint.signing_secret}</code>
      <span :if={is_nil(@endpoint.signing_secret)} class="text-zinc-500">
        none yet — regenerate to create one
      </span>
      <.button phx-click="regenerate_secret">Regenerate</.button>
    </p>

    <.simple_form
      for={@signature_form}
      id="signature-form"
      phx-submit="update_signature_header"
      class="mt-4"
    >
      <.input
        field={@signature_form[:signature_header]}
        type="text"
        label="Signature header"
        placeholder="x-hub-signature-256"
      />
      <:actions>
        <.button phx-disable-with="Saving...">Save</.button>
      </:actions>
    </.simple_form>

    <p class="mt-2 text-sm text-zinc-500">
      <%= if @endpoint.signature_header do %>
        Verifying every request's <code>{@endpoint.signature_header}</code>
        header against the secret above.
      <% else %>
        Not verifying — any request with the right URL is accepted, same as before.
      <% end %>
    </p>

    <.header class="mt-10">Events</.header>

    <.simple_form for={@filter_form} id="event-filters" phx-change="filter">
      <div class="flex gap-4">
        <.input
          field={@filter_form[:method]}
          type="select"
          label="Method"
          options={[
            {"Any", ""},
            {"GET", "GET"},
            {"POST", "POST"},
            {"PUT", "PUT"},
            {"PATCH", "PATCH"},
            {"DELETE", "DELETE"}
          ]}
        />
        <.input
          field={@filter_form[:status]}
          type="select"
          label="Delivery status"
          options={[
            {"Any", ""},
            {"Delivered", "delivered"},
            {"Failed", "failed"},
            {"No attempts yet", "pending"}
          ]}
        />
        <.input field={@filter_form[:from]} type="date" label="From" />
        <.input field={@filter_form[:to]} type="date" label="To" />
      </div>
    </.simple_form>

    <.table id="events" rows={@streams.events}>
      <:col :let={{_id, event}} label="Received">
        {Calendar.strftime(event.received_at, "%H:%M:%S")}
      </:col>
      <:col :let={{_id, event}} label="Method">{event.method}</:col>
      <:col :let={{_id, event}} label="Body size">{byte_size(event.body)} bytes</:col>
      <:action :let={{_id, event}}>
        <.link navigate={~p"/endpoints/#{@endpoint}/events/#{event}"}>View</.link>
      </:action>
    </.table>
    <p :if={@events_empty? and not filters_active?(@filters)} class="mt-4 text-sm text-zinc-500">
      No events yet. POST anything to the receiving URL above.
    </p>
    <p :if={@events_empty? and filters_active?(@filters)} class="mt-4 text-sm text-zinc-500">
      No events match these filters.
    </p>
    """
  end

  @impl true
  def handle_event("add_destination", %{"destination" => destination_params}, socket) do
    case Relay.create_destination(
           socket.assigns.current_user,
           socket.assigns.endpoint,
           destination_params
         ) do
      {:ok, _destination} ->
        {:noreply,
         socket
         |> assign(:destinations, Relay.list_destinations(socket.assigns.endpoint))
         |> assign(:destination_form, to_form(Relay.create_destination_changeset()))
         |> put_flash(:info, "Destination added")}

      {:error, changeset} ->
        {:noreply, assign(socket, :destination_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("update_signature_header", %{"endpoint" => params}, socket) do
    case Relay.update_endpoint_signature(
           socket.assigns.current_user,
           socket.assigns.endpoint,
           params
         ) do
      {:ok, endpoint} ->
        {:noreply,
         socket
         |> assign(:endpoint, endpoint)
         |> assign(:signature_form, to_form(Relay.change_endpoint_signature(endpoint)))
         |> put_flash(:info, "Signature header updated")}

      {:error, changeset} ->
        {:noreply, assign(socket, :signature_form, to_form(changeset))}
    end
  end

  @impl true
  def handle_event("filter", %{"filters" => filters}, socket) do
    events = Relay.list_events(socket.assigns.endpoint, filters)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:filter_form, to_form(filters, as: :filters))
     |> assign(:events_empty?, events == [])
     |> stream(:events, events, reset: true)}
  end

  @impl true
  def handle_event("regenerate_secret", _params, socket) do
    {:ok, endpoint} =
      Relay.regenerate_endpoint_signing_secret(
        socket.assigns.current_user,
        socket.assigns.endpoint
      )

    {:noreply,
     socket
     |> assign(:endpoint, endpoint)
     |> put_flash(:info, "Signing secret regenerated")}
  end

  # A live-captured event only gets inserted into the visible stream if
  # it matches the current filters — re-running the same list_events/2
  # query is simpler than writing a second, in-memory predicate that
  # would have to stay in sync with the database one.
  @impl true
  def handle_info({:event_captured, event}, socket) do
    endpoint = socket.assigns.endpoint
    filters = socket.assigns.filters

    if event.id in Enum.map(Relay.list_events(endpoint, filters), & &1.id) do
      {:noreply,
       socket
       |> assign(:events_empty?, false)
       |> stream_insert(:events, event, at: 0)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:attempt_recorded, _attempt}, socket), do: {:noreply, socket}

  defp filters_active?(filters) do
    Enum.any?(filters, fn {_key, value} -> value not in [nil, ""] end)
  end
end
