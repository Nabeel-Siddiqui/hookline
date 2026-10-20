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

        events = Relay.list_events(endpoint)

        {:ok,
         socket
         |> assign(:endpoint, endpoint)
         |> assign(:page_title, endpoint.name)
         |> assign(:destinations, Relay.list_destinations(endpoint))
         |> assign(:destination_form, to_form(Relay.create_destination_changeset()))
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

    <.header class="mt-10">Events</.header>
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
    <p :if={@events_empty?} class="mt-4 text-sm text-zinc-500">
      No events yet. POST anything to the receiving URL above.
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
  def handle_info({:event_captured, event}, socket) do
    {:noreply,
     socket
     |> assign(:events_empty?, false)
     |> stream_insert(:events, event, at: 0)}
  end

  def handle_info({:attempt_recorded, _attempt}, socket), do: {:noreply, socket}
end
